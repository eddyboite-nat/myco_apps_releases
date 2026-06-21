#!/bin/bash

echo ""
echo "============================================"
echo " myco_apps_releases - lancement local"
echo "============================================"
echo ""

cd "$(dirname "$0")/applications" || exit 1

if ! command -v Rscript >/dev/null 2>&1; then
  echo "Rscript est introuvable."
  echo "Installez R, par exemple sous Debian/Ubuntu : sudo apt install r-base"
  exit 1
fi

Rscript run_app.R
