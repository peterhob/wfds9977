MODULE VELO

! Module computes the velocity flux terms, baroclinic torque correction terms, and performs the CFL Check

USE PRECISION_PARAMETERS
USE GLOBAL_CONSTANTS
USE MESH_POINTERS
USE COMP_FUNCTIONS, ONLY: SECOND

IMPLICIT NONE

PRIVATE
CHARACTER(255), PARAMETER :: veloid='$Id: velo.f90 9960 2012-02-01 21:02:15Z randy.mcdermott $'
CHARACTER(255), PARAMETER :: velorev='$Revision: 9960 $'
CHARACTER(255), PARAMETER :: velodate='$Date: 2012-02-01 13:02:15 -0800 (Wed, 01 Feb 2012) $'

PUBLIC COMPUTE_VELOCITY_FLUX,VELOCITY_PREDICTOR,VELOCITY_CORRECTOR,NO_FLUX,GET_REV_velo, &
       MATCH_VELOCITY,VELOCITY_BC,CHECK_STABILITY
PRIVATE VELOCITY_FLUX,VELOCITY_FLUX_CYLINDRICAL
 
CONTAINS
 
SUBROUTINE COMPUTE_VELOCITY_FLUX(T,NM,FUNCTION_CODE)

REAL(EB), INTENT(IN) :: T
REAL(EB) :: TNOW
INTEGER, INTENT(IN) :: NM,FUNCTION_CODE

IF (SOLID_PHASE_ONLY .OR. FREEZE_VELOCITY) RETURN
IF (VEG_LEVEL_SET_UNCOUPLED) RETURN

TNOW = SECOND()

SELECT CASE(FUNCTION_CODE)
   CASE(1)
      CALL COMPUTE_VISCOSITY(NM)
   CASE(2)
      CALL VISCOSITY_BC(NM)
      IF (.NOT.CYLINDRICAL) CALL VELOCITY_FLUX(T,NM)
      IF (     CYLINDRICAL) CALL VELOCITY_FLUX_CYLINDRICAL(T,NM)
END SELECT

TUSED(4,NM) = TUSED(4,NM) + SECOND() - TNOW
END SUBROUTINE COMPUTE_VELOCITY_FLUX



SUBROUTINE COMPUTE_VISCOSITY(NM)

USE PHYSICAL_FUNCTIONS, ONLY: GET_VISCOSITY
USE TURBULENCE, ONLY: VARDEN_DYNSMAG,TEST_FILTER,EX2G3D
INTEGER, INTENT(IN) :: NM
REAL(EB) :: ZZ_GET(0:N_TRACKED_SPECIES),NU_EDDY,DELTA,KSGS,NU_G,GRAD_RHO(3),U2,V2,W2,AA,A_IJ(3,3),BB,B_IJ(3,3),&
            DUDX,DUDY,DUDZ,DVDX,DVDY,DVDZ,DWDX,DWDY,DWDZ,MU_DNS
INTEGER :: I,J,K,IIG,JJG,KKG,II,JJ,KK,IW,TURB_MODEL_TMP,IOR
REAL(EB), POINTER, DIMENSION(:,:,:) :: RHOP=>NULL(),UP=>NULL(),VP=>NULL(),WP=>NULL(), &
                                       UP_HAT=>NULL(),VP_HAT=>NULL(),WP_HAT=>NULL(), &
                                       UU=>NULL(),VV=>NULL(),WW=>NULL()
REAL(EB), POINTER, DIMENSION(:,:,:,:) :: ZZP=>NULL()
TYPE(WALL_TYPE), POINTER :: WC=>NULL() 
 
CALL POINT_TO_MESH(NM)
 
IF (PREDICTOR) THEN
   RHOP => RHO
   UU   => U
   VV   => V
   WW   => W
   IF (N_TRACKED_SPECIES > 0) ZZP => ZZ
ELSE
   RHOP => RHOS
   UU   => US
   VV   => VS
   WW   => WS
   IF (N_TRACKED_SPECIES > 0 .AND. .NOT.EVACUATION_ONLY(NM)) ZZP => ZZS
ENDIF

! Compute viscosity for DNS using primitive species/mixture fraction

!$OMP PARALLEL DEFAULT(NONE) &
!$OMP SHARED(N_TRACKED_SPECIES,EVACUATION_ONLY,KBAR,JBAR,IBAR,SOLID,CELL_INDEX,ZZP,MU,TMP, &
!$OMP        LES,NM,C_SMAGORINSKY,TWO_D,DX,DY,DZ,RDX,RDY,RDZ,UU,VV,WW,RHOP,CSD2, &
!$OMP        N_EXTERNAL_WALL_CELLS,N_INTERNAL_WALL_CELLS,KRES, &
!$OMP        IBP1,JBP1,KBP1,TURB_MODEL_TMP,TURB_MODEL,PREDICTOR,STRAIN_RATE,UP,VP,WP,WORK1,WORK2,WORK3,WC,WALL,U_GHOST,V_GHOST, &
!$OMP        W_GHOST,UP_HAT,VP_HAT,WP_HAT,WORK4,WORK5,WORK6,DELTA,KSGS,NU_EDDY,C_DEARDORFF,DUDX,DVDY,DWDZ,DUDY,DUDZ,DVDX,DVDZ,  &
!$OMP        DWDX,DWDY,II,JJ,KK,A_IJ,AA,B_IJ,BB,C_VREMAN,GRAV_VISC,GRAD_RHO,NU_G,C_G,GVEC,IOR,MU_DNS) &
!$OMP PRIVATE(ZZ_GET)

IF (N_TRACKED_SPECIES>0 .AND. EVACUATION_ONLY(NM)) ZZ_GET(1:N_TRACKED_SPECIES) = 0._EB

!$OMP DO COLLAPSE(3) SCHEDULE(STATIC) &
!$OMP PRIVATE(K,J,I) 
DO K=1,KBAR
   DO J=1,JBAR
      DO I=1,IBAR
         IF (SOLID(CELL_INDEX(I,J,K))) CYCLE
         IF (N_TRACKED_SPECIES>0 .AND. .NOT.EVACUATION_ONLY(NM)) ZZ_GET(1:N_TRACKED_SPECIES) = ZZP(I,J,K,1:N_TRACKED_SPECIES)
         CALL GET_VISCOSITY(ZZ_GET,MU(I,J,K),TMP(I,J,K))
      ENDDO
   ENDDO
ENDDO
!$OMP END DO

TURB_MODEL_TMP = TURB_MODEL
IF (EVACUATION_ONLY(NM)) TURB_MODEL_TMP = CONSMAG

SELECT_TURB: SELECT CASE (TURB_MODEL_TMP)

   CASE (CONSMAG,DYNSMAG) SELECT_TURB ! Smagorinsky (1963) eddy viscosity

      CALL COMPUTE_STRAIN_RATE(NM)
   
      IF (PREDICTOR .AND. TURB_MODEL_TMP==DYNSMAG) CALL VARDEN_DYNSMAG(NM) ! dynamic procedure, Moin et al. (1991)
   
      !$OMP DO COLLAPSE(3) SCHEDULE(STATIC) &
      !$OMP PRIVATE(K,J,I)
      DO K=1,KBAR
         DO J=1,JBAR
            DO I=1,IBAR
               IF (SOLID(CELL_INDEX(I,J,K))) CYCLE
               MU(I,J,K) = MU(I,J,K) + RHOP(I,J,K)*CSD2(I,J,K)*STRAIN_RATE(I,J,K)
            ENDDO
         ENDDO
      ENDDO
      !$OMP END DO
   
   CASE (DEARDORFF) SELECT_TURB ! Deardorff (1980) eddy viscosity model (current default)

      ! Velocities relative to the p-cell center

      UP => WORK1
      VP => WORK2
      WP => WORK3
      UP=0._EB
      VP=0._EB
      WP=0._EB

      DO K=1,KBAR
         DO J=1,JBAR
            DO I=1,IBAR
               UP(I,J,K) = 0.5_EB*(UU(I,J,K) + UU(I-1,J,K))
               VP(I,J,K) = 0.5_EB*(VV(I,J,K) + VV(I,J-1,K))
               WP(I,J,K) = 0.5_EB*(WW(I,J,K) + WW(I,J,K-1))
            ENDDO
         ENDDO
      ENDDO
   
      ! extrapolate to ghost cells

      CALL EX2G3D(UP,-1.E10_EB,1.E10_EB)
      CALL EX2G3D(VP,-1.E10_EB,1.E10_EB)
      CALL EX2G3D(WP,-1.E10_EB,1.E10_EB)

      DO IW=1,N_EXTERNAL_WALL_CELLS
         WC=>WALL(IW)
         IF (WC%BOUNDARY_TYPE/=INTERPOLATED_BOUNDARY) CYCLE
         II = WC%II
         JJ = WC%JJ
         KK = WC%KK
         UP(II,JJ,KK) = U_GHOST(IW)
         VP(II,JJ,KK) = V_GHOST(IW)
         WP(II,JJ,KK) = W_GHOST(IW)
      ENDDO

      UP_HAT => WORK4
      VP_HAT => WORK5
      WP_HAT => WORK6
      UP_HAT=0._EB
      VP_HAT=0._EB
      WP_HAT=0._EB

      CALL TEST_FILTER(UP_HAT,UP,-1.E10_EB,1.E10_EB)
      CALL TEST_FILTER(VP_HAT,VP,-1.E10_EB,1.E10_EB)
      CALL TEST_FILTER(WP_HAT,WP,-1.E10_EB,1.E10_EB)

      DO K=1,KBAR
         DO J=1,JBAR
            DO I=1,IBAR
               IF (SOLID(CELL_INDEX(I,J,K))) CYCLE
               IF (TWO_D) THEN
                  DELTA = MAX(DX(I),DZ(K))
               ELSE
                  DELTA = MAX(DX(I),DY(J),DZ(K))
               ENDIF
            
               KSGS = 0.5_EB*( (UP(I,J,K)-UP_HAT(I,J,K))**2 + (VP(I,J,K)-VP_HAT(I,J,K))**2 + (WP(I,J,K)-WP_HAT(I,J,K))**2 )
               NU_EDDY = C_DEARDORFF*DELTA*SQRT(KSGS)
            
               MU(I,J,K) = MU(I,J,K) + RHOP(I,J,K)*NU_EDDY
            ENDDO
         ENDDO
      ENDDO

   CASE (VREMAN) SELECT_TURB ! Vreman (2004) eddy viscosity model (experimental)

      ! A. W. Vreman. An eddy-viscosity subgrid-scale model for turbulent shear flow: Algebraic theory and applications.
      ! Phys. Fluids, 16(10):3670-3681, 2004.
   
      DO K=1,KBAR
         DO J=1,JBAR
            DO I=1,IBAR
               IF (SOLID(CELL_INDEX(I,J,K))) CYCLE
               DUDX = RDX(I)*(UU(I,J,K)-UU(I-1,J,K))
               DVDY = RDY(J)*(VV(I,J,K)-VV(I,J-1,K))
               DWDZ = RDZ(K)*(WW(I,J,K)-WW(I,J,K-1))
               DUDY = 0.25_EB*RDY(J)*(UU(I,J+1,K)-UU(I,J-1,K)+UU(I-1,J+1,K)-UU(I-1,J-1,K))
               DUDZ = 0.25_EB*RDZ(K)*(UU(I,J,K+1)-UU(I,J,K-1)+UU(I-1,J,K+1)-UU(I-1,J,K-1)) 
               DVDX = 0.25_EB*RDX(I)*(VV(I+1,J,K)-VV(I-1,J,K)+VV(I+1,J-1,K)-VV(I-1,J-1,K))
               DVDZ = 0.25_EB*RDZ(K)*(VV(I,J,K+1)-VV(I,J,K-1)+VV(I,J-1,K+1)-VV(I,J-1,K-1))
               DWDX = 0.25_EB*RDX(I)*(WW(I+1,J,K)-WW(I-1,J,K)+WW(I+1,J,K-1)-WW(I-1,J,K-1))
               DWDY = 0.25_EB*RDY(J)*(WW(I,J+1,K)-WW(I,J-1,K)+WW(I,J+1,K-1)-WW(I,J-1,K-1))
         
               ! Vreman, Eq. (6)
               A_IJ(1,1)=DUDX; A_IJ(2,1)=DUDY; A_IJ(3,1)=DUDZ
               A_IJ(1,2)=DVDX; A_IJ(2,2)=DVDY; A_IJ(3,2)=DVDZ
               A_IJ(1,3)=DWDX; A_IJ(2,3)=DWDY; A_IJ(3,3)=DWDZ

               AA=0._EB
               DO JJ=1,3
                  DO II=1,3
                     AA = AA + A_IJ(II,JJ)*A_IJ(II,JJ)
                  ENDDO
               ENDDO
               
               ! Vreman, Eq. (7)
               B_IJ(1,1)=(DX(I)*A_IJ(1,1))**2 + (DY(J)*A_IJ(2,1))**2 + (DZ(K)*A_IJ(3,1))**2
               B_IJ(2,2)=(DX(I)*A_IJ(1,2))**2 + (DY(J)*A_IJ(2,2))**2 + (DZ(K)*A_IJ(3,2))**2
               B_IJ(3,3)=(DX(I)*A_IJ(1,3))**2 + (DY(J)*A_IJ(2,3))**2 + (DZ(K)*A_IJ(3,3))**2

               B_IJ(1,2)=DX(I)**2*A_IJ(1,1)*A_IJ(1,2) + DY(J)**2*A_IJ(2,1)*A_IJ(2,2) + DZ(K)**2*A_IJ(3,1)*A_IJ(3,2)
               B_IJ(1,3)=DX(I)**2*A_IJ(1,1)*A_IJ(1,3) + DY(J)**2*A_IJ(2,1)*A_IJ(2,3) + DZ(K)**2*A_IJ(3,1)*A_IJ(3,3)
               B_IJ(2,3)=DX(I)**2*A_IJ(1,2)*A_IJ(1,3) + DY(J)**2*A_IJ(2,2)*A_IJ(2,3) + DZ(K)**2*A_IJ(3,2)*A_IJ(3,3)

               BB = B_IJ(1,1)*B_IJ(2,2) - B_IJ(1,2)**2 &
                  + B_IJ(1,1)*B_IJ(3,3) - B_IJ(1,3)**2 &
                  + B_IJ(2,2)*B_IJ(3,3) - B_IJ(2,3)**2    ! Vreman, Eq. (8)
 
               IF (ABS(AA)>ZERO_P) THEN
                  NU_EDDY = C_VREMAN*SQRT(BB/AA)  ! Vreman, Eq. (5)
               ELSE
                  NU_EDDY=0._EB
               ENDIF
    
               MU(I,J,K) = MU(I,J,K) + RHOP(I,J,K)*NU_EDDY 
         
            ENDDO
         ENDDO
      ENDDO
   
END SELECT SELECT_TURB
 
! Add viscosity for stably stratified flows (experimental)

GRAVITY_IF: IF (LES .AND. GRAV_VISC) THEN

   DO K=1,KBAR
      DO J=1,JBAR
         DO I=1,IBAR
            IF (SOLID(CELL_INDEX(I,J,K))) CYCLE
            IF (TWO_D) THEN
               DELTA = MAX(DX(I),DZ(K))
            ELSE
               DELTA = MAX(DX(I),DY(J),DZ(K))
            ENDIF
            
            GRAD_RHO(1) = 0.5_EB*RDX(I)*(RHOP(I+1,J,K)-RHOP(I-1,J,K))
            GRAD_RHO(2) = 0.5_EB*RDY(J)*(RHOP(I,J+1,K)-RHOP(I,J-1,K))
            GRAD_RHO(3) = 0.5_EB*RDZ(K)*(RHOP(I,J,K+1)-RHOP(I,J,K-1))
            
            NU_G = C_G*DELTA**2*SQRT(MAX(ZERO_P,DOT_PRODUCT(GRAD_RHO,GVEC))/RHOP(I,J,K))
            
            MU(I,J,K) = MAX(MU(I,J,K),RHOP(I,J,K)*NU_G)
         ENDDO
      ENDDO
   ENDDO

ENDIF GRAVITY_IF

! Compute resolved kinetic energy per unit mass

!$OMP DO COLLAPSE(3) SCHEDULE(STATIC) PRIVATE(K,J,I,U2,V2,W2)
DO K=1,KBAR
   DO J=1,JBAR
      DO I=1,IBAR
         U2 = 0.25_EB*(UU(I-1,J,K)+UU(I,J,K))**2
         V2 = 0.25_EB*(VV(I,J-1,K)+VV(I,J,K))**2
         W2 = 0.25_EB*(WW(I,J,K-1)+WW(I,J,K))**2
         KRES(I,J,K) = 0.5_EB*(U2+V2+W2)
      ENDDO
   ENDDO
ENDDO
!$OMP END DO NOWAIT

! Mirror viscosity into solids and exterior boundary cells

!$OMP DO SCHEDULE(STATIC) &
!$OMP PRIVATE(IW,II,JJ,KK,IIG,JJG,KKG)
WALL_LOOP: DO IW=1,N_EXTERNAL_WALL_CELLS+N_INTERNAL_WALL_CELLS
   WC=>WALL(IW)
   IF (WC%BOUNDARY_TYPE==NULL_BOUNDARY) CYCLE WALL_LOOP
   II  = WC%II
   JJ  = WC%JJ
   KK  = WC%KK
   IOR = WC%IOR
   IIG = WC%IIG
   JJG = WC%JJG
   KKG = WC%KKG
   
   SELECT CASE(WC%BOUNDARY_TYPE)
      CASE(SOLID_BOUNDARY)
         IF (LES) THEN
            IF (N_TRACKED_SPECIES>0 .AND. .NOT.EVACUATION_ONLY(NM)) &
               ZZ_GET(1:N_TRACKED_SPECIES) = ZZP(IIG,JJG,KKG,1:N_TRACKED_SPECIES)
            CALL GET_VISCOSITY(ZZ_GET,MU_DNS,TMP(IIG,JJG,KKG))
            SELECT CASE (IOR)
               CASE ( 1); MU(IIG,JJG,KKG) = MAX(MU_DNS,ONTH*MU(IIG+1,JJG,KKG))
               CASE (-1); MU(IIG,JJG,KKG) = MAX(MU_DNS,ONTH*MU(IIG-1,JJG,KKG))
               CASE ( 2); MU(IIG,JJG,KKG) = MAX(MU_DNS,ONTH*MU(IIG,JJG+1,KKG))
               CASE (-2); MU(IIG,JJG,KKG) = MAX(MU_DNS,ONTH*MU(IIG,JJG-1,KKG))
               CASE ( 3); MU(IIG,JJG,KKG) = MAX(MU_DNS,ONTH*MU(IIG,JJG,KKG+1))
               CASE (-3); MU(IIG,JJG,KKG) = MAX(MU_DNS,ONTH*MU(IIG,JJG,KKG-1))
            END SELECT
         ENDIF
         IF (SOLID(CELL_INDEX(II,JJ,KK))) MU(II,JJ,KK) = MU(IIG,JJG,KKG)
      CASE(OPEN_BOUNDARY,MIRROR_BOUNDARY)
         MU(II,JJ,KK) = MU(IIG,JJG,KKG)
         KRES(II,JJ,KK) = KRES(IIG,JJG,KKG)
   END SELECT
ENDDO WALL_LOOP
!$OMP END DO

!$OMP WORKSHARE
MU(   0,0:JBP1,   0) = MU(   1,0:JBP1,1)
MU(IBP1,0:JBP1,   0) = MU(IBAR,0:JBP1,1)
MU(IBP1,0:JBP1,KBP1) = MU(IBAR,0:JBP1,KBAR)
MU(   0,0:JBP1,KBP1) = MU(   1,0:JBP1,KBAR)
MU(0:IBP1,   0,   0) = MU(0:IBP1,   1,1)
MU(0:IBP1,JBP1,0)    = MU(0:IBP1,JBAR,1)
MU(0:IBP1,JBP1,KBP1) = MU(0:IBP1,JBAR,KBAR)
MU(0:IBP1,0,KBP1)    = MU(0:IBP1,   1,KBAR)
MU(0,   0,0:KBP1)    = MU(   1,   1,0:KBP1)
MU(IBP1,0,0:KBP1)    = MU(IBAR,   1,0:KBP1)
MU(IBP1,JBP1,0:KBP1) = MU(IBAR,JBAR,0:KBP1)
MU(0,JBP1,0:KBP1)    = MU(   1,JBAR,0:KBP1)
!$OMP END WORKSHARE
!$OMP END PARALLEL

END SUBROUTINE COMPUTE_VISCOSITY


SUBROUTINE COMPUTE_STRAIN_RATE(NM)

INTEGER, INTENT(IN) :: NM
REAL(EB) :: DUDX,DUDY,DUDZ,DVDX,DVDY,DVDZ,DWDX,DWDY,DWDZ,S11,S22,S33,S12,S13,S23,ONTHDIV
INTEGER :: I,J,K,IOR,IIG,JJG,KKG,IW,SURF_INDEX
REAL(EB), POINTER, DIMENSION(:,:,:) :: UU=>NULL(),VV=>NULL(),WW=>NULL()
TYPE(WALL_TYPE), POINTER :: WC=>NULL()
CALL POINT_TO_MESH(NM)

IF (PREDICTOR) THEN
   UU => U
   VV => V
   WW => W
ELSE
   UU => US
   VV => VS
   WW => WS
ENDIF

DO K=1,KBAR
   DO J=1,JBAR
      DO I=1,IBAR
         IF (SOLID(CELL_INDEX(I,J,K))) CYCLE
         DUDX = RDX(I)*(UU(I,J,K)-UU(I-1,J,K))
         DVDY = RDY(J)*(VV(I,J,K)-VV(I,J-1,K))
         DWDZ = RDZ(K)*(WW(I,J,K)-WW(I,J,K-1))
         DUDY = 0.25_EB*RDY(J)*(UU(I,J+1,K)-UU(I,J-1,K)+UU(I-1,J+1,K)-UU(I-1,J-1,K))
         DUDZ = 0.25_EB*RDZ(K)*(UU(I,J,K+1)-UU(I,J,K-1)+UU(I-1,J,K+1)-UU(I-1,J,K-1)) 
         DVDX = 0.25_EB*RDX(I)*(VV(I+1,J,K)-VV(I-1,J,K)+VV(I+1,J-1,K)-VV(I-1,J-1,K))
         DVDZ = 0.25_EB*RDZ(K)*(VV(I,J,K+1)-VV(I,J,K-1)+VV(I,J-1,K+1)-VV(I,J-1,K-1))
         DWDX = 0.25_EB*RDX(I)*(WW(I+1,J,K)-WW(I-1,J,K)+WW(I+1,J,K-1)-WW(I-1,J,K-1))
         DWDY = 0.25_EB*RDY(J)*(WW(I,J+1,K)-WW(I,J-1,K)+WW(I,J+1,K-1)-WW(I,J-1,K-1))
         ONTHDIV = ONTH*(DUDX+DVDY+DWDZ)
         S11 = DUDX - ONTHDIV
         S22 = DVDY - ONTHDIV
         S33 = DWDZ - ONTHDIV
         S12 = 0.5_EB*(DUDY+DVDX)
         S13 = 0.5_EB*(DUDZ+DWDX)
         S23 = 0.5_EB*(DVDZ+DWDY)
         STRAIN_RATE(I,J,K) = SQRT(2._EB*(S11**2 + S22**2 + S33**2 + 2._EB*(S12**2 + S13**2 + S23**2)))
      ENDDO
   ENDDO
ENDDO


