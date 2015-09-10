c
c  -----------------------------------------------------------
c
      subroutine gfixup(lbase, lfnew, nvar, naux)
c
      use amr_module
      implicit double precision (a-h,o-z)

      !for setaux timing
      integer :: clock_start, clock_finish, clock_rate
      real(kind=8) :: cpu_start, cpu_finish

c
c ::::::::::::::::::::::::: GFIXUP ::::::::::::::::::::::::::::::::;
c        interpolate initial values for the newly created grids.
c        the start of each level is located in newstl array.
c        since only levels greater than lbase were examined, start
c        looking there.
c :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::;
c
c   reclaim old storage (store2 position) and list space ffluxptr and
c   cfluxptr before allocating new storage. remember, finest level grids
c  (if level = mxnest so that error never estimated) don't have
c  2 copies of solution values at old and new times.
c
c
      call putsp(lbase,lbase,nvar,naux)
      level = lbase + 1
 1    if (level .gt. lfine) go to 4
      call putsp(lbase,level,nvar,naux)
          mptr = lstart(level)
 2        if (mptr .eq. 0) go to 3
              nx = node(ndihi,mptr) - node(ndilo,mptr) + 1
              ny = node(ndjhi,mptr) - node(ndjlo,mptr) + 1
              nz = node(ndkhi,mptr) - node(ndklo,mptr) + 1
              mitot = nx + 2*nghost
              mjtot = ny + 2*nghost
              mktot = nz + 2*nghost
              nwords        = mitot*mjtot*mktot*nvar
              if (level .lt. mxnest) 
     .           call reclam(node(store2, mptr), nwords)
              node(store2, mptr) = 0
              mptr          = node(levelptr, mptr)
          go to 2
 3        level   = level + 1
          go to 1
c
 4    lcheck = lbase + 1
 5    if (lcheck .gt. mxnest) go to 99
          hx = hxposs(lcheck)
          hy = hyposs(lcheck)
          hz = hzposs(lcheck)
c
c  interpolate level lcheck
c
          mptr   = newstl(lcheck)
 10       if (mptr .eq. 0) go to 80
              nx = node(ndihi,mptr) - node(ndilo,mptr) + 1
              ny = node(ndjhi,mptr) - node(ndjlo,mptr) + 1
              nz = node(ndkhi,mptr) - node(ndklo,mptr) + 1
              mitot = nx + 2*nghost
              mjtot = ny + 2*nghost
              mktot = nz + 2*nghost
              corn1 = rnode(cornxlo,mptr)
              corn2 = rnode(cornylo,mptr)
              corn3 = rnode(cornzlo,mptr)
              loc    = igetsp(mitot * mjtot * mktot * nvar)
              node(store1, mptr)  = loc
              if (naux .gt. 0) then
                locaux = igetsp(mitot * mjtot *  mktot * naux)
                mx = mitot - 2*nghost
                my = mjtot - 2*nghost
                mz = mktot - 2*nghost
                call system_clock(clock_start, clock_rate)
                call cpu_time(cpu_start)
                call setaux(nghost,mx,my,mz,corn1,corn2,corn3,
     &                      hx,hy,hz,naux,alloc(locaux))
                call system_clock(clock_finish, clock_rate)
                call cpu_time(cpu_finish)
                timeSetaux = timeSetaux + clock_finish - clock_start
                timeSetauxCPU = timeSetauxCPU + cpu_finish - cpu_start
              else
                locaux = 1
              endif
              node(storeaux, mptr)  = locaux
              time   = rnode(timemult, mptr)
c
c      We now fill in the values for grid mptr using filval. It uses
c      piecewise linear interpolation to obtain values from the
c      (lcheck - 1) grid, then overwrites those with whatever (lcheck)
c      grids are available. We take advantage of the fact that the
c      (lcheck - 1) grids have already been set, and that the distance
c      between any point in mptr and a (lcheck - 1) and (lcheck - 2)
c      interface is at least one (lcheck - 1) cell wide.
c
 
