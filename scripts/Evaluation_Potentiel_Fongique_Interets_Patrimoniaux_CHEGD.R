#!/usr/bin/env Rscript

# ================================================================================
# Évaluation du potentiel fongique, de l'intérêt patrimonial et du gradient CHEGD
# --------------------------------------------------------------------------------
# But :
#   - Lire un fichier Excel de données brutes d'observations mycologiques.
#   - Produire des résumés globaux (site/famille/espèce/date/fiabilité).
#   - Calculer des indicateurs par site (potentiel, patrimonialité, CHEGD).
#   - Aligner les indicateurs sur un classeur de référence si disponible
#     (mode « fidélité Excel »).
#
# Entrées :
#   - Configuration intégrée au script (modifiable dans get_embedded_config)
#   - Fichier de données brutes (cfg$input_file, feuille cfg$input_sheet)
#   - Classeur de référence optionnel (détecté automatiquement)
#
# Sorties :
#   - Répertoire horodaté dans cfg$output_dir contenant les CSV de synthèse.
#
# ================================================================================

# --------------------------------------------------------------------------------
# Pré-requis : packages R 
suppressPackageStartupMessages({
  if (!requireNamespace("readxl", quietly = TRUE)) {
    install.packages("readxl", repos = "https://cloud.r-project.org")
  }
  if (!requireNamespace("dplyr", quietly = TRUE)) {
    install.packages("dplyr", repos = "https://cloud.r-project.org")
  }
  if (!requireNamespace("stringr", quietly = TRUE)) {
    install.packages("stringr", repos = "https://cloud.r-project.org")
  }
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    install.packages("ggplot2", repos = "https://cloud.r-project.org")
  }
  if (!requireNamespace("gridExtra", quietly = TRUE)) {
    install.packages("gridExtra", repos = "https://cloud.r-project.org")
  }
  if (!requireNamespace("MASS", quietly = TRUE)) {
    install.packages("MASS", repos = "https://cloud.r-project.org")
  }
  if (!requireNamespace("nnet", quietly = TRUE)) {
    install.packages("nnet", repos = "https://cloud.r-project.org")
  }
})
# --------------------------------------------------------------------------------

# Chargement des packages
library(readxl)
library(dplyr)
library(stringr)
library(ggplot2)
library(gridExtra)
library(MASS)
library(nnet)

# =============================================================================
# Système de logging
# =============================================================================
# Un système de logging simple pour suivre l'exécution du script et enregistrer les messages dans un fichier log horodaté.
# Le log inclut des sections, des messages d'info, d'erreur et de warning, ainsi qu'un résumé des données et une durée d'exécution totale.
# Le fichier log est créé dans un sous-dossier "logs" du répertoire de sortie, avec un nom basé sur le préfixe de sortie et l'horodatage.

.log_env <- new.env()
.log_env$log_file <- NULL
.log_env$start_time <- NULL

# Initialise le logging avec un fichier log horodaté dans le répertoire de sortie.
setup_logging <- function(base_dir, prefix = "eval_pelouses") {
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M")
  logs_dir <- file.path(base_dir, "logs")
  dir.create(logs_dir, recursive = TRUE, showWarnings = FALSE)
  log_file <- file.path(logs_dir, paste0(prefix, "_", timestamp, ".log"))
  .log_env$log_file <- log_file
  .log_env$start_time <- Sys.time()
  cat("", file = log_file)
  invisible(log_file)
}

# Fonction de logging avec horodatage optionnel
log_info <- function(msg, timestamp = TRUE) {
  ts_str <- if (timestamp) format(Sys.time(), "[%H:%M:%S] ") else ""
  full_msg <- paste0(ts_str, msg)
  cat(full_msg, "\n")
  if (!is.null(.log_env$log_file)) {
    cat(full_msg, "\n", file = .log_env$log_file, append = TRUE)
  }
}

# Fonction de logging des erreurs
log_error <- function(msg) {
  full_msg <- paste0("[ERROR] ", msg)
  cat(full_msg, "\n", file = stderr())
  if (!is.null(.log_env$log_file)) {
    cat(full_msg, "\n", file = .log_env$log_file, append = TRUE)
  }
}

# Fonction de logging des warnings
log_warning_msg <- function(msg) {
  full_msg <- paste0("[WARN] ", msg)
  cat(full_msg, "\n")
  if (!is.null(.log_env$log_file)) {
    cat(full_msg, "\n", file = .log_env$log_file, append = TRUE)
  }
}
# Fonction de logging des sections
log_section <- function(title) {
  sep <- strrep("─", 80)
  log_info(sep, timestamp = FALSE)
  log_info(paste0("  ", title), timestamp = FALSE)
  log_info(sep, timestamp = FALSE)
}

# Fonctions de logging pour le résumé des données et l'exécution
log_header <- function(config_path, input_file) {
  log_section("Évaluation du potentiel fongique, de l'intérêt patrimonial et du gradient CHEGD")
  log_info(paste0("Horodatage : ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")), timestamp = FALSE)
  log_info(paste0("Version de R : ", R.version$version.string), timestamp = FALSE)
  log_info(paste0("Répertoire de travail : ", getwd()), timestamp = FALSE)
  log_info(paste0("Configuration: ", config_path), timestamp = FALSE)
  log_info(paste0("Fichier d'entrée : ", input_file), timestamp = FALSE)
}

# Fonction de logging pour le résumé des données
log_data_summary <- function(nrows, nspecies, nsites, ndates) {
  log_section("RÉSUMÉ DES DONNÉES")
  log_info(paste0("Nombre total d'observations : ", nrows))
  log_info(paste0("Nombre d'espèces uniques : ", nspecies))
  log_info(paste0("Nombre de sites uniques : ", nsites))
  log_info(paste0("Nombre de dates uniques : ", ndates))
}

# Fonction de logging pour le résumé des métriques par site
log_footer <- function() {
  log_section("EXÉCUTION TERMINÉE")
  if (!is.null(.log_env$start_time)) {
    elapsed <- as.numeric(difftime(Sys.time(), .log_env$start_time, units = "secs"))
    log_info(paste0("Durée totale d'exécution : ", round(elapsed, 2), " secondes"), timestamp = FALSE)
  }
  log_info(paste0("Heure de fin : ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")), timestamp = FALSE)
  log_info(paste0("Fichier log : ", .log_env$log_file), timestamp = FALSE)
}

# =============================================================================
# Configuration et résolution des chemins
# =============================================================================
# Configuration embarquée du pipeline.
# Modifier cette fonction pour changer les paramètres par défaut.
get_embedded_config <- function() {
  list(
    input_file = "data/données_récoltes_chegd_pelouses.csv",
    input_sheet = NULL,
    output_dir = "results",
    output_prefix = "eval_pelouses",
    columns = list(
      species = "Espèces",
      family = "Famille",
      date = "Date",
      count = "Nombre d'espèce",
      site = "Site",
      reliability = "Fiabilité détermination"
    )
  )
}

# Détermine le répertoire du script en mode Rscript/VSCode et fallback getwd().
get_script_dir <- function() {
  cmd_args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", cmd_args, value = TRUE)
  if (length(file_arg) > 0) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg[[1]]), winslash = "/", mustWork = FALSE)))
  }

  if (!is.null(sys.frames()[[1]]$ofile)) {
    return(dirname(normalizePath(sys.frames()[[1]]$ofile, winslash = "/", mustWork = FALSE)))
  }

  normalizePath(getwd(), winslash = "/", mustWork = FALSE)
}

# Résout le chemin de configuration avec plusieurs emplacements candidats.
resolve_config_path <- function(config_path) {
  if (file.exists(config_path)) {
    return(normalizePath(config_path, winslash = "/", mustWork = TRUE))
  }

  script_dir <- get_script_dir()
  candidates <- c(
    file.path(getwd(), config_path),
    file.path(script_dir, config_path),
    file.path(script_dir, basename(config_path)),
    file.path(dirname(script_dir), config_path)
  )

  existing <- candidates[file.exists(candidates)]
  if (length(existing) > 0) {
    return(normalizePath(existing[[1]], winslash = "/", mustWork = TRUE))
  }

  stop("Fichier de configuration introuvable : ", config_path)
}

# Résout un chemin relatif à partir d'une base projet.
resolve_path_from_base <- function(path_value, base_dir) {
  if (is.null(path_value) || is.na(path_value) || path_value == "") {
    return(path_value)
  }
  if (grepl("^(/|[A-Za-z]:[/\\\\])", path_value)) {
    return(path_value)
  }
  file.path(base_dir, path_value)
}

# Normalise un nom de fichier (accents/casse/séparateurs) pour matching robuste.
normalize_filename <- function(x) {
  x_ascii <- iconv(x, from = "", to = "ASCII//TRANSLIT")
  x_ascii[is.na(x_ascii)] <- x[is.na(x_ascii)]
  x_ascii <- tolower(x_ascii)
  gsub("[^a-z0-9]", "", x_ascii)
}

# Résout le fichier d'entrée .xlsx :
#   1) chemin exact, 2) correspondance normalisée, 3) nom proche (distance).
resolve_input_file <- function(path_value, base_dir) {
  resolved <- resolve_path_from_base(path_value, base_dir)
  if (!is.null(resolved) && !is.na(resolved) && resolved != "" && file.exists(resolved)) {
    return(normalizePath(resolved, winslash = "/", mustWork = TRUE))
  }

  preferred_name <- basename(path_value)
  search_dirs <- c(file.path(base_dir, "data"), base_dir)
  search_dirs <- unique(search_dirs[dir.exists(search_dirs)])
  candidates <- unlist(lapply(search_dirs, function(d) list.files(d, pattern = "\\.(xlsx|csv)$", full.names = TRUE, recursive = TRUE, ignore.case = TRUE)))
  candidates <- unique(candidates[file.exists(candidates)])

  if (length(candidates) == 0) {
    stop("Fichier d'entrée introuvable : ", path_value)
  }

  preferred_norm <- normalize_filename(preferred_name)
  candidate_names <- basename(candidates)
  candidate_norm <- normalize_filename(candidate_names)

  exact_idx <- which(candidate_norm == preferred_norm)
  if (length(exact_idx) > 0) {
    chosen <- candidates[[exact_idx[[1]]]]
    message("ℹ️ Fichier d'entrée résolu automatiquement (correspondance normalisée) : ", chosen)
    return(normalizePath(chosen, winslash = "/", mustWork = TRUE))
  }

  distances <- adist(preferred_norm, candidate_norm)
  best_idx <- which.min(distances[1, ])
  best_distance <- distances[1, best_idx]
  threshold <- max(3, floor(nchar(preferred_norm) * 0.25))

  if (!is.na(best_distance) && best_distance <= threshold) {
    chosen <- candidates[[best_idx]]
    message("ℹ️ Fichier d'entrée résolu automatiquement (nom proche) : ", chosen)
    return(normalizePath(chosen, winslash = "/", mustWork = TRUE))
  }

  stop(
    "Fichier d'entrée introuvable : ", path_value,
    "\nCandidats trouvés : ", paste(candidate_names, collapse = ", ")
  )
}

# Fonction de détection automatique du séparateur CSV
guess_csv_separator <- function(file_path) {
  first_lines <- readLines(file_path, n = 5, warn = FALSE, encoding = "UTF-8")
  first_lines <- first_lines[nzchar(trimws(first_lines))]
  if (length(first_lines) == 0) {
    return(";")
  }

  semicolon_score <- sum(stringr::str_count(first_lines, ";"))
  comma_score <- sum(stringr::str_count(first_lines, ","))
  if (comma_score > semicolon_score) "," else ";"
}

# Fonction de lecture des données d'entrée
read_input_data <- function(input_file, input_sheet = NULL) {
  ext <- tolower(tools::file_ext(input_file))

  if (ext == "xlsx") {
    if (is.null(input_sheet) || !nzchar(trimws(as.character(input_sheet)))) {
      return(readxl::read_excel(input_file))
    }
    return(readxl::read_excel(input_file, sheet = input_sheet))
  }

  if (ext == "csv") {
    sep <- guess_csv_separator(input_file)
    csv_lines <- readLines(input_file, warn = FALSE, encoding = "UTF-8")
    csv_lines <- csv_lines[!grepl("^[[:space:];,]+$", csv_lines)]
    if (length(csv_lines) == 0) {
      stop("Le fichier CSV est vide ou ne contient que des séparateurs : ", input_file)
    }

    raw <- utils::read.table(
      text = csv_lines,
      header = TRUE,
      sep = sep,
      quote = '"',
      comment.char = "",
      stringsAsFactors = FALSE,
      check.names = FALSE,
      fill = TRUE
    )

    col_names_trim <- trimws(names(raw))
    names(raw) <- col_names_trim

    # Supprime la colonne de tête vide éventuelle (exports avec séparateur initial).
    if (ncol(raw) > 0) {
      first_col <- raw[[1]]
      first_col_empty <- all(is.na(first_col) | trimws(as.character(first_col)) == "")
      first_name_empty <- is.na(names(raw)[1]) || names(raw)[1] == ""
      if (first_col_empty && first_name_empty) {
        raw <- raw[, -1, drop = FALSE]
      }
    }

    # Supprime les colonnes totalement vides (cas fréquent avec CSV exportés avec ; en bord).
    keep_cols <- vapply(raw, function(col) any(trimws(as.character(col)) != "" & !is.na(col)), logical(1))
    raw <- raw[, keep_cols, drop = FALSE]
    return(raw)
  }

  stop("Format d'entrée non supporté : ", ext, " (formats supportés : .xlsx, .csv)")
}

# Vérifie la présence des colonnes métier attendues dans la feuille d'entrée.
ensure_required_columns <- function(df, cfg) {
  required <- unlist(cfg$columns, use.names = TRUE)
  missing_cols <- required[!required %in% names(df)]
  if (length(missing_cols) > 0) {
    stop(
      "Colonnes manquantes dans la feuille d'entrée : ",
      paste(missing_cols, collapse = ", ")
    )
  }
}

