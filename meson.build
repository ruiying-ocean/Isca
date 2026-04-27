project('isca', ['fortran', 'c'],
  version:        'femic-isca-meson',
  meson_version:  '>=1.1',
  default_options: [
    'buildtype=release',
    'warning_level=0',
    'b_ndebug=if-release',
  ],
)

# ---------------------------------------------------------------------------
# Source list — read from the existing GFDL `path_names` file at configure
# time. Keeps a single source of truth across the mkmf-to-meson transition
# and means a Meson rebuild is enough to pick up upstream Isca changes.
#
# RRTM, grey, and Held-Suarez physics all live behind namelist toggles in
# idealized_moist_phys.F90 (`do_rrtm_radiation`, `do_grey_radiation`,
# `do_held_suarez`). They used to be selected at compile time via
# -DRRTM_NO_COMPILE / separate path_names; now they are runtime choices.
# Socrates (external checkout) and the column model (`#ifdef COLUMN_MODEL`
# in source) are deferred to follow-up work.
# ---------------------------------------------------------------------------

variant         = get_option('variant')
path_names_file = 'src' / 'extra' / 'model' / variant / 'path_names'
path_names_raw  = run_command(
  'cat',
  meson.current_source_dir() / path_names_file,
  check: true,
).stdout()

fortran_sources = []
c_sources       = []

# RRTM-SW ships its own copies of parkind.f90 and mcica_random_numbers.f90
# that declare the same Fortran modules (`parkind`, `mersennetwister`) as
# RRTM-LW's. Upstream the two pairs differ only in CVS keyword comments.
# mkmf accepted both and relied on link-order tie-breaking; Meson's
# stricter Fortran depscan refuses duplicate module providers. Skip the
# SW copies — gfortran's parkind.mod / mersennetwister.mod from the LW
# objects already satisfy the `use parkind` / `use mersennetwister`
# references inside rrtmg_sw_*.f90.
skip_paths = [
  'atmos_param/rrtm_radiation/rrtmg_sw/gcm_model/modules/parkind.f90',
  'atmos_param/rrtm_radiation/rrtmg_sw/gcm_model/src/mcica_random_numbers.f90',
]

foreach raw : path_names_raw.strip().split('\n')
  rel = raw.strip()
  if rel == '' or skip_paths.contains(rel)
    continue
  endif
  if rel.endswith('.F90') or rel.endswith('.f90')
    fortran_sources += files('src' / rel)
  elif rel.endswith('.c')
    c_sources       += files('src' / rel)
  endif
  # `.h` and `.inc` headers are picked up via include_directories below;
  # mkmf listed them in path_names for dep tracking, Meson does not need
  # them in the compile list.
endforeach

# ---------------------------------------------------------------------------
# Include directories
#
# Covers every #include / Fortran INCLUDE site in the path_names tree:
#   shared/include              fms_platform.h
#   shared/mpp/include          mpp_*.inc, mpp_*.h, system_clock.h
#   atmos_param/monin_obukhov   monin_obukhov_interfaces.h
#   shared/field_manager        Fortran include 'parse.inc'
#   shared/fms                  Fortran include "read_data_*.inc",
#                               "write_data.inc"
# mpif.h and netcdf.inc come from the MPI / netcdf-fortran deps.
# ---------------------------------------------------------------------------

inc_dirs = include_directories(
  'src/shared/include',
  'src/shared/mpp/include',
  'src/atmos_param/monin_obukhov',
  'src/shared/field_manager',
  'src/shared/fms',
)

# ---------------------------------------------------------------------------
# Preprocessor definitions — mirror the cppDefs that compile.sh has been
# passing to mkmf for the full Isca build.
# ---------------------------------------------------------------------------

cpp_defs = [
  '-Duse_libMPI',
  '-Duse_netCDF',
  '-Duse_LARGEFILE',
  '-DINTERNAL_FILE_NML',
  '-DOVERLOAD_C8',
]

# Socrates is an out-of-repo checkout (GFDL_SOC). When it isn't being built
# in, the SOC_NO_COMPILE guard in idealized_moist_phys.F90 stubs out the
# `use socrates_interface_mod` and turns do_socrates_radiation=.true. into
# a FATAL at runtime.
if not get_option('with_socrates')
  cpp_defs += '-DSOC_NO_COMPILE'