c          # make a coarsened patch with ghost cells so can use
c          # grid interpolation routines, but only set "interior".
c          # extra 2 cells so that can use linear interp. on
c          # "interior" of coarser patch to fill fine grid.
           mic = nx/intratx(lcheck-1) + 2
           mjc = ny/intraty(lcheck-1) + 2
           mkc = nz/intratz(lcheck-1) + 2
           ivalc  = igetsp(mic*mjc*mkc*(nvar+naux))
           ivalaux  = ivalc + nvar*mic*mjc*mkc
           xl = rnode(cornxlo,mptr)
           xr = rnode(cornxhi,mptr)
           yf = rnode(cornylo,mptr)
           yr = rnode(cornyhi,mptr)
           zb = rnode(cornzlo,mptr)
           zt = rnode(cornzhi,mptr)
           hx = hxposs(lcheck)
           hy = hyposs(lcheck)
           hz = hzposs(lcheck)
           ilo    = node(ndilo, mptr)
           ihi    = node(ndihi, mptr)
           jlo    = node(ndjlo, mptr)
           jhi    = node(ndjhi, mptr)
           klo    = node(ndklo, mptr)
           khi    = node(ndkhi, mptr)
 
           call filval(alloc(loc),mitot,mjtot,mktot,hx,hy,hz,lcheck,
     1                 time,alloc(ivalc),alloc(ivalaux),mic,mjc,mkc,
     2                 xl,xr,yf,yr,zb,zt,nvar,
     3                 mptr,ilo,ihi,jlo,jhi,klo,khi,
     4                 alloc(locaux),naux)
 
           call reclam(ivalc,mic*mjc*mkc*(nvar+naux))

           mptr = node(levelptr, mptr)
           go to 10
c
c  done filling new grids at level. move them into lstart from newstl
c  (so can use as source grids for filling next level). can also
c  get rid of loc. 7 storage for old level.
c
 80   mptr = lstart(lcheck)
 85   if (mptr .eq. 0) go to 90
          nx = node(ndihi,mptr) - node(ndilo,mptr) + 1
          ny = node(ndjhi,mptr) - node(ndjlo,mptr) + 1
          nz = node(ndkhi,mptr) - node(ndklo,mptr) + 1
          mitot = nx + 2*nghost
          mjtot = ny + 2*nghost
          mktot = nz + 2*nghost
          call reclam(node(store1,mptr),mitot*mjtot*mktot*nvar)
          if (naux .gt. 0) then
            call reclam(node(storeaux,mptr),mitot*mjtot*mktot*naux)
          endif
          mold   = mptr
          mptr   = node(levelptr,mptr)
          call putnod(mold)
          call freeBndryList(mold)
          go to 85
 90   lstart(lcheck) = newstl(lcheck)
      lcheck = lcheck + 1
      go to 5
c
 99   lfine = lfnew
c
c     initialize 2nd (old time) storage block for new grids not at top level
c
      levend = min(lfine,mxnest-1)
      do 110 level = lbase+1, levend
         mptr = lstart(level)
 105     if (mptr .eq. 0) go to 110
            nx = node(ndihi,mptr) - node(ndilo,mptr) + 1
            ny = node(ndjhi,mptr) - node(ndjlo,mptr) + 1
           nz = node(ndkhi,mptr) - node(ndklo,mptr) + 1
            mitot = nx + 2*nghost
            mjtot = ny + 2*nghost
           mktot = nz + 2*nghost
           nwords = mitot*mjtot*mktot*nvar
            node(store2,mptr) = igetsp(nwords)
         mptr = node(levelptr,mptr)
         go to 105
 110   continue
c
c  grid structure now complete again. safe to print, etc. assuming
c  things initialized to zero in nodget.
c
      return
      end
c
c -----------------------------------------------------------------------------------------
c
c  use different routine since need to scan new grid list (newstl) not lstart
c  to make grids.  
c  could make one routine by passing in source of list, but this changed 4 other routines
c  so I didnt want to have to deal with it

       subroutine prepnewgrids(listnewgrids,num,level)

       use amr_module
       implicit double precision (a-h,o-z)
       integer listnewgrids(num)

       mptr = newstl(level)
       do j = 1, num
          listnewgrids(j) = mptr
          mptr = node(levelptr, mptr)
       end do

       if (mptr .ne. 0) then
         write(*,*)" Error in routine setting up grid array "
         stop
       endif

       return
       end
