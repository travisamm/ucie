#!/usr/bin/env bash
# Open IMC GUI for MBINIT or SBINIT coverage.
# Usage:
#   ./open_imc.sh [subsystem] [action]
#
#   subsystem : mbinit (default) | sbinit
#   action    : (none) — load merged database (union of all runs)
#               sanity — load only the sanity run
#               report — print the Markdown coverage report
#
# Examples:
#   ./open_imc.sh                    — mbinit merged GUI
#   ./open_imc.sh sbinit             — sbinit merged GUI
#   ./open_imc.sh mbinit sanity      — mbinit sanity-only GUI
#   ./open_imc.sh sbinit report      — print sbinit Markdown report

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export MDV_XLM_HOME=/share/instsww/cadence/XCELIUM2509
IMC=/share/instsww/cadence/VMANAGER2509/tools/bin/imc

# Parse subsystem and action from args
ARG1="${1:-}"
ARG2="${2:-}"

if [ "$ARG1" = "sbinit" ]; then
  SUBSYS=sbinit
  ACTION="$ARG2"
elif [ "$ARG1" = "mbinit" ]; then
  SUBSYS=mbinit
  ACTION="$ARG2"
else
  # Backward compat: no subsystem prefix → mbinit, first arg is action
  SUBSYS=mbinit
  ACTION="$ARG1"
fi

WORK="$SCRIPT_DIR/cov_work/$SUBSYS"
SCOPE="$WORK/scope"
MERGED="$SCOPE/merged_all"
RUNFILE="$WORK/runfile.txt"
REPORT="$WORK/coverage.md"
MAKE_TARGET="cov_$SUBSYS"

case "$ACTION" in
  sanity)
    DB="$SCOPE/test_${SUBSYS}_sanity"
    if [ ! -d "$DB" ]; then
      echo "No sanity run found. Run 'make $MAKE_TARGET' first."
      exit 1
    fi
    echo "Opening IMC GUI with $SUBSYS sanity run only."
    "$IMC" -load "$DB" &
    ;;
  report)
    if [ ! -f "$REPORT" ]; then
      echo "No report found. Run 'make $MAKE_TARGET' first."
      exit 1
    fi
    echo "Markdown coverage report: $REPORT"
    "${PAGER:-cat}" "$REPORT"
    ;;
  *)
    # Build merged database if it doesn't exist yet
    if [ ! -d "$MERGED" ]; then
      echo "Merged database not found — building it now..."
      if [ ! -d "$SCOPE" ]; then
        echo "No coverage data found. Run 'make $MAKE_TARGET' first."
        exit 1
      fi
      ls "$SCOPE" | grep "^test_" | while read d; do echo "$SCOPE/$d"; done > "$RUNFILE"
      first=$(head -1 "$RUNFILE")
      "$IMC" -load "$first" \
        -execcmd "merge -runfile $RUNFILE -out $MERGED -overwrite; exit"
    fi
    echo "Opening IMC GUI with $SUBSYS merged database (all runs union)."
    "$IMC" -load "$MERGED" \
      -initcmd "exclude -type mbinit_state_sync_sva -metrics assertion -comment {Intentionally unbound: XC-03 property too tight for RTL substate timing}" &
    ;;
esac
