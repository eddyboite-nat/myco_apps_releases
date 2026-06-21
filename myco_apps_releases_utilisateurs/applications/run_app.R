##
# ==================================================================================================================================
# Script : run_app.R
# Objet  : Point d'entrée pour lancer localement l'application Shiny
#          myco_apps_releases_utilisateurs/applications.
#
# Ce script :
#   1) Configure les options de lancement (CRAN, navigateur)
#   2) Vérifie la présence de app.R
#   3) Initialise les dossiers logs/ et results/
#   4) Journalise le contexte d'exécution
#   5) Installe les dépendances si nécessaire puis lance l'app Shiny
# ==================================================================================================================================
#
# Usage : Rscript run_app.R
#         (à exécuter depuis le dossier applications/)
#
# Dépendances : shiny (et packages requis par app.R)
# Auteur : Eddy Boite
# Date : 2026-06-21
# Version : 1.0
# ==================================================================================================================================

# Configuration des options R
options(
  repos = c(CRAN = "https://cloud.r-project.org"),
  shiny.launch.browser = TRUE
)
# Vérification de la présence de app.R
if (!file.exists("app.R")) {
  stop("Le fichier app.R est introuvable. Lancez ce script depuis le dossier applications/.", call. = FALSE)
}
# Initialisation des dossiers logs/ et results/
dir.create("logs", showWarnings = FALSE, recursive = TRUE)
dir.create("results", showWarnings = FALSE, recursive = TRUE)
# Journalisation du contexte d'exécution
log_file <- file.path("logs", paste0("lancement_shiny_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".log"))
sink(log_file, split = TRUE)
on.exit({ try(sink(), silent = TRUE) }, add = TRUE)
# Journalisation du contexte d'exécution
cat("Date :", as.character(Sys.time()), "\n")
cat("R :", R.version.string, "\n")
cat("Système :", paste(Sys.info(), collapse = " | "), "\n\n")
# Installation automatique des packages nécessaires
cat("\n============================================\n")
cat(" myco_apps_releases - lancement local\n")
cat("============================================\n\n")
# Vérification de la présence de app.R
if (!file.exists("app.R")) {
  stop("Le fichier app.R est introuvable. Lancez ce script depuis le dossier applications/.", call. = FALSE)
}
# Initialisation des dossiers logs/ et results/
dir.create("logs", showWarnings = FALSE, recursive = TRUE)
dir.create("results", showWarnings = FALSE, recursive = TRUE)
# Journalisation du contexte d'exécution
log_file <- file.path("logs", paste0("lancement_shiny_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".log"))
sink(log_file, split = TRUE)
on.exit({ try(sink(), silent = TRUE) }, add = TRUE)
# Journalisation du contexte d'exécution
cat("Date :", as.character(Sys.time()), "\n")
cat("R :", R.version.string, "\n")
cat("Système :", paste(Sys.info(), collapse = " | "), "\n\n")
# Installation automatique des packages nécessaires
source("install_packages.R", encoding = "UTF-8")
# Lancement de l'application Shiny
cat("Lancement de l'application Shiny...\n")
shiny::runApp(appDir = ".", launch.browser = TRUE)
