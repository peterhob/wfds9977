MODULE GLOBAL_CONSTANTS
 
! Module containing global constants, parameters, variables
 
USE PRECISION_PARAMETERS
IMPLICIT NONE

CHARACTER(255), PARAMETER :: consid='$Id: cons.f90 9974 2012-02-03 18:41:26Z mcgratta $'
CHARACTER(255), PARAMETER :: consrev='$Revision: 9974 $'
CHARACTER(255), PARAMETER :: consdate='$Date: 2012-02-03 10:41:26 -0800 (Fri, 03 Feb 2012) $'

! Indices for various modes of operation

INTEGER, PARAMETER :: GAS_SPECIES=2,AEROSOL_SPECIES=3                                       ! For SPECIES%MODE
INTEGER, PARAMETER :: EDDY_DISSIPATION=1,FINITE_RATE=2,MIXED=3,NEW_MIXED_MODE=4             ! For REACTION%MODE
INTEGER, PARAMETER :: SINGLE_EXACT=1,EXPLICIT_EULER=2,RUNGE_KUTTA_2=3,RUNGE_KUTTA_4=4, &    ! For COMBUSTION_ODE
                      IMPLICIT_TRAPEZOID=5
INTEGER, PARAMETER :: CONSMAG=1,DYNSMAG=2,DEARDORFF=3,VREMAN=4                              ! Turbulence model
INTEGER, PARAMETER :: CONVECTIVE_FLUX_BC=-1,NET_FLUX_BC=0,SPECIFIED_TEMPERATURE=1,&
                      NO_CONVECTION=2,THERMALLY_THICK=3,INFLOW_OUTFLOW=4,&
                      SPECIFIED_TEMPERATURE_FROM_FILE=5,INTERPOLATED_BC=6,&
                      VEG_BNDRY_FUEL=99                                                     ! Heat transfer BC
INTEGER, PARAMETER :: WALL_MODEL=2,FREE_SLIP_BC=3,NO_SLIP_BC=4,INTERPOLATED_VELOCITY_BC=6,& ! Velocity BC
                      HVAC_VBC=42
INTEGER, PARAMETER :: EXPOSED=0,VOID=1,INSULATED=2                                          ! Surface backing
INTEGER, PARAMETER :: SURF_CARTESIAN=0,SURF_CYLINDRICAL=1,SURF_SPHERICAL=2                  ! Surface geometry
INTEGER, PARAMETER :: NO_MASS_FLUX=1,SPECIFIED_MASS_FRACTION=2,SPECIFIED_MASS_FLUX=3,&
                      INFLOW_OUTFLOW_MASS_FLUX=4                                            ! Mass transfer BC
INTEGER, PARAMETER :: NULL_BOUNDARY=0,SOLID_BOUNDARY=1,OPEN_BOUNDARY=2,MIRROR_BOUNDARY=3, &
                      VIRTUAL_BOUNDARY=5,INTERPOLATED_BOUNDARY=6,PERIODIC_BOUNDARY=7        ! Boundary Type
INTEGER, PARAMETER :: HVAC_BOUNDARY=42                      
INTEGER, PARAMETER :: NULL_EDGE=0,SOLID_EDGE=1,OPEN_EDGE=2,MIRROR_EDGE=3,SMOOTH_EDGE=4, &
                      INTERPOLATED_EDGE=6,PERIODIC_EDGE=7                                   ! Edge Type
INTEGER, PARAMETER :: DIRICHLET=1,NEUMANN=2,INTERNAL=3                                      ! Pressure Boundary Conditions
INTEGER, PARAMETER :: PYROLYSIS_NONE=0,PYROLYSIS_SOLID=1,PYROLYSIS_LIQUID=2,&
                      PYROLYSIS_MATERIAL=3,PYROLYSIS_SPECIFIED=4                            ! Pyrolysis model
