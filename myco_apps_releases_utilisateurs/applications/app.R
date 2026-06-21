##
# ==================================================================================================================================
# Script : app.R
# Objet  : Interface Shiny locale pour lancer les pipelines myco_apps_releases
#          (ICR et CHEGD), valider les fichiers d'entrée et consulter les résultats.
#
# Fonctionnalités principales :
#   1) Sélection de l'application à exécuter (ICR ou CHEGD)
#   2) Utilisation d'un fichier d'exemple ou import d'un fichier utilisateur
#   3) Validation des colonnes d'entrée attendues
#   4) Exécution du pipeline via Rscript avec journalisation
#   5) Visualisation des sorties et téléchargement du dernier log
# ==================================================================================================================================
#
# Usage : Exécuter via run_app.R (recommandé)
#         ou directement avec shiny::runApp(appDir = ".") depuis ce dossier
#
# Dépendances : shiny, DT, readr, readxl, stringr, later
# Auteur : Eddy Boite
# Date : 2026-06-21
# Version : 1.0
# ==================================================================================================================================

# Configuration des options R
options(
  repos = c(CRAN = "https://cloud.r-project.org"),
  shiny.launch.browser = TRUE
)
library(shiny)
library(DT)
# ==================================================================================================================================
# Fonctions utilitaires
# =================================================================================================================================
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || is.na(x) || !nzchar(x)) y else x

# Catalogue des applications disponibles
script_catalogue <- list(
  ICR = list(
    label = "Inventaires fongiques — Complétude & Représentativité (ICR)",
    script = file.path("scripts", "Inventaires_completude_representativite.R"),
    default_input = file.path("data", "observations.csv"),
    output_dir = file.path("results", "ICR"),
    env_input = "INVENTAIRES_INPUT_FILE",
    env_output = "INVENTAIRES_OUTPUT_DIR",
    required_cols = c("site", "date", "visite_id", "espece")
  ),
  CHEGD = list(
    label = "Évaluation potentiel fongique / intérêt patrimonial / gradient CHEGD",
    script = file.path("scripts", "Evaluation_Potentiel_Fongique_Interets_Patrimoniaux_CHEGD.R"),
    default_input = file.path("data", "données_récoltes_chegd_pelouses.csv"),
    output_dir = file.path("results", "EPFIP_CHEGD"),
    env_input = "CHEGD_INPUT_FILE",
    env_output = "CHEGD_OUTPUT_DIR",
    required_cols = c("Espèces", "Famille", "Date", "Nombre d'espèce", "Site", "Fiabilité détermination")
  )
)

# Fonctions utilitaires pour la validation des colonnes d'entrée et l'exécution des scripts
detect_delimiter <- function(path) {
  first_line <- readLines(path, n = 1, warn = FALSE, encoding = "UTF-8")
  if (!length(first_line)) return(",")
  n_tab <- stringr::str_count(first_line, "\\t")
  n_semi <- stringr::str_count(first_line, ";")
  n_comma <- stringr::str_count(first_line, ",")
  if (n_tab >= max(n_semi, n_comma) && n_tab > 0) return("\t")
  if (n_semi > n_comma) return(";")
  if (n_comma > 0) return(",")
  ","
}

# Lecture des colonnes d'entrée
read_input_columns <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext %in% c("csv", "txt", "tsv")) {
    delim <- detect_delimiter(path)
    df0 <- readr::read_delim(
      file = path,
      delim = delim,
      n_max = 0,
      show_col_types = FALSE,
      progress = FALSE,
      locale = readr::locale(encoding = "UTF-8")
    )
    return(names(df0))
  }
  if (ext %in% c("xlsx", "xls")) {
    df0 <- readxl::read_excel(path, n_max = 0)
    return(names(df0))
  }
  character(0)
}

