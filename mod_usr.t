module mod_usr

  use mod_mhd

  implicit none

  double precision :: T_cl, T_w, v_w, sig_w, sig_cl
  double precision :: r_cl, rho_cl, rho_w
  double precision :: d_box, T_fl, M0, M
  double precision :: B0uG, B0
  integer          :: Bdir

contains

  ! read parameters from parfile
  subroutine usr_params_read(files)
      character(len=*), intent(in) :: files(:)
      integer                      :: n

      namelist /usr_list/ rho_cl, rho_w, d_box, T_fl, T_cl, M, B0uG, Bdir, &
         sig_w, sig_cl, r_cl

      rho_cl = 1.0d0
      rho_w  = 1.0d-2
      d_box  = 65.0d0
      T_fl   = 10.0d0
      T_cl   = 1.0d0
      M      = 1.9891d38
      B0uG   = 0.0d0    ! initial field strength in microGauss
      Bdir   = 1        ! 1 = aligned with flow (b1), 2 = normal to flow (b2)
      sig_w  = -1.0d0   ! <0: default in initglobaldata_usr
      sig_cl = -1.0d0
      r_cl   = -1.0d0

      do n = 1, size(files)
         open(unitpar, file=trim(files(n)), status="old")
         read(unitpar, usr_list, end=111)
  111    close(unitpar)
      end do

    end subroutine usr_params_read

  subroutine usr_init()

    call usr_params_read(par_files)
    call set_coordinate_system("Cartesian_3D")

    usr_set_parameters         => initglobaldata_usr
    usr_init_one_grid          => initonegrid_usr
    usr_init_vector_potential  => init_vector_potential_usr
    usr_special_bc             => specialbound_usr
    usr_aux_output     => extra_var_output
    usr_add_aux_names  => extra_var_names_output
    usr_source         => special_source
    usr_refine_grid     => specialrefine_grid

    unit_length        = 3.086d21
    unit_numberdensity = 1.d1
    unit_temperature   = 1.d6

    call mhd_activate()

  end subroutine usr_init


  subroutine initglobaldata_usr

    T_w    = 1.0d2
    v_w    = 2.0d7 / unit_velocity
    if (r_cl   < 0.0d0) r_cl   = 0.5d0
    if (sig_w  < 0.0d0) sig_w  = 5.0d6 / unit_velocity
    if (sig_cl < 0.0d0) sig_cl = 3.0d6 / unit_velocity

    B0     = B0uG * 1.0d-6 / unit_magneticfield

    M0     = M / unit_mass

    print*, "unit_time = ", unit_time, " s"
    print*, "unit_magneticfield = ", unit_magneticfield, " G"
    print*, "B0 = ", B0uG, " uG = ", B0, " code units"
  end subroutine initglobaldata_usr


  subroutine initonegrid_usr(ixI^L, ixO^L, w, x)

    use mod_global_parameters

    integer, intent(in)             :: ixI^L, ixO^L
    double precision, intent(in)    :: x(ixI^S,1:ndim)
    double precision, intent(inout) :: w(ixI^S,1:nw)

    double precision :: rcloud(ixI^S)
    double precision :: g1(ixI^S), g2(ixI^S)
    double precision :: g3(ixI^S), g4(ixI^S)
    double precision :: g5(ixI^S), g6(ixI^S)

    double precision :: x1, x2, x3
    double precision :: p_cl, p_w

    ! setup medium
    call randgauss(ixI^L, g1, g2)
    call randgauss(ixI^L, g3, g4)
    {^IFTHREED
    call randgauss(ixI^L, g5, g6)
    }

    p_w = rho_w * T_w

    w(ixO^S,rho_)   = rho_w
    w(ixO^S,mom(1)) = v_w + g1(ixO^S) * sig_w
    w(ixO^S,mom(2)) = g2(ixO^S) * sig_w
    {^IFTHREED
    w(ixO^S,mom(3)) = g5(ixO^S) * sig_w
    }
    w(ixO^S,p_) = p_w
    w(ixO^S,tracer(1)) = 0.0d0
    if (stagger_grid) then
      ! CT: set face-centered B from the vector potential (div-free by
      ! construction); cell-centered w(mag) is derived from the faces
      call b_from_vector_potential(ixGs^LL, ixI^L, ixO^L, block%ws, x)
      call mhd_face_to_center(ixO^L, block)
    else
      w(ixO^S,mag(:)) = 0.0d0
      w(ixO^S,mag(Bdir)) = B0
    end if

    ! setup cloud
    x1 = d_box / 2.0d0
    x2 = d_box / 2.0d0
    x3 = d_box / 2.0d0

    rcloud(ixO^S) = (^D&(x(ixO^S,^D)-x^D)**2|+)
    p_cl = rho_cl * T_cl
    where (sqrt(rcloud(ixO^S)) <= r_cl)
      w(ixO^S,rho_)   = rho_cl
      w(ixO^S,mom(1)) = g3(ixO^S) * sig_cl
      w(ixO^S,mom(2)) = g4(ixO^S) * sig_cl
      {^IFTHREED
      w(ixO^S,mom(3)) = g6(ixO^S) * sig_cl
      }
      w(ixO^S,p_) = p_cl
      w(ixO^S,tracer(1)) = 1.0d0
    end where

    call mhd_to_conserved(ixI^L, ixO^L, w, x)

  end subroutine initonegrid_usr

  ! vector potential for the uniform initial field, used only when
  ! typedivbfix='ct' (staggered B): A3=B0*y gives B=B0 x-hat,
  ! A3=-B0*x gives B=B0 y-hat, A2=B0*x gives B=B0 z-hat
  subroutine init_vector_potential_usr(ixI^L, ixC^L, xC, A, idir)
    use mod_global_parameters

    integer, intent(in)           :: ixI^L, ixC^L, idir
    double precision, intent(in)  :: xC(ixI^S,1:ndim)
    double precision, intent(out) :: A(ixI^S)

    A = 0.0d0
    if (Bdir==1 .and. idir==3) A(ixC^S) =  B0 * xC(ixC^S,2)
    if (Bdir==2 .and. idir==3) A(ixC^S) = -B0 * xC(ixC^S,1)
    if (Bdir==3 .and. idir==2) A(ixC^S) =  B0 * xC(ixC^S,1)

  end subroutine init_vector_potential_usr

  !Box-Muller
  subroutine randgauss(ixI^L, x1, x2)

    use mod_global_parameters

    integer, intent(in) :: ixI^L

    double precision, intent(inout) :: x1(ixI^S)
    double precision, intent(inout) :: x2(ixI^S)

    double precision :: a(ixI^S), b(ixI^S)

    call random_number(a)
    call random_number(b)
    x1 = sqrt(-2.d0 * log(a)) * cos(2.d0 * acos(-1.d0) * b)
    x2 = sqrt(-2.d0 * log(a)) * sin(2.d0 * acos(-1.d0) * b)

  end subroutine randgauss


  subroutine specialbound_usr(qdt, qt, ixI^L, ixO^L, iB, w, x)

    integer, intent(in)             :: ixI^L, ixO^L, iB
    double precision, intent(in)    :: qdt, qt
    double precision, intent(in)    :: x(ixI^S,1:ndim)
    double precision, intent(inout) :: w(ixI^S,1:nw)

    double precision :: p_w

    select case(iB)

    case(1)
      p_w = rho_w * T_w

      w(ixO^S,rho_)   = rho_w
      w(ixO^S,mom(1)) = v_w
      w(ixO^S,mom(2)) = 0.0d0
      {^IFTHREED
      w(ixO^S,mom(3)) = 0.0d0
      }
      w(ixO^S,p_) = p_w
      w(ixO^S,mag(:)) = 0.0d0
      w(ixO^S,mag(Bdir)) = B0
      w(ixO^S,tracer(1)) = 0.0d0

      call mhd_to_conserved(ixI^L, ixO^L, w, x)
    case default
      call mpistop('boundary not defined')
    end select

  end subroutine specialbound_usr


  subroutine extra_var_output(ixI^L, ixO^L, w, x, normconv)

    use mod_physics
    use mod_global_parameters
    use mod_radiative_cooling

    integer, intent(in)          :: ixI^L, ixO^L
    double precision, intent(in) :: x(ixI^S,1:ndim)

    double precision :: w(ixI^S,nw+nwauxio)
    double precision :: wlocal(ixI^S,1:nw)
    double precision :: normconv(0:nw+nwauxio)
    double precision :: pth(ixI^S)

    wlocal(ixI^S,1:nw) = w(ixI^S,1:nw)

    call phys_get_pthermal(wlocal, x, ixI^L, ixO^L, pth)

    w(ixO^S,nw+1) = pth(ixO^S) / w(ixO^S,rho_)

  end subroutine extra_var_output


  subroutine extra_var_names_output(varnames)

    character(len=*) :: varnames
    varnames = "T"

  end subroutine extra_var_names_output

  subroutine special_source(qdt,ixI^L,ixO^L,iw^LIM,qtC,wCT,qt,w,x)
    use mod_global_parameters
    integer, intent(in) :: ixI^L, ixO^L, iw^LIM
    double precision, intent(in) :: qdt, qtC, qt
    double precision, intent(in) :: x(ixI^S,1:ndim), wCT(ixI^S,1:nw)
    double precision, intent(inout) :: w(ixI^S,1:nw)
    double precision :: f(ixI^S)
    double precision :: bQgrid(ixI^S)
    double precision, parameter :: ftresh = 1.0d-3

    f(ixO^S) = wCT(ixO^S,tracer(1)) / wCT(ixO^S,rho_)

    call getbQ(bQgrid,ixI^L,ixO^L,qtC,wCT,x)

    where (f(ixO^S) <= ftresh)
      w(ixO^S,e_) = w(ixO^S,e_) + qdt*bQgrid(ixO^S)
    end where

  end subroutine special_source

  ! copied from Jordi!!!
  subroutine getbQ(bQgrid,ixI^L,ixO^L,qt,w,x)
    use mod_global_parameters
    use mod_radiative_cooling
    integer, intent(in)           :: ixI^L, ixO^L
    double precision, intent(in)  :: qt, x(ixI^S,1:ndim), w(ixI^S,1:nw)
    double precision, intent(out) :: bQgrid(ixI^S)

    double precision :: wbg(ixI^S,1:nw)

    ! uniform background state (primitive), then convert
    wbg = 0.0d0
    wbg(ixI^S,rho_) = rho_w
    wbg(ixI^S,p_)   = rho_w * T_w
    call mhd_to_conserved(ixI^L, ixI^L, wbg, x)

    ! cooling rate of that state = heating needed for equilibrium
    call getvar_cooling(ixI^L, ixO^L, wbg, x, bQgrid, rc_fl)
  end subroutine getbQ

  !special refinement since the dispersion seemed to trigger the default one
  subroutine specialrefine_grid(igrid,level,ixG^L,ix^L,qt,w,x,refine,coarsen)
    ! Enforce additional refinement or coarsening
    ! One can use the coordinate info in x and/or time qt=t_n and w(t_n) values w.
    ! you must set consistent values for integers refine/coarsen:
    ! refine = -1 enforce to not refine
    ! refine =  0 doesn't enforce anything
    ! refine =  1 enforce refinement
    ! coarsen = -1 enforce to not coarsen
    ! coarsen =  0 doesn't enforce anything
    ! coarsen =  1 enforce coarsen
    integer, intent(in) :: igrid, level, ixG^L, ix^L
    double precision, intent(in) :: qt, w(ixG^S,1:nw), x(ixG^S,1:ndim)
    integer, intent(inout) :: refine, coarsen

    double precision:: f(ixG^S), rad(ixG^S)
    double precision:: ftresh = 1.0d-3
    double precision:: x1, x2, x3

    x1 = d_box / 2.0d0
    x2 = d_box / 2.0d0
    x3 = d_box / 2.0d0

    f(ix^S) = w(ix^S,tracer(1)) / w(ix^S,rho_)
    rad(ix^S) = dsqrt(^D&(x(ix^S,^D)-x^D)**2|+)

    if (qt < 0.1d0 .and. any(rad(ix^S) <= r_cl + 2.0d0*dx(1,level))) then
      refine  = 1
      coarsen = -1
    else if( any(f(ix^S) > ftresh) ) then
      coarsen = -1
      refine  = 1
    else
      coarsen = 1
      refine  = -1
    endif

  end subroutine specialrefine_grid

end module mod_usr