INTEGER, PARAMETER :: ATMOSPHERIC=1, PARABOLIC=2, ONED_PARABOLIC=3                          ! Surface velocity profile
INTEGER, PARAMETER :: CELL_CENTER=1, CELL_FACE=2, CELL_EDGE=3                               ! Cell position for output quantities
INTEGER, PARAMETER :: NO_STOP=0, INSTABILITY_STOP=1, USER_STOP=2, SETUP_STOP=3              ! Program Stop Status
INTEGER, PARAMETER :: SPHERE_DRAG=1,CYLINDER_DRAG=2,USER_DRAG=3                             ! Options for drag computation
INTEGER, PARAMETER :: OLD=1,NEW=2,GUESS=3,PREVIOUS=4                                        ! Network solver indices

! Species components of the lumped species

INTEGER :: FUEL_INDEX=0,O2_INDEX=0,N2_INDEX=0,H2O_INDEX=0,CO2_INDEX=0,CO_INDEX=0,&
           H2_INDEX=0,SOOT_INDEX=0,OTHER_INDEX=0,SM_FUEL_INDEX = 0                          ! Lumped Species Sub-species

! Species components used in FED calculations
INTEGER :: HCN_INDEX=0,NO_INDEX=0,NO2_INDEX=0

! Program Status Code

INTEGER :: PROCESS_STOP_STATUS=NO_STOP,INPUT_FILE_LINE_NUMBER=0

! Miscellaneous logical constants
 
LOGICAL :: LES,DNS,RADIATION=.TRUE.,KAPPA_ARRAY=.FALSE.,CYLINDRICAL,NOISE, &
           PREDICTOR,CORRECTOR,APPEND,PARTICLE_FILE=.FALSE.,RESTART,SUPPRESSION=.TRUE., &
           CO_PRODUCTION=.FALSE.,ACCUMULATE_WATER=.FALSE.,RECOUNT_DRIP,WRITE_XYZ=.FALSE., &
           CHECK_POISSON=.FALSE.,TWO_D,SET_UP=.FALSE.,SMOKE3D, &
           STATUS_FILES=.FALSE.,DEBUG,SYNCHRONIZE,TIMING,LOCK_TIME_STEP=.FALSE.,RESTRICT_TIME_STEP=.TRUE.,  &
           FLUSH_FILE_BUFFERS, &
           COLUMN_DUMP_LIMIT,MASS_FILE=.FALSE.,STRATIFICATION,SOLID_PHASE_ONLY, &
           AL2O3=.FALSE.,SHARED_FILE_SYSTEM=.TRUE., &
           FREEZE_VELOCITY=.FALSE.,BNDF_DEFAULT=.TRUE.,PARTICLE_CFL=.FALSE., &
           SPATIAL_GRAVITY_VARIATION=.FALSE., &
           PROJECTION=.FALSE.,CLIP_MASS_FRACTION=.FALSE.,CHECK_VN=.FALSE., &
           VIRTUAL_PARTICLES=.FALSE.,HVAC=.FALSE.,BAROCLINIC=.TRUE., &
           THERMOPHORETIC_DEPOSITION=.TRUE.,TURBULENT_DEPOSITION=.TRUE.,VELOCITY_ERROR_FILE=.FALSE.,&
           CONSTANT_SPECIFIC_HEAT=.FALSE., CP_FTMP=.FALSE.,NEW_EVAP=.FALSE., &
           MEAN_FORCING(3)=.FALSE.,CHECK_GR=.FALSE.,CHECK_HT=.FALSE., &
           WFDS=.FALSE.,PATCH_VELOCITY=.FALSE.,OVERWRITE=.TRUE., &
           INIT_HRRPUV = .FALSE.,WFDS_FE=.FALSE.,WFDS_BNDRYFUEL=.FALSE., &
           GRAV_VISC=.FALSE.,HISTOGRAM_FILE=.FALSE.,TENSOR_DIFFUSIVITY=.FALSE.,&
           ENTHALPY_TRANSPORT=.FALSE.,UVW_RESTART=.FALSE.
           
LOGICAL, ALLOCATABLE, DIMENSION(:) :: SYNC_TIME_STEP,CHANGE_TIME_STEP

! Miscellaneous character strings

CHARACTER(256) :: TITLE,RENDER_FILE,UVW_FILE='null'
CHARACTER(40) :: CHID,RESTART_CHID
CHARACTER(256) :: TERRAIN_IMAGE