endif

# ---------------------------------------------------------------------------
# Compiler flags
#
# Lifted from src/extra/python/isca/templates/mkmf.template.gfort-macos
# and the matching ubuntu_conda template — same flag set works on both
# Homebrew gfortran and conda-forge gfortran. Pkg-config (via
# dependency() below) supplies netCDF/MPI include + lib paths, so no
# hardcoded /opt/homebrew or /usr/local lives in here.
#
#   -cpp                       run the Fortran preprocessor on .f90 too
#   -fcray-pointer             Cray pointers don't alias other vars
#   -ffree-line-length-none    tolerate long source lines
#   -fno-range-check           tolerate odd literal constants in RRTM
#   -fdefault-real-8           REAL = REAL(8) (FMS / RRTM compat)
#   -fdefault-double-8         DOUBLE = REAL(8)
#   -fallow-argument-mismatch  relax F77 compat checks gfortran 10+ fatals
#   -fallow-invalid-boz        tolerate BOZ literals RRTM still uses
#
# CFLAGS:
#   -D__IFC                              FMS legacy ifort-compat path
#   -Wno-error=implicit-function-declaration
#                                        Apple clang 21+ promotes the C99
#                                        diagnostic to error; FMS mosaic
#                                        helpers rely on the C89 rule.
# ---------------------------------------------------------------------------

fc = meson.get_compiler('fortran')
cc = meson.get_compiler('c')

f90_args = cpp_defs + [
  '-cpp', '-fcray-pointer',
  '-ffree-line-length-none', '-fno-range-check',
  '-fdefault-real-8', '-fdefault-double-8',
]
# -fallow-argument-mismatch and -fallow-invalid-boz were added in gfortran 10
# to relax checks that were promoted from warnings to errors. RRTM and FMS
# code triggers both. On gfortran < 10 the checks are still warnings, so the
# flags are unneeded — and rejected as unrecognized command-line options.
if fc.get_id() == 'gcc' and fc.version().version_compare('>=10')
  f90_args += ['-fallow-argument-mismatch', '-fallow-invalid-boz']
endif

c_args = cpp_defs + ['-D__IFC']
# Apple clang 21+ promotes "call to undeclared function" (C99) to an error.
# Linux gcc accepts -Wno-error=... silently for unknown warning groups, but
# scoping this to clang keeps the flag list honest.
if cc.get_id() == 'clang' or cc.get_id() == 'apple-clang'
  c_args += ['-Wno-error=implicit-function-declaration']
endif

# ---------------------------------------------------------------------------
# Dependencies — pkg-config based, no per-site hardcoded paths.
# ---------------------------------------------------------------------------

mpi_f    = dependency('mpi',            language: 'fortran')
mpi_c    = dependency('mpi',            language: 'c')
netcdf_f = dependency('netcdf-fortran')
netcdf_c = dependency('netcdf')

# ---------------------------------------------------------------------------
# isca.x — full atmos_solo build, single executable
# ---------------------------------------------------------------------------

isca_exe = executable('isca.x',
  fortran_sources + c_sources,
  include_directories: inc_dirs,
  fortran_args:        f90_args,
  c_args:              c_args,
  dependencies:        [mpi_f, mpi_c, netcdf_f, netcdf_c],
  install:             false,
)

# ---------------------------------------------------------------------------
# mppnccombine.x — postprocessing tool that stitches per-rank diagnostic
# files into a single netCDF. Replaces the standalone
# postprocessing/compile_mppn.sh shell script.
# ---------------------------------------------------------------------------

mppnccombine_exe = executable('mppnccombine.x',
  files('postprocessing/mppnccombine.c'),
  c_args:       ['-O'],
  dependencies: [netcdf_c],
  install:      false,
)

summary({
  'variant':       variant,
  'fortran':       fc.get_id() + ' ' + fc.version(),
  'fortran files': fortran_sources.length(),
  'c files':       c_sources.length(),
}, section: 'Isca build')
