#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
IMPORTS=$(mktemp -d)
trap 'rm -rf "$IMPORTS"' EXIT
mkdir -p "$IMPORTS/qs"
ln -sfn /usr/share/omarchy/shell/Commons "$IMPORTS/qs/Commons"

echo "== node logic tests =="
node --test "$ROOT"/test/*.test.js

echo "== QJSEngine logic tests =="
QT_QPA_PLATFORM=offscreen qmltestrunner -input "$ROOT/test/qml"

echo "== qmllint =="
mapfile -t QMLFILES < <(find "$ROOT" -maxdepth 2 -name '*.qml' -not -path '*/test/*' | sort)
if ! qmllint -I "$IMPORTS" -I /usr/lib/qt6/qml "${QMLFILES[@]}" > "$IMPORTS/qmllint.out" 2>&1; then
  echo "qmllint failed to run or reported errors:"
  cat "$IMPORTS/qmllint.out"
  exit 1
fi
if grep -q 'Error:' "$IMPORTS/qmllint.out"; then
  echo "qmllint reported errors:"
  grep 'Error:' "$IMPORTS/qmllint.out"
  exit 1
fi
echo "qmllint: no errors"
