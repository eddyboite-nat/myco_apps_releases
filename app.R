#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  if (!requireNamespace("shiny", quietly = TRUE)) {
    stop("Package R requis manquant : shiny. Installez-le avec install.packages('shiny').", call. = FALSE)
  }
  if (!requireNamespace("processx", quietly = TRUE)) {
    stop("Package R requis manquant : processx. Installez-le avec install.packages('processx').", call. = FALSE)
  }
  if (!requireNamespace("later", quietly = TRUE)) {
    stop("Package R requis manquant : later. Installez-le avec install.packages('later').", call. = FALSE)
  }
})

library(shiny)

`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

app_file <- local({
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg)) {
    normalizePath(sub("^--file=", "", file_arg[[1]]), winslash = "/", mustWork = FALSE)
  } else {
    src <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
    normalizePath(src %||% "app.R", winslash = "/", mustWork = FALSE)
  }
})

base_dir <- dirname(app_file)
scripts_dir <- file.path(base_dir, "scripts")
data_dir <- file.path(base_dir, "data")
logs_dir <- file.path(base_dir, "logs")
results_dir <- file.path(base_dir, "results")
rscript_bin <- Sys.which("Rscript")
if (!nzchar(rscript_bin)) {
  stop("Rscript est introuvable dans le PATH.", call. = FALSE)
}

icr_script <- "Inventaires_completude_representativite.R"
chegd_script <- "Evaluation_Potentiel_Fongique_Interets_Patrimoniaux_CHEGD.R"
chegd_default_data <- "données_récoltes_chegd_pelouses.csv"

ensure_dir <- function(path) {
  if (!dir.exists(path)) {
    ok <- dir.create(path, recursive = TRUE, showWarnings = FALSE)
    if (!isTRUE(ok) && !dir.exists(path)) {
      stop("Impossible de créer le répertoire : ", path, call. = FALSE)
    }
  }
}

ensure_dir(logs_dir)
ensure_dir(results_dir)

safe_child <- function(root, relative_path, must_work = TRUE) {
  root_norm <- normalizePath(root, winslash = "/", mustWork = TRUE)
  candidate <- normalizePath(file.path(root_norm, relative_path), winslash = "/", mustWork = must_work)
  if (!identical(candidate, root_norm) && !startsWith(candidate, paste0(root_norm, "/"))) {
    stop("Chemin invalide : ", relative_path, call. = FALSE)
  }
  candidate
}

copy_file_checked <- function(from, to, context) {
  ok <- file.copy(from, to, overwrite = TRUE)
  if (!isTRUE(ok) || !file.exists(to)) {
    stop(
      "Copie impossible (", context, ").\n",
      "Source : ", from, "\n",
      "Destination : ", to,
      call. = FALSE
    )
  }
  invisible(to)
}

remove_file_checked <- function(path, context) {
  if (!file.exists(path)) return(invisible(TRUE))
  ok <- unlink(path)
  if (!identical(ok, 0L) && file.exists(path)) {
    stop("Suppression impossible (", context, ") : ", path, call. = FALSE)
  }
  invisible(TRUE)
}

is_port_available <- function(host, port) {
  con <- NULL
  tryCatch({
    con <- suppressWarnings(socketConnection(host = host, port = port, open = "r+", blocking = TRUE, timeout = 1))
    FALSE
  }, error = function(e) {
    TRUE
  }, finally = {
    if (!is.null(con)) close(con)
  })
}

normalize_file_name <- function(value) {
  ascii <- iconv(value, from = "", to = "ASCII//TRANSLIT")
  ascii[is.na(ascii)] <- value[is.na(ascii)]
  gsub("[^a-z0-9]", "", tolower(ascii))
}

relative_files <- function(root, extensions) {
  if (!dir.exists(root)) return(character())
  files <- list.files(root, recursive = TRUE, full.names = TRUE, no.. = TRUE)
  files <- files[file.info(files)$isdir %in% FALSE]
  files <- files[tolower(tools::file_ext(files)) %in% extensions]
  sort(sub(paste0("^", normalizePath(root, winslash = "/", mustWork = TRUE), "/?"), "", normalizePath(files, winslash = "/", mustWork = FALSE)))
}

file_table <- function(root, extensions, limit = 80) {
  rel <- relative_files(root, extensions)
  if (!length(rel)) {
    return(data.frame(name = character(), size = numeric(), mtime = as.POSIXct(character())))
  }
  full <- file.path(root, rel)
  info <- file.info(full)
  out <- data.frame(
    name = rel,
    size = info$size,
    mtime = info$mtime,
    stringsAsFactors = FALSE
  )
  out <- out[order(out$mtime, decreasing = TRUE), , drop = FALSE]
  utils::head(out, limit)
}

result_app_label <- function(app_id) {
  labels <- c(
    ICR = "ICR",
    EPFIP_CHEGD = "CHEGD"
  )
  labels[[app_id]] %||% app_id
}

result_apps_table <- function() {
  if (!dir.exists(results_dir)) {
    return(data.frame(id = character(), label = character(), count = integer(), latest = as.POSIXct(character())))
  }

  dirs <- list.files(results_dir, full.names = FALSE, recursive = FALSE, no.. = TRUE)
  dirs <- dirs[dir.exists(file.path(results_dir, dirs))]
  if (!length(dirs)) {
    return(data.frame(id = character(), label = character(), count = integer(), latest = as.POSIXct(character())))
  }

  rows <- lapply(dirs, function(app_id) {
    app_files <- relative_files(file.path(results_dir, app_id), c("csv", "txt", "log", "png", "pdf", "svg", "xlsx"))
    full <- file.path(results_dir, app_id, app_files)
    latest <- if (length(full)) max(file.info(full)$mtime, na.rm = TRUE) else as.POSIXct(NA)
    data.frame(
      id = app_id,
      label = result_app_label(app_id),
      count = length(app_files),
      latest = latest,
      stringsAsFactors = FALSE
    )
  })

  out <- do.call(rbind, rows)
  out <- out[order(out$latest, decreasing = TRUE, na.last = TRUE), , drop = FALSE]
  row.names(out) <- NULL
  out
}

result_file_table <- function(app_id, limit = 120) {
  if (is.null(app_id) || !nzchar(app_id)) {
    return(data.frame(name = character(), size = numeric(), mtime = as.POSIXct(character())))
  }
  app_dir <- safe_child(results_dir, app_id, must_work = TRUE)
  files <- file_table(app_dir, c("csv", "txt", "log", "png", "pdf", "svg", "xlsx"), limit = limit)
  if (nrow(files)) {
    files$name <- file.path(app_id, files$name)
    files$name <- gsub("\\\\", "/", files$name)
  }
  files
}

read_text_file <- function(root, relative_path, max_lines = 2000) {
  if (is.null(relative_path) || !nzchar(relative_path)) return("")
  path <- safe_child(root, relative_path, must_work = TRUE)
  if (!file.exists(path) || !isTRUE(file.info(path)$isdir %in% FALSE)) {
    stop("Fichier introuvable : ", relative_path, call. = FALSE)
  }

  lines <- tryCatch(
    readLines(path, warn = FALSE, encoding = "UTF-8"),
    error = function(e) readLines(path, warn = FALSE)
  )
  total <- length(lines)
  if (total > max_lines) {
    lines <- utils::tail(lines, max_lines)
    lines <- c(
      paste0("[APP INFO] Affichage limité aux ", max_lines, " dernières lignes sur ", total, "."),
      "",
      lines
    )
  }
  paste(lines, collapse = "\n")
}

find_chegd_default_file <- function() {
  exact <- file.path(data_dir, chegd_default_data)
  if (file.exists(exact)) return(exact)

  candidates <- list.files(data_dir, full.names = TRUE, no.. = TRUE)
  candidates <- candidates[file.info(candidates)$isdir %in% FALSE]
  wanted <- normalize_file_name(chegd_default_data)
  matched <- candidates[normalize_file_name(basename(candidates)) == wanted]
  if (length(matched)) matched[[1]] else exact
}

format_size <- function(bytes) {
  if (is.na(bytes)) return("")
  if (bytes < 1024) return(paste0(bytes, " o"))
  if (bytes < 1024^2) return(paste0(round(bytes / 1024), " Ko"))
  paste0(round(bytes / 1024^2, 1), " Mo")
}

resource_link <- function(root_name, rel_path) {
  paste0(root_name, "/", URLencode(rel_path, reserved = FALSE))
}

guess_table_separator <- function(path) {
  first_lines <- readLines(path, n = 5, warn = FALSE, encoding = "UTF-8")
  first_lines <- first_lines[nzchar(trimws(first_lines))]
  if (!length(first_lines)) return(";")

  count_fixed <- function(pattern) {
    matches <- gregexpr(pattern, first_lines, fixed = TRUE)
    sum(vapply(matches, function(x) if (identical(x, -1L)) 0L else length(x), integer(1)))
  }

  scores <- c(
    tab = count_fixed("\t"),
    semicolon = count_fixed(";"),
    comma = count_fixed(",")
  )
  names(which.max(scores))
}

read_csv_preview <- function(root, relative_path, max_rows = 500) {
  path <- safe_child(root, relative_path, must_work = TRUE)
  sep_name <- guess_table_separator(path)
  sep <- switch(sep_name, tab = "\t", comma = ",", semicolon = ";", ";")
  utils::read.table(
    path,
    header = TRUE,
    sep = sep,
    quote = "\"",
    comment.char = "",
    stringsAsFactors = FALSE,
    check.names = FALSE,
    fill = TRUE,
    fileEncoding = "UTF-8",
    nrows = max_rows
  )
}

render_file_links <- function(files, root_name) {
  if (!nrow(files)) return(tags$p(class = "muted", "Aucun fichier"))
  tagList(lapply(seq_len(nrow(files)), function(i) {
    tags$a(
      class = "file-link",
      href = resource_link(root_name, files$name[[i]]),
      target = "_blank",
      tags$span(files$name[[i]]),
      tags$small(paste(format_size(files$size[[i]]), "-", format(files$mtime[[i]], "%Y-%m-%d %H:%M:%S")))
    )
  }))
}

if (dir.exists(logs_dir)) addResourcePath("logs", logs_dir)
if (dir.exists(results_dir)) addResourcePath("results", results_dir)

app_state <- new.env(parent = emptyenv())
app_state$running <- FALSE
app_state$session_token <- NULL

ui <- fluidPage(
  tags$head(
    tags$title("Myco Apps Local"),
    tags$style(HTML("
      body {
        margin: 0;
        background: #f7f8f5;
        color: #20231f;
        font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      }
      .container-fluid {
        width: min(1440px, calc(100vw - 32px));
        padding: 0;
      }
      .app-header {
        min-height: 76px;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 20px;
        margin: 0 calc((100vw - min(1440px, calc(100vw - 32px))) / -2) 22px;
        padding: 18px calc((100vw - min(1440px, calc(100vw - 32px))) / 2);
        border-bottom: 1px solid #dfe4da;
        background: #eef2ea;
      }
      h1 {
        margin: 0;
        font-size: 22px;
        line-height: 1.2;
        font-weight: 700;
        letter-spacing: 0;
      }
      h2 {
        margin: 0 0 12px;
        font-size: 16px;
        line-height: 1.25;
        letter-spacing: 0;
      }
      .panel {
        background: #ffffff;
        border: 1px solid #dfe4da;
        border-radius: 8px;
        padding: 18px;
        margin-bottom: 18px;
      }
      .controls {
        display: grid;
        grid-template-columns: minmax(220px, 1fr) minmax(220px, 1fr) auto;
        gap: 14px;
        align-items: end;
      }
      label {
        color: #656d60;
        font-size: 13px;
        font-weight: 600;
      }
      .form-control, .btn {
        min-height: 42px;
        border-radius: 6px;
        font: inherit;
      }
      .btn-primary {
        background: #2f6f5e;
        border-color: #2f6f5e;
        font-weight: 700;
      }
      .btn-primary:hover, .btn-primary:focus {
        background: #245648;
        border-color: #245648;
      }
      .btn-danger-outline {
        background: #fff;
        border: 1px solid #d8b9b9;
        color: #9f2f2f;
        font-weight: 700;
      }
      .status-row {
        display: flex;
        flex-wrap: wrap;
        gap: 10px;
        align-items: center;
      }
      .badge-local {
        display: inline-flex;
        align-items: center;
        min-height: 28px;
        padding: 0 10px;
        border-radius: 999px;
        background: #edf1e9;
        color: #656d60;
        font-size: 13px;
        font-weight: 700;
      }
      .badge-running { background: #fff5d9; color: #6e5200; }
      .badge-success { background: #e5f4ec; color: #236146; }
      .badge-failed { background: #f8e6e6; color: #9f2f2f; }
      .muted {
        color: #656d60;
        font-size: 12px;
      }
      .grid {
        display: block;
      }
      pre {
        min-height: 420px;
        max-height: 62vh;
        overflow: auto;
        border-radius: 6px;
        padding: 14px;
        background: #171a16;
        color: #e8eee4;
        font: 13px/1.45 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
        white-space: pre-wrap;
        overflow-wrap: anywhere;
      }
      .file-list {
        display: grid;
        gap: 7px;
        max-height: 260px;
        overflow: auto;
        padding-right: 4px;
      }
      .file-link {
        display: grid;
        gap: 2px;
        padding: 9px 10px;
        border-radius: 6px;
        border: 1px solid #dfe4da;
        text-decoration: none;
        color: #20231f;
        background: #fbfcfa;
      }
      .file-link:hover {
        border-color: #b9c5b2;
        text-decoration: none;
        color: #20231f;
      }
      .file-link small {
        color: #656d60;
        font-size: 12px;
      }
      .nav-tabs {
        border-bottom: 1px solid #dfe4da;
        margin-bottom: 14px;
      }
      .nav-tabs > li > a {
        border-radius: 6px 6px 0 0;
        color: #496154;
        font-weight: 700;
      }
      .nav-tabs > li.active > a,
      .nav-tabs > li.active > a:focus,
      .nav-tabs > li.active > a:hover {
        color: #20231f;
        border-color: #dfe4da #dfe4da #ffffff;
      }
      .log-viewer .form-group {
        margin-bottom: 10px;
      }
      .log-viewer pre {
        min-height: 520px;
        max-height: 68vh;
      }
      .console-view pre {
        min-height: 560px;
        max-height: 70vh;
      }
      .results-browser {
        display: grid;
        grid-template-columns: 180px minmax(240px, 340px) minmax(0, 1fr);
        gap: 12px;
      }
      .results-master .form-group {
        margin-bottom: 0;
      }
      .result-file-master {
        margin-bottom: 0;
        max-height: 68vh;
        overflow: auto;
        padding-right: 4px;
      }
      .result-file-master .form-group {
        margin-bottom: 0;
      }
      .result-file-master .control-label {
        display: none;
      }
      .result-file-master .radio {
        margin: 0 0 7px;
      }
      .result-file-master .radio label {
        display: block;
        min-height: 34px;
        padding: 8px 10px 8px 28px;
        border: 1px solid #dfe4da;
        border-radius: 6px;
        background: #fbfcfa;
        color: #20231f;
        font-size: 12px;
        font-weight: 600;
        overflow-wrap: anywhere;
      }
      .result-file-master .radio input {
        margin-top: 1px;
      }
      .results-master .control-label {
        display: none;
      }
      .results-master .radio {
        margin: 0 0 7px;
      }
      .results-master .radio label {
        display: block;
        min-height: 38px;
        padding: 9px 10px 9px 28px;
        border: 1px solid #dfe4da;
        border-radius: 6px;
        background: #fbfcfa;
        color: #20231f;
        font-size: 13px;
        font-weight: 700;
      }
      .results-master .radio input {
        margin-top: 2px;
      }
      .results-detail-title {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 10px;
        margin-bottom: 8px;
      }
      .result-preview {
        margin-top: 12px;
      }
      .result-preview img {
        max-width: 100%;
        max-height: 70vh;
        border: 1px solid #dfe4da;
        border-radius: 6px;
        background: #fff;
      }
      .result-preview iframe {
        width: 100%;
        height: 70vh;
        border: 1px solid #dfe4da;
        border-radius: 6px;
        background: #fff;
      }
      .result-preview .table {
        font-size: 12px;
        background: #fff;
      }
      .result-preview-table {
        max-height: 70vh;
        overflow: auto;
        border: 1px solid #dfe4da;
        border-radius: 6px;
        padding: 8px;
        background: #fff;
      }
      .open-file-row {
        margin-top: 8px;
      }
      @media (max-width: 820px) {
        .container-fluid { width: calc(100vw - 20px); }
        .app-header {
          align-items: flex-start;
          flex-direction: column;
          margin-bottom: 10px;
          padding-top: 16px;
          padding-bottom: 16px;
        }
        .controls, .results-browser { grid-template-columns: 1fr; }
        pre { min-height: 320px; }
      }
    "))
  ),
  div(
    class = "app-header",
    h1("Myco Apps Local"),
    actionButton("shutdown", "Fermer l'app", class = "btn-danger-outline")
  ),
  div(
    class = "panel",
    div(
      class = "controls",
      selectInput("script", "Script", choices = character(), width = "100%"),
      selectInput("data_file", "Fichier de données", choices = character(), width = "100%"),
      actionButton("run", "Lancer", class = "btn-primary")
    )
  ),
  div(
    class = "panel",
    div(
      class = "status-row",
      uiOutput("status_badge", inline = TRUE),
      textOutput("run_meta", inline = TRUE)
    )
  ),
  div(
    class = "panel",
    tabsetPanel(
      id = "main_tabs",
      tabPanel(
        "Console",
        div(
          class = "console-view",
          verbatimTextOutput("console_output", placeholder = TRUE)
        )
      ),
      tabPanel(
        "Logs",
        div(
          class = "log-viewer",
          selectInput("log_file", "Fichier log", choices = character(), width = "100%"),
          div(
            class = "results-detail-title",
            strong(textOutput("log_file_title", inline = TRUE)),
            span(class = "muted", textOutput("log_file_meta", inline = TRUE))
          ),
          verbatimTextOutput("log_content", placeholder = TRUE)
        )
      ),
      tabPanel(
        "Résultats",
        div(
          class = "results-browser",
          div(class = "results-master", uiOutput("results_app_master")),
          div(class = "result-file-master", uiOutput("result_file_master")),
          div(
            class = "results-detail",
            div(
              class = "results-detail-title",
              strong(textOutput("results_app_title", inline = TRUE)),
              span(class = "muted", textOutput("results_app_meta", inline = TRUE))
            ),
            div(
              class = "results-detail-title",
              strong(textOutput("result_file_title", inline = TRUE)),
              span(class = "muted", textOutput("result_file_meta", inline = TRUE))
            ),
            div(class = "open-file-row", uiOutput("result_file_link")),
            div(class = "result-preview", uiOutput("result_preview"))
          )
        )
      )
    )
  )
)

server <- function(input, output, session) {
  session_token <- paste0(format(Sys.time(), "%Y%m%d%H%M%OS3"), "_", as.integer(stats::runif(1, 100000, 999999)))

  run <- reactiveValues(
    running = FALSE,
    status = "idle",
    script = NULL,
    data_file = NULL,
    started_at = NULL,
    finished_at = NULL,
    exit_code = NULL,
    output = character(),
    process = NULL,
    backup_path = NULL,
    target_path = NULL,
    created_target = FALSE
  )

  refresh_choices <- function() {
    scripts <- relative_files(scripts_dir, "r")
    data_files <- relative_files(data_dir, c("csv", "xlsx", "xls"))
    selected_script <- isolate(input$script)
    selected_data <- isolate(input$data_file)
    if (is.null(selected_script) || !selected_script %in% scripts) {
      selected_script <- if (length(scripts)) scripts[[1]] else character()
    }
    if (is.null(selected_data) || !selected_data %in% data_files) {
      selected_data <- if (length(data_files)) data_files[[1]] else character()
    }
    updateSelectInput(session, "script", choices = scripts, selected = selected_script)
    updateSelectInput(session, "data_file", choices = data_files, selected = selected_data)
  }

  refresh_result_apps <- function() {
    apps <- result_apps_table()
    selected_app <- isolate(input$results_app)
    if (!nrow(apps)) {
      updateRadioButtons(session, "results_app", choices = character(), selected = character())
      return(invisible(apps))
    }
    if (is.null(selected_app) || !selected_app %in% apps$id) {
      selected_app <- apps$id[[1]]
    }
    labels <- paste0(apps$label, " (", apps$count, ")")
    updateRadioButtons(session, "results_app", choices = stats::setNames(apps$id, labels), selected = selected_app)
    invisible(apps)
  }

  refresh_logs <- function() {
    logs <- file_table(logs_dir, c("log", "txt"), limit = 200)
    selected_log <- isolate(input$log_file)
    if (!nrow(logs)) {
      updateSelectInput(session, "log_file", choices = character(), selected = character())
      return(invisible(logs))
    }
    if (is.null(selected_log) || !selected_log %in% logs$name) {
      selected_log <- logs$name[[1]]
    }
    labels <- paste0(logs$name, " - ", format(logs$mtime, "%Y-%m-%d %H:%M"))
    updateSelectInput(session, "log_file", choices = stats::setNames(logs$name, labels), selected = selected_log)
    invisible(logs)
  }

  refresh_result_files <- function() {
    apps <- result_apps_table()
    selected_app <- isolate(input$results_app)
    if (is.null(selected_app) || !selected_app %in% apps$id) {
      selected_app <- if (nrow(apps)) apps$id[[1]] else ""
    }

    files <- result_file_table(selected_app)
    selected_file <- isolate(input$result_file)
    if (!nrow(files)) {
      updateRadioButtons(session, "result_file", choices = character(), selected = character())
      return(invisible(files))
    }
    if (is.null(selected_file) || !selected_file %in% files$name) {
      selected_file <- files$name[[1]]
    }
    labels <- paste0(files$name, " - ", format(files$mtime, "%Y-%m-%d %H:%M"))
    updateRadioButtons(session, "result_file", choices = stats::setNames(files$name, labels), selected = selected_file)
    invisible(files)
  }

  append_output <- function(lines) {
    lines <- lines[nzchar(lines) | !is.na(lines)]
    if (!length(lines)) return()
    run$output <- utils::tail(c(run$output, lines), 2500)
  }

  restore_chegd_input <- function() {
    if (!is.null(run$backup_path) && !is.null(run$target_path) && file.exists(run$backup_path)) {
      tryCatch({
        copy_file_checked(run$backup_path, run$target_path, "restauration du fichier d'entrée CHEGD")
        remove_file_checked(run$backup_path, "suppression de la sauvegarde CHEGD")
      }, error = function(e) {
        append_output(paste("[APP WARN]", conditionMessage(e)))
      })
    } else if (isTRUE(run$created_target) && !is.null(run$target_path) && file.exists(run$target_path)) {
      tryCatch({
        remove_file_checked(run$target_path, "suppression du fichier d'entrée CHEGD temporaire")
      }, error = function(e) {
        append_output(paste("[APP WARN]", conditionMessage(e)))
      })
    }
    run$backup_path <- NULL
    run$target_path <- NULL
    run$created_target <- FALSE
  }

  release_global_lock <- function() {
    if (isTRUE(app_state$running) && identical(app_state$session_token, session_token)) {
      app_state$running <- FALSE
      app_state$session_token <- NULL
    }
  }

  acquire_global_lock <- function() {
    if (isTRUE(app_state$running) && !identical(app_state$session_token, session_token)) {
      stop("Une autre exécution est déjà en cours dans une autre fenêtre de l'application.", call. = FALSE)
    }
    if (isTRUE(run$running)) {
      stop("Une exécution est déjà en cours dans cette fenêtre.", call. = FALSE)
    }
    app_state$running <- TRUE
    app_state$session_token <- session_token
    invisible(TRUE)
  }

  refresh_choices()
  refresh_result_apps()
  refresh_logs()
  refresh_result_files()

  observe({
    invalidateLater(2500, session)
    refresh_choices()
    refresh_result_apps()
    refresh_logs()
  })

  observeEvent(input$results_app, {
    refresh_result_files()
  }, ignoreInit = TRUE)

  observe({
    invalidateLater(1000, session)

    if (!is.null(run$process)) {
      lines <- tryCatch(run$process$read_output_lines(), error = function(e) character())
      append_output(lines)

      if (!run$process$is_alive()) {
        lines <- tryCatch(run$process$read_output_lines(), error = function(e) character())
        append_output(lines)
        run$exit_code <- run$process$get_exit_status()
        run$status <- if (identical(run$exit_code, 0L)) "success" else "failed"
        run$running <- FALSE
        run$finished_at <- Sys.time()
        run$process <- NULL
        restore_chegd_input()
        release_global_lock()
        refresh_result_apps()
        refresh_result_files()
        refresh_logs()
      }
    }
  })

  observeEvent(input$run, {
    script_name <- input$script
    data_name <- input$data_file
    if (!nzchar(script_name %||% "") || !nzchar(data_name %||% "")) return()

    acquired_lock <- FALSE
    tryCatch({
      acquire_global_lock()
      acquired_lock <- TRUE
      script_path <- safe_child(scripts_dir, script_name)
      data_path <- safe_child(data_dir, data_name)
      if (!file.exists(script_path) || tolower(tools::file_ext(script_path)) != "r") {
        stop("Script introuvable ou non autorisé.", call. = FALSE)
      }
      if (!file.exists(data_path) || !(tolower(tools::file_ext(data_path)) %in% c("csv", "xlsx", "xls"))) {
        stop("Fichier de données introuvable ou non autorisé.", call. = FALSE)
      }

      extra_env <- character()
      if (identical(script_name, icr_script)) {
        extra_env <- c(INVENTAIRES_INPUT_FILE = sub(paste0("^", base_dir, "/?"), "", data_path))
      } else if (identical(script_name, chegd_script)) {
        target_path <- find_chegd_default_file()
        run$target_path <- target_path
        if (!file.exists(target_path) || !identical(normalizePath(target_path, winslash = "/", mustWork = FALSE), normalizePath(data_path, winslash = "/", mustWork = TRUE))) {
          ensure_dir(dirname(target_path))
          if (file.exists(target_path)) {
            backup_path <- paste0(target_path, ".app_backup_", format(Sys.time(), "%Y%m%d%H%M%S"))
            copy_file_checked(target_path, backup_path, "sauvegarde du fichier d'entrée CHEGD")
            run$backup_path <- backup_path
          } else {
            run$created_target <- TRUE
          }
          copy_file_checked(data_path, target_path, "préparation du fichier d'entrée CHEGD")
        }
      }

      run$running <- TRUE
      run$status <- "running"
      run$script <- script_name
      run$data_file <- data_name
      run$started_at <- Sys.time()
      run$finished_at <- NULL
      run$exit_code <- NULL
      run$output <- paste("$ Rscript", shQuote(script_path))
      child_env <- Sys.getenv()
      if (length(extra_env)) {
        child_env[names(extra_env)] <- extra_env
      }
      run$process <- processx::process$new(
        command = rscript_bin,
        args = script_path,
        wd = base_dir,
        env = child_env,
        stdout = "|",
        stderr = "2>&1"
      )
    }, error = function(e) {
      run$running <- FALSE
      run$status <- "failed"
      run$finished_at <- Sys.time()
      run$exit_code <- 1L
      append_output(paste("[APP ERROR]", conditionMessage(e)))
      restore_chegd_input()
      if (isTRUE(acquired_lock)) release_global_lock()
    })
  })

  observeEvent(input$shutdown, {
    if (!is.null(run$process) && run$process$is_alive()) {
      try(run$process$kill_tree(), silent = TRUE)
    }
    restore_chegd_input()
    release_global_lock()
    showModal(modalDialog(
      title = "Application fermée",
      "Le serveur Shiny va s'arrêter.",
      footer = NULL,
      easyClose = FALSE
    ))
    later::later(function() stopApp(), delay = 0.4)
  })

  session$onSessionEnded(function() {
    if (!is.null(run$process) && run$process$is_alive()) {
      try(run$process$kill_tree(), silent = TRUE)
    }
    restore_chegd_input()
    release_global_lock()
  })

  output$status_badge <- renderUI({
    label <- switch(
      run$status,
      idle = "Inactif",
      running = "En cours",
      success = "Terminé",
      failed = "Erreur",
      run$status
    )
    class <- paste("badge-local", paste0("badge-", run$status))
    span(class = class, label)
  })

  output$run_meta <- renderText({
    if (is.null(run$script)) return("")
    text <- paste(run$script, "-", run$data_file, "- départ", format(run$started_at, "%Y-%m-%d %H:%M:%S"))
    if (!is.null(run$finished_at)) {
      text <- paste(text, "- fin", format(run$finished_at, "%Y-%m-%d %H:%M:%S"), "- code", run$exit_code)
    }
    text
  })

  output$console_output <- renderText({
    paste(run$output, collapse = "\n")
  })

  output$log_file_title <- renderText({
    selected_log <- input$log_file
    if (is.null(selected_log) || !nzchar(selected_log)) return("Aucun log")
    selected_log
  })

  output$log_file_meta <- renderText({
    selected_log <- input$log_file
    if (is.null(selected_log) || !nzchar(selected_log)) return("")
    path <- tryCatch(safe_child(logs_dir, selected_log, must_work = TRUE), error = function(e) NULL)
    if (is.null(path) || !file.exists(path)) return("")
    info <- file.info(path)
    paste(format_size(info$size), "-", format(info$mtime, "%Y-%m-%d %H:%M:%S"))
  })

  output$log_content <- renderText({
    invalidateLater(2500, session)
    selected_log <- input$log_file
    if (is.null(selected_log) || !nzchar(selected_log)) return("Aucun fichier log disponible.")
    tryCatch(
      read_text_file(logs_dir, selected_log),
      error = function(e) paste("[APP ERROR]", conditionMessage(e))
    )
  })

  output$results_app_master <- renderUI({
    apps <- result_apps_table()
    if (!nrow(apps)) return(tags$p(class = "muted", "Aucune app"))
    labels <- paste0(apps$label, " (", apps$count, ")")
    selected_app <- input$results_app
    if (is.null(selected_app) || !selected_app %in% apps$id) {
      selected_app <- apps$id[[1]]
    }
    radioButtons("results_app", NULL, choices = stats::setNames(apps$id, labels), selected = selected_app)
  })

  output$results_app_title <- renderText({
    apps <- result_apps_table()
    selected_app <- input$results_app
    if (!nrow(apps) || is.null(selected_app) || !selected_app %in% apps$id) return("Aucun résultat")
    apps$label[match(selected_app, apps$id)]
  })

  output$results_app_meta <- renderText({
    apps <- result_apps_table()
    selected_app <- input$results_app
    if (!nrow(apps) || is.null(selected_app) || !selected_app %in% apps$id) return("")
    app <- apps[match(selected_app, apps$id), , drop = FALSE]
    latest <- if (!is.na(app$latest[[1]])) format(app$latest[[1]], "%Y-%m-%d %H:%M:%S") else "jamais"
    paste(app$count[[1]], "fichier(s) - dernier :", latest)
  })

  output$result_file_master <- renderUI({
    selected_app <- input$results_app
    apps <- result_apps_table()
    if (is.null(selected_app) || !selected_app %in% apps$id) {
      selected_app <- if (nrow(apps)) apps$id[[1]] else ""
    }
    files <- result_file_table(selected_app)
    if (!nrow(files)) return(tags$p(class = "muted", "Aucun fichier"))
    selected_file <- input$result_file
    if (is.null(selected_file) || !selected_file %in% files$name) {
      selected_file <- files$name[[1]]
    }
    labels <- paste0(files$name, " - ", format(files$mtime, "%Y-%m-%d %H:%M"))
    radioButtons("result_file", NULL, choices = stats::setNames(files$name, labels), selected = selected_file)
  })

  output$result_file_title <- renderText({
    selected_file <- input$result_file
    if (is.null(selected_file) || !nzchar(selected_file)) return("Aucun fichier")
    basename(selected_file)
  })

  output$result_file_meta <- renderText({
    selected_file <- input$result_file
    if (is.null(selected_file) || !nzchar(selected_file)) return("")
    path <- tryCatch(safe_child(results_dir, selected_file, must_work = TRUE), error = function(e) NULL)
    if (is.null(path) || !file.exists(path)) return("")
    info <- file.info(path)
    paste(format_size(info$size), "-", format(info$mtime, "%Y-%m-%d %H:%M:%S"))
  })

  output$result_file_link <- renderUI({
    selected_file <- input$result_file
    if (is.null(selected_file) || !nzchar(selected_file)) return(NULL)
    tags$a(class = "file-link", href = resource_link("results", selected_file), target = "_blank", "Ouvrir dans un nouvel onglet")
  })

  output$result_preview <- renderUI({
    selected_file <- input$result_file
    if (is.null(selected_file) || !nzchar(selected_file)) {
      return(tags$p(class = "muted", "Aucun fichier résultat disponible."))
    }

    ext <- tolower(tools::file_ext(selected_file))
    url <- resource_link("results", selected_file)

    if (ext %in% c("png", "jpg", "jpeg", "gif", "svg")) {
      return(tags$img(src = url, alt = basename(selected_file)))
    }
    if (identical(ext, "pdf")) {
      return(tags$iframe(src = url, title = basename(selected_file)))
    }
    if (ext %in% c("csv", "tsv")) {
      return(div(class = "result-preview-table", tableOutput("result_csv_preview")))
    }
    if (ext %in% c("txt", "log")) {
      return(verbatimTextOutput("result_text_preview", placeholder = TRUE))
    }

    tags$p(class = "muted", "Aperçu non disponible pour ce format. Utilisez le lien d'ouverture.")
  })

  output$result_csv_preview <- renderTable({
    selected_file <- input$result_file
    if (is.null(selected_file) || !nzchar(selected_file)) return(NULL)
    ext <- tolower(tools::file_ext(selected_file))
    if (!ext %in% c("csv", "tsv")) return(NULL)
    tryCatch(
      read_csv_preview(results_dir, selected_file),
      error = function(e) data.frame(Erreur = conditionMessage(e), check.names = FALSE)
    )
  }, striped = TRUE, hover = TRUE, bordered = TRUE, spacing = "s")

  output$result_text_preview <- renderText({
    selected_file <- input$result_file
    if (is.null(selected_file) || !nzchar(selected_file)) return("")
    ext <- tolower(tools::file_ext(selected_file))
    if (!ext %in% c("txt", "log")) return("")
    tryCatch(
      read_text_file(results_dir, selected_file),
      error = function(e) paste("[APP ERROR]", conditionMessage(e))
    )
  })
}

app <- shinyApp(ui = ui, server = server)

if (any(grepl("^--file=", commandArgs(trailingOnly = FALSE)))) {
  host <- Sys.getenv("MYCO_APP_HOST", unset = "127.0.0.1")
  port <- as.integer(Sys.getenv("MYCO_APP_PORT", unset = "8765"))
  if (is.na(port) || port < 1 || port > 65535) {
    stop("MYCO_APP_PORT doit être un port TCP valide entre 1 et 65535.", call. = FALSE)
  }
  if (!is_port_available(host, port)) {
    stop(
      "Le port ", port, " est déjà utilisé.\n",
      "Fermez l'autre instance de l'application ou relancez avec un autre port, par exemple :\n",
      "MYCO_APP_PORT=8766 Rscript app.R",
      call. = FALSE
    )
  }
  no_browser <- tolower(Sys.getenv("MYCO_APP_NO_BROWSER", unset = "false")) %in% c("1", "true", "yes", "on")
  message("Application locale disponible : http://", host, ":", port, "/")
  shiny::runApp(app, host = host, port = port, launch.browser = !no_browser)
} else {
  app
}
