#
# ==================================================================================================================================
# Script : inventaires_completude_representativite.R
# Objet  : Automatiser les analyses d'inventaires fongiques
#          inspirées des diapositives 25-48 du cours 24 DU Mycologie 2026
#
# Analyses produites :
#   1) Courbe temps-espèces
#   2) Ajustement linéaire et hyperbolique
#   3) Estimation d'asymptote (richesse théorique)
#   4) Taux d'espèces exceptionnelles (TEE)
#   5) Indice de représentativité Ir = 1 - TEE
#   6) Fréquence des espèces par visite
#   7) Distribution spatiale (si placette disponibles)
#   8) Ordination simple (CA) si souhaité
#
# Optimisations :
#   Phase 1 [v1.1] : Fiabilisation (validation robuste, détection formats)
#   Phase 2 [v1.2] : Performance (vectorisation calculs cumulés, benchmarking)
#   Phase 3 [v1.3] : Graphiques (thème unifié CVD-friendly, annotations scientifiques)
#                    - Palette accessible (5 couleurs distinctes)
#                    - Thème de projet cohérent across tous les graphiques
#                    - TEE/Ir: diagramme 2 panneaux avec zones scientifiques (seuils)
#                    - Comparaisons sites: classement par complétude/Ir, annotations
#                    - Export multi-formats (PNG, PDF, SVG)
#   Phase 4 [v1.4] : Industrialisation & métriques de pertinence scientifique
#                    - Rapport Quarto
#                    - Métriques de robustesse/stabilité/pertinence exportées par site et globalement
# ==================================================================================================================================

#
# Usage : Rscript inventaires_completude_representativite.R
#         (ou source("inventaires_completude_representativite.R") dans R interactif)
#
# Dépendances : dplyr, tidyr, ggplot2, purrr, readr, stringr, forcats, tibble, scales, gridExtra
#              (vegan pour CA, minpack.lm pour modèle hyperbolique - optionnels)
# Auteur : Eddy Boite
# Date : 2024-06-15
# Version : 1.4 (Phase 1 + Phase 2 + Phase 3 + Phase 4 métriques scientifiques)
#
# ===================================================================================================================================
# Contrôle d'exécution et options globales
IS_INTERACTIVE_SESSION <- interactive()
CLEAN_ENVIRONMENT <- FALSE  # Mettre à TRUE UNIQUEMENT si exécution isolée requise
DEBUG_MODE <- FALSE          # Mettre à TRUE pour plus de verbosité et warnings détaillés
BENCHMARK_MODE <- FALSE      # Mettre à TRUE pour mesurer temps d'exécution des calculs
AUTO_RUN <- {
  auto_run_env <- tolower(trimws(Sys.getenv("INVENTAIRES_AUTO_RUN", unset = "TRUE")))
  !(auto_run_env %in% c("0", "false", "no", "off"))
}
# ====================================================================================================================================
# Initialisation du script : affichage d'un header informatif et configuration des options globales
print(paste(Sys.time(), "- Initialisation du script ..."))

# Nettoyage optionnel de l'environnement (non recommandé en usage normal)
if (!IS_INTERACTIVE_SESSION && isTRUE(CLEAN_ENVIRONMENT)) {
  rm(list = setdiff(ls(), c("CLEAN_ENVIRONMENT", "DEBUG_MODE", "IS_INTERACTIVE_SESSION")))
  message("Environnement nettoyé (CLEAN_ENVIRONMENT=TRUE).")
}

# Options globales R : éviter les facteurs, réduire les messages d'information de dplyr, mode debug pour warnings détaillés
options(stringsAsFactors = FALSE)
options(dplyr.summarise.inform = FALSE)
if (isTRUE(DEBUG_MODE)) options(warn = 1)  # Mode debug : afficher tous les warnings

# Configuration packages
CRAN_REPO <- "https://cloud.r-project.org"

# Fonction utilitaire : vérifie que les packages requis sont installés, sinon génère une erreur avec instructions d'installation
check_required_packages <- function(pkgs, repos = CRAN_REPO) {
  # Vérification simple de la disponibilité des packages requis
  # Génère une erreur claire avec instructions si packages manquants
  available <- vapply(pkgs, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))
  missing_pkgs <- pkgs[!available]
  
  if (length(missing_pkgs) > 0) {
    install_cmd <- sprintf(
      "install.packages(c(%s))",
      paste(sprintf("'%s'", missing_pkgs), collapse = ", ")
    )
    stop(
      "Packages requis manquants : ", paste(missing_pkgs, collapse = ", "),
      "\nVeuillez installer avec :\n  ", install_cmd,
      call. = FALSE
    )
  }
  invisible(TRUE)
}

# Chargement des packages requis (erreur explicite si l'un est manquant)
suppressPackageStartupMessages({
  required_pkgs <- c(
    "dplyr", "tidyr", "ggplot2", "purrr", "readr", "stringr",
    "forcats", "tibble", "scales", "gridExtra"
  )
  check_required_packages(required_pkgs, repos = CRAN_REPO)
  # Charger tous les packages requis
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(purrr)
  library(readr)
  library(stringr)
  library(forcats)
  library(tibble)
  library(scales)
  library(gridExtra)
})
# Packages optionnels : vérification simple de disponibilité
# vegan pour CA Analyse des Correspondances (Correspondence Analysis / AFC), minpack.lm pour modèle hyperbolique
HAS_VEGAN <- requireNamespace("vegan", quietly = TRUE)
# minpack.lm est nécessaire pour ajuster le modèle hyperbolique de manière robuste (Levenberg-Marquardt)
HAS_MINPACK <- requireNamespace("minpack.lm", quietly = TRUE)
# Log de disponibilité des packages optionnels pour les fonctionnalités avancées (ordination CA, modèle hyperbolique)
SCRIPT_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)

  if (length(file_arg) > 0) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg[1]), mustWork = FALSE)))
  }

  src <- tryCatch(normalizePath(sys.frame(1)$ofile, mustWork = FALSE), error = function(e) NA_character_)
  if (!is.na(src) && nzchar(src)) dirname(src) else getwd()
})
PROJECT_DIR <- dirname(SCRIPT_DIR)

CONFIG <- list(
  input_file = Sys.getenv("INVENTAIRES_INPUT_FILE", unset = "data/observations.csv"),  # Surchargable via env
  output_dir = Sys.getenv("INVENTAIRES_OUTPUT_DIR", unset = "results/ICR"),             # Surchargable via env
  date_format = Sys.getenv("INVENTAIRES_DATE_FORMAT", unset = "%Y-%m-%d"),              # Surchargable via env
  csv_strict_mode = {
    strict_env <- tolower(trimws(Sys.getenv("INVENTAIRES_CSV_STRICT", unset = "TRUE")))
    !(strict_env %in% c("0", "false", "no", "off"))
  },
  csv_allow_extra_cols = {
    extra_env <- tolower(trimws(Sys.getenv("INVENTAIRES_CSV_ALLOW_EXTRA_COLS", unset = "FALSE")))
    !(extra_env %in% c("0", "false", "no", "off"))
  },
  csv_required_cols = c("site", "date", "visite_id", "espece"),
  csv_optional_cols = c("placette"),
  freq_breaks = c(0, 0.10, 0.25, 0.50, 0.75, 1.00),  # Bornes des classes de fréquence (en proportion)
  freq_labels = c("exceptionnelle", "très_rare", "occasionnelle", "fréquente", "constante"),  # Noms des classes
  make_ca = TRUE,                              # Activer l'ordination CA (nécessite vegan)
  min_visits_for_model = 5,                   # Nombre minimum de visites pour ajuster les modèles
  width = 10,                                  # Largeur des graphiques exportés (en pouces)
  height = 6,                                  # Hauteur des graphiques exportés (en pouces)
  dpi = 300                                    # Résolution des PNG exportés (points par pouce)
)

# Crée un répertoire (et ses parents) s'il n'existe pas encore
ensure_dir <- function(path) {
  if (!dir.exists(path)) dir.create(path, recursive = TRUE, showWarnings = FALSE)
}

# Supprime strictement tout fichier Rplots.pdf parasite généré automatiquement par R.
# N'agit que si le fichier a été créé ou modifié pendant l'exécution en cours.
cleanup_new_rplots_pdf <- function(existed_before = FALSE, mtime_before = as.POSIXct(NA), context = "") {
  rplots_path <- file.path(getwd(), "Rplots.pdf")
  if (!file.exists(rplots_path)) return(invisible(NULL))

  # Ne déplacer que les fichiers créés/actualisés pendant l'exécution en cours
  if (isTRUE(existed_before)) {
    mtime_now <- file.info(rplots_path)$mtime
    if (!is.na(mtime_before) && !is.na(mtime_now) && mtime_now <= mtime_before) {
      return(invisible(NULL))
    }
  }

  removed <- isTRUE(file.remove(rplots_path))
  if (isTRUE(removed)) {
    log_info("Rplots.pdf parasite supprimé%s", ifelse(nzchar(context), paste0(" (", context, ")"), ""))
  } else {
    log_warning("Impossible de supprimer Rplots.pdf parasite%s", ifelse(nzchar(context), paste0(" (", context, ")"), ""))
  }

  invisible(removed)
}

log_message <- function(level, ...) {
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  cat(sprintf("[%s] [%s] %s\n", timestamp, level, sprintf(...)))
}
# Fonctions de log spécifiques pour différents niveaux de verbosité (Info, Debug, Warning)
log_info <- function(...) log_message("INFO", ...)

log_debug <- function(...) log_message("DEBUG", ...)

log_warning <- function(...) warning(sprintf(...), call. = FALSE)

log_file_status <- function(path, optional = FALSE) {
  exists_now <- file.exists(path)
  status <- if (exists_now) {
    "OK"
  } else if (isTRUE(optional)) {
    "OPTIONNEL_NON_GENERE"
  } else {
    "MANQUANT"
  }
  log_info("[MANIFEST] %-22s %s", status, path)
}

log_output_manifest <- function(output_dir, site_names = character(0), config = CONFIG) {
  log_info("================ MANIFESTE DES SORTIES ================")

  log_info("[MANIFEST] Section globale")
  global_required <- c(
    "ICR_00_csv_conformite_report.csv",
    "ICR_donnees_preparees.csv",
    "ICR_resume_tous_sites.csv",
    "ICR_metrics_pertinence_tous_sites.csv",
    "ICR_comparaison_completude_sites.png",
    "ICR_comparaison_ir_sites.png",
    "ICR_metrics_pertinence_heatmap_sites.png",
    "ICR_metrics_pertinence_score_sites.png"
  )
  global_optional <- c(
    "ICR_00_csv_conformite_problems.csv"
  )
  for (fname in global_required) {
    log_file_status(file.path(output_dir, fname), optional = FALSE)
  }
  for (fname in global_optional) {
    log_file_status(file.path(output_dir, fname), optional = TRUE)
  }

  if (length(site_names) == 0) {
    log_info("[MANIFEST] Aucun site a journaliser.")
    log_info("========================================================")
    return(invisible(NULL))
  }

  log_info("[MANIFEST] Section par site")
  for (site_name in site_names) {
    site_slug <- sanitize_filename(site_name)
    site_dir <- file.path(output_dir, site_slug)

    log_info("[MANIFEST] Site : %s", site_name)

    site_required <- c(
      "ICR_01_courbe_temps_especes.csv",
      "ICR_02_tee_ir.csv",
      "ICR_03_frequence_especes.csv",
      "ICR_04_resume_site.csv",
      "ICR_07_metrics_pertinence.csv",
      "ICR_01_richesse_par_visite_et_cumul.png",
      "ICR_02_courbe_temps_especes_hyperbole.png",
      "ICR_03_tee_ir.png",
      "ICR_04_histogramme_frequences.png",
      "ICR_07_metrics_pertinence_dashboard.png"
    )

    site_optional <- c(
      "ICR_05_modeles.csv",
      "ICR_06_occupation_spatiale.csv",
      "ICR_05_temporel_vs_spatial.png"
    )

    if (isTRUE(config$make_ca)) {
      site_optional <- c(site_optional, "ICR_06_CA_placettes_especes.png")
    }

    for (fname in site_required) {
      log_file_status(file.path(site_dir, fname), optional = FALSE)
    }
    for (fname in site_optional) {
      log_file_status(file.path(site_dir, fname), optional = TRUE)
    }
  }

  log_info("========================================================")
  invisible(NULL)
}

