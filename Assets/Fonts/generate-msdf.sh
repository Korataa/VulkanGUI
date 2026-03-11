#!/usr/bin/env bash
set -euo pipefail

FONT_FILE="${1:-JetBrainsMono-Regular.ttf}"
OUTPUT_BASE="${2:-JetBrainsMono-msdf}"
CHARSET="${CHARSET:-32-126}"
SIZE="${SIZE:-48}"
ATLAS_W="${ATLAS_W:-1024}"
ATLAS_H="${ATLAS_H:-1024}"
PXRANGE="${PXRANGE:-6}"

if ! command -v msdf-atlas-gen >/dev/null 2>&1; then
  echo "msdf-atlas-gen not found in PATH. Install: https://github.com/Chlumsky/msdf-atlas-gen" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FONT_PATH="$SCRIPT_DIR/$FONT_FILE"
OUT_IMG="$SCRIPT_DIR/$OUTPUT_BASE.png"
OUT_JSON="$SCRIPT_DIR/$OUTPUT_BASE.json"

if [[ ! -f "$FONT_PATH" ]]; then
  echo "Font file not found: $FONT_PATH" >&2
  exit 1
fi

msdf-atlas-gen \
  -font "$FONT_PATH" \
  -type msdf \
  -format png \
  -size "$SIZE" \
  -pxrange "$PXRANGE" \
  -dimensions "$ATLAS_W" "$ATLAS_H" \
  -charset "$CHARSET" \
  -imageout "$OUT_IMG" \
  -json "$OUT_JSON"

echo "Generated: $OUT_IMG"
echo "Generated: $OUT_JSON"
