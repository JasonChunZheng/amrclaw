! :::::::::::::::::::::::::::: FILPATCH :::::::::::::::::::::::::;
!
!  fill the portion of valbig from rows  nrowst
!                             and  cols  ncolst
!  the patch can also be described by the corners (xlp,ybp) by (xrp,ytp).
!  vals are needed at time t, and level level,
!
!  first fill with  values obtainable from the level level
!  grids. if any left unfilled, then enlarge remaining rectangle of
!  unfilled values by 1 (for later linear interp), and recusively
!  obtain the remaining values from  coarser levels.
!
! :::::::::::::::::::::::::::::::::::::::;:::::::::::::::::::::::;
recursive subroutine filrecur(level,num_eqn,valbig,aux,num_aux,t,mx,my,nrowst,ncolst,ilo,ihi,jlo,jhi)

    use amr_module, only: hxposs, hyposs, xlower, ylower, xupper, yupper
    use amr_module, only: outunit, nghost, xperdom, yperdom, spheredom
    use amr_module, only: iregsz, jregsz, intratx, intraty

    implicit none

    ! Input
    integer, intent(in) :: level, num_eqn, num_aux, mx, my, nrowst, ncolst
    integer, intent(in) :: ilo, ihi, jlo, jhi
    real(kind=8), intent(in) :: t

    ! Output
    real(kind=8), intent(in out) :: valbig(num_eqn,mx,my)
    real(kind=8), intent(in out) :: aux(num_aux,mx,my)

    ! Local storage
    integer :: mx_patch, my_patch, isl, isr, jsb, jst, iplo, jplo, iphi, jphi, nrowc, ncolc
    integer :: i_fine, j_fine, i_coarse, j_coarse, n, unset_indices(4)
    integer :: refinement_ratio_x, refinement_ratio_y
    real(kind=8) :: dx_fine, dy_fine, fill_rect(4), dx_coarse, dy_coarse, xlc, ybc, xrc, ytc
    real(kind=8) :: eta1, eta2, valp10, valm10, valc, valp01, valm01, dupc, dumc
    real(kind=8) :: ducc, du, fu, dvpc, dvmc, dvcc, dv, fv, valint
    logical :: set

    integer :: fill_indices(4)

    ! Scratch storage
    !  use stack-based scratch arrays instead of alloc, since dont really
    !  need to save beyond these routines, and to allow dynamic memory resizing
    !
    !     use 1d scratch arrays that are potentially the same size as 
    !     current grid, since may not coarsen.
    !     need to make it 1d instead of 2 and do own indexing, since
    !     when pass it in to subroutines they treat it as having dierent
    !     dimensions than the max size need to allocate here
    
    !--      dimension valcrse((ihi-ilo+2)*(jhi-jlo+2)*num_eqn)  ! NB this is a 1D array 
    !--      dimension auxcrse((ihi-ilo+2)*(jhi-jlo+2)*num_aux)  ! the +2 is to expand on coarse grid to enclose fine
    ! ### turns out you need 3 rows, forget offset of 1 plus one on each side
    real(kind=8) :: valcrse((ihi-ilo+3)*(jhi-jlo+3)*num_eqn)  ! NB this is a 1D array 
    real(kind=8) :: auxcrse((ihi-ilo+3)*(jhi-jlo+3)*num_aux)  ! the +3 is to expand on coarse grid to enclose fine
    integer(kind=1) :: flaguse(ihi-ilo+1,jhi-jlo+1)


    ! We begin by filling values for grids at level level. If all values can be
    ! filled in this way, we return;
    fill_indices = [ilo,ihi,jlo,jhi]
    mx_patch = fill_indices(2) - fill_indices(1) + 1 ! nrowp
    my_patch = fill_indices(4) - fill_indices(3) + 1 ! ncolp

    dx_fine     = hxposs(level)
    dy_fine     = hyposs(level)

    ! Coordinates of edges of patch 
    fill_rect = [xlower + fill_indices(1) * dx_fine, &
                 xlower + (fill_indices(2) + 1) * dx_fine, &
                 ylower + fill_indices(3) * dy_fine, &
                 ylower + (fill_indices(4) + 1) * dy_fine]