print_startup_header <- function(config = CONFIG) {
  sep <- strrep("=", 80)
  sub_sep <- strrep("-", 80)

  cat("\n", sep, "\n", sep = "")
  cat("INVENTAIRES FONGIQUES - COMPLETUDE & REPRESENTATIVITE (v1.4)\n")
  cat(sep, "\n", sep = "")
  cat("Objectif : automatiser l'analyse de complétude et de représentativité des inventaires mycologiques\n")
  cat(sub_sep, "\n", sep = "")
  cat(sprintf("Entrée configurée : %s\n", config$input_file))
  cat(sprintf("Sortie configurée : %s\n", config$output_dir))
  cat(sprintf("Format de date   : %s\n", config$date_format))
  cat("Visite distincte : date + visite_id (et site en multi-sites)\n")
  cat(sub_sep, "\n", sep = "")
  cat("Calculs qui seront exécutés (et sorties associées) :\n")
  cat("  1) Préparation/validation des données\n")
  cat("     -> Global CSV : ICR_00_csv_conformite_report.csv\n")
  cat("     -> Global CSV : ICR_00_csv_conformite_problems.csv (si anomalies parsing)\n")
  cat("     -> Global CSV : ICR_donnees_preparees.csv\n")
  cat("  2) Richesse observée et cumulée (courbe temps-espèces)\n")
  cat("     -> Site CSV   : <site>/ICR_01_courbe_temps_especes.csv\n")
  cat("     -> Site PNG   : <site>/ICR_01_richesse_par_visite_et_cumul.png\n")
  cat("  3) Ajustements linéaire/hyperbolique (si conditions remplies)\n")
  cat("     -> Site CSV   : <site>/ICR_05_modeles.csv\n")
  cat("     -> Site PNG   : <site>/ICR_02_courbe_temps_especes_hyperbole.png\n")
  cat("  4) Asymptote hyperbolique et ratio de complétude\n")
  cat("     -> Site CSV   : <site>/ICR_04_resume_site.csv\n")
  cat("     -> Global CSV : ICR_resume_tous_sites.csv\n")
  cat("     -> Global PNG : ICR_comparaison_completude_sites.png\n")
  cat("  5) TEE (taux d'espèces exceptionnelles) et indice Ir\n")
  cat("     -> Site CSV   : <site>/ICR_02_tee_ir.csv\n")
  cat("     -> Site PNG   : <site>/ICR_03_tee_ir.png\n")
  cat("     -> Global PNG : ICR_comparaison_ir_sites.png\n")
  cat("  6) Fréquences d'occurrence des espèces\n")
  cat("     -> Site CSV   : <site>/ICR_03_frequence_especes.csv\n")
  cat("     -> Site PNG   : <site>/ICR_04_histogramme_frequences.png\n")
  cat("  7) Occupation spatiale (si placette disponible)\n")
  cat("     -> Site CSV   : <site>/ICR_06_occupation_spatiale.csv\n")
  cat("     -> Site PNG   : <site>/ICR_05_temporel_vs_spatial.png\n")
  cat("  8) CA/AFC placettes-espèces (si vegan et données adaptées)\n")
  cat("     -> Site PNG   : <site>/ICR_06_CA_placettes_especes.png\n")
  cat("  9) Métriques de pertinence scientifique (stabilité, robustesse, cohérence)\n")
  cat("     -> Site CSV   : <site>/ICR_07_metrics_pertinence.csv\n")
  cat("     -> Global CSV : ICR_metrics_pertinence_tous_sites.csv\n")
  cat("     -> Site PNG   : <site>/ICR_07_metrics_pertinence_dashboard.png\n")
  cat("     -> Global PNG : ICR_metrics_pertinence_heatmap_sites.png\n")
  cat("     -> Global PNG : ICR_metrics_pertinence_score_sites.png\n")
  cat(sub_sep, "\n", sep = "")
  cat("Sorties graphiques attendues :\n")
  cat("  Par site :\n")
  cat("    - ICR_01_richesse_par_visite_et_cumul.png\n")
  cat("    - ICR_02_courbe_temps_especes_hyperbole.png\n")
  cat("    - ICR_03_tee_ir.png\n")
  cat("    - ICR_04_histogramme_frequences.png\n")
  cat("    - ICR_05_temporel_vs_spatial.png (si données spatiales)\n")
  cat("    - ICR_06_CA_placettes_especes.png (si CA disponible)\n")
  cat("    - ICR_07_metrics_pertinence_dashboard.png\n")
  cat("  Global :\n")
  cat("    - ICR_comparaison_completude_sites.png\n")
  cat("    - ICR_comparaison_ir_sites.png\n")
  cat("    - ICR_metrics_pertinence_heatmap_sites.png\n")
  cat("    - ICR_metrics_pertinence_score_sites.png\n")
  cat("Sorties CSV attendues :\n")
  cat("  Par site :\n")
  cat("    - ICR_01_courbe_temps_especes.csv\n")
  cat("    - ICR_02_tee_ir.csv\n")
  cat("    - ICR_03_frequence_especes.csv\n")
  cat("    - ICR_04_resume_site.csv\n")
  cat("    - ICR_05_modeles.csv (si modèle ajusté)\n")
  cat("    - ICR_06_occupation_spatiale.csv (si placette)\n")
  cat("    - ICR_07_metrics_pertinence.csv\n")
  cat("  Global :\n")
  cat("    - ICR_00_csv_conformite_report.csv\n")
  cat("    - ICR_00_csv_conformite_problems.csv (si anomalies parsing)\n")
  cat("    - ICR_donnees_preparees.csv\n")
  cat("    - ICR_resume_tous_sites.csv\n")
  cat("    - ICR_metrics_pertinence_tous_sites.csv\n")
  cat(sep, "\n\n", sep = "")
}

# Formate un nombre en chaîne fixe (digits décimales), renvoie "NA" si manquant
fmt_num <- function(x, digits = 4) {
  ifelse(is.na(x), "NA", formatC(x, format = "f", digits = digits))
}

# Benchmark helper : mesure temps exécution (en secondes avec precision ms)
bench_time <- function(expr, label = "") {
  t_start <- Sys.time()
  result <- force(expr)
  t_elapsed <- as.numeric(difftime(Sys.time(), t_start, units = "sec"))
  if (nzchar(label)) {
    log_info("BENCHMARK '%s' : %.3f sec", label, t_elapsed)
  }
  list(result = result, elapsed = t_elapsed)
}

log_table_result <- function(label, tbl, preview_cols = NULL, max_preview = 3) {
  if (is.null(tbl)) {
    log_info("Resultat '%s' : NULL", label)
    return(invisible(NULL))
  }

  log_info("Resultat '%s' genere : %d ligne(s), %d colonne(s).", label, nrow(tbl), ncol(tbl))
  log_debug("Resultat '%s' colonnes : %s", label, paste(names(tbl), collapse = ", "))

  if (!is.null(preview_cols) && nrow(tbl) > 0) {
    cols <- intersect(preview_cols, names(tbl))
    if (length(cols) > 0) {
      preview_tbl <- utils::head(tbl[, cols, drop = FALSE], max_preview)
      preview_txt <- paste(apply(preview_tbl, 1, function(row) paste(paste(names(row), row, sep = "="), collapse = " | ")), collapse = " || ")
      log_debug("Resultat '%s' apercu : %s", label, preview_txt)
    }
  }
}

log_model_result <- function(site_name, model_stats) {
  if (is.null(model_stats) || nrow(model_stats) == 0) {
    log_info("Resultat modeles pour site '%s' : aucun modele exporte.", site_name)
    return(invisible(NULL))
  }

  apply(model_stats, 1, function(row) {
    log_info(
      "Resultat modele site '%s' : modele=%s | r2=%s | asymptote_y=%s | asymptote_x=%s",
      site_name,
      row[["modele"]],
      fmt_num(as.numeric(row[["r2"]])),
      fmt_num(as.numeric(row[["asymptote_y"]])),
      fmt_num(as.numeric(row[["asymptote_x"]]))
    )
    log_debug("Equation modele site '%s' (%s) : %s", site_name, row[["modele"]], row[["equation"]])
  })
}

validate_config <- function(config = CONFIG) {
  log_info("Validation de la configuration ...")
  required_names <- c(
    "input_file", "output_dir", "date_format",
    "csv_strict_mode", "csv_allow_extra_cols", "csv_required_cols", "csv_optional_cols",
    "freq_breaks", "freq_labels",
    "make_ca", "min_visits_for_model", "width", "height", "dpi"
  )
  missing_names <- setdiff(required_names, names(config))
  if (length(missing_names) > 0) {
    stop("Configuration incomplete. Parametres manquants : ", paste(missing_names, collapse = ", "))
  }

  if (!is.character(config$input_file) || length(config$input_file) != 1 || !nzchar(config$input_file)) {
    stop("CONFIG$input_file doit etre une chaine non vide.")
  }
  if (!is.character(config$output_dir) || length(config$output_dir) != 1 || !nzchar(config$output_dir)) {
    stop("CONFIG$output_dir doit etre une chaine non vide.")
  }
  if (!is.character(config$date_format) || length(config$date_format) != 1 || !nzchar(config$date_format)) {
    stop("CONFIG$date_format doit etre une chaine non vide.")
  }
  if (!is.logical(config$csv_strict_mode) || length(config$csv_strict_mode) != 1 || is.na(config$csv_strict_mode)) {
    stop("CONFIG$csv_strict_mode doit etre un booleen.")
  }
  if (!is.logical(config$csv_allow_extra_cols) || length(config$csv_allow_extra_cols) != 1 || is.na(config$csv_allow_extra_cols)) {
    stop("CONFIG$csv_allow_extra_cols doit etre un booleen.")
  }
  if (!is.character(config$csv_required_cols) || length(config$csv_required_cols) == 0) {
    stop("CONFIG$csv_required_cols doit etre un vecteur de noms de colonnes.")
  }
  if (!is.character(config$csv_optional_cols)) {
    stop("CONFIG$csv_optional_cols doit etre un vecteur de noms de colonnes (peut etre vide).")
  }
  if (length(intersect(config$csv_required_cols, config$csv_optional_cols)) > 0) {
    stop("CONFIG$csv_required_cols et CONFIG$csv_optional_cols ne doivent pas se chevaucher.")
  }
  if (!is.numeric(config$freq_breaks) || length(config$freq_breaks) < 2) {
    stop("CONFIG$freq_breaks doit contenir au moins deux valeurs numeriques.")
  }
  if (is.unsorted(config$freq_breaks, strictly = TRUE)) {
    stop("CONFIG$freq_breaks doit etre strictement croissant.")
  }
  if (min(config$freq_breaks) > 0 || max(config$freq_breaks) < 1) {
    stop("CONFIG$freq_breaks doit couvrir l'intervalle [0, 1].")
  }
  if (!is.character(config$freq_labels) || length(config$freq_labels) != (length(config$freq_breaks) - 1)) {
    stop("CONFIG$freq_labels doit contenir exactement length(CONFIG$freq_breaks) - 1 libelles.")
  }
  if (!is.logical(config$make_ca) || length(config$make_ca) != 1 || is.na(config$make_ca)) {
    stop("CONFIG$make_ca doit etre un booleen.")
  }
  if (!is.numeric(config$min_visits_for_model) || length(config$min_visits_for_model) != 1 || config$min_visits_for_model < 2) {
    stop("CONFIG$min_visits_for_model doit etre un nombre >= 2.")
  }
  if (!is.numeric(config$width) || !is.numeric(config$height) || !is.numeric(config$dpi)) {
    stop("CONFIG$width, CONFIG$height et CONFIG$dpi doivent etre numeriques.")
  }

  log_info(
    "Configuration validee : input='%s', output='%s', format_date='%s', csv_strict=%s, extra_cols=%s, seuil_modeles=%d, CA=%s",
    config$input_file,
    config$output_dir,
    config$date_format,
    ifelse(isTRUE(config$csv_strict_mode), "TRUE", "FALSE"),
    ifelse(isTRUE(config$csv_allow_extra_cols), "TRUE", "FALSE"),
    config$min_visits_for_model,
    ifelse(isTRUE(config$make_ca), "activee", "desactivee")
  )
}

