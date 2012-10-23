c
c -----------------------------------------------------------
c
      subroutine update (level, nvar)
c
      implicit double precision (a-h,o-z)

      include  "call.i"

c2D   iadd(i,j,ivar)  = loc     + i - 1 + mitot*((ivar-1)*mjtot+j-1)
c2D   iaddf(i,j,ivar) = locf    + i - 1 + mi*((ivar-1)*mj  +j-1)
c2D   iaddfaux(i,j)   = locfaux + i - 1 + mi*((mcapa-1)*mj + (j-1))
c2D   iaddcaux(i,j)   = loccaux + i - 1 + mitot*((mcapa-1)*mjtot+(j-1))
      iadd(i,j,k,ivar)   = loc     +     (i-1)
     &                             +     (j-1)*mitot
     &                             +     (k-1)*mitot*mjtot
     &                             +  (ivar-1)*mitot*mjtot*mktot
      iaddf(i,j,k,ivar)  = locf    +     (i-1)
     &                             +     (j-1)*mi
     &                             +     (k-1)*mi*mj
     &                             +  (ivar-1)*mi*mj*mk
      iaddfaux(i,j,k)    = locfaux +     (i-1)
     &                             +     (j-1)*mi
     &                             +     (k-1)*mi*mj
     &                             + (mcapa-1)*mi*mj*mk
      iaddcaux(i,j,k)    = loccaux +     (i-1)
     &                             +     (j-1)*mitot
     &                             +     (k-1)*mitot*mjtot
     &                             + (mcapa-1)*mitot*mjtot*mktot
c
c :::::::::::::::::::::::::: UPDATE :::::::::::::::::::::::::::::::::
c update - update all grids at level 'level'.
c          this routine assumes cell centered variables.
c          the update is done from 1 level finer meshes under it.
c input parameter:
c    level  - ptr to the only level to be updated. levels coarser than
c             this will be at a diffeent time.
c :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
c
      lget = level
      if (uprint) write(outunit,100) lget
100   format(19h    updating level ,i5)
c
c  grid loop for each level
c
      dt     = possk(lget)

      mptr = lstart(lget)
 20   if (mptr .eq. 0) go to 85
         loc     = node(store1,mptr)
         loccaux = node(storeaux,mptr)
	 nx      = node(ndihi,mptr) - node(ndilo,mptr) + 1
	 ny      = node(ndjhi,mptr) - node(ndjlo,mptr) + 1
         nz      = node(ndkhi,mptr) - node(ndklo,mptr) + 1
	 mitot   = nx + 2*nghost
	 mjtot   = ny + 2*nghost
         mktot   = nz + 2*nghost
	 ilo     = node(ndilo,mptr)
	 jlo     = node(ndjlo,mptr)
         klo     = node(ndklo,mptr)
	 ihi     = node(ndihi,mptr)
	 jhi     = node(ndjhi,mptr)
         khi     = node(ndkhi,mptr)
c
         if (node(cfluxptr,mptr) .eq. 0) go to 25
         locuse = igetsp(mitot*mjtot*mktot)
         call upbnd(alloc(node(cfluxptr,mptr)),alloc(loc),nvar,
     1              mitot,mjtot,mktot,listsp(lget),alloc(locuse),mptr)
         call reclam(locuse,mitot*mjtot*mktot)
c
c  loop through all intersecting fine grids as source updaters.
c
 25      mkid = lstart(lget+1)
 30        if (mkid .eq. 0) go to 80
	   iclo   = node(ndilo,mkid)/intratx(lget)
	   jclo   = node(ndjlo,mkid)/intraty(lget)
           kclo   = node(ndklo,mkid)/intratz(lget)
	   ichi   = node(ndihi,mkid)/intratx(lget)
	   jchi   = node(ndjhi,mkid)/intraty(lget)
           kchi   = node(ndkhi,mkid)/intratz(lget)

	   mi      = node(ndihi,mkid)-node(ndilo,mkid) + 1 + 2*nghost
	   mj      = node(ndjhi,mkid)-node(ndjlo,mkid) + 1 + 2*nghost
           mk      = node(ndkhi,mkid)-node(ndklo,mkid) + 1 + 2*nghost
	   locf    = node(store1,mkid)
	   locfaux = node(storeaux,mkid)