c
c -----------------------------------------------------------------
c
      subroutine makeGridList(lbase)
c
      use amr_module
      implicit none

      integer lbase, levSt, lev, mptr, n

c :::::::::::::::::::::::::::: make_gridList :::::::::::::::::::::::::
c     make array of grid numbers (after sorting them so in decreasing
c     order of workload, done in arrangeGrid and put back into linked 
c     list. Done every time there is regridding, initial gridding,
c     or restarting.  Most often finest level is regridded, so
c     put it last in array. lbase is the level that didnt change, so 
c     only redo from lbase+1 to lfine.
c :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

      !write(*,*)"mgl: lbase,lfine",lbase,lfine
      do lev = lbase+1, lfine
         levSt = listStart(lev) 
         !write(*,*)"mgl: level ",lev," starts at ",levSt
         mptr = lstart(lev)
c        traverse linked list into array. list already sorted by arrangegrids
         do n = 1, numgrids(lev)
            listOfGrids(levSt+n-1) = mptr
            mptr = node(levelptr,mptr)
         end do
c        next level starts one after where this one ends.
c        Using a sentinel in dimension of
c        listStart so no need to test if level = mxnest
         listStart(lev+1) = levSt + numgrids(lev)
      end do
      return
      end
c
c -----------------------------------------------------------------
c
      subroutine makeBndryList(level)
c
      use amr_module
      implicit none

      integer level, n, levSt, k, nborCount
      integer nodget_bnd, nextSpot, prevNbor, msrc, mptr
      integer imin, imax, jmin, jmax
      integer imlo, imhi, jmlo, jmhi
      integer ixlo, ixhi, jxlo, jxhi

c :::::::::::::::::::::::::::: makeBndryList :::::::::::::::::::::::::
c     preprocess each grid to have linked list of other grids at
c     same level that supply ghost cells.
c :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

c     traverse linked list into array. list already sorted by arrangegrids
      levSt = listStart(level) 
      do n = 1, numgrids(level)
         mptr = listOfGrids(levSt+n-1)
         imin = node(ndilo,mptr) - nghost  ! ghost cells included since
         imax = node(ndihi,mptr) + nghost  ! this is what you want to fill
         jmin = node(ndjlo,mptr) - nghost  ! may also use for filval stuff,
         jmax = node(ndjhi,mptr) + nghost  ! change nghost to mbuff, etc
         nborCount = 0
         
         do k = 1, numgrids(level)  ! loop over all other grids once to find touching ones 
            if (k .eq. n) cycle     ! dont count yourself as source grid
            msrc = listOfgrids(levSt+k-1)

            ! Check if grid mptr and patch intersect
            imlo = node(ndilo, msrc)
            jmlo = node(ndjlo, msrc)
            imhi = node(ndihi, msrc)
            jmhi = node(ndjhi, msrc)

            ixlo = max(imlo,imin)
            ixhi = min(imhi,imax)
            jxlo = max(jmlo,jmin)
            jxhi = min(jmhi,jmax)

            if (ixlo .le. ixhi .and. jxlo .le. jxhi) then ! put on bnd list for mptr
               nborCount = nborCount + 1
               nextSpot = nodget_bnd()   
               bndList(nextSpot,gridNbor) = msrc
               ! get spot in bnd list. insert next grid at front to avoid traversing
               bndList(nextSpot,nextfree) =  node(bndListSt,mptr)
               node(bndListSt,mptr) = nextSpot
            endif

         end do

!        save final count
         node(bndListNum,mptr) = nborcount
      end do

      return
      end
c
c -----------------------------------------------------------------
c
      subroutine freeBndryList(mold)
c
      use amr_module
      implicit none

      integer nborCount, mold,nextSpot, i, nextnext

c :::::::::::::::::::::::::::: freeBndryList :::::::::::::::::::::::::
c     free the linked list of intersecting "boundary" grids for grid 'mold'
c     that is no longer active
c :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

           nborCount = node(bndListNum,mold) ! count for this grid
           nextSpot  = node(bndListSt,mold)  ! first index of this grids nbors
           do i = 1, nborCount
               nextnext = bndList(nextSpot,nextfree)
               call putnod_bnd(nextSpot)
               nextSpot = nextnext
           end do

      return
      end
