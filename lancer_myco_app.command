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

if ! "$RSCRIPT_BIN" -e 'min_version <- "4.0.0"; if (getRversion() < min_version) quit(status = 1)' >/dev/null 2>&1; then
  current_r_version=$("$RSCRIPT_BIN" -e 'cat(as.character(getRversion()))')
  echo "ERREUR : version de R insuffisante."
  echo "Version détectée : R $current_r_version"
  echo "Version minimale requise : R 4.0.0"
  echo ""
  echo "Installez une version récente de R depuis :"
  echo "https://cran.r-project.org/bin/macosx/"
  echo ""
  echo "Après installation, relancez ce script."
  echo "Si R est déjà à jour, vérifiez que le Rscript trouvé est le bon :"
  echo "$RSCRIPT_BIN"
  echo ""
  echo "Appuyez sur une touche pour fermer cette fenêtre."
  read -k 1
  exit 1
fi

missing_packages=$("$RSCRIPT_BIN" -e '
pkgs <- c(
  "shiny", "processx", "later",
  "readxl", "dplyr", "stringr", "ggplot2", "gridExtra", "MASS", "nnet",
  "tidyr", "purrr", "readr", "forcats", "tibble", "scales"
)
missing <- pkgs[!vapply(pkgs, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]
cat(paste(missing, collapse = " "))
')

if [[ -n "$missing_packages" ]]; then
  echo "ERREUR : packages R manquants : $missing_packages"
  echo ""
  echo "Voulez-vous tenter une installation automatique depuis CRAN ? [o/N]"
  read "install_required_packages?"
  install_required_packages="${install_required_packages:l}"
  if [[ "$install_required_packages" == "o" || "$install_required_packages" == "oui" || "$install_required_packages" == "y" || "$install_required_packages" == "yes" ]]; then
    echo "Installation des packages obligatoires..."
    MYCO_REQUIRED_PACKAGES="$missing_packages" "$RSCRIPT_BIN" -e '
      pkgs <- strsplit(Sys.getenv("MYCO_REQUIRED_PACKAGES"), " ", fixed = TRUE)[[1]]
      install.packages(pkgs, repos = "https://cloud.r-project.org")
      missing <- pkgs[!vapply(pkgs, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]
      if (length(missing) > 0) {
        stop("Packages toujours manquants apres installation : ", paste(missing, collapse = ", "), call. = FALSE)
      }
    '
    install_exit_code=$?
    if [[ "$install_exit_code" -ne 0 ]]; then
      echo ""
      echo "ERREUR : installation automatique incomplète."
      echo "Installez manuellement dans R avec :"
      echo "install.packages(c(\"shiny\", \"processx\", \"later\", \"readxl\", \"dplyr\", \"stringr\", \"ggplot2\", \"gridExtra\", \"MASS\", \"nnet\", \"tidyr\", \"purrr\", \"readr\", \"forcats\", \"tibble\", \"scales\"), repos = \"https://cloud.r-project.org\")"
      echo ""
      echo "Appuyez sur une touche pour fermer cette fenêtre."
      read -k 1
      exit 1
    fi
  else
    echo "Installation annulée."
    echo "Installez-les dans R avec :"
    echo "install.packages(c(\"shiny\", \"processx\", \"later\", \"readxl\", \"dplyr\", \"stringr\", \"ggplot2\", \"gridExtra\", \"MASS\", \"nnet\", \"tidyr\", \"purrr\", \"readr\", \"forcats\", \"tibble\", \"scales\"), repos = \"https://cloud.r-project.org\")"
    echo ""
    echo "Appuyez sur une touche pour fermer cette fenêtre."
    read -k 1
    exit 1
  fi
fi

optional_missing_packages=$("$RSCRIPT_BIN" -e '
pkgs <- c("vegan", "minpack.lm", "ggrepel")
missing <- pkgs[!vapply(pkgs, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]
cat(paste(missing, collapse = " "))
')

if [[ -n "$optional_missing_packages" ]]; then
  echo "AVERTISSEMENT : packages R optionnels absents : $optional_missing_packages"
  echo "Certaines sorties avancees peuvent etre ignorees par les scripts."
  echo ""
  echo "Voulez-vous tenter l'installation automatique des packages optionnels ? [o/N]"
  read "install_optional_packages?"
  install_optional_packages="${install_optional_packages:l}"
  if [[ "$install_optional_packages" == "o" || "$install_optional_packages" == "oui" || "$install_optional_packages" == "y" || "$install_optional_packages" == "yes" ]]; then
    echo "Installation des packages optionnels..."
    MYCO_OPTIONAL_PACKAGES="$optional_missing_packages" "$RSCRIPT_BIN" -e '
      pkgs <- strsplit(Sys.getenv("MYCO_OPTIONAL_PACKAGES"), " ", fixed = TRUE)[[1]]
      install.packages(pkgs, repos = "https://cloud.r-project.org")
      missing <- pkgs[!vapply(pkgs, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]
      if (length(missing) > 0) {
        warning("Packages optionnels toujours absents : ", paste(missing, collapse = ", "))
      }
    '
    echo ""
  else
    echo "Installation optionnelle ignorée."
    echo "Installation manuelle possible :"
    echo "install.packages(c(\"vegan\", \"minpack.lm\", \"ggrepel\"), repos = \"https://cloud.r-project.org\")"
    echo ""
  fi
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