build_csv_colspec <- function(config = CONFIG) {
  cols_spec <- purrr::set_names(
    rep(list(readr::col_character()), length(unique(c(config$csv_required_cols, config$csv_optional_cols)))),
    unique(c(config$csv_required_cols, config$csv_optional_cols))
  )
  do.call(readr::cols, c(cols_spec, list(.default = readr::col_character())))
}

audit_csv_conformity <- function(df_raw, parse_problems = tibble::tibble(), path = "", delim = ",", config = CONFIG) {
  required <- unique(config$csv_required_cols)
  optional <- unique(config$csv_optional_cols)
  allowed <- unique(c(required, optional))
  cols <- names(df_raw)

  missing_required <- setdiff(required, cols)
  extra_cols <- setdiff(cols, allowed)

  parse_problem_count <- nrow(parse_problems)
  required_ok <- length(missing_required) == 0
  extra_ok <- isTRUE(config$csv_allow_extra_cols) || length(extra_cols) == 0
  parse_ok <- parse_problem_count == 0
  is_conform <- required_ok && extra_ok && parse_ok

  report_tbl <- tibble::tibble(
    horodatage = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    fichier = normalizePath(path, mustWork = FALSE),
    delimiteur = switch(delim, "\t" = "TAB", ";" = "SEMICOLON", "," = "COMMA", delim),
    nb_lignes = nrow(df_raw),
    nb_colonnes = ncol(df_raw),
    csv_strict_mode = isTRUE(config$csv_strict_mode),
    colonnes_requises = paste(required, collapse = ","),
    colonnes_optionnelles = paste(optional, collapse = ","),
    colonnes_lues = paste(cols, collapse = ","),
    colonnes_manquantes = ifelse(length(missing_required) == 0, "", paste(missing_required, collapse = ",")),
    colonnes_supplementaires = ifelse(length(extra_cols) == 0, "", paste(extra_cols, collapse = ",")),
    nb_problemes_parse = parse_problem_count,
    statut = ifelse(is_conform, "CONFORME", "NON_CONFORME")
  )

  list(
    report = report_tbl,
    problems = parse_problems,
    is_conform = is_conform,
    missing_required = missing_required,
    extra_cols = extra_cols,
    parse_problem_count = parse_problem_count
  )
}

export_csv_conformity_report <- function(audit, output_dir) {
  report_path <- file.path(output_dir, "ICR_00_csv_conformite_report.csv")
  tryCatch(
    readr::write_csv(audit$report, report_path),
    error = function(e) stop("Echec d'ecriture de ICR_00_csv_conformite_report.csv : ", conditionMessage(e), call. = FALSE)
  )
  log_info("Rapport de conformité CSV exporté : %s", report_path)

  if (!is.null(audit$problems) && nrow(audit$problems) > 0) {
    problems_path <- file.path(output_dir, "ICR_00_csv_conformite_problems.csv")
    tryCatch(
      readr::write_csv(audit$problems, problems_path),
      error = function(e) stop("Echec d'ecriture de ICR_00_csv_conformite_problems.csv : ", conditionMessage(e), call. = FALSE)
    )
    log_info("Détails des problèmes CSV exportés : %s", problems_path)
  }

  invisible(report_path)
}

read_delim_auto <- function(path, config = CONFIG) {
  # Détection automatique du délimiteur (CSV, CSV2, TSV, tab)
  first_line <- readLines(path, n = 1, warn = FALSE)
  
  # Compter les occurrences de délimiteurs courants
  n_tab <- stringr::str_count(first_line, "\t")
  n_semi <- stringr::str_count(first_line, ";")
  n_comma <- stringr::str_count(first_line, ",")
  
  # Déterminer le meilleur délimiteur
  delim <- case_when(
    n_tab >= max(n_semi, n_comma) && n_tab > 0 ~ "\t",
    n_semi > n_comma ~ ";",
    n_comma > 0 ~ ",",
    TRUE ~ ","  # Défaut
  )
  
  log_info("Lecture du fichier '%s' (délimiteur détecté : '%s').", 
           path, 
           switch(delim, "\t" = "TAB", ";" = "SEMICOLON", "," = "COMMA", delim))

  df_raw <- readr::read_delim(
    path, 
    delim = delim, 
    col_types = build_csv_colspec(config),
    show_col_types = FALSE, 
    locale = readr::locale(encoding = "UTF-8")
  )

  parse_problems <- readr::problems(df_raw)
  list(data = df_raw, delim = delim, problems = parse_problems)
}

# Nettoie une chaîne pour en faire un nom de fichier valide (remplace les caractères spéciaux par "_")
sanitize_filename <- function(x) {
  x |>
    stringr::str_replace_all("[^[:alnum:]_\\-]+", "_") |>
    stringr::str_replace_all("_+", "_") |>
    stringr::str_replace_all("^_|_$", "")
}

# Division sécurisée : renvoie NA si le dénominateur est nul (évite les NaN)
safe_prop <- function(num, den) ifelse(den == 0, NA_real_, num / den)

# Compte le nombre de visites distinctes dans un data frame (clé : date + visite_id, + site si présent)
count_distinct_visits <- function(df) {
  visit_keys <- c("date", "visite_id")
  if ("site" %in% names(df)) {
    visit_keys <- c("site", visit_keys)
  }
  df |>
    dplyr::distinct(dplyr::across(dplyr::all_of(visit_keys))) |>
    nrow()
}

# Résout un chemin relatif par rapport au répertoire projet ; les chemins absolus sont retournés tels quels
resolve_path <- function(path, base_dir = PROJECT_DIR) {
  if (grepl("^(~|/|[A-Za-z]:)", path)) {
    return(path.expand(path))
  }
  normalizePath(file.path(base_dir, path), mustWork = FALSE)
}

resolve_input_file <- function(config = CONFIG) {
  configured <- resolve_path(config$input_file)
  log_debug("Resolution du fichier d'entree configure : %s", configured)
  if (file.exists(configured)) {
    log_info("Fichier d'entree retenu : %s", configured)
    return(configured)
  }

  data_dir <- resolve_path("data")
  obs_candidates <- character(0)

  if (dir.exists(data_dir)) {
    obs_candidates <- list.files(
      data_dir,
      pattern = "^observations\\.(csv|txt|tsv)$",
      ignore.case = TRUE,
      full.names = TRUE
    )
  }

  if (length(obs_candidates) > 0) {
    auto_file <- obs_candidates[1]
    log_info(
      "Info : '%s' introuvable. Utilisation automatique de '%s'.",
      config$input_file,
      auto_file
    )
    return(auto_file)
  }

  stop(
    "Fichier introuvable : ", configured,
    "\nAjoute un fichier 'observations.csv' (ou 'observations.txt'/'observations.tsv') dans : ", data_dir,
    "\nColonnes obligatoires : site,date,visite_id,espece"
  )
}

prepare_data <- function(df, config = CONFIG) {
  log_info("Prep. données brutes : %d lignes, %d colonnes.", nrow(df), ncol(df))
  
  # 1. Vérifier les colonnes obligatoires
  required <- c("site", "date", "visite_id", "espece")
  missing_cols <- setdiff(required, names(df))
  if (length(missing_cols) > 0) {
    stop("Colonnes obligatoires manquantes : ", paste(missing_cols, collapse = ", "))
  }

  # 2. Convertir les types et nettoyer
  df <- df |>
    dplyr::mutate(
      site = stringr::str_trim(as.character(site)),
      visite_id = stringr::str_trim(as.character(visite_id)),
      espece = stringr::str_squish(as.character(espece)),
      date = as.Date(date, format = config$date_format)
    )

  # 3. Valider les colonnes essentielles
  if (anyNA(df$site) || any(df$site == "")) {
    stop("Colonne 'site' : au moins une valeur vide/manquante détectée.")
  }
  if (anyNA(df$visite_id) || any(df$visite_id == "")) {
    stop("Colonne 'visite_id' : au moins une valeur vide/manquante détectée.")
  }
  if (anyNA(df$espece) || any(df$espece == "")) {
    stop("Colonne 'espece' : au moins une valeur vide/manquante détectée après nettoyage.")
  }
  if (any(is.na(df$date))) {
    invalid_dates <- sum(is.na(df$date))
    stop("Colonne 'date' : ", invalid_dates, " date(s) non parsée(s). ",
         "Vérifiez CONFIG$date_format et le format des dates.")
  }

  # 4. Ajouter placette (optionnel)
  if ("placette" %in% names(df)) {
    df <- df |> dplyr::mutate(placette = as.character(placette))
  } else {
    df <- df |> dplyr::mutate(placette = NA_character_)
  }

  # 5. Déduplication : garder les lignes distinctes
  n_before <- nrow(df)
  df_prepared <- df |>
    dplyr::distinct(site, placette, date, visite_id, espece, .keep_all = TRUE) |>
    dplyr::arrange(site, date, visite_id, espece)
  n_after <- nrow(df_prepared)
  
  if (n_before > n_after) {
    log_info("Déduplication : %d ligne(s) doublée(s) supprimée(s).", n_before - n_after)
  }

  # 6. Log synthétique
  log_info(
    "Données prep. : %d lignes, %d site(s), %d visite(s), %d espèce(s).",
    nrow(df_prepared),
    dplyr::n_distinct(df_prepared$site),
    count_distinct_visits(df_prepared),
    dplyr::n_distinct(df_prepared$espece)
  )
  df_prepared
}

