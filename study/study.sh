#!/usr/bin/env bash
# Thin wrapper so the daily loop is short: ./study/study.sh due
set -euo pipefail
exec python3 "$(dirname "$0")/study.py" "$@"