! Dates, version numbers, revision numbers

CHARACTER(20) :: COMPILE_DATE='null',VERSION_STRING='null'
REAL(FB) :: VERSION_NUMBER=6.0
INTEGER :: SVN_REVISION_NUMBER=0
 
! Global EVACuation parameters

LOGICAL, ALLOCATABLE, DIMENSION(:) :: EVACUATION_ONLY, EVACUATION_GRID
REAL(EB) :: EVAC_DT_FLOWFIELD,EVAC_DT_STEADY_STATE,EVAC_DT,T_EVAC,T_EVAC_SAVE
INTEGER :: EVAC_PRESSURE_ITERATIONS,EVAC_TIME_ITERATIONS,EVAC_N_QUANTITIES,I_EVAC
INTEGER :: EVAC_AVATAR_NCOLOR
LOGICAL :: EVACUATION_MC_MODE=.FALSE.,EVACUATION_DRILL=.FALSE.,NO_EVACUATION=.FALSE.
CHARACTER(30), ALLOCATABLE, DIMENSION(:) :: EVAC_CLASS_NAME, EVAC_CLASS_PROP
INTEGER, ALLOCATABLE, DIMENSION(:) :: EVAC_QUANTITIES_INDEX
INTEGER, ALLOCATABLE, DIMENSION(:,:) :: EVAC_CLASS_RGB,EVAC_AVATAR_RGB
REAL(EB), ALLOCATABLE, DIMENSION(:) :: EVACUATION_Z_OFFSET

! Miscellaneous real constants
 
REAL(EB) :: CPOPR,RSC,RPR,TMPA,TMPA4,RHOA,P_INF,&
            CP_GAMMA,GAMMA,U0,V0,W0,H0,GVEC(3),FVEC(3)=0._EB, &
            C_SMAGORINSKY=0.2_EB,C_DEARDORFF=0.1_EB,C_VREMAN=0.07_EB,C_G=0.04_EB, &
            LAPSE_RATE,HCH,HCV,TEX_ORI(3),KAPPA0,C_FORCED,C_FORCED_CYLINDER,C_FORCED_SPHERE, &
            ASSUMED_GAS_TEMPERATURE,PR_ONTH,MU_AIR_0,CP_AIR_0,PR_AIR,K_AIR_0, &
            CHARACTERISTIC_VELOCITY,CFL_MAX,CFL_MIN,VN_MAX,VN_MIN,PR,SC,H_V_W,GROUND_LEVEL=0._EB, &
            PARTICLE_CFL_MAX=1.0_EB,LIMITING_DT_RATIO=1.E-4_EB,HRRPUVCUT_MAX=200._EB, &
            SCALAR_ENERGY_TOLERANCE=1.E-12_EB,TKE_TOLERANCE=1.E-6_EB,RFAC_FORCING(3)=0.5_EB, &
            TAU_CHEM=1.E-10_EB,TAU_FLAME=1.E10_EB,SMOKE_ALBEDO=0.3, &
            MIXING_LAYER_U0,MIXING_LAYER_H0,MIXING_LAYER_THETA0, &
            TMPM=273.15_EB, P_STP=101325._EB,GRAV=9.80665_EB,R0=8314.472_EB,R1=1.986257E-03_EB,SIGMA=5.67E-8_EB 
            !    K             Pa           m/s**2^2   J/kmol/K     kcal/mol/K           W/m**2/K**4
REAL(FB) :: HRRPUV_MAX_SMV=-1.0_FB
INTEGER :: USE_HRRPUV_MAX_SMV=0

! Parameters associated with parallel mode

INTEGER :: MYID=0,NUMPROCS=1,EVAC_PROCESS=-1
LOGICAL :: USE_MPI=.FALSE.
INTEGER, ALLOCATABLE, DIMENSION(:) :: PROCESS,FILE_COUNTER

! Time parameters

REAL(EB) :: T_BEGIN,T_END,TWFIN,TIME_SHRINK_FACTOR,RELAXATION_FACTOR=1._EB
EQUIVALENCE(T_END,TWFIN)
 