WALL_LOOP: DO IW=1,N_EXTERNAL_WALL_CELLS+N_INTERNAL_WALL_CELLS
   WC=>WALL(IW)
   IF (WC%BOUNDARY_TYPE/=SOLID_BOUNDARY) CYCLE WALL_LOOP
   IOR = WC%IOR
   SURF_INDEX = WC%SURF_INDEX
   IIG = WC%IIG
   JJG = WC%JJG
   KKG = WC%KKG
   
   DUDX = RDX(IIG)*(UU(IIG,JJG,KKG)-UU(IIG-1,JJG,KKG))
   DVDY = RDY(JJG)*(VV(IIG,JJG,KKG)-VV(IIG,JJG-1,KKG))
   DWDZ = RDZ(KKG)*(WW(IIG,JJG,KKG)-WW(IIG,JJG,KKG-1))
   ONTHDIV = ONTH*(DUDX+DVDY+DWDZ)
   S11 = DUDX - ONTHDIV
   S22 = DVDY - ONTHDIV
   S33 = DWDZ - ONTHDIV
   
   DUDY = 0.25_EB*RDY(JJG)*(UU(IIG,JJG+1,KKG)-UU(IIG,JJG-1,KKG)+UU(IIG-1,JJG+1,KKG)-UU(IIG-1,JJG-1,KKG))
   DUDZ = 0.25_EB*RDZ(KKG)*(UU(IIG,JJG,KKG+1)-UU(IIG,JJG,KKG-1)+UU(IIG-1,JJG,KKG+1)-UU(IIG-1,JJG,KKG-1)) 
   DVDX = 0.25_EB*RDX(IIG)*(VV(IIG+1,JJG,KKG)-VV(IIG-1,JJG,KKG)+VV(IIG+1,JJG-1,KKG)-VV(IIG-1,JJG-1,KKG))
   DVDZ = 0.25_EB*RDZ(KKG)*(VV(IIG,JJG,KKG+1)-VV(IIG,JJG,KKG-1)+VV(IIG,JJG-1,KKG+1)-VV(IIG,JJG-1,KKG-1))
   DWDX = 0.25_EB*RDX(IIG)*(WW(IIG+1,JJG,KKG)-WW(IIG-1,JJG,KKG)+WW(IIG+1,JJG,KKG-1)-WW(IIG-1,JJG,KKG-1))
   DWDY = 0.25_EB*RDY(JJG)*(WW(IIG,JJG+1,KKG)-WW(IIG,JJG-1,KKG)+WW(IIG,JJG+1,KKG-1)-WW(IIG,JJG-1,KKG-1))
   
   FREE_SLIP_IF: IF (SURFACE(SURF_INDEX)%VELOCITY_BC_INDEX==FREE_SLIP_BC) THEN
      SELECT CASE(ABS(IOR))
         CASE(1)
            DVDX = 0._EB
            DWDX = 0._EB
         CASE(2)
            DUDY = 0._EB
            DWDY = 0._EB
         CASE(3)
            DUDZ = 0._EB
            DVDZ = 0._EB
      END SELECT
   ELSE FREE_SLIP_IF
      SELECT CASE(IOR)
         CASE(1) 
            DVDX = 0.25_EB*RDX(IIG)*(VV(IIG,JJG,KKG)+VV(IIG+1,JJG,KKG)+VV(IIG,JJG-1,KKG)+VV(IIG+1,JJG-1,KKG))
            DWDX = 0.25_EB*RDX(IIG)*(WW(IIG,JJG,KKG)+WW(IIG+1,JJG,KKG)+WW(IIG,JJG,KKG-1)+WW(IIG+1,JJG,KKG-1))
         CASE(-1)
            DVDX = -0.25_EB*RDX(IIG)*(VV(IIG,JJG,KKG)+VV(IIG-1,JJG,KKG)+VV(IIG,JJG-1,KKG)+VV(IIG-1,JJG-1,KKG))
            DWDX = -0.25_EB*RDX(IIG)*(WW(IIG,JJG,KKG)+WW(IIG-1,JJG,KKG)+WW(IIG,JJG,KKG-1)+WW(IIG-1,JJG,KKG-1))
         CASE(2)
            DUDY = 0.25_EB*RDY(JJG)*(UU(IIG,JJG,KKG)+UU(IIG,JJG+1,KKG)+UU(IIG-1,JJG,KKG)+UU(IIG-1,JJG+1,KKG))
            DWDY = 0.25_EB*RDY(JJG)*(WW(IIG,JJG,KKG)+WW(IIG,JJG+1,KKG)+WW(IIG,JJG,KKG-1)+WW(IIG,JJG+1,KKG-1))
         CASE(-2)
            DUDY = -0.25_EB*RDY(JJG)*(UU(IIG,JJG,KKG)+UU(IIG,JJG-1,KKG)+UU(IIG-1,JJG,KKG)+UU(IIG-1,JJG-1,KKG))
            DWDY = -0.25_EB*RDY(JJG)*(WW(IIG,JJG,KKG)+WW(IIG,JJG-1,KKG)+WW(IIG,JJG,KKG-1)+WW(IIG,JJG-1,KKG-1))
         CASE(3)
            DUDZ = 0.25_EB*RDZ(KKG)*(UU(IIG,JJG,KKG)+UU(IIG,JJG,KKG+1)+UU(IIG-1,JJG,KKG)+UU(IIG-1,JJG,KKG+1))
            DVDZ = 0.25_EB*RDZ(KKG)*(VV(IIG,JJG,KKG)+VV(IIG,JJG,KKG+1)+VV(IIG,JJG-1,KKG)+VV(IIG,JJG-1,KKG+1))
         CASE(-3)
            DUDZ = -0.25_EB*RDZ(KKG)*(UU(IIG,JJG,KKG)+UU(IIG,JJG,KKG-1)+UU(IIG-1,JJG,KKG)+UU(IIG-1,JJG,KKG-1))
            DVDZ = -0.25_EB*RDZ(KKG)*(VV(IIG,JJG,KKG)+VV(IIG,JJG,KKG-1)+VV(IIG,JJG-1,KKG)+VV(IIG,JJG-1,KKG-1))   
      END SELECT
   ENDIF FREE_SLIP_IF
   
   S12 = 0.5_EB*(DUDY+DVDX)
   S13 = 0.5_EB*(DUDZ+DWDX)
   S23 = 0.5_EB*(DVDZ+DWDY)
   
   STRAIN_RATE(IIG,JJG,KKG) = SQRT(2._EB*(S11**2 + S22**2 + S33**2 + 2._EB*(S12**2 + S13**2 + S23**2)))
ENDDO WALL_LOOP



END SUBROUTINE COMPUTE_STRAIN_RATE


SUBROUTINE VISCOSITY_BC(NM)

! Specify ghost cell values of the viscosity array MU

INTEGER, INTENT(IN) :: NM
REAL(EB) :: MU_OTHER,DP_OTHER,KRES_OTHER
INTEGER :: II,JJ,KK,IW,IIO,JJO,KKO,NOM,N_INT_CELLS
TYPE(WALL_TYPE),POINTER :: WC=>NULL()

CALL POINT_TO_MESH(NM)

! Mirror viscosity into solids and exterior boundary cells
 
!$OMP PARALLEL DO DEFAULT(NONE) SCHEDULE(STATIC) & 
!$OMP SHARED(N_EXTERNAL_WALL_CELLS,N_INTERNAL_WALL_CELLS,OMESH,PREDICTOR,MU,KRES,D,DS,WC,WALL) &
!$OMP PRIVATE(IW,II,JJ,KK,NOM,MU_OTHER,DP_OTHER,KRES_OTHER,KKO,JJO,IIO,N_INT_CELLS)
WALL_LOOP: DO IW=1,N_EXTERNAL_WALL_CELLS+N_INTERNAL_WALL_CELLS
   WC=>WALL(IW)
   IF (WC%NOM==0) CYCLE WALL_LOOP
   II  = WC%II
   JJ  = WC%JJ
   KK  = WC%KK
   NOM = WC%NOM
   MU_OTHER   = 0._EB
   DP_OTHER   = 0._EB
   KRES_OTHER = 0._EB
   DO KKO=WC%NOM_IB(3),WC%NOM_IB(6)
      DO JJO=WC%NOM_IB(2),WC%NOM_IB(5)
         DO IIO=WC%NOM_IB(1),WC%NOM_IB(4)
            MU_OTHER = MU_OTHER + OMESH(NOM)%MU(IIO,JJO,KKO)
            KRES_OTHER = KRES_OTHER + OMESH(NOM)%KRES(IIO,JJO,KKO)
            IF (PREDICTOR) THEN
               DP_OTHER = DP_OTHER + OMESH(NOM)%D(IIO,JJO,KKO)
            ELSE
               DP_OTHER = DP_OTHER + OMESH(NOM)%DS(IIO,JJO,KKO)
            ENDIF
         ENDDO
      ENDDO
   ENDDO
   N_INT_CELLS = (WC%NOM_IB(4)-WC%NOM_IB(1)+1) * (WC%NOM_IB(5)-WC%NOM_IB(2)+1) * (WC%NOM_IB(6)-WC%NOM_IB(3)+1)
   MU_OTHER = MU_OTHER/REAL(N_INT_CELLS,EB)
   KRES_OTHER = KRES_OTHER/REAL(N_INT_CELLS,EB)
   DP_OTHER = DP_OTHER/REAL(N_INT_CELLS,EB)
   MU(II,JJ,KK) = MU_OTHER
   KRES(II,JJ,KK) = KRES_OTHER
   IF (PREDICTOR) THEN
      D(II,JJ,KK) = DP_OTHER
   ELSE
      DS(II,JJ,KK) = DP_OTHER
   ENDIF
ENDDO WALL_LOOP
!$OMP END PARALLEL DO
    
END SUBROUTINE VISCOSITY_BC



SUBROUTINE VELOCITY_FLUX(T,NM)

! Compute convective and diffusive terms of the momentum equations

USE MATH_FUNCTIONS, ONLY: EVALUATE_RAMP
INTEGER, INTENT(IN) :: NM
REAL(EB) :: T,MUX,MUY,MUZ,UP,UM,VP,VM,WP,WM,VTRM,OMXP,OMXM,OMYP,OMYM,OMZP,OMZM,TXYP,TXYM,TXZP,TXZM,TYZP,TYZM, &
            DTXYDY,DTXZDZ,DTYZDZ,DTXYDX,DTXZDX,DTYZDY, &
            DUDX,DVDY,DWDZ,DUDY,DUDZ,DVDX,DVDZ,DWDX,DWDY, &
            VOMZ,WOMY,UOMY,VOMX,UOMZ,WOMX, &
            AH,RRHO,GX(0:IBAR_MAX),GY(0:IBAR_MAX),GZ(0:IBAR_MAX),TXXP,TXXM,TYYP,TYYM,TZZP,TZZM,DTXXDX,DTYYDY,DTZZDZ, &
            DUMMY=0._EB, &
            INTEGRAL,SUM_VOLUME,DVOLUME,UMEAN,VMEAN,WMEAN,DU_FORCING=0._EB,DV_FORCING=0._EB,DW_FORCING=0._EB
REAL(EB) :: VEG_UMAG
INTEGER :: I,J,K,IEXP,IEXM,IEYP,IEYM,IEZP,IEZM,IC,IC1,IC2,KKG
REAL(EB), POINTER, DIMENSION(:,:,:) :: TXY=>NULL(),TXZ=>NULL(),TYZ=>NULL(),OMX=>NULL(),OMY=>NULL(),OMZ=>NULL(), &
                                       UU=>NULL(),VV=>NULL(),WW=>NULL(),RHOP=>NULL(),DP=>NULL()
 
CALL POINT_TO_MESH(NM)
 
IF (PREDICTOR) THEN
   UU => U
   VV => V
   WW => W
   DP => D  
   RHOP => RHO
ELSE
   UU => US
   VV => VS
   WW => WS
   DP => DS
   RHOP => RHOS
ENDIF

TXY => WORK1
TXZ => WORK2
TYZ => WORK3
OMX => WORK4
OMY => WORK5
OMZ => WORK6

!$OMP PARALLEL DEFAULT(NONE) &
!$OMP SHARED(KBAR,JBAR,IBAR,RDXN,RDYN,RDZN,UU,VV,WW,OMX,OMY,OMZ,MU,TXY,TXZ,TYZ, &
!$OMP        IMMERSED_BOUNDARY_METHOD,IBM_SAVE1,IBM_SAVE2,IBM_SAVE3,IBM_SAVE4,IBM_SAVE5,IBM_SAVE6, &
!$OMP        SPATIAL_GRAVITY_VARIATION,GX,GY,GZ,T,DUMMY,I_RAMP_GX,I_RAMP_GY,I_RAMP_GZ,GVEC,X, &
!$OMP        CELL_INDEX,EDGE_INDEX,OME_E,TAU_E,RHOP,RHO_0,RDX,RDY,RDZ,DP,FVEC,FVX,FVY,FVZ, &
!$OMP        MEAN_FORCING,SOLID,U_MASK,V_MASK,W_MASK,DX,DY,DZ,DXN,DYN,DZN,INTEGRAL,SUM_VOLUME, &
!$OMP        DU_FORCING,DV_FORCING,DW_FORCING,RFAC_FORCING, &
!$OMP        U0,V0,W0,UMEAN,VMEAN,WMEAN,DT)

! Compute vorticity and stress tensor components

!$OMP DO COLLAPSE(3) SCHEDULE(STATIC) &
!$OMP PRIVATE(K,J,I,DUDY,DVDX,DUDZ,DWDX,DVDZ,DWDY,MUX,MUY,MUZ)
DO K=0,KBAR
   DO J=0,JBAR
      DO I=0,IBAR
         DUDY = RDYN(J)*(UU(I,J+1,K)-UU(I,J,K))
         DVDX = RDXN(I)*(VV(I+1,J,K)-VV(I,J,K))
         DUDZ = RDZN(K)*(UU(I,J,K+1)-UU(I,J,K))
         DWDX = RDXN(I)*(WW(I+1,J,K)-WW(I,J,K))
         DVDZ = RDZN(K)*(VV(I,J,K+1)-VV(I,J,K))
         DWDY = RDYN(J)*(WW(I,J+1,K)-WW(I,J,K))
         OMX(I,J,K) = DWDY - DVDZ
         OMY(I,J,K) = DUDZ - DWDX
         OMZ(I,J,K) = DVDX - DUDY
         MUX = 0.25_EB*(MU(I,J+1,K)+MU(I,J,K)+MU(I,J,K+1)+MU(I,J+1,K+1))
         MUY = 0.25_EB*(MU(I+1,J,K)+MU(I,J,K)+MU(I,J,K+1)+MU(I+1,J,K+1))
         MUZ = 0.25_EB*(MU(I+1,J,K)+MU(I,J,K)+MU(I,J+1,K)+MU(I+1,J+1,K))
         TXY(I,J,K) = MUZ*(DVDX + DUDY)
         TXZ(I,J,K) = MUY*(DUDZ + DWDX)
         TYZ(I,J,K) = MUX*(DVDZ + DWDY)
         
         IF (IMMERSED_BOUNDARY_METHOD==2) THEN
            IBM_SAVE1(I,J,K) = DUDY
            IBM_SAVE2(I,J,K) = DUDZ
            IBM_SAVE3(I,J,K) = DVDX
            IBM_SAVE4(I,J,K) = DVDZ
            IBM_SAVE5(I,J,K) = DWDX
            IBM_SAVE6(I,J,K) = DWDY
         ENDIF
         
      ENDDO
   ENDDO
ENDDO
!$OMP END DO NOWAIT

! Compute gravity components

!$OMP SINGLE PRIVATE(I)
IF (.NOT.SPATIAL_GRAVITY_VARIATION) THEN
   GX(0:IBAR) = EVALUATE_RAMP(T,DUMMY,I_RAMP_GX)*GVEC(1)
   GY(0:IBAR) = EVALUATE_RAMP(T,DUMMY,I_RAMP_GY)*GVEC(2)
   GZ(0:IBAR) = EVALUATE_RAMP(T,DUMMY,I_RAMP_GZ)*GVEC(3)
ELSE
   DO I=0,IBAR
      GX(I) = EVALUATE_RAMP(X(I),DUMMY,I_RAMP_GX)*GVEC(1)
      GY(I) = EVALUATE_RAMP(X(I),DUMMY,I_RAMP_GY)*GVEC(2)
      GZ(I) = EVALUATE_RAMP(X(I),DUMMY,I_RAMP_GZ)*GVEC(3)
   ENDDO
ENDIF
!$OMP END SINGLE
 
! Compute x-direction flux term FVX

!$OMP DO COLLAPSE(3) &
!$OMP PRIVATE(K,J,I,WP,WM,VP,VM,OMYP,OMYM,OMZP,OMZM,TXZP,TXZM,TXYP,TXYM,IC,IEYP,IEYM,IEZP,IEZM) &
!$OMP PRIVATE(WOMY,VOMZ,RRHO,AH,DVDY,DWDZ,TXXP,TXXM,DTXXDX,DTXYDY,DTXZDZ,VTRM)
DO K=1,KBAR
   DO J=1,JBAR
      DO I=0,IBAR
         WP    = WW(I,J,K)   + WW(I+1,J,K)
         WM    = WW(I,J,K-1) + WW(I+1,J,K-1)
         VP    = VV(I,J,K)   + VV(I+1,J,K)
         VM    = VV(I,J-1,K) + VV(I+1,J-1,K)
         OMYP  = OMY(I,J,K)
         OMYM  = OMY(I,J,K-1)
         OMZP  = OMZ(I,J,K)
         OMZM  = OMZ(I,J-1,K)
         TXZP  = TXZ(I,J,K)
         TXZM  = TXZ(I,J,K-1)
         TXYP  = TXY(I,J,K)
         TXYM  = TXY(I,J-1,K)
         IC    = CELL_INDEX(I,J,K)
         IEYP  = EDGE_INDEX(IC,8)
         IEYM  = EDGE_INDEX(IC,6)
         IEZP  = EDGE_INDEX(IC,12)
         IEZM  = EDGE_INDEX(IC,10)
         IF (OME_E(IEYP,-1)>-1.E5_EB) OMYP = OME_E(IEYP,-1)
         IF (OME_E(IEYM, 1)>-1.E5_EB) OMYM = OME_E(IEYM, 1)
         IF (OME_E(IEZP,-2)>-1.E5_EB) OMZP = OME_E(IEZP,-2)
         IF (OME_E(IEZM, 2)>-1.E5_EB) OMZM = OME_E(IEZM, 2)
         IF (TAU_E(IEYP,-1)>-1.E5_EB) TXZP = TAU_E(IEYP,-1)
         IF (TAU_E(IEYM, 1)>-1.E5_EB) TXZM = TAU_E(IEYM, 1)
         IF (TAU_E(IEZP,-2)>-1.E5_EB) TXYP = TAU_E(IEZP,-2)
         IF (TAU_E(IEZM, 2)>-1.E5_EB) TXYM = TAU_E(IEZM, 2)
         WOMY  = WP*OMYP + WM*OMYM
         VOMZ  = VP*OMZP + VM*OMZM
         RRHO  = 2._EB/(RHOP(I,J,K)+RHOP(I+1,J,K))
         AH    = RHO_0(K)*RRHO - 1._EB   
         DVDY  = (VV(I+1,J,K)-VV(I+1,J-1,K))*RDY(J)
         DWDZ  = (WW(I+1,J,K)-WW(I+1,J,K-1))*RDZ(K)
         TXXP  = MU(I+1,J,K)*( FOTH*DP(I+1,J,K) - 2._EB*(DVDY+DWDZ) )
         DVDY  = (VV(I,J,K)-VV(I,J-1,K))*RDY(J)
         DWDZ  = (WW(I,J,K)-WW(I,J,K-1))*RDZ(K)
         TXXM  = MU(I,J,K)  *( FOTH*DP(I,J,K)   - 2._EB*(DVDY+DWDZ) )
         DTXXDX= RDXN(I)*(TXXP-TXXM)
         DTXYDY= RDY(J) *(TXYP-TXYM)
         DTXZDZ= RDZ(K) *(TXZP-TXZM)
         VTRM  = RRHO*(DTXXDX + DTXYDY + DTXZDZ)
         FVX(I,J,K) = 0.25_EB*(WOMY - VOMZ) + GX(I)*AH - VTRM - RRHO*FVEC(1)
      ENDDO 
   ENDDO   
ENDDO
!$OMP END DO NOWAIT
 
! Compute y-direction flux term FVY

!$OMP DO COLLAPSE(3) &
!$OMP PRIVATE(K,J,I,UP,UM,WP,WM,OMXP,OMXM,OMZP,OMZM,TYZP,TYZM,TXYP,TXYM,IC,IEXP,IEXM,IEZP,IEZM) &
!$OMP PRIVATE(WOMX,UOMZ,RRHO,AH,DUDX,DWDZ,TYYP,TYYM,DTXYDX,DTYYDY,DTYZDZ,VTRM)
DO K=1,KBAR
   DO J=0,JBAR
      DO I=1,IBAR
         UP    = UU(I,J,K)   + UU(I,J+1,K)
         UM    = UU(I-1,J,K) + UU(I-1,J+1,K)
         WP    = WW(I,J,K)   + WW(I,J+1,K)
         WM    = WW(I,J,K-1) + WW(I,J+1,K-1)
         OMXP  = OMX(I,J,K)
         OMXM  = OMX(I,J,K-1)
         OMZP  = OMZ(I,J,K)
         OMZM  = OMZ(I-1,J,K)
         TYZP  = TYZ(I,J,K)
         TYZM  = TYZ(I,J,K-1)
         TXYP  = TXY(I,J,K)
         TXYM  = TXY(I-1,J,K)
         IC    = CELL_INDEX(I,J,K)
         IEXP  = EDGE_INDEX(IC,4)
         IEXM  = EDGE_INDEX(IC,2)
         IEZP  = EDGE_INDEX(IC,12)
         IEZM  = EDGE_INDEX(IC,11)
         IF (OME_E(IEXP,-2)>-1.E5_EB) OMXP = OME_E(IEXP,-2)
         IF (OME_E(IEXM, 2)>-1.E5_EB) OMXM = OME_E(IEXM, 2)
         IF (OME_E(IEZP,-1)>-1.E5_EB) OMZP = OME_E(IEZP,-1)
         IF (OME_E(IEZM, 1)>-1.E5_EB) OMZM = OME_E(IEZM, 1)
         IF (TAU_E(IEXP,-2)>-1.E5_EB) TYZP = TAU_E(IEXP,-2)
         IF (TAU_E(IEXM, 2)>-1.E5_EB) TYZM = TAU_E(IEXM, 2)
         IF (TAU_E(IEZP,-1)>-1.E5_EB) TXYP = TAU_E(IEZP,-1)
         IF (TAU_E(IEZM, 1)>-1.E5_EB) TXYM = TAU_E(IEZM, 1)
         WOMX  = WP*OMXP + WM*OMXM
         UOMZ  = UP*OMZP + UM*OMZM
         RRHO  = 2._EB/(RHOP(I,J,K)+RHOP(I,J+1,K))
         AH    = RHO_0(K)*RRHO - 1._EB
         DUDX  = (UU(I,J+1,K)-UU(I-1,J+1,K))*RDX(I)
         DWDZ  = (WW(I,J+1,K)-WW(I,J+1,K-1))*RDZ(K)
         TYYP  = MU(I,J+1,K)*( FOTH*DP(I,J+1,K) - 2._EB*(DUDX+DWDZ) )
         DUDX  = (UU(I,J,K)-UU(I-1,J,K))*RDX(I)
         DWDZ  = (WW(I,J,K)-WW(I,J,K-1))*RDZ(K)
         TYYM  = MU(I,J,K)  *( FOTH*DP(I,J,K)   - 2._EB*(DUDX+DWDZ) )
         DTXYDX= RDX(I) *(TXYP-TXYM)
         DTYYDY= RDYN(J)*(TYYP-TYYM)
         DTYZDZ= RDZ(K) *(TYZP-TYZM)
         VTRM  = RRHO*(DTXYDX + DTYYDY + DTYZDZ)
         FVY(I,J,K) = 0.25_EB*(UOMZ - WOMX) + GY(I)*AH - VTRM - RRHO*FVEC(2)
      ENDDO
   ENDDO   
ENDDO
!$OMP END DO NOWAIT
 
! Compute z-direction flux term FVZ

!$OMP DO COLLAPSE(3) &
!$OMP PRIVATE(K,J,I,UP,UM,VP,VM,OMYP,OMYM,OMXP,OMXM,TXZP,TXZM,TYZP,TYZM,IC,IEXP,IEXM,IEYP,IEYM) &
!$OMP PRIVATE(UOMY,VOMX,RRHO,AH,DUDX,DVDY,TZZP,TZZM,DTXZDX,DTYZDY,DTZZDZ,VTRM) 
DO K=0,KBAR
   DO J=1,JBAR
      DO I=1,IBAR
         UP    = UU(I,J,K)   + UU(I,J,K+1)
         UM    = UU(I-1,J,K) + UU(I-1,J,K+1)
         VP    = VV(I,J,K)   + VV(I,J,K+1)
         VM    = VV(I,J-1,K) + VV(I,J-1,K+1)
         OMYP  = OMY(I,J,K)
         OMYM  = OMY(I-1,J,K)
         OMXP  = OMX(I,J,K)
         OMXM  = OMX(I,J-1,K)
         TXZP  = TXZ(I,J,K)
         TXZM  = TXZ(I-1,J,K)
         TYZP  = TYZ(I,J,K)
         TYZM  = TYZ(I,J-1,K)
         IC    = CELL_INDEX(I,J,K)
         IEXP  = EDGE_INDEX(IC,4)
         IEXM  = EDGE_INDEX(IC,3)
         IEYP  = EDGE_INDEX(IC,8)
         IEYM  = EDGE_INDEX(IC,7)
         IF (OME_E(IEXP,-1)>-1.E5_EB) OMXP = OME_E(IEXP,-1)
         IF (OME_E(IEXM, 1)>-1.E5_EB) OMXM = OME_E(IEXM, 1)
         IF (OME_E(IEYP,-2)>-1.E5_EB) OMYP = OME_E(IEYP,-2)
         IF (OME_E(IEYM, 2)>-1.E5_EB) OMYM = OME_E(IEYM, 2)
         IF (TAU_E(IEXP,-1)>-1.E5_EB) TYZP = TAU_E(IEXP,-1)
         IF (TAU_E(IEXM, 1)>-1.E5_EB) TYZM = TAU_E(IEXM, 1)
         IF (TAU_E(IEYP,-2)>-1.E5_EB) TXZP = TAU_E(IEYP,-2)
         IF (TAU_E(IEYM, 2)>-1.E5_EB) TXZM = TAU_E(IEYM, 2)
         UOMY  = UP*OMYP + UM*OMYM
         VOMX  = VP*OMXP + VM*OMXM
         RRHO  = 2._EB/(RHOP(I,J,K)+RHOP(I,J,K+1))
         AH    = 0.5_EB*(RHO_0(K)+RHO_0(K+1))*RRHO - 1._EB
         DUDX  = (UU(I,J,K+1)-UU(I-1,J,K+1))*RDX(I)
         DVDY  = (VV(I,J,K+1)-VV(I,J-1,K+1))*RDY(J)
         TZZP  = MU(I,J,K+1)*( FOTH*DP(I,J,K+1) - 2._EB*(DUDX+DVDY) )
         DUDX  = (UU(I,J,K)-UU(I-1,J,K))*RDX(I)
         DVDY  = (VV(I,J,K)-VV(I,J-1,K))*RDY(J)
         TZZM  = MU(I,J,K)  *( FOTH*DP(I,J,K)   - 2._EB*(DUDX+DVDY) )
         DTXZDX= RDX(I) *(TXZP-TXZM)
         DTYZDY= RDY(J) *(TYZP-TYZM)
         DTZZDZ= RDZN(K)*(TZZP-TZZM)
         VTRM  = RRHO*(DTXZDX + DTYZDY + DTZZDZ)
         FVZ(I,J,K) = 0.25_EB*(VOMX - UOMY) + GZ(I)*AH - VTRM - RRHO*FVEC(3)
      ENDDO
   ENDDO   
