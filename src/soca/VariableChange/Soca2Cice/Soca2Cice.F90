! (C) Copyright 2020-2022 UCAR
!
! This software is licensed under the terms of the Apache Licence Version 2.0
! which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.

!> C++ interface for converting model variables to geovals (mostly identity function)
module soca_soca2cice_mod_c

use iso_c_binding
use kinds, only: kind_real
use duration_mod, only: duration, duration_seconds, assignment(=)
use fckit_configuration_module, only: fckit_configuration

! soca modules
use soca_fields_mod, only: soca_field
use soca_geom_mod_c, only: soca_geom_registry
use soca_geom_mod, only: soca_geom
use soca_state_mod, only: soca_state
use soca_state_reg, only: soca_state_registry
use soca_soca2cice_mod, only: soca_soca2cice

implicit none
private

#define LISTED_TYPE soca_soca2cice

!> Linked list interface - defines registry_t type
#include "oops/util/linkedList_i.f"

!> Global registry for soca_soca2cice_mod::soca_soca2cice
type(registry_t), public :: soca_soca2cice_registry

!-------------------------------------------------------------------------------
contains
!-------------------------------------------------------------------------------

!> Linked list implementation
#include "oops/util/linkedList_c.f"

! ------------------------------------------------------------------------------
!> C++ interface for soca_soca2cice_mod::soca_soca2cice::setup()
subroutine soca_soca2cice_setup_f90(c_key_self, c_conf, c_key_geom) &
  bind(c,name='soca_soca2cice_setup_f90')

  integer(c_int), intent(inout) :: c_key_self   !<
  type(c_ptr),       intent(in) :: c_conf       !< The configuration
  integer(c_int),    intent(in) :: c_key_geom   !< Geometry

  type(soca_soca2cice), pointer :: self
  type(soca_geom), pointer :: geom

  type(fckit_configuration) :: f_conf
  character(len=:), allocatable :: str

  f_conf = fckit_configuration(c_conf)

  call soca_soca2cice_registry%init()
  call soca_soca2cice_registry%add(c_key_self)
  call soca_soca2cice_registry%get(c_key_self, self)
  call soca_geom_registry%get(c_key_geom, geom)

  ! cice geometry
  call f_conf%get_or_die("cice background state.ncat", self%ncat)
  call f_conf%get_or_die("cice background state.ice_lev", self%ice_lev)
  call f_conf%get_or_die("cice background state.sno_lev", self%sno_lev)

  ! seaice edge
  self%seaice_edge = 0.15_kind_real
  if (f_conf%has("seaice edge")) call f_conf%get_or_die("seaice edge", self%seaice_edge)

  ! shuffle switch
  self%shuffle = .true.
  if (f_conf%has("shuffle")) call f_conf%get_or_die("shuffle", self%shuffle)

  ! rescale to prior switch
  self%rescale_prior = .false.
  if (f_conf%has("rescale prior")) then
     self%rescale_prior = .true.
     self%rescale_min_hice = 0.5_kind_real   ! set default min ice thickness above which to rescale
     if (f_conf%has("rescale prior.min hice")) then
        call f_conf%get_or_die("rescale prior.min hice", self%rescale_min_hice)
     end if
     self%rescale_min_hsno = 0.1_kind_real   ! set default min snow thickness above which to rescale
     if (f_conf%has("rescale prior.min hsno")) then
        call f_conf%get_or_die("rescale prior.min hsno", self%rescale_min_hsno)
     end if
  end if

  ! domain
  self%domain = "global"
  if (f_conf%has("domain")) call f_conf%get_or_die("domain", self%domain)

  ! cice input restart
  call f_conf%get_or_die("cice background state.restart", self%rst_filename)

  ! cice input restart
  call f_conf%get_or_die("cice output.restart", self%rst_out_filename)

  call self%setup(geom)

end subroutine soca_soca2cice_setup_f90

!-------------------------------------------------------------------------------
!> C++ interface for the non-linear change of variables

subroutine soca_soca2cice_changevar_f90(c_key_self, c_key_geom, c_key_xin, c_key_xout) &
  bind(c,name='soca_soca2cice_changevar_f90')
  integer(c_int), intent(in) :: c_key_self, c_key_geom, c_key_xin, c_key_xout

  type(soca_soca2cice), pointer :: self
  type(soca_geom),      pointer :: geom
  type(soca_state),     pointer :: xin, xout
  type(soca_field),     pointer :: field

  call soca_soca2cice_registry%get(c_key_self, self)
  call soca_geom_registry%get(c_key_geom, geom)
  call soca_state_registry%get(c_key_xin, xin)
  call soca_state_registry%get(c_key_xout, xout)

  call self%changevar(geom, xin, xout)

end subroutine

!-------------------------------------------------------------------------------

end module