! Combustion parameters
 
REAL(EB), PARAMETER :: CO_HEAT_OF_FORMATION = 110.523E3_EB, CO2_HEAT_OF_FORMATION = 393.513E3_EB, &
                       H2O_HEAT_OF_FORMATION = 241.826E3_EB !HEAT_OF_FORMATION J/mol Drysdale, Fire Dynamics
REAL(EB) :: Y_O2_INFTY = 0.232378_EB,Y_CO2_INFTY=0.000595_EB,Y_H2O_INFTY=0._EB
REAL(EB) :: MW_AIR=28.84852_EB,MW_N2,MW_O2,MW_CO2,MW_H2O,MW_CO,MW_H2,&
            HRRPUA_SHEET,RHO_SOOT,VISIBILITY_FACTOR, &
            EC_LL,BETA_EDC=2._EB,Y_P_MIN_EDC=0.01_EB,HRRPUV_AVERAGE, &
            FIXED_MIX_TIME=-1._EB
INTEGER :: N_SPECIES=0,N_REACTIONS,I_PRODUCTS=-1,I_WATER=-1,I_CO2=-1,N_KAPPA_ARRAY,N_TRACKED_SPECIES=0,N_SURFACE_DENSITY_SPECIES=0
INTEGER :: COMBUSTION_ODE = -1
REAL(EB) :: RSUM0
REAL(EB), ALLOCATABLE, DIMENSION(:,:) :: Z2Y,CP_Z,CPBAR_Z,K_Z,MU_Z,D_Z,CP_AVG_Z
REAL(EB), ALLOCATABLE, DIMENSION(:) :: MWR_Z,Z2KAPPA_M4
INTEGER, ALLOCATABLE, DIMENSION(:) :: KAPPA_INDEX,MAX_CHEM_SUBIT
REAL(EB), ALLOCATABLE, DIMENSION(:,:,:,:) :: Z2KAPPA
INTEGER :: Z2KAPPA_T,Z2KAPPA_M

! Radiation parameters

INTEGER :: NUMBER_SPECTRAL_BANDS,NUMBER_RADIATION_ANGLES,ANGLE_INCREMENT
CHARACTER(30) :: RADCAL_FUEL='METHANE'

! Ramping parameters
 
CHARACTER(30) :: RAMP_ID(1000),RAMP_TYPE(1000)
INTEGER :: I_RAMP_GX,I_RAMP_GY,I_RAMP_GZ,N_RAMP=0
INTEGER, PARAMETER :: TIME_HEAT=-1,TIME_VELO=-2,TIME_TEMP=-3,TIME_EFLUX=-4,TIME_PART=-5,TANH_RAMP=-2,TSQR_RAMP=-1

! TABLe parameters

CHARACTER(30) :: TABLE_ID(1000)
INTEGER :: N_TABLE=0,TABLE_TYPE(1000)
INTEGER, PARAMETER :: SPRAY_PATTERN=1,PART_RADIATIVE_PROPERTY=2

! Variables related to meshes

INTEGER :: NMESHES=1,IBAR_MAX=0,JBAR_MAX=0,KBAR_MAX=0,MESH_LIST_EMB(100)
REAL(EB) :: XS_MIN=1.E6_EB,XF_MAX=-1.E6_EB,YS_MIN=1.E6_EB,YF_MAX=-1.E6_EB,ZS_MIN=1.E6_EB,ZF_MAX=-1.E6_EB
CHARACTER(30), DIMENSION(:), ALLOCATABLE :: MESH_NAME

! Variables related to pressure solver

LOGICAL :: ITERATE_PRESSURE=.FALSE.,PRESSIT_ACCELERATOR=.FALSE.
REAL(EB) :: VELOCITY_TOLERANCE=1.E6_EB,PRESSIT_SCALE_FACTOR=0.5_EB
REAL(EB), ALLOCATABLE, DIMENSION(:) :: VELOCITY_ERROR_MAX
INTEGER, ALLOCATABLE, DIMENSION(:) :: VELOCITY_ERROR_MAX_I,VELOCITY_ERROR_MAX_J,VELOCITY_ERROR_MAX_K
INTEGER :: PRESSURE_ITERATIONS=0,MAX_PRESSURE_ITERATIONS=10000
CHARACTER(10):: PRES_METHOD = 'FFT'