ENDDO
!$OMP END DO NOWAIT

! Mean forcing

MEAN_FORCING_X: IF (MEAN_FORCING(1)) THEN
   !$OMP SINGLE
   INTEGRAL = 0._EB
   SUM_VOLUME = 0._EB
   !$OMP END SINGLE
   !$OMP DO COLLAPSE(3) SCHEDULE(STATIC) &
   !$OMP PRIVATE(K,J,I,IC1,IC2,DVOLUME) REDUCTION(+:INTEGRAL,SUM_VOLUME)
   DO K=1,KBAR
      DO J=1,JBAR
         DO I=0,IBAR
            IC1 = CELL_INDEX(I,J,K)
            IC2 = CELL_INDEX(I+1,J,K)
            IF (SOLID(IC1) .OR. SOLID(IC2)) CYCLE
            IF (IMMERSED_BOUNDARY_METHOD>0 .AND. U_MASK(I,J,K)==-1) CYCLE
            DVOLUME = DXN(I)*DY(J)*DZ(K)
            INTEGRAL = INTEGRAL + UU(I,J,K)*DVOLUME
            SUM_VOLUME = SUM_VOLUME + DVOLUME
         ENDDO
      ENDDO
   ENDDO
   !$OMP END DO
   !$OMP SINGLE
   UMEAN = INTEGRAL/SUM_VOLUME
   DU_FORCING = RFAC_FORCING(1)*(U0-UMEAN)/DT
   !$OMP END SINGLE
   !$OMP WORKSHARE
   FVX = FVX-DU_FORCING
   !$OMP END WORKSHARE NOWAIT
ENDIF MEAN_FORCING_X
   
MEAN_FORCING_Y: IF (MEAN_FORCING(2)) THEN
   !$OMP SINGLE
   INTEGRAL = 0._EB
   SUM_VOLUME = 0._EB
   !$OMP END SINGLE
   !$OMP DO COLLAPSE(3) SCHEDULE(STATIC) &
   !$OMP PRIVATE(K,J,I,IC1,IC2,DVOLUME) REDUCTION(+:INTEGRAL,SUM_VOLUME)  
   DO K=1,KBAR
      DO J=0,JBAR
         DO I=1,IBAR
            IC1 = CELL_INDEX(I,J,K)
            IC2 = CELL_INDEX(I,J+1,K)
            IF (SOLID(IC1) .OR. SOLID(IC2)) CYCLE
            IF (IMMERSED_BOUNDARY_METHOD>0 .AND. V_MASK(I,J,K)==-1) CYCLE
            DVOLUME = DX(I)*DYN(J)*DZ(K)
            INTEGRAL = INTEGRAL + VV(I,J,K)*DVOLUME
            SUM_VOLUME = SUM_VOLUME + DVOLUME
         ENDDO
      ENDDO
   ENDDO
   !$OMP END DO
   !$OMP SINGLE
   VMEAN = INTEGRAL/SUM_VOLUME
   DV_FORCING = RFAC_FORCING(2)*(V0-VMEAN)/DT
   !$OMP END SINGLE
   !$OMP WORKSHARE
   FVY=FVY-DV_FORCING
   !$OMP END WORKSHARE NOWAIT
ENDIF MEAN_FORCING_Y
   
MEAN_FORCING_Z: IF (MEAN_FORCING(3)) THEN
   !$OMP SINGLE
   INTEGRAL = 0._EB
   SUM_VOLUME = 0._EB
   !$OMP END SINGLE
   !$OMP DO COLLAPSE(3) SCHEDULE(STATIC) &
   !$OMP PRIVATE(K,J,I,IC1,IC2,DVOLUME) REDUCTION(+:INTEGRAL,SUM_VOLUME)
   DO K=0,KBAR
      DO J=1,JBAR
         DO I=1,IBAR
            IC1 = CELL_INDEX(I,J,K)
            IC2 = CELL_INDEX(I,J,K+1)
            IF (SOLID(IC1) .OR. SOLID(IC2)) CYCLE
            IF (IMMERSED_BOUNDARY_METHOD>0 .AND. W_MASK(I,J,K)==-1) CYCLE
            DVOLUME = DX(I)*DY(J)*DZN(K)
            INTEGRAL = INTEGRAL + WW(I,J,K)*DVOLUME
            SUM_VOLUME = SUM_VOLUME + DVOLUME
         ENDDO
      ENDDO
   ENDDO
   !$OMP END DO
   !$OMP SINGLE
   WMEAN = INTEGRAL/SUM_VOLUME
   DW_FORCING = RFAC_FORCING(3)*(W0-WMEAN)/DT
   !$OMP END SINGLE
   !$OMP WORKSHARE
   FVZ=FVZ-DW_FORCING
   !$OMP END WORKSHARE NOWAIT
ENDIF MEAN_FORCING_Z
!$OMP END PARALLEL


! Surface vegetation drag (NEED TO ADJUST THIS TO HANDLE TERRAIN)

WFDS_BNDRYFUEL_IF: IF (WFDS_BNDRYFUEL .OR. VEG_LEVEL_SET_COUPLED) THEN
 DO K=1,MIN(8,KBAR)
   DO J=1,JBAR
      DO I=0,IBAR
         IF (VEG_DRAG(I,J,0) == -1._EB) CYCLE
         KKG = INT(VEG_DRAG(I,J,0))+K-1
         VEG_UMAG = SQRT(UU(I,J,KKG)**2 + VV(I,J,KKG)**2 + WW(I,J,KKG)**2) ! VEG_UMAG=KRES(I,J,K)
         FVX(I,J,KKG) = FVX(I,J,KKG) + VEG_DRAG(I,J,K)*VEG_UMAG*UU(I,J,KKG)
      ENDDO
   ENDDO

   DO J=0,JBAR
      DO I=1,IBAR
         IF (VEG_DRAG(I,J,0) == -1._EB) CYCLE
         KKG = INT(VEG_DRAG(I,J,0))+K-1
         VEG_UMAG = SQRT(UU(I,J,KKG)**2 + VV(I,J,KKG)**2 + WW(I,J,KKG)**2)
         FVY(I,J,KKG) = FVY(I,J,KKG) + VEG_DRAG(I,J,K)*VEG_UMAG*VV(I,J,KKG)
      ENDDO
   ENDDO

   DO J=1,JBAR
      DO I=1,IBAR
         IF (VEG_DRAG(I,J,0) == -1._EB) CYCLE
         KKG = INT(VEG_DRAG(I,J,0))+K-1
         VEG_UMAG = SQRT(UU(I,J,KKG)**2 + VV(I,J,KKG)**2 + WW(I,J,KKG)**2)
         FVZ(I,J,KKG) = FVZ(I,J,KKG) + VEG_DRAG(I,J,K)*VEG_UMAG*WW(I,J,KKG)
      ENDDO
   ENDDO

 ENDDO
ENDIF WFDS_BNDRYFUEL_IF

! Baroclinic torque correction
 
IF (BAROCLINIC .AND. .NOT.EVACUATION_ONLY(NM)) CALL BAROCLINIC_CORRECTION(T)

! Specified patch velocity

IF (PATCH_VELOCITY) CALL PATCH_VELOCITY_FLUX

! Adjust FVX, FVY and FVZ at solid, internal obstructions for no flux

CALL NO_FLUX(NM)
IF (IMMERSED_BOUNDARY_METHOD>=0) CALL IBM_VELOCITY_FLUX(NM)
IF (EVACUATION_ONLY(NM)) FVZ = 0._EB

END SUBROUTINE VELOCITY_FLUX



SUBROUTINE VELOCITY_FLUX_CYLINDRICAL(T,NM)

! Compute convective and diffusive terms for 2D axisymmetric

USE MATH_FUNCTIONS, ONLY: EVALUATE_RAMP 
REAL(EB) :: T,DMUDX
INTEGER :: I0
INTEGER, INTENT(IN) :: NM
REAL(EB) :: MUY,UP,UM,WP,WM,VTRM,DTXZDZ,DTXZDX,DUDX,DWDZ,DUDZ,DWDX,WOMY,UOMY,OMYP,OMYM,TXZP,TXZM, &
            AH,RRHO,GX,GZ,TXXP,TXXM,TZZP,TZZM,DTXXDX,DTZZDZ,DUMMY=0._EB
INTEGER :: I,J,K,IEYP,IEYM,IC
REAL(EB), POINTER, DIMENSION(:,:,:) :: TXZ=>NULL(),OMY=>NULL(),UU=>NULL(),WW=>NULL(),RHOP=>NULL(),DP=>NULL()
 
CALL POINT_TO_MESH(NM)
 
IF (PREDICTOR) THEN
   UU => U
   WW => W
   DP => D  
   RHOP => RHO
ELSE
   UU => US
   WW => WS
   DP => DS
   RHOP => RHOS
ENDIF
 
TXZ => WORK2
OMY => WORK5
 
! Compute vorticity and stress tensor components

!$OMP PARALLEL DEFAULT(NONE) &
!$OMP SHARED(KBAR,JBAR,IBAR,RDZN,RDXN,UU,WW,OMY,MU,TXZ, &
!$OMP        GX,GZ,XS,T,DUMMY,I_RAMP_GZ,GVEC,I0,J, &
!$OMP        CELL_INDEX,EDGE_INDEX,OME_E,TAU_E,RHOP,RHO_0,RDX,RDZ,DP,R,FVX,FVZ,RRN)

!$OMP DO COLLAPSE(3) SCHEDULE(STATIC) &
!$OMP PRIVATE(K,J,I,DUDZ,DWDX,MUY)  
DO K=0,KBAR
   DO J=0,JBAR
      DO I=0,IBAR
         DUDZ = RDZN(K)*(UU(I,J,K+1)-UU(I,J,K))
         DWDX = RDXN(I)*(WW(I+1,J,K)-WW(I,J,K))
         OMY(I,J,K) = DUDZ - DWDX
         MUY = 0.25_EB*(MU(I+1,J,K)+MU(I,J,K)+MU(I,J,K+1)+MU(I+1,J,K+1))
         TXZ(I,J,K) = MUY*(DUDZ + DWDX)
      ENDDO
   ENDDO
ENDDO
!$OMP END DO NOWAIT
 
! Compute gravity components

!$OMP SINGLE
GX  = 0._EB
GZ  = EVALUATE_RAMP(T,DUMMY,I_RAMP_GZ)*GVEC(3)
 
! Compute r-direction flux term FVX
 
IF (ABS(XS)<=ZERO_P) THEN 
   I0 = 1
ELSE
   I0 = 0
ENDIF
 
J = 1
!$OMP END SINGLE


!$OMP DO COLLAPSE(2) SCHEDULE(STATIC) &
!$OMP PRIVATE(K,I,WP,WM,OMYP,OMYM,TXZP,TXZM,IC,IEYP,IEYM,WOMY,RRHO,AH,DWDZ,TXXP,TXXM,DTXXDX,DTXZDZ,DMUDX,VTRM) 
DO K= 1,KBAR
   DO I=I0,IBAR
      WP    = WW(I,J,K)   + WW(I+1,J,K)
      WM    = WW(I,J,K-1) + WW(I+1,J,K-1)
      OMYP  = OMY(I,J,K)
      OMYM  = OMY(I,J,K-1)
      TXZP  = TXZ(I,J,K)
      TXZM  = TXZ(I,J,K-1)
      IC    = CELL_INDEX(I,J,K)
      IEYP  = EDGE_INDEX(IC,8)
      IEYM  = EDGE_INDEX(IC,6)
      IF (OME_E(IEYP,-1)>-1.E5_EB) OMYP = OME_E(IEYP,-1)
      IF (OME_E(IEYM, 1)>-1.E5_EB) OMYM = OME_E(IEYM, 1)
      IF (TAU_E(IEYP,-1)>-1.E5_EB) TXZP = TAU_E(IEYP,-1)
      IF (TAU_E(IEYM, 1)>-1.E5_EB) TXZM = TAU_E(IEYM, 1)
      WOMY  = WP*OMYP + WM*OMYM
      RRHO  = 2._EB/(RHOP(I,J,K)+RHOP(I+1,J,K))
      AH    = RHO_0(K)*RRHO - 1._EB   
      DWDZ  = (WW(I+1,J,K)-WW(I+1,J,K-1))*RDZ(K)
      TXXP  = MU(I+1,J,K)*( FOTH*DP(I+1,J,K) - 2._EB*DWDZ )
      DWDZ  = (WW(I,J,K)-WW(I,J,K-1))*RDZ(K)
      TXXM  = MU(I,J,K)  *( FOTH*DP(I,J,K) -2._EB*DWDZ )
      DTXXDX= RDXN(I)*(TXXP-TXXM)
      DTXZDZ= RDZ(K) *(TXZP-TXZM)
      DMUDX = (MU(I+1,J,K)-MU(I,J,K))*RDXN(I)
      VTRM  = RRHO*( DTXXDX + DTXZDZ - 2._EB*UU(I,J,K)*DMUDX/R(I) ) 
      FVX(I,J,K) = 0.25_EB*WOMY + GX*AH - VTRM 
   ENDDO
ENDDO
!$OMP END DO NOWAIT

! Compute z-direction flux term FVZ
 
!$OMP DO COLLAPSE(2) SCHEDULE(STATIC) &
!$OMP PRIVATE(K,I,UP,UM,OMYP,OMYM,TXZP,TXZM,IC,IEYP,IEYM,UOMY,RRHO,AH,DUDX,TZZP,TZZM,DTXZDX,DTZZDZ,VTRM)
DO K=0,KBAR
   DO I=1,IBAR
      UP    = UU(I,J,K)   + UU(I,J,K+1)
      UM    = UU(I-1,J,K) + UU(I-1,J,K+1)
      OMYP  = OMY(I,J,K)
      OMYM  = OMY(I-1,J,K)
      TXZP  = TXZ(I,J,K)
      TXZM  = TXZ(I-1,J,K)
      IC    = CELL_INDEX(I,J,K)
      IEYP  = EDGE_INDEX(IC,8)
      IEYM  = EDGE_INDEX(IC,7)
      IF (OME_E(IEYP,-2)>-1.E5_EB) OMYP = OME_E(IEYP,-2)
      IF (OME_E(IEYM, 2)>-1.E5_EB) OMYM = OME_E(IEYM, 2)
      IF (TAU_E(IEYP,-2)>-1.E5_EB) TXZP = TAU_E(IEYP,-2)
      IF (TAU_E(IEYM, 2)>-1.E5_EB) TXZM = TAU_E(IEYM, 2)
      UOMY  = UP*OMYP + UM*OMYM
      RRHO  = 2._EB/(RHOP(I,J,K)+RHOP(I,J,K+1))
      AH    = 0.5_EB*(RHO_0(K)+RHO_0(K+1))*RRHO - 1._EB
      DUDX  = (R(I)*UU(I,J,K+1)-R(I-1)*UU(I-1,J,K+1))*RDX(I)*RRN(I)
      TZZP  = MU(I,J,K+1)*( FOTH*DP(I,J,K+1) - 2._EB*DUDX )
      DUDX  = (R(I)*UU(I,J,K)-R(I-1)*UU(I-1,J,K))*RDX(I)*RRN(I)
      TZZM  = MU(I,J,K)  *( FOTH*DP(I,J,K)   - 2._EB*DUDX )
      DTXZDX= RDX(I) *(R(I)*TXZP-R(I-1)*TXZM)*RRN(I)
      DTZZDZ= RDZN(K)*(     TZZP       -TZZM)
      VTRM  = RRHO*(DTXZDX + DTZZDZ)
      FVZ(I,J,K) = -0.25_EB*UOMY + GZ*AH - VTRM 
   ENDDO
ENDDO
!$OMP END DO NOWAIT
!$OMP END PARALLEL   
 
! Baroclinic torque correction terms
 
IF (BAROCLINIC) CALL BAROCLINIC_CORRECTION(T)
 
! Adjust FVX and FVZ at solid, internal obstructions for no flux
 
CALL NO_FLUX(NM)
 
END SUBROUTINE VELOCITY_FLUX_CYLINDRICAL
 
 
SUBROUTINE NO_FLUX(NM)

! Set FVX,FVY,FVZ inside and on the surface of solid obstructions to maintain no flux

USE MATH_FUNCTIONS, ONLY: EVALUATE_RAMP 
INTEGER, INTENT(IN) :: NM
REAL(EB), POINTER, DIMENSION(:,:,:) :: HP=>NULL()
REAL(EB) :: RFODT,H_OTHER,DUUDT,DVVDT,DWWDT
INTEGER  :: IC2,IC1,N,I,J,K,IW,II,JJ,KK,IOR,N_INT_CELLS,IIO,JJO,KKO,NOM
TYPE (OBSTRUCTION_TYPE), POINTER :: OB=>NULL()
TYPE (WALL_TYPE), POINTER :: WC=>NULL()

CALL POINT_TO_MESH(NM)
 
RFODT = RELAXATION_FACTOR/DT

IF (PREDICTOR) HP => H
IF (CORRECTOR) HP => HS
 
! Exchange H at interpolated boundaries

!$OMP PARALLEL DEFAULT(NONE) &
!$OMP SHARED(PRES_METHOD,N_EXTERNAL_WALL_CELLS,PREDICTOR,CORRECTOR,OMESH,H,HS, &
!$OMP        N_OBST,OBSTRUCTION,CELL_INDEX,SOLID,RFODT,U,V,W,US,VS,WS,FVX,FVY,FVZ,RDXN,RDYN,RDZN,HP, &
!$OMP        N_INTERNAL_WALL_CELLS,WC,WALL)

NO_SCARC_IF: IF (PRES_METHOD /= 'SCARC') THEN
   !$OMP DO SCHEDULE(STATIC) PRIVATE(IW,NOM,II,JJ,KK,H_OTHER,KKO,JJO,IIO,N_INT_CELLS)
   DO IW=1,N_EXTERNAL_WALL_CELLS
      WC=>WALL(IW)
      NOM =WC%NOM
      IF (NOM==0) CYCLE
      II = WC%II
      JJ = WC%JJ
      KK = WC%KK
      H_OTHER = 0._EB
      DO KKO=WC%NOM_IB(3),WC%NOM_IB(6)
         DO JJO=WC%NOM_IB(2),WC%NOM_IB(5)
            DO IIO=WC%NOM_IB(1),WC%NOM_IB(4)
               IF (PREDICTOR) H_OTHER = H_OTHER + OMESH(NOM)%H(IIO,JJO,KKO)
               IF (CORRECTOR) H_OTHER = H_OTHER + OMESH(NOM)%HS(IIO,JJO,KKO)
            ENDDO
         ENDDO
      ENDDO
      N_INT_CELLS = (WC%NOM_IB(4)-WC%NOM_IB(1)+1) * (WC%NOM_IB(5)-WC%NOM_IB(2)+1) * (WC%NOM_IB(6)-WC%NOM_IB(3)+1)
      IF (PREDICTOR) H(II,JJ,KK)  = H_OTHER/REAL(N_INT_CELLS,EB)
      IF (CORRECTOR) HS(II,JJ,KK) = H_OTHER/REAL(N_INT_CELLS,EB)
   ENDDO
   !$OMP END DO NOWAIT
ENDIF NO_SCARC_IF

! Set FVX, FVY and FVZ to drive velocity components at solid boundaries towards zero

!$OMP DO SCHEDULE(STATIC) PRIVATE(N,OB,K,J,I,IC1,IC2,DUUDT,DVVDT,DWWDT) 
OBST_LOOP: DO N=1,N_OBST
   OB=>OBSTRUCTION(N)
   DO K=OB%K1+1,OB%K2
      DO J=OB%J1+1,OB%J2
         LOOP1: DO I=OB%I1  ,OB%I2
            IC1 = CELL_INDEX(I,J,K)
            IC2 = CELL_INDEX(I+1,J,K)
            IF (SOLID(IC1) .AND. SOLID(IC2)) THEN
               IF (PREDICTOR) DUUDT = -RFODT*U(I,J,K)
               IF (CORRECTOR) DUUDT = -RFODT*(U(I,J,K)+US(I,J,K))
               FVX(I,J,K) = -RDXN(I)*(HP(I+1,J,K)-HP(I,J,K)) - DUUDT
            ENDIF
         ENDDO LOOP1
      ENDDO 
   ENDDO 
   DO K=OB%K1+1,OB%K2
      DO J=OB%J1  ,OB%J2
         LOOP2: DO I=OB%I1+1,OB%I2
            IC1 = CELL_INDEX(I,J,K)
            IC2 = CELL_INDEX(I,J+1,K)
            IF (SOLID(IC1) .AND. SOLID(IC2)) THEN
               IF (PREDICTOR) DVVDT = -RFODT*V(I,J,K)
               IF (CORRECTOR) DVVDT = -RFODT*(V(I,J,K)+VS(I,J,K))
               FVY(I,J,K) = -RDYN(J)*(HP(I,J+1,K)-HP(I,J,K)) - DVVDT
            ENDIF
         ENDDO LOOP2
      ENDDO 
   ENDDO 
   DO K=OB%K1  ,OB%K2
      DO J=OB%J1+1,OB%J2
         LOOP3: DO I=OB%I1+1,OB%I2
            IC1 = CELL_INDEX(I,J,K)
            IC2 = CELL_INDEX(I,J,K+1)
            IF (SOLID(IC1) .AND. SOLID(IC2)) THEN
               IF (PREDICTOR) DWWDT = -RFODT*W(I,J,K)
               IF (CORRECTOR) DWWDT = -RFODT*(W(I,J,K)+WS(I,J,K))
               FVZ(I,J,K) = -RDZN(K)*(HP(I,J,K+1)-HP(I,J,K)) - DWWDT
            ENDIF
         ENDDO LOOP3
      ENDDO 
   ENDDO 
ENDDO OBST_LOOP
!$OMP END DO
 
! Add normal velocity to FVX, etc. for surface cells

