#!/usr/bin/env bash
# Design token violations. Run from repo root: ./tool/token_audit.sh
cd "$(dirname "$0")/.." || exit 1
SRC="CPR-Assist-App/cpr_assist/lib"
EXCLUDE="$SRC/core/"

total=0

scan() {
  local label="$1" pattern="$2" allow="$3" hits count
  hits=$(grep -rnE "$pattern" "$SRC" --include="*.dart" | grep -v "^$EXCLUDE")
  [ -n "$allow" ] && hits=$(printf '%s\n' "$hits" | grep -vE "$allow")
  count=$(printf '%s' "$hits" | grep -c . )
  total=$((total + count))
  printf '\n=== %s (%d) ===\n' "$label" "$count"
  [ "$count" -gt 0 ] && printf '%s\n' "$hits"
}

scan "raw Color(0x...)"      'Color\(0x'
scan "Colors.*"              '\bColors\.'
scan "inline TextStyle"      'TextStyle\('
scan "inline BoxDecoration"  'BoxDecoration\('
scan "ScaffoldMessenger"     'ScaffoldMessenger'
scan "inline showDialog"     'showDialog\('
scan "Navigator.of"          'Navigator\.of\(context\)'
scan "MediaQuery size"       'MediaQuery\.(sizeOf|of)\(context\)\.size'
scan "hardcoded PdfColor"    '(PdfColor\(|PdfColors\.)' 'PdfTokens'

printf '\n========================\nTOTAL VIOLATIONS: %d\n' "$total"