! Miscellaneous integer constants
 
INTEGER :: ICYC,WALL_INCREMENT,NFRAMES,PERIODIC_TEST=0,TURB_MODEL=0
 
! Clocks for output file dumps
 
REAL(EB), ALLOCATABLE, DIMENSION(:) :: PART_CLOCK,CORE_CLOCK,SLCF_CLOCK,SL3D_CLOCK, &
                                       PL3D_CLOCK,BNDF_CLOCK,ISOF_CLOCK,PROF_CLOCK
REAL(EB) :: MINT_CLOCK,DEVC_CLOCK,HRR_CLOCK,EVAC_CLOCK,CTRL_CLOCK,FLUSH_CLOCK
REAL(EB) :: DT_SLCF,DT_BNDE,DT_BNDF,DT_DEVC,DT_DEVC_LINE,DT_PL3D,DT_PART,DT_RESTART,DT_ISOF,DT_HRR,DT_MASS,DT_PROF,DT_CTRL,&
            DT_FLUSH,DT_SL3D,DT_GEOM
REAL(EB) :: DT_OUTPUT_LS,DT_VEG,VEG_CLOCK,BNDE_CLOCK,GEOM_CLOCK,UVW_CLOCK,UVW_TIMER(10)
REAL(EB) :: UVW_CLOCK_CBC(1:4)=(/0._EB,0.28_EB,0.67_EB,1.E10_EB/)

! Miscellaneous mesh dimensions

REAL(EB) :: CHARACTERISTIC_CELL_SIZE
 
! Logical units and output file names
 
INTEGER                              :: LU_ERR=0,LU_END=2,LU_SVN=3,LU_SMV=4,LU_INPUT=5,LU_OUTPUT=6
INTEGER                              :: LU_MASS,LU_HRR,LU_NOTREADY,LU_VELOCITY_ERROR,LU_LINE=-1
INTEGER                              :: LU_EVACCSV,LU_EVACEFF,LU_EVACFED,LU_EVACOUT,LU_HISTOGRAM,LU_SFBC=-1
INTEGER, ALLOCATABLE, DIMENSION(:)   :: LU_PART,LU_PROF,LU_XYZ,LU_PL3D,LU_DEVC,LU_STATE,LU_CTRL,LU_CORE,LU_RESTART
INTEGER, ALLOCATABLE, DIMENSION(:)   :: LU_VEG_OUT,LU_GEOM,LU_BNDE
INTEGER, ALLOCATABLE, DIMENSION(:,:) :: LU_SLCF,LU_BNDF,LU_ISOF,LU_SMOKE3D,LU_BNDF_SLCF
INTEGER                              :: DEVC_COLUMN_LIMIT=254,CTRL_COLUMN_LIMIT=254

CHARACTER(250)                             :: FN_INPUT='null'
CHARACTER(45)                              :: FN_STOP='null'
CHARACTER(80)                              :: FN_MASS,FN_HRR,FN_OUTPUT,FN_SMV,FN_END,FN_ERR,FN_NOTREADY,FN_VELOCITY_ERROR,FN_SVN
CHARACTER(80)                              :: FN_EVACCSV,FN_EVACEFF,FN_EVACFED,FN_EVACOUT,FN_LINE,FN_HISTOGRAM
CHARACTER(80), ALLOCATABLE, DIMENSION(:)   :: FN_PART,FN_PROF,FN_XYZ,FN_PL3D,FN_DEVC,FN_STATE,FN_CTRL,FN_CORE,FN_RESTART
CHARACTER(80), ALLOCATABLE, DIMENSION(:)   :: FN_VEG_OUT,FN_GEOM,FN_BNDE
CHARACTER(80), ALLOCATABLE, DIMENSION(:,:) :: FN_SLCF,FN_BNDF,FN_ISOF,FN_SMOKE3D,FN_BNDF_SLCF

CHARACTER(9) :: FMT_R
 
! Boundary condition arrays
 
