#!/usr/bin/env bash
#
# Generates an LLVM compiler backend (LCB) from a VADL specification and
# compiles the resulting LLVM toolchain with the Makefile that openvadl
# generates. Reports how long each step took.
#
# Works with the bash 3.2 shipped by macOS as well as with bash on Linux.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Defaults. LLVM build settings left empty are not passed to make, so the
# defaults of the generated Makefile apply.
# ---------------------------------------------------------------------------
REPO_ROOT="${OPENVADL_ROOT:-}"
SPEC="sys/risc-v/rv32iCustom.vadl"
TARGET=""
OUTPUT_DIR="output"
CACHE=1
MAKE_TARGET="build"
BUILD_TYPE=""
PROJECTS=""
UPSTREAM_TARGETS=""
UPSTREAM_TARGETS_SET=0
ASSERTIONS=""
JOBS=""
LINK_JOBS=""
LLVM_SRC=""
CLEAN=0
SKIP_VADL=0
SKIP_LLVM=0
SKIP_VADL_BUILD=0
VADL_VARIANT="openvadl"
CSV_FILE=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Generates the LLVM compiler backend from a VADL specification (openvadl lcb)
and compiles the LLVM toolchain using the generated <output-dir>/lcb/Makefile.
Prints the duration of the VADL generation, the LLVM compilation and the total.

Repository:
  -r, --repo-root DIR      OpenVADL repository to work in (default: \$OPENVADL_ROOT,
                           else the parent of the script's directory, else the
                           current directory, whichever is an OpenVADL checkout).
                           Relative paths of all other options are resolved
                           against this directory.

Specification / generation:
  -s, --spec FILE          VADL specification (default: $SPEC)
  -t, --target NAME        LLVM target name passed to openvadl
                           (default: spec file name in lower case)
  -o, --output-dir DIR     openvadl output directory; sources and the Makefile
                           are generated into DIR/lcb (default: $OUTPUT_DIR)
      --vadl VARIANT       openvadl build used for the generation:
                             openvadl     JVM build    (./gradlew installDist)
                             nativevadl   GraalVM native image, serial GC
                                          (./gradlew nativeCompile)
                             epsilonvadl  GraalVM native image, Epsilon GC,
                                          i.e. no garbage collection
                                          (./gradlew nativeEpsilonCompile)
                           The native variants need a GraalVM JDK, e.g. via
                           GRAALVM_HOME (default: $VADL_VARIANT)
      --skip-vadl-build    Do not run the Gradle task above before generating
      --skip-vadl          Skip the VADL generation step
      --skip-llvm          Skip the LLVM compilation step

LLVM build (options not given fall back to the generated Makefile's defaults):
      --cache              Build with the Makefile's compiler caching
                           (ccache and sccache) (default)
      --no-cache           Build without any compiler cache
  -b, --build-type TYPE    Debug, Release, RelWithDebInfo or MinSizeRel
                           (LLVM_CMAKE_BUILD_TYPE)
      --projects LIST      LLVM_ENABLE_PROJECTS, e.g. "clang;lld"
      --upstream-targets L LLVM_UPSTREAM_TARGETS, e.g. "RISCV"
      --assertions On|Off  LLVM_ENABLE_ASSERTIONS
  -j, --jobs N             LLVM_PARALLEL_COMPILE_JOBS
      --link-jobs N        LLVM_PARALLEL_LINK_JOBS
      --llvm-src DIR       LLVM_SOURCE_PATH, the llvm-project checkout
                           (Makefile default: <output-dir>/lcb/llvm-final)
      --make-target T      Makefile target: build, build-llc, build-clang or
                           build-lld (default: $MAKE_TARGET)
      --clean              Delete <llvm-src>/build first (cold build)

Reporting:
      --csv FILE           Append the timings as a row to FILE

  -h, --help               Show this help and exit

Examples:
  $(basename "$0")
  $(basename "$0") --spec sys/risc-v/rv32im.vadl --build-type Release --no-cache --clean
  $(basename "$0") --make-target build-llc --csv timings.csv
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

need_arg() {
  [ $# -ge 2 ] && [ -n "$2" ] || die "option '$1' requires an argument"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -r|--repo-root) need_arg "$@"; REPO_ROOT="$2"; shift 2 ;;
    -s|--spec) need_arg "$@"; SPEC="$2"; shift 2 ;;
    -t|--target) need_arg "$@"; TARGET="$2"; shift 2 ;;
    -o|--output-dir) need_arg "$@"; OUTPUT_DIR="$2"; shift 2 ;;
    --cache) CACHE=1; shift ;;
    --no-cache) CACHE=0; shift ;;
    -b|--build-type) need_arg "$@"; BUILD_TYPE="$2"; shift 2 ;;
    --projects) need_arg "$@"; PROJECTS="$2"; shift 2 ;;
    # May be empty on purpose (no upstream targets).
    --upstream-targets)
      [ $# -ge 2 ] || die "option '$1' requires an argument"
      UPSTREAM_TARGETS="$2"; UPSTREAM_TARGETS_SET=1; shift 2 ;;
    --assertions) need_arg "$@"; ASSERTIONS="$2"; shift 2 ;;
    -j|--jobs) need_arg "$@"; JOBS="$2"; shift 2 ;;
    --link-jobs) need_arg "$@"; LINK_JOBS="$2"; shift 2 ;;
    --llvm-src) need_arg "$@"; LLVM_SRC="$2"; shift 2 ;;
    --make-target) need_arg "$@"; MAKE_TARGET="$2"; shift 2 ;;
    --clean) CLEAN=1; shift ;;
    --skip-vadl) SKIP_VADL=1; shift ;;
    --skip-llvm) SKIP_LLVM=1; shift ;;
    --skip-vadl-build) SKIP_VADL_BUILD=1; shift ;;
    --vadl) need_arg "$@"; VADL_VARIANT="$2"; shift 2 ;;
    --csv) need_arg "$@"; CSV_FILE="$2"; shift 2 ;;
    *) usage >&2; echo >&2; die "unknown option '$1'" ;;
  esac
