library(shiny)
library(DT)

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || is.na(x) || !nzchar(x)) y else x

script_catalogue <- list(
  ICR = list(
    label = "Inventaires fongiques — Complétude & Représentativité (ICR)",
    script = file.path("scripts", "Inventaires_completude_representativite.R"),
    default_input = file.path("data", "observations.csv"),
    output_dir = file.path("results", "ICR"),
    env_input = "INVENTAIRES_INPUT_FILE",
    env_output = "INVENTAIRES_OUTPUT_DIR"
  ),
  CHEGD = list(
    label = "Évaluation potentiel fongique / intérêt patrimonial / gradient CHEGD",
    script = file.path("scripts", "Evaluation_Potentiel_Fongique_Interets_Patrimoniaux_CHEGD.R"),
    default_input = file.path("data", "données_récoltes_chegd_pelouses.csv"),
    output_dir = file.path("results", "EPFIP_CHEGD"),
    env_input = "CHEGD_INPUT_FILE",
    env_output = "CHEGD_OUTPUT_DIR"
  )
)

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

copy_uploaded_input <- function(datapath, original_name, script_key) {
  dir.create(file.path("data", "uploaded"), recursive = TRUE, showWarnings = FALSE)
  ext <- tools::file_ext(original_name)
  base <- paste0("input_", script_key, "_", format(Sys.time(), "%Y%m%d_%H%M%S"))
  dest <- file.path("data", "uploaded", paste0(base, if (nzchar(ext)) paste0(".", ext) else ""))
  file.copy(datapath, dest, overwrite = TRUE)
  normalizePath(dest, winslash = "/", mustWork = TRUE)
}

run_pipeline <- function(script_key, input_path = NULL) {
  cfg <- script_catalogue[[script_key]]
  if (is.null(cfg)) stop("Application inconnue.", call. = FALSE)
  if (!file.exists(cfg$script)) stop("Script introuvable : ", cfg$script, call. = FALSE)

  input_path <- input_path %||% cfg$default_input
  if (!file.exists(input_path)) stop("Fichier d'entrée introuvable : ", input_path, call. = FALSE)

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
    input = normalizePath(input_path, winslash = "/", mustWork = TRUE)
  )
}

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
      downloadButton("download_log", "Télécharger le dernier log"),
      br(), br(),
      actionButton("quit_app", "Quitter l'application", class = "btn-danger"),
      br(), br(),
      helpText("Les résultats sont écrits dans le dossier application/results/." ),
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
            tags$li("Consulter les résultats dans l'onglet Résultats, ou dans le dossier application/results/." )
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

server <- function(input, output, session) {
  state <- reactiveValues(last = NULL, message = "Aucune analyse lancée.")

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
        incProgress(0.4, detail = "Exécution du script R")
        res <- run_pipeline(script_key, input_path)
        incProgress(0.9, detail = "Lecture des sorties")
        state$last <- res
        if (isTRUE(res$ok)) {
          state$message <- paste("Analyse terminée avec succès.", "Entrée :", res$input, "Sorties :", res$output_dir, sep = "\n")
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

shinyApp(ui, server)