!$OMP DO SCHEDULE(STATIC) PRIVATE(IW,NOM,II,JJ,KK,IOR,DUUDT,DVVDT,DWWDT) 
WALL_LOOP: DO IW=1,N_EXTERNAL_WALL_CELLS+N_INTERNAL_WALL_CELLS
   WC => WALL(IW)
   !!IF (BOUNDARY_TYPE(IW)==OPEN_BOUNDARY)         CYCLE WALL_LOOP ! testing new boundary forcing
   IF (WC%BOUNDARY_TYPE==INTERPOLATED_BOUNDARY) CYCLE WALL_LOOP
   NOM = WC%NOM
   IF (WC%BOUNDARY_TYPE==NULL_BOUNDARY .AND. NOM==0) CYCLE WALL_LOOP

   II  = WC%II
   JJ  = WC%JJ
   KK  = WC%KK
   IOR = WC%IOR
    
   IF (NOM/=0 .OR. WC%BOUNDARY_TYPE==SOLID_BOUNDARY) THEN
      SELECT CASE(IOR)
         CASE( 1) 
            IF (PREDICTOR) DUUDT =       RFODT*(-WC%UWS-U(II,JJ,KK))
            IF (CORRECTOR) DUUDT = 2._EB*RFODT*(-WC%UW-0.5_EB*(U(II,JJ,KK)+US(II,JJ,KK)))
            FVX(II,JJ,KK) =   -RDXN(II)  *(HP(II+1,JJ,KK)-HP(II,JJ,KK)) - DUUDT
         CASE(-1) 
            IF (PREDICTOR) DUUDT =       RFODT*( WC%UWS-U(II-1,JJ,KK))
            IF (CORRECTOR) DUUDT = 2._EB*RFODT*( WC%UW-0.5_EB*(U(II-1,JJ,KK)+US(II-1,JJ,KK)))
            FVX(II-1,JJ,KK) = -RDXN(II-1)*(HP(II,JJ,KK)-HP(II-1,JJ,KK)) - DUUDT
         CASE( 2) 
            IF (PREDICTOR) DVVDT =       RFODT*(-WC%UWS-V(II,JJ,KK))
            IF (CORRECTOR) DVVDT = 2._EB*RFODT*(-WC%UW-0.5_EB*(V(II,JJ,KK)+VS(II,JJ,KK)))
            FVY(II,JJ,KK)   = -RDYN(JJ)  *(HP(II,JJ+1,KK)-HP(II,JJ,KK)) - DVVDT
         CASE(-2)
            IF (PREDICTOR) DVVDT =       RFODT*( WC%UWS-V(II,JJ-1,KK))
            IF (CORRECTOR) DVVDT = 2._EB*RFODT*( WC%UW-0.5_EB*(V(II,JJ-1,KK)+VS(II,JJ-1,KK)))
            FVY(II,JJ-1,KK) = -RDYN(JJ-1)*(HP(II,JJ,KK)-HP(II,JJ-1,KK)) - DVVDT
         CASE( 3) 
            IF (PREDICTOR) DWWDT =       RFODT*(-WC%UWS-W(II,JJ,KK))
            IF (CORRECTOR) DWWDT = 2._EB*RFODT*(-WC%UW-0.5_EB*(W(II,JJ,KK)+WS(II,JJ,KK)))
            FVZ(II,JJ,KK)   = -RDZN(KK)  *(HP(II,JJ,KK+1)-HP(II,JJ,KK)) - DWWDT
         CASE(-3) 
            IF (PREDICTOR) DWWDT =       RFODT*( WC%UWS-W(II,JJ,KK-1))
            IF (CORRECTOR) DWWDT = 2._EB*RFODT*( WC%UW-0.5_EB*(W(II,JJ,KK-1)+WS(II,JJ,KK-1)))
            FVZ(II,JJ,KK-1) = -RDZN(KK-1)*(HP(II,JJ,KK)-HP(II,JJ,KK-1)) - DWWDT
      END SELECT
   ENDIF

   IF (WC%BOUNDARY_TYPE==MIRROR_BOUNDARY) THEN
      SELECT CASE(IOR)
         CASE( 1)
            FVX(II  ,JJ,KK) = 0._EB
         CASE(-1)
            FVX(II-1,JJ,KK) = 0._EB
         CASE( 2)
            FVY(II  ,JJ,KK) = 0._EB
         CASE(-2)
            FVY(II,JJ-1,KK) = 0._EB
         CASE( 3)
            FVZ(II  ,JJ,KK) = 0._EB
         CASE(-3)
            FVZ(II,JJ,KK-1) = 0._EB
      END SELECT
   ENDIF
   
ENDDO WALL_LOOP
!$OMP END DO NOWAIT
!$OMP END PARALLEL
 
END SUBROUTINE NO_FLUX
 
 

SUBROUTINE VELOCITY_PREDICTOR(T,NM,STOP_STATUS)

USE TURBULENCE, ONLY: COMPRESSION_WAVE

! Estimates the velocity components at the next time step

REAL(EB) :: TNOW
INTEGER  :: STOP_STATUS,I,J,K
INTEGER, INTENT(IN) :: NM
REAL(EB), INTENT(IN) :: T

IF (SOLID_PHASE_ONLY) RETURN
IF (VEG_LEVEL_SET_UNCOUPLED) RETURN
IF (PERIODIC_TEST==4) THEN
   CALL COMPRESSION_WAVE(NM,T,4)
   CALL CHECK_STABILITY(NM,2)
   RETURN
ENDIF

TNOW=SECOND() 
CALL POINT_TO_MESH(NM)

FREEZE_VELOCITY_IF: IF (FREEZE_VELOCITY) THEN
   US = U
   VS = V
   WS = W
ELSE FREEZE_VELOCITY_IF

!$OMP PARALLEL DEFAULT(NONE) &
!$OMP SHARED(KBAR,IBAR,JBAR,US,VS,WS,U,V,W,DT,FVX,FVY,FVZ,RDXN,RDYN,RDZN,H,KRES)

!$OMP DO COLLAPSE(3) SCHEDULE(STATIC) PRIVATE(K,J,I)
DO K=1,KBAR
   DO J=1,JBAR
      DO I=0,IBAR
         US(I,J,K) = U(I,J,K) - DT*( FVX(I,J,K) + RDXN(I)*(H(I+1,J,K)-H(I,J,K)) )
      ENDDO
   ENDDO
ENDDO
!$OMP END DO NOWAIT

!$OMP DO COLLAPSE(3) SCHEDULE(STATIC) PRIVATE(K,J,I)
DO K=1,KBAR
   DO J=0,JBAR
      DO I=1,IBAR
         VS(I,J,K) = V(I,J,K) - DT*( FVY(I,J,K) + RDYN(J)*(H(I,J+1,K)-H(I,J,K)) )
      ENDDO
   ENDDO
ENDDO
!$OMP END DO NOWAIT

!$OMP DO COLLAPSE(3) SCHEDULE(STATIC) PRIVATE(K,J,I)
DO K=0,KBAR
   DO J=1,JBAR
      DO I=1,IBAR
         WS(I,J,K) = W(I,J,K) - DT*( FVZ(I,J,K) + RDZN(K)*(H(I,J,K+1)-H(I,J,K)) )
      ENDDO
   ENDDO
ENDDO
!$OMP END DO
!$OMP END PARALLEL

ENDIF FREEZE_VELOCITY_IF

! No vertical velocity in Evacuation meshes

IF (EVACUATION_ONLY(NM)) WS = 0._EB

! Check the stability criteria, and if the time step is too small, send back a signal to kill the job
 
DT_PREV = DT
CALL CHECK_STABILITY(NM,2)
 
IF (DT<DT_INIT*LIMITING_DT_RATIO) STOP_STATUS = INSTABILITY_STOP
 
TUSED(4,NM)=TUSED(4,NM)+SECOND()-TNOW
END SUBROUTINE VELOCITY_PREDICTOR
 
 

SUBROUTINE VELOCITY_CORRECTOR(T,NM)

USE TURBULENCE, ONLY: COMPRESSION_WAVE

! Correct the velocity components

REAL(EB) :: TNOW
INTEGER  :: I,J,K
INTEGER, INTENT(IN) :: NM
REAL(EB), INTENT(IN) :: T
 
IF (SOLID_PHASE_ONLY) RETURN
IF (VEG_LEVEL_SET_UNCOUPLED) RETURN
IF (PERIODIC_TEST==4) THEN
   CALL COMPRESSION_WAVE(NM,T,4)
   RETURN
ENDIF

TNOW=SECOND() 
CALL POINT_TO_MESH(NM)

FREEZE_VELOCITY_IF: IF (FREEZE_VELOCITY) THEN
   U = US
   V = VS
   W = WS
ELSE FREEZE_VELOCITY_IF

!$OMP PARALLEL DEFAULT(NONE) &
!$OMP SHARED(KBAR,JBAR,IBAR,U,V,W,US,VS,WS,DT,FVX,FVY,FVZ,RDXN,RDYN,RDZN,HS,KRES)

!$OMP DO COLLAPSE(3) SCHEDULE(STATIC) PRIVATE(K,J,I)
DO K=1,KBAR
   DO J=1,JBAR
      DO I=0,IBAR
         U(I,J,K) = 0.5_EB*( U(I,J,K) + US(I,J,K) - DT*(FVX(I,J,K) + RDXN(I)*(HS(I+1,J,K)-HS(I,J,K))) )
      ENDDO
   ENDDO
ENDDO
!$OMP END DO NOWAIT

!$OMP DO COLLAPSE(3) SCHEDULE(STATIC) PRIVATE(K,J,I)
DO K=1,KBAR
   DO J=0,JBAR
      DO I=1,IBAR
         V(I,J,K) = 0.5_EB*( V(I,J,K) + VS(I,J,K) - DT*(FVY(I,J,K) + RDYN(J)*(HS(I,J+1,K)-HS(I,J,K))) )
      ENDDO
   ENDDO
ENDDO
!$OMP END DO NOWAIT

!$OMP DO COLLAPSE(3) SCHEDULE(STATIC) PRIVATE(K,J,I)
DO K=0,KBAR
   DO J=1,JBAR
      DO I=1,IBAR
         W(I,J,K) = 0.5_EB*( W(I,J,K) + WS(I,J,K) - DT*(FVZ(I,J,K) + RDZN(K)*(HS(I,J,K+1)-HS(I,J,K))) )
      ENDDO
   ENDDO
ENDDO
!$OMP END DO
!$OMP END PARALLEL

ENDIF FREEZE_VELOCITY_IF

! No vertical velocity in Evacuation meshes

IF (EVACUATION_ONLY(NM)) W = 0._EB

TUSED(4,NM)=TUSED(4,NM)+SECOND()-TNOW
END SUBROUTINE VELOCITY_CORRECTOR
 

 
SUBROUTINE VELOCITY_BC(T,NM)

! Assert tangential velocity boundary conditions

USE MATH_FUNCTIONS, ONLY: EVALUATE_RAMP
USE TURBULENCE, ONLY: WERNER_WENGLE_WALL_MODEL
REAL(EB), INTENT(IN) :: T
REAL(EB) :: MUA,TSI,WGT,TNOW,RAMP_T,OMW,MU_WALL,RHO_WALL,SLIP_COEF,VEL_T, &
            UUP(2),UUM(2),DXX(2),MU_DUIDXJ(-2:2),DUIDXJ(-2:2),MU_DUIDXJ_0(2),DUIDXJ_0(2),PROFILE_FACTOR,VEL_GAS,VEL_GHOST, &
            MU_DUIDXJ_USE(2),DUIDXJ_USE(2),DUMMY,VEL_EDDY
INTEGER  :: I,J,K,NOM(2),IIO(2),JJO(2),KKO(2),IE,II,JJ,KK,IEC,IOR,IWM,IWP,ICMM,ICMP,ICPM,ICPP,IC,ICD,ICDO,IVL,I_SGN,IS, &
            VELOCITY_BC_INDEX,IIGM,JJGM,KKGM,IIGP,JJGP,KKGP,SURF_INDEXM,SURF_INDEXP,ITMP,ICD_SGN,ICDO_SGN,&
            BOUNDARY_TYPE_M,BOUNDARY_TYPE_P
LOGICAL :: ALTERED_GRADIENT(-2:2),PROCESS_EDGE,SYNTHETIC_EDDY_METHOD,HVAC_TANGENTIAL
INTEGER, INTENT(IN) :: NM
REAL(EB), POINTER, DIMENSION(:,:,:) :: UU=>NULL(),VV=>NULL(),WW=>NULL(),U_Y=>NULL(),U_Z=>NULL(), &
                                       V_X=>NULL(),V_Z=>NULL(),W_X=>NULL(),W_Y=>NULL(),RHOP=>NULL(),VEL_OTHER=>NULL()
TYPE (SURFACE_TYPE), POINTER :: SF=>NULL()
TYPE (OMESH_TYPE), POINTER :: OM=>NULL()
TYPE (VENTS_TYPE), POINTER :: VT

IF (SOLID_PHASE_ONLY) RETURN
IF (VEG_LEVEL_SET_UNCOUPLED) RETURN

TNOW = SECOND()

! Assign local names to variables

CALL POINT_TO_MESH(NM)

! Point to the appropriate velocity field

IF (PREDICTOR) THEN
   UU => US
   VV => VS
   WW => WS
   RHOP => RHOS
ELSE
   UU => U
   VV => V
   WW => W
   RHOP => RHO
ENDIF

! Set the boundary velocity place holder to some large negative number

IF (CORRECTOR) THEN
   
   U_Y => WORK1
   U_Z => WORK2
   V_X => WORK3
   V_Z => WORK4
   W_X => WORK5
   W_Y => WORK6
   !$OMP PARALLEL WORKSHARE DEFAULT(NONE) SHARED(U_Y,U_Z,V_X,V_Z,W_X,W_Y,UVW_GHOST)
   U_Y = -1.E6_EB
   U_Z = -1.E6_EB
   V_X = -1.E6_EB
   V_Z = -1.E6_EB
   W_X = -1.E6_EB
   W_Y = -1.E6_EB
   UVW_GHOST = -1.E6_EB
   !$OMP END PARALLEL WORKSHARE
ENDIF

!$OMP PARALLEL DEFAULT(NONE) &
!$OMP SHARED(TAU_E,OME_E, &
!$OMP        N_EDGES,EDGE_TYPE,EXTERIOR,IJKE,SOLID,UU,VV,WW,DY,DX,DZ,MU, &
!$OMP        WALL_INDEX,I_CELL,J_CELL,K_CELL,NOM,SURFACE,VENTS, &
!$OMP        T_BEGIN,T,ZC,GROUND_LEVEL, &
!$OMP        X,Z,CELL_INDEX,TMP,MU_Z,SPECIES_MIXTURE,RHOP,DUMMY,OMESH,PREDICTOR,CORRECTOR, &
!$OMP        EDGE_INTERPOLATION_FACTOR,IBAR,JBAR,KBAR,U_Y,U_Z,V_X,V_Z,W_X,W_Y,UVW_GHOST)

! Set OME_E and TAU_E to very negative number

!$OMP WORKSHARE
TAU_E = -1.E6_EB
OME_E = -1.E6_EB
!$OMP END WORKSHARE

! Loop over all cell edges and determine the appropriate velocity BCs