# Calcule la richesse cumulée et le nombre de nouvelles espèces par visite (dans l'ordre chronologique).
# Renvoie un tibble avec une ligne par visite : visite_index, nb_especes_trouvees, nb_nouvelles, nb_cumule.
calc_cumulative_metrics <- function(df_site) {
  visits_tbl <- df_site |>
    dplyr::distinct(visite_id, date) |>
    dplyr::arrange(date, visite_id) |>
    dplyr::mutate(visite_index = dplyr::row_number())

  log_debug(
    "Calcul cumulatif pour site '%s' : %d visites distinctes.",
    unique(df_site$site)[1],
    nrow(visits_tbl)
  )
  
  # Table visite-espèce (chaque couple une seule fois)
  visit_spp <- df_site |>
    dplyr::distinct(date, visite_id, espece)
  
  # Compter espèces par visite
  spp_per_visit <- visit_spp |>
    dplyr::group_by(visite_id) |>
    dplyr::count(name = "nb_especes_trouvees") |>
    dplyr::ungroup()
  
  # Joindre pour récupérer l'index visite
  visit_spp_with_idx <- visit_spp |>
    dplyr::left_join(visits_tbl |> dplyr::select(date, visite_id, visite_index), by = c("date", "visite_id"), relationship = "many-to-one") |>
    dplyr::arrange(visite_index)
  
  # Calculer espèces vues jusqu'à chaque visite (cumul)
  out_list <- vector("list", nrow(visits_tbl))
  seen_all <- character(0)
  
  for (i in seq_len(nrow(visits_tbl))) {
    v_id <- visits_tbl$visite_id[i]
    spp_this_visit <- visit_spp_with_idx |>
      dplyr::filter(visite_index == i) |>
      dplyr::pull(espece)
    
    new_spp <- setdiff(spp_this_visit, seen_all)
    seen_all <- union(seen_all, spp_this_visit)
    
    nb_spp_this <- length(spp_this_visit)
    
    out_list[[i]] <- tibble::tibble(
      visite_index = i,
      visite_id = v_id,
      date = visits_tbl$date[i],
      nb_especes_trouvees = nb_spp_this,
      nb_nouvelles = length(new_spp),
      nb_cumule = length(seen_all)
    )
  }
  
  out_tbl <- dplyr::bind_rows(out_list)
  log_debug(
    "Cumul terminé pour site '%s' : %d lignes, richesse finale=%d.",
    unique(df_site$site)[1],
    nrow(out_tbl),
    max(out_tbl$nb_cumule, na.rm = TRUE)
  )
  out_tbl
}

calc_tee_ir <- function(df_site) {
  visits_tbl <- df_site |>
    dplyr::distinct(visite_id, date) |>
    dplyr::arrange(date, visite_id) |>
    dplyr::mutate(visite_index = dplyr::row_number())

  log_debug(
    "Calcul TEE/Ir pour site '%s' : %d visites distinctes.",
    unique(df_site$site)[1],
    nrow(visits_tbl)
  )

  # Table visite-espèce unique
  visit_spp <- df_site |>
    dplyr::distinct(date, visite_id, espece) |>
    dplyr::left_join(visits_tbl |> dplyr::select(date, visite_id, visite_index), by = c("date", "visite_id"), relationship = "many-to-one")

  # Pré-calculer pour chaque visite : espèces vues jusqu'à (et compris) cette visite
  out_list <- vector("list", nrow(visits_tbl))
  seen_all <- character(0)

  for (i in seq_len(nrow(visits_tbl))) {
    v_id <- visits_tbl$visite_id[i]
    
    # Espèces vues jusqu'à visite i (incluse)
    spp_up_to_i <- visit_spp |>
      dplyr::filter(visite_index <= i) |>
      dplyr::pull(espece) |>
      unique()
    
    # Compter fréquence (nombre de visites distinctes où espèce appar)
    freq <- visit_spp |>
      dplyr::filter(visite_index <= i) |>
      dplyr::distinct(date, visite_id, espece) |>
      dplyr::count(espece, name = "freq")
    
    s_total <- nrow(freq)
    s1 <- sum(freq$freq == 1)
    tee <- safe_prop(s1, s_total)
    ir <- ifelse(is.na(tee), NA_real_, 1 - tee)

    out_list[[i]] <- tibble::tibble(
      visite_index = i,
      visite_id = v_id,
      date = visits_tbl$date[i],
      nb_total = s_total,
      nb_esp_1fois = s1,
      TEE = tee,
      Ir = ir
    )
  }

  out_tbl <- dplyr::bind_rows(out_list)
  log_debug(
    "TEE/Ir terminés pour site '%s' : TEE final=%.4f, Ir final=%.4f.",
    unique(df_site$site)[1],
    dplyr::last(out_tbl$TEE),
    dplyr::last(out_tbl$Ir)
  )
  out_tbl
}

fit_linear_model <- function(df_cum) {
  log_debug("Ajustement du modele lineaire sur %d points.", nrow(df_cum))
  stats::lm(nb_cumule ~ visite_index, data = df_cum)
}

# Ajuste un modèle hyperbolique sur la courbe cumulée.
# Équation : S(t) = a - 1 / (b*t + c)
#   a = asymptote (richesse théorique maximale)
#   b, c = paramètres de courbure
# Requiert minpack.lm pour la minimisation non-linéaire robuste (Levenberg-Marquardt).
fit_hyperbolic_model <- function(df_cum) {
  if (!HAS_MINPACK) {
    stop("Le package optionnel 'minpack.lm' est requis pour le modèle hyperbolique.")
  }
  log_debug("Ajustement du modele hyperbolique sur %d points.", nrow(df_cum))
  minpack.lm::nlsLM(
    nb_cumule ~ a - 1 / (b * visite_index + c),
    data = df_cum,
    start = list(
      a = max(df_cum$nb_cumule, na.rm = TRUE) * 1.20,
      b = 1e-4,
      c = 1e-3
    ),
    control = minpack.lm::nls.lm.control(maxiter = 500)
  )
}

extract_model_stats <- function(fit, model_type, df) {
  pred <- stats::predict(fit, newdata = df)
  ss_res <- sum((df$nb_cumule - pred)^2, na.rm = TRUE)
  ss_tot <- sum((df$nb_cumule - mean(df$nb_cumule, na.rm = TRUE))^2, na.rm = TRUE)
  r2 <- 1 - ss_res / ss_tot

  if (model_type == "lineaire") {
    co <- stats::coef(fit)
    tibble::tibble(
      modele = model_type,
      equation = sprintf("y = %.6f*x + %.6f", unname(co[2]), unname(co[1])),
      r2 = r2,
      asymptote_y = NA_real_,
      asymptote_x = NA_real_
    )
  } else {
    co <- stats::coef(fit)
    a <- unname(co["a"]); b <- unname(co["b"]); c <- unname(co["c"])
    tibble::tibble(
      modele = model_type,
      equation = sprintf("y = %.6f - 1/(%.8f*x + %.8f)", a, b, c),
      r2 = r2,
      asymptote_y = a,
      asymptote_x = -c / b
    )
  }
}

predict_hyper_df <- function(fit, max_x) {
  newdata <- tibble::tibble(visite_index = seq_len(max_x))
  newdata$pred <- as.numeric(stats::predict(fit, newdata = newdata))
  newdata
}

calc_species_frequency <- function(df_site, config = CONFIG) {
  n_visits <- count_distinct_visits(df_site)
  log_debug(
    "Calcul des frequences pour site '%s' : %d visites, %d especes.",
    unique(df_site$site)[1],
    n_visits,
    dplyr::n_distinct(df_site$espece)
  )

  out_tbl <- df_site |>
    dplyr::distinct(visite_id, espece) |>
    dplyr::count(espece, name = "nb_visites") |>
    dplyr::mutate(
      prop_visites = nb_visites / n_visits,
      classe_frequence = cut(
        prop_visites,
        breaks = config$freq_breaks,
        labels = config$freq_labels,
        include.lowest = TRUE,
        right = TRUE
      )
    ) |>
    dplyr::arrange(dplyr::desc(nb_visites), espece)

  log_debug("Frequences calculees pour site '%s' : %d lignes.", unique(df_site$site)[1], nrow(out_tbl))
  out_tbl
}

calc_scientific_metrics <- function(df_cum, df_tee, freq_tbl, occ_tbl = NULL, model_stats = NULL,
                                    completude = NA_real_, site_name = NA_character_, terminal_k = 5) {
  n_visites <- nrow(df_cum)
  # Taille de la fenêtre terminale : les k dernières visites servent à évaluer
  # la stabilisation de la courbe (pente faible = inventaire qui se ferme)
  k <- min(terminal_k, n_visites)
  tail_idx <- if (k > 0) seq.int(n_visites - k + 1, n_visites) else integer(0)

  # Pente linéaire estimée sur la fenêtre terminale de la courbe cumulée :
  # proche de 0 indique que peu de nouvelles espèces sont découvertes à la fin
  slope_terminal <- if (k >= 2) {
    as.numeric(stats::coef(stats::lm(nb_cumule ~ visite_index, data = df_cum[tail_idx, , drop = FALSE]))["visite_index"])
  } else {
    NA_real_
  }

  sum_new_total <- sum(df_cum$nb_nouvelles, na.rm = TRUE)
  sum_new_tail <- if (k > 0) sum(df_cum$nb_nouvelles[tail_idx], na.rm = TRUE) else NA_real_
  # Part des nouvelles espèces sur la fenêtre terminale vs. l'ensemble :
  # une valeur faible indique que les dernières visites n'apportent plus grand-chose
  tail_novelty_share <- if (!is.na(sum_new_tail) && sum_new_total > 0) sum_new_tail / sum_new_total else NA_real_

  tee_final <- dplyr::last(df_tee$TEE)
  ir_final <- dplyr::last(df_tee$Ir)

  r2_linear <- NA_real_
  r2_hyper <- NA_real_
  if (!is.null(model_stats) && nrow(model_stats) > 0) {
    if ("lineaire" %in% model_stats$modele) {
      r2_linear <- as.numeric(model_stats$r2[model_stats$modele == "lineaire"][1])
    }
    if ("hyperbolique" %in% model_stats$modele) {
      r2_hyper <- as.numeric(model_stats$r2[model_stats$modele == "hyperbolique"][1])
    }
  }

  # Cohérence temporel/spatial
  spearman_temporal_spatial <- NA_real_
  discordance_rate <- NA_real_
  if (!is.null(occ_tbl) && nrow(occ_tbl) > 0) {
    joined <- dplyr::inner_join(freq_tbl, occ_tbl, by = "espece")
    if (nrow(joined) >= 3) {
      spearman_temporal_spatial <- suppressWarnings(stats::cor(joined$prop_visites, joined$prop_placettes, method = "spearman"))
      discordance_rate <- mean(abs(joined$prop_visites - joined$prop_placettes) > 0.50, na.rm = TRUE)
    }
  }

  # Score synthétique pondéré (entre 0 et 1) agrégeant :
  #   - Ir final          (poids 35%) : représentativité floristique
  #   - Complétude        (poids 35%) : rapport richesse observée / asymptote
  #   - Stabilité finale  (poids 20%) : 1 - part des nouvelles espèces en fin d'inventaire
  #   - R² modèle         (poids 10%) : qualité d'ajustement hyperbolique (ou linéaire à défaut)
  # Les composantes manquantes sont exclues du calcul et les poids renormalisés.
  r2_for_score <- ifelse(!is.na(r2_hyper), r2_hyper, r2_linear)
  comp <- c(
    ir_final,
    completude,
    ifelse(is.na(tail_novelty_share), NA_real_, 1 - tail_novelty_share),
    r2_for_score
  )
  weights <- c(0.35, 0.35, 0.20, 0.10)
  valid <- !is.na(comp)
  score_pertinence <- if (any(valid)) sum(comp[valid] * weights[valid]) / sum(weights[valid]) else NA_real_

  class_ir <- dplyr::case_when(
    is.na(ir_final) ~ NA_character_,
    ir_final < 0.60 ~ "faible",
    ir_final < 0.80 ~ "moyenne",
    TRUE ~ "bonne"
  )

  class_completude <- dplyr::case_when(
    is.na(completude) ~ NA_character_,
    completude < 0.70 ~ "insuffisante",
    completude < 0.90 ~ "intermediaire",
    TRUE ~ "avancee"
  )

  tibble::tibble(
    site = site_name,
    nb_visites = n_visites,
    terminal_window_k = k,
    tee_final = tee_final,
    ir_final = ir_final,
    completude = completude,
    r2_lineaire = r2_linear,
    r2_hyperbolique = r2_hyper,
    slope_terminal_cumul = slope_terminal,
    tail_novelty_share = tail_novelty_share,
    spearman_temporal_spatial = spearman_temporal_spatial,
    discordance_rate = discordance_rate,
    score_pertinence = score_pertinence,
    class_ir = class_ir,
    class_completude = class_completude
  )
}