# Validation des colonnes d'entrée
validate_input_columns <- function(path, script_key) {
  cfg <- script_catalogue[[script_key]]
  required <- cfg$required_cols %||% character(0)
  if (!length(required)) {
    return(list(ok = TRUE, message = "Validation colonnes non configurée."))
  }
# Lecture des colonnes d'entrée
cols <- tryCatch(read_input_columns(path), error = function(e) character(0))
  if (!length(cols)) {
    return(list(ok = FALSE, message = "Impossible de lire les colonnes du fichier fourni."))
  }
# Validation des colonnes requises
missing <- setdiff(required, cols)
  if (length(missing)) {
    return(list(
      ok = FALSE,
      message = paste(
        "Colonnes manquantes :",
        paste(missing, collapse = ", "),
        "\nColonnes détectées :",
        paste(cols, collapse = ", ")
      )
    ))
  }

list(ok = TRUE, message = "Colonnes d'entrée validées.")
}

# Liste des fichiers dans un répertoire
safe_list_files <- function(path) {
  if (!dir.exists(path)) return(data.frame(Fichier = character(), Taille = character(), Modifié = character()))
  files <- list.files(path, recursive = TRUE, full.names = TRUE, all.files = FALSE)
  files <- files[file.exists(files) & !dir.exists(files)]
  if (!length(files)) return(data.frame(Fichier = character(), Taille = character(), Modifié = character()))
  info <- file.info(files)
  data.frame(
    Fichier = sub(paste0("^", normalizePath(path, winslash = "/", mustWork = FALSE), "/?"), "", normalizePath(files, winslash = "/", mustWork = FALSE)),
    Taille = format(info$size, big.mark = " ", scientific = FALSE),
    Modifié = format(info$mtime, "%Y-%m-%d %H:%M"),
    stringsAsFactors = FALSE
  )
}

# Copie d'un fichier téléchargé vers le répertoire des entrées 
copy_uploaded_input <- function(datapath, original_name, script_key) {
  dir.create(file.path("data", "uploaded"), recursive = TRUE, showWarnings = FALSE)
  ext <- tools::file_ext(original_name)
  base <- paste0("input_", script_key, "_", format(Sys.time(), "%Y%m%d_%H%M%S"))
  dest <- file.path("data", "uploaded", paste0(base, if (nzchar(ext)) paste0(".", ext) else ""))
  file.copy(datapath, dest, overwrite = TRUE)
  normalizePath(dest, winslash = "/", mustWork = TRUE)
}

# Nettoyage des fichiers importés plus anciens que max_age_days ou suppression de tous les fichiers si remove_all = TRUE
cleanup_uploaded_inputs <- function(max_age_days = 30, remove_all = FALSE) {
  upload_dir <- file.path("data", "uploaded")
  dir.create(upload_dir, recursive = TRUE, showWarnings = FALSE)

  files <- list.files(upload_dir, full.names = TRUE, recursive = FALSE, all.files = FALSE)
  files <- files[file.exists(files) & !dir.exists(files)]

  if (!length(files)) {
    return(list(total = 0L, removed = 0L, kept = 0L))
  }

  info <- file.info(files)
  now_ts <- Sys.time()
  ages_days <- as.numeric(difftime(now_ts, info$mtime, units = "days"))

  to_remove <- if (isTRUE(remove_all)) {
    rep(TRUE, length(files))
  } else {
    ages_days > max_age_days
  }

  removed <- 0L
  if (any(to_remove)) {
    removed <- sum(file.remove(files[to_remove]))
  }

  list(
    total = as.integer(length(files)),
    removed = as.integer(removed),
    kept = as.integer(length(files) - removed)
  )
}

