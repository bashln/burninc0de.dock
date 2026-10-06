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
qmllint -I "$IMPORTS" -I /usr/lib/qt6/qml "${QMLFILES[@]}" > /tmp/qmllint.out 2>&1 || true
if grep -q 'Error:' /tmp/qmllint.out; then
  echo "qmllint reported errors:"
  grep 'Error:' /tmp/qmllint.out
  exit 1
fi
echo "qmllint: no errors"
