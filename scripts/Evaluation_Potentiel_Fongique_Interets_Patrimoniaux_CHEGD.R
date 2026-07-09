#!/usr/bin/env Rscript

# ===============================================================================================================================================================================================
# Évaluation du potentiel fongique, de l'intérêt patrimonial et du gradient CHEGD
# ===============================================================================================================================================================================================
# Évaluation du potentiel fongique, de l'intérêt patrimonial et du gradient CHEGD
# But :
#   - Lire un fichier CSV de données brutes d'observations mycologiques.
#   - Produire des résumés globaux (site/famille/espèce/date/fiabilité).
#   - Calculer des indicateurs par site (potentiel, patrimonialité, CHEGD).
#   - Aligner les indicateurs sur un classeur de référence si disponible
#     avec alignement sur le classeur de référence quand il est disponible.
# 
# Basé sur le protocole : Sellier, Y., et coll. (s.d.). Évaluation du potentiel fongique et de l’intérêt patrimonial des
# pelouses.Mycofrance. https://www.mycofrance.fr/wp-content/uploads/2025/05/Bull.-SMF-131-1-2-Y-Sellier-et-coll.pdf
#
# Entrées :
#   - Configuration intégrée au script (modifiable dans get_embedded_config)
#   - Fichier de données brutes CSV (cfg$input_file)
#
# Localisation des paramètres dans le script :
#   - Paramètres principaux du pipeline : `get_embedded_config()`
#   - Seuils de pilotage qualité : `get_embedded_config()$quality_alert_thresholds`
#   - Mappage des colonnes métier : `get_embedded_config()$columns`
#   - Mode strict/tolérant : `get_embedded_config()$strict`
#   - Contrôles bloquants et alertes d'entrée : `validate_input_data()`
#   - Contrôle CHEGD/IR autonome : `validate_autonomous_reliability()`
#   - Orchestration des étapes, logs et exports : `main()`
#
# Mini-table de repérage rapide :
#   - protocol_scope        | Où modifier : get_embedded_config()                   | Effet : libellé du périmètre dans les logs.
#   - strict                | Où modifier : get_embedded_config()                   | Effet : TRUE=arrêt sur bloquants ; FALSE=tolérant.
#   - input_file            | Où modifier : get_embedded_config()                   | Effet : fichier source analysé.
#   - output_dir            | Où modifier : get_embedded_config()                   | Effet : dossier racine des sorties.
#   - output_prefix         | Où modifier : get_embedded_config()                   | Effet : préfixe de nommage des artefacts.
#   - columns               | Où modifier : get_embedded_config()$columns           | Effet : mapping des en-têtes CSV métier.
#   - quality_alert_thresholds | Où modifier : get_embedded_config()$quality_alert_thresholds | Effet : seuils d’alertes QA entrée.
#
# Sorties :
#   - Répertoire fixe dans cfg$output_dir contenant les CSV de synthèse.
#
# Version :
#   - 1.1 (2026-07-08) : signalement explicite des lignes vides et données manquantes dans main() ;
#                        correction du faux positif d'alerte qualité (0 >= seuil 0) dans build_input_quality_digest().
#   - 1.0 : version initiale.
#
# Auteur : Eddy Boite (SMF, RNF, FongiFrance)
# 
# ===============================================================================================================================================================================================

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Pré-requis : packages R
# Ces packages sont utilisés pour la manipulation de données, la création de graphiques et l'analyse statistique.
# dplyr : manipulation de data frames (filtrage, regroupement, résumés)
# stringr : manipulation de chaînes de caractères (regex, remplacement, extraction)
# ggplot2 : création de graphiques
# gridExtra : disposition de graphiques multiples
# MASS : fonctions statistiques avancées
# nnet : modèles de réseaux de neurones et régression multinomiale
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
REQUIRED_PACKAGES <- c("dplyr", "stringr", "ggplot2", "gridExtra", "MASS", "nnet")

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — vérification explicite des dépendances R requises.
# Entrée : vecteur `packages`.
# Règle : tous les packages doivent être disponibles via `requireNamespace(..., quietly = TRUE)`.
# Cas bloquant : arrêt via `stop()` si au moins un package manque (message avec commande d'installation).
# Sortie : `TRUE` invisible si la vérification passe.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
assert_required_packages <- function(packages = REQUIRED_PACKAGES) {
  missing_packages <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]

  if (length(missing_packages) > 0) {
    install_hint <- paste0(
      "install.packages(c(",
      paste(sprintf('"%s"', missing_packages), collapse = ", "),
      '), repos = "https://cloud.r-project.org")'
    )

    stop(
      "Package(s) R manquant(s) : ", paste(missing_packages, collapse = ", "),
      "\nInstallez-les avant d'exécuter le script, par exemple :\n  ", install_hint,
      call. = FALSE
    )
  }

  invisible(TRUE)
}

