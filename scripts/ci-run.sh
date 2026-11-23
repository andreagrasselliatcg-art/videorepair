#!/bin/bash
# Esegue un comando; se fallisce, mostra le ultime righe come annotazioni GitHub
LOG="$(mktemp)"
"$@" >"$LOG" 2>&1
code=$?
cat "$LOG"
if [ $code -ne 0 ]; then
  tail -n 30 "$LOG" | while IFS= read -r l; do echo "::warning::${l//::/ }"; done
fi
exit $code
