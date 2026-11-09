#!/usr/bin/env bash
set -euo pipefail
# build-ru-probe.sh - assemble a Russian-PC package zip from windows/<package>/.
#
#   tools/build-ru-probe.sh phase2b2c-EXECUTED        -> dist/ru-probe-phase2b2c.zip
#
# The zip contains a ru-probe/ folder with the package's run files plus bin/xray.exe from the
# official Xray release XRAY_VERSION, verified against the pinned SHA-256 below (the same check
# as the release's .dgst file). Binaries are never committed: dist/ is git-ignored.
# Bookkeeping files (STATUS.md, EXECUTION-RECORD.md, RESULTS/) are left out of the zip.
#
# Offline or behind a proxy that blocks GitHub: download Xray-windows-64.zip yourself and pass
#   XRAY_ZIP=/path/to/Xray-windows-64.zip tools/build-ru-probe.sh <package>
# The checksum is verified either way.

XRAY_VERSION="${XRAY_VERSION:-26.10.31}"
XRAY_SHA256="${XRAY_SHA256:-2e04a9995a6f2ad1b28c0bb25c708ecb2695e43a1c9c7889c4b6ac2b48cf7a6a}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="${1:?usage: tools/build-ru-probe.sh <package folder under windows/>}"
SRC="$ROOT/windows/$PKG"
[[ -d "$SRC" ]] || { echo "error: no package folder $SRC" >&2; exit 1; }
NAME="${PKG%-EXECUTED}"; NAME="${NAME%-READY-NOT-RUN}"
DIST="$ROOT/dist"
OUT="$DIST/ru-probe-$NAME.zip"

WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT
mkdir -p "$WORK/ru-probe/bin" "$DIST"

# 1. run files only
( cd "$SRC" && find . -type f \
    ! -name 'STATUS.md' ! -name 'EXECUTION-RECORD.md' ! -name '.DS_Store' \
    ! -path './RESULTS/*' ! -path './bin/*' -print0 ) |
  while IFS= read -r -d '' f; do
    mkdir -p "$WORK/ru-probe/$(dirname "$f")"
    cp -p -- "$SRC/$f" "$WORK/ru-probe/$f"
  done

# 2. Xray, verified
ZIP="${XRAY_ZIP:-}"
if [[ -z "$ZIP" ]]; then
  ZIP="$WORK/Xray-windows-64.zip"
  curl -fsSL --max-time 300 -o "$ZIP" \
    "https://github.com/XTLS/Xray-core/releases/download/v$XRAY_VERSION/Xray-windows-64.zip" ||
    { echo "error: download failed (GitHub blocked or proxy? see XRAY_ZIP in the header)" >&2; exit 1; }
fi
actual="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
[[ "$actual" == "$XRAY_SHA256" ]] ||
  { echo "error: Xray zip SHA-256 $actual does not match pinned $XRAY_SHA256 (version $XRAY_VERSION)" >&2; exit 1; }
unzip -q -o "$ZIP" xray.exe LICENSE -d "$WORK/x"
cp "$WORK/x/xray.exe" "$WORK/ru-probe/bin/xray.exe"
cp "$WORK/x/LICENSE" "$WORK/ru-probe/bin/LICENSE-xray.txt"

# 3. zip
rm -f -- "$OUT"
( cd "$WORK" && zip -qr -9 "$OUT" ru-probe )
echo "Built: $OUT"
echo "SHA-256: $(shasum -a 256 "$OUT" | awk '{print $1}')"
echo "Xray: v$XRAY_VERSION (zip sha256 verified)"
