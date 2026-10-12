#!/bin/bash
# Compila con SwiftPM (sin Xcode) y arma "Mis Looms.app" en macos/build/.
set -euo pipefail
cd "$(dirname "$0")"

NOMBRE="Mis Looms Dev"
APP="build/Mis Looms.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/MisLooms"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/MisLooms"
cp Info.plist "$APP/Contents/Info.plist"

if security find-identity -p codesigning | grep -q "$NOMBRE"; then
    codesign --force --sign "$NOMBRE" "$APP"
else
    echo "AVISO: no existe el certificado '$NOMBRE' (ejecuta ./crear-certificado.sh)."
    echo "       Firmando ad-hoc: macOS volverá a pedir permisos en cada compilación."
    codesign --force --sign - "$APP"
fi

echo "Listo: $PWD/$APP"