done

# ---------------------------------------------------------------------------
# Validation and derived values
# ---------------------------------------------------------------------------
case "$BUILD_TYPE" in
  ""|Debug|Release|RelWithDebInfo|MinSizeRel) ;;
  *) die "invalid build type '$BUILD_TYPE' (expected Debug, Release, RelWithDebInfo or MinSizeRel)" ;;
esac

case "$ASSERTIONS" in
  ""|On|Off|ON|OFF|on|off) ;;
  *) die "invalid value for --assertions: '$ASSERTIONS' (expected On or Off)" ;;
esac

case "$VADL_VARIANT" in
  openvadl)
    VADL_GRADLE_TASK="installDist"
    VADL_BIN="vadl-cli/build/install/openvadl/bin/openvadl" ;;
  nativevadl)
    VADL_GRADLE_TASK="nativeCompile"
    VADL_BIN="vadl-cli/build/native/nativeCompile/openvadl" ;;
  epsilonvadl)
    VADL_GRADLE_TASK="nativeEpsilonCompile"
    VADL_BIN="vadl-cli/build/native/nativeEpsilonCompile/openvadl" ;;
  *) die "invalid vadl variant '$VADL_VARIANT' (expected openvadl, nativevadl or epsilonvadl)" ;;
esac

case "$MAKE_TARGET" in
  build|build-llc|build-clang|build-lld) ;;
  *) die "invalid make target '$MAKE_TARGET' (expected build, build-llc, build-clang or build-lld)" ;;
esac

is_repo_root() {
  [ -x "$1/gradlew" ] && [ -d "$1/vadl-cli" ]
}

if [ -n "$REPO_ROOT" ]; then
  [ -d "$REPO_ROOT" ] || die "repository root '$REPO_ROOT' does not exist"
  REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"
  is_repo_root "$REPO_ROOT" || die "'$REPO_ROOT' is not an OpenVADL repository (no gradlew or vadl-cli)"
elif is_repo_root "$SCRIPT_DIR/.."; then
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
elif is_repo_root "$PWD"; then
  REPO_ROOT="$PWD"
else
  die "cannot find the OpenVADL repository; pass --repo-root DIR or set OPENVADL_ROOT"
fi

cd "$REPO_ROOT"

if [ "$SKIP_VADL" -eq 0 ]; then
  [ -f "$SPEC" ] || die "specification '$SPEC' does not exist"
fi

if [ -z "$TARGET" ]; then
  TARGET="$(basename "$SPEC" .vadl | tr '[:upper:]' '[:lower:]')"
fi

GEN_DIR="$OUTPUT_DIR/lcb"
MAKEFILE="$GEN_DIR/Makefile"

if [ "$SKIP_LLVM" -eq 0 ]; then
  for tool in make cmake ninja git; do
    command -v "$tool" >/dev/null || die "'$tool' not found in PATH"
  done
fi