c
c  calculate starting and ending indices for coarse grid update, if overlap
c
	 iplo = max(ilo,iclo)
	 jplo = max(jlo,jclo)
         kplo = max(klo,kclo)
	 iphi = min(ihi,ichi)
	 jphi = min(jhi,jchi)
         kphi = min(khi,kchi)

	 if (iplo .gt. iphi .or. jplo .gt. jphi
     1                      .or. kplo .gt. kphi) go to 75
c
c  calculate starting index for fine grid source pts.
c
         totrat = intratx(lget) * intraty(lget) * intratz(lget)
 
         iff    = iplo*intratx(lget) - node(ndilo,mkid) + nghost + 1
         do 72 i = iplo-ilo+nghost+1, iphi-ilo+nghost+1
         jff    = jplo*intraty(lget) - node(ndjlo,mkid) + nghost + 1
         do 71 j = jplo-jlo+nghost+1, jphi-jlo+nghost+1
         kff    = kplo*intratz(lget) - node(ndklo,mkid) + nghost + 1
         do 70 k = kplo-klo+nghost+1, kphi-klo+nghost+1
           if (uprint) then
	      write(outunit,101) i,j,k,mptr,iff,jff,kff,mkid
 101          format(' updating pt. ',3i4,' of grid ',i3,' using ',3i4,
     1               ' of grid ',i4)
              write(outunit,102)(alloc(iadd(i,j,k,ivar)),ivar=1,nvar)
 102          format(' old vals: ',5e30.20)
	   endif
c
c
c  update using intrat fine points in each direction
c
           do 40 ivar = 1, nvar
 40           alloc(iadd(i,j,k,ivar)) = 0.d0
c
           if (mcapa .eq. 0) then

               do 50 kco  = 1, intratz(lget)
	       do 50 jco  = 1, intraty(lget)
	       do 50 ico  = 1, intratx(lget)
	       do 45 ivar = 1, nvar
                 alloc(iadd(i,j,k,ivar))= alloc(iadd(i,j,k,ivar)) + 
     1                  alloc(iaddf(iff+ico-1,jff+jco-1,kff+kco-1,ivar))
 45              continue
 50            continue
               do 65 ivar = 1, nvar
 65             alloc(iadd(i,j,k,ivar)) = alloc(iadd(i,j,k,ivar))/totrat
	       
	   else

               do 51 kco  = 1, intratz(lget)
	       do 51 jco  = 1, intraty(lget)
	       do 51 ico  = 1, intratx(lget)
	       capa = alloc(iaddfaux(iff+ico-1,jff+jco-1,kff+kco-1))
	       do 46 ivar = 1, nvar
                 alloc(iadd(i,j,k,ivar))= alloc(iadd(i,j,k,ivar)) + 
     1             alloc(iaddf(iff+ico-1,jff+jco-1,kff+kco-1,ivar))*capa
 46              continue
 51            continue
               do 66 ivar = 1, nvar
 66             alloc(iadd(i,j,k,ivar)) = alloc(iadd(i,j,k,ivar))/
     1	                                 (totrat*alloc(iaddcaux(i,j,k)))
	   endif
c
            if (uprint) write(outunit,103)(alloc(iadd(i,j,k,ivar)),
     .			                   ivar=1,nvar)
 103        format(' new vals: ',5e12.4)
c
           kff = kff + intratz(lget)
 70        continue
           jff = jff + intraty(lget)
 71        continue
           iff = iff + intratx(lget)
 72        continue
c
 75         mkid = node(levelptr,mkid)
            go to 30
c
 80         mptr = node(levelptr, mptr)
            go to 20
c
 85       continue
c
 99   return
      end