!     xlp     = xlower + fill_indices(1) * dx_fine
!     xrp     = xlower + (fill_indices(2) + 1) * dx_fine
!     ybp     = ylower + fill_indices(3) * dy_fine
!     ytp     = ylower + (fill_indices(4) + 1) * dy_fine

    ! Fill in the patch as much as possible using values at this level
    call intfil(valbig,mx,my,t,flaguse,nrowst,ncolst,fill_indices(1), &
                fill_indices(2),fill_indices(3),fill_indices(4),level,num_eqn,num_aux)

    ! Trimbd returns set = true if all of the entries are filled (=1.).
    ! set = false, otherwise. If set = true, then no other levels are
    ! are required to interpolate, and we return.
    !
    ! Note that the used array is filled entirely in intfil, i.e. the
    ! marking done there also takes  into account the points filled by
    ! the boundary conditions. bc2amr will be called later, after all 4
    ! boundary pieces filled.
    call trimbd(flaguse,mx_patch,my_patch,set,unset_indices)
    ! il,ir,jb,jt = unset_indices(4)

    ! If set is .true. then all cells have been set and we can skip to setting
    ! the remaining boundary cells.  If it is .false. we need to interpolate
    ! some values from coarser levels, possibly calling this routine
    ! recursively.
    if (.not.set) then

        ! Error check 
        if (level == 1) then
            write(outunit,*)" error in filrecur - level 1 not set"
            write(outunit,'("start at row: ",i4," col ",i4)') nrowst,ncolst
            print *," error in filrecur - level 1 not set"
            print *," should not need more recursion "
            print *," to set patch boundaries"
            print '("start at row: ",i4," col ",i4)', nrowst,ncolst
            stop
        endif

        ! We begin by initializing the level level arrays, so that we can use
        ! purely recursive formulation for interpolating.
        dx_coarse  = hxposs(level - 1)
        dy_coarse  = hyposs(level - 1)

        isl  = unset_indices(1) + fill_indices(1) - 1
        isr  = unset_indices(2) + fill_indices(1) - 1
        jsb  = unset_indices(3) + fill_indices(3) - 1
        jst  = unset_indices(4) + fill_indices(3) - 1

        ! Coarsened geometry
        refinement_ratio_x = intratx(level - 1)
        refinement_ratio_y = intraty(level - 1)

        ! New patch rectangle (after we have partially filled it in) but in the
        ! coarse patches 
        iplo = (isl - refinement_ratio_x + nghost * refinement_ratio_x) &
                                                / refinement_ratio_x - nghost
        jplo = (jsb - refinement_ratio_y + nghost * refinement_ratio_y) &
                                                / refinement_ratio_y - nghost
        iphi = (isr + refinement_ratio_x) / refinement_ratio_x
        jphi = (jst + refinement_ratio_y) / refinement_ratio_y

        xlc  =  xlower + iplo * dx_coarse
        ybc  =  ylower + jplo * dy_coarse
        xrc  =  xlower + (iphi + 1) * dx_coarse
        ytc  =  ylower + (jphi + 1) * dy_coarse

        ! Coarse grid number of spatial points
        nrowc   =  iphi - iplo + 1
        ncolc   =  jphi - jplo + 1