CHARACTER(30) :: MATL_NAME(1:1000)
INTEGER :: N_SURF,N_SURF_RESERVED,N_MATL,MIRROR_SURF_INDEX,OPEN_SURF_INDEX,INTERPOLATED_SURF_INDEX,DEFAULT_SURF_INDEX=0, &
           INERT_SURF_INDEX=0,PERIODIC_SURF_INDEX,HVAC_SURF_INDEX=-1,EVACUATION_SURF_INDEX=-1
REAL(EB), ALLOCATABLE, DIMENSION(:) :: AAS,BBS,CCS,DDS,DDT,DX_S,RDX_S,RDXN_S,DX_WGT_S, &
                                       K_S,RHOCBAR,C_S,RHO_S,Q_S,KAPPA_S,X_S_NEW,R_S,MF_FRAC
INTEGER,  ALLOCATABLE, DIMENSION(:) :: LAYER_INDEX

! Divergence Arrays

REAL(EB), ALLOCATABLE, DIMENSION(:,:) :: DSUM,USUM,PSUM,ACTUAL_LEAK_AREA
REAL(EB), ALLOCATABLE, DIMENSION(:,:,:) :: FDS_LEAK_AREA,FDS_LEAK_AREA_RATIO

! Raised vegetation arrays
 
INTEGER :: N_TREES,N_TREES_OUT
INTEGER :: N_CONE_TREES,N_FRUSTUM_TREES,N_CYLINDER_TREES,N_RECTANGLE_TREES,N_RING_TREES
INTEGER :: N_CONE_IGNITORS,N_FRUSTUM_IGNITORS,N_CYLINDER_IGNITORS,N_RECTANGLE_IGNITORS,N_RING_IGNITORS
!cone frustum, cylinder, ring veg bulk volumes
REAL(EB), ALLOCATABLE, DIMENSION(:) :: CROWN_W,CROWN_B_H,TREE_H,X_TREE,Y_TREE,Z_TREE
!frustum bulk veg volumes
REAL(EB), ALLOCATABLE, DIMENSION(:) :: CROWN_W_BOTTOM,CROWN_W_TOP 
!rectangular bulk veg volumes
REAL(EB), ALLOCATABLE, DIMENSION(:) :: XS_RECT_VEG,XF_RECT_VEG,YS_RECT_VEG,YF_RECT_VEG,ZS_RECT_VEG,ZF_RECT_VEG
!ring bulk veg volume
REAL(EB), ALLOCATABLE, DIMENSION(:) :: RING_THICKNESS_VEG
!All bulk veg volume types
REAL(EB), ALLOCATABLE, DIMENSION(:) :: TON_IGN_ELEMS,TOFF_IGN_ELEMS,T_RAMPOFF_IGN_ELEMS,T_RAMPON_IGN_ELEMS

LOGICAL :: CONE_TREE_PRESENT,FRUSTUM_TREE_PRESENT,CYLINDER_TREE_PRESENT,RING_TREE_PRESENT, &
           RECTANGLE_TREE_PRESENT,IGNITOR_PRESENT