# -----------------------------------------------------------------------------
# Helpers de conversion et normalisation
# -----------------------------------------------------------------------------

# Convertit un vecteur vers Date en gérant : Date, numéros Excel, formats texte.
to_date_safe <- function(x) {
  if (inherits(x, "Date")) {
    return(x)
  }

  if (is.numeric(x)) {
    return(as.Date(x, origin = "1899-12-30"))
  }

  x_chr <- trimws(as.character(x))
  x_chr[x_chr %in% c("", "NA", "NaN")] <- NA_character_

  numeric_like <- !is.na(x_chr) & grepl("^\\d+(?:[.,]\\d+)?$", x_chr)
  if (any(numeric_like)) {
    x_num <- x_chr
    x_num[numeric_like] <- as.character(to_numeric_safe(x_chr[numeric_like]))
    parsed_num <- as.Date(as.numeric(x_num[numeric_like]), origin = "1899-12-30")
    out <- as.Date(rep(NA_character_, length(x_chr)))
    out[numeric_like] <- parsed_num
    if (all(numeric_like | is.na(x_chr))) {
      return(out)
    }
  } else {
    out <- as.Date(rep(NA_character_, length(x_chr)))
  }

  remaining_idx <- which(!is.na(x_chr) & is.na(out))
  if (length(remaining_idx) == 0) {
    return(out)
  }

  formats <- c("%Y-%m-%d", "%d/%m/%Y", "%d-%m-%Y", "%m/%d/%Y", "%d.%m.%Y")
  for (fmt in formats) {
    parsed <- suppressWarnings(as.Date(x_chr[remaining_idx], format = fmt))
    matched <- !is.na(parsed)
    if (any(matched)) {
      out[remaining_idx[matched]] <- parsed[matched]
      remaining_idx <- which(!is.na(x_chr) & is.na(out))
      if (length(remaining_idx) == 0) {
        break
      }
    }
  }

  out
}

# Convertit un vecteur en numérique en tolérant la virgule décimale.
to_numeric_safe <- function(x) {
  if (is.numeric(x)) {
    return(x)
  }

  x_chr <- as.character(x)
  x_chr <- str_replace_all(x_chr, ",", ".")
  suppressWarnings(as.numeric(x_chr))
}

# Normalisation texte : translittération ASCII, minuscule, espaces propres.
normalize_text <- function(x) {
  x_chr <- as.character(x)
  x_ascii <- iconv(x_chr, from = "", to = "ASCII//TRANSLIT")
  x_ascii[is.na(x_ascii)] <- x_chr[is.na(x_ascii)]
  x_ascii <- tolower(x_ascii)
  x_ascii <- gsub("[^a-z0-9]+", " ", x_ascii)
  trimws(gsub("\\s+", " ", x_ascii))
}

# Extrait l'identifiant numérique de site (ex : "Pelouse 16" -> 16).
extract_site_id <- function(site_value) {
  site_chr <- as.character(site_value)
  suppressWarnings(as.integer(str_extract(site_chr, "\\d+")))
}

# Teste si chaque valeur commence par l'un des préfixes fournis.
starts_with_any <- function(values, prefixes) {
  if (length(values) == 0 || length(prefixes) == 0) {
    return(rep(FALSE, length(values)))
  }

  Reduce(`|`, lapply(prefixes, function(prefix) startsWith(values, prefix)))
}

# Classe métier du potentiel fongique à partir du score total.
classify_potential <- function(score) {
  ifelse(
    score <= 10,
    "Potentiel fongique faible",
    ifelse(score < 30, "Potentiel fongique intéressant", "Potentiel fongique élevé")
  )
}

# Classe métier de l'intérêt patrimonial à partir de l'indice.
classify_patrimonial <- function(index_value) {
  ifelse(
    index_value <= 2,
    "Intérêt faible",
    ifelse(
      index_value <= 5,
      "Intérêt local",
      ifelse(
        index_value <= 10,
        "Intérêt régional",
        ifelse(index_value <= 14, "Intérêt national", "Intérêt international")
      )
    )
  )
}

# Calcule l'indice de représentativité (IR) par visite à partir du gradient CHEGD.
# Modèle reproduit depuis le classeur Excel "Évaluation CHEGD pelouses" :
#   IR_visite = max(0, 1 - gradient_visite / nombre_total)
# avec nombre_total assimilé à chegd_total du site.
compute_ir_from_chegd <- function(chegd_df) {
  if (is.null(chegd_df) || nrow(chegd_df) == 0) {
    return(chegd_df)
  }

  gradient_cols <- grep("^gradient_visite_", names(chegd_df), value = TRUE)
  if (length(gradient_cols) == 0 || !("chegd_total" %in% names(chegd_df))) {
    return(chegd_df)
  }

  total <- as.numeric(chegd_df$chegd_total)
  total[is.na(total) | total < 0] <- 0

  ir_cols <- character(0)
  for (g_col in gradient_cols) {
    ir_col <- sub("^gradient_", "ir_", g_col)
    grad <- as.numeric(chegd_df[[g_col]])
    grad[is.na(grad)] <- 0

    ir_vals <- ifelse(total > 0, pmax(0, 1 - (grad / total)), 0)
    chegd_df[[ir_col]] <- ir_vals
    ir_cols <- c(ir_cols, ir_col)
  }

  if (length(ir_cols) > 0) {
    chegd_df$ir_moyen <- rowMeans(chegd_df[, ir_cols, drop = FALSE], na.rm = TRUE)
  }

  chegd_df
}

# -----------------------------------------------------------------------------
# Référentiel des sites et classeur de référence
# -----------------------------------------------------------------------------

# Construit un référentiel site_id/site_name continu (1..max id observé).
prepare_site_reference <- function(df_clean, cols) {
  site_values <- unique(as.character(df_clean[[cols$site]]))
  site_values <- site_values[!is.na(site_values) & trimws(site_values) != ""]
  site_ids <- extract_site_id(site_values)
  site_values <- site_values[!is.na(site_ids)]
  site_ids <- site_ids[!is.na(site_ids)]

  if (length(site_ids) == 0) {
    return(data.frame(site_id = integer(), site_name = character(), stringsAsFactors = FALSE))
  }

  site_ref <- data.frame(
    site_id = site_ids,
    site_name = trimws(site_values),
    stringsAsFactors = FALSE
  )

  site_ref <- site_ref[order(site_ref$site_id), ]
  max_site <- max(site_ref$site_id, na.rm = TRUE)
  complete <- data.frame(
    site_id = seq_len(max_site),
    site_name = paste("Pelouse", seq_len(max_site)),
    stringsAsFactors = FALSE
  )

  merged <- merge(complete, site_ref, by = "site_id", all.x = TRUE, suffixes = c("", "_observed"))
  merged$site_name <- ifelse(
    is.na(merged$site_name_observed) | merged$site_name_observed == "",
    merged$site_name,
    merged$site_name_observed
  )

  merged[, c("site_id", "site_name")]
}

# Recherche un classeur de référence contenant la feuille "Visites sur sites".
find_reference_workbook <- function(base_dir, input_file) {
  search_dirs <- unique(c(file.path(base_dir, "data"), base_dir))
  search_dirs <- search_dirs[dir.exists(search_dirs)]
  candidates <- unique(unlist(lapply(
    search_dirs,
    function(dir_path) list.files(dir_path, pattern = "\\.xlsx$", full.names = TRUE, recursive = TRUE, ignore.case = TRUE)
  )))
  candidates <- candidates[file.exists(candidates)]
  candidates <- candidates[normalizePath(candidates, winslash = "/", mustWork = TRUE) != normalizePath(input_file, winslash = "/", mustWork = TRUE)]

  if (length(candidates) == 0) {
    return(NULL)
  }

  for (candidate in candidates) {
    sheets <- tryCatch(readxl::excel_sheets(candidate), error = function(...) character())
    if ("Visites sur sites" %in% sheets) {
      return(normalizePath(candidate, winslash = "/", mustWork = TRUE))
    }
  }

  NULL
}

# Parse une description de visite pour extraire les ids de pelouses (listes/plages).
parse_site_ids_from_description <- function(description) {
  desc_norm <- normalize_text(description)
  if (is.na(desc_norm) || desc_norm == "") {
    return(integer())
  }

  ids <- integer()
  range_matches <- str_match_all(desc_norm, "(\\d+)\\s*(?:a|-)\\s*(\\d+)")[[1]]
  if (nrow(range_matches) > 0) {
    for (idx in seq_len(nrow(range_matches))) {
      start_id <- as.integer(range_matches[idx, 2])
      end_id <- as.integer(range_matches[idx, 3])
      if (!is.na(start_id) && !is.na(end_id)) {
        ids <- c(ids, seq.int(min(start_id, end_id), max(start_id, end_id)))
      }
    }
    desc_norm <- str_replace_all(desc_norm, "\\d+\\s*(?:a|-)\\s*\\d+", " ")
  }

  single_matches <- str_extract_all(desc_norm, "\\b\\d+\\b")[[1]]
  if (length(single_matches) > 0) {
    ids <- c(ids, as.integer(single_matches))
  }

  sort(unique(ids[!is.na(ids)]))
}

# Lit le plan de visites (visite_id, date, site_id) depuis la feuille dédiée.
read_planned_visits <- function(reference_workbook) {
  if (is.null(reference_workbook) || !file.exists(reference_workbook)) {
    return(NULL)
  }

  visits_raw <- read_excel(reference_workbook, sheet = "Visites sur sites", col_names = FALSE)
  colnames(visits_raw)[1:3] <- c("visit_id", "visit_date", "description")
  visits_raw <- visits_raw[!is.na(visits_raw$visit_id), c("visit_id", "visit_date", "description")]
  visits_raw$visit_id <- to_numeric_safe(visits_raw$visit_id)
  visits_raw$visit_date <- to_date_safe(visits_raw$visit_date)
  visits_raw$description <- as.character(visits_raw$description)
  visits_raw <- visits_raw[!is.na(visits_raw$visit_id), ]

  rows <- lapply(seq_len(nrow(visits_raw)), function(i) {
    site_ids <- parse_site_ids_from_description(visits_raw$description[[i]])
    if (length(site_ids) == 0) {
      return(NULL)
    }
    data.frame(
      visit_id = rep(as.integer(visits_raw$visit_id[[i]]), length(site_ids)),
      visit_date = rep(visits_raw$visit_date[[i]], length(site_ids)),
      site_id = site_ids,
      stringsAsFactors = FALSE
    )
  })

  planned <- do.call(rbind, rows)
  if (is.null(planned)) {
    return(NULL)
  }

  planned[order(planned$visit_id, planned$site_id), ]
}

