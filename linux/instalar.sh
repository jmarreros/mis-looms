#!/usr/bin/env bash
# Compila e instala la app para el usuario actual: binario en ~/.local/bin, acceso en el
# lanzador (archivo .desktop) e icono. Se puede volver a ejecutar para actualizar.
set -euo pipefail
cd "$(dirname "$0")"

cargo build --release
install -d ~/.local/bin ~/.local/share/applications ~/.local/share/icons/hicolor/scalable/apps
ln -sf "$PWD/target/release/mis-looms" ~/.local/bin/mis-looms
install -m644 ../marca/logo.svg ~/.local/share/icons/hicolor/scalable/apps/mis-looms.svg
# Exec con ruta absoluta: el lanzador no siempre tiene ~/.local/bin en el PATH.
sed "s|^Exec=mis-looms|Exec=$HOME/.local/bin/mis-looms|" mis-looms.desktop > ~/.local/share/applications/mis-looms.desktop
update-desktop-database ~/.local/share/applications 2>/dev/null || true
gtk-update-icon-cache -q ~/.local/share/icons/hicolor 2>/dev/null || true
echo "Instalado. Búscalo como «Mis Looms» en el lanzador."