!REAL(EB), ALLOCATABLE, DIMENSION(:) :: CROWN_W_CONE,CROWN_B_H_CONE,TREE_H_CONE,X_TREE_CONE,Y_TREE_CONE,Z_TREE_CONE, &
!                                       TON_IGN_ELEM_CONE,TOFF_IGN_ELEM_CONE,T_RAMPOFF_IGN_ELEM_CONE,T_RAMPON_IGN_ELEM_CONE
!
!REAL(EB), ALLOCATABLE, DIMENSION(:) :: CROWN_W_BOTTOM_FRUSTUM,CROWN_W_TOP_FRUSTUM,CROWN_B_H_FRUSTUM, &
!                                       TREE_H_FRUSTUM,X_TREE_FRUSTUM,Y_TREE_FRUSTUM,Z_TREE_FRUSTUM, &
!                                       TON_IGN_ELEM_FRUSTUM,TOFF_IGN_ELEM_FRUSTUM,T_RAMPOFF_IGN_ELEM_FRUSTUM, &
!                                       T_RAMPON_IGN_ELEM_FRUSTUM
!
!REAL(EB), ALLOCATABLE, DIMENSION(:) :: CROWN_W_CYLINDER,CROWN_B_H_CYLINDER,TREE_H_CYL,X_TREE_CYLINDER,Y_TREE_CYLINDER,& 
!                                       Z_TREE_CYLINDER, &
!                                       TON_IGN_ELEM_CYLINDER,TOFF_IGN_ELEM_CYLINDER,T_RAMPOFF_IGN_ELEM_CYLINDER, &
!                                       T_RAMPON_IGN_ELEM_CYLINDER
!
!REAL(EB), ALLOCATABLE, DIMENSION(:) :: XS_RECT_VEG,XF_RECT_VEG,YS_RECT_VEG,YF_RECT_VEG,ZS_RECT_VEG,ZF_RECT_VEG,
!                                       TON_IGN_ELEM_RECT,TOFF_IGN_ELEM_RECT,T_RAMPOFF_IGN_ELEM_RECT,T_RAMPON_IGN_ELEM_RECT
!
!REAL(EB), ALLOCATABLE, DIMENSION(:) :: CROWN_W_RING,CROWN_B_H_RING,TREE_H_RING,X_TREE_RING,Y_TREE_RING,Z_TREE_RING, &
!                                       RING_THICKNESS_VEG, &
!                                       TON_IGN_ELEM_RING,TOFF_IGN_ELEM_RING,T_RAMPOFF_IGN_ELEM_RING,T_RAMPON_IGN_ELEM_RING

INTEGER,  ALLOCATABLE, DIMENSION(:) :: TREE_PARTICLE_CLASS
CHARACTER(30),ALLOCATABLE, DIMENSION(:) :: VEG_FUEL_GEOM, VEG_LABELS

LOGICAL, ALLOCATABLE, DIMENSION(:) :: TREE_MESH,TREE_MESH_OUT
LOGICAL, ALLOCATABLE, DIMENSION(:) :: IGN_ELEMS
INTEGER, ALLOCATABLE, DIMENSION(:) :: N_TREE_OUT,TREE_CFCR_INDEX,TREE_FRUSTUM_INDEX,TREE_RING_INDEX,TREE_RECT_INDEX, &
                                      TREE_IGN_INDEX
REAL(EB),ALLOCATABLE, DIMENSION(:) :: VEG_TOTAL_DRY_MASS,VEG_TOTAL_MOIST_MASS
REAL(EB),ALLOCATABLE, DIMENSION(:,:,:) :: TREE_OUTPUT_DATA
REAL(EB),ALLOCATABLE, DIMENSION(:,:) :: TREE_OUTPUT_DATA_TOTAL

! Level Set vegetation fire spread
LOGICAL  :: LSET_IGNITION=.FALSE.,VEG_LEVEL_SET,VEG_LEVEL_SET_BURNERS_FOR_FIRELINE,VEG_LEVEL_SET_COUPLED,VEG_LEVEL_SET_UNCOUPLED, &
            VEG_LEVEL_SET_THERMAL_ELEMENTS,VEG_LEVEL_SET_SURFACE_HEATFLUX,VEG_LEVEL_SET_SURFACE_HRRPUA, &
            VEG_LEVEL_SET_FM10_SPREADRATE=.FALSE.,VEG_LEVEL_SET_SR_CROWNFIRE_MODEL=.FALSE.,VEG_LEVEL_SET_CFIS_CROWNFIRE_MODEL=.FALSE.
LOGICAL  :: RK2_PREDICTOR_LS,LSET_ELLIPSE,LSET_TAN2
REAL     :: DT_LS_UNCOUPLED,PHI_MIN_LS,PHI_MAX_LS
INTEGER  :: N_BRNR=0 !for 'burner' driven LS4 simulations
INTEGER  :: LEVEL_SET_MODE=4

! Using 'burners' to mimic the spread of a fireline
INTEGER, ALLOCATABLE, DIMENSION(:) :: BURNER_FILE

! Parameters for Terrain and Wind simulation needs