!$OMP DO SCHEDULE(DYNAMIC) &
!$OMP PRIVATE(IE,II,JJ,KK,IEC,ICMM,ICPM,ICMP,ICPP,NOM,IIO,JJO,KKO,UUP,UUM,DXX,MUA,I_SGN,IS,IOR,ICD,IVL,ICD_SGN,&
!$OMP         SURF_INDEXM,SURF_INDEXP,ITMP, &
!$OMP         VEL_GAS,VEL_GHOST,IWP,IWM,SF,VELOCITY_BC_INDEX,TSI,PROFILE_FACTOR,RAMP_T,VEL_T,IIGM,JJGM,KKGM,IIGP,JJGP,KKGP, &
!$OMP         RHO_WALL,MU_WALL,OM,VEL_OTHER,WGT,OMW,ICDO,MU_DUIDXJ,DUIDXJ,DUIDXJ_0,MU_DUIDXJ_0,MU_DUIDXJ_USE,DUIDXJ_USE, &
!$OMP         PROCESS_EDGE,ALTERED_GRADIENT,SLIP_COEF,ICDO_SGN,DUMMY,SYNTHETIC_EDDY_METHOD,VT,VEL_EDDY,BOUNDARY_TYPE_M, &
!$OMP         BOUNDARY_TYPE_P,WALL,HVAC_TANGENTIAL)
EDGE_LOOP: DO IE=1,N_EDGES

   IF (EDGE_TYPE(IE,1)==NULL_EDGE .AND. EDGE_TYPE(IE,2)==NULL_EDGE) CYCLE EDGE_LOOP

   ! Throw out edges that are completely surrounded by blockages or the exterior of the domain

   PROCESS_EDGE = .FALSE.
   DO IS=5,8
      IF (.NOT.EXTERIOR(IJKE(IS,IE)) .AND. .NOT.SOLID(IJKE(IS,IE))) THEN
         PROCESS_EDGE = .TRUE.
         EXIT
      ENDIF
   ENDDO
   IF (.NOT.PROCESS_EDGE) CYCLE EDGE_LOOP

   ! If the edge is to be "smoothed," set tau and omega to zero and cycle

   IF (EDGE_TYPE(IE,1)==SMOOTH_EDGE) THEN
      OME_E(IE,:) = 0._EB
      TAU_E(IE,:) = 0._EB
      CYCLE EDGE_LOOP
   ENDIF

   ! Unpack indices for the edge

   II     = IJKE( 1,IE)
   JJ     = IJKE( 2,IE)
   KK     = IJKE( 3,IE)
   IEC    = IJKE( 4,IE)
   ICMM   = IJKE( 5,IE)
   ICPM   = IJKE( 6,IE)
   ICMP   = IJKE( 7,IE)
   ICPP   = IJKE( 8,IE)
   NOM(1) = IJKE( 9,IE)
   IIO(1) = IJKE(10,IE)
   JJO(1) = IJKE(11,IE)
   KKO(1) = IJKE(12,IE)
   NOM(2) = IJKE(13,IE)
   IIO(2) = IJKE(14,IE)
   JJO(2) = IJKE(15,IE)
   KKO(2) = IJKE(16,IE)

   ! Get the velocity components at the appropriate cell faces     
 
   COMPONENT: SELECT CASE(IEC)
      CASE(1) COMPONENT    
         UUP(1)  = VV(II,JJ,KK+1)
         UUM(1)  = VV(II,JJ,KK)
         UUP(2)  = WW(II,JJ+1,KK)
         UUM(2)  = WW(II,JJ,KK)
         DXX(1)  = DY(JJ)
         DXX(2)  = DZ(KK)
         MUA      = 0.25_EB*(MU(II,JJ,KK) + MU(II,JJ+1,KK) + MU(II,JJ+1,KK+1) + MU(II,JJ,KK+1) )
      CASE(2) COMPONENT  
         UUP(1)  = WW(II+1,JJ,KK)
         UUM(1)  = WW(II,JJ,KK)
         UUP(2)  = UU(II,JJ,KK+1)
         UUM(2)  = UU(II,JJ,KK)
         DXX(1)  = DZ(KK)
         DXX(2)  = DX(II)
         MUA      = 0.25_EB*(MU(II,JJ,KK) + MU(II+1,JJ,KK) + MU(II+1,JJ,KK+1) + MU(II,JJ,KK+1) )
      CASE(3) COMPONENT 
         UUP(1)  = UU(II,JJ+1,KK)
         UUM(1)  = UU(II,JJ,KK)
         UUP(2)  = VV(II+1,JJ,KK)
         UUM(2)  = VV(II,JJ,KK)
         DXX(1)  = DX(II)
         DXX(2)  = DY(JJ)
         MUA      = 0.25_EB*(MU(II,JJ,KK) + MU(II+1,JJ,KK) + MU(II+1,JJ+1,KK) + MU(II,JJ+1,KK) )
   END SELECT COMPONENT

   ! Indicate that the velocity gradients in the two orthogonal directions have not been changed yet

   ALTERED_GRADIENT = .FALSE.

   ! Loop over all possible orientations of edge and reassign velocity gradients if appropriate

   SIGN_LOOP: DO I_SGN=-1,1,2
      ORIENTATION_LOOP: DO IS=1,3
         IF (IS==IEC) CYCLE ORIENTATION_LOOP

         IOR = I_SGN*IS

         ! Determine Index_Coordinate_Direction
         ! IEC=1, ICD=1 refers to DWDY; ICD=2 refers to DVDZ
         ! IEC=2, ICD=1 refers to DUDZ; ICD=2 refers to DWDX
         ! IEC=3, ICD=1 refers to DVDX; ICD=2 refers to DUDY

         IF (IS>IEC) ICD = IS-IEC
         IF (IS<IEC) ICD = IS-IEC+3
         IF (ICD==1) THEN ! Used to pick the appropriate velocity component
            IVL=2
         ELSE !ICD==2
            IVL=1
         ENDIF
         ICD_SGN = I_SGN * ICD   
         ! IWM and IWP are the wall cell indices of the boundary on either side of the edge.
         IF (IOR<0) THEN
            VEL_GAS   = UUM(IVL)
            VEL_GHOST = UUP(IVL)
            IWM  = WALL_INDEX(ICMM,IS)
            IIGM = I_CELL(ICMM)
            JJGM = J_CELL(ICMM)
            KKGM = K_CELL(ICMM)
            IF (ICD==1) THEN
               IWP  = WALL_INDEX(ICMP,IS)
               IIGP = I_CELL(ICMP)
               JJGP = J_CELL(ICMP)
               KKGP = K_CELL(ICMP)
            ELSE ! ICD==2
               IWP  = WALL_INDEX(ICPM,IS)
               IIGP = I_CELL(ICPM)
               JJGP = J_CELL(ICPM)
               KKGP = K_CELL(ICPM)
            ENDIF
         ELSE
            VEL_GAS   = UUP(IVL)
            VEL_GHOST = UUM(IVL)
            IF (ICD==1) THEN
               IWM  = WALL_INDEX(ICPM,-IOR)
               IIGM = I_CELL(ICPM)
               JJGM = J_CELL(ICPM)
               KKGM = K_CELL(ICPM)
            ELSE ! ICD==2
               IWM  = WALL_INDEX(ICMP,-IOR)
               IIGM = I_CELL(ICMP)
               JJGM = J_CELL(ICMP)
               KKGM = K_CELL(ICMP)
            ENDIF
            IWP  = WALL_INDEX(ICPP,-IOR)
            IIGP = I_CELL(ICPP)
            JJGP = J_CELL(ICPP)
            KKGP = K_CELL(ICPP)
         ENDIF
         
         ! Throw out edge orientations that need not be processed
         BOUNDARY_TYPE_M = WALL(IWM)%BOUNDARY_TYPE
         BOUNDARY_TYPE_P = WALL(IWP)%BOUNDARY_TYPE

         IF (BOUNDARY_TYPE_M==NULL_BOUNDARY .AND. BOUNDARY_TYPE_P==NULL_BOUNDARY) CYCLE ORIENTATION_LOOP

         ! Decide whether or not to process edge using data interpolated from another mesh
   
         INTERPOLATION_IF: IF (NOM(ICD)==0 .OR. &
                   (BOUNDARY_TYPE_M/=INTERPOLATED_BOUNDARY .AND. BOUNDARY_TYPE_P/=INTERPOLATED_BOUNDARY)) THEN

            ! Determine appropriate velocity BC by assessing each adjacent wall cell. If the BCs are different on each
            ! side of the edge, choose the one with the specified velocity, if there is one. If not, choose the max value of
            ! boundary condition index, simply for consistency.

            SURF_INDEXM = 0
            SURF_INDEXP = 0
            IF (IWM>0) SURF_INDEXM = WALL(IWM)%SURF_INDEX
            IF (IWP>0) SURF_INDEXP = WALL(IWP)%SURF_INDEX
            IF (SURFACE(SURF_INDEXM)%SPECIFIED_NORMAL_VELOCITY) THEN
               SF=>SURFACE(SURF_INDEXM)
            ELSEIF (SURFACE(SURF_INDEXP)%SPECIFIED_NORMAL_VELOCITY) THEN
               SF=>SURFACE(SURF_INDEXP)
            ELSE
               SF=>SURFACE(MAX(SURF_INDEXM,SURF_INDEXP))
            ENDIF
            VELOCITY_BC_INDEX = SF%VELOCITY_BC_INDEX

            ! Compute the viscosity in the two adjacent gas cells

            MUA = 0.5_EB*(MU(IIGM,JJGM,KKGM) + MU(IIGP,JJGP,KKGP))

            ! Set up synthetic eddy method (experimental)
            
            SYNTHETIC_EDDY_METHOD = .FALSE.
            HVAC_TANGENTIAL = .FALSE.
            IF (IWM>0 .AND. IWP>0) THEN
               IF (WALL(IWM)%VENT_INDEX==WALL(IWP)%VENT_INDEX) THEN
                  IF (WALL(IWM)%VENT_INDEX>0) THEN
                     VT=>VENTS(WALL(IWM)%VENT_INDEX)
                     IF (VT%N_EDDY>0) SYNTHETIC_EDDY_METHOD=.TRUE.
                     IF (ALL(VT%UVW > -1.E12_EB) .AND. VT%NODE_INDEX > 0) HVAC_TANGENTIAL = .TRUE.
                  ENDIF
               ENDIF
            ENDIF
            
            ! Determine if there is a tangential velocity component

            VEL_T_IF: IF (.NOT.SF%SPECIFIED_TANGENTIAL_VELOCITY .AND. .NOT.SYNTHETIC_EDDY_METHOD .AND. &
                          .NOT. HVAC_TANGENTIAL .OR. IWM==0 .OR. IWP==0) THEN
               VEL_T = 0._EB
            ELSE VEL_T_IF
               VEL_EDDY = 0._EB
               SYNTHETIC_EDDY_IF: IF (SYNTHETIC_EDDY_METHOD) THEN
                  IS_SELECT: SELECT CASE(IS) ! unsigned vent orientation
                     CASE(1) ! yz plane
                        SELECT CASE(IEC) ! edge orientation
                           CASE(2)
                              IF (ICD==1) VEL_EDDY = 0.5_EB*(VT%U_EDDY(JJ,KK)+VT%U_EDDY(JJ,KK+1))
                              IF (ICD==2) VEL_EDDY = 0.5_EB*(VT%W_EDDY(JJ,KK)+VT%W_EDDY(JJ,KK+1))
                           CASE(3)
                              IF (ICD==1) VEL_EDDY = 0.5_EB*(VT%V_EDDY(JJ,KK)+VT%V_EDDY(JJ+1,KK))
                              IF (ICD==2) VEL_EDDY = 0.5_EB*(VT%U_EDDY(JJ,KK)+VT%U_EDDY(JJ+1,KK))
                        END SELECT
                     CASE(2) ! zx plane
                        SELECT CASE(IEC)
                           CASE(3)
                              IF (ICD==1) VEL_EDDY = 0.5_EB*(VT%V_EDDY(II,KK)+VT%V_EDDY(II+1,KK))
                              IF (ICD==2) VEL_EDDY = 0.5_EB*(VT%U_EDDY(II,KK)+VT%U_EDDY(II+1,KK))
                           CASE(1)
                              IF (ICD==1) VEL_EDDY = 0.5_EB*(VT%W_EDDY(II,KK)+VT%W_EDDY(II,KK+1))
                              IF (ICD==2) VEL_EDDY = 0.5_EB*(VT%V_EDDY(II,KK)+VT%V_EDDY(II,KK+1))
                        END SELECT
                     CASE(3) ! xy plane
                        SELECT CASE(IEC)
                           CASE(1)
                              IF (ICD==1) VEL_EDDY = 0.5_EB*(VT%W_EDDY(II,JJ)+VT%W_EDDY(II,JJ+1))
                              IF (ICD==2) VEL_EDDY = 0.5_EB*(VT%V_EDDY(II,JJ)+VT%V_EDDY(II,JJ+1))
                           CASE(2)
                              IF (ICD==1) VEL_EDDY = 0.5_EB*(VT%U_EDDY(II,JJ)+VT%U_EDDY(II+1,JJ))
                              IF (ICD==2) VEL_EDDY = 0.5_EB*(VT%W_EDDY(II,JJ)+VT%W_EDDY(II+1,JJ))
                        END SELECT
                  END SELECT IS_SELECT
               ENDIF SYNTHETIC_EDDY_IF
               IF (ABS(SF%T_IGN-T_BEGIN)<=SPACING(SF%T_IGN) .AND. SF%RAMP_INDEX(TIME_VELO)>=1) THEN
                  TSI = T
               ELSE
                  TSI=T-SF%T_IGN
               ENDIF
               PROFILE_FACTOR = 1._EB
               IF (HVAC_TANGENTIAL .AND. 0.5*(WALL(IWM)%UWS+WALL(IWP)%UWS) > 0._EB) HVAC_TANGENTIAL = .FALSE.
               IF (HVAC_TANGENTIAL) THEN
                  VEL_T = 0._EB
                  IEC_SELECT: SELECT CASE(IEC) ! edge orientation
                     CASE (1)
                        IF (ICD==1) VEL_T = 0.5*(WALL(IWM)%UWS+WALL(IWP)%UWS)/VT%UVW(ABS(VT%IOR))*VT%UVW(3)
                        IF (ICD==2) VEL_T = 0.5*(WALL(IWM)%UWS+WALL(IWP)%UWS)/VT%UVW(ABS(VT%IOR))*VT%UVW(2)
                     CASE (2)
                        IF (ICD==1) VEL_T = 0.5*(WALL(IWM)%UWS+WALL(IWP)%UWS)/VT%UVW(ABS(VT%IOR))*VT%UVW(1)
                        IF (ICD==2) VEL_T = 0.5*(WALL(IWM)%UWS+WALL(IWP)%UWS)/VT%UVW(ABS(VT%IOR))*VT%UVW(3)
                     CASE (3)                     
                        IF (ICD==1) VEL_T = 0.5*(WALL(IWM)%UWS+WALL(IWP)%UWS)/VT%UVW(ABS(VT%IOR))*VT%UVW(2)
                        IF (ICD==2) VEL_T = 0.5*(WALL(IWM)%UWS+WALL(IWP)%UWS)/VT%UVW(ABS(VT%IOR))*VT%UVW(1)
                  END SELECT IEC_SELECT
                  IF (VT%IOR > 0) VEL_T = -VEL_T
               ELSE
                  IF (SF%PROFILE==ATMOSPHERIC) PROFILE_FACTOR = (MAX(0._EB,ZC(KK)-GROUND_LEVEL)/SF%Z0)**SF%PLE
                  RAMP_T = EVALUATE_RAMP(TSI,SF%TAU(TIME_VELO),SF%RAMP_INDEX(TIME_VELO))
                  IF (IEC==1 .OR. (IEC==2 .AND. ICD==2)) VEL_T = RAMP_T*(PROFILE_FACTOR*SF%VEL_T(2) + VEL_EDDY)
                  IF (IEC==3 .OR. (IEC==2 .AND. ICD==1)) VEL_T = RAMP_T*(PROFILE_FACTOR*SF%VEL_T(1) + VEL_EDDY)
               ENDIF
            ENDIF VEL_T_IF
 
            ! Choose the appropriate boundary condition to apply
            IF (HVAC_TANGENTIAL)  THEN

               VEL_GHOST = 2._EB*VEL_T - VEL_GAS
               DUIDXJ(ICD_SGN) = I_SGN*(VEL_GAS-VEL_GHOST)/DXX(ICD)
               MU_DUIDXJ(ICD_SGN) = MUA*DUIDXJ(ICD_SGN)
               ALTERED_GRADIENT(ICD_SGN) = .TRUE.
      
            ELSE

               BOUNDARY_CONDITION: SELECT CASE(VELOCITY_BC_INDEX)

                  CASE (FREE_SLIP_BC) BOUNDARY_CONDITION

                     VEL_GHOST = VEL_GAS
                     DUIDXJ(ICD_SGN) = I_SGN*(VEL_GAS-VEL_GHOST)/DXX(ICD)
                     MU_DUIDXJ(ICD_SGN) = MUA*DUIDXJ(ICD_SGN)
                     ALTERED_GRADIENT(ICD_SGN) = .TRUE.

                  CASE (NO_SLIP_BC) BOUNDARY_CONDITION

                     VEL_GHOST = 2._EB*VEL_T - VEL_GAS
                     DUIDXJ(ICD_SGN) = I_SGN*(VEL_GAS-VEL_GHOST)/DXX(ICD)
                     MU_DUIDXJ(ICD_SGN) = MUA*DUIDXJ(ICD_SGN)
                     ALTERED_GRADIENT(ICD_SGN) = .TRUE.

                  CASE (WALL_MODEL) BOUNDARY_CONDITION

                     IF ( SOLID(CELL_INDEX(IIGM,JJGM,KKGM)) .OR. SOLID(CELL_INDEX(IIGP,JJGP,KKGP)) ) THEN
                        MU_WALL = MUA
                        SLIP_COEF=-1._EB
                     ELSE
                        ITMP = MIN(5000,NINT(0.5_EB*(TMP(IIGM,JJGM,KKGM)+TMP(IIGP,JJGP,KKGP))))
                        MU_WALL = MU_Z(ITMP,0)*SPECIES_MIXTURE(0)%MW
                        RHO_WALL = 0.5_EB*( RHOP(IIGM,JJGM,KKGM) + RHOP(IIGP,JJGP,KKGP) )
                        CALL WERNER_WENGLE_WALL_MODEL(SLIP_COEF,DUMMY,VEL_GAS-VEL_T,MU_WALL/RHO_WALL,DXX(ICD),SF%ROUGHNESS)
                     ENDIF
                     VEL_GHOST = 2._EB*VEL_T - VEL_GAS
                     DUIDXJ(ICD_SGN) = I_SGN*(VEL_GAS-VEL_GHOST)/DXX(ICD)
                     MU_DUIDXJ(ICD_SGN) = MU_WALL*(VEL_GAS-VEL_T)*I_SGN*(1._EB-SLIP_COEF)/DXX(ICD)
                     ALTERED_GRADIENT(ICD_SGN) = .TRUE.
                     IF (BOUNDARY_TYPE_M==SOLID_BOUNDARY .NEQV. BOUNDARY_TYPE_P==SOLID_BOUNDARY) THEN
                        DUIDXJ(ICD_SGN) = 0.5_EB*DUIDXJ(ICD_SGN)
                        MU_DUIDXJ(ICD_SGN) = 0.5_EB*MU_DUIDXJ(ICD_SGN)
                     ENDIF

               END SELECT BOUNDARY_CONDITION
            ENDIF

         ELSE INTERPOLATION_IF  ! Use data from another mesh
 
            OM => OMESH(ABS(NOM(ICD)))
   
            IF (PREDICTOR) THEN
               SELECT CASE(IEC)
                  CASE(1)
                     IF (ICD==1) THEN
                        VEL_OTHER => OM%WS
                     ELSE ! ICD=2
                        VEL_OTHER => OM%VS
                     ENDIF
                  CASE(2)
                     IF (ICD==1) THEN
                        VEL_OTHER => OM%US
                     ELSE ! ICD=2
                        VEL_OTHER => OM%WS
                     ENDIF
                  CASE(3) 
                     IF (ICD==1) THEN
                        VEL_OTHER => OM%VS
                     ELSE ! ICD=2
                        VEL_OTHER => OM%US
                     ENDIF
               END SELECT
            ELSE
               SELECT CASE(IEC)
                  CASE(1) 
                     IF (ICD==1) THEN
                        VEL_OTHER => OM%W
                     ELSE ! ICD=2
                        VEL_OTHER => OM%V
                     ENDIF
                  CASE(2)
                     IF (ICD==1) THEN
                        VEL_OTHER => OM%U
                     ELSE ! ICD=2
                        VEL_OTHER => OM%W
                     ENDIF
                  CASE(3)
                     IF (ICD==1) THEN
                        VEL_OTHER => OM%V
                     ELSE ! ICD=2
                        VEL_OTHER => OM%U
                     ENDIF
               END SELECT
            ENDIF
   
            WGT = EDGE_INTERPOLATION_FACTOR(IE,ICD)
            OMW = 1._EB-WGT

            SELECT CASE(IEC)
               CASE(1)
                  IF (ICD==1) THEN
                     VEL_GHOST = WGT*VEL_OTHER(IIO(ICD),JJO(ICD),KKO(ICD)) + OMW*VEL_OTHER(IIO(ICD),JJO(ICD),KKO(ICD)-1)
                  ELSE ! ICD=2
                     VEL_GHOST = WGT*VEL_OTHER(IIO(ICD),JJO(ICD),KKO(ICD)) + OMW*VEL_OTHER(IIO(ICD),JJO(ICD)-1,KKO(ICD))
                  ENDIF
               CASE(2)
                  IF (ICD==1) THEN
                     VEL_GHOST = WGT*VEL_OTHER(IIO(ICD),JJO(ICD),KKO(ICD)) + OMW*VEL_OTHER(IIO(ICD)-1,JJO(ICD),KKO(ICD))
                  ELSE ! ICD=2
                     VEL_GHOST = WGT*VEL_OTHER(IIO(ICD),JJO(ICD),KKO(ICD)) + OMW*VEL_OTHER(IIO(ICD),JJO(ICD),KKO(ICD)-1)
                  ENDIF
               CASE(3)
                  IF (ICD==1) THEN
                     VEL_GHOST = WGT*VEL_OTHER(IIO(ICD),JJO(ICD),KKO(ICD)) + OMW*VEL_OTHER(IIO(ICD),JJO(ICD)-1,KKO(ICD))
                  ELSE ! ICD==2
                     VEL_GHOST = WGT*VEL_OTHER(IIO(ICD),JJO(ICD),KKO(ICD)) + OMW*VEL_OTHER(IIO(ICD)-1,JJO(ICD),KKO(ICD))
                  ENDIF
            END SELECT

            IF (ICD==1) THEN
               IF (IOR<0) UUP(2) = VEL_GHOST
               IF (IOR>0) UUM(2) = VEL_GHOST
            ELSE ! ICD=2
               IF (IOR<0) UUP(1) = VEL_GHOST
               IF (IOR>0) UUM(1) = VEL_GHOST
            ENDIF
            
         ENDIF INTERPOLATION_IF

         ! Set ghost cell values at edge of computational domain
   
         SELECT CASE(IEC)
            CASE(1)
               IF (JJ==0    .AND. IOR== 2) WW(II,JJ,KK)   = VEL_GHOST
               IF (JJ==JBAR .AND. IOR==-2) WW(II,JJ+1,KK) = VEL_GHOST
               IF (KK==0    .AND. IOR== 3) VV(II,JJ,KK)   = VEL_GHOST
               IF (KK==KBAR .AND. IOR==-3) VV(II,JJ,KK+1) = VEL_GHOST
               IF (CORRECTOR .AND. JJ>0 .AND. JJ<JBAR .AND. KK>0 .AND. KK<KBAR) THEN
                 IF (ICD==1) THEN
                    W_Y(II,JJ,KK) = 0.5_EB*(VEL_GHOST+VEL_GAS)
                 ELSE ! ICD=2
                    V_Z(II,JJ,KK) = 0.5_EB*(VEL_GHOST+VEL_GAS)
                 ENDIF
               ENDIF
            CASE(2)
               IF (II==0    .AND. IOR== 1) WW(II,JJ,KK)   = VEL_GHOST
               IF (II==IBAR .AND. IOR==-1) WW(II+1,JJ,KK) = VEL_GHOST
               IF (KK==0    .AND. IOR== 3) UU(II,JJ,KK)   = VEL_GHOST
               IF (KK==KBAR .AND. IOR==-3) UU(II,JJ,KK+1) = VEL_GHOST
               IF (CORRECTOR .AND. II>0 .AND. II<IBAR .AND. KK>0 .AND. KK<KBAR) THEN
                 IF (ICD==1) THEN
                    U_Z(II,JJ,KK) = 0.5_EB*(VEL_GHOST+VEL_GAS)
                 ELSE ! ICD=2
                    W_X(II,JJ,KK) = 0.5_EB*(VEL_GHOST+VEL_GAS)
                 ENDIF
               ENDIF
            CASE(3)
               IF (II==0    .AND. IOR== 1) VV(II,JJ,KK)   = VEL_GHOST
               IF (II==IBAR .AND. IOR==-1) VV(II+1,JJ,KK) = VEL_GHOST
               IF (JJ==0    .AND. IOR== 2) UU(II,JJ,KK)   = VEL_GHOST
               IF (JJ==JBAR .AND. IOR==-2) UU(II,JJ+1,KK) = VEL_GHOST
               IF (CORRECTOR .AND. II>0 .AND. II<IBAR .AND. JJ>0 .AND. JJ<JBAR) THEN
                 IF (ICD==1) THEN
                    V_X(II,JJ,KK) = 0.5_EB*(VEL_GHOST+VEL_GAS)
                 ELSE ! ICD=2
                    U_Y(II,JJ,KK) = 0.5_EB*(VEL_GHOST+VEL_GAS)
                 ENDIF
               ENDIF
         END SELECT
      ENDDO ORIENTATION_LOOP
   
   ENDDO SIGN_LOOP

   ! If the edge is on an interpolated boundary, cycle

   IF (EDGE_TYPE(IE,1)==INTERPOLATED_EDGE .OR. EDGE_TYPE(IE,2)==INTERPOLATED_EDGE) THEN
      PROCESS_EDGE = .FALSE.
      DO IS=5,8
         IF (SOLID(IJKE(IS,IE))) PROCESS_EDGE = .TRUE.
      ENDDO
      IF (.NOT.PROCESS_EDGE) CYCLE EDGE_LOOP
   ENDIF

   ! Save vorticity and viscous stress for use in momentum equation

   DUIDXJ_0(1)    = (UUP(2)-UUM(2))/DXX(1)
   DUIDXJ_0(2)    = (UUP(1)-UUM(1))/DXX(2)
   MU_DUIDXJ_0(1) = MUA*DUIDXJ_0(1)
   MU_DUIDXJ_0(2) = MUA*DUIDXJ_0(2)

   SIGN_LOOP_2: DO I_SGN=-1,1,2
      ORIENTATION_LOOP_2: DO ICD=1,2
         IF (ICD==1) THEN
            ICDO=2
         ELSE !ICD==2)
            ICDO=1
         ENDIF
         ICD_SGN = I_SGN*ICD
         IF (ALTERED_GRADIENT(ICD_SGN)) THEN
               DUIDXJ_USE(ICD) =    DUIDXJ(ICD_SGN)
            MU_DUIDXJ_USE(ICD) = MU_DUIDXJ(ICD_SGN)
         ELSEIF (ALTERED_GRADIENT(-ICD_SGN)) THEN
               DUIDXJ_USE(ICD) =    DUIDXJ(-ICD_SGN)
            MU_DUIDXJ_USE(ICD) = MU_DUIDXJ(-ICD_SGN)
         ELSE
            CYCLE
         ENDIF
         ICDO_SGN = I_SGN*ICDO
         IF (ALTERED_GRADIENT(ICDO_SGN) .AND. ALTERED_GRADIENT(-ICDO_SGN)) THEN
               DUIDXJ_USE(ICDO) =    0.5_EB*(DUIDXJ(ICDO_SGN)+   DUIDXJ(-ICDO_SGN))
            MU_DUIDXJ_USE(ICDO) = 0.5_EB*(MU_DUIDXJ(ICDO_SGN)+MU_DUIDXJ(-ICDO_SGN))
         ELSEIF (ALTERED_GRADIENT(ICDO_SGN)) THEN
               DUIDXJ_USE(ICDO) =    DUIDXJ(ICDO_SGN)
            MU_DUIDXJ_USE(ICDO) = MU_DUIDXJ(ICDO_SGN)
         ELSEIF (ALTERED_GRADIENT(-ICDO_SGN)) THEN
               DUIDXJ_USE(ICDO) =    DUIDXJ(-ICDO_SGN)
            MU_DUIDXJ_USE(ICDO) = MU_DUIDXJ(-ICDO_SGN)
         ELSE
               DUIDXJ_USE(ICDO) =    DUIDXJ_0(ICDO)
            MU_DUIDXJ_USE(ICDO) = MU_DUIDXJ_0(ICDO)
         ENDIF
         OME_E(IE,ICD_SGN) =    DUIDXJ_USE(1) -    DUIDXJ_USE(2)
         TAU_E(IE,ICD_SGN) = MU_DUIDXJ_USE(1) + MU_DUIDXJ_USE(2)    
      ENDDO ORIENTATION_LOOP_2
   ENDDO SIGN_LOOP_2

ENDDO EDGE_LOOP
!$OMP END DO

! Store cell node averages of the velocity components in UVW_GHOST for use in Smokeview only

IF (CORRECTOR) THEN
   !$OMP DO COLLAPSE(3) PRIVATE(K,J,I,IC)
   DO K=0,KBAR
      DO J=0,JBAR
         DO I=0,IBAR
            IC = CELL_INDEX(I,J,K) 
            IF (IC==0) CYCLE
            IF (U_Y(I,J,K)  >-1.E5_EB) UVW_GHOST(IC,1) = U_Y(I,J,K) 
            IF (U_Z(I,J,K)  >-1.E5_EB) UVW_GHOST(IC,1) = U_Z(I,J,K) 
            IF (V_X(I,J,K)  >-1.E5_EB) UVW_GHOST(IC,2) = V_X(I,J,K) 
            IF (V_Z(I,J,K)  >-1.E5_EB) UVW_GHOST(IC,2) = V_Z(I,J,K) 
            IF (W_X(I,J,K)  >-1.E5_EB) UVW_GHOST(IC,3) = W_X(I,J,K) 
            IF (W_Y(I,J,K)  >-1.E5_EB) UVW_GHOST(IC,3) = W_Y(I,J,K)
         ENDDO
      ENDDO
   ENDDO
   !$OMP END DO NOWAIT
ENDIF
!$OMP END PARALLEL

TUSED(4,NM)=TUSED(4,NM)+SECOND()-TNOW
END SUBROUTINE VELOCITY_BC 
 
 
 
SUBROUTINE MATCH_VELOCITY(NM)

! Force normal component of velocity to match at interpolated boundaries

INTEGER  :: NOM,II,JJ,KK,IOR,IW,IIO,JJO,KKO
INTEGER, INTENT(IN) :: NM
REAL(EB) :: UU_AVG,VV_AVG,WW_AVG,TNOW,DA_OTHER,UU_OTHER,VV_OTHER,WW_OTHER,NOM_CELLS
REAL(EB), POINTER, DIMENSION(:,:,:) :: UU=>NULL(),VV=>NULL(),WW=>NULL(),OM_UU=>NULL(),OM_VV=>NULL(),OM_WW=>NULL()
TYPE (OMESH_TYPE), POINTER :: OM=>NULL()
TYPE (MESH_TYPE), POINTER :: M2=>NULL()
TYPE (WALL_TYPE), POINTER :: WC=>NULL()
IF (SOLID_PHASE_ONLY) RETURN
IF (VEG_LEVEL_SET_UNCOUPLED) RETURN
IF (EVACUATION_ONLY(NM)) RETURN

TNOW = SECOND()

! Assign local variable names

CALL POINT_TO_MESH(NM)

! Point to the appropriate velocity field

IF (PREDICTOR) THEN
   UU => US
   VV => VS
   WW => WS
   D_CORR = 0._EB
ELSE
   UU => U
   VV => V
   WW => W
   DS_CORR = 0._EB
ENDIF

! Loop over all cell edges and determine the appropriate velocity BCs

