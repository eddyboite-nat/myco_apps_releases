# Lancement de l'application locale myco_apps_releases
options(
  repos = c(CRAN = "https://cloud.r-project.org"),
  shiny.launch.browser = TRUE
)

cat("\n============================================\n")
cat(" myco_apps_releases - lancement local\n")
cat("============================================\n\n")

if (!file.exists("app.R")) {
  stop("Le fichier app.R est introuvable. Lancez ce script depuis le dossier application/.", call. = FALSE)
}

dir.create("logs", showWarnings = FALSE, recursive = TRUE)
dir.create("results", showWarnings = FALSE, recursive = TRUE)

log_file <- file.path("logs", paste0("lancement_shiny_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".log"))
sink(log_file, split = TRUE)
on.exit({ try(sink(), silent = TRUE) }, add = TRUE)

cat("Date :", as.character(Sys.time()), "\n")
cat("R :", R.version.string, "\n")
cat("Système :", paste(Sys.info(), collapse = " | "), "\n\n")

source("install_packages.R", encoding = "UTF-8")

shiny::runApp(appDir = ".", launch.browser = TRUE)
