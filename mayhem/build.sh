#!/usr/bin/env bash
#
# mayhem/build.sh — build SQLite's ossfuzz harness and its test suite (testfixture).
# Runs inside the commit image (mayhem/Dockerfile) as `mayhem` in /mayhem; safe to re-run offline.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
OUT="$SRC"

# Build directories are all gitignored (mayhem/.gitignore), so `git clean -ffdX` resets them.
GEN="$SRC/mayhem/build-gen" FUZZ="$SRC/mayhem/build-fuzz" TEST="$SRC/mayhem/build-test"

# 0) The git mirror lacks Fossil's `manifest`/`manifest.uuid`, which the makefile needs for the source id,
#    so synthesize them from the git HEAD. They are untracked and rewritten on every run.
CDATE="$(git log -1 --format=%cd --date=format:%Y-%m-%dT%H:%M:%S.000 2>/dev/null || echo 2000-01-01T00:00:00.000)"
CHASH="$(git rev-parse HEAD 2>/dev/null || echo 0000000000000000000000000000000000000000)"
printf 'C git\\smirror\nD %s\nR 00000000000000000000000000000000\nU mayhem\nZ 00000000000000000000000000000000\n' "$CDATE" > "$SRC/manifest"
printf '%s\n' "$CHASH" > "$SRC/manifest.uuid"

# 1) Amalgamation (sqlite3.c / sqlite3.h) from the in-tree sources, out-of-tree, normal compiler flags.
mkdir -p "$GEN"
(
  cd "$GEN"
  env -u CFLAGS -u LDFLAGS -u CXXFLAGS CC=cc \
    "$SRC/configure" --all --disable-shared >configure.log 2>&1 || { tail -50 configure.log >&2; exit 1; }
  env -u CFLAGS -u LDFLAGS -u CXXFLAGS make -j"$MAYHEM_JOBS" sqlite3.c sqlite3.h >make.log 2>&1 \
    || { tail -50 make.log >&2; exit 1; }
)

# 2) The sanitized project (the amalgamation), twice: SanCov-instrumented for the libFuzzer
#    binaries, plain for the -standalone reproducers. Same feature set as SQLite's OSS-Fuzz build.
mkdir -p "$FUZZ"
SQLITE_DEFS="-DSQLITE_DEBUG=1 -DSQLITE_THREADSAFE=0 -DSQLITE_MAX_LENGTH=128000000
 -DSQLITE_MAX_SQL_LENGTH=128000000 -DSQLITE_MAX_MEMORY=25000000 -DSQLITE_PRINTF_PRECISION_LIMIT=1048576
 -DSQLITE_MAX_PAGE_SIZE=65536 -DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_FTS3_PARENTHESIS -DSQLITE_ENABLE_FTS4
 -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_RTREE -DSQLITE_ENABLE_GEOPOLY -DSQLITE_ENABLE_DBSTAT_VTAB
 -DSQLITE_ENABLE_DBPAGE_VTAB -DSQLITE_ENABLE_STMTVTAB -DSQLITE_ENABLE_BYTECODE_VTAB
 -DSQLITE_ENABLE_MATH_FUNCTIONS -DSQLITE_ENABLE_COLUMN_METADATA -DSQLITE_ENABLE_PREUPDATE_HOOK
 -DSQLITE_ENABLE_SESSION -DSQLITE_ENABLE_STAT4 -DSQLITE_ENABLE_UNLOCK_NOTIFY -DSQLITE_ENABLE_EXPLAIN_COMMENTS
 -DSQLITE_ENABLE_DESERIALIZE -DSQLITE_ENABLE_NORMALIZE -DSQLITE_OMIT_LOAD_EXTENSION"
COMMON="$SANITIZER_FLAGS $DEBUG_FLAGS -O1 -I$GEN $SQLITE_DEFS"

$CC $COMMON -fsanitize=fuzzer-no-link -c "$GEN/sqlite3.c" -o "$FUZZ/sqlite3-fuzz.o"
$CC $COMMON -c "$GEN/sqlite3.c" -o "$FUZZ/sqlite3-plain.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.c" -o "$FUZZ/lsan_off.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$FUZZ/standalone_main.o"

# 3) Harness: ossfuzz (SQL text).
build_harness() {
  local name="$1" src="$2"
  $CC $COMMON -fsanitize=fuzzer-no-link -c "$src" -o "$FUZZ/$name-fuzz.o"
  $CC $COMMON -c "$src" -o "$FUZZ/$name-plain.o"
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$FUZZ/$name-fuzz.o" "$FUZZ/sqlite3-fuzz.o" \
      "$FUZZ/lsan_off.o" -lm -ldl -o "$OUT/$name"
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS "$FUZZ/$name-plain.o" "$FUZZ/sqlite3-plain.o" "$FUZZ/standalone_main.o" \
      "$FUZZ/lsan_off.o" -lm -ldl -o "$OUT/$name-standalone"
}
build_harness ossfuzz "$SRC/mayhem/ossfuzz-mined-b1e2fd1/ossfuzz.c"

# 4) The project's own test suite (testfixture), NORMAL flags, separate out-of-tree build.
mkdir -p "$TEST"
(
  cd "$TEST"
  env -u CFLAGS -u LDFLAGS -u CXXFLAGS CC=cc \
    "$SRC/configure" --all --disable-shared >configure.log 2>&1 || { tail -50 configure.log >&2; exit 1; }
  env -u CFLAGS -u LDFLAGS -u CXXFLAGS make -j"$MAYHEM_JOBS" testfixture >make.log 2>&1 \
    || { tail -50 make.log >&2; exit 1; }
)
[ -x "$TEST/testfixture" ]
