! (C) Copyright 2017- UCAR
!
! This software is licensed under the terms of the Apache Licence Version 2.0
! which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.
!

module soca_geom_mod
  use config_mod
  use MOM_grid,                  only : ocean_grid_type
  use MOM_verticalGrid,          only : verticalGrid_type
  use soca_mom6
  use soca_utils
  use kinds
  use fckit_kdtree_module!, only: kdtree,kdtree_create,kdtree_destroy,kdtree_k_nearest_neighbors
  use fckit_mpi_module, only: fckit_mpi_comm
  use mpp_domains_mod, only : mpp_get_compute_domain, mpp_get_data_domain
  use mpp_domains_mod, only : mpp_update_domains
  use kinds
  use fms_mod,         only : get_mosaic_tile_grid, write_data, set_domain, read_data
  use fms_io_mod,      only : fms_io_init, fms_io_exit
  use iso_c_binding

  implicit none

  private
  public :: soca_geom
  public :: geom_infotofile, geom_get_domain_indices

  !> Geometry data structure
  type :: soca_geom
     type(ocean_grid_type)            :: G          !< Ocean/sea-ice horizontal grid
     type(VerticalGrid_type), pointer :: GV         !< Ocean vertical grid
     type(soca_ice_column)            :: ice_column !< Sea-ice geometry
     integer :: nx, ny, nzo
     integer :: nzi, nzs, ncat
     integer :: isc, iec, jsc, jec  !< indices of compute domain
     integer :: isd, ied, jsd, jed  !< indices of data domain
     integer :: iscl, iecl, jscl, jecl  !< indices of local compute domain
     integer :: isdl, iedl, jsdl, jedl  !< indices of local data domain
     real(kind=kind_real), allocatable, dimension(:,:) :: lon, lat  !< horizontal grid type
                                                                   !< 2D array of longitude, latitude
     real(kind=kind_real), allocatable, dimension(:,:) :: mask2d    !< 0 = land 1 = ocean
     real(kind=kind_real), allocatable, dimension(:,:) :: shoremask ! Includes shoreline as ocean point (useful for BUMP)
     integer,              allocatable, dimension(:,:) :: ij        ! index of ocean+shore line in compute grid
     real(kind=kind_real), allocatable, dimension(:,:) :: cell_area
     real(kind=kind_real), allocatable, dimension(:,:) :: rossby_radius
     logical :: save_local_domain ! If true, save the local geometry for each pe.
   contains
     procedure :: init => geom_init
     procedure :: end => geom_end
     !procedure :: shortcuts => geom_allocate
     procedure :: clone => geom_clone
     procedure :: print => geom_print
     procedure :: get_rossby_radius => geom_rossby_radius
     procedure :: validindex => geom_validindex
     procedure :: thickness2depth => geom_thickness2depth
     procedure :: struct2unstruct => geom_struct2unstruct
     procedure :: unstruct2struct => geom_unstruct2struct
     procedure :: infotofile => geom_infotofile
  end type soca_geom

  ! ------------------------------------------------------------------------------