calc_spatial_occupancy <- function(df_site) {
  if (!("placette" %in% names(df_site)) || all(is.na(df_site$placette))) return(NULL)

  n_placettes <- df_site |>
    dplyr::filter(!is.na(placette), placette != "") |>
    dplyr::distinct(placette) |>
    nrow()

  if (n_placettes == 0) return(NULL)

  log_debug(
    "Calcul de l'occupation spatiale pour site '%s' : %d placettes.",
    unique(df_site$site)[1],
    n_placettes
  )

  out_tbl <- df_site |>
    dplyr::filter(!is.na(placette), placette != "") |>
    dplyr::distinct(placette, espece) |>
    dplyr::count(espece, name = "nb_placettes") |>
    dplyr::mutate(prop_placettes = nb_placettes / n_placettes) |>
    dplyr::arrange(dplyr::desc(nb_placettes), espece)

  log_debug("Occupation spatiale calculee pour site '%s' : %d lignes.", unique(df_site$site)[1], nrow(out_tbl))
  out_tbl
}

# Réalise une Analyse des Correspondances (CA/AFC) sur la matrice placette × espèce.
# Retourne une liste (model, matrix) ou NULL si les conditions ne sont pas remplies.
run_ca <- function(df_site, site_name = NA_character_) {
  if (!HAS_VEGAN) {
    log_info("Info site '%s' : CA ignoree, package 'vegan' absent.", site_name)
    return(NULL)
  }
  if (!("placette" %in% names(df_site)) || all(is.na(df_site$placette))) {
    log_info("Info site '%s' : CA ignoree, aucune placette exploitable.", site_name)
    return(NULL)
  }

  mat <- df_site |>
    dplyr::filter(!is.na(placette), placette != "") |>
    dplyr::distinct(placette, espece) |>
    dplyr::mutate(val = 1L)

  if (nrow(mat) == 0) {
    log_info("Info site '%s' : CA ignoree, matrice placette-espece vide.", site_name)
    return(NULL)
  }

  wide <- mat |>
    tidyr::pivot_wider(names_from = espece, values_from = val, values_fill = 0)

  if (ncol(wide) < 3) {
    log_info("Info site '%s' : CA ignoree, nombre d'especes insuffisant pour l'ordination.", site_name)
    return(NULL)
  }

  rn <- wide$placette
  X <- as.data.frame(wide[, -1, drop = FALSE])
  rownames(X) <- rn
  ca_fit <- vegan::cca(X)
  list(model = ca_fit, matrix = X)
}

# =================================================================================================================================================
# CHARTE GRAPHIQUE UNIFIÉE
# =================================================================================================================================================

# Palette couleurs daltonien-friendly (CVD-friendly)
# Source : https://jfly.uni-koeln.de/color/
PALETTE_PRIMARY <- c(
  blue = "#0072B2",
  orange = "#E69F00",
  green = "#009E73",
  red = "#D55E00",
  purple = "#CC79A7"
)

# Thème unifié pour tous les graphiques
theme_project <- function(base_size = 11, base_family = "sans") {
  ggplot2::theme_minimal(base_size = base_size, base_family = base_family) +
    ggplot2::theme(
      # Polices
      plot.title = ggplot2::element_text(
        size = rel(1.3), face = "bold", margin = ggplot2::margin(b = 10)
      ),
      plot.subtitle = ggplot2::element_text(
        size = rel(1.0), face = "italic", margin = ggplot2::margin(b = 5)
      ),
      axis.title = ggplot2::element_text(size = rel(1.0), face = "bold"),
      axis.text = ggplot2::element_text(size = rel(0.9)),
      strip.text = ggplot2::element_text(size = rel(1.0), face = "bold"),
      legend.title = ggplot2::element_text(size = rel(1.0), face = "bold"),
      legend.text = ggplot2::element_text(size = rel(0.9)),
      
      # Couleurs
      plot.background = ggplot2::element_rect(fill = "white", colour = NA),
      panel.background = ggplot2::element_rect(fill = "#F5F5F5", colour = NA),
      panel.grid.major = ggplot2::element_line(color = "#E0E0E0", linewidth = 0.3),
      panel.grid.minor = ggplot2::element_blank(),
      
      # Axes
      axis.line = ggplot2::element_line(color = "#333333", linewidth = 0.3),
      axis.ticks = ggplot2::element_line(color = "#333333", linewidth = 0.3),
      
      # Légende
      legend.background = ggplot2::element_rect(fill = "white", colour = "#CCCCCC"),
      legend.position = "bottom",
      legend.box = "horizontal",
      legend.margin = ggplot2::margin(t = 10),
      
      # Facettes
      panel.spacing = ggplot2::unit(1, "lines")
    )
}

plot_richness_over_time <- function(df_cum, site_name) {
  ggplot2::ggplot(df_cum, ggplot2::aes(x = visite_index)) +
    ggplot2::geom_col(
      ggplot2::aes(y = nb_especes_trouvees, fill = "Espèces par visite"),
      alpha = 0.7, color = NA
    ) +
    ggplot2::geom_line(
      ggplot2::aes(y = nb_cumule, color = "Cumul espèces"),
      linewidth = 1.1
    ) +
    ggplot2::geom_point(
      ggplot2::aes(y = nb_cumule, color = "Cumul espèces"),
      size = 2.2
    ) +
    ggplot2::scale_fill_manual(
      values = c("Espèces par visite" = PALETTE_PRIMARY[["blue"]])
    ) +
    ggplot2::scale_color_manual(
      values = c("Cumul espèces" = PALETTE_PRIMARY[["orange"]])
    ) +
    ggplot2::labs(
      title = paste("Richesse observée et cumul des espèces —", site_name),
      subtitle = "Visites distinctes définies par : date + visite_id",
      x = "Indice de visite",
      y = "Nombre d'espèces",
      fill = "", color = ""
    ) +
    theme_project() +
    ggplot2::theme(legend.position = "bottom")
}

plot_time_species_curve <- function(df_cum, fit_hyp = NULL, site_name = "") {
  p <- ggplot2::ggplot(df_cum, ggplot2::aes(x = visite_index, y = nb_cumule)) +
    ggplot2::geom_point(size = 2.2, color = PALETTE_PRIMARY["blue"]) +
    ggplot2::geom_line(linewidth = 1.0, color = PALETTE_PRIMARY["blue"]) +
    ggplot2::labs(
      title = paste("Courbe temps-espèces —", site_name),
      subtitle = "Visites distinctes définies par : date + visite_id",
      x = "Visite (rang temporel)",
      y = "Richesse cumulée (nb espèces)"
    ) +
    theme_project()

  if (!is.null(fit_hyp)) {
    pred_df <- predict_hyper_df(fit_hyp, max(df_cum$visite_index))
    a <- unname(stats::coef(fit_hyp)["a"])
    p <- p +
      ggplot2::geom_line(
        data = pred_df,
        ggplot2::aes(x = visite_index, y = pred),
        linetype = "dashed",
        linewidth = 0.9,
        color = PALETTE_PRIMARY["red"],
        inherit.aes = FALSE
      ) +
      ggplot2::geom_hline(
        yintercept = a,
        linetype = "dotted",
        linewidth = 0.8,
        color = PALETTE_PRIMARY["red"]
      ) +
      ggplot2::annotate(
        "text",
        x = max(df_cum$visite_index) * 0.95,
        y = a * 1.05,
        label = sprintf("Asymptote = %.0f espèces", a),
        hjust = 1,
        vjust = 0,
        size = 3.5,
        fontface = "italic"
      )
  }
  p
}

plot_tee_ir <- function(df_tee, site_name) {
  # Préparer données pour deux panneaux : (1) Espèces uniques, (2) Indice Ir
  
  # Panneau 1 : Espèces vues une seule fois (barplot)
  p1 <- ggplot2::ggplot(df_tee, ggplot2::aes(x = visite_index, y = nb_esp_1fois)) +
    ggplot2::geom_col(
      fill = PALETTE_PRIMARY["orange"],
      alpha = 0.8,
      color = NA
    ) +
    ggplot2::geom_hline(
      yintercept = 0,
      linetype = "solid",
      linewidth = 0.5,
      color = "#333333"
    ) +
    ggplot2::labs(
      title = "Espèces observées une seule fois",
      x = "Visite (rang temporel)",
      y = "Nombre"
    ) +
    theme_project()
  
  # Panneau 2 : Indice Ir avec seuils scientifiques
  p2 <- ggplot2::ggplot(df_tee, ggplot2::aes(x = visite_index, y = Ir)) +
    # Zones de couleur indicative (background)
    ggplot2::annotate(
      "rect",
      xmin = -Inf, xmax = Inf, ymin = 0, ymax = 0.60,
      fill = "#FFCCCC", alpha = 0.2, color = NA
    ) +
    ggplot2::annotate(
      "rect",
      xmin = -Inf, xmax = Inf, ymin = 0.60, ymax = 0.80,
      fill = "#FFFFCC", alpha = 0.2, color = NA
    ) +
    ggplot2::annotate(
      "rect",
      xmin = -Inf, xmax = Inf, ymin = 0.80, ymax = 1.0,
      fill = "#CCFFCC", alpha = 0.2, color = NA
    ) +
    # Ligne et points
    ggplot2::geom_line(
      linewidth = 1.1,
      color = PALETTE_PRIMARY["blue"]
    ) +
    ggplot2::geom_point(
      size = 2.2,
      color = PALETTE_PRIMARY["blue"]
    ) +
    # Seuils scientifiques
    ggplot2::geom_hline(
      yintercept = 0.60,
      linetype = "dashed",
      linewidth = 0.7,
      color = PALETTE_PRIMARY["red"]
    ) +
    ggplot2::geom_hline(
      yintercept = 0.80,
      linetype = "dashed",
      linewidth = 0.7,
      color = PALETTE_PRIMARY["green"]
    ) +
    # Labels seuils
    ggplot2::annotate(
      "text",
      x = Inf, y = 0.60,
      label = "Acceptable (0.60)",
      hjust = 1, vjust = -0.5,
      size = 3, fontface = "italic", color = PALETTE_PRIMARY["red"]
    ) +
    ggplot2::annotate(
      "text",
      x = Inf, y = 0.80,
      label = "Bon (0.80)",
      hjust = 1, vjust = -0.5,
      size = 3, fontface = "italic", color = PALETTE_PRIMARY["green"]
    ) +
    # Titres et axes
    ggplot2::scale_y_continuous(
      limits = c(0, 1),
      labels = scales::percent_format(accuracy = 1)
    ) +
    ggplot2::labs(
      title = "Indice de représentativité (Ir = 1 - TEE)",
      x = "Visite (rang temporel)",
      y = "Ir"
    ) +
    theme_project()
  
  # Combiner les deux panneaux
  gridExtra::grid.arrange(p1, p2, nrow = 2, top = grid::textGrob(
    sprintf("Complétude et Représentativité - %s", site_name),
    gp = grid::gpar(fontsize = 14, fontface = "bold")
  ))
}

