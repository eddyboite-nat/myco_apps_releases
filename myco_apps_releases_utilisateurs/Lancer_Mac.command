#!/bin/bash

echo ""
echo "============================================"
echo " myco_apps_releases - lancement local"
echo "============================================"
echo ""

cd "$(dirname "$0")/application" || exit 1

if ! command -v Rscript >/dev/null 2>&1; then
  echo "Rscript est introuvable."
  echo "Veuillez installer R depuis https://cran.r-project.org/"
  read -r -p "Appuyez sur Entrée pour fermer."
  exit 1
fi

Rscript run_app.R

echo ""
echo "Si l'application ne s'est pas ouverte, consultez les messages ci-dessus."
read -r -p "Appuyez sur Entrée pour fermer."
