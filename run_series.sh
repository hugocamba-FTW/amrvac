#!/usr/bin/env bash
# run_series.sh — run a list of AMRVAC .par files sequentially.
#
# For each par file it:
#   1. reads base_filename from the par and creates the output directory
#      (AMRVAC does not create it itself)
#   2. runs: mpirun -np NP <amrvac binary> -i <par>
#   3. appends a one-line status to run_series.log in the current directory
#
# Usage:
#   ./run_series.sh [-n NP] [-e BINARY] file1.par [file2.par ...]
#   ./run_series.sh [-n NP] [-e BINARY] -l LISTFILE
#
#   -n NP        MPI ranks (default: 4)
#   -e BINARY    path to the amrvac executable (default: ./amrvac)
#   -l LISTFILE  text file with one .par path per line (comments and
#                blank lines allowed)
#
# Examples:
#   ./run_series.sh -n 8 MHD3A_test.par
#   ./run_series.sh -n 8 -l mhd_pars.txt
#   ls MHD{1,3,5}*.par | ./run_series.sh -n 8 -l /dev/stdin
#
# A run that finishes with "Finished AMRVAC" in its stdout is recorded as
# OK; anything else is recorded as FAILED with the exit code. Failures do
# not stop the series — check the log afterwards.

set -uo pipefail

NP=4
BIN=./amrvac
LISTFILE=""

while getopts "n:e:l:h" opt; do
  case "$opt" in
    n) NP="$OPTARG" ;;
    e) BIN="$OPTARG" ;;
    l) LISTFILE="$OPTARG" ;;
    h) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "usage: $0 [-n NP] [-e BINARY] [-l LISTFILE] file.par ..." >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

PARS=()
if [ -n "$LISTFILE" ]; then
  while IFS= read -r line; do
    line="${line%%#*}"; line="$(echo "$line" | xargs)"
    [ -n "$line" ] && PARS+=("$line")
  done < "$LISTFILE"
fi
PARS+=("$@")

if [ ${#PARS[@]} -eq 0 ]; then
  echo "No par files given. Run '$0 -h' for usage." >&2
  exit 2
fi
if [ ! -x "$BIN" ]; then
  echo "amrvac binary not found or not executable: $BIN" >&2
  echo "(build it with 'make' in this directory, or pass -e /path/to/amrvac)" >&2
  exit 2
fi

LOG=run_series.log
echo "=== run_series started $(date) | np=$NP | binary=$BIN ===" >> "$LOG"
FAILED=0

for PAR in "${PARS[@]}"; do
  NAME="$(basename "$PAR" .par)"
  if [ ! -f "$PAR" ]; then
    echo "$(date '+%F %T') MISSING  $PAR" | tee -a "$LOG"
    FAILED=$((FAILED + 1)); continue
  fi

  # Output directory = dirname of base_filename (quoted value in &filelist)
  BASE="$(grep -i 'base_filename' "$PAR" | head -1 | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/")"
  OUTDIR="$(dirname "$BASE")"
  if [ -z "$BASE" ] || [ "$OUTDIR" = "." ]; then
    echo "$(date '+%F %T') BADPAR   $PAR (no usable base_filename)" | tee -a "$LOG"
    FAILED=$((FAILED + 1)); continue
  fi
  mkdir -p "$OUTDIR"

  echo "$(date '+%F %T') START    $NAME (np=$NP) -> $OUTDIR" | tee -a "$LOG"
  OUT="${NAME}.out"
  mpirun -np "$NP" "$BIN" -i "$PAR" > "$OUT" 2>&1
  RC=$?

  if [ $RC -eq 0 ] && grep -q "Finished AMRVAC" "$OUT"; then
    echo "$(date '+%F %T') OK       $NAME" | tee -a "$LOG"
  else
    LAST="$(grep -i 'error' "$OUT" | tail -1 | cut -c1-120)"
    echo "$(date '+%F %T') FAILED   $NAME (exit=$RC) ${LAST:+-- $LAST}" | tee -a "$LOG"
    FAILED=$((FAILED + 1))
  fi
done

echo "=== run_series finished $(date) | failures: $FAILED ===" >> "$LOG"
[ $FAILED -eq 0 ] && echo "All runs finished OK." || echo "$FAILED run(s) failed — see $LOG and the per-run .out files."
exit $((FAILED > 0))