!$OMP PARALLEL DO DEFAULT(NONE) SCHEDULE(DYNAMIC) &
!$OMP SHARED(N_EXTERNAL_WALL_CELLS,OMESH,MESHES,PREDICTOR,CORRECTOR, &
!$OMP        D_CORR,DS_CORR,UU,VV,WW,RDX,RDY,RDZ,UVW_SAVE,IBAR,JBAR,KBAR,WC,WALL,U_GHOST,V_GHOST,W_GHOST) &
!$OMP PRIVATE(IW,II,JJ,KK,IOR,NOM,OM,M2,DA_OTHER,OM_UU,OM_VV,OM_WW,KKO,JJO,IIO, &
!$OMP         UU_OTHER,VV_OTHER,WW_OTHER,UU_AVG,VV_AVG,WW_AVG,NOM_CELLS)
EXTERNAL_WALL_LOOP: DO IW=1,N_EXTERNAL_WALL_CELLS
   WC=>WALL(IW)
   IF (WC%BOUNDARY_TYPE/=INTERPOLATED_BOUNDARY) CYCLE EXTERNAL_WALL_LOOP

   II  = WC%II
   JJ  = WC%JJ
   KK  = WC%KK
   IOR = WC%IOR
   NOM = WC%NOM
   OM => OMESH(NOM)
   M2 => MESHES(NOM)
   
   ! Determine the area of the interpolated cell face
   
   DA_OTHER = 0._EB

   SELECT CASE(ABS(IOR))
      CASE(1)
         IF (PREDICTOR) OM_UU => OM%US
         IF (CORRECTOR) OM_UU => OM%U 
         DO KKO=WC%NOM_IB(3),WC%NOM_IB(6)
            DO JJO=WC%NOM_IB(2),WC%NOM_IB(5)
               DO IIO=WC%NOM_IB(1),WC%NOM_IB(4)
                  DA_OTHER = DA_OTHER + M2%DY(JJO)*M2%DZ(KKO)
               ENDDO
            ENDDO
         ENDDO
      CASE(2)
         IF (PREDICTOR) OM_VV => OM%VS
         IF (CORRECTOR) OM_VV => OM%V
         DO KKO=WC%NOM_IB(3),WC%NOM_IB(6)
            DO JJO=WC%NOM_IB(2),WC%NOM_IB(5)
               DO IIO=WC%NOM_IB(1),WC%NOM_IB(4)
                  DA_OTHER = DA_OTHER + M2%DX(IIO)*M2%DZ(KKO)
               ENDDO
            ENDDO
         ENDDO
      CASE(3)
         IF (PREDICTOR) OM_WW => OM%WS
         IF (CORRECTOR) OM_WW => OM%W
         DO KKO=WC%NOM_IB(3),WC%NOM_IB(6)
            DO JJO=WC%NOM_IB(2),WC%NOM_IB(5)
               DO IIO=WC%NOM_IB(1),WC%NOM_IB(4)
                  DA_OTHER = DA_OTHER + M2%DX(IIO)*M2%DY(JJO)
               ENDDO
            ENDDO
         ENDDO
   END SELECT
   
   ! Determine the normal component of velocity from the other mesh and use it for average

   SELECT CASE(IOR)
   
      CASE( 1)
      
         UU_OTHER = 0._EB
         DO KKO=WC%NOM_IB(3),WC%NOM_IB(6)
            DO JJO=WC%NOM_IB(2),WC%NOM_IB(5)
               DO IIO=WC%NOM_IB(1),WC%NOM_IB(4)
                  UU_OTHER = UU_OTHER + OM_UU(IIO,JJO,KKO)*M2%DY(JJO)*M2%DZ(KKO)/DA_OTHER
               ENDDO
            ENDDO
         ENDDO
         UU_AVG = 0.5_EB*(UU(0,JJ,KK) + UU_OTHER)
         IF (PREDICTOR) D_CORR(IW) = DS_CORR(IW) + 0.5*(UU_AVG-UU(0,JJ,KK))*RDX(1)
         IF (CORRECTOR) DS_CORR(IW) = (UU_AVG-UU(0,JJ,KK))*RDX(1)
         UVW_SAVE(IW) = UU(0,JJ,KK)
         UU(0,JJ,KK)  = UU_AVG

      CASE(-1)
         
         UU_OTHER = 0._EB
         DO KKO=WC%NOM_IB(3),WC%NOM_IB(6)
            DO JJO=WC%NOM_IB(2),WC%NOM_IB(5)
               DO IIO=WC%NOM_IB(1),WC%NOM_IB(4)
                  UU_OTHER = UU_OTHER + OM_UU(IIO-1,JJO,KKO)*M2%DY(JJO)*M2%DZ(KKO)/DA_OTHER
               ENDDO
            ENDDO
         ENDDO
         UU_AVG = 0.5_EB*(UU(IBAR,JJ,KK) + UU_OTHER)
         IF (PREDICTOR) D_CORR(IW) = DS_CORR(IW) - 0.5*(UU_AVG-UU(IBAR,JJ,KK))*RDX(IBAR)
         IF (CORRECTOR) DS_CORR(IW) = -(UU_AVG-UU(IBAR,JJ,KK))*RDX(IBAR)
         UVW_SAVE(IW) = UU(IBAR,JJ,KK)
         UU(IBAR,JJ,KK) = UU_AVG

      CASE( 2)
      
         VV_OTHER = 0._EB
         DO KKO=WC%NOM_IB(3),WC%NOM_IB(6)
            DO JJO=WC%NOM_IB(2),WC%NOM_IB(5)
               DO IIO=WC%NOM_IB(1),WC%NOM_IB(4)
                  VV_OTHER = VV_OTHER + OM_VV(IIO,JJO,KKO)*M2%DX(IIO)*M2%DZ(KKO)/DA_OTHER
               ENDDO
            ENDDO
         ENDDO
         VV_AVG = 0.5_EB*(VV(II,0,KK) + VV_OTHER)
         IF (PREDICTOR) D_CORR(IW) = DS_CORR(IW) + 0.5*(VV_AVG-VV(II,0,KK))*RDY(1)
         IF (CORRECTOR) DS_CORR(IW) = (VV_AVG-VV(II,0,KK))*RDY(1)
         UVW_SAVE(IW) = VV(II,0,KK)
         VV(II,0,KK)  = VV_AVG

      CASE(-2)
      
         VV_OTHER = 0._EB
         DO KKO=WC%NOM_IB(3),WC%NOM_IB(6)
            DO JJO=WC%NOM_IB(2),WC%NOM_IB(5)
               DO IIO=WC%NOM_IB(1),WC%NOM_IB(4)
                  VV_OTHER = VV_OTHER + OM_VV(IIO,JJO-1,KKO)*M2%DX(IIO)*M2%DZ(KKO)/DA_OTHER
               ENDDO
            ENDDO
         ENDDO
         VV_AVG = 0.5_EB*(VV(II,JBAR,KK) + VV_OTHER)
         IF (PREDICTOR) D_CORR(IW) = DS_CORR(IW) - 0.5*(VV_AVG-VV(II,JBAR,KK))*RDY(JBAR)
         IF (CORRECTOR) DS_CORR(IW) = -(VV_AVG-VV(II,JBAR,KK))*RDY(JBAR)
         UVW_SAVE(IW)   = VV(II,JBAR,KK)
         VV(II,JBAR,KK) = VV_AVG

      CASE( 3)
      
         WW_OTHER = 0._EB
         DO KKO=WC%NOM_IB(3),WC%NOM_IB(6)
            DO JJO=WC%NOM_IB(2),WC%NOM_IB(5)
               DO IIO=WC%NOM_IB(1),WC%NOM_IB(4)
                  WW_OTHER = WW_OTHER + OM_WW(IIO,JJO,KKO)*M2%DX(IIO)*M2%DY(JJO)/DA_OTHER
               ENDDO
            ENDDO
         ENDDO
         WW_AVG = 0.5_EB*(WW(II,JJ,0) + WW_OTHER)
         IF (PREDICTOR) D_CORR(IW) = DS_CORR(IW) + 0.5*(WW_AVG-WW(II,JJ,0))*RDZ(1)
         IF (CORRECTOR) DS_CORR(IW) = (WW_AVG-WW(II,JJ,0))*RDZ(1)
         UVW_SAVE(IW) = WW(II,JJ,0)
         WW(II,JJ,0)  = WW_AVG

      CASE(-3)
      
         WW_OTHER = 0._EB
         DO KKO=WC%NOM_IB(3),WC%NOM_IB(6)
            DO JJO=WC%NOM_IB(2),WC%NOM_IB(5)
               DO IIO=WC%NOM_IB(1),WC%NOM_IB(4)
                  WW_OTHER = WW_OTHER + OM_WW(IIO,JJO,KKO-1)*M2%DX(IIO)*M2%DY(JJO)/DA_OTHER
               ENDDO
            ENDDO
         ENDDO
         WW_AVG = 0.5_EB*(WW(II,JJ,KBAR) + WW_OTHER)
         IF (PREDICTOR) D_CORR(IW) = DS_CORR(IW) - 0.5*(WW_AVG-WW(II,JJ,KBAR))*RDZ(KBAR)
         IF (CORRECTOR) DS_CORR(IW) = -(WW_AVG-WW(II,JJ,KBAR))*RDZ(KBAR)
         UVW_SAVE(IW)   = WW(II,JJ,KBAR)
         WW(II,JJ,KBAR) = WW_AVG
         
   END SELECT

   ! Save velocity components at the ghost cell midpoint 

   U_GHOST(IW) = 0._EB
   V_GHOST(IW) = 0._EB
   W_GHOST(IW) = 0._EB

   IF (PREDICTOR) OM_UU => OM%US
   IF (CORRECTOR) OM_UU => OM%U 
   IF (PREDICTOR) OM_VV => OM%VS
   IF (CORRECTOR) OM_VV => OM%V 
   IF (PREDICTOR) OM_WW => OM%WS
   IF (CORRECTOR) OM_WW => OM%W 

   DO KKO=WC%NOM_IB(3),WC%NOM_IB(6)
      DO JJO=WC%NOM_IB(2),WC%NOM_IB(5)
         DO IIO=WC%NOM_IB(1),WC%NOM_IB(4)
            U_GHOST(IW) = U_GHOST(IW) + 0.5_EB*(OM_UU(IIO,JJO,KKO)+OM_UU(IIO-1,JJO,KKO))
            V_GHOST(IW) = V_GHOST(IW) + 0.5_EB*(OM_VV(IIO,JJO,KKO)+OM_VV(IIO,JJO-1,KKO))
            W_GHOST(IW) = W_GHOST(IW) + 0.5_EB*(OM_WW(IIO,JJO,KKO)+OM_WW(IIO,JJO,KKO-1))
         ENDDO
      ENDDO
   ENDDO
   NOM_CELLS = REAL((WC%NOM_IB(4)-WC%NOM_IB(1)+1)*(WC%NOM_IB(5)-WC%NOM_IB(2)+1)*(WC%NOM_IB(6)-WC%NOM_IB(3)+1),EB)
   U_GHOST(IW) = U_GHOST(IW)/NOM_CELLS
   V_GHOST(IW) = V_GHOST(IW)/NOM_CELLS
   W_GHOST(IW) = W_GHOST(IW)/NOM_CELLS


ENDDO EXTERNAL_WALL_LOOP
!$OMP END PARALLEL DO

TUSED(4,NM)=TUSED(4,NM)+SECOND()-TNOW
END SUBROUTINE MATCH_VELOCITY


SUBROUTINE CHECK_STABILITY(NM,CODE)
 
! Checks the Courant and Von Neumann stability criteria, and if necessary, reduces the time step accordingly

USE PHYSICAL_FUNCTIONS, ONLY: GET_SPECIFIC_HEAT 
INTEGER, INTENT(IN) :: NM,CODE
REAL(EB) :: UODX,VODY,WODZ,UVW,UVWMAX,R_DX2,MU_MAX,MUTRM,CP,ZZ_GET(0:N_TRACKED_SPECIES)
INTEGER  :: I,J,K,IW,IIG,JJG,KKG
REAL(EB) :: P_UVWMAX,P_MU_MAX,P_MU_TMP !private variables for OpenMP-Code
INTEGER  :: P_ICFL,P_JCFL,P_KCFL,P_I_VN,P_J_VN,P_K_VN !private variables for OpenMP-Code
REAL(EB), POINTER, DIMENSION(:,:,:) :: UU=>NULL(),VV=>NULL(),WW=>NULL(),RHOP=>NULL(),DP=>NULL(),MUP=>NULL()
REAL(EB), POINTER, DIMENSION(:,:,:,:) :: ZZP=>NULL()
TYPE(WALL_TYPE), POINTER :: WC=>NULL()

IF (EVACUATION_ONLY(NM)) THEN
   CHANGE_TIME_STEP(NM) = .FALSE.
   RETURN
ENDIF

SELECT CASE(CODE)
   CASE(1)
      UU => MESHES(NM)%U
      VV => MESHES(NM)%V
      WW => MESHES(NM)%W
      RHOP => MESHES(NM)%RHO
      DP => MESHES(NM)%D
      ZZP => MESHES(NM)%ZZ
   CASE(2)
      UU => MESHES(NM)%US
      VV => MESHES(NM)%VS
      WW => MESHES(NM)%WS
      RHOP => MESHES(NM)%RHOS
      DP => MESHES(NM)%DS
      ZZP => MESHES(NM)%ZZS
END SELECT
 
CHANGE_TIME_STEP(NM) = .FALSE.
UVWMAX = 0._EB
VN     = 0._EB
MUTRM  = 1.E-9_EB
R_DX2  = 1.E-9_EB

! Strategy for OpenMP version of CFL/VN number determination
! - find max CFL/VN number for each thread (P_UVWMAX/P_MU_MAX)
! - save I,J,K of each P_UVWMAX/P_MU_MAX in P_ICFL... for each thread
! - compare sequentially all P_UVWMAX/P_MU_MAX and find the global maximum
! - save P_ICFL... of the "winning" thread in the global ICFL... variable
 
! Determine max CFL number from all grid cells

SELECT_VELOCITY_NORM: SELECT CASE (CFL_VELOCITY_NORM)
   CASE(0)
      P_UVWMAX = UVWMAX
      !$OMP PARALLEL DEFAULT(NONE) & 
      !$OMP SHARED(UVWMAX,ICFL,JCFL,KCFL,UU,VV,WW,RDXN,RDYN,RDZN,IBAR,JBAR,KBAR,DP) &
      !$OMP PRIVATE(P_ICFL,P_JCFL,P_KCFL) &
      !$OMP FIRSTPRIVATE(P_UVWMAX) 

      !$OMP DO COLLAPSE(3) SCHEDULE(STATIC) PRIVATE(K,J,I,UODX,VODY,WODZ,UVW)
      DO K=0,KBAR
         DO J=0,JBAR
            DO I=0,IBAR
               UODX = ABS(UU(I,J,K))*RDXN(I)
               VODY = ABS(VV(I,J,K))*RDYN(J)
               WODZ = ABS(WW(I,J,K))*RDZN(K)
               UVW  = MAX(UODX,VODY,WODZ) + ABS(DP(I,J,K))
               IF (UVW>=P_UVWMAX) THEN
                  P_UVWMAX = UVW
                  P_ICFL = I
                  P_JCFL = J
                  P_KCFL = K
               ENDIF
            ENDDO
         ENDDO
      ENDDO
      !$OMP END DO NOWAIT
      !$OMP CRITICAL
      IF (P_UVWMAX>=UVWMAX) THEN
         UVWMAX = P_UVWMAX
         ICFL=P_ICFL
         JCFL=P_JCFL
         KCFL=P_KCFL
      ENDIF
      !$OMP END CRITICAL
      !$OMP END PARALLEL
   CASE(1)
      P_UVWMAX = UVWMAX
      !$OMP PARALLEL DEFAULT(NONE) &
      !$OMP SHARED(UVWMAX,ICFL,JCFL,KCFL,UU,VV,WW,RDXN,RDYN,RDZN,IBAR,JBAR,KBAR,DP) &
      !$OMP PRIVATE(P_ICFL,P_JCFL,P_KCFL) &
      !$OMP FIRSTPRIVATE(P_UVWMAX) 

      !$OMP DO COLLAPSE(3) SCHEDULE(STATIC) PRIVATE(K,J,I,UVW)
      DO K=0,KBAR
         DO J=0,JBAR
            DO I=0,IBAR
               UVW = ABS(UU(I,J,K)*RDXN(I)) + ABS(VV(I,J,K)*RDYN(J)) + ABS(WW(I,J,K)*RDZN(K))
               UVW = UVW + ABS(DP(I,J,K))
               IF (UVW>=P_UVWMAX) THEN
                  P_UVWMAX = UVW
                  P_ICFL=I
                  P_JCFL=J
                  P_KCFL=K
               ENDIF
            ENDDO
         ENDDO
      ENDDO
      !$OMP END DO NOWAIT
      !$OMP CRITICAL
      IF (P_UVWMAX>=UVWMAX) THEN
         UVWMAX = P_UVWMAX
         ICFL=P_ICFL
         JCFL=P_JCFL
         KCFL=P_KCFL
      ENDIF
      !$OMP END CRITICAL
      !$OMP END PARALLEL
   CASE(2)
      P_UVWMAX = UVWMAX
      !$OMP PARALLEL DEFAULT(NONE) &
      !$OMP SHARED(UVWMAX,ICFL,JCFL,KCFL,UU,VV,WW,RDXN,RDYN,RDZN,IBAR,JBAR,KBAR,DP) &
      !$OMP PRIVATE(P_ICFL,P_JCFL,P_KCFL) &
      !$OMP FIRSTPRIVATE(P_UVWMAX) 

      !$OMP DO COLLAPSE(3) SCHEDULE(STATIC) PRIVATE(K,J,I,UVW)
      DO K=0,KBAR
         DO J=0,JBAR
            DO I=0,IBAR
               UVW = SQRT( (UU(I,J,K)*RDXN(I))**2 + (VV(I,J,K)*RDYN(J))**2 + (WW(I,J,K)*RDZN(K))**2 )
               UVW = UVW + ABS(DP(I,J,K))
               IF (UVW>=P_UVWMAX) THEN
                  P_UVWMAX = UVW
                  P_ICFL=I
                  P_JCFL=J
                  P_KCFL=K
               ENDIF
            ENDDO
         ENDDO
      ENDDO
      !$OMP END DO NOWAIT
      !$OMP CRITICAL
      IF (P_UVWMAX>=UVWMAX) THEN
         UVWMAX = P_UVWMAX
         ICFL=P_ICFL
         JCFL=P_JCFL
         KCFL=P_KCFL
      ENDIF
      !$OMP END CRITICAL
      !$OMP END PARALLEL
   CASE(3)
      P_UVWMAX = UVWMAX
      !$OMP PARALLEL DEFAULT(NONE) &
      !$OMP SHARED(UVWMAX,ICFL,JCFL,KCFL,FVX,FVY,FVZ,RDXN,RDYN,RDZN,IBAR,JBAR,KBAR,DP) &
      !$OMP PRIVATE(P_ICFL,P_JCFL,P_KCFL) &
      !$OMP FIRSTPRIVATE(P_UVWMAX) 

      !$OMP DO COLLAPSE(3) SCHEDULE(STATIC) PRIVATE(K,J,I,UODX,VODY,WODZ,UVW)
      DO K=0,KBAR
         DO J=0,JBAR
            DO I=0,IBAR
               ! Experimental:
               ! The idea here is that basing the time scale off the acceleration should also account for
               ! VN (Von Neumann), GR (gravity), and BARO (baroclinic torque), or whatever other physics
               ! you decide to include in F_i.
               UODX = SQRT(ABS(FVX(I,J,K))*RDXN(I))
               VODY = SQRT(ABS(FVY(I,J,K))*RDYN(J))
               WODZ = SQRT(ABS(FVZ(I,J,K))*RDZN(K))
               UVW  = MAX(UODX,VODY,WODZ) + ABS(DP(I,J,K))
               IF (UVW>=P_UVWMAX) THEN
                  P_UVWMAX = UVW
                  P_ICFL = I
                  P_JCFL = J
                  P_KCFL = K
               ENDIF
            ENDDO
         ENDDO
      ENDDO
      !$OMP END DO NOWAIT
      !$OMP CRITICAL
      IF (P_UVWMAX>=UVWMAX) THEN
         UVWMAX = P_UVWMAX
         ICFL=P_ICFL
         JCFL=P_JCFL
         KCFL=P_KCFL
      ENDIF
      !$OMP END CRITICAL
      !$OMP END PARALLEL
END SELECT SELECT_VELOCITY_NORM

HEAT_TRANSFER_IF: IF (CHECK_HT) THEN
   WALL_LOOP: DO IW=1,N_EXTERNAL_WALL_CELLS+N_INTERNAL_WALL_CELLS
      WC=>WALL(IW)
      IF (WC%BOUNDARY_TYPE/=SOLID_BOUNDARY) CYCLE WALL_LOOP
      IIG = WC%IIG
      JJG = WC%JJG
      KKG = WC%KKG
      IF (N_TRACKED_SPECIES > 0) ZZ_GET(1:N_TRACKED_SPECIES) = ZZP(IIG,JJG,KKG,1:N_TRACKED_SPECIES)
      CALL GET_SPECIFIC_HEAT(ZZ_GET,CP,TMP(IIG,JJG,KKG))
      UVW = WC%HEAT_TRANS_COEF/(WC%RHO_F*CP)
      IF (UVW>=UVWMAX) THEN
         UVWMAX = UVW
         ICFL=IIG
         JCFL=JJG
         KCFL=KKG
      ENDIF
   ENDDO WALL_LOOP
ENDIF HEAT_TRANSFER_IF

GRAVITY_IF: IF (CHECK_GR) THEN ! resolve gravity waves
   UVWMAX = MAX(UVWMAX, SQRT(ABS(GVEC(1))*MAXVAL(RDX)),&
                        SQRT(ABS(GVEC(2))*MAXVAL(RDY)),&
                        SQRT(ABS(GVEC(3))*MAXVAL(RDZ)))
ENDIF GRAVITY_IF

UVWMAX = MAX(UVWMAX,IBM_UVWMAX) ! for moving immersed boundary method

CFL = DT*UVWMAX
 
! Determine max Von Neumann Number for fine grid calcs
 
PARABOLIC_IF: IF (DNS .OR. CHECK_VN) THEN
 
   MU_MAX = 0._EB
   P_MU_MAX = MU_MAX
   MUP => MU
   !$OMP PARALLEL DEFAULT(NONE) &
   !$OMP SHARED(KBAR,IBAR,JBAR,SOLID,CELL_INDEX,MUP,RHOP,MU_MAX,I_VN,J_VN,K_VN) &
   !$OMP PRIVATE(P_I_VN,P_J_VN,P_K_VN,P_MU_TMP) &
   !$OMP FIRSTPRIVATE(P_MU_MAX)

   !$OMP DO COLLAPSE(3) SCHEDULE(STATIC) PRIVATE(K,J,I)
   DO K=1,KBAR
      DO J=1,JBAR
         IILOOP_OpenMP: DO I=1,IBAR
            IF (SOLID(CELL_INDEX(I,J,K))) CYCLE IILOOP_OpenMP
            P_MU_TMP = MUP(I,J,K)/RHOP(I,J,K)
            IF (P_MU_TMP>=P_MU_MAX) THEN
               P_MU_MAX = P_MU_TMP
               P_I_VN=I
               P_J_VN=J
               P_K_VN=K
            ENDIF
         ENDDO IILOOP_OpenMP
      ENDDO
   ENDDO
   !$OMP END DO NOWAIT
   !$OMP CRITICAL
   IF (P_MU_MAX>=MU_MAX) THEN
      MU_MAX = P_MU_MAX
      I_VN=P_I_VN
      J_VN=P_J_VN
      K_VN=P_K_VN
   ENDIF
   !$OMP END CRITICAL
   !$OMP END PARALLEL
   
   IF (TWO_D) THEN
      R_DX2 = RDX(I_VN)**2 + RDZ(K_VN)**2
   ELSE
      R_DX2 = RDX(I_VN)**2 + RDY(J_VN)**2 + RDZ(K_VN)**2
   ENDIF

   MUTRM = MAX(RPR,RSC)*MU_MAX
   VN = DT*2._EB*R_DX2*MUTRM
 
ENDIF PARABOLIC_IF
 
! Adjust time step size if necessary
 
IF ((CFL<CFL_MAX.AND.VN<VN_MAX) .OR. LOCK_TIME_STEP) THEN
   DT_NEXT = DT
   IF (CFL<=CFL_MIN .AND. VN<VN_MIN .AND. .NOT.LOCK_TIME_STEP) THEN
      IF (     RESTRICT_TIME_STEP) DT_NEXT = MIN(1.1_EB*DT,DT_INIT)
      IF (.NOT.RESTRICT_TIME_STEP) DT_NEXT =     1.1_EB*DT
   ENDIF
ELSE
   DT = 0.9_EB*MIN( CFL_MAX/MAX(UVWMAX,1.E-10_EB) , VN_MAX/(2._EB*R_DX2*MAX(MUTRM,1.E-10_EB)) )
   CHANGE_TIME_STEP(NM) = .TRUE.
ENDIF

IF (PARTICLE_CFL .AND. PART_CFL>PARTICLE_CFL_MAX .AND. .NOT.LOCK_TIME_STEP) THEN
   DT = (PARTICLE_CFL_MAX/PART_CFL)*DT
   DT_NEXT = DT
ENDIF
 
END SUBROUTINE CHECK_STABILITY
 
 

SUBROUTINE BAROCLINIC_CORRECTION(T)
 
! Add baroclinic term to the momentum equation
 
USE MATH_FUNCTIONS, ONLY: EVALUATE_RAMP
REAL(EB), INTENT(IN) :: T
REAL(EB), POINTER, DIMENSION(:,:,:) :: UU=>NULL(),VV=>NULL(),WW=>NULL(),RHOP=>NULL(),HP=>NULL(),RHMK=>NULL(),RRHO=>NULL()
INTEGER  :: I,J,K,IC1,IC2,II,JJ,KK,IIG,JJG,KKG,IOR,IW
REAL(EB) :: P_EXTERNAL,TSI,TIME_RAMP_FACTOR,DUMMY
LOGICAL  :: INFLOW
TYPE(VENTS_TYPE), POINTER :: VT=>NULL()
TYPE(WALL_TYPE), POINTER :: WC=>NULL()

RHMK => WORK1 ! p=rho*(H-K)
RRHO => WORK2 ! reciprocal of rho
 
IF (PREDICTOR) THEN
   UU => U
   VV => V
   WW => W
   RHOP=>RHO
   HP => HS
ELSE
   UU => US
   VV => VS
   WW => WS
   RHOP=>RHOS
   HP => H
ENDIF

!$OMP PARALLEL DEFAULT(NONE) &
!$OMP SHARED(KBP1,JBP1,IBP1,RHMK,RHOP,HP,KRES,RRHO, &
!$OMP        N_EXTERNAL_WALL_CELLS,VENTS,T_BEGIN,T,DUMMY,UU,VV,WW, &
!$OMP        KBAR,JBAR,IBAR,CELL_INDEX,SOLID,FVX,FVY,FVZ,RDXN,RDYN,RDZN,TWO_D)

! Compute pressure and 1/rho in each grid cell

!$OMP DO COLLAPSE(3) SCHEDULE(STATIC) &
!$OMP PRIVATE(K,J,I) 
DO K=0,KBP1
   DO J=0,JBP1
      DO I=0,IBP1         
         RHMK(I,J,K) = RHOP(I,J,K)*(HP(I,J,K)-KRES(I,J,K))
         RRHO(I,J,K) = 1._EB/RHOP(I,J,K)
      ENDDO
   ENDDO
ENDDO
!$OMP END DO

! Set baroclinic term to zero at outflow boundaries and P_EXTERNAL at inflow boundaries