plot_frequency_hist <- function(freq_tbl, site_name) {
  ggplot2::ggplot(freq_tbl, ggplot2::aes(x = nb_visites)) +
    ggplot2::geom_histogram(
      binwidth = 1,
      boundary = 0.5,
      closed = "left",
      fill = PALETTE_PRIMARY["blue"],
      color = "#333333",
      alpha = 0.8
    ) +
    ggplot2::labs(
      title = paste("Distribution des fréquences d'observation —", site_name),
      x = "Nombre de visites où observée",
      y = "Nombre d'espèces"
    ) +
    theme_project()
}

plot_spatial_vs_temporal <- function(freq_tbl, occ_tbl, site_name) {
  if (is.null(occ_tbl)) return(NULL)
  joined <- freq_tbl |> dplyr::inner_join(occ_tbl, by = "espece")
  if (nrow(joined) == 0) return(NULL)

  ggplot2::ggplot(joined, ggplot2::aes(x = prop_visites, y = prop_placettes)) +
    ggplot2::geom_point(
      color = PALETTE_PRIMARY["blue"],
      alpha = 0.7,
      size = 2.5
    ) +
    ggplot2::geom_abline(
      intercept = 0,
      slope = 1,
      linetype = "dashed",
      linewidth = 0.7,
      color = PALETTE_PRIMARY["red"],
      alpha = 0.5
    ) +
    ggplot2::scale_x_continuous(
      labels = scales::percent_format(accuracy = 1),
      limits = c(0, 1)
    ) +
    ggplot2::scale_y_continuous(
      labels = scales::percent_format(accuracy = 1),
      limits = c(0, 1)
    ) +
    ggplot2::labs(
      title = paste("Distribution spatio-temporelle des espèces —", site_name),
      x = "Fréquence temporelle (% visites)",
      y = "Occupation spatiale (% placettes)",
      caption = "Ligne pointillée = relation parfaite temporelle/spatiale"
    ) +
    theme_project()
}

prepare_metrics_plot_data <- function(metrics_tbl) {
  if (is.null(metrics_tbl) || nrow(metrics_tbl) == 0) return(tibble::tibble())

  metrics_tbl |>
    dplyr::mutate(
      stabilite_fin = 1 - tail_novelty_share,
      robustesse_modele = dplyr::coalesce(r2_hyperbolique, r2_lineaire),
      coherence_temp_spat = (spearman_temporal_spatial + 1) / 2,
      concordance_temp_spat = 1 - discordance_rate
    ) |>
    dplyr::select(
      site,
      ir_final,
      completude,
      stabilite_fin,
      robustesse_modele,
      coherence_temp_spat,
      concordance_temp_spat,
      score_pertinence
    ) |>
    tidyr::pivot_longer(
      cols = -site,
      names_to = "indicateur",
      values_to = "valeur"
    ) |>
    dplyr::mutate(
      indicateur = factor(
        indicateur,
        levels = c(
          "ir_final",
          "completude",
          "stabilite_fin",
          "robustesse_modele",
          "coherence_temp_spat",
          "concordance_temp_spat",
          "score_pertinence"
        ),
        labels = c(
          "Ir final",
          "Complétude",
          "Stabilité finale",
          "Robustesse modèle (R²)",
          "Cohérence temp/spat (Spearman)",
          "Concordance temp/spat",
          "Score de pertinence"
        )
      )
    )
}

plot_scientific_metrics_site <- function(scientific_metrics, site_name) {
  pdat <- prepare_metrics_plot_data(scientific_metrics) |>
    dplyr::filter(!is.na(valeur))

  if (nrow(pdat) == 0) return(NULL)

  ggplot2::ggplot(pdat, ggplot2::aes(x = indicateur, y = valeur, fill = indicateur)) +
    ggplot2::geom_col(width = 0.75, color = "white", linewidth = 0.3, show.legend = FALSE) +
    ggplot2::geom_hline(yintercept = 0.60, linetype = "dashed", color = "gray45", linewidth = 0.5) +
    ggplot2::geom_hline(yintercept = 0.80, linetype = "dashed", color = "gray45", linewidth = 0.5) +
    ggplot2::scale_y_continuous(
      limits = c(0, 1),
      labels = scales::percent_format(accuracy = 1)
    ) +
    ggplot2::coord_flip() +
    ggplot2::scale_fill_manual(values = c(
      "Ir final" = PALETTE_PRIMARY[["blue"]],
      "Complétude" = PALETTE_PRIMARY[["green"]],
      "Stabilité finale" = PALETTE_PRIMARY[["orange"]],
      "Robustesse modèle (R²)" = PALETTE_PRIMARY[["purple"]],
      "Cohérence temp/spat (Spearman)" = PALETTE_PRIMARY[["red"]],
      "Concordance temp/spat" = "#56B4E9",
      "Score de pertinence" = "#1B9E77"
    )) +
    ggplot2::labs(
      title = paste("Métriques de pertinence scientifique —", site_name),
      subtitle = "Lecture : < 60% faible, 60-80% intermédiaire, > 80% satisfaisant",
      x = "",
      y = "Score (0 à 1)"
    ) +
    theme_project()
}

plot_scientific_metrics_heatmap <- function(site_metrics) {
  pdat <- prepare_metrics_plot_data(site_metrics) |>
    dplyr::filter(!is.na(valeur))

  if (nrow(pdat) == 0) return(NULL)

  ggplot2::ggplot(pdat, ggplot2::aes(x = indicateur, y = stats::reorder(site, valeur, FUN = mean), fill = valeur)) +
    ggplot2::geom_tile(color = "white", linewidth = 0.4) +
    ggplot2::geom_text(
      ggplot2::aes(label = sprintf("%.2f", valeur)),
      size = 3,
      color = "black"
    ) +
    ggplot2::scale_fill_gradientn(
      colours = c("#D55E00", "#E69F00", "#009E73"),
      limits = c(0, 1),
      labels = scales::percent_format(accuracy = 1),
      name = "Niveau"
    ) +
    ggplot2::labs(
      title = "Heatmap des métriques de pertinence par site",
      subtitle = "Comparaison multi-sites des dimensions : stabilité, robustesse, cohérence",
      x = "Indicateur",
      y = "Site"
    ) +
    theme_project() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 20, hjust = 1))
}

plot_scientific_metrics_score <- function(site_metrics) {
  if (is.null(site_metrics) || nrow(site_metrics) == 0) return(NULL)

  score_tbl <- site_metrics |>
    dplyr::select(site, score_pertinence, class_ir, class_completude) |>
    dplyr::mutate(
      score_pertinence = as.numeric(score_pertinence),
      etiquette = paste0("Ir: ", class_ir, " | Complétude: ", class_completude)
    ) |>
    dplyr::filter(!is.na(score_pertinence))

  if (nrow(score_tbl) == 0) return(NULL)

  ggplot2::ggplot(score_tbl, ggplot2::aes(x = stats::reorder(site, score_pertinence), y = score_pertinence)) +
    ggplot2::annotate("rect", xmin = -Inf, xmax = Inf, ymin = 0, ymax = 0.60, fill = "#FFCCCC", alpha = 0.25) +
    ggplot2::annotate("rect", xmin = -Inf, xmax = Inf, ymin = 0.60, ymax = 0.80, fill = "#FFFFCC", alpha = 0.25) +
    ggplot2::annotate("rect", xmin = -Inf, xmax = Inf, ymin = 0.80, ymax = 1.00, fill = "#CCFFCC", alpha = 0.25) +
    ggplot2::geom_col(fill = PALETTE_PRIMARY[["blue"]], alpha = 0.85) +
    ggplot2::geom_text(
      ggplot2::aes(label = sprintf("%.2f", score_pertinence)),
      hjust = -0.1,
      size = 3.2
    ) +
    ggplot2::coord_flip(clip = "off") +
    ggplot2::scale_y_continuous(
      limits = c(0, 1.05),
      labels = scales::percent_format(accuracy = 1)
    ) +
    ggplot2::labs(
      title = "Classement global par score de pertinence scientifique",
      subtitle = "Score agrégé : Ir, complétude, stabilité finale et robustesse du modèle",
      x = "Site",
      y = "Score de pertinence"
    ) +
    theme_project()
}

save_plot <- function(plot_obj, filename, config = CONFIG, formats = c("png")) {
  if (is.null(plot_obj)) return(invisible(NULL))
  
  # Extraire le chemin et le nom de fichier base (sans extension)
  dir_path <- dirname(filename)
  file_base <- tools::file_path_sans_ext(basename(filename))
  
  # Sauvegarder dans les formats demandés
  for (fmt in formats) {
    if (!(fmt %in% c("png", "pdf", "svg"))) {
      log_warning("Format graphique '%s' non supporté (png, pdf, svg). Ignoré.", fmt)
      next
    }
    
    fname_out <- file.path(dir_path, sprintf("%s.%s", file_base, fmt))
    
    tryCatch(
      {
        if (fmt == "png") {
          ggplot2::ggsave(
            filename = fname_out,
            plot = plot_obj,
            width = config$width,
            height = config$height,
            dpi = config$dpi,
            device = "png"
          )
        } else if (fmt == "pdf") {
          ggplot2::ggsave(
            filename = fname_out,
            plot = plot_obj,
            width = config$width,
            height = config$height,
            useDingbats = FALSE,
            device = "pdf"
          )
        } else if (fmt == "svg") {
          ggplot2::ggsave(
            filename = fname_out,
            plot = plot_obj,
            width = config$width,
            height = config$height,
            device = "svg"
          )
        }
        log_debug("Graphique enregistré : %s", fname_out)
      },
      error = function(e) {
        log_warning(
          "Échec sauvegarde %s '%s' : %s",
          fmt, fname_out, conditionMessage(e)
        )
      }
    )
  }
  invisible(filename)
}

