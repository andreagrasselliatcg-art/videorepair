#!/bin/bash
# Esegue un comando; se fallisce, mostra le ultime righe come annotazioni GitHub
LOG="$(mktemp)"
if "$@" >"$LOG" 2>&1; then cat "$LOG"; exit 0; fi
code=$?
cat "$LOG"
tail -n 30 "$LOG" | while IFS= read -r l; do echo "::warning::${l//::/ }"; done
exit $code