!$OMP DO SCHEDULE(STATIC) &
!$OMP PRIVATE(IW,VT,TSI,TIME_RAMP_FACTOR,P_EXTERNAL,II,JJ,KK,IOR,IIG,JJG,KKG,INFLOW,WC,WALL)
EXTERNAL_WALL_LOOP: DO IW=1,N_EXTERNAL_WALL_CELLS
   WC=>WALL(IW)
   IF (WC%BOUNDARY_TYPE/=OPEN_BOUNDARY) CYCLE EXTERNAL_WALL_LOOP
   IF (WC%VENT_INDEX>0) THEN
      VT => VENTS(WC%VENT_INDEX)
      IF (ABS(WC%TW-T_BEGIN)<=SPACING(WC%TW) .AND. VT%PRESSURE_RAMP_INDEX>=1) THEN
         TSI = T
      ELSE
         TSI = T - T_BEGIN
      ENDIF
      TIME_RAMP_FACTOR = EVALUATE_RAMP(TSI,DUMMY,VT%PRESSURE_RAMP_INDEX)
      P_EXTERNAL = TIME_RAMP_FACTOR*VT%DYNAMIC_PRESSURE
   ENDIF
   II  = WC%II
   JJ  = WC%JJ
   KK  = WC%KK
   IOR = WC%IOR
   IIG = WC%IIG
   JJG = WC%JJG
   KKG = WC%KKG
   INFLOW = .FALSE.
   SELECT CASE(IOR)
      CASE( 1)
         IF (UU(II,JJ,KK)>=0._EB)   INFLOW = .TRUE.
      CASE(-1)
         IF (UU(II-1,JJ,KK)<=0._EB) INFLOW = .TRUE.
      CASE( 2)
         IF (VV(II,JJ,KK)>=0._EB)   INFLOW = .TRUE.
      CASE(-2)
         IF (VV(II,JJ-1,KK)<=0._EB) INFLOW = .TRUE.
      CASE( 3)
         IF (WW(II,JJ,KK)>=0._EB)   INFLOW = .TRUE.
      CASE(-3)
         IF (WW(II,JJ,KK-1)<=0._EB) INFLOW = .TRUE.
   END SELECT
   IF (INFLOW) THEN
      RHMK(II,JJ,KK) = 2._EB*P_EXTERNAL - RHMK(IIG,JJG,KKG)  ! Pressure at inflow boundary is P_EXTERNAL
   ELSE
      RHMK(II,JJ,KK) = -RHMK(IIG,JJG,KKG)                    ! No baroclinic correction for outflow boundary
   ENDIF
ENDDO EXTERNAL_WALL_LOOP
!$OMP END DO

! Compute baroclinic term in the x momentum equation

!$OMP DO COLLAPSE(3) SCHEDULE(STATIC) &
!$OMP PRIVATE(K,J,I,IC1,IC2)
DO K=1,KBAR
   DO J=1,JBAR
      DO I=0,IBAR
         IC1 = CELL_INDEX(I,J,K)
         IC2 = CELL_INDEX(I+1,J,K)
         IF (SOLID(IC1) .OR. SOLID(IC2)) CYCLE
         FVX(I,J,K) = FVX(I,J,K) - 0.5_EB*(RHMK(I,J,K)+RHMK(I+1,J,K))*(RRHO(I+1,J,K)-RRHO(I,J,K))*RDXN(I)
      ENDDO
   ENDDO
ENDDO
!$OMP END DO NOWAIT

! Compute baroclinic term in the y momentum equation
 
IF (.NOT.TWO_D) THEN
   !$OMP DO COLLAPSE(3) SCHEDULE(STATIC) &
   !$OMP PRIVATE(K,J,I,IC1,IC2)
   DO K=1,KBAR
      DO J=0,JBAR
         DO I=1,IBAR
            IC1 = CELL_INDEX(I,J,K)
            IC2 = CELL_INDEX(I,J+1,K)
            IF (SOLID(IC1) .OR. SOLID(IC2)) CYCLE
            FVY(I,J,K) = FVY(I,J,K) - 0.5_EB*(RHMK(I,J,K)+RHMK(I,J+1,K))*(RRHO(I,J+1,K)-RRHO(I,J,K))*RDYN(J)
         ENDDO
      ENDDO
   ENDDO
   !$OMP END DO NOWAIT
ENDIF

! Compute baroclinic term in the z momentum equation

!$OMP DO COLLAPSE(3) SCHEDULE(STATIC) &
!$OMP PRIVATE(K,J,I,IC1,IC2)
DO K=0,KBAR
   DO J=1,JBAR
      DO I=1,IBAR
         IC1 = CELL_INDEX(I,J,K)
         IC2 = CELL_INDEX(I,J,K+1)
         IF (SOLID(IC1) .OR. SOLID(IC2)) CYCLE
         FVZ(I,J,K) = FVZ(I,J,K) - 0.5_EB*(RHMK(I,J,K)+RHMK(I,J,K+1))*(RRHO(I,J,K+1)-RRHO(I,J,K))*RDZN(K)
      ENDDO
   ENDDO
ENDDO
!$OMP END DO NOWAIT

!$OMP END PARALLEL
 
END SUBROUTINE BAROCLINIC_CORRECTION


!===========================================================================
! The following are experimental routines for implementation of a second-
! order immersed boundary method (IBM). ~RJM
!===========================================================================

SUBROUTINE IBM_VELOCITY_FLUX(NM)

USE COMPLEX_GEOMETRY, ONLY: TRILINEAR,GETX,GETU,GETGRAD,GET_VELO_IBM
USE TURBULENCE, ONLY: VELTAN2D,VELTAN3D

INTEGER, INTENT(IN) :: NM
REAL(EB), POINTER, DIMENSION(:,:,:) :: UU,VV,WW,DP,RHOP,PP,HP, &
                                       UBAR,VBAR,WBAR, &
                                       DUDX,DUDY,DUDZ, &
                                       DVDX,DVDY,DVDZ, &
                                       DWDX,DWDY,DWDZ
REAL(EB) :: U_IBM,V_IBM,W_IBM,DN, &
            U_ROT,V_ROT,W_ROT, &
            PE,PW,PN,PS,PT,PB, &
            U_DATA(0:1,0:1,0:1),XI(3),DXI(3),DXC(3),XVELO(3),XGEOM(3),XCELL(3),XEDGX(3),XEDGY(3),XEDGZ(3),XSURF(3), &
            U_VEC(3),U_GEOM(3),N_VEC(3),DIVU,GRADU(3,3),GRADP(3),TAU_IJ(3,3), &
            MU_WALL,RRHO,MUA,DUUDT,DVVDT,DWWDT,DELTA,WT, NXNY_REAL,NX_REAL,IC_REAL,XV(3),TMP_SUM
INTEGER :: I,J,K,NG,IJK(3),I_VEL,IP1,IM1,JP1,JM1,KP1,KM1,ITMP,TRI_INDEX,IERR,N_CELLS
TYPE(GEOMETRY_TYPE), POINTER :: G=>NULL()
TYPE(CUTCELL_LINKED_LIST_TYPE), POINTER :: CL=>NULL()

! References:
!
! E.A. Fadlun, R. Verzicco, P. Orlandi, and J. Mohd-Yusof. Combined Immersed-
! Boundary Finite-Difference Methods for Three-Dimensional Complex Flow
! Simulations. J. Comp. Phys. 161:35-60, 2000.
!
! R. McDermott. A Direct-Forcing Immersed Boundary Method with Dynamic Velocity
! Interpolation. APS/DFD Annual Meeting, Long Beach, CA, Nov. 2010.
 
IF (PREDICTOR) THEN
   UU => U
   VV => V
   WW => W
   DP => D
   RHOP => RHOS
   HP => H
ELSE
   UU => US
   VV => VS
   WW => WS
   DP => DS
   RHOP => RHO
   HP => HS
ENDIF

IF (IMMERSED_BOUNDARY_METHOD==2) THEN
   PP => WORK1
   UBAR => WORK2
   VBAR => WORK3
   WBAR => WORK4
   DUDX => WORK5
   DVDY => WORK6
   DWDZ => WORK7
     
   PP = 0._EB
   UBAR = 0._EB
   VBAR = 0._EB
   WBAR = 0._EB
   DUDX=0._EB
   DVDY=0._EB
   DWDZ=0._EB
   
   DUDY => IBM_SAVE1
   DUDZ => IBM_SAVE2
   DVDX => IBM_SAVE3
   DVDZ => IBM_SAVE4
   DWDX => IBM_SAVE5
   DWDY => IBM_SAVE6
   
   DO K=0,KBP1
      DO J=0,JBP1
         DO I=0,IBP1
         
            IP1 = MIN(I+1,IBP1)
            JP1 = MIN(J+1,JBP1)
            KP1 = MIN(K+1,KBP1)
            IM1 = MAX(I-1,0)   
            JM1 = MAX(J-1,0)
            KM1 = MAX(K-1,0)
         
            P_MASK_IF: IF (P_MASK(I,J,K)>-1) THEN
               PP(I,J,K) = RHOP(I,J,K)*(HP(I,J,K)-KRES(I,J,K))
               UBAR(I,J,K) = 0.5_EB*(UU(I,J,K)+UU(IM1,J,K))
               VBAR(I,J,K) = 0.5_EB*(VV(I,J,K)+VV(I,JM1,K))
               WBAR(I,J,K) = 0.5_EB*(WW(I,J,K)+WW(I,J,KM1))
               DUDX(I,J,K) = (UU(I,J,K)-UU(IM1,J,K))/DX(I)
               DVDY(I,J,K) = (VV(I,J,K)-VV(I,JM1,K))/DY(J)
               DWDZ(I,J,K) = (WW(I,J,K)-WW(I,J,KM1))/DZ(K)
            ENDIF P_MASK_IF
            
            IF (U_MASK(I,J,K)==-1 .AND. U_MASK(I,JP1,K)==-1) DUDY(I,J,K)=0._EB
            IF (U_MASK(I,J,K)==-1 .AND. U_MASK(I,J,KP1)==-1) DUDZ(I,J,K)=0._EB
            
            IF (V_MASK(I,J,K)==-1 .AND. V_MASK(IP1,J,K)==-1) DVDX(I,J,K)=0._EB
            IF (V_MASK(I,J,K)==-1 .AND. V_MASK(I,J,KP1)==-1) DVDZ(I,J,K)=0._EB
            
            IF (W_MASK(I,J,K)==-1 .AND. W_MASK(IP1,J,K)==-1) DWDX(I,J,K)=0._EB
            IF (W_MASK(I,J,K)==-1 .AND. W_MASK(I,JP1,K)==-1) DWDY(I,J,K)=0._EB
            
         ENDDO
      ENDDO
   ENDDO
   
   IF (TWO_D) THEN
      DELTA = MIN(DX(1),DZ(1))
   ELSE
      DELTA = MIN(DX(1),DY(1),DZ(1))
   ENDIF
   
ENDIF

GEOM_LOOP: DO NG=1,N_GEOM

   G => GEOMETRY(NG)
   
   IF ( G%MAX_I(NM)<G%MIN_I(NM) .OR. &
        G%MAX_J(NM)<G%MIN_J(NM) .OR. &
        G%MAX_K(NM)<G%MIN_K(NM) ) CYCLE GEOM_LOOP
   
   XGEOM = (/G%X,G%Y,G%Z/)
   
   DO K=G%MIN_K(NM),G%MAX_K(NM)
      DO J=G%MIN_J(NM),G%MAX_J(NM)
         DO I=G%MIN_I(NM),G%MAX_I(NM)
            IF (U_MASK(I,J,K)==1) CYCLE ! point is in gas phase
         
            IJK   = (/I,J,K/)
            XVELO = (/X(I),YC(J),ZC(K)/)
            XCELL = (/XC(I),YC(J),ZC(K)/)
            XEDGX = (/XC(I),Y(J),Z(K)/)
            XEDGY = (/X(I),YC(J),Z(K)/)
            XEDGZ = (/X(I),Y(J),ZC(K)/)
            DXC   = (/DX(I),DY(J),DZ(K)/)
            WT    = 0._EB
  
            SELECT CASE(U_MASK(I,J,K))
               CASE(-1)
                  U_ROT = (XVELO(3)-XGEOM(3))*G%OMEGA_Y - (XVELO(2)-XGEOM(2))*G%OMEGA_Z
                  U_IBM = G%U + U_ROT
               CASE(0)
                  SELECT_METHOD1: SELECT CASE(IMMERSED_BOUNDARY_METHOD)
                     CASE(0)
                        CYCLE ! treat as gas phase cell
                     CASE(1)
                        U_ROT = (XVELO(3)-XGEOM(3))*G%OMEGA_Y - (XVELO(2)-XGEOM(2))*G%OMEGA_Z
                        CALL GETX(XI,XVELO,NG)
                        CALL GETU(U_DATA,DXI,XI,1,NM)
                        U_IBM = TRILINEAR(U_DATA,DXI,DXC)
                        IF (DNS) U_IBM = 0.5_EB*(U_IBM+(G%U+U_ROT)) ! linear profile
                        IF (LES) U_IBM = 0.9_EB*(U_IBM+(G%U+U_ROT)) ! power law
                     CASE(2)
                        IP1 = MIN(I+1,IBP1)
                        JP1 = MIN(J+1,JBP1)
                        KP1 = MIN(K+1,KBP1)
                        IM1 = MAX(I-1,0)
                        JM1 = MAX(J-1,0)
                        KM1 = MAX(K-1,0)
 
                        CALL GETX(XI,XVELO,NG)                  ! find interpolation point XI for tensors
                        XSURF = XVELO-(XI-XVELO)                ! point on the surface of geometry
                        N_VEC = XVELO-XSURF                     ! normal from surface to velocity point
                        DN    = SQRT(DOT_PRODUCT(N_VEC,N_VEC))  ! distance from surface to velocity point
                        N_VEC = N_VEC/DN                        ! unit normal
                        
                        U_VEC  = (/UU(I,J,K),0.5_EB*(VBAR(I,J,K)+VBAR(IP1,J,K)),0.5_EB*(WBAR(I,J,K)+WBAR(IP1,J,K))/)
                        U_ROT  = (XSURF(3)-XGEOM(3))*G%OMEGA_Y - (XSURF(2)-XGEOM(2))*G%OMEGA_Z
                        V_ROT  = (XSURF(1)-XGEOM(1))*G%OMEGA_Z - (XSURF(3)-XGEOM(3))*G%OMEGA_X
                        W_ROT  = (XSURF(2)-XGEOM(2))*G%OMEGA_X - (XSURF(1)-XGEOM(1))*G%OMEGA_Y
                        U_GEOM = (/G%U+U_ROT,G%V+V_ROT,G%W+W_ROT/)
                        
                        ! store interpolated value
                        CALL GETU(U_DATA,DXI,XI,1,NM)
                        U_IBM = TRILINEAR(U_DATA,DXI,DXC)
                        IF (DNS) U_IBM = 0.5_EB*(U_IBM+(G%U+U_ROT)) ! linear profile
                        IF (LES) U_IBM = 0.9_EB*(U_IBM+(G%U+U_ROT)) ! power law

                        DIVU = 0.5_EB*(DP(I,J,K)+DP(IP1,J,K))
                        
                        ! compute GRADU at point XI
                        CALL GETGRAD(U_DATA,DXI,XI,XCELL,IJK,1,1,NM); GRADU(1,1) = TRILINEAR(U_DATA,DXI,DXC)
                        CALL GETGRAD(U_DATA,DXI,XI,XEDGZ,IJK,1,2,NM); GRADU(1,2) = TRILINEAR(U_DATA,DXI,DXC)
                        CALL GETGRAD(U_DATA,DXI,XI,XEDGY,IJK,1,3,NM); GRADU(1,3) = TRILINEAR(U_DATA,DXI,DXC)
                        CALL GETGRAD(U_DATA,DXI,XI,XEDGZ,IJK,2,1,NM); GRADU(2,1) = TRILINEAR(U_DATA,DXI,DXC)
                        CALL GETGRAD(U_DATA,DXI,XI,XCELL,IJK,2,2,NM); GRADU(2,2) = TRILINEAR(U_DATA,DXI,DXC)
                        CALL GETGRAD(U_DATA,DXI,XI,XEDGX,IJK,2,3,NM); GRADU(2,3) = TRILINEAR(U_DATA,DXI,DXC)
                        CALL GETGRAD(U_DATA,DXI,XI,XEDGY,IJK,3,1,NM); GRADU(3,1) = TRILINEAR(U_DATA,DXI,DXC)
                        CALL GETGRAD(U_DATA,DXI,XI,XEDGX,IJK,3,2,NM); GRADU(3,2) = TRILINEAR(U_DATA,DXI,DXC)
                        CALL GETGRAD(U_DATA,DXI,XI,XCELL,IJK,3,3,NM); GRADU(3,3) = TRILINEAR(U_DATA,DXI,DXC)
                        
                        ! compute GRADP at point XVELO
                        PE = PP(IP1,J,K)
                        PW = PP(I,J,K)
                        PN = 0.25_EB*(PP(I,J,K)+PP(IP1,J,K)+PP(I,JP1,K)+PP(IP1,JP1,K))
                        PS = 0.25_EB*(PP(I,J,K)+PP(IP1,J,K)+PP(I,JM1,K)+PP(IP1,JM1,K))
                        PT = 0.25_EB*(PP(I,J,K)+PP(IP1,J,K)+PP(I,J,KP1)+PP(IP1,J,KP1))
                        PB = 0.25_EB*(PP(I,J,K)+PP(IP1,J,K)+PP(I,J,KM1)+PP(IP1,J,KM1))
                  
                        GRADP(1) = (PE-PW)/DXN(I)
                        GRADP(2) = (PN-PS)/DY(J)
                        GRADP(3) = (PT-PB)/DZ(K)
 
                        RRHO  = 2._EB/(RHOP(I,J,K)+RHOP(IP1,J,K))
                        !!MUA = 0.5_EB*(MU(I,J,K)+MU(IP1,J,K)) ! strictly speaking, should be interpolated to XI
                        CALL GETU(U_DATA,DXI,XI,4,NM); MUA = TRILINEAR(U_DATA,DXI,DXC)
                  
                        TAU_IJ(1,1) = -MUA*(GRADU(1,1)-TWTH*DIVU)
                        TAU_IJ(2,2) = -MUA*(GRADU(2,2)-TWTH*DIVU)
                        TAU_IJ(3,3) = -MUA*(GRADU(3,3)-TWTH*DIVU)
                        TAU_IJ(1,2) = -MUA*(GRADU(1,2)+GRADU(2,1))
                        TAU_IJ(1,3) = -MUA*(GRADU(1,3)+GRADU(3,1))
                        TAU_IJ(2,3) = -MUA*(GRADU(2,3)+GRADU(3,2))
                        TAU_IJ(2,1) = TAU_IJ(1,2)
                        TAU_IJ(3,1) = TAU_IJ(1,3)
                        TAU_IJ(3,2) = TAU_IJ(2,3)
                  
                        I_VEL = 1

                        ITMP = MIN(5000,NINT(0.5_EB*(TMP(I,J,K)+TMP(IP1,J,K))))
                        MU_WALL = MU_Z(ITMP,0)*SPECIES_MIXTURE(0)%MW
                        
                        !! use 2D for debug
                        !U_VEC(2)=U_VEC(3)
                        !U_GEOM(2)=U_GEOM(3)
                        !N_VEC(2)=N_VEC(3)
                        !GRADU(1,2)=GRADU(1,3)
                        !GRADU(2,2)=GRADU(3,3)
                        !GRADU(2,1)=GRADU(3,1)
                        !GRADP(2)=GRADP(3)
                        !TAU_IJ(1,2)=TAU_IJ(1,3)
                        !TAU_IJ(2,2)=TAU_IJ(3,3)
                        !TAU_IJ(2,1)=TAU_IJ(3,1)
                        
                        !U_IBM = VELTAN2D( U_VEC(1:2),&
                        !                  U_GEOM(1:2),&
                        !                  N_VEC(1:2),&
                        !                  DN,DIVU,&
                        !                  GRADU(1:2,1:2),&
                        !                  GRADP(1:2),&
                        !                  TAU_IJ(1:2,1:2),&
                        !                  DT,RRHO,MUA,I_VEL)
                        
                        WT = MIN(1._EB,(DN/DELTA)**7._EB)
                        
                        U_IBM = VELTAN3D(U_VEC,U_GEOM,N_VEC,DN,DIVU,GRADU,GRADP,TAU_IJ,DT,RRHO,MU_WALL,I_VEL,G%ROUGHNESS,U_IBM)
                        
                  END SELECT SELECT_METHOD1
            END SELECT
            
            IF (PREDICTOR) DUUDT = (U_IBM-U(I,J,K))/DT
            IF (CORRECTOR) DUUDT = (2._EB*U_IBM-(U(I,J,K)+US(I,J,K)))/DT
            
            FVX(I,J,K) = WT*FVX(I,J,K) + (1._EB-WT)*(-RDXN(I)*(HP(I+1,J,K)-HP(I,J,K)) - DUUDT)
        
         ENDDO
      ENDDO
   ENDDO
   
   TWO_D_IF: IF (.NOT.TWO_D) THEN
      DO K=G%MIN_K(NM),G%MAX_K(NM)
         DO J=G%MIN_J(NM),G%MAX_J(NM)
            DO I=G%MIN_I(NM),G%MAX_I(NM)
               IF (V_MASK(I,J,K)==1) CYCLE ! point is in gas phase
         
               IJK   = (/I,J,K/)
               XVELO = (/XC(I),Y(J),ZC(K)/)
               XCELL = (/XC(I),YC(J),ZC(K)/)
               XEDGX = (/XC(I),Y(J),Z(K)/)
               XEDGY = (/X(I),YC(J),Z(K)/)
               XEDGZ = (/X(I),Y(J),ZC(K)/)
               DXC   = (/DX(I),DY(J),DZ(K)/)
               WT    = 0._EB
         
               SELECT CASE(V_MASK(I,J,K))
                  CASE(-1)
                     V_ROT = (XVELO(1)-XGEOM(1))*G%OMEGA_Z - (XVELO(3)-XGEOM(3))*G%OMEGA_X
                     V_IBM = G%V + V_ROT
                  CASE(0)
                     SELECT_METHOD2: SELECT CASE(IMMERSED_BOUNDARY_METHOD)
                        CASE(0)
                           CYCLE
                        CASE(1)
                           V_ROT = (XVELO(1)-XGEOM(1))*G%OMEGA_Z - (XVELO(3)-XGEOM(3))*G%OMEGA_X
                           CALL GETX(XI,XVELO,NG)
                           CALL GETU(U_DATA,DXI,XI,2,NM)
                           V_IBM = TRILINEAR(U_DATA,DXI,DXC)
                           IF (DNS) V_IBM = 0.5_EB*(V_IBM+(G%V+V_ROT))
                           IF (LES) V_IBM = 0.9_EB*(V_IBM+(G%V+V_ROT))
                        CASE(2)
                           IP1 = MIN(I+1,IBP1)
                           JP1 = MIN(J+1,JBP1)
                           KP1 = MIN(K+1,KBP1)
                           IM1 = MAX(I-1,0)
                           JM1 = MAX(J-1,0)
                           KM1 = MAX(K-1,0)
 
                           CALL GETX(XI,XVELO,NG)                  ! find interpolation point XI for tensors
                           XSURF = XVELO-(XI-XVELO)                ! point on the surface of geometry
                           N_VEC = XVELO-XSURF                     ! normal from surface to velocity point
                           DN    = SQRT(DOT_PRODUCT(N_VEC,N_VEC))  ! distance from surface to velocity point
                           N_VEC = N_VEC/DN                        ! unit normal
                        
                           U_VEC  = (/0.5_EB*(UBAR(I,J,K)+UBAR(I,JP1,K)),VV(I,J,K),0.5_EB*(WBAR(I,J,K)+WBAR(I,JP1,K))/)
                           U_ROT  = (XSURF(3)-XGEOM(3))*G%OMEGA_Y - (XSURF(2)-XGEOM(2))*G%OMEGA_Z
                           V_ROT  = (XSURF(1)-XGEOM(1))*G%OMEGA_Z - (XSURF(3)-XGEOM(3))*G%OMEGA_X
                           W_ROT  = (XSURF(2)-XGEOM(2))*G%OMEGA_X - (XSURF(1)-XGEOM(1))*G%OMEGA_Y
                           U_GEOM = (/G%U+U_ROT,G%V+V_ROT,G%W+W_ROT/)
                           
                           ! store interpolated value
                           CALL GETU(U_DATA,DXI,XI,2,NM)
                           V_IBM = TRILINEAR(U_DATA,DXI,DXC)
                           IF (DNS) V_IBM = 0.5_EB*(V_IBM+(G%V+V_ROT))
                           IF (LES) V_IBM = 0.9_EB*(V_IBM+(G%V+V_ROT))

                           DIVU = 0.5_EB*(DP(I,J,K)+DP(I,JP1,K))
                        
                           ! compute GRADU at point XI
                           CALL GETGRAD(U_DATA,DXI,XI,XCELL,IJK,1,1,NM); GRADU(1,1) = TRILINEAR(U_DATA,DXI,DXC)
                           CALL GETGRAD(U_DATA,DXI,XI,XEDGZ,IJK,1,2,NM); GRADU(1,2) = TRILINEAR(U_DATA,DXI,DXC)
                           CALL GETGRAD(U_DATA,DXI,XI,XEDGY,IJK,1,3,NM); GRADU(1,3) = TRILINEAR(U_DATA,DXI,DXC)
                           CALL GETGRAD(U_DATA,DXI,XI,XEDGZ,IJK,2,1,NM); GRADU(2,1) = TRILINEAR(U_DATA,DXI,DXC)
                           CALL GETGRAD(U_DATA,DXI,XI,XCELL,IJK,2,2,NM); GRADU(2,2) = TRILINEAR(U_DATA,DXI,DXC)
                           CALL GETGRAD(U_DATA,DXI,XI,XEDGX,IJK,2,3,NM); GRADU(2,3) = TRILINEAR(U_DATA,DXI,DXC)
                           CALL GETGRAD(U_DATA,DXI,XI,XEDGY,IJK,3,1,NM); GRADU(3,1) = TRILINEAR(U_DATA,DXI,DXC)
                           CALL GETGRAD(U_DATA,DXI,XI,XEDGX,IJK,3,2,NM); GRADU(3,2) = TRILINEAR(U_DATA,DXI,DXC)
                           CALL GETGRAD(U_DATA,DXI,XI,XCELL,IJK,3,3,NM); GRADU(3,3) = TRILINEAR(U_DATA,DXI,DXC)
                        
                           ! compute GRADP at point XVELO
                           PE = 0.25_EB*(PP(I,J,K)+PP(IP1,J,K)+PP(I,JP1,K)+PP(IP1,JP1,K))
                           PW = 0.25_EB*(PP(I,J,K)+PP(IM1,J,K)+PP(I,JP1,K)+PP(IM1,JP1,K))
                           PN = PP(I,JP1,K)
                           PS = PP(I,J,K)
                           PT = 0.25_EB*(PP(I,J,K)+PP(I,J,KP1)+PP(I,JP1,K)+PP(I,JP1,KP1))
                           PB = 0.25_EB*(PP(I,J,K)+PP(I,J,KM1)+PP(I,JP1,K)+PP(I,JP1,KM1))
                  
                           GRADP(1) = (PE-PW)/DX(I)
                           GRADP(2) = (PN-PS)/DYN(J)
                           GRADP(3) = (PT-PB)/DZ(K)
 
                           RRHO  = 2._EB/(RHOP(I,J,K)+RHOP(I,JP1,K))
                           !!MUA = 0.5_EB*(MU(I,J,K)+MU(I,JP1,K)) ! strictly speaking, should be interpolated to XI
                           CALL GETU(U_DATA,DXI,XI,4,NM); MUA = TRILINEAR(U_DATA,DXI,DXC)
                  
                           TAU_IJ(1,1) = -MUA*(GRADU(1,1)-TWTH*DIVU)
                           TAU_IJ(2,2) = -MUA*(GRADU(2,2)-TWTH*DIVU)
                           TAU_IJ(3,3) = -MUA*(GRADU(3,3)-TWTH*DIVU)
                           TAU_IJ(1,2) = -MUA*(GRADU(1,2)+GRADU(2,1))
                           TAU_IJ(1,3) = -MUA*(GRADU(1,3)+GRADU(3,1))
                           TAU_IJ(2,3) = -MUA*(GRADU(2,3)+GRADU(3,2))
                           TAU_IJ(2,1) = TAU_IJ(1,2)
                           TAU_IJ(3,1) = TAU_IJ(1,3)
                           TAU_IJ(3,2) = TAU_IJ(2,3)
                  
                           I_VEL = 2

                           ITMP = MIN(5000,NINT(0.5_EB*(TMP(I,J,K)+TMP(I,JP1,K))))
                           MU_WALL = MU_Z(ITMP,0)*SPECIES_MIXTURE(0)%MW
                           
                           WT = MIN(1._EB,(DN/DELTA)**7._EB)
                           
                           V_IBM = VELTAN3D(U_VEC,U_GEOM,N_VEC,DN,DIVU,GRADU,GRADP,TAU_IJ,DT,RRHO,MU_WALL,I_VEL,G%ROUGHNESS,V_IBM)
                           
                     END SELECT SELECT_METHOD2
               END SELECT
               
               IF (PREDICTOR) DVVDT = (V_IBM-V(I,J,K))/DT
               IF (CORRECTOR) DVVDT = (2._EB*V_IBM-(V(I,J,K)+VS(I,J,K)))/DT
         
               FVY(I,J,K) = WT*FVY(I,J,K) + (1._EB-WT)*(-RDYN(J)*(HP(I,J+1,K)-HP(I,J,K)) - DVVDT)
         
            ENDDO
         ENDDO 
      ENDDO
   ENDIF TWO_D_IF
   
   DO K=G%MIN_K(NM),G%MAX_K(NM)
      DO J=G%MIN_J(NM),G%MAX_J(NM)
         DO I=G%MIN_I(NM),G%MAX_I(NM)
            IF (W_MASK(I,J,K)==1) CYCLE
         
            IJK   = (/I,J,K/)
            XVELO = (/XC(I),YC(J),Z(K)/)
            XCELL = (/XC(I),YC(J),ZC(K)/)
            XEDGX = (/XC(I),Y(J),Z(K)/)
            XEDGY = (/X(I),YC(J),Z(K)/)
            XEDGZ = (/X(I),Y(J),ZC(K)/)
            DXC   = (/DX(I),DY(J),DZ(K)/)
            WT    = 0._EB
            
            SELECT CASE(W_MASK(I,J,K))
               CASE(-1)
                  W_ROT = (XVELO(2)-XGEOM(2))*G%OMEGA_X - (XVELO(1)-XGEOM(1))*G%OMEGA_Y
                  W_IBM = G%W + W_ROT
               CASE(0)
                  SELECT_METHOD3: SELECT CASE(IMMERSED_BOUNDARY_METHOD)
                     CASE(0)
                        CYCLE
                     CASE(1)
                        W_ROT = (XVELO(2)-XGEOM(2))*G%OMEGA_X - (XVELO(1)-XGEOM(1))*G%OMEGA_Y
                        CALL GETX(XI,XVELO,NG)
                        CALL GETU(U_DATA,DXI,XI,3,NM)
                        W_IBM = TRILINEAR(U_DATA,DXI,DXC)
                        IF (DNS) W_IBM = 0.5_EB*(W_IBM+(G%W+W_ROT)) ! linear profile
                        IF (LES) W_IBM = 0.9_EB*(W_IBM+(G%W+W_ROT)) ! power law
                     CASE(2)
                        IP1 = MIN(I+1,IBP1)
                        JP1 = MIN(J+1,JBP1)
                        KP1 = MIN(K+1,KBP1)
                        IM1 = MAX(I-1,0)
                        JM1 = MAX(J-1,0)
                        KM1 = MAX(K-1,0)
                                                
                        CALL GETX(XI,XVELO,NG)                  ! find interpolation point XI for tensors
                        XSURF = XVELO-(XI-XVELO)                ! point on the surface of geometry
                        N_VEC = XVELO-XSURF                     ! normal from surface to velocity point
                        DN    = SQRT(DOT_PRODUCT(N_VEC,N_VEC))  ! distance from surface to velocity point
                        N_VEC = N_VEC/DN                        ! unit normal
                        
                        U_VEC  = (/0.5_EB*(UBAR(I,J,K)+UBAR(I,J,KP1)),0.5_EB*(VBAR(I,J,K)+VBAR(I,J,KP1)),WW(I,J,K)/)
                        U_ROT  = (XSURF(3)-XGEOM(3))*G%OMEGA_Y - (XSURF(2)-XGEOM(2))*G%OMEGA_Z
                        V_ROT  = (XSURF(1)-XGEOM(1))*G%OMEGA_Z - (XSURF(3)-XGEOM(3))*G%OMEGA_X
                        W_ROT  = (XSURF(2)-XGEOM(2))*G%OMEGA_X - (XSURF(1)-XGEOM(1))*G%OMEGA_Y
                        U_GEOM = (/G%U+U_ROT,G%V+V_ROT,G%W+W_ROT/)
                        
                        ! store interpolated value
                        CALL GETU(U_DATA,DXI,XI,3,NM)
                        W_IBM = TRILINEAR(U_DATA,DXI,DXC)
                        IF (DNS) W_IBM = 0.5_EB*(W_IBM+(G%W+W_ROT)) ! linear profile
                        IF (LES) W_IBM = 0.9_EB*(W_IBM+(G%W+W_ROT)) ! power law
                        
                        DIVU = 0.5_EB*(DP(I,J,K)+DP(I,J,KP1))
                       
                        ! compute GRADU at point XI
                        CALL GETGRAD(U_DATA,DXI,XI,XCELL,IJK,1,1,NM); GRADU(1,1) = TRILINEAR(U_DATA,DXI,DXC)
                        CALL GETGRAD(U_DATA,DXI,XI,XEDGZ,IJK,1,2,NM); GRADU(1,2) = TRILINEAR(U_DATA,DXI,DXC)
                        CALL GETGRAD(U_DATA,DXI,XI,XEDGY,IJK,1,3,NM); GRADU(1,3) = TRILINEAR(U_DATA,DXI,DXC)
                        CALL GETGRAD(U_DATA,DXI,XI,XEDGZ,IJK,2,1,NM); GRADU(2,1) = TRILINEAR(U_DATA,DXI,DXC)
                        CALL GETGRAD(U_DATA,DXI,XI,XCELL,IJK,2,2,NM); GRADU(2,2) = TRILINEAR(U_DATA,DXI,DXC)
                        CALL GETGRAD(U_DATA,DXI,XI,XEDGX,IJK,2,3,NM); GRADU(2,3) = TRILINEAR(U_DATA,DXI,DXC)
                        CALL GETGRAD(U_DATA,DXI,XI,XEDGY,IJK,3,1,NM); GRADU(3,1) = TRILINEAR(U_DATA,DXI,DXC)
                        CALL GETGRAD(U_DATA,DXI,XI,XEDGX,IJK,3,2,NM); GRADU(3,2) = TRILINEAR(U_DATA,DXI,DXC)
                        CALL GETGRAD(U_DATA,DXI,XI,XCELL,IJK,3,3,NM); GRADU(3,3) = TRILINEAR(U_DATA,DXI,DXC)
                  
                        ! compute GRADP at point XVELO
                        PE = 0.25_EB*(PP(I,J,K)+PP(I,J,KP1)+PP(IP1,J,K)+PP(IP1,J,KP1))
                        PW = 0.25_EB*(PP(I,J,K)+PP(I,J,KP1)+PP(IM1,J,K)+PP(IM1,J,KP1))
                        PN = 0.25_EB*(PP(I,J,K)+PP(I,J,KP1)+PP(I,JP1,K)+PP(I,JP1,KP1))
                        PS = 0.25_EB*(PP(I,J,K)+PP(I,J,KP1)+PP(I,JM1,K)+PP(I,JM1,KP1))
                        PT = PP(I,J,KP1)
                        PB = PP(I,J,K)
                  
                        GRADP(1) = (PE-PW)/DX(I)
                        GRADP(2) = (PN-PS)/DY(J)
                        GRADP(3) = (PT-PB)/DZN(K)
 
                        RRHO  = 2._EB/(RHOP(I,J,K)+RHOP(I,J,KP1))
                        !!MUA = 0.5_EB*(MU(I,J,K)+MU(I,J,KP1)) ! strictly speaking, should be interpolated to XI
                        CALL GETU(U_DATA,DXI,XI,4,NM); MUA = TRILINEAR(U_DATA,DXI,DXC)
                  
                        TAU_IJ(1,1) = -MUA*(GRADU(1,1)-TWTH*DIVU)
                        TAU_IJ(2,2) = -MUA*(GRADU(2,2)-TWTH*DIVU)
                        TAU_IJ(3,3) = -MUA*(GRADU(3,3)-TWTH*DIVU)
                        TAU_IJ(1,2) = -MUA*(GRADU(1,2)+GRADU(2,1))
                        TAU_IJ(1,3) = -MUA*(GRADU(1,3)+GRADU(3,1))
                        TAU_IJ(2,3) = -MUA*(GRADU(2,3)+GRADU(3,2))
                        TAU_IJ(2,1) = TAU_IJ(1,2)
                        TAU_IJ(3,1) = TAU_IJ(1,3)
                        TAU_IJ(3,2) = TAU_IJ(2,3)
                  
                        I_VEL = 3 ! 2 only for debug
                  
                        ITMP = MIN(5000,NINT(0.5_EB*(TMP(I,J,K)+TMP(I,J,KP1))))
                        MU_WALL = MU_Z(ITMP,0)*SPECIES_MIXTURE(0)%MW
                        
                        !! use 2D for debug
                        !U_VEC(2)=U_VEC(3)
                        !U_GEOM(2)=U_GEOM(3)
                        !N_VEC(2)=N_VEC(3)
                        !GRADU(1,2)=GRADU(1,3)
                        !GRADU(2,2)=GRADU(3,3)
                        !GRADU(2,1)=GRADU(3,1)
                        !GRADP(2)=GRADP(3)
                        !TAU_IJ(1,2)=TAU_IJ(1,3)
                        !TAU_IJ(2,2)=TAU_IJ(3,3)
                        !TAU_IJ(2,1)=TAU_IJ(3,1)
                        
                        !W_IBM = VELTAN2D( U_VEC(1:2),&
                        !                  U_GEOM(1:2),&
                        !                  N_VEC(1:2),&
                        !                  DN,DIVU,&
                        !                  GRADU(1:2,1:2),&
                        !                  GRADP(1:2),&
                        !                  TAU_IJ(1:2,1:2),&
                        !                  DT,RRHO,MUA,I_VEL)
                        
                        WT = MIN(1._EB,(DN/DELTA)**7._EB)
                        
                        W_IBM = VELTAN3D(U_VEC,U_GEOM,N_VEC,DN,DIVU,GRADU,GRADP,TAU_IJ,DT,RRHO,MU_WALL,I_VEL,G%ROUGHNESS,W_IBM)
                        
                  END SELECT SELECT_METHOD3
            END SELECT
            
            IF (PREDICTOR) DWWDT = (W_IBM-W(I,J,K))/DT
            IF (CORRECTOR) DWWDT = (2._EB*W_IBM-(W(I,J,K)+WS(I,J,K)))/DT
         
            FVZ(I,J,K) = WT*FVZ(I,J,K) + (1._EB-WT)*(-RDZN(K)*(HP(I,J,K+1)-HP(I,J,K)) - DWWDT)
         
         ENDDO
      ENDDO
   ENDDO
   
