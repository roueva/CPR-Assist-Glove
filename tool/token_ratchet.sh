#!/usr/bin/env bash
# Fails if raw token-audit violations exceed BASELINE (regression gate).
# Run from repo root: ./tool/token_ratchet.sh
cd "$(dirname "$0")/.." || exit 1

BASELINE=424

current=$(./tool/token_audit.sh | grep 'TOTAL VIOLATIONS' | grep -oE '[0-9]+')

if [ -z "$current" ]; then
  echo "token_ratchet: could not determine current violation count"
  exit 1
fi

if [ "$current" -gt "$BASELINE" ]; then
  echo "token_ratchet: FAIL — $current violations exceeds baseline of $BASELINE"
  exit 1
fi

echo "token_ratchet: OK — $current violations (baseline $BASELINE)"