LOGICAL :: TERRAIN_CASE=.FALSE.,WIND_ONLY=.FALSE.,INIT_ATMOSPHERIC=.FALSE.
INTEGER :: N_VENT_TOTAL=0
REAL(EB) :: INIT_PLE=0._EB,INIT_Z0=0._EB 

! Sprinkler Variables
 
REAL(EB) :: C_DIMARZO=6.E6_EB
INTEGER :: NSTRATA,N_ACTUATED_SPRINKLERS=0,N_OPEN_NOZZLES=0
INTEGER, PARAMETER :: NDC=1000,NDC2=100
LOGICAL :: POROUS_FLOOR=.TRUE.,ALLOW_UNDERSIDE_PARTICLES=.FALSE.,ALLOW_SURFACE_PARTICLES=.TRUE.

! Particles and PARTICLEs
 
INTEGER :: MAXIMUM_PARTICLES,N_PART,PARTICLE_TAG,N_EVAC,N_EVAP_INDICES=0,WATER_PART_INDEX=0
REAL(EB) :: RUN_AVG_FAC
LOGICAL :: EB_PART_FILE=.FALSE.
 
! Number of initial value, pressure zone, and multiplier derived types
 
INTEGER :: N_INIT,N_ZONE,N_MULT 
LOGICAL, ALLOCATABLE, DIMENSION(:,:,:) :: CONNECTED_ZONES
REAL(EB) :: PRESSURE_RELAX_FACTOR=0.2_EB

! Clipping values
 
REAL(EB) :: TMPMIN,TMPMAX,RHOMIN,RHOMAX

! Flux limiter

INTEGER :: FLUX_LIMITER=2,CFL_VELOCITY_NORM=0
 
! CPU and Wall Clock Timings
 
INTEGER, PARAMETER :: N_TIMERS_FDS=11,N_TIMERS_EVAC=15,N_TIMERS_DIM=21,N_TIMERS_HVAC=16
REAL(EB), ALLOCATABLE, DIMENSION(:,:) :: TUSED
INTEGER, ALLOCATABLE, DIMENSION(:) :: NTCYC,NCYC
REAL(EB), ALLOCATABLE, DIMENSION(:) :: T_PER_STEP,T_ACCUM
REAL(EB) :: WALL_CLOCK_START, WALL_CLOCK_END, WALL_CLOCK_START_ITERATIONS

! OpenMP Specifications

INTEGER :: OPENMP_AVAILABLE_THREADS=0
LOGICAL :: USE_OPENMP=.FALSE., DEBUG_OPENMP=.FALSE.

! CSV specification

INTEGER :: N_CSVF=0

! Complex geometry (experimental)

INTEGER :: IMMERSED_BOUNDARY_METHOD=-1,N_GEOM=0,N_VERT=0,N_FACE=0,N_VOLU=0,CUTCELL_TEST=-1
INTEGER, PARAMETER :: IBOX=1,ISPHERE=2,ICYLINDER=3,IPLANE=4
REAL(EB) :: IBM_UVWMAX = 0._EB
REAL(FB), ALLOCATABLE, DIMENSION(:) :: FB_REAL_FACE_VALS_ARRAY

! HVAC Parameters

INTEGER :: N_DUCTNODES = 0, N_DUCTS = 0, N_FANS = 0, N_FILTERS = 0, N_AIRCOILS = 0,N_NETWORKS=0
INTEGER , ALLOCATABLE, DIMENSION(:) :: DUCT_NE,DUCTNODE_NE
LOGICAL :: HVAC_SOLVE=.FALSE.

CONTAINS

SUBROUTINE GET_REV_cons(MODULE_REV,MODULE_DATE)
INTEGER,INTENT(INOUT) :: MODULE_REV
CHARACTER(255),INTENT(INOUT) :: MODULE_DATE

WRITE(MODULE_DATE,'(A)') consrev(INDEX(consrev,':')+1:LEN_TRIM(consrev)-2)
READ (MODULE_DATE,'(I5)') MODULE_REV
WRITE(MODULE_DATE,'(A)') consdate

END SUBROUTINE GET_REV_cons
 
END MODULE GLOBAL_CONSTANTS