analyze_site <- function(df_site, site_name, output_dir, config = CONFIG) {
  site_slug <- sanitize_filename(site_name)
  site_dir <- file.path(output_dir, site_slug)
  ensure_dir(site_dir)
  rplots_path <- file.path(getwd(), "Rplots.pdf")
  rplots_exists_before <- file.exists(rplots_path)
  rplots_mtime_before <- if (rplots_exists_before) file.info(rplots_path)$mtime else as.POSIXct(NA)

  log_info(
    "Analyse du site : %s | observations=%d | visites=%d | especes=%d | placettes=%d",
    site_name,
    nrow(df_site),
    count_distinct_visits(df_site),
    dplyr::n_distinct(df_site$espece),
    dplyr::n_distinct(stats::na.omit(df_site$placette))
  )
  log_debug("Répertoire de sortie du site '%s' : %s", site_name, site_dir)

  # Benchmark : calculs principaux (si mode benchmark activé)
  if (isTRUE(BENCHMARK_MODE)) {
    bench_results <- list()
    b_cum <- bench_time(calc_cumulative_metrics(df_site), sprintf("calc_cumulative [%s]", site_name))
    df_cum <- b_cum$result
    bench_results$cumulative <- b_cum$elapsed
    
    b_tee <- bench_time(calc_tee_ir(df_site), sprintf("calc_tee_ir [%s]", site_name))
    df_tee <- b_tee$result
    bench_results$tee <- b_tee$elapsed
    
    b_freq <- bench_time(calc_species_frequency(df_site, config = config), sprintf("calc_freq [%s]", site_name))
    freq_tbl <- b_freq$result
    bench_results$freq <- b_freq$elapsed
  } else {
    df_cum <- calc_cumulative_metrics(df_site)
    df_tee <- calc_tee_ir(df_site)
    freq_tbl <- calc_species_frequency(df_site, config = config)
  }
  
  occ_tbl <- calc_spatial_occupancy(df_site)
  log_table_result(
    sprintf("site=%s / courbe_temps_especes", site_name),
    df_cum,
    preview_cols = c("visite_index", "visite_id", "nb_especes_trouvees", "nb_nouvelles", "nb_cumule")
  )
  log_table_result(
    sprintf("site=%s / tee_ir", site_name),
    df_tee,
    preview_cols = c("visite_index", "visite_id", "nb_total", "nb_esp_1fois", "TEE", "Ir")
  )
  log_table_result(
    sprintf("site=%s / frequence_especes", site_name),
    freq_tbl,
    preview_cols = c("espece", "nb_visites", "prop_visites", "classe_frequence")
  )
  log_table_result(
    sprintf("site=%s / occupation_spatiale", site_name),
    occ_tbl,
    preview_cols = c("espece", "nb_placettes", "prop_placettes")
  )

  model_stats <- tibble::tibble()
  fit_lin <- NULL
  fit_hyp <- NULL

  if (nrow(df_cum) >= config$min_visits_for_model) {
    fit_lin <- tryCatch(
      fit_linear_model(df_cum),
      error = function(e) {
        log_warning("Site '%s' : echec du modele lineaire : %s", site_name, conditionMessage(e))
        NULL
      }
    )
    if (HAS_MINPACK) {
      fit_hyp <- tryCatch(
        fit_hyperbolic_model(df_cum),
        error = function(e) {
          log_warning("Site '%s' : echec du modele hyperbolique : %s", site_name, conditionMessage(e))
          NULL
        }
      )
    } else {
      log_info("Info site '%s' : modele hyperbolique ignore, package 'minpack.lm' absent.", site_name)
    }
  } else {
    log_info(
      "Info site '%s' : modeles ignores, %d visites < seuil %d.",
      site_name, nrow(df_cum), config$min_visits_for_model
    )
  }
  # Extraction et logging des stats modèles ajustés (si succès)
  if (!is.null(fit_lin)) model_stats <- dplyr::bind_rows(model_stats, extract_model_stats(fit_lin, "lineaire", df_cum))
  if (!is.null(fit_hyp)) model_stats <- dplyr::bind_rows(model_stats, extract_model_stats(fit_hyp, "hyperbolique", df_cum))
  
  if (nrow(model_stats) > 0) {
    log_debug("Modèles conservés pour site '%s' : %s", site_name, paste(model_stats$modele, collapse = ", "))
  } else {
    log_debug("Aucun modèle conservé pour site '%s'.", site_name)
  }
  log_model_result(site_name, model_stats)

  hyper_asym <- if (!is.null(fit_hyp)) unname(stats::coef(fit_hyp)["a"]) else NA_real_
  s_obs <- max(df_cum$nb_cumule, na.rm = TRUE)
  completude <- ifelse(is.na(hyper_asym) || hyper_asym <= 0, NA_real_, s_obs / hyper_asym)

  site_summary <- tibble::tibble(
    site = site_name,
    nb_observations = nrow(df_site),
    nb_visites = count_distinct_visits(df_site),
    nb_especes_observees = dplyr::n_distinct(df_site$espece),
    nb_placettes = if ("placette" %in% names(df_site)) dplyr::n_distinct(stats::na.omit(df_site$placette)) else NA_integer_,
    asymptote_hyperbolique = hyper_asym,
    completude_obs_sur_asymptote = completude,
    tee_final = dplyr::last(df_tee$TEE),
    ir_final = dplyr::last(df_tee$Ir)
  )
  log_table_result(
    sprintf("site=%s / resume_site", site_name),
    site_summary,
    preview_cols = c(
      "site", "nb_observations", "nb_visites", "nb_especes_observees",
      "nb_placettes", "asymptote_hyperbolique", "completude_obs_sur_asymptote", "tee_final", "ir_final"
    )
  )

  scientific_metrics <- calc_scientific_metrics(
    df_cum = df_cum,
    df_tee = df_tee,
    freq_tbl = freq_tbl,
    occ_tbl = occ_tbl,
    model_stats = model_stats,
    completude = completude,
    site_name = site_name,
    terminal_k = 5
  )
  log_table_result(
    sprintf("site=%s / metrics_pertinence", site_name),
    scientific_metrics,
    preview_cols = c(
      "site", "nb_visites", "tee_final", "ir_final", "completude",
      "r2_hyperbolique", "slope_terminal_cumul", "tail_novelty_share", "score_pertinence"
    )
  )

  tryCatch(
    readr::write_csv(df_cum, file.path(site_dir, "ICR_01_courbe_temps_especes.csv")),
    error = function(e) stop("Echec d'ecriture de ICR_01_courbe_temps_especes.csv : ", conditionMessage(e), call. = FALSE)
  )
  log_debug("CSV ecrit : %s", file.path(site_dir, "ICR_01_courbe_temps_especes.csv"))
  tryCatch(
    readr::write_csv(df_tee, file.path(site_dir, "ICR_02_tee_ir.csv")),
    error = function(e) stop("Echec d'ecriture de ICR_02_tee_ir.csv : ", conditionMessage(e), call. = FALSE)
  )
  log_debug("CSV ecrit : %s", file.path(site_dir, "ICR_02_tee_ir.csv"))
  tryCatch(
    readr::write_csv(freq_tbl, file.path(site_dir, "ICR_03_frequence_especes.csv")),
    error = function(e) stop("Echec d'ecriture de ICR_03_frequence_especes.csv : ", conditionMessage(e), call. = FALSE)
  )
  log_debug("CSV ecrit : %s", file.path(site_dir, "ICR_03_frequence_especes.csv"))
  tryCatch(
    readr::write_csv(site_summary, file.path(site_dir, "ICR_04_resume_site.csv")),
    error = function(e) stop("Echec d'ecriture de ICR_04_resume_site.csv : ", conditionMessage(e), call. = FALSE)
  )
  log_debug("CSV ecrit : %s", file.path(site_dir, "ICR_04_resume_site.csv"))
  if (nrow(model_stats) > 0) {
    tryCatch(
      readr::write_csv(model_stats, file.path(site_dir, "ICR_05_modeles.csv")),
      error = function(e) stop("Echec d'ecriture de ICR_05_modeles.csv : ", conditionMessage(e), call. = FALSE)
    )
    log_debug("CSV ecrit : %s", file.path(site_dir, "ICR_05_modeles.csv"))
  }
  tryCatch(
    readr::write_csv(scientific_metrics, file.path(site_dir, "ICR_07_metrics_pertinence.csv")),
    error = function(e) stop("Echec d'ecriture de ICR_07_metrics_pertinence.csv : ", conditionMessage(e), call. = FALSE)
  )
  log_debug("CSV ecrit : %s", file.path(site_dir, "ICR_07_metrics_pertinence.csv"))
  if (!is.null(occ_tbl)) {
    tryCatch(
      readr::write_csv(occ_tbl, file.path(site_dir, "ICR_06_occupation_spatiale.csv")),
      error = function(e) stop("Echec d'ecriture de ICR_06_occupation_spatiale.csv : ", conditionMessage(e), call. = FALSE)
    )
    log_debug("CSV ecrit : %s", file.path(site_dir, "ICR_06_occupation_spatiale.csv"))
  } else {
    log_info("Info site '%s' : occupation spatiale non produite, aucune placette exploitable.", site_name)
  }

  save_plot(plot_richness_over_time(df_cum, site_name), file.path(site_dir, "ICR_01_richesse_par_visite_et_cumul.png"), config)
  log_info("Resultat graphique genere : %s", file.path(site_dir, "ICR_01_richesse_par_visite_et_cumul.png"))
  save_plot(plot_time_species_curve(df_cum, fit_hyp, site_name), file.path(site_dir, "ICR_02_courbe_temps_especes_hyperbole.png"), config)
  log_info("Resultat graphique genere : %s", file.path(site_dir, "ICR_02_courbe_temps_especes_hyperbole.png"))
  save_plot(plot_tee_ir(df_tee, site_name), file.path(site_dir, "ICR_03_tee_ir.png"), config)
  log_info("Resultat graphique genere : %s", file.path(site_dir, "ICR_03_tee_ir.png"))
  save_plot(plot_frequency_hist(freq_tbl, site_name), file.path(site_dir, "ICR_04_histogramme_frequences.png"), config)
  log_info("Resultat graphique genere : %s", file.path(site_dir, "ICR_04_histogramme_frequences.png"))
  save_plot(plot_spatial_vs_temporal(freq_tbl, occ_tbl, site_name), file.path(site_dir, "ICR_05_temporel_vs_spatial.png"), config)
  if (!is.null(occ_tbl)) {
    log_info("Resultat graphique genere : %s", file.path(site_dir, "ICR_05_temporel_vs_spatial.png"))
  }

  save_plot(plot_scientific_metrics_site(scientific_metrics, site_name), file.path(site_dir, "ICR_07_metrics_pertinence_dashboard.png"), config)
  log_info("Resultat graphique genere : %s", file.path(site_dir, "ICR_07_metrics_pertinence_dashboard.png"))

  if (isTRUE(config$make_ca)) {
    ca_res <- tryCatch(
      run_ca(df_site, site_name = site_name),
      error = function(e) {
        log_warning("Site '%s' : echec de la CA : %s", site_name, conditionMessage(e))
        NULL
      }
    )
    if (!is.null(ca_res)) {
      log_debug("Export du graphique de CA pour site '%s'.", site_name)
      ca_plot_title <- sprintf("CA / AFC - %s", site_name)
      tryCatch(
        {
          png(file.path(site_dir, "ICR_06_CA_placettes_especes.png"), width = 2200, height = 1600, res = 220)
          plot(ca_res$model)
          title(main = ca_plot_title)
          dev.off()
        },
        error = function(e) {
          if (grDevices::dev.cur() > 1) grDevices::dev.off()
          stop("Echec de creation de ICR_06_CA_placettes_especes.png : ", conditionMessage(e), call. = FALSE)
        }
      )
      log_debug("Graphique ecrit : %s", file.path(site_dir, "ICR_06_CA_placettes_especes.png"))
      log_info("Resultat graphique genere : %s", file.path(site_dir, "ICR_06_CA_placettes_especes.png"))
    }
  } else {
    log_info("Info site '%s' : CA desactivee par configuration.", site_name)
  }

  log_info(
    "Fin du site '%s' : completude=%s | Ir final=%s",
    site_name,
    ifelse(is.na(completude), "NA", sprintf("%.4f", completude)),
    ifelse(is.na(dplyr::last(df_tee$Ir)), "NA", sprintf("%.4f", dplyr::last(df_tee$Ir)))
  )

  cleanup_new_rplots_pdf(
    existed_before = rplots_exists_before,
    mtime_before = rplots_mtime_before,
    context = paste0("site=", site_name)
  )

  invisible(list(site_summary = site_summary, model_stats = model_stats, scientific_metrics = scientific_metrics))
}

