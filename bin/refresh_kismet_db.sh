#!/usr/bin/env bash
set -euo pipefail
LOGDIR="$HOME/cyt/logs"
TARGET="$HOME/cyt/kismet.db"

newest="$(ls -1t "$LOGDIR"/*.kismet 2>/dev/null | head -n 1 || true)"
if [[ -n "${newest:-}" ]]; then
  ln -sfn "$newest" "$TARGET"
fi
