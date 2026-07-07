#!/bin/zsh

set -u

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/Library/Frameworks/R.framework/Resources/bin:$PATH"

SCRIPT_DIR="${0:A:h}"
cd "$SCRIPT_DIR" || exit 1

echo "========================================"
echo "Myco Apps Local"
echo "========================================"
echo "Dossier projet : $SCRIPT_DIR"
echo ""

RSCRIPT_BIN="$(command -v Rscript || true)"
if [[ -z "$RSCRIPT_BIN" && -x "/Library/Frameworks/R.framework/Resources/bin/Rscript" ]]; then
  RSCRIPT_BIN="/Library/Frameworks/R.framework/Resources/bin/Rscript"
fi

if [[ -z "$RSCRIPT_BIN" ]]; then
  echo "ERREUR : Rscript est introuvable."
  echo "Installez R depuis https://cran.r-project.org/bin/macosx/"
  echo "Si R est déjà installé, vérifiez que Rscript est accessible dans le PATH."
  echo ""
  echo "Appuyez sur une touche pour fermer cette fenêtre."
  read -k 1
  exit 1
fi

echo "Version R :"
"$RSCRIPT_BIN" --version
echo ""

missing_packages=$("$RSCRIPT_BIN" -e '
pkgs <- c("shiny", "processx", "later")
missing <- pkgs[!vapply(pkgs, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]
cat(paste(missing, collapse = " "))
')

if [[ -n "$missing_packages" ]]; then
  echo "ERREUR : packages R manquants : $missing_packages"
  echo "Installez-les dans R avec :"
  echo "install.packages(c(\"shiny\", \"processx\", \"later\"))"
  echo ""
  echo "Appuyez sur une touche pour fermer cette fenêtre."
  read -k 1
  exit 1
fi

echo "Lancement de l'application..."
echo "URL locale : http://127.0.0.1:8765/"
echo ""
echo "Pour fermer proprement : utilisez le bouton \"Fermer l'app\" dans l'interface."
echo ""

"$RSCRIPT_BIN" app.R
app_exit_code=$?
if [[ "$app_exit_code" -ne 0 ]]; then
  echo ""
  echo "ERREUR : l'application s'est arrêtée avec le code $app_exit_code."
  echo "Lisez les messages ci-dessus pour identifier la cause."
  echo ""
  echo "Appuyez sur une touche pour fermer cette fenêtre."
  read -k 1
  exit "$app_exit_code"
fi

echo ""
echo "Application fermée."
echo "Appuyez sur une touche pour fermer cette fenêtre."
read -k 1
