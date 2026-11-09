#!/usr/bin/env bash
#
# mayhem/test.sh — RUN a selection of SQLite's own Tcl test suite with the testfixture that
# mayhem/build.sh produced (mayhem/build-test/testfixture). Each test file ends with an
# "N errors out of M tests" line; those asserted-result counts feed the CTRF report.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}


TESTFIXTURE="$SRC/mayhem/build-test/testfixture"
[ -x "$TESTFIXTURE" ] || { echo "missing $TESTFIXTURE (mayhem/build.sh builds it)" >&2; emit_ctrf sqlite-tcl 0 1 0; exit 1; }

TESTS="select1 select2 select3 select4 select5 select6 select7 expr func func2 insert insert2 update delete
 join join2 where where2 where3 trigger1 trigger2 index like like2 null in in2 cast date json101 json102
 jsonb01 fts3aa vtab1 window1 with1 alter altertab upsert1 collate1 minmax limit orderby1 subquery view
 ../ext/fts5/test/fts5aa ../ext/rtree/rtree1"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/sqlite-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

passed=0 failed=0
for t in $TESTS; do
  f="$SRC/test/$t.test"
  if [ ! -f "$f" ]; then echo "FAIL $t: test file missing" >&2; failed=$((failed+1)); continue; fi
  out="$("$TESTFIXTURE" "$f" 2>&1)"
  line="$(printf '%s\n' "$out" | grep -E '^[0-9]+ errors out of [0-9]+ tests' | tail -n1)"
  if [ -z "$line" ]; then
    echo "FAIL $t: no \"N errors out of M tests\" summary" >&2; failed=$((failed+1)); continue
  fi
  errs="$(printf '%s' "$line" | awk '{print $1}')" total="$(printf '%s' "$line" | awk '{print $5}')"
  [ "$total" -gt 0 ] || { echo "FAIL $t: ran zero tests" >&2; failed=$((failed+1)); continue; }
  echo "$t: $line"
  passed=$((passed + total - errs)); failed=$((failed + errs))
done

emit_ctrf sqlite-tcl "$passed" "$failed" 0