# Exécution d'un script R avec journalisation et gestion des variables d'environnement 
run_pipeline <- function(script_key, input_path = NULL) {
  cfg <- script_catalogue[[script_key]]
  if (is.null(cfg)) stop("Application inconnue.", call. = FALSE)
  if (!file.exists(cfg$script)) stop("Script introuvable : ", cfg$script, call. = FALSE)

  input_path <- input_path %||% cfg$default_input
  if (!file.exists(input_path)) stop("Fichier d'entrée introuvable : ", input_path, call. = FALSE)

  dir.create("logs", recursive = TRUE, showWarnings = FALSE)
  dir.create(cfg$output_dir, recursive = TRUE, showWarnings = FALSE)
  run_log <- file.path("logs", paste0("run_", script_key, "_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".log"))

  env <- c(
    paste0(cfg$env_input, "=", normalizePath(input_path, winslash = "/", mustWork = TRUE)),
    paste0(cfg$env_output, "=", normalizePath(cfg$output_dir, winslash = "/", mustWork = FALSE))
  )

  if (script_key == "ICR") {
    env <- c(env, "INVENTAIRES_AUTO_RUN=TRUE")
  }

  status <- system2(
    command = "Rscript",
    args = c(normalizePath(cfg$script, winslash = "/", mustWork = TRUE)),
    stdout = run_log,
    stderr = run_log,
    env = env
  )

  list(
    status = status,
    ok = identical(status, 0L),
    log = normalizePath(run_log, winslash = "/", mustWork = TRUE),
    output_dir = normalizePath(cfg$output_dir, winslash = "/", mustWork = FALSE),
    input = normalizePath(input_path, winslash = "/", mustWork = TRUE),
    script_key = script_key
  )
}

# ==================================================================================================================================
# Interface Shiny
# ==================================================================================================================================
ui <- fluidPage(
  titlePanel("myco_apps_releases — lancement local"),
  sidebarLayout(
    sidebarPanel(
      h4("1. Choisir l'application"),
      selectInput(
        "script_key",
        label = NULL,
        choices = setNames(names(script_catalogue), vapply(script_catalogue, `[[`, character(1), "label"))
      ),
      hr(),
      h4("2. Choisir les données"),
      radioButtons(
        "input_mode",
        label = NULL,
        choices = c("Utiliser le fichier d'exemple fourni" = "example", "Charger mon propre fichier" = "upload"),
        selected = "example"
      ),
      fileInput("input_file", "Fichier CSV ou XLSX", accept = c(".csv", ".txt", ".xlsx", ".xls")),
      hr(),
      actionButton("run", "Lancer l'analyse", class = "btn-primary"),
      br(), br(),
      actionButton("clean_uploads", "Nettoyer les fichiers importés", class = "btn-warning"),
      br(), br(),
      downloadButton("download_log", "Télécharger le dernier log"),
      br(), br(),
      actionButton("quit_app", "Quitter l'application", class = "btn-danger"),
      br(), br(),
      helpText("Les résultats sont écrits dans le dossier applications/results/." ),
      helpText("Pour fermer complètement l'application, cliquez sur “Quitter l'application”, puis fermez cette page.")
    ),
    mainPanel(
      tabsetPanel(
        tabPanel("Accueil",
          h3("Mode d'emploi"),
          tags$ol(
            tags$li("Choisir l'application."),
            tags$li("Utiliser les données d'exemple ou charger un fichier."),
            tags$li("Cliquer sur “Lancer l'analyse”."),
            tags$li("Consulter les résultats dans l'onglet Résultats, ou dans le dossier applications/results/." )
          ),
          h4("Colonnes attendues — ICR"),
          tags$p("site, date, visite_id, espece ; placette est optionnelle."),
          h4("Colonnes attendues — CHEGD"),
          tags$p("Espèces, Famille, Date, Nombre d'espèce, Site, Fiabilité détermination.")
        ),
        tabPanel("Exécution",
          h3("État"),
          verbatimTextOutput("status"),
          h3("Dernier log"),
          verbatimTextOutput("log_tail")
        ),
        tabPanel("Résultats",
          h3("Fichiers produits"),
          DTOutput("outputs")
        )
      )
    )
  )
)

# ==================================================================================================================================
# Serveur Shiny
# ==================================================================================================================================
server <- function(input, output, session) {
  state <- reactiveValues(last = NULL, message = "Aucune analyse lancée.")

  startup_cleanup <- cleanup_uploaded_inputs(max_age_days = 30, remove_all = FALSE)
  if (startup_cleanup$removed > 0) {
    showNotification(
      paste0("Nettoyage automatique : ", startup_cleanup$removed, " fichier(s) importé(s) ancien(s) supprimé(s)."),
      type = "message",
      duration = 8
    )
  }

  observeEvent(input$clean_uploads, {
    res <- cleanup_uploaded_inputs(remove_all = TRUE)
    msg <- paste0(
      "Nettoyage terminé. Fichiers supprimés : ", res$removed,
      " | Restants : ", res$kept
    )
    state$message <- paste("Aucune analyse lancée.", msg, sep = "\n")
    showNotification(msg, type = "message", duration = 8)
  })

  observeEvent(input$quit_app, {
    showModal(modalDialog(
      title = "Application arrêtée",
      "La session Shiny va être fermée. Vous pouvez fermer cet onglet et la fenêtre Terminal.",
      easyClose = TRUE,
      footer = modalButton("Fermer")
    ))
    later::later(function() {
      stopApp()
    }, delay = 0.5)
  })

  observeEvent(input$run, {
    state$message <- "Analyse en cours. La fenêtre peut rester active pendant le calcul."
    state$last <- NULL

    withProgress(message = "Analyse en cours...", value = 0.2, {
      tryCatch({
        script_key <- input$script_key
        input_path <- NULL
        if (identical(input$input_mode, "upload")) {
          req(input$input_file)
          input_path <- copy_uploaded_input(input$input_file$datapath, input$input_file$name, script_key)
        }
        input_for_validation <- input_path %||% script_catalogue[[script_key]]$default_input
        validation <- validate_input_columns(input_for_validation, script_key)
        if (!isTRUE(validation$ok)) {
          stop(validation$message, call. = FALSE)
        }
        incProgress(0.4, detail = "Exécution du script R")
        res <- run_pipeline(script_key, input_path)
        incProgress(0.9, detail = "Lecture des sorties")
        state$last <- res
        produced_files <- nrow(safe_list_files(res$output_dir))
        if (isTRUE(res$ok)) {
          state$message <- paste(
            "Analyse terminée avec succès.",
            paste0("Application : ", res$script_key),
            paste0("Entrée : ", res$input),
            paste0("Sorties : ", res$output_dir),
            paste0("Fichiers détectés : ", produced_files),
            sep = "\n"
          )
        } else {
          state$message <- paste("L'analyse s'est terminée avec une erreur.", "Consultez le log ci-dessous.", "Log :", res$log, sep = "\n")
        }
      }, error = function(e) {
        state$message <- paste("Erreur :", conditionMessage(e))
      })
    })
  })

  output$status <- renderText({ state$message })

  output$log_tail <- renderText({
    res <- state$last
    if (is.null(res) || is.null(res$log) || !file.exists(res$log)) return("Aucun log disponible.")
    lines <- readLines(res$log, warn = FALSE, encoding = "UTF-8")
    paste(tail(lines, 80), collapse = "\n")
  })

  output$outputs <- renderDT({
    res <- state$last
    path <- if (!is.null(res)) res$output_dir else script_catalogue[[input$script_key]]$output_dir
    datatable(safe_list_files(path), options = list(pageLength = 25, scrollX = TRUE))
  })

  output$download_log <- downloadHandler(
    filename = function() paste0("log_myco_apps_", Sys.Date(), ".txt"),
    content = function(file) {
      res <- state$last
      if (is.null(res) || is.null(res$log) || !file.exists(res$log)) {
        writeLines("Aucun log disponible.", file)
      } else {
        file.copy(res$log, file, overwrite = TRUE)
      }
    }
  )
}

# Lancement de l'application Shiny
shinyApp(ui, server)