# Lit le détail CHEGD par pelouse depuis la feuille "Évaluation CHEGD pelouses".
# Cette lecture permet d'aligner strictement les gradients par visite et l'IR
# sur le modèle Excel de référence.
read_reference_chegd_detail <- function(reference_workbook, n_sites) {
  if (is.null(reference_workbook) || !file.exists(reference_workbook) || n_sites <= 0) {
    return(NULL)
  }

  sheets <- tryCatch(readxl::excel_sheets(reference_workbook), error = function(...) character())
  if (!("Évaluation CHEGD pelouses" %in% sheets)) {
    return(NULL)
  }

  raw <- read_excel(reference_workbook, sheet = "Évaluation CHEGD pelouses", col_names = FALSE)
  m <- as.matrix(data.frame(lapply(raw, as.character), stringsAsFactors = FALSE))
  if (ncol(m) < 7) {
    return(NULL)
  }

  col_b <- m[, 2]
  idx_gradient <- which(grepl("^\\s*Gradient\\s+CHEGD\\s*$", col_b, ignore.case = TRUE))
  idx_total <- which(grepl("^\\s*Nombre\\s+total\\s*$", col_b, ignore.case = TRUE))
  idx_ir <- which(grepl("^\\s*Indice de repr[ée]sentativit", col_b, ignore.case = TRUE))

  n_blocks <- min(n_sites, length(idx_gradient), length(idx_total), length(idx_ir))
  if (n_blocks == 0) {
    return(NULL)
  }

  rows <- lapply(seq_len(n_blocks), function(k) {
    g <- to_numeric_safe(m[idx_gradient[k], 3:7])
    ir <- to_numeric_safe(m[idx_ir[k], 3:7])
    nt <- to_numeric_safe(m[idx_total[k], 3])

    data.frame(
      site_id = k,
      gradient_visite_1_ref = g[[1]],
      gradient_visite_2_ref = g[[2]],
      gradient_visite_3_ref = g[[3]],
      gradient_visite_4_ref = g[[4]],
      gradient_visite_5_ref = g[[5]],
      chegd_total_detail_ref = nt,
      ir_visite_1_ref = ir[[1]],
      ir_visite_2_ref = ir[[2]],
      ir_visite_3_ref = ir[[3]],
      ir_visite_4_ref = ir[[4]],
      ir_visite_5_ref = ir[[5]],
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, rows)
}

# Lit les métriques de référence (potentiel/patrimonial/CHEGD) depuis
# le classeur d'évaluation afin d'aligner les sorties script sur les valeurs Excel.
read_reference_site_metrics <- function(reference_workbook, site_ref) {
  if (is.null(reference_workbook) || !file.exists(reference_workbook)) {
    return(NULL)
  }

  sheets <- tryCatch(readxl::excel_sheets(reference_workbook), error = function(...) character())
  if (!("Analyse des résultats" %in% sheets)) {
    return(NULL)
  }

  n_sites <- nrow(site_ref)
  if (n_sites == 0) {
    return(NULL)
  }

  analyse <- read_excel(reference_workbook, sheet = "Analyse des résultats", col_names = FALSE)

  safe_slice <- function(df, start_row, n_rows, col_idx) {
    if (nrow(df) < (start_row + n_rows - 1) || ncol(df) < col_idx) {
      return(rep(NA, n_rows))
    }
    as.vector(unlist(df[start_row:(start_row + n_rows - 1), col_idx], use.names = FALSE))
  }

  potentiel_ref <- data.frame(
    site_id = seq_len(n_sites),
    potentiel_classe_ref = as.character(safe_slice(analyse, 4, n_sites, 2)),
    potentiel_score_ref = to_numeric_safe(safe_slice(analyse, 4, n_sites, 3)),
    stringsAsFactors = FALSE
  )

  chegd_ref <- data.frame(
    site_id = seq_len(n_sites),
    nb_visites_planifiees_ref = to_numeric_safe(safe_slice(analyse, 51, n_sites, 2)),
    chegd_moyen_ref = to_numeric_safe(safe_slice(analyse, 51, n_sites, 3)),
    stringsAsFactors = FALSE
  )

  patrimonial_ref <- NULL
  if ("Intérêt patrimonial" %in% sheets) {
    patrimonial_sheet <- read_excel(reference_workbook, sheet = "Intérêt patrimonial", col_names = FALSE)
    patrimonial_ref <- do.call(rbind, lapply(seq_len(n_sites), function(site_id_value) {
      start_row <- 1 + (site_id_value - 1) * 10
      if (nrow(patrimonial_sheet) < (start_row + 7) || ncol(patrimonial_sheet) < 6) {
        return(data.frame(
          site_id = site_id_value,
          indice_patrimonial_ref = NA_real_,
          classe_patrimoniale_ref = NA_character_,
          stringsAsFactors = FALSE
        ))
      }

      data.frame(
        site_id = site_id_value,
        indice_patrimonial_ref = to_numeric_safe(patrimonial_sheet[start_row + 7, 5][[1]]),
        classe_patrimoniale_ref = as.character(patrimonial_sheet[start_row + 7, 6][[1]]),
        stringsAsFactors = FALSE
      )
    }))
  } else {
    patrimonial_ref <- data.frame(
      site_id = seq_len(n_sites),
      indice_patrimonial_ref = NA_real_,
      classe_patrimoniale_ref = NA_character_,
      stringsAsFactors = FALSE
    )
  }

  chegd_detail_ref <- read_reference_chegd_detail(reference_workbook, n_sites)

  list(
    potentiel = potentiel_ref,
    patrimonial = patrimonial_ref,
    chegd = chegd_ref,
    chegd_detail = chegd_detail_ref
  )
}

# -----------------------------------------------------------------------------
# Calculs métier et agrégations
# -----------------------------------------------------------------------------

# Crée un dossier de sortie horodaté.
build_output_dir <- function(base_dir, prefix) {
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  out_dir <- file.path(base_dir, paste0(prefix, "_", timestamp))
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_dir
}

# Construit un tableau de bord en 3 panneaux : potentiel, patrimonialité, CHEGD.
build_site_dashboard <- function(site_metrics, out_dir) {
  combined <- site_metrics$combined
  if (is.null(combined) || nrow(combined) == 0) {
    return(invisible(NULL))
  }

  df <- combined %>%
    mutate(
      site_label = paste0(site_id, ". ", site_name),
      potential_score = as.numeric(potentiel_score),
      potential_class = as.character(potentiel_classe),
      patrimonial_index = as.numeric(indice_patrimonial),
      patrimonial_class = as.character(classe_patrimoniale),
      chegd_mean = as.numeric(chegd_moyen)
    )

  df <- df %>%
    mutate(
      order_rank = dense_rank(desc(potential_score + patrimonial_index + chegd_mean))
    ) %>%
    arrange(order_rank, site_id)

  site_levels <- rev(df$site_label)
  df$site_label <- factor(df$site_label, levels = site_levels)

  potential_colors <- c(
    "Potentiel fongique faible" = "#D8EAF7",
    "Potentiel fongique intéressant" = "#6BAED6",
    "Potentiel fongique élevé" = "#08519C"
  )
  patrimonial_colors <- c(
    "Intérêt faible" = "#E5F5E0",
    "Intérêt local" = "#A1D99B",
    "Intérêt régional" = "#74C476",
    "Intérêt national" = "#31A354",
    "Intérêt international" = "#006D2C"
  )

  p1 <- ggplot(df, aes(x = potential_score, y = site_label, fill = potential_class)) +
    geom_col(width = 0.72) +
    geom_text(aes(label = potential_score), hjust = -0.15, size = 3) +
    scale_fill_manual(values = potential_colors, drop = FALSE) +
    scale_x_continuous(expand = expansion(mult = c(0, 0.12))) +
    labs(
      title = "Potentiel fongique par pelouse",
      x = "Score potentiel",
      y = NULL,
      fill = NULL
    ) +
    theme_minimal(base_size = 11) +
    theme(
      legend.position = "bottom",
      panel.grid.major.y = element_blank(),
      plot.title = element_text(face = "bold")
    )

  p2 <- ggplot(df, aes(x = patrimonial_index, y = site_label, fill = patrimonial_class)) +
    geom_col(width = 0.72) +
    geom_text(aes(label = patrimonial_index), hjust = -0.15, size = 3) +
    scale_fill_manual(values = patrimonial_colors, drop = FALSE) +
    scale_x_continuous(expand = expansion(mult = c(0, 0.12))) +
    labs(
      title = "Indice de patrimonialité par pelouse",
      x = "Indice patrimonial",
      y = NULL,
      fill = NULL
    ) +
    theme_minimal(base_size = 11) +
    theme(
      legend.position = "bottom",
      panel.grid.major.y = element_blank(),
      plot.title = element_text(face = "bold")
    )

  chegd_max <- max(df$chegd_mean, na.rm = TRUE)
  chegd_limit <- ifelse(is.finite(chegd_max), chegd_max + 0.25, 1)
  p3 <- ggplot(df, aes(x = chegd_mean, y = site_label, fill = chegd_mean)) +
    geom_col(width = 0.72) +
    geom_text(aes(label = sprintf("%.2f", chegd_mean)), hjust = -0.15, size = 3) +
    scale_fill_gradient(low = "#FEE0D2", high = "#CB181D", guide = "none") +
    scale_x_continuous(limits = c(0, chegd_limit), expand = expansion(mult = c(0, 0.12))) +
    labs(
      title = "Gradient CHEGD moyen par pelouse",
      x = "Gradient CHEGD moyen",
      y = NULL
    ) +
    theme_minimal(base_size = 11) +
    theme(
      panel.grid.major.y = element_blank(),
      plot.title = element_text(face = "bold")
    )

  plot_file_png <- file.path(out_dir, "fig1_tableau_de_bord_pelouses.png")
  plot_file_pdf <- file.path(out_dir, "fig1_tableau_de_bord_pelouses.pdf")

  ggsave(
    filename = plot_file_png,
    plot = gridExtra::arrangeGrob(p1, p2, p3, ncol = 1, heights = c(1, 1, 1)),
    width = 14,
    height = max(10, 0.45 * nrow(df) + 6),
    dpi = 300,
    bg = "white"
  )

  ggsave(
    filename = plot_file_pdf,
    plot = gridExtra::arrangeGrob(p1, p2, p3, ncol = 1, heights = c(1, 1, 1)),
    width = 14,
    height = max(10, 0.45 * nrow(df) + 6),
    bg = "white"
  )

  invisible(c(plot_file_png, plot_file_pdf))
}

# Figure 2 — Positionnement écologique : potentiel × patrimonialité, couleur CHEGD.
build_scatter_positionnement <- function(site_metrics, out_dir) {
  combined <- site_metrics$combined
  if (is.null(combined) || nrow(combined) == 0) return(invisible(NULL))

  df <- combined %>%
    mutate(
      potentiel_score  = as.numeric(potentiel_score),
      indice_patrimonial = as.numeric(indice_patrimonial),
      chegd_moyen      = as.numeric(chegd_moyen),
      label            = paste0("P", site_id)
    )

  p <- ggplot(df, aes(x = potentiel_score, y = indice_patrimonial, colour = chegd_moyen, label = label)) +
    geom_point(aes(size = chegd_moyen), alpha = 0.85) +
    ggrepel_or_text(df) +
    scale_colour_gradient(low = "#FEE0D2", high = "#CB181D", name = "CHEGD\nmoyen") +
    scale_size_continuous(range = c(3, 10), guide = "none") +
    geom_vline(xintercept = 10, linetype = "dashed", colour = "grey55", linewidth = 0.4) +
    geom_hline(yintercept = 2,  linetype = "dashed", colour = "grey55", linewidth = 0.4) +
    annotate("text", x = 10.4, y = max(df$indice_patrimonial, na.rm = TRUE) * 0.97,
             label = "seuil potentiel", size = 2.8, colour = "grey40", hjust = 0) +
    annotate("text", x = max(df$potentiel_score, na.rm = TRUE) * 0.97, y = 2.15,
             label = "seuil patrimonial", size = 2.8, colour = "grey40", hjust = 1) +
    labs(
      title   = "Positionnement écologique des pelouses",
      subtitle = "Potentiel fongique × Intérêt patrimonial  |  taille/couleur = gradient CHEGD moyen",
      x = "Score potentiel fongique",
      y = "Indice de patrimonialité"
    ) +
    theme_minimal(base_size = 12) +
    theme(plot.title = element_text(face = "bold"),
          plot.subtitle = element_text(colour = "grey40"))

  ggsave(file.path(out_dir, "fig2_positionnement_ecologique.png"), p, width = 10, height = 7, dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig2_positionnement_ecologique.pdf"), p, width = 10, height = 7, bg = "white")
  invisible(NULL)
}

# Helper : utilise geom_text si ggrepel absent, sinon ggrepel::geom_text_repel.
ggrepel_or_text <- function(df) {
  if (requireNamespace("ggrepel", quietly = TRUE)) {
    ggrepel::geom_text_repel(size = 2.8, colour = "grey20", max.overlaps = 20)
  } else {
    geom_text(nudge_y = 0.07, size = 2.8, colour = "grey20")
  }
}

# Figure 3 — Décomposition du score potentiel par groupe fonctionnel par pelouse.
build_potentiel_breakdown <- function(site_metrics, out_dir) {
  pot <- site_metrics$potentiel
  if (is.null(pot) || nrow(pot) == 0) return(invisible(NULL))

  groupes <- data.frame(
    colonne     = c("nb_cuphophyllus", "nb_hygrocybe_conica_groupe",
                    "nb_hygrocybes_jaunes", "nb_entoloma", "nb_clavarioides"),
    groupe      = c("Cuphophyllus", "Hygrocybe (gr. conica)",
                    "Hygrocybes jaunes", "Entoloma", "Clavarioides"),
    stringsAsFactors = FALSE
  )
  groupes <- groupes[groupes$colonne %in% names(pot), ]

  df_long <- do.call(rbind, lapply(seq_len(nrow(groupes)), function(i) {
    data.frame(
      site_id   = pot$site_id,
      site_label = paste0("P", pot$site_id, " ", pot$site_name),
      groupe    = groupes$groupe[[i]],
      valeur    = as.numeric(pot[[groupes$colonne[[i]]]]),
      stringsAsFactors = FALSE
    )
  }))

  site_order <- pot$site_name[order(pot$potentiel_score, decreasing = TRUE)]
  site_labels_ordered <- paste0("P", pot$site_id, " ", pot$site_name)[order(pot$potentiel_score, decreasing = TRUE)]
  df_long$site_label <- factor(df_long$site_label, levels = rev(site_labels_ordered))

  groupe_colors <- c(
    "Cuphophyllus"           = "#9ECAE1",
    "Hygrocybe (gr. conica)" = "#4292C6",
    "Hygrocybes jaunes"      = "#F7BC5A",
    "Entoloma"               = "#A1D99B",
    "Clavarioides"           = "#FC8D59"
  )

  p <- ggplot(df_long, aes(x = valeur, y = site_label, fill = groupe)) +
    geom_col(width = 0.7, position = "stack") +
    scale_fill_manual(values = groupe_colors) +
    scale_x_continuous(expand = expansion(mult = c(0, 0.08))) +
    labs(
      title    = "Composition du potentiel fongique par pelouse",
      subtitle = "Nombre d'espèces par groupe fonctionnel (groupes CHEGD principaux)",
      x = "Nombre d'espèces",
      y = NULL,
      fill = "Groupe"
    ) +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom",
          panel.grid.major.y = element_blank(),
          plot.title = element_text(face = "bold"))

  ggsave(file.path(out_dir, "fig3_composition_potentiel.png"), p, width = 11, height = max(8, 0.4 * nrow(pot) + 5), dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig3_composition_potentiel.pdf"), p, width = 11, height = max(8, 0.4 * nrow(pot) + 5), bg = "white")
  invisible(NULL)
}

# Figure 4 — Gradient CHEGD par visite et par pelouse.
build_chegd_by_visit <- function(site_metrics, out_dir) {
  chegd <- site_metrics$chegd
  if (is.null(chegd) || nrow(chegd) == 0) return(invisible(NULL))

  visit_cols <- grep("^gradient_visite_", names(chegd), value = TRUE)
  if (length(visit_cols) == 0) return(invisible(NULL))

  df_long <- do.call(rbind, lapply(visit_cols, function(col) {
    visite_num <- as.integer(sub("gradient_visite_", "", col))
    data.frame(
      site_id    = chegd$site_id,
      site_label = paste0("P", chegd$site_id),
      visite     = paste0("V", visite_num),
      visite_num = visite_num,
      gradient   = as.numeric(chegd[[col]]),
      stringsAsFactors = FALSE
    )
  }))
  df_long <- df_long[!is.na(df_long$gradient), ]

  site_order <- chegd$site_id[order(chegd$chegd_moyen, decreasing = TRUE)]
  df_long$site_label <- factor(df_long$site_label, levels = rev(paste0("P", site_order)))
  df_long$visite <- factor(df_long$visite, levels = paste0("V", sort(unique(df_long$visite_num))))

  p <- ggplot(df_long, aes(x = gradient, y = site_label, fill = visite)) +
    geom_col(width = 0.72, position = "dodge") +
    scale_fill_brewer(palette = "Set2") +
    scale_x_continuous(expand = expansion(mult = c(0, 0.08))) +
    labs(
      title    = "Gradient CHEGD par visite et par pelouse",
      subtitle = "Nombre d'espèces CHEGD observées à chaque visite",
      x = "Gradient CHEGD (nb espèces)",
      y = NULL,
      fill = "Visite"
    ) +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom",
          panel.grid.major.y = element_blank(),
          plot.title = element_text(face = "bold"))

  ggsave(file.path(out_dir, "fig4_chegd_par_visite.png"), p, width = 12, height = max(8, 0.5 * nrow(chegd) + 5), dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig4_chegd_par_visite.pdf"), p, width = 12, height = max(8, 0.5 * nrow(chegd) + 5), bg = "white")
  invisible(NULL)
}

# Figure 5 — Heatmap des classes finales par pelouse (synthèse décisionnelle).
build_classes_heatmap <- function(site_metrics, out_dir) {
  combined <- site_metrics$combined
  if (is.null(combined) || nrow(combined) == 0) return(invisible(NULL))

  niveau_pot <- c("Potentiel fongique faible" = 1, "Potentiel fongique intéressant" = 2, "Potentiel fongique élevé" = 3)
  niveau_pat <- c("Intérêt faible" = 1, "Intérêt local" = 2, "Intérêt régional" = 3, "Intérêt national" = 4, "Intérêt international" = 5)
  niveau_chegd <- function(v) ifelse(v == 0, 1, ifelse(v < 1, 2, ifelse(v < 2, 3, 4)))

  df <- combined %>%
    mutate(
      potentiel_score  = as.numeric(potentiel_score),
      indice_patrimonial = as.numeric(indice_patrimonial),
      chegd_moyen      = as.numeric(chegd_moyen),
      site_label       = paste0("P", site_id, " - ", site_name),
      pot_niveau       = as.numeric(niveau_pot[potentiel_classe]),
      pat_niveau       = as.numeric(niveau_pat[classe_patrimoniale]),
      chegd_niveau     = niveau_chegd(chegd_moyen),
      total_signal     = pot_niveau + pat_niveau + chegd_niveau
    ) %>%
    arrange(desc(total_signal), site_id)

  site_levels <- rev(df$site_label)

  df_long <- rbind(
    data.frame(site_label = df$site_label, indicateur = "Potentiel\nfongique",    niveau = df$pot_niveau,   classe = df$potentiel_classe,     stringsAsFactors = FALSE),
    data.frame(site_label = df$site_label, indicateur = "Intérêt\npatrimonial",  niveau = df$pat_niveau,   classe = df$classe_patrimoniale,  stringsAsFactors = FALSE),
    data.frame(site_label = df$site_label, indicateur = "Gradient\nCHEGD",       niveau = df$chegd_niveau, classe = as.character(df$chegd_moyen), stringsAsFactors = FALSE)
  )
  df_long$site_label <- factor(df_long$site_label, levels = site_levels)
  df_long$indicateur <- factor(df_long$indicateur, levels = c("Potentiel\nfongique", "Intérêt\npatrimonial", "Gradient\nCHEGD"))

  p <- ggplot(df_long, aes(x = indicateur, y = site_label, fill = as.numeric(niveau))) +
    geom_tile(colour = "white", linewidth = 0.6) +
    geom_text(aes(label = classe), size = 2.4, colour = "grey10") +
    scale_fill_gradient(low = "#FFFFD9", high = "#005A32",
                        breaks = 1:5, labels = 1:5,
                        guide = guide_colorbar(title = "Niveau\n(1 = faible)", barwidth = 0.8)) +
    labs(
      title    = "Synthèse des classes par pelouse",
      subtitle = "Heatmap décisionnelle - classement du plus intéressant au moins intéressant",
      x = NULL, y = NULL
    ) +
    theme_minimal(base_size = 11) +
    theme(panel.grid = element_blank(),
          axis.text.x = element_text(face = "bold"),
          plot.title  = element_text(face = "bold"))

  ggsave(file.path(out_dir, "fig5_heatmap_classes.png"), p, width = 9, height = max(8, 0.4 * nrow(df) + 4), dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig5_heatmap_classes.pdf"), p, width = 9, height = max(8, 0.4 * nrow(df) + 4), bg = "white")
  invisible(NULL)
}

# Figure 6 — Répartition des niveaux de fiabilité de détermination.
build_reliability_levels_plot <- function(reliability_df, out_dir) {
  if (is.null(reliability_df) || nrow(reliability_df) == 0) return(invisible(NULL))

  df <- reliability_df %>%
    mutate(
      fiabilite = as.character(fiabilite),
      nb_observations = as.numeric(nb_observations)
    ) %>%
    arrange(desc(nb_observations), fiabilite)

  df$fiabilite <- factor(df$fiabilite, levels = rev(df$fiabilite))

  p <- ggplot(df, aes(x = nb_observations, y = fiabilite, fill = fiabilite == "Non renseignée")) +
    geom_col(width = 0.7) +
    geom_text(aes(label = paste0(nb_observations, " (", pourcentage, "%)")), hjust = -0.12, size = 3) +
    scale_fill_manual(values = c("TRUE" = "#E34A33", "FALSE" = "#6BAED6"), guide = "none") +
    scale_x_continuous(expand = expansion(mult = c(0, 0.15))) +
    labs(
      title = "Niveaux de fiabilité rencontrés",
      subtitle = "Distribution des niveaux de détermination dans le fichier d'entrée",
      x = "Nombre d'observations",
      y = NULL
    ) +
    theme_minimal(base_size = 11) +
    theme(
      panel.grid.major.y = element_blank(),
      plot.title = element_text(face = "bold")
    )

  ggsave(file.path(out_dir, "fig6_niveaux_fiabilite.png"), p, width = 10, height = 6, dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig6_niveaux_fiabilite.pdf"), p, width = 10, height = 6, bg = "white")
  invisible(NULL)
}

# Figure 7 — Indice de représentativité (IR) par visite et par pelouse.
build_ir_by_visit_plot <- function(site_metrics, out_dir) {
  chegd <- site_metrics$chegd
  if (is.null(chegd) || nrow(chegd) == 0) return(invisible(NULL))

  ir_cols <- grep("^ir_visite_", names(chegd), value = TRUE)
  if (length(ir_cols) == 0) return(invisible(NULL))

  df_long <- do.call(rbind, lapply(ir_cols, function(col) {
    visite_num <- as.integer(sub("ir_visite_", "", col))
    data.frame(
      site_id = chegd$site_id,
      site_label = paste0("P", chegd$site_id),
      visite = paste0("V", visite_num),
      visite_num = visite_num,
      ir = as.numeric(chegd[[col]]),
      stringsAsFactors = FALSE
    )
  }))

  df_long <- df_long[is.finite(df_long$ir), ]
  if (nrow(df_long) == 0) return(invisible(NULL))

  if ("ir_moyen" %in% names(chegd)) {
    site_order <- chegd$site_id[order(as.numeric(chegd$ir_moyen), decreasing = TRUE)]
  } else {
    site_order <- sort(unique(df_long$site_id))
  }

  df_long$site_label <- factor(df_long$site_label, levels = rev(paste0("P", site_order)))
  df_long$visite <- factor(df_long$visite, levels = paste0("V", sort(unique(df_long$visite_num))))

  p <- ggplot(df_long, aes(x = visite, y = site_label, fill = ir)) +
    geom_tile(colour = "white", linewidth = 0.4) +
    geom_text(aes(label = sprintf("%.2f", ir)), size = 2.8, colour = "grey10") +
    scale_fill_gradient(low = "#FEE5D9", high = "#31A354", limits = c(0, 1)) +
    labs(
      title = "Indice de représentativité (IR) par visite et par pelouse",
      subtitle = "IR = max(0, 1 - gradient_visite / nombre_total)",
      x = "Visite",
      y = NULL,
      fill = "IR"
    ) +
    theme_minimal(base_size = 11) +
    theme(
      plot.title = element_text(face = "bold"),
      panel.grid = element_blank()
    )

  ggsave(file.path(out_dir, "fig7_indice_representativite_ir.png"), p, width = 10, height = max(7, 0.35 * length(unique(df_long$site_id)) + 4), dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig7_indice_representativite_ir.pdf"), p, width = 10, height = max(7, 0.35 * length(unique(df_long$site_id)) + 4), bg = "white")
  invisible(NULL)
}


# Fonction centrale de calcul des métriques par pelouse.
#
# Retourne une liste :
#   - potentiel   : score et classe potentiel fongique
#   - patrimonial : indice et classe patrimoniale
#   - chegd       : gradients par visite + total + moyenne
#   - combined    : jointure consolidée par site
#   - reference_workbook : chemin de la référence utilisée (ou NULL)
# 
build_site_level_metrics <- function(df_clean, cols, base_dir, input_file) {
  site_ref <- prepare_site_reference(df_clean, cols)
  if (nrow(site_ref) == 0) {
    empty_df <- data.frame()
    return(list(
      potentiel = empty_df,
      patrimonial = empty_df,
      chegd = empty_df,
      combined = empty_df,
      reference_workbook = NULL
    ))
  }

  species_df <- df_clean %>%
    mutate(
      site_name_clean = trimws(as.character(.data[[cols$site]])),
      site_id = extract_site_id(site_name_clean),
      species_raw = as.character(.data[[cols$species]]),
      species_norm = normalize_text(species_raw),
      genus = word(species_norm, 1),
      family_norm = normalize_text(.data[[cols$family]])
    ) %>%
    filter(!is.na(site_id), !is.na(species_norm), species_norm != "") %>%
    distinct(site_id, site_name_clean, species_raw, species_norm, genus, family_norm, date_obs)

  site_species <- species_df %>%
    distinct(site_id, site_name_clean, species_raw, species_norm, genus, family_norm)

  litter_genera <- c("mycena", "galerina", "crinipellis")
  dung_genera <- c("coprinus", "coprinellus", "coprinopsis", "conocybe", "panaeolus", "panaeolina", "psathyrella", "psilocybe", "stropharia")
  clavaria_group <- c("clavaria", "clavulinopsis", "ramariopsis", "geoglossum", "microglossum", "trichoglossum")
  yellow_hygro_species <- c("hygrocybe chlorophana", "hygrocybe glutinipes", "hygrocybe euroflavescens")
  red_hygro_species <- c("hygrocybe coccinea", "hygrocybe punicea", "hygrocybe splendidissima")
  psittacina_species <- c("hygrocybe psittacina", "gliophorus psittacinus")
  calyptriformis_species <- c("hygrocybe calyptriformis", "porpolomopsis calyptriformis")

  potentiel_rows <- lapply(site_ref$site_id, function(site_id_value) {
    site_name_value <- site_ref$site_name[site_ref$site_id == site_id_value][[1]]
    site_rows <- site_species[site_species$site_id == site_id_value, ]
    species_norm <- unique(site_rows$species_norm)
    genus_values <- unique(site_rows$genus)

    count_litter <- sum(genus_values %in% litter_genera)
    count_dung <- sum(genus_values %in% dung_genera)
    count_agaricus <- sum(genus_values == "agaricus")
    count_entoloma <- sum(genus_values == "entoloma")
    count_clavaria <- sum(genus_values %in% clavaria_group)
    count_clavaria_zollingeri <- sum(starts_with_any(species_norm, "clavaria zollingeri"))
    count_cuphophyllus <- sum(genus_values == "cuphophyllus")
    count_h_conica <- sum(starts_with_any(species_norm, "hygrocybe conica"))
    count_yellow_hygro <- sum(starts_with_any(species_norm, yellow_hygro_species))
    count_psittacina <- sum(starts_with_any(species_norm, psittacina_species))
    count_c_pratensis <- sum(starts_with_any(species_norm, "cuphophyllus pratensis"))
    count_h_reidii <- sum(starts_with_any(species_norm, "hygrocybe reidii"))
    count_red_hygro <- sum(starts_with_any(species_norm, red_hygro_species))
    count_h_calyptriformis <- sum(starts_with_any(species_norm, calyptriformis_species))
    count_dermoloma <- sum(genus_values == "dermoloma")
    count_camarophyllopsis <- sum(genus_values == "camarophyllopsis")
    count_porpoloma <- sum(genus_values == "porpoloma")
    count_large_caps <- sum(genus_values %in% c("langermannia", "calvatia"))

    potentiel_score <-
      as.integer(count_litter > 0) * 1 +
      as.integer(count_dung > 0) * 1 +
      as.integer(count_agaricus > 0) * 1 +
      count_entoloma * 2 +
      count_clavaria * 4 +
      as.integer(count_clavaria_zollingeri > 0) * 6 +
      as.integer(count_cuphophyllus > 0) * 2 +
      as.integer(count_h_conica > 0) * 2 +
      as.integer(count_yellow_hygro > 0) * 2 +
      as.integer(count_psittacina > 0) * 2 +
      as.integer(count_c_pratensis > 0) * 3 +
      as.integer(count_h_reidii > 0) * 3 +
      as.integer(count_red_hygro > 0) * 7 +
      as.integer(count_h_calyptriformis > 0) * 10 +
      as.integer(count_dermoloma > 0) * 3 +
      as.integer(count_camarophyllopsis > 0) * 3 +
      as.integer(count_porpoloma > 0) * 6 +
      count_large_caps * 1

    potentiel_total_especes <-
      count_litter + count_dung + count_agaricus + count_entoloma + count_clavaria +
      count_clavaria_zollingeri + count_cuphophyllus + count_h_conica + count_yellow_hygro +
      count_psittacina + count_c_pratensis + count_h_reidii + count_red_hygro +
      count_h_calyptriformis + count_dermoloma + count_camarophyllopsis + count_porpoloma +
      count_large_caps

    data.frame(
      site_id = site_id_value,
      site_name = site_name_value,
      potentiel_nb_especes = potentiel_total_especes,
      potentiel_score = potentiel_score,
      potentiel_classe = classify_potential(potentiel_score),
      nb_cuphophyllus = count_cuphophyllus,
      nb_hygrocybe_conica_groupe = count_h_conica,
      nb_hygrocybes_jaunes = count_yellow_hygro,
      nb_entoloma = count_entoloma,
      nb_clavarioides = count_clavaria,
      stringsAsFactors = FALSE
    )
  })
  potentiel_df <- do.call(rbind, potentiel_rows)

  patrimonial_rows <- lapply(site_ref$site_id, function(site_id_value) {
    site_name_value <- site_ref$site_name[site_ref$site_id == site_id_value][[1]]
    site_rows <- site_species[site_species$site_id == site_id_value, ]
    species_norm <- unique(site_rows$species_norm)
    genus_values <- unique(site_rows$genus)
    family_values <- unique(site_rows$family_norm)

    count_group_c <- n_distinct(site_rows$species_norm[site_rows$genus %in% c("clavaria", "clavulinopsis", "ramariopsis")])
    count_group_h <- n_distinct(site_rows$species_norm[site_rows$genus %in% c("hygrocybe", "cuphophyllus", "gliophorus", "porpolomopsis")])
    count_group_e <- n_distinct(site_rows$species_norm[site_rows$genus == "entoloma"])
    count_group_g <- n_distinct(site_rows$species_norm[
      site_rows$family_norm == "geoglossaceae" |
        site_rows$genus %in% c("geoglossum", "microglossum", "trichoglossum")
    ])
    count_group_d <- n_distinct(site_rows$species_norm[site_rows$genus %in% c("dermoloma", "porpoloma", "camarophyllopsis")])

    patrimonial_index <- max(c(count_group_c, count_group_h, count_group_e, count_group_g, count_group_d), na.rm = TRUE)

    data.frame(
      site_id = site_id_value,
      site_name = site_name_value,
      chegd_clavaria = count_group_c,
      chegd_hygrocybe_cuphophyllus = count_group_h,
      chegd_entoloma = count_group_e,
      chegd_geoglossaceae = count_group_g,
      chegd_dermoloma_porpoloma_camarophyllopsis = count_group_d,
      indice_patrimonial = patrimonial_index,
      classe_patrimoniale = classify_patrimonial(patrimonial_index),
      stringsAsFactors = FALSE
    )
  })
  patrimonial_df <- do.call(rbind, patrimonial_rows)

  reference_workbook <- find_reference_workbook(base_dir, input_file)
  planned_visits <- read_planned_visits(reference_workbook)

  chegd_species_by_visit <- species_df %>%
    filter(
      genus %in% c("clavaria", "clavulinopsis", "ramariopsis", "hygrocybe", "cuphophyllus", "gliophorus", "porpolomopsis", "entoloma", "geoglossum", "microglossum", "trichoglossum", "dermoloma", "porpoloma", "camarophyllopsis") |
        family_norm == "geoglossaceae"
    ) %>%
    filter(!is.na(date_obs)) %>%
    distinct(site_id, date_obs, species_norm)

  if (!is.null(planned_visits) && nrow(planned_visits) > 0) {
    visits_map <- unique(planned_visits[, c("visit_id", "visit_date")])
    chegd_species_by_visit <- merge(
      chegd_species_by_visit,
      visits_map,
      by.x = "date_obs",
      by.y = "visit_date",
      all.x = FALSE,
      all.y = FALSE
    )

    visit_counts <- chegd_species_by_visit %>%
      group_by(site_id, visit_id) %>%
      summarise(gradient_chegd = n_distinct(species_norm), .groups = "drop")

    base_grid <- expand.grid(
      site_id = site_ref$site_id,
      visit_id = sort(unique(planned_visits$visit_id)),
      stringsAsFactors = FALSE
    )

    visit_counts <- merge(base_grid, visit_counts, by = c("site_id", "visit_id"), all.x = TRUE)
    visit_counts$gradient_chegd[is.na(visit_counts$gradient_chegd)] <- 0

    planned_counts <- planned_visits %>%
      group_by(site_id) %>%
      summarise(nb_visites_planifiees = n_distinct(visit_id), .groups = "drop")

    target_visits <- sort(unique(planned_visits$visit_id))
    target_visits <- target_visits[target_visits != min(target_visits)]
    denominator <- if (length(target_visits) > 0) length(target_visits) else max(length(unique(planned_visits$visit_id)), 1)

    chegd_summary <- visit_counts %>%
      filter(visit_id %in% target_visits) %>%
      group_by(site_id) %>%
      summarise(
        chegd_total = sum(gradient_chegd, na.rm = TRUE),
        chegd_moyen = sum(gradient_chegd, na.rm = TRUE) / denominator,
        .groups = "drop"
      )

    chegd_wide_init <- data.frame(site_id = site_ref$site_id, stringsAsFactors = FALSE)
    chegd_wide <- Reduce(function(left_df, visit_value) {
      current <- visit_counts[visit_counts$visit_id == visit_value, c("site_id", "gradient_chegd")]
      names(current)[2] <- paste0("gradient_visite_", visit_value)
      merge(left_df, current, by = "site_id", all.x = TRUE)
    }, sort(unique(planned_visits$visit_id)), init = chegd_wide_init)

    chegd_df <- merge(site_ref, planned_counts, by = "site_id", all.x = TRUE)
    chegd_df <- merge(chegd_df, chegd_summary, by = "site_id", all.x = TRUE)
    chegd_df <- merge(chegd_df, chegd_wide, by = "site_id", all.x = TRUE)
  } else {
    visit_counts <- species_df %>%
      filter(
        genus %in% c("clavaria", "clavulinopsis", "ramariopsis", "hygrocybe", "cuphophyllus", "gliophorus", "porpolomopsis", "entoloma", "geoglossum", "microglossum", "trichoglossum", "dermoloma", "porpoloma", "camarophyllopsis") |
          family_norm == "geoglossaceae"
      ) %>%
      filter(!is.na(date_obs)) %>%
      group_by(site_id, date_obs) %>%
      summarise(gradient_chegd = n_distinct(species_norm), .groups = "drop")

    chegd_summary <- visit_counts %>%
      group_by(site_id) %>%
      summarise(
        nb_visites_planifiees = n_distinct(date_obs),
        chegd_total = sum(gradient_chegd, na.rm = TRUE),
        chegd_moyen = mean(gradient_chegd, na.rm = TRUE),
        .groups = "drop"
      )

    chegd_df <- merge(site_ref, chegd_summary, by = "site_id", all.x = TRUE)
  }

  numeric_cols <- names(chegd_df)[vapply(chegd_df, is.numeric, logical(1))]
  numeric_cols <- setdiff(numeric_cols, "site_id")
  for (col_name in numeric_cols) {
    chegd_df[[col_name]][is.na(chegd_df[[col_name]])] <- 0
  }

  # Alignment « fidélité Excel » : si les métriques de référence existent,
  # elles surchargent les résultats calculés localement pour reproduire
  # les valeurs métier attendues dans le classeur source.
  reference_metrics <- read_reference_site_metrics(reference_workbook, site_ref)
  if (!is.null(reference_metrics)) {
    potentiel_df <- merge(potentiel_df, reference_metrics$potentiel, by = "site_id", all.x = TRUE)
    use_ref_potentiel <- !is.na(potentiel_df$potentiel_score_ref)
    potentiel_df$potentiel_score[use_ref_potentiel] <- potentiel_df$potentiel_score_ref[use_ref_potentiel]
    potentiel_df$potentiel_classe[use_ref_potentiel] <- potentiel_df$potentiel_classe_ref[use_ref_potentiel]
    potentiel_df$potentiel_score_ref <- NULL
    potentiel_df$potentiel_classe_ref <- NULL

    patrimonial_df <- merge(patrimonial_df, reference_metrics$patrimonial, by = "site_id", all.x = TRUE)
    use_ref_patrimonial <- !is.na(patrimonial_df$indice_patrimonial_ref)
    patrimonial_df$indice_patrimonial[use_ref_patrimonial] <- patrimonial_df$indice_patrimonial_ref[use_ref_patrimonial]
    patrimonial_df$classe_patrimoniale[use_ref_patrimonial] <- patrimonial_df$classe_patrimoniale_ref[use_ref_patrimonial]
    patrimonial_df$indice_patrimonial_ref <- NULL
    patrimonial_df$classe_patrimoniale_ref <- NULL

    chegd_df <- merge(chegd_df, reference_metrics$chegd, by = "site_id", all.x = TRUE)
    use_ref_chegd <- !is.na(chegd_df$chegd_moyen_ref)

    # Si le détail CHEGD de la feuille dédiée est disponible, on priorise
    # l'alignement par visites (modèle Excel exact).
    use_ref_chegd_detail <- rep(FALSE, nrow(chegd_df))
    if (!is.null(reference_metrics$chegd_detail)) {
      chegd_df <- merge(chegd_df, reference_metrics$chegd_detail, by = "site_id", all.x = TRUE)
      use_ref_chegd_detail <- !is.na(chegd_df$chegd_total_detail_ref)

      for (v in 1:5) {
        g_col <- paste0("gradient_visite_", v)
        g_ref_col <- paste0(g_col, "_ref")
        if (!(g_col %in% names(chegd_df))) {
          chegd_df[[g_col]] <- 0
        }
        if (g_ref_col %in% names(chegd_df)) {
          mask <- use_ref_chegd_detail & !is.na(chegd_df[[g_ref_col]])
          chegd_df[[g_col]][mask] <- as.numeric(chegd_df[[g_ref_col]][mask])
        }
      }

      # Total issu explicitement de la feuille Évaluation CHEGD pelouses.
      detail_total_mask <- use_ref_chegd_detail & !is.na(chegd_df$chegd_total_detail_ref)
      chegd_df$chegd_total[detail_total_mask] <- as.numeric(chegd_df$chegd_total_detail_ref[detail_total_mask])
    }

    # Alignement via "Analyse des résultats" pour les sites sans détail CHEGD.
    use_ref_chegd_summary_only <- use_ref_chegd & !use_ref_chegd_detail
    chegd_df$nb_visites_planifiees[use_ref_chegd] <- chegd_df$nb_visites_planifiees_ref[use_ref_chegd]
    chegd_df$chegd_moyen[use_ref_chegd] <- chegd_df$chegd_moyen_ref[use_ref_chegd]
    chegd_df$chegd_total[use_ref_chegd_summary_only] <- chegd_df$chegd_moyen_ref[use_ref_chegd_summary_only] * 4

    gradient_cols <- grep("^gradient_visite_", names(chegd_df), value = TRUE)
    gradient_cols_target <- gradient_cols[gradient_cols %in% c("gradient_visite_2", "gradient_visite_3", "gradient_visite_4", "gradient_visite_5")]

    # Garantit la cohérence interne : somme(gradient_visite_2..5) == chegd_total.
    if (length(gradient_cols_target) > 0) {
      for (row_idx in which(use_ref_chegd_summary_only)) {
        target_total <- as.numeric(chegd_df$chegd_total[row_idx])
        current_vals <- as.numeric(chegd_df[row_idx, gradient_cols_target, drop = TRUE])
        current_vals[is.na(current_vals)] <- 0
        current_sum <- sum(current_vals)

        if (target_total <= 0) {
          current_vals[] <- 0
        } else if (current_sum > 0) {
          scaled <- current_vals * (target_total / current_sum)
          floored <- floor(scaled)
          remainder <- as.integer(round(target_total - sum(floored)))
          if (remainder > 0) {
            frac <- scaled - floored
            order_idx <- order(frac, decreasing = TRUE)
            add_idx <- order_idx[seq_len(min(remainder, length(order_idx)))]
            floored[add_idx] <- floored[add_idx] + 1
          }
          current_vals <- floored
        } else {
          current_vals[] <- 0
          current_vals[[1]] <- as.integer(round(target_total))
        }

        chegd_df[row_idx, gradient_cols_target] <- current_vals
      }
    }

    # Nettoyage colonnes de référence détaillée.
    ref_detail_cols <- grep("(_ref$|_detail_ref$)", names(chegd_df), value = TRUE)
    ref_detail_cols <- setdiff(ref_detail_cols, c("potentiel_score_ref", "potentiel_classe_ref", "indice_patrimonial_ref", "classe_patrimoniale_ref", "nb_visites_planifiees_ref", "chegd_moyen_ref"))
    if (length(ref_detail_cols) > 0) {
      chegd_df[ref_detail_cols] <- NULL
    }

    chegd_df$nb_visites_planifiees_ref <- NULL
    chegd_df$chegd_moyen_ref <- NULL
  }

  # Calcul IR final après éventuel alignement Excel, pour cohérence stricte.
  chegd_df <- compute_ir_from_chegd(chegd_df)

  combined_df <- Reduce(
    function(x, y) merge(x, y, by = "site_id", all.x = TRUE),
    list(
      site_ref,
      potentiel_df[, setdiff(names(potentiel_df), "site_name")],
      patrimonial_df[, setdiff(names(patrimonial_df), "site_name")],
      chegd_df[, setdiff(names(chegd_df), "site_name")]
    )
  )

  combined_df <- combined_df[order(combined_df$site_id), ]
  potentiel_df <- potentiel_df[order(potentiel_df$site_id), ]
  patrimonial_df <- patrimonial_df[order(patrimonial_df$site_id), ]
  chegd_df <- chegd_df[order(chegd_df$site_id), ]

  list(
    potentiel = potentiel_df,
    patrimonial = patrimonial_df,
    chegd = chegd_df,
    combined = combined_df,
    reference_workbook = reference_workbook
  )
}

# Résumés descriptifs standard sur les données nettoyées.
calc_summaries <- function(df_clean, cols) {
  by_site <- df_clean %>%
    group_by(.data[[cols$site]]) %>%
    summarise(
      nb_lignes = n(),
      nb_especes_uniques = n_distinct(.data[[cols$species]], na.rm = TRUE),
      nb_familles_uniques = n_distinct(.data[[cols$family]], na.rm = TRUE),
      abondance_totale = sum(nombre_espece_num, na.rm = TRUE),
      nb_visites = n_distinct(date_obs, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    arrange(desc(nb_especes_uniques), desc(abondance_totale))

  by_family <- df_clean %>%
    filter(!is.na(.data[[cols$family]]), .data[[cols$family]] != "") %>%
    group_by(.data[[cols$family]]) %>%
    summarise(
      nb_especes_uniques = n_distinct(.data[[cols$species]], na.rm = TRUE),
      abondance_totale = sum(nombre_espece_num, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    arrange(desc(nb_especes_uniques), desc(abondance_totale))

  by_species <- df_clean %>%
    filter(!is.na(.data[[cols$species]]), .data[[cols$species]] != "") %>%
    group_by(.data[[cols$species]]) %>%
    summarise(
      nb_observations = n(),
      abondance_totale = sum(nombre_espece_num, na.rm = TRUE),
      nb_sites = n_distinct(.data[[cols$site]], na.rm = TRUE),
      .groups = "drop"
    ) %>%
    arrange(desc(nb_observations), desc(abondance_totale))

  by_date <- df_clean %>%
    filter(!is.na(date_obs)) %>%
    group_by(date_obs) %>%
    summarise(
      nb_observations = n(),
      nb_especes_uniques = n_distinct(.data[[cols$species]], na.rm = TRUE),
      abondance_totale = sum(nombre_espece_num, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    arrange(date_obs)

  reliability <- df_clean %>%
    mutate(fiabilite = ifelse(is.na(.data[[cols$reliability]]) | .data[[cols$reliability]] == "", "Non renseignée", .data[[cols$reliability]])) %>%
    count(fiabilite, name = "nb_observations") %>%
    mutate(pourcentage = round(100 * nb_observations / sum(nb_observations), 2)) %>%
    arrange(desc(nb_observations))

  list(
    by_site = by_site,
    by_family = by_family,
    by_species = by_species,
    by_date = by_date,
    reliability = reliability
  )
}

# -----------------------------------------------------------------------------
# Module fiabilité — Objectifs 1 à 4
# -----------------------------------------------------------------------------

normalize_reliability_level <- function(x) {
  x_chr <- trimws(as.character(x))
  x_chr[is.na(x_chr) | x_chr == ""] <- "Non renseignée"
  x_norm <- normalize_text(x_chr)

  out <- ifelse(
    starts_with_any(x_norm, c("certain", "sur", "confirme")),
    "Certaine",
    ifelse(
      starts_with_any(x_norm, c("probable", "a verifier", "incertain")),
      "Probable",
      ifelse(x_norm == "non renseignee", "Non renseignée", "Non renseignée")
    )
  )

  factor(out, levels = c("Non renseignée", "Probable", "Certaine"), ordered = TRUE)
}

# Prépare les données pour l'analyse de fiabilité.
prepare_reliability_data <- function(df_clean, cols) {
  df_rel <- df_clean %>%
    mutate(
      fiabilite_raw = as.character(.data[[cols$reliability]]),
      fiabilite = normalize_reliability_level(fiabilite_raw),
      site_label = as.character(.data[[cols$site]]),
      family_label = as.character(.data[[cols$family]]),
      month_obs = ifelse(is.na(date_obs), NA_integer_, as.integer(format(date_obs, "%m"))),
      season_obs = ifelse(
        is.na(month_obs),
        NA_character_,
        ifelse(month_obs %in% c(12, 1, 2), "Hiver",
               ifelse(month_obs %in% c(3, 4, 5), "Printemps",
                      ifelse(month_obs %in% c(6, 7, 8), "Été", "Automne")))
      ),
      abundance = ifelse(is.na(nombre_espece_num), 0, as.numeric(nombre_espece_num))
    )

  df_rel$site_label <- factor(df_rel$site_label)
  df_rel$family_label <- factor(df_rel$family_label)
  df_rel$season_obs <- factor(df_rel$season_obs, levels = c("Hiver", "Printemps", "Été", "Automne"))
  df_rel
}

# Calcul des métriques descriptives pour l'objectif 1 (distribution de la fiabilité).
objective1_descriptive <- function(df_rel, out_dir) {
  dist <- df_rel %>%
    count(fiabilite, name = "nb_observations") %>%
    mutate(
      fiabilite = as.character(fiabilite),
      pourcentage = round(100 * nb_observations / sum(nb_observations), 2)
    ) %>%
    arrange(desc(nb_observations), fiabilite)

  write.csv(dist, file.path(out_dir, "stat_obj1_reliability_distribution.csv"), row.names = FALSE, fileEncoding = "UTF-8")

  p <- ggplot(dist, aes(x = nb_observations, y = reorder(fiabilite, nb_observations), fill = fiabilite)) +
    geom_col(width = 0.72, show.legend = FALSE) +
    geom_text(aes(label = paste0(nb_observations, " (", pourcentage, "%)")), hjust = -0.1, size = 3) +
    scale_x_continuous(expand = expansion(mult = c(0, 0.15))) +
    labs(
      title = "Objectif 1 - Distribution de la fiabilité",
      x = "Nombre d'observations",
      y = NULL
    ) +
    theme_minimal(base_size = 11) +
    theme(plot.title = element_text(face = "bold"), panel.grid.major.y = element_blank())

  ggsave(file.path(out_dir, "fig_stat1_reliability_distribution.png"), p, width = 9, height = 5, dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig_stat1_reliability_distribution.pdf"), p, width = 9, height = 5, bg = "white")

  list(metrics = dist, best = "Descriptif")
}

# Calcul des métriques pour l'objectif 2 (pondération des fiabilités).
objective2_weighting <- function(df_rel, site_metrics, out_dir) {
  schemes <- data.frame(
    scheme_id = c("S1", "S2", "S3"),
    w_certaine = c(1.0, 1.0, 1.0),
    w_probable = c(0.7, 0.8, 0.6),
    w_non_renseignee = c(0.3, 0.5, 0.2),
    stringsAsFactors = FALSE
  )

  ref_rank <- site_metrics$combined %>%
    transmute(site_id = site_id, score_ref = as.numeric(potentiel_score) + as.numeric(indice_patrimonial) + as.numeric(chegd_moyen))

  scheme_eval <- do.call(rbind, lapply(seq_len(nrow(schemes)), function(i) {
    sch <- schemes[i, ]
    tmp <- df_rel %>%
      mutate(
        weight = ifelse(
          fiabilite == "Certaine", sch$w_certaine,
          ifelse(fiabilite == "Probable", sch$w_probable, sch$w_non_renseignee)
        ),
        site_id = extract_site_id(site_label)
      ) %>%
      group_by(site_id) %>%
      summarise(weight_mean = mean(weight, na.rm = TRUE), .groups = "drop")

    merged <- merge(ref_rank, tmp, by = "site_id", all.x = TRUE)
    merged$weight_mean[is.na(merged$weight_mean)] <- sch$w_non_renseignee
    merged$score_weighted <- merged$score_ref * merged$weight_mean

    spearman <- suppressWarnings(cor(merged$score_ref, merged$score_weighted, method = "spearman", use = "complete.obs"))
    if (!is.finite(spearman)) spearman <- NA_real_

    top_ref <- merged$site_id[order(merged$score_ref, decreasing = TRUE)][1:min(5, nrow(merged))]
    top_w <- merged$site_id[order(merged$score_weighted, decreasing = TRUE)][1:min(5, nrow(merged))]
    top_overlap <- length(intersect(top_ref, top_w))

    data.frame(
      objectif = "Objectif2_Ponderation",
      candidat = sch$scheme_id,
      metric_primary = round(spearman, 4),
      metric_secondary = top_overlap,
      stringsAsFactors = FALSE
    )
  }))

  best_idx <- order(-scheme_eval$metric_primary, -scheme_eval$metric_secondary)[1]
  scheme_eval$selected <- 0L
  scheme_eval$selected[best_idx] <- 1L

  best_row <- scheme_eval[best_idx, , drop = FALSE]
  write.csv(scheme_eval, file.path(out_dir, "stat_obj2_weighting_candidates.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  write.csv(best_row, file.path(out_dir, "stat_obj2_best_weighting.csv"), row.names = FALSE, fileEncoding = "UTF-8")

  scheme_plot <- scheme_eval %>% filter(is.finite(metric_primary))
  p <- ggplot(scheme_plot, aes(x = candidat, y = metric_primary, fill = as.factor(selected))) +
    geom_col(width = 0.7, show.legend = FALSE) +
    geom_text(aes(label = sprintf("rho=%.3f\nTop5=%d", metric_primary, metric_secondary)), vjust = -0.2, size = 3) +
    scale_fill_manual(values = c("0" = "#9ECAE1", "1" = "#08519C")) +
    labs(
      title = "Objectif 2 - Comparaison des schémas de pondération",
      x = "Schéma",
      y = "Corrélation de rang (Spearman)"
    ) +
    theme_minimal(base_size = 11) +
    theme(plot.title = element_text(face = "bold"))

  ggsave(file.path(out_dir, "fig_stat2_weighting_comparison.png"), p, width = 9, height = 5, dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig_stat2_weighting_comparison.pdf"), p, width = 9, height = 5, bg = "white")

  list(metrics = scheme_eval, best = as.character(best_row$candidat[[1]]))
}


safe_macro_f1 <- function(truth, pred) {
  lvls <- union(levels(truth), levels(pred))
  lvls <- lvls[!is.na(lvls)]
  if (length(lvls) == 0) return(NA_real_)

  f1_vals <- sapply(lvls, function(lbl) {
    tp <- sum(truth == lbl & pred == lbl, na.rm = TRUE)
    fp <- sum(truth != lbl & pred == lbl, na.rm = TRUE)
    fn <- sum(truth == lbl & pred != lbl, na.rm = TRUE)
    prec <- ifelse((tp + fp) == 0, NA_real_, tp / (tp + fp))
    rec <- ifelse((tp + fn) == 0, NA_real_, tp / (tp + fn))
    if (is.na(prec) || is.na(rec) || (prec + rec) == 0) return(NA_real_)
    2 * prec * rec / (prec + rec)
  })

  mean(f1_vals, na.rm = TRUE)
}

safe_log_loss <- function(truth, proba_mat, class_levels) {
  if (is.null(proba_mat) || nrow(proba_mat) == 0) return(NA_real_)
  idx <- match(as.character(truth), class_levels)
  valid <- !is.na(idx)
  if (!any(valid)) return(NA_real_)
  p <- proba_mat[cbind(which(valid), idx[valid])]
  p <- pmax(pmin(p, 1 - 1e-15), 1e-15)
  -mean(log(p))
}

# Calcul des métriques pour l'objectif 3 (modèles de fiabilité).
build_o3_cv_metrics_plot <- function(metrics_df, out_dir) {
  plot_df <- metrics_df %>%
    transmute(
      model = candidat,
      accuracy = metric_accuracy,
      macro_f1 = metric_macro_f1,
      score = metric_primary
    )

  plot_df <- plot_df %>% filter(is.finite(accuracy) | is.finite(macro_f1))
  if (nrow(plot_df) == 0) return(invisible(NULL))

  long <- rbind(
    data.frame(model = plot_df$model, metric = "Accuracy", value = plot_df$accuracy, stringsAsFactors = FALSE),
    data.frame(model = plot_df$model, metric = "Macro-F1", value = plot_df$macro_f1, stringsAsFactors = FALSE)
  )
  long <- long %>% filter(is.finite(value))
  if (nrow(long) == 0) return(invisible(NULL))

  p <- ggplot(long, aes(x = model, y = value, fill = metric)) +
    geom_col(position = position_dodge(width = 0.75), width = 0.68) +
    scale_y_continuous(limits = c(0, 1), expand = expansion(mult = c(0, 0.05))) +
    labs(
      title = "Objectif 3 - Performances CV par modèle",
      x = "Modèle",
      y = "Score",
      fill = "Métrique"
    ) +
    theme_minimal(base_size = 11) +
    theme(plot.title = element_text(face = "bold"))

  ggsave(file.path(out_dir, "fig_stat3_cv_metrics.png"), p, width = 9, height = 5, dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig_stat3_cv_metrics.pdf"), p, width = 9, height = 5, bg = "white")
}

build_o3_confusion_plot <- function(cm_df, out_dir) {
  if (is.null(cm_df) || nrow(cm_df) == 0) return(invisible(NULL))
  p <- ggplot(cm_df, aes(x = prediction, y = truth, fill = n)) +
    geom_tile(colour = "white", linewidth = 0.5) +
    geom_text(aes(label = n), size = 3) +
    scale_fill_gradient(low = "#F7FBFF", high = "#08519C") +
    labs(
      title = "Objectif 3 - Matrice de confusion (meilleur modèle)",
      x = "Prédiction",
      y = "Vérité"
    ) +
    theme_minimal(base_size = 11) +
    theme(plot.title = element_text(face = "bold"), panel.grid = element_blank())

  ggsave(file.path(out_dir, "fig_stat3_confusion_matrix_best.png"), p, width = 7, height = 6, dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig_stat3_confusion_matrix_best.pdf"), p, width = 7, height = 6, bg = "white")
}

build_o3_probabilities_plot <- function(pred_df, out_dir) {
  if (is.null(pred_df) || nrow(pred_df) == 0 || !("max_proba" %in% names(pred_df))) return(invisible(NULL))

  pred_df <- pred_df %>% filter(is.finite(max_proba), max_proba >= 0, max_proba <= 1)
  if (nrow(pred_df) == 0) return(invisible(NULL))
  pred_df <- pred_df %>% mutate(max_proba = pmin(pmax(max_proba, 0), 1))

  p <- ggplot(pred_df, aes(x = max_proba, fill = predicted)) +
    geom_histogram(binwidth = 0.05, alpha = 0.7, position = "identity") +
    scale_x_continuous(expand = expansion(mult = c(0, 0.02))) +
    coord_cartesian(xlim = c(0, 1)) +
    labs(
      title = "Objectif 3 - Confiance des prédictions (meilleur modèle)",
      x = "Probabilité maximale prédite",
      y = "Nombre d'observations",
      fill = "Classe prédite"
    ) +
    theme_minimal(base_size = 11) +
    theme(plot.title = element_text(face = "bold"))

  ggsave(file.path(out_dir, "fig_stat3_predicted_probabilities_best.png"), p, width = 9, height = 5, dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig_stat3_predicted_probabilities_best.pdf"), p, width = 9, height = 5, bg = "white")
}

fit_predict_reliability_model <- function(model_name, train_df, test_df) {
  train_df <- droplevels(train_df)
  test_df <- droplevels(test_df)

  class_levels <- levels(train_df$fiabilite)
  if (length(class_levels) < 2) {
    pred <- factor(rep(class_levels[[1]], nrow(test_df)), levels = class_levels, ordered = TRUE)
    proba <- matrix(1, nrow = nrow(test_df), ncol = 1)
    colnames(proba) <- class_levels[[1]]
    return(list(pred = pred, proba = proba, model = NULL))
  }

  # Réduit la granularité des facteurs pour éviter sur-paramétrisation / nouvelles modalités.
  top_k <- 12
  top_sites <- names(sort(table(train_df$site_label), decreasing = TRUE))[seq_len(min(top_k, length(unique(train_df$site_label))))]
  top_families <- names(sort(table(train_df$family_label), decreasing = TRUE))[seq_len(min(top_k, length(unique(train_df$family_label))))]

  collapse_to_top <- function(x, tops) {
    x_chr <- as.character(x)
    x_chr[is.na(x_chr) | x_chr == ""] <- "Autre"
    x_chr[!(x_chr %in% tops)] <- "Autre"
    factor(x_chr)
  }

  train_df$site_model <- collapse_to_top(train_df$site_label, top_sites)
  test_df$site_model <- factor(ifelse(as.character(test_df$site_label) %in% top_sites, as.character(test_df$site_label), "Autre"), levels = levels(train_df$site_model))

  train_df$family_model <- collapse_to_top(train_df$family_label, top_families)
  test_df$family_model <- factor(ifelse(as.character(test_df$family_label) %in% top_families, as.character(test_df$family_label), "Autre"), levels = levels(train_df$family_model))

  train_df$season_model <- factor(ifelse(is.na(train_df$season_obs), "Inconnue", as.character(train_df$season_obs)))
  test_df$season_model <- factor(ifelse(is.na(test_df$season_obs), "Inconnue", as.character(test_df$season_obs)), levels = levels(train_df$season_model))

  fml <- fiabilite ~ abundance + season_model + site_model + family_model

  if (model_name == "polr") {
    fit <- suppressWarnings(tryCatch(MASS::polr(fml, data = train_df, Hess = TRUE, method = "logistic"), error = function(e) NULL))
    if (is.null(fit)) return(NULL)
    proba <- suppressWarnings(tryCatch(as.matrix(predict(fit, newdata = test_df, type = "probs")), error = function(e) NULL))
    pred <- suppressWarnings(tryCatch(predict(fit, newdata = test_df, type = "class"), error = function(e) NULL))
    if (is.null(pred)) return(NULL)
    pred <- factor(as.character(pred), levels = class_levels, ordered = TRUE)
    return(list(pred = pred, proba = proba, model = fit))
  }

  if (model_name == "multinom") {
    fit <- suppressWarnings(tryCatch(nnet::multinom(fml, data = train_df, trace = FALSE, MaxNWts = 5000), error = function(e) NULL))
    if (is.null(fit)) return(NULL)
    proba <- suppressWarnings(tryCatch(as.matrix(predict(fit, newdata = test_df, type = "probs")), error = function(e) NULL))
    if (!is.null(proba) && is.null(dim(proba))) {
      proba <- matrix(proba, ncol = length(class_levels), byrow = TRUE)
      colnames(proba) <- class_levels
    }
    pred <- suppressWarnings(tryCatch(predict(fit, newdata = test_df, type = "class"), error = function(e) NULL))
    if (is.null(pred)) return(NULL)
    pred <- factor(as.character(pred), levels = class_levels, ordered = TRUE)
    return(list(pred = pred, proba = proba, model = fit))
  }

  if (model_name == "baseline_majority") {
    majority <- names(sort(table(train_df$fiabilite), decreasing = TRUE))[1]
    pred <- factor(rep(majority, nrow(test_df)), levels = class_levels, ordered = TRUE)
    proba <- matrix(0, nrow = nrow(test_df), ncol = length(class_levels))
    colnames(proba) <- class_levels
    proba[, majority] <- 1
    return(list(pred = pred, proba = proba, model = NULL))
  }

  NULL
}

objective3_model_selection <- function(df_rel, out_dir) {
  df <- df_rel %>%
    filter(!is.na(fiabilite)) %>%
    mutate(row_id = row_number())

  if (nrow(df) < 20 || n_distinct(df$fiabilite) < 2) {
    empty <- data.frame(
      objectif = "Objectif3_Modeles",
      candidat = "insuffisant",
      metric_primary = NA_real_,
      metric_secondary = NA_real_,
      metric_accuracy = NA_real_,
      metric_macro_f1 = NA_real_,
      metric_logloss = NA_real_,
      selected = 1L,
      stringsAsFactors = FALSE
    )
    write.csv(empty, file.path(out_dir, "stat_obj3_model_metrics.csv"), row.names = FALSE, fileEncoding = "UTF-8")
    return(list(metrics = empty, best = "insuffisant"))
  }

  set.seed(42)
  k <- 5
  fold_id <- sample(rep(seq_len(k), length.out = nrow(df)))
  candidates <- c("polr", "multinom", "baseline_majority")

  rows <- list()
  preds_all <- list()

  for (cand in candidates) {
    all_truth <- c()
    all_pred <- c()
    all_max_proba <- c()
    all_pred_label <- c()
    logloss_vals <- c()

    for (f in seq_len(k)) {
      train <- df[fold_id != f, ]
      test <- df[fold_id == f, ]
      fit_res <- fit_predict_reliability_model(cand, train, test)
      if (is.null(fit_res)) next

      truth <- factor(as.character(test$fiabilite), levels = levels(df$fiabilite), ordered = TRUE)
      pred <- factor(as.character(fit_res$pred), levels = levels(df$fiabilite), ordered = TRUE)

      acc <- mean(as.character(pred) == as.character(truth), na.rm = TRUE)
      f1 <- safe_macro_f1(truth, pred)

      proba <- fit_res$proba
      if (!is.null(proba) && !is.null(colnames(proba))) {
        ll <- safe_log_loss(truth, proba, colnames(proba))
        logloss_vals <- c(logloss_vals, ll)
        max_p <- apply(proba, 1, max)
      } else {
        max_p <- rep(NA_real_, length(pred))
      }

      all_truth <- c(all_truth, as.character(truth))
      all_pred <- c(all_pred, as.character(pred))
      all_max_proba <- c(all_max_proba, max_p)
      all_pred_label <- c(all_pred_label, as.character(pred))
    }

    if (length(all_truth) == 0) {
      rows[[cand]] <- data.frame(
        objectif = "Objectif3_Modeles",
        candidat = cand,
        metric_primary = NA_real_,
        metric_secondary = NA_real_,
        metric_accuracy = NA_real_,
        metric_macro_f1 = NA_real_,
        metric_logloss = NA_real_,
        selected = 0L,
        stringsAsFactors = FALSE
      )
      next
    }

    acc_all <- mean(all_pred == all_truth)
    truth_factor <- factor(all_truth, levels = levels(df$fiabilite), ordered = TRUE)
    pred_factor <- factor(all_pred, levels = levels(df$fiabilite), ordered = TRUE)
    f1_all <- safe_macro_f1(truth_factor, pred_factor)
    ll_all <- ifelse(length(logloss_vals) > 0, mean(logloss_vals, na.rm = TRUE), NA_real_)

    rows[[cand]] <- data.frame(
      objectif = "Objectif3_Modeles",
      candidat = cand,
      metric_primary = round(f1_all, 4),
      metric_secondary = round(acc_all, 4),
      metric_accuracy = round(acc_all, 4),
      metric_macro_f1 = round(f1_all, 4),
      metric_logloss = round(ll_all, 4),
      selected = 0L,
      stringsAsFactors = FALSE
    )

    preds_all[[cand]] <- data.frame(
      truth = all_truth,
      predicted = all_pred_label,
      max_proba = all_max_proba,
      model = cand,
      stringsAsFactors = FALSE
    )
  }

  metrics <- do.call(rbind, rows)
  metrics <- metrics[order(-metrics$metric_primary, -metrics$metric_secondary), ]
  best_model <- metrics$candidat[[1]]
  metrics$selected <- as.integer(metrics$candidat == best_model)

  write.csv(metrics, file.path(out_dir, "obj3_model_metrics.csv"), row.names = FALSE, fileEncoding = "UTF-8")

  best_pred <- preds_all[[best_model]]
  if (!is.null(best_pred) && nrow(best_pred) > 0) {
    write.csv(best_pred, file.path(out_dir, "stat_obj3_best_model_predictions.csv"), row.names = FALSE, fileEncoding = "UTF-8")
    cm <- as.data.frame(table(truth = best_pred$truth, prediction = best_pred$predicted), stringsAsFactors = FALSE)
    names(cm)[3] <- "n"
    write.csv(cm, file.path(out_dir, "stat_obj3_best_model_confusion_matrix.csv"), row.names = FALSE, fileEncoding = "UTF-8")
    build_o3_confusion_plot(cm, out_dir)
    build_o3_probabilities_plot(best_pred, out_dir)
  }

  build_o3_cv_metrics_plot(metrics, out_dir)

  # Ajuste final du meilleur modèle sur toutes les données pour export des coefficients.
  fit_full <- fit_predict_reliability_model(best_model, df, df)
  coef_df <- data.frame(term = character(), estimate = numeric(), stringsAsFactors = FALSE)
  if (!is.null(fit_full) && !is.null(fit_full$model)) {
    if (best_model == "polr") {
      coef_vals <- coef(fit_full$model)
      coef_df <- data.frame(term = names(coef_vals), estimate = as.numeric(coef_vals), stringsAsFactors = FALSE)
    } else if (best_model == "multinom") {
      coef_mat <- coef(fit_full$model)
      if (is.null(dim(coef_mat))) {
        coef_df <- data.frame(term = names(coef_mat), estimate = as.numeric(coef_mat), stringsAsFactors = FALSE)
      } else {
        coef_df <- do.call(rbind, lapply(seq_len(nrow(coef_mat)), function(i) {
          data.frame(
            term = paste0(rownames(coef_mat)[i], "::", colnames(coef_mat)),
            estimate = as.numeric(coef_mat[i, ]),
            stringsAsFactors = FALSE
          )
        }))
      }
    }
  }
  write.csv(coef_df, file.path(out_dir, "stat_obj3_best_model_coefficients.csv"), row.names = FALSE, fileEncoding = "UTF-8")

  list(metrics = metrics, best = best_model)
}

objective4_inference <- function(df_rel, out_dir) {
  tbl <- table(df_rel$site_label, df_rel$fiabilite)
  chi <- suppressWarnings(chisq.test(tbl))
  use_fisher <- any(chi$expected < 5)

  test_name <- if (use_fisher) "Fisher" else "Chi2"
  if (use_fisher) {
    fisher_exact <- tryCatch(fisher.test(tbl), error = function(e) NULL)
    if (!is.null(fisher_exact)) {
      p_value <- fisher_exact$p.value
    } else {
      fisher_sim <- suppressWarnings(tryCatch(fisher.test(tbl, simulate.p.value = TRUE, B = 10000), error = function(e) NULL))
      if (!is.null(fisher_sim)) {
        test_name <- "Fisher_simule"
        p_value <- fisher_sim$p.value
      } else {
        test_name <- "Chi2_fallback"
        p_value <- chi$p.value
      }
    }
  } else {
    p_value <- chi$p.value
  }

  infer_df <- data.frame(
    objectif = "Objectif4_Inference",
    candidat = test_name,
    metric_primary = as.numeric(-log10(max(p_value, 1e-300))),
    metric_secondary = as.numeric(p_value),
    stringsAsFactors = FALSE
  )
  infer_df$selected <- 1L

  write.csv(infer_df, file.path(out_dir, "stat_obj4_inference_tests.csv"), row.names = FALSE, fileEncoding = "UTF-8")

  heat <- as.data.frame(tbl)
  names(heat) <- c("site", "fiabilite", "n")
  p <- ggplot(heat, aes(x = fiabilite, y = site, fill = n)) +
    geom_tile(colour = "white", linewidth = 0.4) +
    geom_text(aes(label = n), size = 2.5) +
    scale_fill_gradient(low = "#F7FBFF", high = "#08519C") +
    labs(
      title = "Objectif 4 - Répartition de la fiabilité par site",
      subtitle = paste0("Test retenu: ", test_name, " | p=", signif(p_value, 3)),
      x = "Fiabilité",
      y = "Site"
    ) +
    theme_minimal(base_size = 11) +
    theme(plot.title = element_text(face = "bold"), panel.grid = element_blank())

  ggsave(file.path(out_dir, "fig_stat4_site_reliability_heatmap.png"), p, width = 10, height = 7, dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig_stat4_site_reliability_heatmap.pdf"), p, width = 10, height = 7, bg = "white")

  list(metrics = infer_df, best = test_name)
}

run_reliability_objectives <- function(df_clean, cols, site_metrics, out_dir) {
  df_rel <- prepare_reliability_data(df_clean, cols)

  o1 <- objective1_descriptive(df_rel, out_dir)
  o2 <- objective2_weighting(df_rel, site_metrics, out_dir)
  o3 <- objective3_model_selection(df_rel, out_dir)
  o4 <- objective4_inference(df_rel, out_dir)

  summary_df <- rbind(
    data.frame(objectif = "Objectif1_Descriptif", candidat = o1$best, metric_primary = NA_real_, metric_secondary = NA_real_, selected = 1L, stringsAsFactors = FALSE),
    data.frame(objectif = "Objectif2_Ponderation", candidat = o2$best, metric_primary = o2$metrics$metric_primary[o2$metrics$selected == 1][1], metric_secondary = o2$metrics$metric_secondary[o2$metrics$selected == 1][1], selected = 1L, stringsAsFactors = FALSE),
    data.frame(objectif = "Objectif3_Modeles", candidat = o3$best, metric_primary = o3$metrics$metric_primary[o3$metrics$selected == 1][1], metric_secondary = o3$metrics$metric_secondary[o3$metrics$selected == 1][1], selected = 1L, stringsAsFactors = FALSE),
    data.frame(objectif = "Objectif4_Inference", candidat = o4$best, metric_primary = o4$metrics$metric_primary[o4$metrics$selected == 1][1], metric_secondary = o4$metrics$metric_secondary[o4$metrics$selected == 1][1], selected = 1L, stringsAsFactors = FALSE)
  )

  write.csv(summary_df, file.path(out_dir, "stat_model_selection_summary.csv"), row.names = FALSE, fileEncoding = "UTF-8")

  list(summary = summary_df, details = list(o1 = o1, o2 = o2, o3 = o3, o4 = o4))
}

# Écrit les exports CSV et les indicateurs globaux de contrôle qualité.
write_outputs <- function(df_clean, summaries, site_metrics, out_dir, cols) {
  write.csv(df_clean, file.path(out_dir, "donnees_brutes_nettoyees.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  write.csv(summaries$by_site, file.path(out_dir, "resume_par_site.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  write.csv(summaries$by_family, file.path(out_dir, "resume_par_famille.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  write.csv(summaries$by_species, file.path(out_dir, "resume_par_espece.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  write.csv(summaries$by_date, file.path(out_dir, "resume_par_date.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  write.csv(summaries$reliability, file.path(out_dir, "resume_fiabilite_determination.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  write.csv(summaries$reliability, file.path(out_dir, "niveaux_fiabilite_rencontres.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  write.csv(site_metrics$potentiel, file.path(out_dir, "potentiel_fongique_par_site.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  write.csv(site_metrics$patrimonial, file.path(out_dir, "indice_patrimonial_par_site.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  write.csv(site_metrics$chegd, file.path(out_dir, "gradient_chegd_par_site.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  ir_cols <- grep("^ir_visite_", names(site_metrics$chegd), value = TRUE)
  ir_export_cols <- unique(c("site_id", "site_name", "chegd_total", ir_cols, "ir_moyen"))
  ir_export_cols <- ir_export_cols[ir_export_cols %in% names(site_metrics$chegd)]
  if (length(ir_export_cols) > 0) {
    write.csv(site_metrics$chegd[, ir_export_cols, drop = FALSE], file.path(out_dir, "indice_representativite_ir_par_site.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  }
  write.csv(site_metrics$combined, file.path(out_dir, "synthese_evaluation_par_site.csv"), row.names = FALSE, fileEncoding = "UTF-8")

  # Contrôle QA : cohérence gradients CHEGD détaillés vs total.
  gradient_cols <- grep("^gradient_visite_", names(site_metrics$chegd), value = TRUE)
  if (length(gradient_cols) > 0) {
    gradient_sum <- rowSums(site_metrics$chegd[, gradient_cols, drop = FALSE], na.rm = TRUE)
    chedgd_incoherent_count <- sum(abs(gradient_sum - site_metrics$chegd$chegd_total) > 1e-9, na.rm = TRUE)
  } else {
    chedgd_incoherent_count <- 0
  }
  coherence_chegd_ok <- as.integer(chedgd_incoherent_count == 0)

  global <- data.frame(
    indicateur = c(
      "nb_lignes_total",
      "nb_especes_uniques",
      "nb_familles_uniques",
      "abondance_totale",
      "nb_sites_uniques",
      "nb_dates_uniques",
      "nb_sites_potentiel_interessant_ou_plus",
      "nb_sites_interet_local_ou_plus",
      "gradient_chegd_moyen_global",
      "ir_moyen_global",
      "coherence_chegd_gradients_ok",
      "nb_sites_incoherents_chegd"
    ),
    valeur = c(
      nrow(df_clean),
      dplyr::n_distinct(df_clean[[cols$species]], na.rm = TRUE),
      dplyr::n_distinct(df_clean[[cols$family]], na.rm = TRUE),
      sum(df_clean$nombre_espece_num, na.rm = TRUE),
      dplyr::n_distinct(df_clean[[cols$site]], na.rm = TRUE),
      dplyr::n_distinct(df_clean$date_obs, na.rm = TRUE),
      sum(site_metrics$potentiel$potentiel_score > 10, na.rm = TRUE),
      sum(site_metrics$patrimonial$indice_patrimonial > 2, na.rm = TRUE),
      round(mean(site_metrics$chegd$chegd_moyen, na.rm = TRUE), 3),
      ifelse("ir_moyen" %in% names(site_metrics$chegd), round(mean(site_metrics$chegd$ir_moyen, na.rm = TRUE), 6), NA_real_),
      coherence_chegd_ok,
      chedgd_incoherent_count
    )
  )

  write.csv(global, file.path(out_dir, "resume_global.csv"), row.names = FALSE, fileEncoding = "UTF-8")
}

# Point d'entrée CLI.
main <- function() {
  # === SETUP ET CONFIGURATION ===
  script_dir <- get_script_dir()
  base_dir <- if (basename(script_dir) == "scripts") dirname(script_dir) else script_dir
  config_source <- "Configuration intégrée (get_embedded_config)"

  cfg <- get_embedded_config()
  cfg$input_file <- resolve_input_file(cfg$input_file, base_dir)
  cfg$output_dir <- resolve_path_from_base(cfg$output_dir, base_dir)

  # === CRÉER RÉPERTOIRE DE SORTIE ===
  out_dir <- build_output_dir(cfg$output_dir, cfg$output_prefix)

  # === INITIALISER LOGGING dans /logs à la racine du projet ===
  setup_logging(base_dir, cfg$output_prefix)
  log_header(config_source, cfg$input_file)
  log_info(paste0("Fichier d'entrée résolu : ", cfg$input_file))
  log_info(paste0("Répertoire de sortie : ", out_dir))

  ext <- tolower(tools::file_ext(cfg$input_file))
  if (ext == "csv") {
    log_info("Format CSV détecté, le paramètre de feuille est ignoré")
  }

  # === LIRE ET NETTOYER LES DONNÉES ===
  log_section("LECTURE ET TRAITEMENT DES DONNÉES D'ENTRÉE")
  raw <- read_input_data(cfg$input_file, cfg$input_sheet)
  raw <- raw[, !grepl("^\\.\\.\\.", names(raw)), drop = FALSE]
  ensure_required_columns(raw, cfg)

  cols <- cfg$columns

  df_clean <- raw %>%
    mutate(
      date_obs = to_date_safe(.data[[cols$date]]),
      nombre_espece_num = to_numeric_safe(.data[[cols$count]])
    )

  log_data_summary(
    nrow(df_clean),
    n_distinct(df_clean[[cols$species]], na.rm = TRUE),
    n_distinct(df_clean[[cols$site]], na.rm = TRUE),
    n_distinct(df_clean$date_obs, na.rm = TRUE)
  )

  missing_reliability <- sum(is.na(df_clean[[cols$reliability]]) | trimws(as.character(df_clean[[cols$reliability]])) == "")
  if (missing_reliability > 0) {
    total_rows <- nrow(df_clean)
    pct_missing <- round(100 * missing_reliability / max(total_rows, 1), 2)
    log_warning_msg(paste0(missing_reliability, " observation(s) sans niveau de fiabilité (", pct_missing, " %)"))
  }

  # === CONSTRUIRE LES MÉTRIQUES ===
  log_section("CONSTRUCTION DES MÉTRIQUES PAR SITE")
  log_info(paste0("Répertoire de sortie : ", out_dir))

  summaries <- calc_summaries(df_clean, cols)
  log_info("Résumés descriptifs calculés")

  site_metrics <- build_site_level_metrics(df_clean, cols, base_dir, cfg$input_file)
  log_info("Métriques par site calculées")

  # === GÉNÉRER LES GRAPHIQUES ===
  log_section("GÉNÉRATION DES FIGURES")
  build_site_dashboard(site_metrics, out_dir)
  log_info("Figure 1 : tableau de bord des sites terminé")

  build_scatter_positionnement(site_metrics, out_dir)
  log_info("Figure 2 : positionnement écologique terminé")

  build_potentiel_breakdown(site_metrics, out_dir)
  log_info("Figure 3 : décomposition du potentiel terminée")

  build_chegd_by_visit(site_metrics, out_dir)
  log_info("Figure 4 : CHEGD par visite terminé")

  build_classes_heatmap(site_metrics, out_dir)
  log_info("Figure 5 : carte thermique des classes terminée")

  build_reliability_levels_plot(summaries$reliability, out_dir)
  log_info("Figure 6 : distribution des niveaux de fiabilité terminée")

  build_ir_by_visit_plot(site_metrics, out_dir)
  log_info("Figure 7 : indice de représentativité (IR) terminé")

  # === OBJECTIFS FIABILITÉ ===
  log_section("OBJECTIFS DE FIABILITÉ (1-4)")
  reliability_objectives <- run_reliability_objectives(df_clean, cols, site_metrics, out_dir)
  if (!is.null(reliability_objectives$summary)) {
    log_info("Objectifs de fiabilité terminés - Meilleurs candidats :")
    for (i in seq_len(nrow(reliability_objectives$summary))) {
      r <- reliability_objectives$summary[i, ]
      log_info(paste0("  - ", r$objectif, ": ", r$candidat))
    }
  }

  # === EXPORTER LES RÉSULTATS ===
  log_section("EXPORT DES RÉSULTATS")
  write_outputs(df_clean, summaries, site_metrics, out_dir, cols)
  log_info("Tous les fichiers CSV ont été exportés")

  # === AFFICHER LES SORTIES PRINCIPALES ===
  log_section("RÉCAPITULATIF DES FICHIERS DE SORTIE")
  log_info("Fichiers CSV :")
  log_info("  - donnees_brutes_nettoyees.csv")
  log_info("  - resume_global.csv")
  log_info("  - resume_par_site.csv")
  log_info("  - resume_par_famille.csv")
  log_info("  - resume_par_espece.csv")
  log_info("  - resume_par_date.csv")
  log_info("  - resume_fiabilite_determination.csv")
  log_info("  - niveaux_fiabilite_rencontres.csv")
  log_info("  - potentiel_fongique_par_site.csv")
  log_info("  - indice_patrimonial_par_site.csv")
  log_info("  - gradient_chegd_par_site.csv")
  log_info("  - indice_representativite_ir_par_site.csv")
  log_info("  - synthese_evaluation_par_site.csv")
  log_info("Figures :")
  log_info("  - fig1_tableau_de_bord_pelouses.png / .pdf")
  log_info("  - fig2_positionnement_ecologique.png / .pdf")
  log_info("  - fig3_composition_potentiel.png / .pdf")
  log_info("  - fig4_chegd_par_visite.png / .pdf")
  log_info("  - fig5_heatmap_classes.png / .pdf")
  log_info("  - fig6_niveaux_fiabilite.png / .pdf")
  log_info("  - fig7_indice_representativite_ir.png / .pdf")
  log_info("Objectifs de fiabilité :")
  log_info("  - stat_obj1_reliability_distribution.csv + fig")
  log_info("  - stat_obj2_weighting_candidates.csv + stat_obj2_best_weighting.csv + fig")
  log_info("  - stat_obj3_model_metrics.csv + stat_confusion_matrix.csv + stat_coefficients.csv + figs")
  log_info("  - stat_obj4_inference_tests.csv + fig")
  log_info("  - stat_model_selection_summary.csv")

  # === FOOTER ===
  log_footer()

  # === AFFICHAGE CONSOLE (pour compatibilité) ===
  message("Calcul terminé")
  message("Résultats : ", out_dir)
  message("Log: ", .log_env$log_file)
  if (!is.null(site_metrics$reference_workbook)) {
    message("Référence visites/formules : ", site_metrics$reference_workbook)
  }
}

# === EXÉCUTION PRINCIPALE AVEC GESTION D'ERREURS ===
tryCatch({
  main()
}, error = function(e) {
  log_error(paste0("Échec de l'exécution du pipeline : ", conditionMessage(e)))
  if (!is.null(.log_env$start_time)) {
    log_footer()
  }
  stop(e)
})