run_analysis <- function(config = CONFIG) {
  print_startup_header(config)

  rplots_path <- file.path(getwd(), "Rplots.pdf")
  rplots_exists_before <- file.exists(rplots_path)
  rplots_mtime_before <- if (rplots_exists_before) file.info(rplots_path)$mtime else as.POSIXct(NA)

  validate_config(config)
  input_file <- resolve_input_file(config)
  output_dir <- resolve_path(config$output_dir)

  ensure_dir(output_dir)
  log_info("Repertoire de sortie global : %s", output_dir)

  if (!HAS_MINPACK) {
    log_info("Info : package optionnel 'minpack.lm' non installé. Le modèle hyperbolique et l'asymptote seront ignorés.")
  }
  if (HAS_VEGAN) {
    log_info("Package optionnel 'vegan' detecte : CA disponible.")
  } else {
    log_info("Package optionnel 'vegan' absent : CA indisponible.")
  }

  log_info("Lecture : %s", input_file)
  read_res <- read_delim_auto(input_file, config = config)
  df_raw <- read_res$data

  csv_audit <- audit_csv_conformity(
    df_raw = df_raw,
    parse_problems = read_res$problems,
    path = input_file,
    delim = read_res$delim,
    config = config
  )
  export_csv_conformity_report(csv_audit, output_dir)

  if (!csv_audit$is_conform) {
    msg <- paste0(
      "CSV non conforme : ",
      if (length(csv_audit$missing_required) > 0) {
        paste0("colonnes manquantes [", paste(csv_audit$missing_required, collapse = ", "), "]")
      } else {
        ""
      },
      if (length(csv_audit$missing_required) > 0 && length(csv_audit$extra_cols) > 0) " ; " else "",
      if (length(csv_audit$extra_cols) > 0) {
        paste0("colonnes supplémentaires [", paste(csv_audit$extra_cols, collapse = ", "), "]")
      } else {
        ""
      },
      if ((length(csv_audit$missing_required) > 0 || length(csv_audit$extra_cols) > 0) && csv_audit$parse_problem_count > 0) " ; " else "",
      if (csv_audit$parse_problem_count > 0) {
        paste0("problèmes de parsing=", csv_audit$parse_problem_count)
      } else {
        ""
      }
    )

    if (isTRUE(config$csv_strict_mode)) {
      stop(msg, "\nVoir : ", file.path(output_dir, "ICR_00_csv_conformite_report.csv"), call. = FALSE)
    }

    log_warning("%s", msg)
  } else {
    log_info("Validation CSV : CONFORME (schéma + parsing).")
  }

  df <- prepare_data(df_raw, config = config)
  tryCatch(
    readr::write_csv(df, file.path(output_dir, "ICR_donnees_preparees.csv")),
    error = function(e) stop("Echec d'ecriture de ICR_donnees_preparees.csv : ", conditionMessage(e), call. = FALSE)
  )
  log_debug("CSV ecrit : %s", file.path(output_dir, "ICR_donnees_preparees.csv"))
  log_table_result(
    "global / donnees_preparees",
    df,
    preview_cols = c("site", "placette", "date", "visite_id", "espece")
  )

  sites <- unique(df$site)
  log_info("Lancement de l'analyse sur %d site(s) : %s", length(sites), paste(sites, collapse = ", "))

  site_results <- df |>
    dplyr::group_split(site) |>
    purrr::map(function(d) {
      site_name <- unique(d$site)
      analyze_site(d, site_name, output_dir, config = config)
    }) |>
    purrr::compact()

  site_summaries <- site_results |>
    purrr::map("site_summary") |>
    dplyr::bind_rows()

  site_metrics <- site_results |>
    purrr::map("scientific_metrics") |>
    dplyr::bind_rows()

  tryCatch(
    readr::write_csv(site_summaries, file.path(output_dir, "ICR_resume_tous_sites.csv")),
    error = function(e) stop("Echec d'ecriture de ICR_resume_tous_sites.csv : ", conditionMessage(e), call. = FALSE)
  )
  log_debug("CSV ecrit : %s", file.path(output_dir, "ICR_resume_tous_sites.csv"))
  log_table_result(
    "global / resume_tous_sites",
    site_summaries,
    preview_cols = c(
      "site", "nb_observations", "nb_visites", "nb_especes_observees",
      "nb_placettes", "asymptote_hyperbolique", "completude_obs_sur_asymptote", "tee_final", "ir_final"
    )
  )

  tryCatch(
    readr::write_csv(site_metrics, file.path(output_dir, "ICR_metrics_pertinence_tous_sites.csv")),
    error = function(e) stop("Echec d'ecriture de ICR_metrics_pertinence_tous_sites.csv : ", conditionMessage(e), call. = FALSE)
  )
  log_debug("CSV ecrit : %s", file.path(output_dir, "ICR_metrics_pertinence_tous_sites.csv"))
  log_table_result(
    "global / metrics_pertinence_tous_sites",
    site_metrics,
    preview_cols = c(
      "site", "nb_visites", "tee_final", "ir_final", "completude",
      "r2_hyperbolique", "tail_novelty_share", "score_pertinence"
    )
  )

  # Graphique comparatif de la complétude entre sites (trié par complétude croissante)
  p_compare <- ggplot2::ggplot(site_summaries,
    ggplot2::aes(x = stats::reorder(site, completude_obs_sur_asymptote), y = completude_obs_sur_asymptote)
  ) +
    ggplot2::geom_col(fill = PALETTE_PRIMARY["blue"]) +
    ggplot2::coord_flip() +
    ggplot2::scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
    ggplot2::labs(
      title = "Complétude observée / asymptote hyperbolique par site",
      subtitle = "Classement des sites par complétude",
      x = "Site", 
      y = "Complétude"
    ) +
    theme_project()
  save_plot(p_compare, file.path(output_dir, "ICR_comparaison_completude_sites.png"), config)
  log_info("Resultat graphique genere : %s", file.path(output_dir, "ICR_comparaison_completude_sites.png"))

  # Graphique comparatif de l'indice Ir entre sites avec zones de qualité colorées
  # Zone rouge  : Ir < 0.60 (représentativité faible)
  # Zone jaune  : 0.60 ≤ Ir < 0.80 (représentativité moyenne)
  # Zone verte  : Ir ≥ 0.80 (bonne représentativité)
  p_ir <- ggplot2::ggplot(site_summaries,
    ggplot2::aes(x = stats::reorder(site, ir_final), y = ir_final)
  ) +
    ggplot2::annotate("rect", xmin = -Inf, xmax = Inf, ymin = 0, ymax = 0.60, fill = "#FFCCCC", alpha = 0.3) +
    ggplot2::annotate("rect", xmin = -Inf, xmax = Inf, ymin = 0.60, ymax = 0.80, fill = "#FFFFCC", alpha = 0.3) +
    ggplot2::annotate("rect", xmin = -Inf, xmax = Inf, ymin = 0.80, ymax = 1.0, fill = "#CCFFCC", alpha = 0.3) +
    ggplot2::geom_col(fill = PALETTE_PRIMARY["blue"]) +
    ggplot2::geom_hline(yintercept = 0.60, linetype = "dashed", color = "gray50", linewidth = 0.5) +
    ggplot2::geom_hline(yintercept = 0.80, linetype = "dashed", color = "gray50", linewidth = 0.5) +
    ggplot2::coord_flip() +
    ggplot2::scale_y_continuous(labels = scales::percent_format(accuracy = 1), limits = c(0, 1)) +
    ggplot2::annotate("text", x = Inf, y = 0.30, label = "Faible", color = "darkred", size = 3, hjust = 1, vjust = 1.5) +
    ggplot2::annotate("text", x = Inf, y = 0.70, label = "Moyen", color = "darkorange", size = 3, hjust = 1, vjust = 1.5) +
    ggplot2::annotate("text", x = Inf, y = 0.90, label = "Bon", color = "darkgreen", size = 3, hjust = 1, vjust = 1.5) +
    ggplot2::labs(
      title = "Indice de représentativité final par site",
      subtitle = "Seuils scientifiques : < 0.60 (faible), 0.60-0.80 (moyen), > 0.80 (bon)",
      x = "Site", 
      y = "Ir final"
    ) +
    theme_project()
  save_plot(p_ir, file.path(output_dir, "ICR_comparaison_ir_sites.png"), config)
  log_info("Resultat graphique genere : %s", file.path(output_dir, "ICR_comparaison_ir_sites.png"))

  save_plot(plot_scientific_metrics_heatmap(site_metrics), file.path(output_dir, "ICR_metrics_pertinence_heatmap_sites.png"), config)
  log_info("Resultat graphique genere : %s", file.path(output_dir, "ICR_metrics_pertinence_heatmap_sites.png"))

  save_plot(plot_scientific_metrics_score(site_metrics), file.path(output_dir, "ICR_metrics_pertinence_score_sites.png"), config)
  log_info("Resultat graphique genere : %s", file.path(output_dir, "ICR_metrics_pertinence_score_sites.png"))

  log_info(
    "Analyse terminée : %d site(s) traité(s), résultats dans : %s",
    nrow(site_summaries),
    output_dir
  )

  log_output_manifest(
    output_dir = output_dir,
    site_names = site_summaries$site,
    config = config
  )
  # Politique stricte : ne jamais conserver de Rplots.pdf parasite en sortie.
  cleanup_new_rplots_pdf(
    existed_before = rplots_exists_before,
    mtime_before = rplots_mtime_before,
    context = "global"
  )
  # Note : les données détaillées par site (courbe temps-espèces, TEE/IR, fréquences, occupation spatiale) sont déjà sauvegardées dans les sous-dossiers 
  # respectifs de chaque site.
  invisible(site_summaries)
}
#
# =======================================================================================================================================================
# MODES D'EXÉCUTION
# =======================================================================================================================================================
# L'utilisateur peut paramétrer des flags globaux en haut du script :
#
# DEBUG_MODE = TRUE       : Affiche tous les warnings + messages détaillés
# BENCHMARK_MODE = TRUE   : Mesure temps d'exécution des calculs cumulés
# CLEAN_ENVIRONMENT = TRUE: Nettoie l'environnement R (déconseillé pour les non-initiés, à utiliser avec précaution)
#
# Exemples :
#   source("Inventaires_completude_representativite.R")  # Défaut : mode normal
#   DEBUG_MODE <- TRUE ; source("...")                   # Mode debug
#   BENCHMARK_MODE <- TRUE ; source("...")              # Mode benchmark
#=========================================================================================================================================================
# Lancement automatique en session interactive ou non-interactive (Rscript)
if (isTRUE(AUTO_RUN)) {
  if (!IS_INTERACTIVE_SESSION) {
    run_analysis(CONFIG)
  } else if (interactive()) {
    log_info("Session interactive : run_analysis(CONFIG) prêt à être appelé.")
    run_analysis(CONFIG)
  }
} else {
  log_info("Auto-run désactivé via INVENTAIRES_AUTO_RUN. Chargement des fonctions uniquement.")
}
#==========================================================================================================================================================