contains
  ! ------------------------------------------------------------------------------

  ! ------------------------------------------------------------------------------
  !> Initialize and allocate memory for geometry object
  subroutine geom_init(self, c_conf)
    class(soca_geom), intent(out) :: self
    type(c_ptr),      intent( in) :: c_conf

    integer :: isave

    call soca_geom_init(self%G, self%GV, self%ice_column, c_conf)

    ! Set output option for local geometry
    self%save_local_domain = .false.
    if (config_element_exists(c_conf,"save_local_domain")) then
       isave = config_get_int(c_conf,"read_from_file")
       if (isave.eq.1 ) self%save_local_domain = .true.
    endif

    call geom_allocate(self)

  end subroutine geom_init

  ! ------------------------------------------------------------------------------
  !> Geometry destructor
  subroutine geom_end(self)
    class(soca_geom), intent(out)  :: self

    if (allocated(self%lon)) deallocate(self%lon)
    if (allocated(self%lat)) deallocate(self%lat)
    if (allocated(self%mask2d)) deallocate(self%mask2d)
    if (allocated(self%shoremask)) deallocate(self%shoremask)
    if (allocated(self%cell_area)) deallocate(self%cell_area)
    if (allocated(self%rossby_radius)) deallocate(self%rossby_radius)

    self%nx = 0
    self%ny = 0

    self%G%isc = 0
    self%G%iec = 0
    self%G%jsc = 0
    self%G%jec = 0
    self%G%ke = 0

    if (allocated(self%G%GeoLonT)) deallocate(self%G%GeoLonT)
    if (allocated(self%G%GeoLatT)) deallocate(self%G%GeoLatT)
    if (allocated(self%G%mask2dT)) deallocate(self%G%mask2dT)
    if (allocated(self%G%areaT)) deallocate(self%G%areaT)

    nullify(self%GV)

  end subroutine geom_end

  ! ------------------------------------------------------------------------------
  !> Clone, self = other
  subroutine geom_clone(self, other)
    class(soca_geom), intent( in) :: self
    class(soca_geom), intent(out) :: other

    other%G = self%G
    !other%GV = self%GV  ! CAREFUL, GV is a pointer!!!
    other%ice_column = self%ice_column
    call geom_allocate(other)

    other%rossby_radius = self%rossby_radius

  end subroutine geom_clone

  ! ------------------------------------------------------------------------------
  !> Allocate memory and point to mom6 data structure
  subroutine geom_allocate(self)
    class(soca_geom), intent(inout) :: self

    integer :: nxny(2), nx, ny
    integer :: nzo, nzi, nzs
    integer :: isd, ied, jsd, jed

    ! Get indices of data and compute domain
    call geom_get_domain_indices(self, "compute", self%isc, self%iec, self%jsc, self%jec)
    call geom_get_domain_indices(self, "data", isd, ied, jsd, jed)
    self%isd = isd ;  self%ied = ied ; self%jsd = jsd; self%jed = jed

    call geom_get_domain_indices(self, "compute", self%iscl, self%iecl, self%jscl, self%jecl, local=.true.)
    call geom_get_domain_indices(self, "data", self%isdl, self%iedl, self%jsdl, self%jedl, local=.true.)

    nzo = self%G%ke

    ! Extract geometry of interest from model's data structure.
    ! Common to ocean & sea-ice
    ! No halo grid size
    ! TODO: Probably obsolete, remove
    nxny = shape( self%G%GeoLonT )
    nx = nxny(1)
    ny = nxny(2)
    self%nx = nx
    self%ny = ny

    ! Allocate arrays on compute domain
    allocate(self%lon(isd:ied,jsd:jed))
    allocate(self%lat(isd:ied,jsd:jed))
    allocate(self%mask2d(isd:ied,jsd:jed))
    allocate(self%cell_area(isd:ied,jsd:jed))
    allocate(self%rossby_radius(isd:ied,jsd:jed))

    self%lon = self%G%GeoLonT
    self%lat = self%G%GeoLatT
    self%mask2d = self%G%mask2dT
    self%cell_area  = self%G%areaT

    ! Fill halo
    call mpp_update_domains(self%lon, self%G%Domain%mpp_domain)
    call mpp_update_domains(self%lat, self%G%Domain%mpp_domain)
    call mpp_update_domains(self%mask2d, self%G%Domain%mpp_domain)
    call mpp_update_domains(self%cell_area, self%G%Domain%mpp_domain)

    ! Ocean levels
    self%nzo = self%G%ke

    ! Sea-ice categories and levels
    self%ncat = self%ice_column%ncat
    self%nzi = self%ice_column%nzi
    self%nzs = self%ice_column%nzs

  end subroutine geom_allocate

  ! ------------------------------------------------------------------------------
  !> Print geometry info to std output
  subroutine geom_print(self)
    class(soca_geom), intent(in) :: self

    print *, 'nx=', self%nx
    print *, 'ny=', self%ny

  end subroutine geom_print

  ! ------------------------------------------------------------------------------
  !> Read and store Rossby Radius of deformation
  !> TODO: Move out of geometry, use bilinear interp instead of nearest neighbor
  subroutine geom_rossby_radius(self)
    class(soca_geom), intent(inout) :: self

    integer :: unit, i, j, n
    real(kind=kind_real) :: dum
    real(kind=kind_real), allocatable :: lon(:),lat(:),rr(:)
    type(kdtree) :: kd
    integer :: isc, iec, jsc, jec
    integer :: index(1), nn, io
    character(len=256) :: geom_output_file = "geom_output.nc"

    unit = 20
    open(unit=unit,file="rossrad.dat",status="old",action="read")
    n = 0
    do
       read(unit,*,iostat=io)
       if (io/=0) exit
       n = n+1
    end do
    rewind(unit)
    allocate(lon(n),lat(n),rr(n))
    do i = 1, n
       read(unit,*) lat(i),lon(i),dum,rr(i)
    end do
    close(unit)

    !--- Initialize kd-tree
    kd = kdtree_create(n, lon, lat)

    isc = self%isc ;  iec = self%iec ; jsc = self%jsc ; jec = self%jec

    !--- Find nearest neighbor
    nn=1 ! Num neighbors
    do i = isc, iec
       do j = jsc, jec
          call kdtree_k_nearest_neighbors(kd,self%lon(i,j),self%lat(i,j),1,index)
          self%rossby_radius(i,j)=rr(index(1))*1e3
       end do
    end do

    ! Release memory
    call kdtree_destroy(kd)

  end subroutine geom_rossby_radius

  ! ------------------------------------------------------------------------------
  !> Setup array of "valid index" to inline and pack structured geometry to
  !> unstructured geometry
  subroutine geom_validindex(self)
    ! Ignores inland mask grid points and
    ! select wet gridpoints and shoreline mask
    class(soca_geom), intent(inout) :: self
    integer :: i, j, ns, cnt
    integer :: isc, iec, jsc, jec
    real(kind=kind_real) :: shoretest

    ! Indices for compute domain (no halo)
    isc = self%isc ; iec = self%iec ; jsc = self%jsc ; jec = self%jec

    ! Allocate shoremask
    allocate(self%shoremask(isc:iec,jsc:jec))

    ! Extend mask 2 grid point inland TODO:NEED HALO FOR MASK!!!
    self%shoremask = self%mask2d
    do i = isc, iec
       do j = jsc, jec
          self%shoremask(i,j) = self%mask2d(i,j)
       end do
    end do

    ! Get number of valid points
    ns = int(sum(self%shoremask(isc:iec,jsc:jec)))
    allocate(self%ij(2,ns))