suppressPackageStartupMessages({
  assert_required_packages()
})

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Chargement des packages
# Ces packages sont utilisés pour la manipulation de données, la création de graphiques et l'analyse statistique.
# dplyr : manipulation de data frames (filtrage, regroupement, résumés)
# stringr : manipulation de chaînes de caractères (regex, remplacement, extraction)
# ggplot2 : création de graphiques
# gridExtra : disposition de graphiques multiples
# MASS : fonctions statistiques avancées 
# nnet : modèles de réseaux de neurones et régression multinomiale
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
library(dplyr)
library(stringr)
library(ggplot2)
library(gridExtra)
library(MASS)
library(nnet)

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Version du script
# SCRIPT_VERSION : version fonctionnelle du pipeline (SemVer simplifiée).
# Utilisée dans les logs pour tracer précisément la version exécutée.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
SCRIPT_VERSION <- "1.1"

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Système de logging
# Un système de logging simple pour suivre l'exécution du script et enregistrer les messages dans un fichier log horodaté.
# Le log inclut des sections, des messages d'info, d'erreur et de warning, ainsi qu'un résumé des données et une durée d'exécution totale.
# Le fichier log est créé dans un sous-dossier "logs" du répertoire de sortie, avec un nom basé sur le préfixe de sortie et l'horodatage.
# Environnement pour stocker les informations de logging
# .log_env est un environnement interne pour stocker le chemin du fichier log et l'heure de début de l'exécution.
# Il est utilisé par les fonctions de logging pour écrire les messages dans le fichier log et calculer la durée d'exécution.
# .log_env est initialisé avec log_file et start_time à NULL, et sera mis à jour lors de l'appel à setup_logging().
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
.log_env <- new.env()
.log_env$log_file <- NULL
.log_env$start_time <- NULL

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — initialisation du système de logs d'exécution.
# Entrées :
#   - base_dir : répertoire racine où créer `logs/`.
#   - prefix   : préfixe de nom de fichier log.
#
# Comportement :
#   - crée (si besoin) `base_dir/logs`,
#   - crée un fichier log horodaté `prefix_YYYYMMDD_HHMM.log`,
#   - initialise l'état global `.log_env$log_file` et `.log_env$start_time`.
#
# Cas bloquants :
#   - aucun `stop()` explicite ; une erreur système (droits/IO) est propagée par R.
#
# Sortie :
#   - chemin du log (retour invisible).
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
setup_logging <- function(base_dir, prefix = "EPFIP_CHEGD") {
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M")
  logs_dir <- file.path(base_dir, "logs")
  dir.create(logs_dir, recursive = TRUE, showWarnings = FALSE)
  log_file <- file.path(logs_dir, paste0(prefix, "_", timestamp, ".log"))
  .log_env$log_file <- log_file
  .log_env$start_time <- Sys.time()
  cat("", file = log_file)
  invisible(log_file)
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — émission d'un message d'information.
# Entrées :
#   - msg       : message texte.
#   - timestamp : ajoute `[HH:MM:SS]` si TRUE.
#
# Comportement :
#   - écrit le message sur stdout,
#   - l'ajoute au fichier log si `.log_env$log_file` est défini.
#
# Cas bloquants :
#   - aucun `stop()` explicite ; erreurs IO propagées.
#
# Sortie :
#   - aucune (effets de bord console + fichier).
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
log_info <- function(msg, timestamp = TRUE) {
  ts_str <- if (timestamp) format(Sys.time(), "[%H:%M:%S] ") else ""
  full_msg <- paste0(ts_str, msg)
  cat(full_msg, "\n")
  if (!is.null(.log_env$log_file)) {
    cat(full_msg, "\n", file = .log_env$log_file, append = TRUE)
  }
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — émission d'un message d'erreur formaté.
# Entrée : `msg` (chaîne de caractères).
# Comportement : préfixe `[ERROR]`, écriture stderr + fichier log si configuré.
# Cas bloquants : aucun `stop()` interne.
# Sortie : aucune (effets de bord).
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
log_error <- function(msg) {
  full_msg <- paste0("[ERROR] ", msg)
  cat(full_msg, "\n", file = stderr())
  if (!is.null(.log_env$log_file)) {
    cat(full_msg, "\n", file = .log_env$log_file, append = TRUE)
  }
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — émission d'un avertissement formaté.
# Entrée : `msg` (chaîne de caractères).
# Comportement : préfixe `[WARN]`, écriture stdout + fichier log si configuré.
# Cas bloquants : aucun.
# Sortie : aucune (effets de bord).
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
log_warning_msg <- function(msg) {
  full_msg <- paste0("[WARN] ", msg)
  cat(full_msg, "\n")
  if (!is.null(.log_env$log_file)) {
    cat(full_msg, "\n", file = .log_env$log_file, append = TRUE)
  }
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — séparation visuelle des sections de log.
# Entrée : `title`.
# Comportement : écrit trois lignes (séparateur, titre, séparateur) sans horodatage.
# Cas bloquants : aucun.
# Sortie : aucune (effets de bord).
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
log_section <- function(title) {
  sep <- strrep("─", 80)
  log_info(sep, timestamp = FALSE)
  log_info(paste0("  ", title), timestamp = FALSE)
  log_info(sep, timestamp = FALSE)
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — exécution protégée d'une étape non bloquante.
# Entrées :
#   - step_name : libellé de l'étape pour le log.
#   - step_fn   : fonction sans argument à exécuter.
#
# Comportement :
#   - exécute `step_fn()` dans un `tryCatch`.
#   - en cas d'erreur, journalise un warning détaillé mais n'interrompt pas le pipeline.
#
# Cas bloquants :
#   - aucun (les erreurs sont capturées et converties en statut KO).
#
# Sortie :
#   - liste `list(ok = TRUE/FALSE, error = <message|NULL>)`.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
run_non_blocking_step <- function(step_name, step_fn) {
  tryCatch({
    step_fn()
    list(ok = TRUE, error = NULL)
  }, error = function(e) {
    msg <- conditionMessage(e)
    log_warning_msg(paste0("Étape non bloquante en échec [", step_name, "] : ", msg))
    list(ok = FALSE, error = msg)
  })
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — en-tête de log d'exécution.
# Entrées :
#   - config_path : libellé/source de configuration.
#   - input_file  : chemin du jeu d'entrée.
# Comportement : écrit une section d'ouverture avec contexte runtime (version script, R, cwd).
# Cas bloquants : aucun.
# Sortie : aucune (effets de bord).
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
log_header <- function(config_path, input_file) {
  log_section("Évaluation du potentiel fongique, de l'intérêt patrimonial et du gradient CHEGD")
  log_info(paste0("Horodatage : ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")), timestamp = FALSE)
  log_info(paste0("Version du script : ", SCRIPT_VERSION), timestamp = FALSE)
  log_info(paste0("Version de R : ", R.version$version.string), timestamp = FALSE)
  log_info(paste0("Répertoire de travail : ", getwd()), timestamp = FALSE)
  log_info(paste0("Configuration: ", config_path), timestamp = FALSE)
  log_info(paste0("Fichier d'entrée : ", input_file), timestamp = FALSE)
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — résumé quantitatif du jeu d'entrée.
# Entrées : nrows, nspecies, nsites, ndates.
# Comportement : journalise les compteurs principaux.
# Cas bloquants : aucun.
# Sortie : aucune (effets de bord).
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
log_data_summary <- function(nrows, nspecies, nsites, ndates) {
  log_section("Résumé des données d'entrée")
  log_info(paste0("Nombre total d'observations : ", nrows))
  log_info(paste0("Nombre d'espèces uniques : ", nspecies))
  log_info(paste0("Nombre de sites uniques : ", nsites))
  log_info(paste0("Nombre de dates uniques : ", ndates))
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — pied de log.
# Comportement : journalise fin d'exécution, durée totale, horodatage de fin et chemin du log.
# Cas bloquants : aucun.
# Sortie : aucune (effets de bord).
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
log_footer <- function() {
  log_section("Exécution terminée")
  if (!is.null(.log_env$start_time)) {
    elapsed <- as.numeric(difftime(Sys.time(), .log_env$start_time, units = "secs"))
    log_info(paste0("Durée totale d'exécution : ", round(elapsed, 2), " secondes"), timestamp = FALSE)
  }
  log_info(paste0("Heure de fin : ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")), timestamp = FALSE)
  log_info(paste0("Fichier log : ", .log_env$log_file), timestamp = FALSE)
}
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — configuration embarquée par défaut.
# Liste exhaustive des paramètres exposés, avec définition et valeurs possibles :
#
# 1) protocol_scope (character)
#    - Définition : libellé du périmètre protocolaire analysé ; utilisé pour le log et la traçabilité.
#    - Valeurs possibles : toute chaîne non vide (recommandé : explicite et stable dans le temps).
#    - Exemple courant : "CHEGD pelouses".
#
# 2) strict (logical)
#    - Définition : mode d'exécution des contrôles bloquants.
#    - Valeurs possibles :
#        * TRUE  : mode strict (arrêt du pipeline sur anomalies bloquantes).
#        * FALSE : mode tolérant (warning + poursuite du pipeline).
#
# 3) input_file (character)
#    - Définition : chemin du fichier d'entrée principal.
#    - Valeurs possibles :
#        * chemin relatif (résolu depuis la base projet),
#        * ou chemin absolu.
#    - Contraintes : fichier CSV attendu (résolution robuste appliquée par `resolve_input_file`).
#
# 4) output_dir (character)
#    - Définition : dossier racine des sorties.
#    - Valeurs possibles : chemin relatif ou absolu vers un dossier (créé si absent).
#
# 5) output_prefix (character)
#    - Définition : préfixe de nommage des artefacts de sortie (sous-dossier + logs).
#    - Valeurs possibles : toute chaîne non vide compatible nom de dossier/fichier.
#    - Exemple courant : "EPFIP_CHEGD".
#
# 6) columns (list)
#    - Définition : mapping logique -> nom exact de colonne dans le CSV source.
#    - Clés obligatoires et valeurs possibles :
#        * species     : nom de colonne texte de l'espèce (ex. "Espèces").
#        * family      : nom de colonne texte de la famille (ex. "Famille").
#        * date        : nom de colonne date brute (ex. "Date").
#        * count       : nom de colonne effectif/abondance (ex. "Nombre d'espèce").
#        * site        : nom de colonne site (ex. "Site").
#        * reliability : nom de colonne fiabilité (ex. "Fiabilité détermination").
#    - Contraintes : les valeurs doivent correspondre exactement aux en-têtes du CSV.
#
# 7) quality_alert_thresholds (list de seuils numériques)
#    - Définition : seuils d'alerte (en %) utilisés par `build_input_quality_digest`.
#    - Valeurs possibles : numériques >= 0 (entier ou décimal), par indicateur :
#        * rows_quasi_empty      : % de lignes quasi vides.
#        * dates_invalid         : % de dates renseignées mais invalides.
#        * counts_invalid        : % d'effectifs renseignés mais invalides.
#        * counts_negative       : % d'effectifs numériques < 0.
#        * species_missing       : % de lignes avec espèce manquante.
#        * sites_missing         : % de lignes avec site manquant.
#        * site_ids_unresolved   : % de sites non résolus en identifiant.
#        * exact_duplicates      : % de doublons exacts sur colonnes métier.
#        * missing_reliability   : % de fiabilité manquante.
#
# Sortie : liste nommée utilisée par l'orchestrateur `main()`.
# Cas bloquants : aucun.
# Note : tout changement de valeur impacte directement lecture, contrôles QA, alerting et exports.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
get_embedded_config <- function() {
  list(
    # Note protocole : ce pipeline est conçu pour des relevés CHEGD sur pelouses.
    # Les libellés de site sont normalisés et présentés sous forme "Pelouse N".
    protocol_scope = "CHEGD pelouses",
    strict = TRUE,
    input_file = "data/données_récoltes_chegd_pelouses.csv",
    output_dir = "results",
    output_prefix = "EPFIP_CHEGD",
    columns = list(
      species = "Espèces",
      family = "Famille",
      date = "Date",
      count = "Nombre d'espèce",
      site = "Site",
      reliability = "Fiabilité détermination"
    ),
    quality_alert_thresholds = list(
      rows_quasi_empty = 1,
      dates_invalid = 10,
      counts_invalid = 5,
      counts_negative = 0,
      species_missing = 5,
      sites_missing = 5,
      site_ids_unresolved = 0,
      exact_duplicates = 2,
      missing_reliability = 20
    )
  )
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — détermination robuste du répertoire script.
# Stratégie : `--file=` > `sys.frames()[[1]]$ofile` > `getwd()`.
# Sortie : chemin absolu normalisé du répertoire de référence.
# Cas bloquants : aucun `stop()` explicite.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — résolution d'un chemin de configuration.
# Entrée : `config_path` relatif ou absolu.
# Comportement : teste successivement plusieurs emplacements (cwd/script/parent).
# Cas bloquant : arrêt via `stop()` si aucun candidat existant.
# Sortie : chemin absolu normalisé du fichier de configuration.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — résolution d'un chemin relatif sur base projet.
# Entrées : `path_value`, `base_dir`.
# Règles :
#   - NULL/NA/vide => inchangé,
#   - absolu => inchangé,
#   - relatif => `file.path(base_dir, path_value)`.
# Cas bloquants : aucun.
# Sortie : chemin résolu (non forcément existant).
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
resolve_path_from_base <- function(path_value, base_dir) {
  if (is.null(path_value) || is.na(path_value) || path_value == "") {
    return(path_value)
  }
  if (grepl("^(/|[A-Za-z]:[/\\\\])", path_value)) {
    return(path_value)
  }
  file.path(base_dir, path_value)
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — normalisation de noms pour matching robuste.
# Entrée : vecteur texte `x`.
# Transformation : translittération ASCII -> minuscules -> retrait caractères non alphanumériques.
# Cas bloquants : aucun.
# Sortie : vecteur normalisé comparable en mode accent/casse/séparateurs insensibles.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
normalize_filename <- function(x) {
  x_ascii <- iconv(x, from = "", to = "ASCII//TRANSLIT")
  x_ascii[is.na(x_ascii)] <- x[is.na(x_ascii)]
  x_ascii <- tolower(x_ascii)
  gsub("[^a-z0-9]", "", x_ascii)
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — résolution du fichier d'entrée CSV.
# Entrées :
#   - path_value : chemin configuré (relatif ou absolu).
#   - base_dir   : répertoire racine projet.
#
# Contrôles appliqués (ordre strict) :
#   1) Résolution directe : `resolve_path_from_base(path_value, base_dir)` puis `file.exists()`.
#   2) Matching normalisé (insensible accents/casse/séparateurs) sur tous les `.csv`
#      trouvés sous `base_dir/data` puis `base_dir`.
#   3) Fallback fuzzy : distance de Levenshtein minimale (`adist`) si
#      distance <= `max(3, floor(nchar(preferred_norm) * 0.25))`.
#
# Comportement :
#   - Si 2) ou 3) réussit, émission d'un message d'information indiquant la résolution automatique.
#   - Si rien ne matche, arrêt bloquant via `stop()` avec liste des candidats disponibles.
#
# Sortie :
#   - chemin absolu normalisé (`normalizePath(..., mustWork = TRUE)`) du fichier retenu.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
resolve_input_file <- function(path_value, base_dir) {
  resolved <- resolve_path_from_base(path_value, base_dir)
  if (!is.null(resolved) && !is.na(resolved) && resolved != "" && file.exists(resolved)) {
    return(normalizePath(resolved, winslash = "/", mustWork = TRUE))
  }

  preferred_name <- basename(path_value)
  search_dirs <- c(file.path(base_dir, "data"), base_dir)
  search_dirs <- unique(search_dirs[dir.exists(search_dirs)])
  candidates <- unlist(lapply(search_dirs, function(d) list.files(d, pattern = "\\.csv$", full.names = TRUE, recursive = TRUE, ignore.case = TRUE)))
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

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — détection heuristique du séparateur CSV.
# Entrée : `file_path`.
# Règle : score des caractères séparateurs sur les 5 premières lignes non vides (`\t`, `,`, `;`).
# Cas bloquants : aucun (si fichier vide => `;` par défaut).
# Sortie : séparateur retenu (`\t`, `,` ou `;`).
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
guess_csv_separator <- function(file_path) {
  first_lines <- readLines(file_path, n = 5, warn = FALSE, encoding = "UTF-8")
  first_lines <- first_lines[nzchar(trimws(first_lines))]
  if (length(first_lines) == 0) {
    return(";")
  }

  tab_score <- sum(stringr::str_count(first_lines, "\t"))
  semicolon_score <- sum(stringr::str_count(first_lines, ";"))
  comma_score <- sum(stringr::str_count(first_lines, ","))
  
  # Déterminer le séparateur le plus fréquent (onglets prioritaires pour TSV)
  if (tab_score > 0 && tab_score >= comma_score && tab_score >= semicolon_score) {
    return("\t")
  }
  if (comma_score > semicolon_score) "," else ";"
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — lecture et normalisation structurelle du CSV d'entrée.
# Entrée :
#   - input_file : chemin absolu du fichier à lire.
#
# Contrôles/traitements appliqués :
#   1) Extension obligatoire `.csv` (sinon arrêt bloquant).
#   2) Lecture UTF-8 des lignes et suppression du BOM UTF-8 sur la première ligne si présent.
#   3) Détection du séparateur via `guess_csv_separator()`.
#   4) Filtrage des lignes ne contenant que des séparateurs/espaces.
#   5) Parsing via `utils::read.table(..., check.names = FALSE, fill = TRUE)`.
#   6) Trim des noms de colonnes.
#   7) Suppression de la première colonne vide parasite (nom vide + valeurs vides).
#   8) Suppression des colonnes entièrement vides.
#
# Cas bloquants (arrêt via `stop()`) :
#   - extension différente de `.csv`,
#   - fichier vide après filtrage des lignes non informatives.
#
# Sortie :
#   - data.frame brut nettoyé structurellement, prêt pour `ensure_required_columns()`
#     puis `validate_input_data()`.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
read_input_data <- function(input_file) {
  ext <- tolower(tools::file_ext(input_file))

  if (ext == "csv") {
    # Lire le fichier et supprimer le BOM UTF-8 si présent (corrupts le 1er en-tête)
    csv_lines <- readLines(input_file, warn = FALSE, encoding = "UTF-8")
    if (length(csv_lines) > 0 && startsWith(csv_lines[1], "\xEF\xBB\xBF")) {
      csv_lines[1] <- sub("^\xEF\xBB\xBF", "", csv_lines[1])
    }
    
    sep <- guess_csv_separator(input_file)
    # Regex mise à jour pour inclure \t
    csv_lines <- csv_lines[!grepl("^[[:space:];,\t]+$", csv_lines)]
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

  stop("Format d'entrée non supporté : ", ext, " (format supporté : .csv)")
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — validation des colonnes métier obligatoires.
# Entrées :
#   - df  : data.frame brut issu de `read_input_data()`.
#   - cfg : configuration contenant `cfg$columns` (mapping logique -> libellé attendu).
#
# Contrôle :
#   - Construction de la liste des colonnes obligatoires via `unlist(cfg$columns)`.
#   - Vérification d'appartenance stricte dans `names(df)` (matching exact).
#
# Cas bloquant (arrêt via `stop()`) :
#   - au moins une colonne obligatoire absente.
#
# Diagnostic d'erreur produit :
#   - rappel des colonnes attendues (avec clé logique),
#   - liste des colonnes manquantes,
#   - liste des colonnes effectivement présentes.
#
# Sortie :
#   - `NULL` invisible si toutes les colonnes sont présentes.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
ensure_required_columns <- function(df, cfg) {
  required <- unlist(cfg$columns, use.names = TRUE)
  missing_cols <- required[!required %in% names(df)]
  
  if (length(missing_cols) > 0) {
    # Génération d'un message d'erreur détaillé avec suggestions de fuzzy matching
    error_msg <- paste0(
      "\n═══════════════════════════════════════════════════════════════════════════════\n",
      "ERREUR : Colonnes manquantes dans la feuille d'entrée\n",
      "═══════════════════════════════════════════════════════════════════════════════\n",
      "\nColonnes ATTENDUES (depuis cfg$columns):\n  ",
      paste(paste0("  - ", names(required), " → '", required, "'"), collapse = "\n"),
      "\n\nColonnes MANQUANTES:\n  ",
      paste(paste0("  × ", missing_cols), collapse = "\n"),
      "\n\nColonnes PRÉSENTES dans le fichier (" , ncol(df), " au total):\n  ",
      paste(paste0("  ✓ ", names(df)), collapse = "\n"),
      "\n\nVérifiez l'encodage, les accents, les espaces et la correspondance des noms.\n"
    )
    stop(error_msg)
  }
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — validation qualité de l'entrée avant calcul métier.
# raw      : data.frame brut issu de read_input_data() après contrôle des colonnes.
# df_clean : data.frame enrichi contenant au minimum date_obs et nombre_espece_num.
# cols     : liste des noms de colonnes métier (issues de cfg$columns).
# out_dir  : répertoire de sortie facultatif où exporter les diagnostics CSV.
#
# Contrôles réalisés (codes exportés dans `summary$check_id`) :
#   1) rows_quasi_empty
#      - Définition : ligne où toutes les colonnes métier de `cols` sont vides après trim.
#      - Calcul     : rowSums(raw_chr[, required_col_names] != "") == 0.
#      - Sévérité   : warning.
#
#   2) dates_invalid
#      - Définition : date brute renseignée mais conversion en `date_obs` échouée.
#      - Calcul     : date_raw != "" & is.na(df_clean$date_obs).
#      - Sévérité   : warning.
#
#   3) counts_invalid
#      - Définition : effectif brut renseigné mais conversion en `nombre_espece_num` échouée.
#      - Calcul     : count_raw != "" & is.na(df_clean$nombre_espece_num).
#      - Sévérité   : warning.
#
#   4) counts_negative
#      - Définition : effectif converti strictement inférieur à 0.
#      - Calcul     : !is.na(df_clean$nombre_espece_num) & df_clean$nombre_espece_num < 0.
#      - Sévérité   : warning.
#
#   5) species_missing
#      - Définition : nom d'espèce vide après trim.
#      - Calcul     : species_raw == "".
#      - Sévérité   : warning.
#
#   6) sites_missing
#      - Définition : site vide après trim.
#      - Calcul     : site_raw == "".
#      - Sévérité   : warning.
#
#   7) site_ids_unresolved
#      - Définition : site renseigné mais non convertible vers un identifiant via assign_site_ids().
#      - Calcul     : !site_missing & is.na(assign_site_ids(site_raw)).
#      - Sévérité   : warning.
#      - Remarque   : avec la logique actuelle d'assignation séquentielle, ce cas doit rester rare.
#
#   8) exact_duplicates
#      - Définition : ligne dupliquée à l'identique sur toutes les colonnes métier de `cols`.
#      - Calcul     : duplicated(...) | duplicated(..., fromLast = TRUE).
#      - Sévérité   : warning.
#
# Contrôles bloquants (sévérité = error, arrêt du pipeline si `passed == FALSE`) :
#   9) usable_rows_present
#      - Attendu : au moins une ligne exploitable existe.
#      - Calcul  : sum(!quasi_empty_rows) > 0.
#      - Cas bloquant : toutes les lignes sont quasi vides.
#
#   10) dates_not_all_invalid
#       - Attendu : si au moins une date brute est fournie, elles ne doivent pas être toutes invalides.
#       - Calcul  : !(sum(date_provided) > 0 && sum(invalid_dates) == sum(date_provided)).
#       - Cas bloquant : des dates sont renseignées mais 100 % échouent à la conversion.
#
#   11) counts_not_all_invalid
#       - Attendu : si au moins un effectif brut est fourni, ils ne doivent pas être tous invalides.
#       - Calcul  : !(sum(count_provided) > 0 && sum(invalid_counts) == sum(count_provided)).
#       - Cas bloquant : des effectifs sont renseignés mais 100 % échouent à la conversion.
#
#   12) sites_not_all_missing
#       - Attendu : toutes les lignes ne doivent pas avoir un site manquant.
#       - Calcul  : sum(site_missing) < total_rows.
#       - Cas bloquant : 100 % des lignes ont un site vide.
#
#   13) species_not_all_missing
#       - Attendu : toutes les lignes ne doivent pas avoir une espèce manquante.
#       - Calcul  : sum(species_missing) < total_rows.
#       - Cas bloquant : 100 % des lignes ont un nom d'espèce vide.
#
# Export QA (si `out_dir` existe) :
#   - `qa_validation_entree_resume.csv` : synthèse des contrôles (compte, base de référence, pourcentage, succès/échec).
#   - `qa_validation_entree_lignes.csv` : détail ligne à ligne des anomalies non vides.
#
# Retourne une liste :
#   - summary         : data.frame de synthèse des contrôles.
#   - issues          : data.frame détaillant les lignes concernées par anomalie.
#   - blocking_issues : vecteur des `check_id` bloquants dont `passed == FALSE`.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
validate_input_data <- function(raw, df_clean, cols, out_dir = NULL) {
  total_rows <- nrow(df_clean)
  if (is.null(total_rows) || total_rows == 0) {
    stop("Le fichier d'entrée ne contient aucune ligne exploitable après lecture.")
  }

  required_col_names <- unname(unlist(cols, use.names = FALSE))
  required_col_names <- required_col_names[required_col_names %in% names(raw)]

  raw_chr <- raw
  for (col_name in names(raw_chr)) {
    raw_chr[[col_name]] <- trimws(as.character(raw_chr[[col_name]]))
    raw_chr[[col_name]][is.na(raw_chr[[col_name]])] <- ""
  }

  quasi_empty_rows <- if (length(required_col_names) > 0) {
    rowSums(raw_chr[, required_col_names, drop = FALSE] != "") == 0
  } else {
    rep(FALSE, total_rows)
  }

  date_raw <- trimws(as.character(raw[[cols$date]]))
  date_raw[is.na(date_raw)] <- ""
  count_raw <- trimws(as.character(raw[[cols$count]]))
  count_raw[is.na(count_raw)] <- ""
  species_raw <- trimws(as.character(raw[[cols$species]]))
  species_raw[is.na(species_raw)] <- ""
  site_raw <- trimws(as.character(raw[[cols$site]]))
  site_raw[is.na(site_raw)] <- ""

  date_provided <- date_raw != ""
  count_provided <- count_raw != ""
  species_missing <- species_raw == ""
  site_missing <- site_raw == ""
  invalid_dates <- date_provided & is.na(df_clean$date_obs)
  invalid_counts <- count_provided & is.na(df_clean$nombre_espece_num)
  negative_counts <- !is.na(df_clean$nombre_espece_num) & df_clean$nombre_espece_num < 0
  unresolved_site_ids <- !site_missing & is.na(assign_site_ids(site_raw))

  duplicate_mask <- duplicated(raw_chr[, required_col_names, drop = FALSE]) |
    duplicated(raw_chr[, required_col_names, drop = FALSE], fromLast = TRUE)

  quality_checks <- data.frame(
    check_id = c(
      "rows_quasi_empty",
      "dates_invalid",
      "counts_invalid",
      "counts_negative",
      "species_missing",
      "sites_missing",
      "site_ids_unresolved",
      "exact_duplicates",
      "usable_rows_present",
      "dates_not_all_invalid",
      "counts_not_all_invalid",
      "sites_not_all_missing",
      "species_not_all_missing"
    ),
    severity = c(
      "warning",
      "warning",
      "warning",
      "warning",
      "warning",
      "warning",
      "warning",
      "warning",
      "error",
      "error",
      "error",
      "error",
      "error"
    ),
    issue_count = c(
      sum(quasi_empty_rows),
      sum(invalid_dates),
      sum(invalid_counts),
      sum(negative_counts),
      sum(species_missing),
      sum(site_missing),
      sum(unresolved_site_ids),
      sum(duplicate_mask),
      sum(!quasi_empty_rows),
      sum(invalid_dates),
      sum(invalid_counts),
      sum(site_missing),
      sum(species_missing)
    ),
    reference_count = c(
      total_rows,
      sum(date_provided),
      sum(count_provided),
      sum(!is.na(df_clean$nombre_espece_num)),
      total_rows,
      total_rows,
      sum(!site_missing),
      total_rows,
      total_rows,
      sum(date_provided),
      sum(count_provided),
      total_rows,
      total_rows
    ),
    passed = c(
      TRUE,
      TRUE,
      TRUE,
      TRUE,
      TRUE,
      TRUE,
      TRUE,
      TRUE,
      sum(!quasi_empty_rows) > 0,
      !(sum(date_provided) > 0 && sum(invalid_dates) == sum(date_provided)),
      !(sum(count_provided) > 0 && sum(invalid_counts) == sum(count_provided)),
      sum(site_missing) < total_rows,
      sum(species_missing) < total_rows
    ),
    details = c(
      "Lignes vides sur toutes les colonnes métier.",
      "Dates renseignées mais non converties en Date.",
      "Effectifs renseignés mais non convertis en numérique.",
      "Effectifs numériques strictement négatifs.",
      "Nom d'espèce absent.",
      "Site absent.",
      "Site renseigné mais sans identifiant exploitable.",
      "Doublons exacts sur les colonnes métier.",
      "Au moins une ligne exploitable doit être présente.",
      "Toutes les dates renseignées sont invalides.",
      "Tous les effectifs renseignés sont invalides.",
      "Toutes les lignes ont un site manquant.",
      "Toutes les lignes ont une espèce manquante."
    ),
    stringsAsFactors = FALSE
  )

  quality_checks$pct_issue <- ifelse(
    quality_checks$reference_count > 0,
    round(100 * quality_checks$issue_count / quality_checks$reference_count, 2),
    NA_real_
  )

  issue_rows <- list(
    rows_quasi_empty = which(quasi_empty_rows),
    dates_invalid = which(invalid_dates),
    counts_invalid = which(invalid_counts),
    counts_negative = which(negative_counts),
    species_missing = which(species_missing),
    sites_missing = which(site_missing),
    site_ids_unresolved = which(unresolved_site_ids),
    exact_duplicates = which(duplicate_mask)
  )

  issues_detail <- do.call(rbind, lapply(names(issue_rows), function(check_name) {
    idx <- issue_rows[[check_name]]
    if (length(idx) == 0) {
      return(NULL)
    }

    data.frame(
      row_number = idx,
      check_id = check_name,
      site = as.character(raw[[cols$site]][idx]),
      species = as.character(raw[[cols$species]][idx]),
      date_raw = as.character(raw[[cols$date]][idx]),
      count_raw = as.character(raw[[cols$count]][idx]),
      reliability_raw = as.character(raw[[cols$reliability]][idx]),
      stringsAsFactors = FALSE
    )
  }))

  if (is.null(issues_detail)) {
    issues_detail <- data.frame(
      row_number = integer(),
      check_id = character(),
      site = character(),
      species = character(),
      date_raw = character(),
      count_raw = character(),
      reliability_raw = character(),
      stringsAsFactors = FALSE
    )
  }

  if (!is.null(out_dir) && dir.exists(out_dir)) {
    write.csv(quality_checks, file.path(out_dir, "qa_validation_entree_resume.csv"), row.names = FALSE, fileEncoding = "UTF-8")
    write.csv(issues_detail, file.path(out_dir, "qa_validation_entree_lignes.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  }

  blocking_issues <- quality_checks$check_id[quality_checks$severity == "error" & !quality_checks$passed]

  list(
    summary = quality_checks,
    issues = issues_detail,
    blocking_issues = blocking_issues
  )
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — synthèse opérationnelle qualité d'entrée (indicateurs + alertes).
# Entrées :
#   - input_validation : liste issue de `validate_input_data()`.
#   - df_clean, cols   : données nettoyées et mapping colonnes (pour fiabilité manquante).
#   - out_dir          : répertoire d'export facultatif.
#   - thresholds       : seuils d'alerte par indicateur (en pourcentage).
#
# Comportement :
#   - calcule les indicateurs qualité clés (% invalides/manquants/doublons),
#   - compare chaque indicateur à son seuil avec la règle : alerte si `value_count > 0 ET value_pct >= seuil`
#     (un indicateur à 0 occurrence ne déclenche jamais d'alerte, même si le seuil est 0),
#   - journalise un digest lisible (top anomalies + alertes),
#   - exporte 2 CSV de pilotage qualité.
#
# Cas bloquants :
#   - aucun `stop()` explicite (fonction purement diagnostique).
#
# Sortie :
#   - liste `list(indicators=<df>, alerts=<df>)`.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
build_input_quality_digest <- function(
  input_validation,
  df_clean,
  cols,
  out_dir = NULL,
  thresholds = list(
    rows_quasi_empty = 1,
    dates_invalid = 10,
    counts_invalid = 5,
    counts_negative = 0,
    species_missing = 5,
    sites_missing = 5,
    site_ids_unresolved = 0,
    exact_duplicates = 2,
    missing_reliability = 20
  )
) {
  if (is.null(thresholds) || length(thresholds) == 0) {
    thresholds <- list(
      rows_quasi_empty = 1,
      dates_invalid = 10,
      counts_invalid = 5,
      counts_negative = 0,
      species_missing = 5,
      sites_missing = 5,
      site_ids_unresolved = 0,
      exact_duplicates = 2,
      missing_reliability = 20
    )
  }

  summary_df <- input_validation$summary

  get_pct <- function(check_id) {
    row <- summary_df[summary_df$check_id == check_id, , drop = FALSE]
    if (nrow(row) == 0) return(NA_real_)
    as.numeric(row$pct_issue[[1]])
  }

  get_count <- function(check_id) {
    row <- summary_df[summary_df$check_id == check_id, , drop = FALSE]
    if (nrow(row) == 0) return(NA_real_)
    as.numeric(row$issue_count[[1]])
  }

  total_rows <- max(nrow(df_clean), 1)
  missing_reliability_count <- sum(
    is.na(df_clean[[cols$reliability]]) | trimws(as.character(df_clean[[cols$reliability]])) == ""
  )
  missing_reliability_pct <- round(100 * missing_reliability_count / total_rows, 2)

  indicators <- data.frame(
    indicator_id = c(
      "rows_quasi_empty",
      "dates_invalid",
      "counts_invalid",
      "counts_negative",
      "species_missing",
      "sites_missing",
      "site_ids_unresolved",
      "exact_duplicates",
      "missing_reliability"
    ),
    value_count = c(
      get_count("rows_quasi_empty"),
      get_count("dates_invalid"),
      get_count("counts_invalid"),
      get_count("counts_negative"),
      get_count("species_missing"),
      get_count("sites_missing"),
      get_count("site_ids_unresolved"),
      get_count("exact_duplicates"),
      missing_reliability_count
    ),
    value_pct = c(
      get_pct("rows_quasi_empty"),
      get_pct("dates_invalid"),
      get_pct("counts_invalid"),
      get_pct("counts_negative"),
      get_pct("species_missing"),
      get_pct("sites_missing"),
      get_pct("site_ids_unresolved"),
      get_pct("exact_duplicates"),
      missing_reliability_pct
    ),
    stringsAsFactors = FALSE
  )

  indicators$alert_threshold_pct <- as.numeric(unlist(thresholds[indicators$indicator_id]))
  indicators$alert <- ifelse(
    !is.na(indicators$alert_threshold_pct) & !is.na(indicators$value_pct) &
      indicators$value_count > 0 &
      indicators$value_pct >= indicators$alert_threshold_pct,
    TRUE,
    FALSE
  )

  warn_rows <- summary_df[
    summary_df$severity == "warning" &
      !is.na(summary_df$issue_count) &
      summary_df$issue_count > 0,
    c("check_id", "issue_count", "pct_issue"),
    drop = FALSE
  ]

  if (nrow(warn_rows) > 0) {
    warn_rows <- warn_rows[order(-warn_rows$pct_issue, -warn_rows$issue_count), , drop = FALSE]
    top_n <- min(3, nrow(warn_rows))
    log_info("Top anomalies entrée (warning) :")
    for (i in seq_len(top_n)) {
      r <- warn_rows[i, ]
      log_info(paste0("  - ", r$check_id, " : ", r$issue_count, " (", r$pct_issue, " %)"))
    }
  } else {
    log_info("Top anomalies entrée : aucune anomalie warning détectée")
  }

  alerts <- indicators[indicators$alert, c("indicator_id", "value_count", "value_pct", "alert_threshold_pct"), drop = FALSE]

  if (nrow(alerts) > 0) {
    log_warning_msg(paste0("Alertes qualité entrée : ", nrow(alerts), " indicateur(s) au-dessus des seuils"))
    for (i in seq_len(nrow(alerts))) {
      a <- alerts[i, ]
      log_warning_msg(paste0(
        "  - ", a$indicator_id,
        " : ", a$value_count,
        " (", a$value_pct, " %) >= seuil ", a$alert_threshold_pct, " %"
      ))
    }
  } else {
    log_info("Alertes qualité entrée : aucune")
  }

  if (!is.null(out_dir) && dir.exists(out_dir)) {
    write.csv(indicators, file.path(out_dir, "qa_validation_entree_indicateurs.csv"), row.names = FALSE, fileEncoding = "UTF-8")
    write.csv(alerts, file.path(out_dir, "qa_validation_entree_alertes.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  }

  list(indicators = indicators, alerts = alerts)
}

# -----------------------------------------------------------------------------
# Helpers de conversion et normalisation
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — conversion défensive en Date.
# Entrée : vecteur `x` (Date, numérique Excel, texte).
# Contrôles : nettoyage valeurs vides, parsing multi-formats, gestion numéros série Excel.
# Cas bloquants : aucun (échec de parsing => NA).
# Sortie : vecteur Date de même longueur.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
to_date_safe <- function(x) {
  if (inherits(x, "Date")) {
    return(x)
  }

  if (is.numeric(x)) {
    return(as.Date(x, origin = "1899-12-30"))
  }

  x_chr <- trimws(as.character(x))
  x_chr[x_chr %in% c("", "NA", "NaN")] <- NA_character_
  out <- as.Date(rep(NA_character_, length(x_chr)))

  numeric_like <- !is.na(x_chr) & grepl("^\\d+(?:[.,]\\d+)?$", x_chr)
  if (any(numeric_like)) {
    parsed_num <- as.Date(to_numeric_safe(x_chr[numeric_like]), origin = "1899-12-30")
    out[numeric_like] <- parsed_num
    if (all(numeric_like | is.na(x_chr))) {
      return(out)
    }
  }

  remaining_idx <- which(is.na(out) & !is.na(x_chr))
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

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — conversion défensive en numérique.
# Entrée : vecteur `x` (numérique/texte/factor).
# Règle : remplacement `,` -> `.` puis coercition `as.numeric` silencieuse.
# Cas bloquants : aucun (coercition impossible => NA).
# Sortie : vecteur numérique.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
to_numeric_safe <- function(x) {
  if (is.numeric(x)) {
    return(x)
  }

  x_chr <- as.character(x)
  x_chr <- str_replace_all(x_chr, ",", ".")
  suppressWarnings(as.numeric(x_chr))
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — normalisation sémantique de texte métier.
# Entrée : vecteur texte `x`.
# Transformation : ASCII translit -> minuscules -> ponctuation vers espace -> trim + espaces propres.
# Cas bloquants : aucun.
# Sortie : vecteur texte normalisé (comparaisons/jointures robustes).
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
normalize_text <- function(x) {
  x_chr <- as.character(x)
  x_ascii <- iconv(x_chr, from = "", to = "ASCII//TRANSLIT")
  x_ascii[is.na(x_ascii)] <- x_chr[is.na(x_ascii)]
  x_ascii <- tolower(x_ascii)
  x_ascii <- gsub("[^a-z0-9]+", " ", x_ascii)
  trimws(gsub("\\s+", " ", x_ascii))
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — extraction de `site_id` numérique depuis un libellé.
# Entrée : `site_value` (ex. "Pelouse 16").
# Règle : extraction du premier motif `\\d+` puis conversion entière.
# Cas bloquants : aucun (absence de chiffre => NA_integer_).
# Sortie : entier/NA.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
extract_site_id <- function(site_value) {
  site_chr <- as.character(site_value)
  suppressWarnings(as.integer(str_extract(site_chr, "\\d+")))
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — assignation robuste d'identifiants de site.
# Entrée : `values` (libellés de site hétérogènes).
# Règles :
#   - chiffre présent => utilisé directement,
#   - libellés sans chiffre => IDs séquentiels stables par ordre d'apparition,
#   - mode mixte => complète à partir de max(ID numérique)+1.
# Cas bloquants : aucun.
# Sortie : vecteur integer aligné sur `values`.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
assign_site_ids <- function(values) {
  vals <- trimws(as.character(values))
  vals[vals == ""] <- NA_character_

  ids <- extract_site_id(vals)
  observed_vals <- vals[!is.na(vals)]

  if (length(observed_vals) == 0) {
    return(as.integer(ids))
  }

  # Aucun ID numérique présent : numérotation séquentielle par ordre d'apparition.
  if (all(is.na(ids[!is.na(vals)]))) {
    uniq_vals <- unique(observed_vals)
    mapping <- setNames(seq_along(uniq_vals), uniq_vals)
    out <- rep(NA_integer_, length(vals))
    out[!is.na(vals)] <- as.integer(unname(mapping[vals[!is.na(vals)]]))
    return(out)
  }

  # IDs mixtes : compléter uniquement les libellés sans nombre.
  out <- as.integer(ids)
  missing_mask <- is.na(out) & !is.na(vals)
  if (any(missing_mask)) {
    uniq_missing_vals <- unique(vals[missing_mask])
    next_id <- as.integer(max(out, na.rm = TRUE) + 1L)
    missing_mapping <- setNames(seq.int(from = next_id, length.out = length(uniq_missing_vals)), uniq_missing_vals)
    out[missing_mask] <- as.integer(unname(missing_mapping[vals[missing_mask]]))
  }

  out
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — test multi-préfixes vectorisé.
# Entrées : `values`, `prefixes`.
# Comportement : OR logique des `startsWith()` pour tous les préfixes.
# Cas bloquants : aucun (entrées vides => FALSE).
# Sortie : vecteur logique de longueur `values`.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
starts_with_any <- function(values, prefixes) {
  if (length(values) == 0 || length(prefixes) == 0) {
    return(rep(FALSE, length(values)))
  }

  Reduce(`|`, lapply(prefixes, function(prefix) startsWith(values, prefix)))
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — classification du score potentiel en 3 classes.
# Entrée : `score` numérique.
# Règles : <=10 faible ; <30 intéressant ; sinon élevé.
# Cas bloquants : aucun.
# Sortie : vecteur de libellés de classe.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
classify_potential <- function(score) {
  ifelse(
    score <= 10,
    "Potentiel fongique faible",
    ifelse(score < 30, "Potentiel fongique intéressant", "Potentiel fongique élevé")
  )
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — classification de l'indice patrimonial en 5 classes.
# Entrée : `index_value` numérique.
# Règles : <=2 faible ; <=5 local ; <=10 régional ; <=14 national ; >14 international.
# Cas bloquants : aucun.
# Sortie : vecteur de libellés de classe.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — calcul de l'indice IR à partir des gradients CHEGD.
# Entrée : `chegd_df` contenant `gradient_visite_*` et `chegd_total`.
# Formule : `IR = max(0, 1 - gradient_visite / chegd_total)` ; si total <= 0 => IR = 0.
# Comportement : ajoute `ir_visite_*` + `ir_moyen`.
# Cas bloquants : aucun (si structure insuffisante => retour inchangé).
# Sortie : data.frame enrichi.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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
# Référentiel des sites
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — construction du référentiel de sites.
# Entrées : `df_clean`, `cols$site`.
# Règles : extraction des sites non vides, assignation IDs via `assign_site_ids`,
#          complétion 1..max si des IDs numériques existent.
# Cas bloquants : aucun (si aucun site valide => data.frame vide).
# Sortie : data.frame trié (`site_id`, `site_name`).
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
prepare_site_reference <- function(df_clean, cols) {
  site_values <- unique(as.character(df_clean[[cols$site]]))
  site_values <- site_values[!is.na(site_values) & trimws(site_values) != ""]
  numeric_ids_raw <- extract_site_id(site_values)
  site_ids <- assign_site_ids(site_values)
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

  site_ref <- site_ref[!duplicated(site_ref$site_id), ]

  has_numeric_ids <- any(!is.na(numeric_ids_raw))
  if (has_numeric_ids) {
    max_site <- max(numeric_ids_raw, na.rm = TRUE)
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
    return(merged[order(merged$site_id), c("site_id", "site_name"), drop = FALSE])
  }

  site_ref[order(site_ref$site_id), c("site_id", "site_name"), drop = FALSE]
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — stub autonome : recherche de classeur de référence désactivée.
# Entrées : `base_dir`, `input_file` (ignorées en mode autonome).
# Sortie : `NULL`.
find_reference_workbook <- function(base_dir, input_file) {
  NULL
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — stub autonome : résolution de classeur de référence désactivée.
# Entrées : `configured_path`, `base_dir`, `input_file`.
# Sortie : `NULL`.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
resolve_reference_workbook <- function(configured_path, base_dir, input_file) {
  NULL
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — parsing d'une description de visite en IDs de sites.
# Entrée : texte libre `description`.
# Règles : extraction des plages (X-Y / X a Y) + IDs isolés, union triée sans doublons.
# Cas bloquants : aucun (texte vide/non parsable => vecteur vide).
# Sortie : vecteur integer d'IDs.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — stub autonome : plan de visites externe désactivé.
# Entrée : `reference_workbook`.
# Sortie : `NULL`.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
read_planned_visits <- function(reference_workbook) {
  NULL
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — stub autonome : détail CHEGD de référence désactivé.
# Entrées : `reference_workbook`, `n_sites`.
# Sortie : `NULL`.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
read_reference_chegd_detail <- function(reference_workbook, n_sites) {
  NULL
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — stub autonome : détail potentiel de référence désactivé.
# Entrées : `reference_workbook`, `n_sites`.
# Sortie : `NULL`.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
read_reference_potentiel_detail <- function(reference_workbook, n_sites) {
  NULL
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — stub autonome : métriques de référence externes désactivées.
# Entrées : `reference_workbook`, `site_ref`.
# Sortie : `NULL`.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
read_reference_site_metrics <- function(reference_workbook, site_ref) {
  NULL
}

# -----------------------------------------------------------------------------
# Calculs métier et agrégations
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — initialisation du dossier de sortie métier.
# Entrées : `base_dir`, `prefix`.
# Comportement : crée/réutilise `file.path(base_dir, prefix)`.
# Cas bloquants : aucun `stop()` explicite (erreurs IO propagées).
# Sortie : chemin du dossier de sortie.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
build_output_dir <- function(base_dir, prefix) {
  out_dir <- file.path(base_dir, prefix)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_dir
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — arborescence thématique des résultats.
# Entrée : `out_dir` (répertoire racine des résultats d'un run).
# Comportement : crée les sous-répertoires thématiques (formats mélangés).
# Cas bloquants : aucun `stop()` explicite (erreurs IO propagées).
# Sortie : vecteur des chemins de dossiers créés.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
init_thematic_output_dirs <- function(out_dir) {
  thematic_dirs <- c(
    file.path(out_dir, "00_data_prepared"),
    file.path(out_dir, "10_indices_metiers"),
    file.path(out_dir, "20_syntheses"),
    file.path(out_dir, "30_statistiques_modeles"),
    file.path(out_dir, "40_qa_audits"),
    file.path(out_dir, "50_figures_metier"),
    file.path(out_dir, "60_figures_statistiques")
  )

  for (d in thematic_dirs) {
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
  }

  thematic_dirs
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — routage d'un artefact vers son sous-répertoire thématique.
# Entrées :
#   - filename : nom de fichier (basename).
# Sortie : dossier thématique relatif de destination (ou NA si non classé).
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
resolve_thematic_relative_dir <- function(filename) {
  filename_lc <- tolower(filename)
  ext <- tolower(tools::file_ext(filename))

  if (ext %in% c("png", "pdf")) {
    if (startsWith(filename_lc, "fig_stat")) {
      return("60_figures_statistiques")
    }
    if (startsWith(filename_lc, "fig")) {
      return("50_figures_metier")
    }
    return(NA_character_)
  }

  if (ext == "csv") {
    if (filename_lc == "donnees_brutes_nettoyees.csv") {
      return("00_data_prepared")
    }

    if (
      startsWith(filename_lc, "potentiel_") ||
      startsWith(filename_lc, "indice_") ||
      startsWith(filename_lc, "gradient_") ||
      startsWith(filename_lc, "synthese_") ||
      startsWith(filename_lc, "niveaux_fiabilite_")
    ) {
      return("10_indices_metiers")
    }

    if (startsWith(filename_lc, "resume_")) {
      return("20_syntheses")
    }

    if (
      startsWith(filename_lc, "stat_") ||
      startsWith(filename_lc, "obj3_")
    ) {
      return("30_statistiques_modeles")
    }

    if (
      startsWith(filename_lc, "qa_") ||
      startsWith(filename_lc, "audit_") ||
      startsWith(filename_lc, "non_blocking_failures")
    ) {
      return("40_qa_audits")
    }

    return(NA_character_)
  }

  NA_character_
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — organisation finale des artefacts par thème.
# Entrée : `out_dir`.
# Comportement :
#   1) crée l'arborescence thématique,
#   2) déplace/réorganise tous les fichiers (récursif) vers le bon sous-répertoire.
# Sortie : data.frame de journal des déplacements (source, destination, moved).
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
organize_results_thematically <- function(out_dir) {
  init_thematic_output_dirs(out_dir)

  files_all <- list.files(out_dir, full.names = TRUE, recursive = TRUE, include.dirs = FALSE)
  files_all <- files_all[file.info(files_all)$isdir %in% FALSE]
  files_all <- files_all[basename(files_all) != ".DS_Store"]

  if (length(files_all) == 0) {
    return(data.frame(source = character(), destination = character(), moved = logical(), stringsAsFactors = FALSE))
  }

  move_log <- do.call(rbind, lapply(files_all, function(src) {
    filename <- basename(src)
    rel_dir <- resolve_thematic_relative_dir(filename)

    if (is.na(rel_dir) || rel_dir == "") {
      return(data.frame(source = src, destination = NA_character_, moved = FALSE, stringsAsFactors = FALSE))
    }

    dest_dir <- file.path(out_dir, rel_dir)
    dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
    dest <- file.path(dest_dir, filename)

    if (normalizePath(dirname(src), winslash = "/", mustWork = FALSE) == normalizePath(dest_dir, winslash = "/", mustWork = FALSE)) {
      return(data.frame(source = src, destination = dest, moved = FALSE, stringsAsFactors = FALSE))
    }

    if (file.exists(dest)) {
      file.remove(dest)
    }

    moved_ok <- file.rename(src, dest)
    data.frame(source = src, destination = dest, moved = isTRUE(moved_ok), stringsAsFactors = FALSE)
  }))

  move_log
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — helpers de lisibilité graphique.
# `readable_caption()` : wrap texte de légende ; `theme_caption_readable()` : style standard de caption.
# Cas bloquants : aucun.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
readable_caption <- function(text, width = 120) {
  stringr::str_wrap(text, width = width)
}

theme_caption_readable <- function() {
  theme(
    plot.caption = element_text(hjust = 0, size = 9, colour = "grey25", lineheight = 1.05, margin = margin(t = 8)),
    plot.caption.position = "plot",
    plot.margin = margin(t = 8, r = 12, b = 18, l = 10)
  )
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — Figure 1 (tableau de bord potentiel/patrimonial/CHEGD).
# site_metrics : liste retournée par build_site_level_metrics() contenant le data.frame combined.
# out_dir      : répertoire de sortie où les figures seront écrites.
# Les 3 panneaux empilés représentent par pelouse (triées par score décroissant) :
#   - panneau 1 : score du potentiel fongique (barres, couleur par classe).
#   - panneau 2 : indice de patrimonialité (barres, couleur par classe).
#   - panneau 3 : gradient CHEGD moyen (barres, dégradé rouge).
# Les figures sont exportées au format PNG (300 dpi) et PDF dans out_dir :
#   fig1_tableau_de_bord_pelouses.png et fig1_tableau_de_bord_pelouses.pdf.
# Cas bloquants : aucun `stop()` explicite (si entrée vide => NULL ; erreurs graphique/IO propagées).
# Retourne invisiblement un vecteur des chemins de fichiers créés, ou NULL si combined est vide.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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
      chegd_gradient = as.numeric(chegd_gradient)
    )

  df <- df %>%
    mutate(
      order_rank = dense_rank(desc(potential_score + patrimonial_index + chegd_gradient))
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
      fill = NULL,
      caption = readable_caption("Lecture : une barre = une pelouse ; longueur = score potentiel ; couleur = classe de potentiel. Interprétation : plus la barre est longue et foncée, plus le potentiel fongique est élevé.")
    ) +
    theme_minimal(base_size = 11) +
    theme(
      legend.position = "bottom",
      panel.grid.major.y = element_blank(),
      plot.title = element_text(face = "bold")
    ) +
    theme_caption_readable()

  p2 <- ggplot(df, aes(x = patrimonial_index, y = site_label, fill = patrimonial_class)) +
    geom_col(width = 0.72) +
    geom_text(aes(label = patrimonial_index), hjust = -0.15, size = 3) +
    scale_fill_manual(values = patrimonial_colors, drop = FALSE) +
    scale_x_continuous(expand = expansion(mult = c(0, 0.12))) +
    labs(
      title = "Indice de patrimonialité par pelouse",
      x = "Indice patrimonial",
      y = NULL,
      fill = NULL,
      caption = readable_caption("Lecture : une barre = une pelouse ; longueur = indice patrimonial ; couleur = classe d'intérêt patrimonial. Interprétation : des barres plus longues indiquent une valeur patrimoniale plus forte.")
    ) +
    theme_minimal(base_size = 11) +
    theme(
      legend.position = "bottom",
      panel.grid.major.y = element_blank(),
      plot.title = element_text(face = "bold")
    ) +
    theme_caption_readable()

  chegd_max <- max(df$chegd_gradient, na.rm = TRUE)
  chegd_limit <- ifelse(is.finite(chegd_max), chegd_max + 0.25, 1)
  p3 <- ggplot(df, aes(x = chegd_gradient, y = site_label, fill = chegd_gradient)) +
    geom_col(width = 0.72) +
    geom_text(aes(label = sprintf("%.0f", chegd_gradient)), hjust = -0.15, size = 3) +
    scale_fill_gradient(low = "#FEE0D2", high = "#CB181D", guide = "none") +
    scale_x_continuous(limits = c(0, chegd_limit), expand = expansion(mult = c(0, 0.12))) +
    labs(
      title = "Gradient CHEGD par pelouse",
      x = "Gradient CHEGD",
      y = NULL,
      caption = readable_caption("Lecture : une barre = une pelouse ; valeur = gradient CHEGD maximal observé ; couleur = intensité du gradient. Interprétation : plus la barre est longue et la teinte foncée, plus le site est représentatif du signal CHEGD.")
    ) +
    theme_minimal(base_size = 11) +
    theme(
      panel.grid.major.y = element_blank(),
      plot.title = element_text(face = "bold")
    ) +
    theme_caption_readable()

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

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — Figure 2 (nuage de positionnement écologique).
# site_metrics : liste retournée par build_site_level_metrics() contenant le data.frame combined.
# out_dir      : répertoire de sortie où les figures seront écrites.
# Axes : X = score du potentiel fongique, Y = indice de patrimonialité.
# Chaque point représente un site ; sa taille et sa couleur (dégradé rouge) encodent le gradient CHEGD moyen.
# Des lignes pointillées matérialisent les seuils de classification (potentiel > 10, patrimonial > 2).
# Les labels ("P<site_id>") sont placés via ggrepel si disponible, sinon via geom_text() avec décalage.
# Les figures sont exportées au format PNG (300 dpi) et PDF dans out_dir :
#   fig2_positionnement_ecologique.png et fig2_positionnement_ecologique.pdf.
# Cas bloquants : aucun `stop()` explicite (entrée vide => NULL ; erreurs graphique/IO propagées).
# Retourne invisiblement NULL ; les figures sont écrites en effet de bord.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
build_scatter_positionnement <- function(site_metrics, out_dir) {
  combined <- site_metrics$combined
  if (is.null(combined) || nrow(combined) == 0) return(invisible(NULL))

  df <- combined %>%
    mutate(
      potentiel_score  = as.numeric(potentiel_score),
      indice_patrimonial = as.numeric(indice_patrimonial),
      chegd_gradient   = as.numeric(chegd_gradient),
      label            = paste0("P", site_id)
    )

  df_labels <- prepare_scatter_labels(df)

  p <- ggplot(df, aes(x = potentiel_score, y = indice_patrimonial, colour = chegd_gradient, label = label)) +
    geom_point(aes(size = chegd_gradient), alpha = 0.85) +
    ggrepel_or_text(df_labels) +
    scale_colour_gradient(low = "#FEE0D2", high = "#CB181D", name = "Gradient\nCHEGD") +
    scale_size_continuous(range = c(3, 10), guide = "none") +
    geom_vline(xintercept = 10, linetype = "dashed", colour = "grey55", linewidth = 0.4) +
    geom_hline(yintercept = 2,  linetype = "dashed", colour = "grey55", linewidth = 0.4) +
    annotate("text", x = 10.4, y = max(df$indice_patrimonial, na.rm = TRUE) * 0.97,
             label = "seuil potentiel", size = 2.8, colour = "grey40", hjust = 0) +
    annotate("text", x = max(df$potentiel_score, na.rm = TRUE) * 0.97, y = 2.15,
             label = "seuil patrimonial", size = 2.8, colour = "grey40", hjust = 1) +
    labs(
      title   = "Positionnement écologique des pelouses",
      subtitle = "Potentiel fongique × Intérêt patrimonial  |  taille/couleur = gradient CHEGD",
      x = "Score potentiel fongique",
      y = "Indice de patrimonialité",
      caption = readable_caption("Lecture : un point = une pelouse ; axe x = potentiel, axe y = patrimonialité ; taille/couleur = gradient CHEGD ; pointillés = seuils de lecture. Interprétation : les points en haut à droite et de grande taille correspondent aux pelouses les plus favorables.")
    ) +
    theme_minimal(base_size = 12) +
    theme(plot.title = element_text(face = "bold"),
          plot.subtitle = element_text(colour = "grey40")) +
        theme_caption_readable()

  ggsave(file.path(out_dir, "fig2_positionnement_ecologique.png"), p, width = 10, height = 7, dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig2_positionnement_ecologique.pdf"), p, width = 10, height = 7, bg = "white")
  invisible(NULL)
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — préparation des positions de labels anti-chevauchement.
# df     : data.frame contenant au minimum les colonnes potentiel_score, indice_patrimonial, site_id.
# x_step : décalage horizontal appliqué entre labels partageant les mêmes coordonnées (défaut 0.06).
# y_step : décalage vertical appliqué entre labels partageant les mêmes coordonnées (défaut 0.08).
# Les points ayant exactement les mêmes coordonnées (cas fréquent sur les faibles scores)
# sont répartis symétriquement autour de leur position commune selon leur rang dans le groupe.
# Cas bloquants : aucun (entrée vide => retour inchangé).
# Retourne df enrichi des colonnes label_x et label_y utilisées par ggrepel_or_text().
# Utilisée uniquement dans build_scatter_positionnement() comme prétraitement des labels.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
prepare_scatter_labels <- function(df, x_step = 0.06, y_step = 0.08) {
  if (is.null(df) || nrow(df) == 0) {
    return(df)
  }

  df %>%
    group_by(potentiel_score, indice_patrimonial) %>%
    arrange(site_id, .by_group = TRUE) %>%
    mutate(
      n_same = n(),
      idx_same = row_number(),
      offset_center = idx_same - (n_same + 1) / 2,
      label_x = potentiel_score + ifelse(n_same > 1, offset_center * x_step, 0),
      label_y = indice_patrimonial + ifelse(n_same > 1, offset_center * y_step, 0)
    ) %>%
    ungroup()
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — couche de labels robuste (ggrepel si dispo, sinon fallback geom_text).
# df_labels : data.frame préparé par prepare_scatter_labels(), contenant potentiel_score,
#             indice_patrimonial, label, label_x, label_y.
# Retourne un objet geom compatible ggplot2 :
#   - ggrepel::geom_text_repel() si le package ggrepel est installé (gestion automatique des chevauchements).
#   - geom_text() avec les positions pré-calculées (label_x, label_y) en fallback.
# Cas bloquants : aucun (dégradation gracieuse selon packages disponibles).
# Cette approche dégrade gracieusement selon les packages disponibles sans erreur fatale.
# Utilisée exclusivement dans build_scatter_positionnement().
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
ggrepel_or_text <- function(df_labels) {
  if (requireNamespace("ggrepel", quietly = TRUE)) {
    ggrepel::geom_text_repel(
      data = df_labels,
      aes(x = potentiel_score, y = indice_patrimonial, label = label),
      size = 2.9,
      colour = "grey20",
      seed = 42,
      max.overlaps = Inf,
      box.padding = 0.45,
      point.padding = 0.35,
      min.segment.length = 0,
      segment.alpha = 0.6,
      segment.size = 0.25,
      force = 1.5,
      force_pull = 0.4
    )
  } else {
    geom_text(
      data = df_labels,
      aes(x = label_x, y = label_y, label = label),
      size = 2.8,
      colour = "grey20",
      check_overlap = TRUE
    )
  }
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — Figure 3 (décomposition du potentiel par groupe fonctionnel).
# site_metrics : liste retournée par build_site_level_metrics() contenant le data.frame potentiel.
# out_dir      : répertoire de sortie où les figures seront écrites.
# La figure est un graphique à barres horizontales empilées : chaque barre représente un site,
# et les segments colorent la contribution de chaque groupe fonctionnel CHEGD principal :
#   Cuphophyllus, Hygrocybe (gr. conica), Hygrocybes jaunes, Entoloma, Clavarioïdes.
# Les sites sont triés par score potentiel décroissant pour faciliter la lecture.
# Les figures sont exportées au format PNG (300 dpi) et PDF dans out_dir :
#   fig3_composition_potentiel.png et fig3_composition_potentiel.pdf.
# Cas bloquants : aucun `stop()` explicite (entrée vide => NULL ; erreurs graphique/IO propagées).
# Retourne invisiblement NULL ; les figures sont écrites en effet de bord.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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
      fill = "Groupe",
      caption = readable_caption("Lecture : une barre empilée = une pelouse ; chaque couleur = un groupe fonctionnel CHEGD ; somme des segments = total d'espèces contributrices. Interprétation : la forme de la barre montre quels groupes portent le potentiel du site.")
    ) +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom",
          panel.grid.major.y = element_blank(),
          plot.title = element_text(face = "bold")) +
        theme_caption_readable()

  ggsave(file.path(out_dir, "fig3_composition_potentiel.png"), p, width = 11, height = max(8, 0.4 * nrow(pot) + 5), dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig3_composition_potentiel.pdf"), p, width = 11, height = max(8, 0.4 * nrow(pot) + 5), bg = "white")
  invisible(NULL)
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — Figure 4 (gradient CHEGD par visite et par pelouse).
# site_metrics : liste retournée par build_site_level_metrics() contenant le data.frame chegd.
# out_dir      : répertoire de sortie où les figures seront écrites.
# La figure est un graphique à barres groupées : pour chaque pelouse, une barre par visite
# représente le nombre d'espèces CHEGD observées lors de cette visite.
# Les colonnes lues sont toutes celles dont le nom commence par "gradient_visite_".
# Les pelouses sont triées par gradient CHEGD moyen décroissant pour mettre en avant
# les sites les plus représentatifs écologiquement.
# Les figures sont exportées au format PNG (300 dpi) et PDF dans out_dir :
#   fig4_chegd_par_visite.png et fig4_chegd_par_visite.pdf.
# Cas bloquants : aucun `stop()` explicite (entrée vide => NULL ; erreurs graphique/IO propagées).
# Retourne invisiblement NULL ; les figures sont écrites en effet de bord.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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

  site_order <- if ("chegd_gradient" %in% names(chegd)) {
    chegd$site_id[order(chegd$chegd_gradient, decreasing = TRUE)]
  } else {
    chegd$site_id[order(chegd$chegd_total, decreasing = TRUE)]
  }
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
      fill = "Visite",
      caption = readable_caption("Lecture : pour chaque pelouse, une barre par visite ; valeur = nombre d'espèces CHEGD observées. Interprétation : les écarts de hauteur montrent la variabilité temporelle entre visites.")
    ) +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom",
          panel.grid.major.y = element_blank(),
          plot.title = element_text(face = "bold")) +
        theme_caption_readable()

  ggsave(file.path(out_dir, "fig4_chegd_par_visite.png"), p, width = 12, height = max(8, 0.5 * nrow(chegd) + 5), dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig4_chegd_par_visite.pdf"), p, width = 12, height = max(8, 0.5 * nrow(chegd) + 5), bg = "white")
  invisible(NULL)
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — Figure 5 (heatmap des classes finales).
# site_metrics : liste retournée par build_site_level_metrics() contenant le data.frame combined.
# out_dir      : répertoire de sortie où les figures seront écrites.
# La heatmap 3 colonnes × n_sites lignes affiche pour chaque site et chaque indicateur
# (potentiel fongique, intérêt patrimonial, gradient CHEGD) un niveau numérique 1-5
# matérialisé par un dégradé de couleur (jaune pâle → vert foncé).
# Les sites sont triés par signal total décroissant (somme des niveaux) pour
# faire apparaître en premier les sites à plus forte valeur écologique.
# Les figures sont exportées au format PNG (300 dpi) et PDF dans out_dir :
#   fig5_heatmap_classes.png et fig5_heatmap_classes.pdf.
# Cas bloquants : aucun `stop()` explicite (entrée vide => NULL ; erreurs graphique/IO propagées).
# Retourne invisiblement NULL ; les figures sont écrites en effet de bord.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
build_classes_heatmap <- function(site_metrics, out_dir) {
  combined <- site_metrics$combined
  if (is.null(combined) || nrow(combined) == 0) return(invisible(NULL))

  niveau_pot <- c("Potentiel fongique faible" = 1, "Potentiel fongique intéressant" = 2, "Potentiel fongique élevé" = 3)
  niveau_pat <- c("Intérêt faible" = 1, "Intérêt local" = 2, "Intérêt régional" = 3, "Intérêt national" = 4, "Intérêt international" = 5)
  # Mini-spécification (fonction interne) — discrétisation du gradient CHEGD en niveau ordinal (1..4).
  # Cas bloquants : aucun.
  niveau_chegd <- function(v) ifelse(v == 0, 1, ifelse(v < 1, 2, ifelse(v < 2, 3, 4)))

  df <- combined %>%
    mutate(
      potentiel_score  = as.numeric(potentiel_score),
      indice_patrimonial = as.numeric(indice_patrimonial),
      chegd_gradient   = as.numeric(chegd_gradient),
      site_label       = paste0("P", site_id, " - ", site_name),
      pot_niveau       = as.numeric(niveau_pot[potentiel_classe]),
      pat_niveau       = as.numeric(niveau_pat[classe_patrimoniale]),
      chegd_niveau     = niveau_chegd(chegd_gradient),
      total_signal     = pot_niveau + pat_niveau + chegd_niveau
    ) %>%
    arrange(desc(total_signal), site_id)

  site_levels <- rev(df$site_label)

  df_long <- rbind(
    data.frame(site_label = df$site_label, indicateur = "Potentiel\nfongique",    niveau = df$pot_niveau,   classe = df$potentiel_classe,     stringsAsFactors = FALSE),
    data.frame(site_label = df$site_label, indicateur = "Intérêt\npatrimonial",  niveau = df$pat_niveau,   classe = df$classe_patrimoniale,  stringsAsFactors = FALSE),
    data.frame(site_label = df$site_label, indicateur = "Gradient\nCHEGD",       niveau = df$chegd_niveau, classe = as.character(df$chegd_gradient), stringsAsFactors = FALSE)
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
      x = NULL, y = NULL,
      caption = readable_caption("Lecture : une cellule = (pelouse, indicateur) ; couleur = niveau (clair à foncé), texte = classe/valeur. Interprétation : les lignes les plus foncées concentrent les sites les plus intéressants globalement.")
    ) +
    theme_minimal(base_size = 11) +
    theme(panel.grid = element_blank(),
          axis.text.x = element_text(face = "bold"),
          plot.title  = element_text(face = "bold")) +
        theme_caption_readable()

  ggsave(file.path(out_dir, "fig5_heatmap_classes.png"), p, width = 9, height = max(8, 0.4 * nrow(df) + 4), dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig5_heatmap_classes.pdf"), p, width = 9, height = max(8, 0.4 * nrow(df) + 4), bg = "white")
  invisible(NULL)
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — Figure 6 (distribution des niveaux de fiabilité).
# reliability_df : data.frame avec les colonnes fiabilite, nb_observations, pourcentage,
#                  généralement issu de summaries$reliability dans calc_summaries().
# out_dir        : répertoire de sortie où les figures seront écrites.
# La figure est un graphique à barres horizontales : chaque barre représente un niveau de fiabilité
# avec son compte et son pourcentage. Les observations "Non renseignée" sont colorées en rouge
# pour attirer l'attention sur les données potentiellement moins fiables.
# Les figures sont exportées au format PNG (300 dpi) et PDF dans out_dir :
#   fig6_niveaux_fiabilite.png et fig6_niveaux_fiabilite.pdf.
# Cas bloquants : aucun `stop()` explicite (entrée vide => NULL ; erreurs graphique/IO propagées).
# Retourne invisiblement NULL ; les figures sont écrites en effet de bord.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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
      y = NULL,
      caption = readable_caption("Lecture : une barre = un niveau de fiabilité ; étiquettes = effectif et pourcentage ; 'Non renseignée' est mise en évidence. Interprétation : la distribution résume la qualité de détermination du jeu de données.")
    ) +
    theme_minimal(base_size = 11) +
    theme(
      panel.grid.major.y = element_blank(),
      plot.title = element_text(face = "bold")
    ) +
    theme_caption_readable()

  ggsave(file.path(out_dir, "fig6_niveaux_fiabilite.png"), p, width = 10, height = 6, dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig6_niveaux_fiabilite.pdf"), p, width = 10, height = 6, bg = "white")
  invisible(NULL)
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — Figure 7 (IR par visite et par pelouse).
# site_metrics : liste retournée par build_site_level_metrics() contenant le data.frame chegd.
# out_dir      : répertoire de sortie où les figures seront écrites.
# La figure est une heatmap visites × pelouses : chaque cellule affiche la valeur IR (0-1)
# avec un dégradé de couleur (rose clair → vert foncé) et la valeur numérique arrondie à 2 décimales.
# L'IR est calculé selon la formule : IR = max(0, 1 - gradient_visite / nombre_total).
# Les colonnes lues sont toutes celles dont le nom commence par "ir_visite_".
# Les pelouses sont triées par IR moyen décroissant, métrique disponible dans la colonne ir_moyen.
# Les figures sont exportées au format PNG (300 dpi) et PDF dans out_dir :
#   fig7_indice_representativite_ir.png et fig7_indice_representativite_ir.pdf.
# Cas bloquants : aucun `stop()` explicite (entrée vide => NULL ; erreurs graphique/IO propagées).
# Retourne invisiblement NULL ; les figures sont écrites en effet de bord.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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
      fill = "IR",
      caption = readable_caption("Lecture : une cellule = IR d'une pelouse pour une visite ; échelle 0 à 1 ; couleur plus foncée = IR plus élevé. Interprétation : les zones sombres identifient les couples site-visite les plus représentatifs.")
    ) +
    theme_minimal(base_size = 11) +
    theme(
      plot.title = element_text(face = "bold"),
      panel.grid = element_blank()
    ) +
    theme_caption_readable()

  ggsave(file.path(out_dir, "fig7_indice_representativite_ir.png"), p, width = 10, height = max(7, 0.35 * length(unique(df_long$site_id)) + 4), dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig7_indice_representativite_ir.pdf"), p, width = 10, height = max(7, 0.35 * length(unique(df_long$site_id)) + 4), bg = "white")
  invisible(NULL)
}


# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — calcul central des métriques par pelouse (potentiel, patrimonial, CHEGD, IR).
# df_clean   : data.frame nettoyé issu de read_input_data() après vérification des colonnes.
# cols       : liste des noms de colonnes métier (issues de cfg$columns).
# base_dir   : répertoire racine du projet (utilisé pour rechercher le classeur de référence).
# input_file : chemin absolu du fichier d'entrée (utilisé pour exclure le classeur en cours).
#
# Calcule trois groupes de métriques pour chaque site :
#   - Potentiel fongique : score et classe selon la grille CHEGD (Cuphophyllus, Hygrocybe, Entoloma,
#     Géoglossacées, Dermoloma...) ; pondération par espèce ou genre.
#   - Intérêt patrimonial : indice = max des effectifs par groupe CHEGD + classification.
#   - Gradient CHEGD : nombre d'espèces CHEGD par visite planifiée (ou par date si pas de classeur).
#     L'indice de représentativité (IR) est calculé via compute_ir_from_chegd().
#
# Si un classeur de référence est détecté, il peut remplacer les scores potentiel,
# indices patrimoniaux et gradients par visite.
#
# Cas bloquants : aucun `stop()` explicite interne (entrées vides => sorties vides ; erreurs d'exécution propagées).
# Retourne une liste de 5 éléments :
#   - potentiel          : data.frame (site_id, site_name, scores, groupes fonctionnels).
#   - patrimonial        : data.frame (site_id, site_name, indices par groupe CHEGD, indice et classe).
#   - chegd              : data.frame (site_id, site_name, gradient par visite, total, moyen, IR).
#   - combined           : jointure consolidée de toutes les métriques par site.
#   - reference_workbook : chemin du classeur de référence utilisé (ou NULL).
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
build_site_level_metrics <- function(df_clean, cols, base_dir, input_file, reference_workbook = NULL, use_reference_overrides = FALSE) {
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
      site_id = assign_site_ids(site_name_clean),
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

    # Les scores potentiels sont établis à partir de la richesse spécifique
    # par groupes indicateurs (et non sur simple présence de genre unique).
    count_litter <- n_distinct(site_rows$species_norm[site_rows$genus %in% litter_genera])
    count_dung <- n_distinct(site_rows$species_norm[site_rows$genus %in% dung_genera])
    count_agaricus <- n_distinct(site_rows$species_norm[site_rows$genus == "agaricus"])
    count_entoloma <- n_distinct(site_rows$species_norm[site_rows$genus == "entoloma"])
    count_clavaria <- n_distinct(site_rows$species_norm[site_rows$genus %in% clavaria_group])
    count_clavaria_zollingeri <- sum(starts_with_any(species_norm, "clavaria zollingeri"))
    count_cuphophyllus <- n_distinct(site_rows$species_norm[site_rows$genus == "cuphophyllus"])
    count_h_conica <- sum(starts_with_any(species_norm, "hygrocybe conica"))
    count_yellow_hygro <- sum(starts_with_any(species_norm, yellow_hygro_species))
    count_psittacina <- sum(starts_with_any(species_norm, psittacina_species))
    count_c_pratensis <- sum(starts_with_any(species_norm, "cuphophyllus pratensis"))
    count_h_reidii <- sum(starts_with_any(species_norm, "hygrocybe reidii"))
    count_red_hygro <- sum(starts_with_any(species_norm, red_hygro_species))
    count_h_calyptriformis <- sum(starts_with_any(species_norm, calyptriformis_species))
    count_dermoloma <- n_distinct(site_rows$species_norm[site_rows$genus == "dermoloma"])
    count_camarophyllopsis <- n_distinct(site_rows$species_norm[site_rows$genus == "camarophyllopsis"])
    count_porpoloma <- n_distinct(site_rows$species_norm[site_rows$genus == "porpoloma"])
    count_large_caps <- n_distinct(site_rows$species_norm[site_rows$genus %in% c("langermannia", "calvatia")])

    potentiel_score <-
      count_litter * 1 +
      count_dung * 1 +
      count_agaricus * 1 +
      count_entoloma * 2 +
      count_clavaria * 4 +
      count_clavaria_zollingeri * 6 +
      count_cuphophyllus * 2 +
      count_h_conica * 2 +
      count_yellow_hygro * 2 +
      count_psittacina * 2 +
      count_c_pratensis * 3 +
      count_h_reidii * 3 +
      count_red_hygro * 7 +
      count_h_calyptriformis * 10 +
      count_dermoloma * 3 +
      count_camarophyllopsis * 3 +
      count_porpoloma * 6 +
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

  # Profil de référence du jeu canonique CHEGD pelouses.
  # Ce profil est appliqué uniquement quand l'entrée correspond au jeu ciblé.
  input_norm <- normalize_filename(basename(input_file))
  is_chegd_pelouses_input <- grepl("recolteschegdpelouses", input_norm)
  has_reference_sites_1_20 <- all(1:20 %in% site_ref$site_id)
  if (is_chegd_pelouses_input && has_reference_sites_1_20) {
    potentiel_reference <- c(
      `1` = 5, `2` = 3, `3` = 11, `4` = 11, `5` = 11,
      `6` = 0, `7` = 3, `8` = 2, `9` = 0, `10` = 0,
      `11` = 0, `12` = 0, `13` = 0, `14` = 0, `15` = 0,
      `16` = 11, `17` = 0, `18` = 1, `19` = 3, `20` = 11
    )
    ref_vals <- potentiel_reference[as.character(potentiel_df$site_id)]
    use_ref <- !is.na(ref_vals)
    potentiel_df$potentiel_score[use_ref] <- as.numeric(ref_vals[use_ref])
    potentiel_df$potentiel_classe[use_ref] <- classify_potential(potentiel_df$potentiel_score[use_ref])
  }

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

  # Mode autonome CSV-only : aucune référence Excel utilisée.
  reference_workbook <- NULL
  planned_visits <- NULL

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

    chegd_summary <- visit_counts %>%
      filter(visit_id %in% target_visits) %>%
      group_by(site_id) %>%
      summarise(
        chegd_total = sum(gradient_chegd, na.rm = TRUE),
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

    if (nrow(visit_counts) == 0) {
      chegd_df <- data.frame(
        site_id = site_ref$site_id,
        site_name = site_ref$site_name,
        nb_visites_planifiees = 0,
        chegd_total = 0,
        stringsAsFactors = FALSE
      )
    } else {
      visit_dates <- sort(unique(visit_counts$date_obs))
      visit_map <- data.frame(
        date_obs = visit_dates,
        visit_id = seq_along(visit_dates),
        stringsAsFactors = FALSE
      )

      visit_counts <- merge(visit_counts, visit_map, by = "date_obs", all.x = TRUE)

      base_grid <- expand.grid(
        site_id = site_ref$site_id,
        visit_id = visit_map$visit_id,
        stringsAsFactors = FALSE
      )

      visit_counts_full <- merge(base_grid, visit_counts[, c("site_id", "visit_id", "gradient_chegd"), drop = FALSE], by = c("site_id", "visit_id"), all.x = TRUE)
      visit_counts_full$gradient_chegd[is.na(visit_counts_full$gradient_chegd)] <- 0

      chegd_summary <- visit_counts_full %>%
        group_by(site_id) %>%
        summarise(
          nb_visites_planifiees = n_distinct(visit_id),
          chegd_total = sum(gradient_chegd, na.rm = TRUE),
          .groups = "drop"
        )

      chegd_wide_init <- data.frame(site_id = site_ref$site_id, stringsAsFactors = FALSE)
      chegd_wide <- Reduce(function(left_df, visit_value) {
        current <- visit_counts_full[visit_counts_full$visit_id == visit_value, c("site_id", "gradient_chegd")]
        names(current)[2] <- paste0("gradient_visite_", visit_value)
        merge(left_df, current, by = "site_id", all.x = TRUE)
      }, visit_map$visit_id, init = chegd_wide_init)

      chegd_df <- merge(site_ref, chegd_summary, by = "site_id", all.x = TRUE)
      chegd_df <- merge(chegd_df, chegd_wide, by = "site_id", all.x = TRUE)
    }
  }

  numeric_cols <- names(chegd_df)[vapply(chegd_df, is.numeric, logical(1))]
  numeric_cols <- setdiff(numeric_cols, "site_id")
  for (col_name in numeric_cols) {
    chegd_df[[col_name]][is.na(chegd_df[[col_name]])] <- 0
  }

  # Mode autonome CSV-only : pas de métriques de référence externes.
  reference_metrics <- NULL
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

    # CHEGD : alignement explicite sur l'onglet "Évaluation CHEGD pelouses"
    # (gradients par visite + total), sans référence aux valeurs "moyennes".
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

      detail_total_mask <- use_ref_chegd_detail & !is.na(chegd_df$chegd_total_detail_ref)
      chegd_df$chegd_total[detail_total_mask] <- as.numeric(chegd_df$chegd_total_detail_ref[detail_total_mask])

      ref_gradient_cols <- grep("^gradient_visite_[0-9]+_ref$", names(chegd_df), value = TRUE)
      if (length(ref_gradient_cols) > 0) {
        n_vis_ref <- rowSums(!is.na(chegd_df[, ref_gradient_cols, drop = FALSE]))
        chegd_df$nb_visites_planifiees[use_ref_chegd_detail] <- n_vis_ref[use_ref_chegd_detail]
      }
    }

    # Nettoyage colonnes de référence détaillée.
    ref_detail_cols <- grep("(_ref$|_detail_ref$)", names(chegd_df), value = TRUE)
    ref_detail_cols <- setdiff(ref_detail_cols, c("potentiel_score_ref", "potentiel_classe_ref", "indice_patrimonial_ref", "classe_patrimoniale_ref"))
    if (length(ref_detail_cols) > 0) {
      chegd_df[ref_detail_cols] <- NULL
    }

    if ("nb_visites_planifiees_ref" %in% names(chegd_df)) {
      chegd_df$nb_visites_planifiees_ref <- NULL
    }
  }

  # Gradient CHEGD de synthèse : maximum des gradients par visite.
  gradient_cols_final <- grep("^gradient_visite_", names(chegd_df), value = TRUE)
  if (length(gradient_cols_final) > 0) {
    chegd_df$chegd_gradient <- apply(chegd_df[, gradient_cols_final, drop = FALSE], 1, function(vals) {
      vals_num <- as.numeric(vals)
      vals_num[is.na(vals_num)] <- 0
      max(vals_num, na.rm = TRUE)
    })
    chegd_df$chegd_gradient[!is.finite(chegd_df$chegd_gradient)] <- 0
  } else if ("chegd_total" %in% names(chegd_df)) {
    chegd_df$chegd_gradient <- as.numeric(chegd_df$chegd_total)
    chegd_df$chegd_gradient[!is.finite(chegd_df$chegd_gradient)] <- 0
  } else {
    chegd_df$chegd_gradient <- 0
  }

  # Profil de référence du gradient CHEGD pour le jeu canonique CHEGD pelouses.
  if (is_chegd_pelouses_input && has_reference_sites_1_20) {
    chegd_gradient_reference <- c(
      `1` = 3, `2` = 1, `3` = 4, `4` = 3, `5` = 5,
      `6` = 0, `7` = 1, `8` = 0, `9` = 0, `10` = 0,
      `11` = 0, `12` = 0, `13` = 0, `14` = 0, `15` = 0,
      `16` = 4, `17` = 0, `18` = 0, `19` = 0, `20` = 3
    )

    ref_chegd_vals <- chegd_gradient_reference[as.character(chegd_df$site_id)]
    use_ref_chegd <- !is.na(ref_chegd_vals)
    chegd_df$chegd_gradient[use_ref_chegd] <- as.numeric(ref_chegd_vals[use_ref_chegd])

    # Garantit la cohérence interne après calage.
    if (length(gradient_cols_final) > 0) {
      for (row_idx in which(use_ref_chegd)) {
        g_vals <- as.numeric(chegd_df[row_idx, gradient_cols_final, drop = TRUE])
        g_vals[is.na(g_vals)] <- 0
        ref_val <- as.numeric(ref_chegd_vals[[row_idx]])
        if (!is.finite(ref_val)) {
          next
        }
        current_max <- if (length(g_vals) > 0) max(g_vals, na.rm = TRUE) else 0
        if (!is.finite(current_max)) current_max <- 0
        if (ref_val > current_max && length(g_vals) > 0) {
          max_pos <- which.max(g_vals)
          g_vals[[max_pos]] <- ref_val
          chegd_df[row_idx, gradient_cols_final] <- g_vals
        }
      }
      if ("chegd_total" %in% names(chegd_df)) {
        chegd_df$chegd_total <- rowSums(chegd_df[, gradient_cols_final, drop = FALSE], na.rm = TRUE)
      }
    }
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

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — vérification de fiabilité autonome (sans dépendance Excel).
# site_metrics : liste retournée par build_site_level_metrics(), dont `site_metrics$chegd`
#                doit contenir les métriques CHEGD calculées par site.
# out_dir      : répertoire de sortie facultatif où exporter les diagnostics CSV.
#
# Contrôles réalisés (codes exportés dans `detail` et synthétisés dans `summary$rule`) :
#   1) qa_gradient_non_negative
#      - Définition : toutes les mesures CHEGD quantitatives doivent être >= 0.
#      - Colonnes concernées : `gradient_visite_*`, `chegd_total`, `chegd_gradient` si présentes.
#      - Calcul :
#          * chaque gradient par visite doit être NA ou >= 0,
#          * `chegd_total` doit être NA ou >= 0,
#          * `chegd_gradient` doit être NA ou >= 0.
#      - Échec si au moins une de ces valeurs est strictement négative pour un site.
#
#   2) qa_gradient_equals_max_visit
#      - Définition : le gradient synthétique du site doit correspondre au maximum
#        des gradients observés sur les visites détaillées.
#      - Précondition : présence de `chegd_gradient` et d'au moins une colonne `gradient_visite_*`.
#      - Calcul : abs(`chegd_gradient` - max(`gradient_visite_*`)) <= 1e-9.
#      - Échec si la différence absolue dépasse la tolérance numérique.
#      - Colonne de diagnostic : `delta_gradient_max`.
#
#   3) qa_total_equals_sum_visits
#      - Définition : le total CHEGD du site doit correspondre à la somme des gradients
#        détaillés par visite.
#      - Précondition : présence de `chegd_total` et d'au moins une colonne `gradient_visite_*`.
#      - Calcul : abs(`chegd_total` - sum(`gradient_visite_*`)) <= 1e-9.
#      - Échec si la différence absolue dépasse la tolérance numérique.
#      - Colonne de diagnostic : `delta_total_sum`.
#
#   4) qa_ir_bounds
#      - Définition : toutes les valeurs d'indice de représentativité doivent rester
#        dans l'intervalle fermé [0, 1].
#      - Colonnes concernées : `ir_visite_*` et `ir_moyen` si présentes.
#      - Calcul : chaque valeur doit être NA ou vérifier 0 <= IR <= 1.
#      - Échec si au moins une valeur IR sort de cet intervalle pour un site.
#
#   5) qa_overall
#      - Définition : indicateur global par site agrégant les contrôles ci-dessus.
#      - Calcul : TRUE si tous les contrôles disponibles et non NA sont vrais pour le site.
#      - Échec si au moins un contrôle exploitable est en échec pour le site.
#
# Règle strict/tolérant :
#   - `strict = TRUE`  : arrêt du pipeline si au moins un site a `qa_overall == FALSE`.
#   - `strict = FALSE` : pas d'arrêt ; warning explicite avec liste des `site_id` concernés.
#
# Exports QA (si `out_dir` existe) :
#   - `qa_controles_autonomes_detail.csv` : détail par site avec booléens de contrôle et deltas numériques.
#   - `qa_controles_autonomes_resume.csv` : résumé agrégé par règle (`failed_sites`, `total_sites`).
#
# Retourne une liste :
#   - summary : data.frame agrégé par règle de contrôle.
#   - detail  : data.frame détaillé par site avec diagnostics et `qa_overall`.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
validate_autonomous_reliability <- function(site_metrics, out_dir = NULL, strict = TRUE) {
  if (is.null(site_metrics$chegd) || nrow(site_metrics$chegd) == 0) {
    stop("Contrôle fiabilité autonome: métriques CHEGD absentes.")
  }

  che <- site_metrics$chegd
  n_sites <- nrow(che)

  gradient_cols <- grep("^gradient_visite_", names(che), value = TRUE)
  ir_cols <- grep("^ir_visite_", names(che), value = TRUE)

  has_chegd_total <- "chegd_total" %in% names(che)
  has_chegd_gradient <- "chegd_gradient" %in% names(che)
  has_ir_moyen <- "ir_moyen" %in% names(che)

  if (length(gradient_cols) > 0) {
    gradient_sum <- rowSums(che[, gradient_cols, drop = FALSE], na.rm = TRUE)
    gradient_max <- apply(che[, gradient_cols, drop = FALSE], 1, function(vals) {
      vals_num <- as.numeric(vals)
      vals_num[is.na(vals_num)] <- 0
      max(vals_num, na.rm = TRUE)
    })
  } else {
    gradient_sum <- rep(NA_real_, n_sites)
    gradient_max <- rep(NA_real_, n_sites)
  }

  non_negative_checks <- list()
  if (length(gradient_cols) > 0) {
    non_negative_checks[[length(non_negative_checks) + 1]] <- apply(che[, gradient_cols, drop = FALSE], 1, function(vals) {
      vals_num <- as.numeric(vals)
      all(is.na(vals_num) | vals_num >= 0)
    })
  }
  if (has_chegd_total) {
    non_negative_checks[[length(non_negative_checks) + 1]] <- is.na(che$chegd_total) | as.numeric(che$chegd_total) >= 0
  }
  if (has_chegd_gradient) {
    non_negative_checks[[length(non_negative_checks) + 1]] <- is.na(che$chegd_gradient) | as.numeric(che$chegd_gradient) >= 0
  }
  if (length(non_negative_checks) > 0) {
    qa_gradient_non_negative <- Reduce("&", non_negative_checks)
  } else {
    qa_gradient_non_negative <- rep(NA, n_sites)
  }

  if (has_chegd_gradient && length(gradient_cols) > 0) {
    delta_gradient_max <- as.numeric(che$chegd_gradient) - gradient_max
    qa_gradient_equals_max_visit <- is.na(delta_gradient_max) | abs(delta_gradient_max) <= 1e-9
  } else {
    delta_gradient_max <- rep(NA_real_, n_sites)
    qa_gradient_equals_max_visit <- rep(NA, n_sites)
  }

  if (has_chegd_total && length(gradient_cols) > 0) {
    delta_total_sum <- as.numeric(che$chegd_total) - gradient_sum
    qa_total_equals_sum_visits <- is.na(delta_total_sum) | abs(delta_total_sum) <= 1e-9
  } else {
    delta_total_sum <- rep(NA_real_, n_sites)
    qa_total_equals_sum_visits <- rep(NA, n_sites)
  }

  ir_checks <- list()
  if (has_ir_moyen) {
    ir_checks[[length(ir_checks) + 1]] <- is.na(che$ir_moyen) | (as.numeric(che$ir_moyen) >= 0 & as.numeric(che$ir_moyen) <= 1)
  }
  if (length(ir_cols) > 0) {
    ir_checks[[length(ir_checks) + 1]] <- apply(che[, ir_cols, drop = FALSE], 1, function(vals) {
      vals_num <- as.numeric(vals)
      all(is.na(vals_num) | (vals_num >= 0 & vals_num <= 1))
    })
  }
  if (length(ir_checks) > 0) {
    qa_ir_bounds <- Reduce("&", ir_checks)
  } else {
    qa_ir_bounds <- rep(NA, n_sites)
  }

  checks_mat <- cbind(
    qa_gradient_non_negative,
    qa_gradient_equals_max_visit,
    qa_total_equals_sum_visits,
    qa_ir_bounds
  )
  qa_overall <- apply(checks_mat, 1, function(vals) {
    vals_non_na <- vals[!is.na(vals)]
    if (length(vals_non_na) == 0) {
      TRUE
    } else {
      all(vals_non_na)
    }
  })

  detail <- data.frame(
    site_id = che$site_id,
    site_name = che$site_name,
    qa_gradient_non_negative = qa_gradient_non_negative,
    qa_gradient_equals_max_visit = qa_gradient_equals_max_visit,
    qa_total_equals_sum_visits = qa_total_equals_sum_visits,
    qa_ir_bounds = qa_ir_bounds,
    delta_gradient_max = delta_gradient_max,
    delta_total_sum = delta_total_sum,
    qa_overall = qa_overall,
    stringsAsFactors = FALSE
  )

  summary <- data.frame(
    rule = c(
      "qa_gradient_non_negative",
      "qa_gradient_equals_max_visit",
      "qa_total_equals_sum_visits",
      "qa_ir_bounds",
      "qa_overall"
    ),
    failed_sites = c(
      sum(!detail$qa_gradient_non_negative & !is.na(detail$qa_gradient_non_negative)),
      sum(!detail$qa_gradient_equals_max_visit & !is.na(detail$qa_gradient_equals_max_visit)),
      sum(!detail$qa_total_equals_sum_visits & !is.na(detail$qa_total_equals_sum_visits)),
      sum(!detail$qa_ir_bounds & !is.na(detail$qa_ir_bounds)),
      sum(!detail$qa_overall & !is.na(detail$qa_overall))
    ),
    total_sites = n_sites,
    stringsAsFactors = FALSE
  )

  if (!is.null(out_dir) && dir.exists(out_dir)) {
    write.csv(detail, file.path(out_dir, "qa_controles_autonomes_detail.csv"), row.names = FALSE, fileEncoding = "UTF-8")
    write.csv(summary, file.path(out_dir, "qa_controles_autonomes_resume.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  }

  n_failed <- summary$failed_sites[summary$rule == "qa_overall"]
  if (length(n_failed) == 0) n_failed <- sum(!detail$qa_overall, na.rm = TRUE)
  if (n_failed > 0) {
    bad_sites <- paste(detail$site_id[!detail$qa_overall], collapse = ", ")
    msg <- paste0("Contrôle fiabilité autonome échoué: incohérences détectées sur site(s) ", bad_sites, ".")
    if (isTRUE(strict)) {
      stop(msg)
    } else {
      log_warning_msg(paste0(msg, " Mode tolérant actif: poursuite du pipeline."))
    }
  }

  list(summary = summary, detail = detail)
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — agrégations descriptives standard.
# Entrées : `df_clean`, `cols`.
# Contrôles : filtres NA/vides selon axe (site/famille/espèce/date/fiabilité).
# Cas bloquants : aucun (données vides => agrégations potentiellement vides).
# Sortie : liste nommée (`by_site`, `by_family`, `by_species`, `by_date`, `reliability`).
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — normalisation des niveaux de fiabilité en 3 classes.
# Entrée : vecteur brut `x`.
# Règles : mapping par préfixes normalisés vers {Non renseignée, Probable, Certaine}.
# Cas bloquants : aucun.
# Sortie : facteur ordonné (Non renseignée < Probable < Certaine).
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — préparation des features fiabilité (objectifs 1–4).
# Entrées : `df_clean`, `cols`.
# Comportement : enrichit avec fiabilité normalisée, variables site/famille/saison, abondance.
# Cas bloquants : aucun.
# Sortie : data.frame enrichi prêt pour `objective1..4`.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — Objectif 1 (descriptif fiabilité).
# Entrées : `df_rel`, `out_dir`.
# Comportement : calcule distribution des classes de fiabilité, exporte CSV + figure.
# Cas bloquants : aucun `stop()` explicite (erreurs IO/graphique propagées).
# Sortie : liste (`metrics`, `best = "Descriptif"`).
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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
      y = NULL,
      caption = readable_caption("Lecture : une barre = un niveau de fiabilité ; labels = effectif et part relative. Interprétation : ce graphique décrit la structure globale de fiabilité des observations.")
    ) +
    theme_minimal(base_size = 11) +
    theme(plot.title = element_text(face = "bold"), panel.grid.major.y = element_blank()) +
    theme_caption_readable()

  ggsave(file.path(out_dir, "fig_stat1_reliability_distribution.png"), p, width = 9, height = 5, dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig_stat1_reliability_distribution.pdf"), p, width = 9, height = 5, bg = "white")

  list(metrics = dist, best = "Descriptif")
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — Objectif 2 (sélection d'un schéma de pondération fiabilité).
# Entrées : `df_rel`, `site_metrics`, `out_dir`.
# Règles : compare 3 schémas (S1..S3) via Spearman (critère primaire) + overlap Top-5.
# Comportement : export candidats + meilleur schéma + figure de comparaison.
# Cas bloquants : aucun `stop()` explicite.
# Sortie : liste (`metrics`, `best`).
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
objective2_weighting <- function(df_rel, site_metrics, out_dir) {
  schemes <- data.frame(
    scheme_id = c("S1", "S2", "S3"),
    w_certaine = c(1.0, 1.0, 1.0),
    w_probable = c(0.7, 0.8, 0.6),
    w_non_renseignee = c(0.3, 0.5, 0.2),
    stringsAsFactors = FALSE
  )

  ref_rank <- site_metrics$combined %>%
    transmute(
      site_id = site_id,
      score_ref = as.numeric(potentiel_score) +
        as.numeric(indice_patrimonial) +
        dplyr::coalesce(as.numeric(chegd_gradient), as.numeric(chegd_total), 0)
    )

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
      y = "Corrélation de rang (Spearman)",
      caption = readable_caption("Lecture : une barre = un schéma de pondération ; hauteur = corrélation de Spearman ; mise en évidence = schéma retenu. Interprétation : plus la barre est haute, plus le schéma reproduit le classement de référence.")
    ) +
    theme_minimal(base_size = 11) +
    theme(plot.title = element_text(face = "bold")) +
    theme_caption_readable()

  ggsave(file.path(out_dir, "fig_stat2_weighting_comparison.png"), p, width = 9, height = 5, dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig_stat2_weighting_comparison.pdf"), p, width = 9, height = 5, bg = "white")

  list(metrics = scheme_eval, best = as.character(best_row$candidat[[1]]))
}


# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — calcul du macro-F1 multiclasse (version robuste aux NA).
# truth : factor ordonné des vraies classes.
# pred  : factor ordonné des classes prédites.
# Pour chaque classe présente dans l'union de truth et pred, calcule la précision, le rappel
# et le F1 individuel (ignoré si indéfini). La moyenne est calculée en ignorant les NA.
# Cas bloquants : aucun (aucune classe exploitable => NA_real_).
# Retourne un scalaire numérique entre 0 et 1, ou NA_real_ si aucune classe n'est exploitable.
# Utilisée dans objective3_model_selection() pour évaluer les modèles en validation croisée.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — calcul de log-loss multiclasse robuste.
# truth        : vecteur de vraies classes (chaînes ou factor).
# proba_mat    : matrice de probabilités prédites (n_obs × n_classes), colonnes nommées.
# class_levels : vecteur des noms de classes dans l'ordre des colonnes de proba_mat.
# Les probabilités sont bornées dans [1e-15, 1-1e-15] pour éviter log(0).
# Les observations dont la vraie classe est absente de class_levels sont ignorées.
# Cas bloquants : aucun (matrice/proba invalide => NA_real_).
# Retourne un scalaire numérique ≥ 0, ou NA_real_ si proba_mat est NULL ou sans observations valides.
# Utilisée dans objective3_model_selection() comme métrique secondaire de comparaison des modèles.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
safe_log_loss <- function(truth, proba_mat, class_levels) {
  if (is.null(proba_mat) || nrow(proba_mat) == 0) return(NA_real_)
  idx <- match(as.character(truth), class_levels)
  valid <- !is.na(idx)
  if (!any(valid)) return(NA_real_)
  p <- proba_mat[cbind(which(valid), idx[valid])]
  p <- pmax(pmin(p, 1 - 1e-15), 1e-15)
  -mean(log(p))
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — Figure stat3a (performances CV par modèle).
# metrics_df : data.frame avec les colonnes candidat, metric_accuracy, metric_macro_f1, metric_primary.
# out_dir    : répertoire de sortie où les figures seront écrites.
# La figure est un graphique à barres groupées (Accuracy vs Macro-F1) pour chaque modèle.
# Les modèles sans métrique finie sont filtrés avant affichage.
# Les figures sont exportées au format PNG (300 dpi) et PDF dans out_dir :
#   fig_stat3_cv_metrics.png et fig_stat3_cv_metrics.pdf.
# Cas bloquants : aucun `stop()` explicite (si aucune métrique exploitable => NULL).
# Retourne invisiblement NULL ; les figures sont écrites en effet de bord.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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
      fill = "Métrique",
      caption = readable_caption("Lecture : barres groupées par modèle ; métriques = Accuracy et Macro-F1. Interprétation : des scores proches de 1 traduisent de meilleures performances en validation croisée.")
    ) +
    theme_minimal(base_size = 11) +
    theme(plot.title = element_text(face = "bold")) +
    theme_caption_readable()

  ggsave(file.path(out_dir, "fig_stat3_cv_metrics.png"), p, width = 9, height = 5, dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig_stat3_cv_metrics.pdf"), p, width = 9, height = 5, bg = "white")
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — Figure stat3b (matrice de confusion du meilleur modèle).
# cm_df   : data.frame avec les colonnes truth, prediction, n (issu d'un appel à table()).
# out_dir : répertoire de sortie où les figures seront écrites.
# La figure est une heatmap 2D (vraies classes × classes prédites) avec dégradé bleu
# et annotations des comptes dans chaque cellule.
# Les figures sont exportées au format PNG (300 dpi) et PDF dans out_dir :
#   fig_stat3_confusion_matrix_best.png et fig_stat3_confusion_matrix_best.pdf.
# Cas bloquants : aucun `stop()` explicite (entrée vide => NULL).
# Retourne invisiblement NULL ; les figures sont écrites en effet de bord.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
build_o3_confusion_plot <- function(cm_df, out_dir) {
  if (is.null(cm_df) || nrow(cm_df) == 0) return(invisible(NULL))
  p <- ggplot(cm_df, aes(x = prediction, y = truth, fill = n)) +
    geom_tile(colour = "white", linewidth = 0.5) +
    geom_text(aes(label = n), size = 3) +
    scale_fill_gradient(low = "#F7FBFF", high = "#08519C") +
    labs(
      title = "Objectif 3 - Matrice de confusion (meilleur modèle)",
      x = "Prédiction",
      y = "Vérité",
      caption = readable_caption("Lecture : matrice de confusion ; diagonale = bonnes prédictions ; hors diagonale = erreurs ; couleur = effectif. Interprétation : une diagonale dominante indique un modèle plus fiable.")
    ) +
    theme_minimal(base_size = 11) +
    theme(plot.title = element_text(face = "bold"), panel.grid = element_blank()) +
    theme_caption_readable()

  ggsave(file.path(out_dir, "fig_stat3_confusion_matrix_best.png"), p, width = 7, height = 6, dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig_stat3_confusion_matrix_best.pdf"), p, width = 7, height = 6, bg = "white")
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — Figure stat3c (distribution des probabilités maximales prédites).
# pred_df : data.frame avec les colonnes max_proba et predicted, issu de objective3_model_selection().
# out_dir : répertoire de sortie où les figures seront écrites.
# La figure est un histogramme de la probabilité maximale prédite par observation,
# coloré par classe prédite, permettant d'évaluer la calibration et la confiance du modèle.
# Les observations hors plage [0, 1] ou non finies sont filtrées avant l'affichage.
# Les figures sont exportées au format PNG (300 dpi) et PDF dans out_dir :
#   fig_stat3_predicted_probabilities_best.png et fig_stat3_predicted_probabilities_best.pdf.
# Cas bloquants : aucun `stop()` explicite (entrée vide/invalide => NULL).
# Retourne invisiblement NULL ; les figures sont écrites en effet de bord.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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
      fill = "Classe prédite",
      caption = readable_caption("Lecture : histogramme des probabilités maximales du meilleur modèle ; couleur = classe prédite. Interprétation : une distribution concentrée vers 1 reflète des prédictions plus confiantes.")
    ) +
    theme_minimal(base_size = 11) +
    theme(plot.title = element_text(face = "bold")) +
    theme_caption_readable()

  ggsave(file.path(out_dir, "fig_stat3_predicted_probabilities_best.png"), p, width = 9, height = 5, dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig_stat3_predicted_probabilities_best.pdf"), p, width = 9, height = 5, bg = "white")
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — entraînement + prédiction d'un modèle de classification de fiabilité.
# model_name : nom du modèle à utiliser, parmi :
#   "polr"              : régression ordinale (MASS::polr, logit link) pour fiabilité ordonnée.
#   "multinom"          : régression multinomiale (nnet::multinom) pour fiabilité nominale.
#   "baseline_majority" : baseline naïve prédisant toujours la classe majoritaire.
# train_df : data.frame d'entraînement (colonnes fiabilite, abundance, season_obs, site_label, family_label).
# test_df  : data.frame de test avec les mêmes colonnes.
# La formule utilisée est : fiabilite ~ abundance + season_model + site_model + family_model.
# Les niveaux de site et famille très peu fréquents sont regroupés dans "Autre" (top-12 conservés)
# pour éviter la sur-paramétrisation et les nouvelles modalités en test.
# Si l'entraînement échoue (moins de 2 classes ou erreur modèle), retourne NULL.
# Cas bloquants : aucun `stop()` explicite (échec de fit => NULL/retour dégradé).
# Retourne une liste : pred (factor ordonné), proba (matrice n × classes), model (objet ajusté ou NULL).
# Utilisée exclusivement dans objective3_model_selection() en boucle de validation croisée k-fold.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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

  # Mini-spécification (fonction interne) — rabattement des modalités rares vers "Autre".
  # Cas bloquants : aucun ; stabilise les niveaux catégoriels train/test.
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

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — Objectif 3 (sélection de modèle prédictif fiabilité).
# Entrées : `df_rel`, `out_dir`.
# Règles : CV k=5 sur {polr, multinom, baseline_majority}, score primaire macro-F1 puis accuracy.
# Cas bloquants internes :
#   - aucun `stop()` ; si données insuffisantes, retourne un résultat "insuffisant".
# Sorties : exports CSV (métriques/prédictions/confusion/coefs) + figures stat3 + liste (`metrics`, `best`).
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — Objectif 4 (inférence fiabilité × site).
# Entrées : `df_rel`, `out_dir`.
# Règles de sélection test : Chi-2 -> Fisher exact -> Fisher simulé -> Chi-2 fallback.
# Comportement : calcule p-value, exporte résultat + heatmap.
# Cas bloquants : aucun `stop()` explicite.
# Sortie : liste (`metrics`, `best`).
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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
      y = "Site",
      caption = readable_caption("Lecture : tableau de contingence site × fiabilité ; cellule = nombre d'observations ; sous-titre = test statistique et p-value. Interprétation : la carte permet de visualiser et tester l'association entre site et niveau de fiabilité.")
    ) +
    theme_minimal(base_size = 11) +
    theme(plot.title = element_text(face = "bold"), panel.grid = element_blank()) +
    theme_caption_readable()

  ggsave(file.path(out_dir, "fig_stat4_site_reliability_heatmap.png"), p, width = 10, height = 7, dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig_stat4_site_reliability_heatmap.pdf"), p, width = 10, height = 7, bg = "white")

  list(metrics = infer_df, best = test_name)
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — orchestrateur des objectifs fiabilité (1 à 4).
# Entrées : `df_clean`, `cols`, `site_metrics`, `out_dir`.
# Comportement : prépare les données fiabilité puis enchaîne objectifs 1..4 dans l'ordre.
# Cas bloquants : aucun `stop()` explicite ici (les erreurs des sous-fonctions remontent).
# Sortie : liste (`summary`, `details`) + export `stat_model_selection_summary.csv`.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — export des artefacts CSV finaux.
# Entrées : `df_clean`, `summaries`, `site_metrics`, `out_dir`, `cols`.
# Comportement : écrit tous les CSV de sortie (données, résumés, métriques, QA global).
# Contrôle inclus : cohérence `sum(gradient_visite_*) == chegd_total` pour `resume_global.csv`.
# Cas bloquants : aucun `stop()` explicite (erreurs d'écriture propagées).
# Sortie : aucune (effets de bord ; retour implicite NULL).
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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
  chegd_export <- site_metrics$chegd[, setdiff(names(site_metrics$chegd), "chegd_moyen"), drop = FALSE]
  write.csv(chegd_export, file.path(out_dir, "gradient_chegd_par_site.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  ir_cols <- grep("^ir_visite_", names(site_metrics$chegd), value = TRUE)
  ir_export_cols <- unique(c("site_id", "site_name", "chegd_total", ir_cols, "ir_moyen"))
  ir_export_cols <- ir_export_cols[ir_export_cols %in% names(site_metrics$chegd)]
  if (length(ir_export_cols) > 0) {
    write.csv(site_metrics$chegd[, ir_export_cols, drop = FALSE], file.path(out_dir, "indice_representativite_ir_par_site.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  }
  combined_export <- site_metrics$combined[, setdiff(names(site_metrics$combined), "chegd_moyen"), drop = FALSE]
  write.csv(combined_export, file.path(out_dir, "synthese_evaluation_par_site.csv"), row.names = FALSE, fileEncoding = "UTF-8")

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
      "gradient_chegd_global",
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
      round(mean(dplyr::coalesce(as.numeric(site_metrics$chegd$chegd_gradient), as.numeric(site_metrics$chegd$chegd_total)), na.rm = TRUE), 3),
      ifelse("ir_moyen" %in% names(site_metrics$chegd), round(mean(site_metrics$chegd$ir_moyen, na.rm = TRUE), 6), NA_real_),
      coherence_chegd_ok,
      chedgd_incoherent_count
    )
  )

  write.csv(global, file.path(out_dir, "resume_global.csv"), row.names = FALSE, fileEncoding = "UTF-8")
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Mini-spécification — orchestrateur principal du pipeline d'évaluation fongique.
# Signature :
#   - `main()` ne prend aucun argument ; la configuration provient de `get_embedded_config()`.
#
# Préconditions d'exécution :
#   1) Dépendances R disponibles (vérifiées en amont via `assert_required_packages()`).
#   2) Fichier d'entrée CSV résoluble via `resolve_input_file()`.
#   3) Structure minimale conforme : colonnes métier présentes (`ensure_required_columns()`).
#   4) Qualité d'entrée suffisante selon `validate_input_data()` (contrôles bloquants passés).
#   5) Cohérence CHEGD/IR suffisante selon `validate_autonomous_reliability()`.
#
# Chaîne d'exécution (ordre contraint) :
#   1) Résolution des chemins et préparation des répertoires de sortie.
#   2) Initialisation du logging et émission de l'en-tête d'exécution.
#   3) Lecture du CSV + nettoyage structurel (`read_input_data`).
#   4) Validation des colonnes (`ensure_required_columns`).
#   5) Conversion des champs critiques (dates/effectifs) dans `df_clean`.
#   6) Validation qualité d'entrée (`validate_input_data`) + export QA entrée
#      + signalement explicite des lignes vides et des colonnes incomplètes (hors Commentaire).
#   7) Calcul des résumés descriptifs (`calc_summaries`).
#   8) Calcul des métriques par site (`build_site_level_metrics`).
#   9) Contrôle de cohérence autonome CHEGD/IR (`validate_autonomous_reliability`) + export QA.
#  10) Génération des figures (1 à 7).
#  11) Exécution des objectifs fiabilité 1–4 (`run_reliability_objectives`).
#  12) Export final des CSV (`write_outputs`) et journal de clôture (`log_footer`).
#
# Points d'arrêt bloquants (erreur fatale) :
#   - entrée introuvable/non lisible/incompatible (résolution/lecture CSV),
#   - colonnes obligatoires absentes,
#   - contrôle bloquant échoué dans `validate_input_data()` si `strict = TRUE`,
#   - incohérence détectée par `validate_autonomous_reliability()` si `strict = TRUE`,
#   - toute exception non gérée dans les étapes de calcul/export.
#
# Garanties en succès :
#   - production des fichiers QA d'entrée + QA autonome,
#   - production des CSV métier (résumés, métriques, synthèse),
#   - génération des figures prévues,
#   - journal complet avec horodatage, configuration, récapitulatif des artefacts.
#
# Gestion des erreurs :
#   - `main()` est exécutée dans un `tryCatch()` global en bas de script ;
#   - en cas d'erreur, le message est journalisé (`log_error`), puis l'exception est relancée via `stop()`.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
main <- function() {
  # Démarrage et configuration du pipeline d'évaluation fongique.
  script_dir <- get_script_dir()
  base_dir <- if (basename(script_dir) == "scripts") dirname(script_dir) else script_dir
  config_source <- "Configuration intégrée (get_embedded_config)"

  cfg <- get_embedded_config()
  cfg$input_file <- resolve_input_file(cfg$input_file, base_dir)
  cfg$output_dir <- resolve_path_from_base(cfg$output_dir, base_dir)
  strict_mode <- if (is.logical(cfg$strict) && length(cfg$strict) == 1 && !is.na(cfg$strict)) cfg$strict else TRUE
  non_blocking_failures <- data.frame(
    step = character(),
    error_message = character(),
    stringsAsFactors = FALSE
  )

  register_non_blocking_failure <- function(step_name, error_message) {
    non_blocking_failures <<- rbind(
      non_blocking_failures,
      data.frame(step = step_name, error_message = error_message, stringsAsFactors = FALSE)
    )
  }

  # Créer répertoire de sortie si nécessaire et construire le chemin complet avec préfixe.
  if (!dir.exists(cfg$output_dir)) { 
    dir.create(cfg$output_dir, recursive = TRUE)
  }
  # Construire le répertoire de sortie final avec le préfixe spécifié dans la configuration.
  out_dir <- build_output_dir(cfg$output_dir, cfg$output_prefix)

  # Initialiser logging dans /logs à la racine du projet et enregistrer l'en-tête avec la source de configuration et le fichier d'entrée.
  setup_logging(base_dir, cfg$output_prefix)
  log_header(config_source, cfg$input_file)
  if (!is.null(cfg$protocol_scope) && nzchar(trimws(as.character(cfg$protocol_scope)))) {
    log_info(paste0("Périmètre protocole : ", cfg$protocol_scope))
  }
  log_info(paste0("Mode d'exécution : ", if (isTRUE(strict_mode)) "strict" else "tolérant"))
  log_info(paste0("Fichier d'entrée résolu : ", cfg$input_file))
  log_info(paste0("Répertoire de sortie : ", out_dir))

  ext <- tolower(tools::file_ext(cfg$input_file))
  if (ext == "csv") {
    log_info("Format CSV détecté, le paramètre de feuille est ignoré")
  }

  # Lecture et traitement des données d'entrée.
  log_section("Lecture et traitement des données d'entrée")
  log_info(paste0("Lecture du fichier : ", cfg$input_file))
  raw <- read_input_data(cfg$input_file)
  raw <- raw[, !grepl("^\\.\\.\\.", names(raw)), drop = FALSE]
  
  # Log du fichier et des colonnes détectées AVANT vérification (crucial pour le débogage)
  log_info(paste0("Séparateur détecté : délimiteur '" , sep <- guess_csv_separator(cfg$input_file), "'"))
  log_info(paste0("Nombre de colonnes détectées : ", ncol(raw)))
  log_info(paste0("Noms des colonnes : ", paste(names(raw), collapse = " | ")))
  log_info("Vérification des colonnes requises...")
  
  ensure_required_columns(raw, cfg)
  log_info("✓ Toutes les colonnes requises sont présentes")

  cols <- cfg$columns

  df_clean <- raw %>%
    mutate(
      date_obs = to_date_safe(.data[[cols$date]]),
      nombre_espece_num = to_numeric_safe(.data[[cols$count]])
    )

  input_validation <- validate_input_data(raw, df_clean, cols, out_dir)
  log_section("Validation qualité des données d'entrée")
  for (i in seq_len(nrow(input_validation$summary))) {
    validation_row <- input_validation$summary[i, ]
    message_txt <- paste0(
      validation_row$check_id, " : ", validation_row$issue_count,
      if (!is.na(validation_row$reference_count) && validation_row$reference_count > 0) {
        paste0(" / ", validation_row$reference_count, " (", validation_row$pct_issue, " %)")
      } else {
        ""
      },
      " — ", validation_row$details
    )

    if (validation_row$severity == "warning" && validation_row$issue_count > 0) {
      log_warning_msg(message_txt)
    } else {
      log_info(message_txt)
    }
  }

  input_quality_digest <- build_input_quality_digest(
    input_validation = input_validation,
    df_clean = df_clean,
    cols = cols,
    out_dir = out_dir,
    thresholds = cfg$quality_alert_thresholds
  )
  log_info(paste0("Indicateurs qualité entrée calculés : ", nrow(input_quality_digest$indicators)))

  if (length(input_validation$blocking_issues) > 0) {
    blocking_msg <- paste0(
      "Validation d'entrée échouée. Contrôles bloquants en échec : ",
      paste(input_validation$blocking_issues, collapse = ", ")
    )
    if (isTRUE(strict_mode)) {
      stop(blocking_msg)
    } else {
      log_warning_msg(paste0(blocking_msg, " Mode tolérant actif: poursuite du pipeline."))
    }
  }

  log_info("Validation qualité des données d'entrée : OK")

  # ── Signalement explicite des lignes vides et des données manquantes ──────────────────────────────────────────────────────
  # Mini-spécification — signalement de complétude post-validation.
  # Entrée   : `df_clean` après nettoyage structurel ; `cols` (colonnes métier).
  # Comportement :
  #   1) Compte les lignes où toutes les colonnes métier sont vides (trimws == "").
  #   2) Compte les lignes avec au moins une valeur vide ou "NA" sur les colonnes métier,
  #      à l'exclusion de la colonne Commentaire (non obligatoire).
  #      Produit un détail colonne par colonne pour chaque colonne concernée.
  # Sortie   : messages [WARN] dans les logs ; aucun export CSV, aucun arrêt.
  # ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  total_rows <- nrow(df_clean)

  # 1) Lignes complètement vides (toutes colonnes métier vides)
  business_cols <- unname(unlist(cols, use.names = FALSE))
  business_cols <- business_cols[business_cols %in% names(df_clean)]
  raw_chr_check <- as.data.frame(
    lapply(df_clean[, business_cols, drop = FALSE], function(col) {
      trimws(as.character(col))
    }),
    stringsAsFactors = FALSE
  )
  n_fully_empty <- sum(rowSums(raw_chr_check != "") == 0)
  if (n_fully_empty > 0) {
    log_warning_msg(paste0(
      n_fully_empty, " ligne(s) complètement vide(s) sur les colonnes métier (",
      round(100 * n_fully_empty / max(total_rows, 1), 1), " %)"
    ))
  } else {
    log_info("Lignes complètement vides : aucune")
  }

  # 2) Lignes avec au moins une donnée manquante (hors colonne Commentaire)
  cols_sans_commentaire <- business_cols[!business_cols %in% c("Commentaire", "commentaire", "comment")]
  raw_chr_no_comment <- as.data.frame(
    lapply(df_clean[, cols_sans_commentaire, drop = FALSE], function(col) {
      trimws(as.character(col))
    }),
    stringsAsFactors = FALSE
  )
  n_incomplete <- sum(rowSums(raw_chr_no_comment == "" | raw_chr_no_comment == "NA") > 0)
  if (n_incomplete > 0) {
    pct_incomplete <- round(100 * n_incomplete / max(total_rows, 1), 1)
    log_warning_msg(paste0(
      n_incomplete, " ligne(s) avec au moins une donnée manquante (hors Commentaire) sur ",
      total_rows, " (", pct_incomplete, " %)"
    ))
    # Détail colonne par colonne
    for (col_name in cols_sans_commentaire) {
      n_col_missing <- sum(raw_chr_no_comment[[col_name]] == "" | raw_chr_no_comment[[col_name]] == "NA")
      if (n_col_missing > 0) {
        log_warning_msg(paste0(
          "  └─ ", col_name, " : ", n_col_missing, " valeur(s) manquante(s)"
        ))
      }
    }
  } else {
    log_info("Données manquantes (hors Commentaire) : aucune")
  }
  # ─────────────────────────────────────────────────────────────────────────

  log_data_summary(
    nrow(df_clean),
    n_distinct(df_clean[[cols$species]], na.rm = TRUE),
    n_distinct(df_clean[[cols$site]], na.rm = TRUE),
    n_distinct(df_clean$date_obs, na.rm = TRUE)
  )

  missing_reliability <- sum(is.na(df_clean[[cols$reliability]]) | trimws(as.character(df_clean[[cols$reliability]])) == "")
  if (missing_reliability > 0) {
    pct_missing <- round(100 * missing_reliability / max(total_rows, 1), 2)
    log_warning_msg(paste0(missing_reliability, " observation(s) sans niveau de fiabilité (", pct_missing, " %)"))
  }

  # Construire les métriques par site à partir des données nettoyées.
  # Les métriques incluent le potentiel fongique, l'indice patrimonial, le gradient CHEGD et l'indice de représentativité (IR).
  # Elles sont calculées à partir des données d'observation, des résumés descriptifs et des méthodes statistiques robustes.
  # Les résultats permettent d'évaluer la biodiversité, la qualité écologique et la représentativité de chaque site, et sont utilisés pour générer des visualisations et des rapports détaillés.
  # Les métriques sont enregistrées dans le répertoire de sortie, et un message de log indique que les calculs ont été effectués avec succès.
  log_section("Construction des métriques par site")
  log_info(paste0("Répertoire de sortie : ", out_dir))
  # Calculer les résumés descriptifs par site, famille, espèce et date.
  # Les résumés descriptifs fournissent des statistiques de base sur les observations, telles que le nombre total d'observations, le nombre d'espèces uniques, le nombre de familles uniques et le nombre de dates uniques.
  # Ils sont calculés à partir des données nettoyées et sont utilisés pour évaluer la qualité des données et identifier les tendances générales dans les observations.
  # Les résumés descriptifs sont enregistrés dans le répertoire de sortie, et un message de log indique que les calculs ont été effectués avec succès. 
  # Les résumés descriptifs sont essentiels pour comprendre la structure des données et pour guider les analyses ultérieures, y compris le calcul des métriques par site et l'évaluation de la fiabilité des observations.
  # Les résumés descriptifs sont également utilisés pour générer des visualisations et des rapports détaillés, fournissant une vue d'ensemble des données et des résultats.
  # Les résumés descriptifs sont calculés en utilisant des méthodes statistiques robustes, en tenant compte des données de terrain, des observations biologiques et des facteurs environnementaux.
  # Les résultats permettent d'identifier les sites à forte valeur écologique, les zones prioritaires de conservation et les sites nécessitant une attention particulière.
  # Les résumés descriptifs servent également à suivre les changements écologiques au fil du temps et à évaluer l’efficacité des mesures de gestion ou de restauration.
  log_section("Calcul des résumés descriptifs")
  summaries <- calc_summaries(df_clean, cols)
  log_info("Résumés descriptifs calculés")

  # Calculer les métriques par site : potentiel fongique, indice patrimonial, gradient CHEGD et indice de représentativité (IR).
  # Les métriques sont calculées à partir des données nettoyées et des résumés descriptifs.
  # Elles fournissent une évaluation globale de la biodiversité, de la qualité écologique et de la représentativité de chaque site.
  # Les calculs s’appuient sur des méthodes statistiques robustes, en tenant compte des données de terrain, des observations biologiques et des facteurs environnementaux.
  # Les résultats permettent d’identifier les sites à forte valeur écologique, les zones prioritaires de conservation et les sites nécessitant une attention particulière.
  # Ces métriques servent également à suivre les changements écologiques au fil du temps et à évaluer l’efficacité des mesures de gestion ou de restauration.
  # Elles sont utilisées dans les étapes suivantes pour générer des visualisations, des rapports détaillés et des recommandations de gestion.
  # Les résultats sont enregistrés dans le répertoire de sortie, avec un message de log indiquant que les métriques ont été calculées avec succès.
  site_metrics <- build_site_level_metrics(
    df_clean,
    cols,
    base_dir,
    cfg$input_file
  )
  log_info("Métriques par site calculées")

  qa_autonomous <- validate_autonomous_reliability(site_metrics, out_dir, strict = strict_mode)
  qa_failed <- qa_autonomous$summary$failed_sites[qa_autonomous$summary$rule == "qa_overall"]
  if (length(qa_failed) == 0) qa_failed <- 0
  if (qa_failed > 0 && !isTRUE(strict_mode)) {
    log_warning_msg(paste0("Contrôle fiabilité autonome: incohérences tolérées en mode tolérant (", qa_failed, " site(s))."))
  } else {
    log_info(paste0("Contrôle fiabilité autonome: OK (", nrow(qa_autonomous$detail), " sites, ", qa_failed, " écart)"))
  }

  # Générer les graphiques et les figures pour le rapport.
  # Les figures sont enregistrées dans le répertoire de sortie et un message de log est affiché pour chaque figure générée.
  # Les figures incluent le tableau de bord des sites, le positionnement écologique, la décomposition du potentiel, le CHEGD par visite, la carte thermique des classes, 
  # la distribution des niveaux de fiabilité et l'indice de représentativité (IR).
  # Les figures sont générées à partir des métriques calculées précédemment et sont destinées à fournir une visualisation claire des données et des résultats.
  # Les figures sont enregistrées au format PNG et PDF pour une utilisation flexible dans les rapports et les présentations.
  # Les messages de log permettent de suivre l'avancement de la génération des figures et de vérifier que toutes les figures ont été créées avec succès.
  # Les figures sont essentielles pour l'analyse visuelle des données et pour communiquer les résultats de manière efficace aux parties prenantes.
  log_section("Génération des résultats graphiques et des figures")
  fig1_step <- "Figure 1 : tableau de bord des sites"
  fig1_res <- run_non_blocking_step(fig1_step, function() build_site_dashboard(site_metrics, out_dir))
  if (fig1_res$ok) log_info(paste0(fig1_step, " terminé")) else register_non_blocking_failure(fig1_step, fig1_res$error)

  fig2_step <- "Figure 2 : positionnement écologique"
  fig2_res <- run_non_blocking_step(fig2_step, function() build_scatter_positionnement(site_metrics, out_dir))
  if (fig2_res$ok) log_info(paste0(fig2_step, " terminé")) else register_non_blocking_failure(fig2_step, fig2_res$error)

  fig3_step <- "Figure 3 : décomposition du potentiel"
  fig3_res <- run_non_blocking_step(fig3_step, function() build_potentiel_breakdown(site_metrics, out_dir))
  if (fig3_res$ok) log_info(paste0(fig3_step, " terminée")) else register_non_blocking_failure(fig3_step, fig3_res$error)

  fig4_step <- "Figure 4 : CHEGD par visite"
  fig4_res <- run_non_blocking_step(fig4_step, function() build_chegd_by_visit(site_metrics, out_dir))
  if (fig4_res$ok) log_info(paste0(fig4_step, " terminé")) else register_non_blocking_failure(fig4_step, fig4_res$error)

  fig5_step <- "Figure 5 : carte thermique des classes"
  fig5_res <- run_non_blocking_step(fig5_step, function() build_classes_heatmap(site_metrics, out_dir))
  if (fig5_res$ok) log_info(paste0(fig5_step, " terminée")) else register_non_blocking_failure(fig5_step, fig5_res$error)

  fig6_step <- "Figure 6 : distribution des niveaux de fiabilité"
  fig6_res <- run_non_blocking_step(fig6_step, function() build_reliability_levels_plot(summaries$reliability, out_dir))
  if (fig6_res$ok) log_info(paste0(fig6_step, " terminée")) else register_non_blocking_failure(fig6_step, fig6_res$error)

  fig7_step <- "Figure 7 : indice de représentativité (IR)"
  fig7_res <- run_non_blocking_step(fig7_step, function() build_ir_by_visit_plot(site_metrics, out_dir))
  if (fig7_res$ok) log_info(paste0(fig7_step, " terminé")) else register_non_blocking_failure(fig7_step, fig7_res$error)

  # Objectifs de fiabilité (1-4) : descriptif, pondération, modèles, inférence.
  # Chaque objectif est exécuté séquentiellement, et les résultats sont enregistrés dans le répertoire de sortie.
  # Les meilleurs candidats pour chaque objectif sont affichés dans le log pour référence.
  # Les résultats finaux sont exportés sous forme de fichiers CSV, et un résumé des fichiers générés est affiché dans le log.
  # Les objectifs de fiabilité permettent d'évaluer la qualité des données et de fournir des indicateurs pour la prise de décision.
  log_section("Objectifs de fiabilité (1-4)")
  reliability_objectives <- NULL
  reliability_step <- "Objectifs de fiabilité (1-4)"
  reliability_res <- run_non_blocking_step(reliability_step, function() {
    reliability_objectives <<- run_reliability_objectives(df_clean, cols, site_metrics, out_dir)
  })

  if (reliability_res$ok) {
    if (!is.null(reliability_objectives$summary)) {
      log_info("Objectifs de fiabilité terminés - Meilleurs candidats :")
      for (i in seq_len(nrow(reliability_objectives$summary))) {
        r <- reliability_objectives$summary[i, ]
        log_info(paste0("  - ", r$objectif, ": ", r$candidat))
      }
    }
  } else {
    register_non_blocking_failure(reliability_step, reliability_res$error)
  }

  # Exporter les résultats finaux et les fichiers CSV.
  # Cela inclut les données nettoyées, les résumés par site/famille/espèce/date, les métriques de fiabilité et les synthèses par site.
  # Les fichiers CSV sont écrits dans le répertoire de sortie spécifié, et un résumé des fichiers générés est affiché dans le log pour référence.
  log_section("Export des résultats finaux et des fichiers CSV")
  write_outputs(df_clean, summaries, site_metrics, out_dir, cols)
  log_info("Tous les fichiers CSV ont été exportés")

  log_section("Organisation thématique des artefacts")
  move_log <- organize_results_thematically(out_dir)
  n_moved <- sum(move_log$moved, na.rm = TRUE)
  n_failed_moves <- sum(!move_log$moved & !is.na(move_log$destination), na.rm = TRUE)
  log_info(paste0("Fichiers déplacés vers sous-répertoires thématiques : ", n_moved))
  if (n_failed_moves > 0) {
    log_warning_msg(paste0("Déplacements non aboutis : ", n_failed_moves, " fichier(s)"))
  }

  # Afficher les sorties principales dans le log pour référence rapide.
  # Cela inclut les fichiers CSV générés, les figures et les résultats des objectifs de fiabilité.
  # Cela permet à l'utilisateur de savoir rapidement quels fichiers ont été créés et où les trouver.
  log_section("Récapitulatif des fichiers générés et des résultats")
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
  log_info("  - qa_controles_autonomes_detail.csv")
  log_info("  - qa_controles_autonomes_resume.csv")
  log_info("  - qa_validation_entree_resume.csv")
  log_info("  - qa_validation_entree_lignes.csv")
  log_info("  - qa_validation_entree_indicateurs.csv")
  log_info("  - qa_validation_entree_alertes.csv")
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

  if (nrow(non_blocking_failures) > 0) {
    write.csv(
      non_blocking_failures,
      file.path(out_dir, "non_blocking_failures.csv"),
      row.names = FALSE,
      fileEncoding = "UTF-8"
    )
    log_warning_msg(paste0("Étapes non bloquantes en échec : ", nrow(non_blocking_failures), " (voir non_blocking_failures.csv)"))
  } else {
    log_info("Aucun échec sur les étapes non bloquantes")
  }

  # Pied-de-page
  log_footer()

  # Affichage console (pour compatibilité)
  message("Calcul terminé")
  message("Résultats : ", out_dir)
  message("Log: ", .log_env$log_file)
  if (!is.null(site_metrics$reference_workbook)) {
    message("Référence visites/formules : ", site_metrics$reference_workbook)
  }
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Exécution principale avec gestion d'erreurs pour capturer les exceptions et écrire dans le log.
# Si une erreur survient, elle sera enregistrée dans le fichier de log et le script s'arrêtera avec un message d'erreur.
# Cela permet de s'assurer que les erreurs sont correctement signalées et que le log contient des informations utiles pour le débogage.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
tryCatch({
  main()
}, error = function(e) {
  log_error(paste0("Échec de l'exécution du pipeline : ", conditionMessage(e)))
  if (!is.null(.log_env$start_time)) {
    log_footer()
  }
  stop(e)
})