ENDDO GEOM_LOOP

NXNY_REAL = REAL(IBAR*JBAR,EB)+1.E-10_EB
NX_REAL = REAL(IBAR,EB)+1.E-10_EB

UNSTRUCTURED_GEOMETRY_LOOP: DO TRI_INDEX=1,N_FACE

   CL=>FACET(TRI_INDEX)%CUTCELL_LIST

   TMP_SUM=0._EB
   N_CELLS=0

   CUTCELL_LOOP: DO

      IF ( .NOT. ASSOCIATED(CL) ) EXIT

      IC_REAL = REAL(CL%INDEX,EB)
      K = CEILING(IC_REAL/NXNY_REAL)
      J = CEILING((IC_REAL-(K-1)*NXNY_REAL)/NX_REAL)
      I = NINT(IC_REAL-(K-1)*NXNY_REAL-(J-1)*NX_REAL)

      IJK = (/I,J,K/)
      DXC = (/DXN(I),DY(J),DZ(K)/)
      XV = (/X(I),YC(J),ZC(K)/)

      CALL GET_VELO_IBM(U_IBM,IERR,1,XV,TRI_INDEX,IMMERSED_BOUNDARY_METHOD,DXC,NM)
      IF (IERR==0) THEN
         IF (PREDICTOR) DUUDT = (U_IBM-U(I,J,K))/DT
         IF (CORRECTOR) DUUDT = (2._EB*U_IBM-(U(I,J,K)+US(I,J,K)))/DT
         FVX(I,J,K) = -RDXN(I)*(HP(I+1,J,K)-HP(I,J,K)) - DUUDT
      ENDIF

      DXC = (/DX(I),DYN(J),DZ(K)/)
      XV = (/XC(I),Y(J),ZC(K)/)

      CALL GET_VELO_IBM(V_IBM,IERR,2,XV,TRI_INDEX,IMMERSED_BOUNDARY_METHOD,DXC,NM)
      IF (IERR==0) THEN
         IF (PREDICTOR) DVVDT = (V_IBM-V(I,J,K))/DT
         IF (CORRECTOR) DVVDT = (2._EB*V_IBM-(V(I,J,K)+VS(I,J,K)))/DT
         FVY(I,J,K) = -RDYN(J)*(HP(I,J+1,K)-HP(I,J,K)) - DVVDT
      ENDIF

      DXC = (/DX(I),DY(J),DZN(K)/)
      XV = (/XC(I),YC(J),Z(K)/)

      CALL GET_VELO_IBM(W_IBM,IERR,3,XV,TRI_INDEX,IMMERSED_BOUNDARY_METHOD,DXC,NM)
      IF (IERR==0) THEN
         IF (PREDICTOR) DWWDT = (W_IBM-W(I,J,K))/DT
         IF (CORRECTOR) DWWDT = (2._EB*W_IBM-(W(I,J,K)+WS(I,J,K)))/DT
         FVZ(I,J,K) = -RDZN(K)*(HP(I,J,K+1)-HP(I,J,K)) - DWWDT
      ENDIF

      CL=>CL%NEXT

      ! for testing, set face tmp to gas cell tmp

      TMP_SUM = TMP_SUM + TMP(I,J,K)
      N_CELLS = N_CELLS + 1

   ENDDO CUTCELL_LOOP

   FACET(TRI_INDEX)%TMP_G = TMP_SUM/REAL(N_CELLS,EB)

ENDDO UNSTRUCTURED_GEOMETRY_LOOP

END SUBROUTINE IBM_VELOCITY_FLUX


SUBROUTINE PATCH_VELOCITY_FLUX

! The user may specify a polynomial profile using the PROP and DEVC lines. This routine 
! specifies the source term in the momentum equation to drive the local velocity toward
! this user-specified value, in much the same way as the immersed boundary method
! (see IBM_VELOCITY_FLUX).

USE DEVICE_VARIABLES, ONLY: DEVICE_TYPE,PROPERTY_TYPE,N_DEVC,DEVICE,PROPERTY

TYPE(DEVICE_TYPE), POINTER :: DV=>NULL()
TYPE(PROPERTY_TYPE), POINTER :: PY=>NULL()
INTEGER :: N,I,J,K,IC1,IC2
REAL(EB), POINTER, DIMENSION(:,:,:) :: UU=>NULL(),VV=>NULL(),WW=>NULL(),HP=>NULL()
REAL(EB) :: VELP,DX0,DY0,DZ0

IF (PREDICTOR) THEN
   UU => U
   VV => V
   WW => W
   HP => H
ELSE
   UU => US
   VV => VS
   WW => WS
   HP => HS
ENDIF

DEVC_LOOP: DO N=1,N_DEVC

   DV=>DEVICE(N)
   IF (DV%QUANTITY/='VELOCITY PATCH') CYCLE DEVC_LOOP
   IF (DV%PROP_INDEX<1)               CYCLE DEVC_LOOP
   IF (.NOT.DEVICE(DV%DEVC_INDEX(1))%CURRENT_STATE) CYCLE DEVC_LOOP
   PY=>PROPERTY(DV%PROP_INDEX)

   I_VEL_SELECT: SELECT CASE(PY%I_VEL)
   
      CASE(1) I_VEL_SELECT
      
         DO K=1,KBAR
            DO J=1,JBAR
               DO I=0,IBAR
               
                  IC1 = CELL_INDEX(I,J,K)
                  IC2 = CELL_INDEX(I+1,J,K)
                  IF (SOLID(IC1) .OR. SOLID(IC2)) CYCLE
               
                  IF ( X(I)<DV%X1 .OR.  X(I)>DV%X2) CYCLE ! Inefficient but simple
                  IF (YC(J)<DV%Y1 .OR. YC(J)>DV%Y2) CYCLE
                  IF (ZC(K)<DV%Z1 .OR. ZC(K)>DV%Z2) CYCLE
               
                  DX0 =  X(I)-DV%X
                  DY0 = YC(J)-DV%Y
                  DZ0 = ZC(K)-DV%Z
                  VELP = PY%P0 + DX0*PY%PX(1) + 0.5_EB*(DX0*DX0*PY%PXX(1,1)+DX0*DY0*PY%PXX(1,2)+DX0*DZ0*PY%PXX(1,3)) &
                               + DY0*PY%PX(2) + 0.5_EB*(DY0*DX0*PY%PXX(2,1)+DY0*DY0*PY%PXX(2,2)+DY0*DZ0*PY%PXX(2,3)) &
                               + DZ0*PY%PX(3) + 0.5_EB*(DZ0*DX0*PY%PXX(3,1)+DZ0*DY0*PY%PXX(3,2)+DZ0*DZ0*PY%PXX(3,3))
        
                  FVX(I,J,K) = -RDXN(I)*(HP(I+1,J,K)-HP(I,J,K)) - (VELP-UU(I,J,K))/DT
               ENDDO
            ENDDO
         ENDDO
     
      CASE(2) I_VEL_SELECT
     
         DO K=1,KBAR
            DO J=0,JBAR
               DO I=1,IBAR
               
                  IC1 = CELL_INDEX(I,J,K)
                  IC2 = CELL_INDEX(I,J+1,K)
                  IF (SOLID(IC1) .OR. SOLID(IC2)) CYCLE
               
                  IF (XC(I)<DV%X1 .OR. XC(I)>DV%X2) CYCLE
                  IF ( Y(J)<DV%Y1 .OR.  Y(J)>DV%Y2) CYCLE
                  IF (ZC(K)<DV%Z1 .OR. ZC(K)>DV%Z2) CYCLE
                  
                  DX0 = XC(I)-DV%X
                  DY0 =  Y(J)-DV%Y
                  DZ0 = ZC(K)-DV%Z
                  VELP = PY%P0 + DX0*PY%PX(1) + 0.5_EB*(DX0*DX0*PY%PXX(1,1)+DX0*DY0*PY%PXX(1,2)+DX0*DZ0*PY%PXX(1,3)) &
                               + DY0*PY%PX(2) + 0.5_EB*(DY0*DX0*PY%PXX(2,1)+DY0*DY0*PY%PXX(2,2)+DY0*DZ0*PY%PXX(2,3)) &
                               + DZ0*PY%PX(3) + 0.5_EB*(DZ0*DX0*PY%PXX(3,1)+DZ0*DY0*PY%PXX(3,2)+DZ0*DZ0*PY%PXX(3,3))
        
                  FVY(I,J,K) = -RDYN(J)*(HP(I,J+1,K)-HP(I,J,K)) - (VELP-VV(I,J,K))/DT
               ENDDO
            ENDDO
         ENDDO
     
      CASE(3) I_VEL_SELECT
     
         DO K=0,KBAR
            DO J=1,JBAR
               DO I=1,IBAR
               
                  IC1 = CELL_INDEX(I,J,K)
                  IC2 = CELL_INDEX(I,J,K+1)
                  IF (SOLID(IC1) .OR. SOLID(IC2)) CYCLE
               
                  IF (XC(I)<DV%X1 .OR. XC(I)>DV%X2) CYCLE
                  IF (YC(J)<DV%Y1 .OR. YC(J)>DV%Y2) CYCLE
                  IF ( Z(K)<DV%Z1 .OR.  Z(K)>DV%Z2) CYCLE
               
                  DX0 = XC(I)-DV%X
                  DY0 = YC(J)-DV%Y
                  DZ0 =  Z(K)-DV%Z
                  VELP = PY%P0 + DX0*PY%PX(1) + 0.5_EB*(DX0*DX0*PY%PXX(1,1)+DX0*DY0*PY%PXX(1,2)+DX0*DZ0*PY%PXX(1,3)) &
                               + DY0*PY%PX(2) + 0.5_EB*(DY0*DX0*PY%PXX(2,1)+DY0*DY0*PY%PXX(2,2)+DY0*DZ0*PY%PXX(2,3)) &
                               + DZ0*PY%PX(3) + 0.5_EB*(DZ0*DX0*PY%PXX(3,1)+DZ0*DY0*PY%PXX(3,2)+DZ0*DZ0*PY%PXX(3,3))
        
                  FVZ(I,J,K) = -RDZN(K)*(HP(I,J,K)-HP(I,J,K+1)) - (VELP-WW(I,J,K))/DT
               ENDDO
            ENDDO
         ENDDO
     
   END SELECT I_VEL_SELECT

ENDDO DEVC_LOOP

END SUBROUTINE PATCH_VELOCITY_FLUX


SUBROUTINE GET_REV_velo(MODULE_REV,MODULE_DATE)
INTEGER,INTENT(INOUT) :: MODULE_REV
CHARACTER(255),INTENT(INOUT) :: MODULE_DATE

WRITE(MODULE_DATE,'(A)') velorev(INDEX(velorev,':')+1:LEN_TRIM(velorev)-2)
READ (MODULE_DATE,'(I5)') MODULE_REV
WRITE(MODULE_DATE,'(A)') velodate

END SUBROUTINE GET_REV_velo
 
END MODULE VELO