# Wall-clock time in seconds with millisecond precision. `date +%s.%N` is not
# supported on macOS, so perl is used instead (available on macOS and Linux).
now() {
  perl -MTime::HiRes=time -e 'printf "%.3f\n", time'
}

elapsed() {
  perl -e 'printf "%.3f\n", $ARGV[1] - $ARGV[0]' "$1" "$2"
}

fmt_duration() {
  perl -e '
    my $t = $ARGV[0];
    my $h = int($t / 3600); my $m = int(($t - $h * 3600) / 60);
    my $s = $t - $h * 3600 - $m * 60;
    printf "%02d:%02d:%06.3f (%.3f s)\n", $h, $m, $s, $t;
  ' "$1"
}

section() {
  printf '\n==> %s\n' "$*"
}

# Reads the value of a plain `VAR=value` or `VAR ?= value` line from the Makefile.
makefile_value() {
  sed -n -E "s/^[[:space:]]*$1[[:space:]]*\??=[[:space:]]*\"?([^\"]*)\"?[[:space:]]*$/\1/p" "$MAKEFILE" | head -n 1
}

# The generated Makefile hard-codes the compiler launcher (sccache) in the cmake
# call. Replace it with a variable that defaults to the original value, so it can
# be disabled from the command line. Running this on a patched Makefile is a no-op.
patch_makefile_launcher() {
  local launcher tmp
  if grep -q '^LLVM_COMPILER_LAUNCHER ?=' "$MAKEFILE"; then
    return
  fi
  launcher="$(sed -n -E 's/.*-DCMAKE_CXX_COMPILER_LAUNCHER=([^[:space:]\\]*).*/\1/p' "$MAKEFILE" | head -n 1)"
  tmp="$(mktemp)"
  {
    echo "LLVM_COMPILER_LAUNCHER ?= $launcher"
    sed -E 's/(-DCMAKE_(C|CXX)_COMPILER_LAUNCHER=)[^[:space:]\\]*/\1$(LLVM_COMPILER_LAUNCHER)/' "$MAKEFILE"
  } > "$tmp"
  mv "$tmp" "$MAKEFILE"
}

echo "Repository    : $REPO_ROOT"
echo "Specification : $SPEC"
echo "VADL variant  : $VADL_VARIANT ($VADL_BIN)"
echo "Target        : $TARGET"
echo "Generated dir : $GEN_DIR"
if [ "$CACHE" -eq 1 ]; then
  echo "Compiler cache: on"
else
  echo "Compiler cache: off"
fi

VADL_TIME="0"
LLVM_TIME="0"

# ---------------------------------------------------------------------------
# Step 1: VADL generation
# ---------------------------------------------------------------------------
if [ "$SKIP_VADL" -eq 0 ]; then
  OPENVADL="$REPO_ROOT/$VADL_BIN"

  # Building openvadl itself is not part of the measured generation time.
  if [ "$SKIP_VADL_BUILD" -eq 0 ]; then
    section "Building $VADL_VARIANT (./gradlew $VADL_GRADLE_TASK, not timed)"
    ./gradlew "$VADL_GRADLE_TASK" -q
  fi
  [ -x "$OPENVADL" ] || die "'$OPENVADL' not found; run without --skip-vadl-build"

  section "Generating LLVM sources from $SPEC"
  start="$(now)"
  "$OPENVADL" lcb "$SPEC" --output "$OUTPUT_DIR" --target "$TARGET"
  VADL_TIME="$(elapsed "$start" "$(now)")"
  echo "VADL generation took $(fmt_duration "$VADL_TIME")"
fi