!!$    ! Save shoreline + ocean grid point
!!$    cnt = 1
!!$    do i = isc, iec
!!$       do j = jsc, jec
!!$          if (shoretest.gt.0.0d0) then
!!$             self%ij(1, cnt) = i
!!$             self%ij(2, cnt) = j
!!$             cnt = cnt + 1
!!$          end if
!!$       end do
!!$    end do

  end subroutine geom_validindex

  ! ------------------------------------------------------------------------------
  !> Write geometry info to file
  subroutine geom_infotofile(self)
    class(soca_geom), intent(in) :: self

    character(len=256) :: geom_output_file = "geom_output.nc"
    character(len=256) :: geom_output_pe
    integer :: pe
    character(len=8) :: fmt = '(I5.5)'
    character(len=1024) :: strpe
    integer :: ns
    type(fckit_mpi_comm) :: f_comm

    ! Setup Communicator
    f_comm = fckit_mpi_comm()

    call fms_io_init()
    ! Save global domain
    call write_data( geom_output_file, "lon", self%lon, self%G%Domain%mpp_domain)
    call write_data( geom_output_file, "lat", self%lat, self%G%Domain%mpp_domain)
    call write_data( geom_output_file, "area", self%cell_area, self%G%Domain%mpp_domain)
    call write_data( geom_output_file, "rossby_radius", self%rossby_radius, self%G%Domain%mpp_domain)
    call write_data( geom_output_file, "mask2d", self%mask2d, self%G%Domain%mpp_domain)
    call fms_io_exit()

    if (self%save_local_domain) then
       ! Save local compute grid
       pe = f_comm%rank()

       write (strpe,fmt) pe
       geom_output_pe='geom_output_'//trim(strpe)//'.nc'

       ns = (self%iec - self%isc + 1) * (self%jec - self%jsc + 1 )
       call write2pe(reshape(self%shoremask,(/ns/)),'shoremask',geom_output_pe,.false.)
       call write2pe(reshape(self%mask2d,(/ns/)),'mask',geom_output_pe,.true.)
       call write2pe(reshape(self%lon,(/ns/)),'lon',geom_output_pe,.true.)
       call write2pe(reshape(self%lat,(/ns/)),'lat',geom_output_pe,.true.)
    end if

  end subroutine geom_infotofile

  ! ------------------------------------------------------------------------------
  !> Get indices for compute or data domain
  subroutine geom_get_domain_indices(self, domain_type, is, ie, js, je, local)
    class(soca_geom), intent(in) :: self
    character(len=*),       intent(in) :: domain_type
    integer,               intent(out) :: is, ie, js, je
    logical,      optional, intent(in) :: local

    integer :: isc, iec, jsc, jec
    integer :: isd, ied, jsd, jed

    call mpp_get_compute_domain(self%G%Domain%mpp_domain,isc,iec,jsc,jec)
    call mpp_get_data_domain(self%G%Domain%mpp_domain,isd,ied,jsd,jed)
    if (present(local)) then
       isc = isc - (isd-1) ; iec = iec - (isd-1) ; ied = ied - (isd-1) ; isd = 1
       jsc = jsc - (jsd-1) ; jec = jec - (jsd-1) ; jed = jed - (jsd-1) ; jsd = 1
    end if

    select case (trim(domain_type))
    case ("compute")
       is = isc; ie = iec; js = jsc; je = jec;
    case ("data")
       is = isd; ie = ied; js = jsd; je = jed;

    end select

  end subroutine geom_get_domain_indices

  ! ------------------------------------------------------------------------------
  !> Get layer depth from layer thicknesses
  subroutine geom_thickness2depth(self, h, z)
    class(soca_geom),     intent(in   ) :: self
    real(kind=kind_real), intent(in   ) :: h(:,:,:) ! Layer thickness
    real(kind=kind_real), intent(inout) :: z(:,:,:) ! Mid-layer depth

    integer :: is, ie, js, je, i, j, k

    ! Should check shape of z
    is = lbound(h,dim=1)
    ie = ubound(h,dim=1)
    js = lbound(h,dim=2)
    je = ubound(h,dim=2)

    !allocate(z(is:ie, js:je, self%nzo))

    do i = is, ie
       do j = js, je
          do k = 1, self%nzo
             if (k.eq.1) then
                z(i,j,k) = 0.5_kind_real*h(i,j,k)
             else
                z(i,j,k) = sum(h(i,j,1:k-1))+0.5_kind_real*h(i,j,k)
             end if
          end do
       end do
    end do
  end subroutine geom_thickness2depth

  ! ------------------------------------------------------------------------------

  subroutine geom_struct2unstruct(self, dx_struct, dx_unstruct)
    class(soca_geom),                  intent(in ) :: self
    real(kind=kind_real),              intent(in ) :: dx_struct(:,:)
    real(kind=kind_real), allocatable, intent(out) :: dx_unstruct(:,:,:,:)

    integer :: nc0a

    nc0a = (self%iecl - self%iscl + 1) * (self%jecl - self%jscl + 1 )
    allocate(dx_unstruct(nc0a,1,1,1))
    dx_unstruct = &
    &  reshape(dx_struct(self%iscl:self%iecl, self%jscl:self%jecl), (/nc0a,1,1,1/))

  end subroutine geom_struct2unstruct

  ! ------------------------------------------------------------------------------

  subroutine geom_unstruct2struct(self, dx_struct, dx_unstruct)
    class(soca_geom),                  intent(in   ) :: self
    real(kind=kind_real),              intent(inout) :: dx_struct(:,:)
    real(kind=kind_real), allocatable, intent(inout) :: dx_unstruct(:,:,:,:)

    dx_struct(self%iscl:self%iecl, self%jscl:self%jecl) = &
    & reshape(dx_unstruct, (/size(dx_struct(self%iscl:self%iecl, self%jscl:self%jecl),1), &
    &                        size(dx_struct(self%iscl:self%iecl, self%jscl:self%jecl),2)/))

    deallocate(dx_unstruct)

  end subroutine geom_unstruct2struct

  ! ------------------------------------------------------------------------------

end module soca_geom_mod