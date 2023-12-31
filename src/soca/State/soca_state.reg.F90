! (C) Copyright 2020-2021 UCAR
!
! This software is licensed under the terms of the Apache Licence Version 2.0
! which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.

!> registry for soca_state_mod::soca_state instances for use in
!! Fortran/C++ interfaces of soca_state_mod_c
module soca_state_reg

use soca_state_mod

implicit none
private

!> Linked list interface - defines registry_t type
#define LISTED_TYPE soca_state
#include "oops/util/linkedList_i.f"

!> Global registry for soca_state instances
type(registry_t), public:: soca_state_registry

! ------------------------------------------------------------------------------
contains
! ------------------------------------------------------------------------------

!> Linked list implementation
#include "oops/util/linkedList_c.f"

end module soca_state_reg