# ---------------------------------------------------------------------------
# Step 2: LLVM compilation via the generated Makefile
# ---------------------------------------------------------------------------
if [ "$SKIP_LLVM" -eq 0 ]; then
  [ -f "$MAKEFILE" ] || die "no generated Makefile at '$MAKEFILE'; run without --skip-vadl"

  patch_makefile_launcher

  # make runs inside GEN_DIR, so a user-given source path must be absolute.
  if [ -n "$LLVM_SRC" ]; then
    mkdir -p "$LLVM_SRC"
    LLVM_SRC="$(cd "$LLVM_SRC" && pwd)"
  fi

  MAKE_VARS=()
  [ -z "$BUILD_TYPE" ] || MAKE_VARS+=("LLVM_CMAKE_BUILD_TYPE=$BUILD_TYPE")
  [ -z "$PROJECTS" ] || MAKE_VARS+=("LLVM_ENABLE_PROJECTS=$PROJECTS")
  [ "$UPSTREAM_TARGETS_SET" -eq 0 ] || MAKE_VARS+=("LLVM_UPSTREAM_TARGETS=$UPSTREAM_TARGETS")
  [ -z "$ASSERTIONS" ] || MAKE_VARS+=("LLVM_ENABLE_ASSERTIONS=$ASSERTIONS")
  [ -z "$JOBS" ] || MAKE_VARS+=("LLVM_PARALLEL_COMPILE_JOBS=$JOBS")
  [ -z "$LINK_JOBS" ] || MAKE_VARS+=("LLVM_PARALLEL_LINK_JOBS=$LINK_JOBS")
  [ -z "$LLVM_SRC" ] || MAKE_VARS+=("LLVM_SOURCE_PATH=$LLVM_SRC")
  if [ "$CACHE" -eq 0 ]; then
    MAKE_VARS+=("LLVM_CCACHE_BUILD=0" "LLVM_COMPILER_LAUNCHER=")
  else
    launcher="$(makefile_value LLVM_COMPILER_LAUNCHER)"
    if [ -n "$launcher" ] && ! command -v "$launcher" >/dev/null; then
      die "compiler launcher '$launcher' from the Makefile not found in PATH; use --no-cache"
    fi
  fi

  if [ -n "$LLVM_SRC" ]; then
    BUILD_DIR="$LLVM_SRC/build"
  else
    BUILD_DIR="$GEN_DIR/$(makefile_value LLVM_SOURCE_PATH)/build"
  fi

  if [ "$CLEAN" -eq 1 ] && [ -d "$BUILD_DIR" ]; then
    section "Removing build directory $BUILD_DIR"
    rm -rf "$BUILD_DIR"
  fi

  section "Building LLVM: make $MAKE_TARGET ${MAKE_VARS[*]:-}"
  start="$(now)"
  # ${arr[@]+...} avoids an "unbound variable" error for empty arrays in bash 3.2.
  make -C "$GEN_DIR" "$MAKE_TARGET" ${MAKE_VARS[@]+"${MAKE_VARS[@]}"}
  LLVM_TIME="$(elapsed "$start" "$(now)")"
  echo "LLVM compilation took $(fmt_duration "$LLVM_TIME")"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
TOTAL_TIME="$(perl -e 'printf "%.3f\n", $ARGV[0] + $ARGV[1]' "$VADL_TIME" "$LLVM_TIME")"

section "Summary"
printf 'VADL generation : %s\n' "$(fmt_duration "$VADL_TIME")"
printf 'LLVM compilation: %s\n' "$(fmt_duration "$LLVM_TIME")"
printf 'Total           : %s\n' "$(fmt_duration "$TOTAL_TIME")"
[ "$SKIP_LLVM" -eq 1 ] || printf 'Binaries        : %s/bin\n' "$BUILD_DIR"

if [ -n "$CSV_FILE" ]; then
  CSV_HEADER_V1="timestamp,spec,target,make_target,build_type,cache,clean,vadl_s,llvm_s,total_s"
  CSV_HEADER="$CSV_HEADER_V1,vadl"
  if [ ! -s "$CSV_FILE" ]; then
    echo "$CSV_HEADER" > "$CSV_FILE"
  elif [ "$(head -n 1 "$CSV_FILE")" = "$CSV_HEADER_V1" ]; then
    # Files written before --vadl existed: all of those runs used the JVM build.
    tmp="$(mktemp)"
    { echo "$CSV_HEADER"; tail -n +2 "$CSV_FILE" | sed 's/$/,openvadl/'; } > "$tmp"
    mv "$tmp" "$CSV_FILE"
    echo "Added the 'vadl' column to $CSV_FILE (existing rows: openvadl)"
  elif [ "$(head -n 1 "$CSV_FILE")" != "$CSV_HEADER" ]; then
    die "unexpected header in '$CSV_FILE'; use a new CSV file"
  fi
  CSV_BUILD_TYPE="$BUILD_TYPE"
  [ -n "$CSV_BUILD_TYPE" ] || [ ! -f "$MAKEFILE" ] || CSV_BUILD_TYPE="$(makefile_value LLVM_CMAKE_BUILD_TYPE)"
  echo "$(date '+%Y-%m-%dT%H:%M:%S'),$SPEC,$TARGET,$MAKE_TARGET,$CSV_BUILD_TYPE,$CACHE,$CLEAN,$VADL_TIME,$LLVM_TIME,$TOTAL_TIME,$VADL_VARIANT" >> "$CSV_FILE"
  echo "Timings appended to $CSV_FILE"
fi