!         ntot    = nrowc * ncolc * (num_eqn + num_aux)
!        write(*,'(" needed coarse grid size ",2i5," allocated ",2i5)') nrowc,ncolc, fill_indices(2)-fill_indices(1)+2,fill_indices(4)-fill_indices(3)+2
!        write(*,'(" needed coarse grid size ",2i5," allocated ",2i5)') nrowc,ncolc, fill_indices(2)-fill_indices(1)+3,fill_indices(4)-fill_indices(3)+3
        if (nrowc > fill_indices(2)-fill_indices(1)+3 .or. ncolc > fill_indices(4)-fill_indices(3)+3) then
            print *," did not make big enough work space in filrecur "
            print *," need coarse space with nrowc,ncolc ",nrowc,ncolc
            print *," made space for ilo,ihi,jlo,jhi ",fill_indices
            stop
        endif

        ! Set the aux array values for the coarse grid, this could be done 
        ! instead in intfil using possibly already available bathy data from the
        ! grids
        if (num_aux > 0) then
            call setaux(nrowc - 2*nghost,ncolc - 2*nghost,nghost, &
                        nrowc - 2*nghost,ncolc - 2*nghost, &
                        xlc + nghost*dx_coarse,ybc + nghost*dy_coarse, &
                        dx_coarse,dy_coarse,num_aux,auxcrse)
        endif

        ! Fill in the edges of the coarse grid
        if ((xperdom .or. (yperdom .or. spheredom)) .and. sticksout(iplo,iphi,jplo,jphi)) then
            call prefilrecur(level - 1,num_eqn,valcrse,auxcrse,num_aux,t,nrowc,ncolc,1,1,iplo,iphi,jplo,jphi)
        else
            call filrecur(level - 1,num_eqn,valcrse,auxcrse,num_aux,t,nrowc,ncolc,1,1,iplo,iphi,jplo,jphi)
        endif

        do i_fine = 1,mx_patch
            i_coarse = 2 + (i_fine - (isl - fill_indices(1)) - 1) / refinement_ratio_x
            eta1 = (-0.5d0 + real(mod(i_fine - 1, refinement_ratio_x),kind=8)) &
                                / real(refinement_ratio_x,kind=8)

            do j_fine  = 1,my_patch
                j_coarse = 2 + (j_fine - (jsb - fill_indices(3)) - 1) / refinement_ratio_y
                eta2 = (-0.5d0 + real(mod(j_fine - 1, refinement_ratio_y),kind=8)) &
                                    / real(refinement_ratio_y,kind=8)

                if (flaguse(i_fine,j_fine) == 0) then

                    do n=1,num_eqn

                        valp10 = valcrse(ivalc(n,i_coarse + 1,j_coarse))
                        valm10 = valcrse(ivalc(n,i_coarse - 1,j_coarse))
                        valc   = valcrse(ivalc(n,i_coarse    ,j_coarse))
                        valp01 = valcrse(ivalc(n,i_coarse    ,j_coarse + 1))
                        valm01 = valcrse(ivalc(n,i_coarse    ,j_coarse - 1))
        
                        dupc = valp10 - valc
                        dumc = valc   - valm10
                        ducc = valp10 - valm10
                        du   = min(abs(dupc), abs(dumc))
                        du   = min(2.d0 * du, 0.5d0 * abs(ducc))
                        fu = max(0.d0, sign(1.d0, dupc * dumc))
        
                        dvpc = valp01 - valc
                        dvmc = valc   - valm01
                        dvcc = valp01 - valm01
                        dv   = min(abs(dvpc), abs(dvmc))
                        dv   = min(2.d0 * dv, 0.5d0 * abs(dvcc))
                        fv = max(0.d0,sign(1.d0, dvpc * dvmc))

                        valint = valc + eta1 * du * sign(1.d0, ducc) * fu &
                                      + eta2 * dv * sign(1.d0, dvcc) * fv


                        valbig(n,i_fine+nrowst-1,j_fine+ncolst-1) = valint

                    end do

                endif
            end do
        end do
    end if

    !  set bcs, whether or not recursive calls needed. set any part of patch that stuck out
    call bc2amr(valbig,aux,mx,my,num_eqn,num_aux,dx_fine,dy_fine,level,t,fill_rect(1),fill_rect(2), &
                fill_rect(3),fill_rect(4),xlower,ylower,xupper,yupper,xperdom,yperdom,spheredom)

contains

    integer pure function ivalc(n,i,j)
        implicit none
        integer, intent(in) :: n, i, j
        ivalc = n + num_eqn*(i-1)+num_eqn*nrowc*(j-1)
    end function ivalc

    logical pure function sticksout(iplo,iphi,jplo,jphi)
        implicit none
        integer, intent(in) :: iplo, iphi, jplo, jphi
        sticksout = (iplo < 0 .or. jplo < 0 .or. &
                     iphi >= iregsz(level - 1) .or. jphi >= jregsz(level - 1))
    end function sticksout

end subroutine filrecur