# Installation automatique des packages nécessaires
options(repos = c(CRAN = "https://cloud.r-project.org"))

packages_requis <- c(
  "shiny", "DT", "readr", "readxl", "writexl", "dplyr", "tidyr", "purrr",
  "stringr", "forcats", "ggplot2", "gridExtra", "scales", "tibble",
  "MASS", "nnet", "ggrepel"
)

packages_optionnels <- c("vegan", "minpack.lm")

installer_si_absent <- function(pkg, obligatoire = TRUE) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    cat("Installation du package :", pkg, "\n")
    ok <- tryCatch({
      install.packages(pkg, repos = "https://cloud.r-project.org")
      requireNamespace(pkg, quietly = TRUE)
    }, error = function(e) {
      cat("Impossible d'installer", pkg, ":", conditionMessage(e), "\n")
      FALSE
    })
    if (!isTRUE(ok) && obligatoire) {
      stop(
        "Package obligatoire indisponible : ", pkg, "\n",
        "Vérifiez la connexion internet puis relancez l'application.",
        call. = FALSE
      )
    }
  }
  invisible(TRUE)
}

cat("Vérification des composants R nécessaires...\n")
invisible(lapply(packages_requis, installer_si_absent, obligatoire = TRUE))
invisible(lapply(packages_optionnels, installer_si_absent, obligatoire = FALSE))
cat("Composants disponibles.\n\n")
