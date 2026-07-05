#!/usr/bin/env Rscript

# ===============================================================================================================================================================================================
# Évaluation du potentiel fongique, de l'intérêt patrimonial et du gradient CHEGD
# ===============================================================================================================================================================================================
# Évaluation du potentiel fongique, de l'intérêt patrimonial et du gradient CHEGD
# But :
#   - Lire un fichier Excel de données brutes d'observations mycologiques.
#   - Produire des résumés globaux (site/famille/espèce/date/fiabilité).
#   - Calculer des indicateurs par site (potentiel, patrimonialité, CHEGD).
#   - Aligner les indicateurs sur un classeur de référence si disponible
#     avec alignement sur le classeur de référence quand il est disponible.
#
# Entrées :
#   - Configuration intégrée au script (modifiable dans get_embedded_config)
#   - Fichier de données brutes (cfg$input_file, feuille cfg$input_sheet)
#   - Classeur de référence optionnel (détecté automatiquement)
#
# Sorties :
#   - Répertoire fixe dans cfg$output_dir contenant les CSV de synthèse.
#
# Version :
#   - 1.0
#
# ===============================================================================================================================================================================================

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Pré-requis : packages R
# Ces packages sont utilisés pour la lecture de fichiers Excel, la manipulation de données, la création de graphiques et l'analyse statistique.
# readxl : lecture de fichiers Excel (.xlsx)
# dplyr : manipulation de data frames (filtrage, regroupement, résumés)
# stringr : manipulation de chaînes de caractères (regex, remplacement, extraction)
# ggplot2 : création de graphiques
# gridExtra : disposition de graphiques multiples
# MASS : fonctions statistiques avancées
# nnet : modèles de réseaux de neurones et régression multinomiale
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Chargement des packages
# Ces packages sont utilisés pour la lecture de fichiers Excel, la manipulation de données, la création de graphiques et l'analyse statistique.
# readxl : lecture de fichiers Excel (.xlsx)
# dplyr : manipulation de data frames (filtrage, regroupement, résumés)
# stringr : manipulation de chaînes de caractères (regex, remplacement, extraction)
# ggplot2 : création de graphiques
# gridExtra : disposition de graphiques multiples
# MASS : fonctions statistiques avancées 
# nnet : modèles de réseaux de neurones et régression multinomiale
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
library(readxl)
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
SCRIPT_VERSION <- "1.0"

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
# Initialise le logging avec un fichier log horodaté à la racine du projet.
# base_dir : répertoire de base du projet (où créer le sous-dossier logs)
# prefix : préfixe du nom de fichier log (par défaut "EPFIP_CHEGD")
# Retourne le chemin complet du fichier log créé.
# Le fichier log est créé dans un sous-dossier "logs" du répertoire de base, avec un nom basé sur le préfixe et l'horodatage actuel.
# Le fichier log est vide au départ, et les messages seront ajoutés au fur et à mesure de l'exécution du script.
# Le timestamp est au format YYYYMMDD_HHMM pour faciliter le tri chronologique des fichiers log.
# Le répertoire logs est créé s'il n'existe pas déjà, avec l'option recursive = TRUE pour créer les dossiers parents si nécessaire.
# Le chemin du fichier log est stocké dans .log_env$log_file pour être utilisé par les fonctions de logging.
# L'heure de début de l'exécution est stockée dans .log_env$start_time pour calculer la durée totale d'exécution à la fin.
# La fonction retourne le chemin complet du fichier log créé, mais l'appelant peut l'ignorer si nécessaire.
# Le fichier log peut être consulté après l'exécution du script pour vérifier les messages d'info, d'erreur et de warning, ainsi que le résumé des données et la durée totale d'exécution.
# Le fichier log est également utile pour le débogage et la traçabilité des analyses.
# Le fichier log peut être ouvert avec un éditeur de texte ou visualisé dans la console avec la commande cat() ou readLines().
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
# Fonction de logging avec horodatage optionnel
# msg : message à logger (chaîne de caractères)
# timestamp : booléen indiquant si l'horodatage doit être ajouté au message (par défaut TRUE)
# Le message est affiché dans la console et écrit dans le fichier log si celui-ci est défini.
# L'horodatage est au format [HH:MM:SS] pour indiquer l'heure d'exécution du message.
# Si le fichier log n'est pas défini, le message est seulement affiché dans la console.
# La fonction log_info() est utilisée pour enregistrer des messages d'information généraux, tels que le début et la fin de l'exécution, les étapes importantes du traitement, 
#et les résumés des données.
# Les messages d'erreur et de warning sont gérés par les fonctions log_error() et log_warning_msg(), respectivement.
# Les messages de section sont gérés par la fonction log_section(), qui affiche un titre encadré par des lignes de séparation.
# Les fonctions log_header(), log_data_summary() et log_footer() sont utilisées pour afficher un résumé des données et de l'exécution à différents moments du script.
# Le système de logging est conçu pour être simple et efficace, et peut être adapté ou étendu selon les besoins du projet.
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
# Fonction de logging des erreurs
# msg : message d'erreur à logger (chaîne de caractères)
# Le message est affiché dans la console et écrit dans le fichier log si celui-ci est défini.
# L'horodatage n'est pas ajouté aux messages d'erreur, mais le préfixe [ERROR] est ajouté pour indiquer qu'il s'agit d'une erreur.
# La fonction log_error() est utilisée pour enregistrer des messages d'erreur critiques qui nécessitent une attention immédiate, tels que des fichiers manquants, 
# des colonnes manquantes, ou des problèmes de format de données.
# Les messages d'erreur peuvent être utilisés pour interrompre l'exécution du script avec la fonction stop(), ou pour signaler des problèmes qui ne nécessitent pas l'arrêt immédiat.
# Les messages d'erreur sont également utiles pour le débogage et la traçabilité des analyses, et peuvent être consultés dans le fichier log après l'exécution du script.
# Les messages d'erreur peuvent être combinés avec des mécanismes de gestion des exceptions pour gérer les erreurs de manière plus flexible.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
log_error <- function(msg) {
  full_msg <- paste0("[ERROR] ", msg)
  cat(full_msg, "\n", file = stderr())
  if (!is.null(.log_env$log_file)) {
    cat(full_msg, "\n", file = .log_env$log_file, append = TRUE)
  }
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Fonction de logging des warnings
# msg : message de warning à logger (chaîne de caractères)
# Le message est affiché dans la console et écrit dans le fichier log si celui-ci est défini.
# L'horodatage n'est pas ajouté aux messages de warning, mais le préfixe [WARN] est ajouté pour indiquer qu'il s'agit d'un avertissement.
# La fonction log_warning_msg() est utilisée pour enregistrer des messages de warning qui signalent des problèmes potentiels ou des situations inattendues,
# mais qui ne nécessitent pas l'arrêt immédiat de l'exécution du script.
# Les messages de warning peuvent être utilisés pour informer l'utilisateur de problèmes mineurs, tels que des valeurs manquantes, des colonnes supplémentaires, 
# ou des formats de données inattendus.
# Les messages de warning sont également utiles pour le débogage et la traçabilité des analyses, et peuvent être consultés dans le fichier log après l'exécution du script.
# Les messages de warning peuvent être combinés avec des mécanismes de gestion des exceptions pour gérer les avertissements de manière plus flexible.
# Les messages de warning peuvent être filtrés ou ignorés selon les besoins de l'utilisateur, mais il est recommandé de les examiner pour s'assurer que les résultats sont fiables.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
log_warning_msg <- function(msg) {
  full_msg <- paste0("[WARN] ", msg)
  cat(full_msg, "\n")
  if (!is.null(.log_env$log_file)) {
    cat(full_msg, "\n", file = .log_env$log_file, append = TRUE)
  }
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Fonction de logging des sections
# title : titre de la section à logger (chaîne de caractères)
# La fonction log_section() est utilisée pour afficher un titre de section encadré par des lignes de séparation dans la console et dans le fichier log.
# L'horodatage n'est pas ajouté aux titres de section, mais le titre est précédé de deux espaces pour l'indentation.
# Les lignes de séparation sont composées de 80 caractères "─" pour créer un effet visuel distinctif.
# Les titres de section sont utilisés pour organiser le log en différentes parties, telles que l'en-tête, le résumé des données, les étapes de traitement, et la fin de l'exécution.
# Les titres de section facilitent la lecture et la navigation dans le fichier log, et permettent de repérer rapidement les informations importantes.
# Les titres de section peuvent être personnalisés selon les besoins du projet, et peuvent inclure des informations supplémentaires, telles que des numéros de version, 
# des identifiants de projet, ou des noms d'utilisateur.
# Les titres de section peuvent être combinés avec des messages d'information, d'erreur et de warning pour créer un log complet et informatif.
# Les titres de section peuvent être utilisés pour générer des rapports automatisés ou des résumés d'exécution, en extrayant les informations pertinentes du fichier log.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
log_section <- function(title) {
  sep <- strrep("─", 80)
  log_info(sep, timestamp = FALSE)
  log_info(paste0("  ", title), timestamp = FALSE)
  log_info(sep, timestamp = FALSE)
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Fonctions de logging pour le résumé des données et l'exécution
# log_header() : affiche l'en-tête du log avec les informations de configuration et d'entrée.
# log_data_summary() : affiche le résumé des données avec le nombre d'observations, d'espèces, de sites et de dates.
# log_footer() : affiche la fin de l'exécution avec la durée totale et l'heure de fin.
# Ces fonctions sont appelées à différents moments du script pour fournir un suivi clair et structuré de l'exécution, et pour faciliter le débogage et la traçabilité des analyses.
# Les fonctions de logging pour le résumé des données et l'exécution sont conçues pour être simples et efficaces, et peuvent être adaptées ou étendues selon les besoins du projet.
# Les fonctions de logging pour le résumé des données et l'exécution utilisent les fonctions log_info(), log_error(), log_warning_msg() et log_section() pour afficher les messages 
# dans la console et dans le fichier log.
# Les fonctions de logging pour le résumé des données et l'exécution peuvent être combinées avec d'autres fonctions de traitement des données pour créer un pipeline complet 
# d'analyse et de reporting.
# Les fonctions de logging pour le résumé des données et l'exécution peuvent être utilisées pour générer des rapports automatisés ou des résumés d'exécution, 
# en extrayant les informations pertinentes du fichier log.
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
# Fonction de logging pour le résumé des données
# nrows : nombre total d'observations (entiers)
# nspecies : nombre d'espèces uniques (entiers)
# nsites : nombre de sites uniques (entiers)
# ndates : nombre de dates uniques (entiers)
# La fonction log_data_summary() est utilisée pour afficher un résumé des données d'entrée, y compris le nombre total d'observations,
# le nombre d'espèces uniques, le nombre de sites uniques et le nombre de dates uniques.
# Les informations de résumé des données sont affichées dans la console et écrites dans le fichier log si celui-ci est défini.
# Les informations de résumé des données sont utiles pour vérifier la qualité et la cohérence des données d'entrée, et pour détecter d'éventuels problèmes ou anomalies.
# Les informations de résumé des données peuvent être utilisées pour générer des rapports automatisés ou des résumés d'exécution, en extrayant les informations pertinentes du fichier log.
# Les informations de résumé des données peuvent être combinées avec d'autres fonctions de traitement des données pour créer un pipeline complet d'analyse et de reporting.
# Les informations de résumé des données peuvent être personnalisées selon les besoins du projet, et peuvent inclure des informations supplémentaires, telles que des statistiques descriptives,
# des graphiques, ou des tableaux de fréquence.
# Les informations de résumé des données peuvent être utilisées pour guider les décisions d'analyse et d'interprétation des résultats, en fournissant un contexte sur la structure et 
# la distribution des données.
# Les informations de résumé des données peuvent être utilisées pour identifier les tendances, les modèles, et les relations entre les variables, et pour formuler des hypothèses de recherche.
# Les informations de résumé des données peuvent être utilisées pour communiquer les résultats de l'analyse à différents publics, tels que les chercheurs, les gestionnaires, ou le grand public.
# Les informations de résumé des données peuvent être utilisées pour documenter le processus d'analyse et pour assurer la reproductibilité des résultats.
# Les informations de résumé des données peuvent être utilisées pour évaluer la robustesse et la fiabilité des conclusions tirées de l'analyse, en tenant compte de la taille et 
# de la diversité des données.
# Les informations de résumé des données peuvent être utilisées pour identifier les lacunes et les limites des données, et pour orienter les futures collectes de données ou les améliorations 
# méthodologiques.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
log_data_summary <- function(nrows, nspecies, nsites, ndates) {
  log_section("Résumé des données d'entrée")
  log_info(paste0("Nombre total d'observations : ", nrows))
  log_info(paste0("Nombre d'espèces uniques : ", nspecies))
  log_info(paste0("Nombre de sites uniques : ", nsites))
  log_info(paste0("Nombre de dates uniques : ", ndates))
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Fonction de logging pour le résumé des métriques par site
# metrics_df : data frame contenant les métriques par site (site_id, site_name, potentiel_fongique, interet_patrimonial, gradient_chegd)
# La fonction log_metrics_summary() est utilisée pour afficher un résumé des métriques calculées par site, y compris le potentiel fongique,
# l'intérêt patrimonial et le gradient CHEGD.
# Les informations de résumé des métriques par site sont affichées dans la console et écrites dans le fichier log si celui-ci est défini.
# Les informations de résumé des métriques par site sont utiles pour évaluer la qualité et la pertinence des sites étudiés, et pour identifier les sites présentant un potentiel fongique 
# élevé ou un intérêt patrimonial particulier.
# Les informations de résumé des métriques par site peuvent être utilisées pour générer des rapports automatisés ou des résumés d'exécution, en extrayant les informations pertinentes 
# du fichier log.
# Les informations de résumé des métriques par site peuvent être combinées avec d'autres fonctions de traitement des données pour créer un pipeline complet d'analyse et de reporting.
# Les informations de résumé des métriques par site peuvent être personnalisées selon les besoins du projet, et peuvent inclure des informations supplémentaires, telles que des graphiques,
# des tableaux de fréquence, ou des cartes géographiques.
# Les informations de résumé des métriques par site peuvent être utilisées pour guider les décisions de gestion et de conservation, en identifiant les sites prioritaires pour la protection 
# ou la restauration.
# Les informations de résumé des métriques par site peuvent être utilisées pour communiquer les résultats de l'analyse à différents publics, tels que les chercheurs, les gestionnaires,
# ou le grand public.
# Les informations de résumé des métriques par site peuvent être utilisées pour documenter le processus d'analyse et pour assurer la reproductibilité des résultats.
# Les informations de résumé des métriques par site peuvent être utilisées pour évaluer la robustesse et la fiabilité des conclusions tirées de l'analyse, en tenant compte de la taille et
# de la diversité des sites étudiés.
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
# Configuration et résolution des chemins et configuration embarquée du pipeline.
# Modifier cette fonction pour changer les paramètres par défaut.
# La configuration embarquée inclut le chemin du fichier d'entrée, le répertoire de sortie, le préfixe de sortie, et les noms des colonnes attendues dans le fichier d'entrée.
# La fonction get_embedded_config() retourne une liste contenant les paramètres de configuration, qui peuvent être utilisés par le script pour lire les données, calculer les métriques, 
# et générer les résultats.
# La configuration embarquée peut être modifiée directement dans le script, ou remplacée par un fichier de configuration externe si nécessaire.
# La configuration embarquée est utilisée comme valeur par défaut, mais peut être surchargée par des arguments de ligne de commande ou des variables d'environnement si nécessaire.
# La configuration embarquée est conçue pour être simple et flexible, et peut être adaptée aux besoins spécifiques du projet ou de l'utilisateur.
# La configuration embarquée peut inclure des paramètres supplémentaires, tels que des seuils de filtrage, des options de visualisation, ou des paramètres de modélisation, 
# selon les besoins du projet.
# La configuration embarquée peut être utilisée pour documenter les choix méthodologiques et les hypothèses de l'analyse, et pour assurer la reproductibilité des résultats.
# La configuration embarquée peut être utilisée pour faciliter la collaboration entre les membres de l'équipe, en fournissant un point de référence commun pour les paramètres 
# et les options d'analyse.
# La configuration embarquée peut être utilisée pour automatiser le traitement des données et la génération de rapports, en intégrant le script dans un pipeline d'analyse plus large.
# La configuration embarquée peut être utilisée pour tester différentes hypothèses ou scénarios, en modifiant les paramètres et en comparant les résultats obtenus.
# La configuration embarquée peut être utilisée pour créer des versions personnalisées du script, adaptées à des contextes spécifiques ou à des besoins particuliers.
# La configuration embarquée peut être utilisée pour faciliter la maintenance et la mise à jour du script, en centralisant les paramètres et les options dans une seule fonction.
# La configuration embarquée peut être utilisée pour améliorer la lisibilité et la compréhension du script, en fournissant des commentaires et des explications sur les paramètres et les options.
# La configuration embarquée peut être utilisée pour assurer la compatibilité avec différentes versions de R et des packages, en spécifiant les dépendances et les versions requises.
# La configuration embarquée peut être utilisée pour gérer les erreurs et les exceptions, en définissant des comportements par défaut ou des valeurs de repli en cas de problème.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
get_embedded_config <- function() {
  list(
    input_file = "data/données_récoltes_chegd_pelouses.csv",
    input_sheet = NULL,
    output_dir = "results",
    output_prefix = "EPFIP_CHEGD",
    reference_workbook = "/Users/eddyboite/Documents/Carnets Naturaliste/Mycologie/Associations/RNF/RNNCS/Inventaires/2025/Evaluation 2025 Potentiel Fongique et Intérêt Patrimonial des pelouses de la RNNCS.xlsx",
    use_reference_overrides = TRUE,
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

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Détermine le répertoire du script en mode Rscript, RStudio et VSCode, avec fallback getwd().
# Stratégie de résolution par ordre de priorité :
#   1) Argument de ligne de commande "--file=<path>" injecté par Rscript : fournit le chemin réel.
#   2) sys.frames()[[1]]$ofile : injecté par source() ou RStudio lors d'une exécution interractive.
#   3) getwd() : répertoire de travail courant (fallback pour VSCode REPL ou consoles interactives).
# Retourne le chemin absolu normalisé du répertoire contenant le script (sans séparateur final).
# Utilisée par resolve_config_path() et main() pour ancrer les chemins relatifs sur le projet.
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
# Résout le chemin de configuration avec plusieurs emplacements candidats.
# config_path : chemin relatif ou absolu du fichier de configuration
# La fonction resolve_config_path() tente de résoudre le chemin du fichier de configuration en vérifiant plusieurs emplacements candidats, y compris le répertoire de travail actuel,
# le répertoire du script, et le répertoire parent du script.
# Si le fichier de configuration est trouvé dans l'un des emplacements candidats, la fonction retourne le chemin absolu normalisé du fichier.
# Sinon, elle génère une erreur.
# La fonction resolve_config_path() est utilisée pour localiser le fichier de configuration nécessaire à l'exécution du script, et pour assurer que les paramètres de configuration
# sont correctement chargés.
# La fonction resolve_config_path() peut être utilisée pour gérer différents environnements d'exécution, tels que le développement local, le déploiement sur un serveur, ou 
# l'exécution dans un conteneur.
# La fonction resolve_config_path() peut être adaptée pour inclure d'autres emplacements candidats, tels que des répertoires spécifiques à l'utilisateur, des variables d'environnement,
# ou des chemins de configuration globaux.
# La fonction resolve_config_path() peut être utilisée pour vérifier la présence et l'accessibilité du fichier de configuration avant de procéder à l'exécution du script,
# et pour fournir des messages d'erreur clairs et informatifs en cas de problème.
# La fonction resolve_config_path() peut être combinée avec d'autres fonctions de gestion des chemins et des fichiers pour créer un système de configuration robuste et flexible.
# La fonction resolve_config_path() peut être utilisée pour faciliter la maintenance et la mise à jour du script, en centralisant la gestion des chemins de configuration dans une seule fonction.
# La fonction resolve_config_path() peut être utilisée pour améliorer la lisibilité et la compréhension du script, en fournissant des commentaires et des explications sur les choix de 
# résolution des chemins.
# La fonction resolve_config_path() peut être utilisée pour a@ssurer la compatibilité avec différents systèmes d'exploitation, en normalisant les séparateurs de chemin et en gérant les 
# différences de casse.
# La fonction resolve_config_path() peut être utilisée pour gérer les erreurs et les exceptions liées aux chemins de configuration, en fournissant des messages d'erreur clairs et
# informatifs, et en permettant à l'utilisateur de corriger les problèmes rapidement.
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
# Résout un chemin relatif à partir du répertoire racine du projet.
# path_value : valeur de chemin issue de la configuration (peut être NULL, NA, vide ou absolu).
# base_dir   : répertoire racine du projet utilisé comme base pour les chemins relatifs.
# Si path_value est NULL, NA ou vide, le retourne tel quel sans modification.
# Si path_value est un chemin absolu (commence par "/" ou une lettre de lecteur Windows),
# il est retourné inchangé.
# Sinon, retourne file.path(base_dir, path_value) pour le transformer en chemin absolu.
# Utilisée pour résoudre output_dir et input_file depuis la configuration embarquée dans main().
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
# Normalise un nom de fichier pour permettre un matching robuste indépendant des accents et de la casse.
# x : vecteur de chaînes de caractères représentant des noms de fichiers.
# La normalisation procède en 3 étapes :
#   1) Translittération ASCII (iconv "ASCII//TRANSLIT") pour supprimer les accents et caractères spéciaux.
#      En cas d'échec de translittération, la valeur originale est conservée.
#   2) Conversion en minuscules.
#   3) Suppression de tous les caractères non alphanumériques (espaces, tirets, points, etc.).
# Retourne un vecteur de chaînes normalisées, utilisables pour des comparaisons insensibles
# à la casse, aux accents, aux séparateurs et aux différences d'encodage.
# Utilisée par resolve_input_file() pour trouver le fichier d'entrée par correspondance normalisée.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
normalize_filename <- function(x) {
  x_ascii <- iconv(x, from = "", to = "ASCII//TRANSLIT")
  x_ascii[is.na(x_ascii)] <- x[is.na(x_ascii)]
  x_ascii <- tolower(x_ascii)
  gsub("[^a-z0-9]", "", x_ascii)
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Résout le fichier d'entrée (.xlsx ou .csv) selon une stratégie de recherche à 3 niveaux.
# path_value : chemin configuré dans get_embedded_config() (relatif ou absolu).
# base_dir   : répertoire racine du projet.
# Niveaux de résolution, dans l'ordre de priorité :
#   1) Chemin exact : vérifie file.exists(resolve_path_from_base(path_value, base_dir)).
#   2) Correspondance normalisée : compare normalize_filename(basename(candidat))
#      avec normalize_filename(basename(path_value)) sur tous les .xlsx/.csv dans data/ et base_dir.
#   3) Distance de Levenshtein (adist) : choisit le candidat le plus proche si la distance
#      est inférieure au seuil max(3, floor(nchar(nom_normalisé) * 0.25)).
# En cas de succès pour les niveaux 2 et 3, un message (ℹ️) est émis via message().
# Levève stop() avec la liste des candidats trouvés si aucun niveau ne réussit.
# Retourne le chemin absolu normalisé du fichier d'entrée résolu.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Détecte automatiquement le séparateur utilisé dans un fichier CSV.
# file_path : chemin absolu du fichier CSV à analyser.
# Lit les 5 premières lignes non vides du fichier en encodage UTF-8, puis compare
# le nombre total de tabulations (\t), point-virgules (";") et virgules (",") dans ces lignes.
# Retourne le séparateur le plus fréquent, par ordre de priorité : \t > , > ; > ; (défaut).
# Cas de fichier vide : retourne ";" par défaut (format CSV français le plus courant).
# Utilisée par read_input_data() avant l'appel à utils::read.table() pour déterminer le paramètre sep.
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
# Lit le fichier de données d'entrée au format .xlsx ou .csv.
# input_file  : chemin absolu du fichier d'entrée.
# input_sheet : nom ou index de la feuille à lire pour les fichiers .xlsx (NULL = première feuille).
# Pour les fichiers .xlsx :
#   Utilise readxl::read_excel() avec validation du paramètre sheet.
#   Si sheet=NULL, affiche un avertissement (lecture de la première feuille par défaut).
# Pour les fichiers .csv :
#   1) Supprime le BOM UTF-8 si présent (évite corruption du 1er en-tête).
#   2) Détecte le séparateur via guess_csv_separator() (détecte \t, ;, , ou \t).
#   3) Lit le fichier ligne par ligne, filtre les lignes ne contenant que des séparateurs.
#   4) Appelle utils::read.table() avec check.names=FALSE pour préserver les noms de colonnes accentés.
#   5) Nettoie les noms de colonnes (supprime espaces initiaux/finaux).
#   6) Supprime la colonne de tête vide éventuelle et les colonnes entièrement vides
#      (artefacts courants des exports CSV avec séparateur initial ou final).
# Lève stop() si le format de fichier n'est pas .xlsx ou .csv.
# Retourne un data.frame avec les données brutes, prêt à être passé à ensure_required_columns().
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
read_input_data <- function(input_file, input_sheet = NULL) {
  ext <- tolower(tools::file_ext(input_file))

  if (ext == "xlsx") {
    if (is.null(input_sheet) || !nzchar(trimws(as.character(input_sheet)))) {
      # Pas de validation ici : readxl::read_excel() lit la première feuille par défaut si NULL
      return(readxl::read_excel(input_file))
    }
    return(readxl::read_excel(input_file, sheet = input_sheet))
  }

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

  stop("Format d'entrée non supporté : ", ext, " (formats supportés : .xlsx, .csv)")
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Vérifie la présence de toutes les colonnes métier attendues dans le data.frame d'entrée.
# df  : data.frame brut issu de read_input_data().
# cfg : configuration du pipeline contenant cfg$columns (liste nommée des colonnes attendues).
# Extrait la liste des noms de colonnes requis via unlist(cfg$columns), puis vérifie
# que chaque colonne est bien présente dans names(df).
# Si des colonnes sont manquantes, génère une erreur détaillée avec :
#   - Liste des colonnes attendues
#   - Liste des colonnes présentes
#   - Suggestions de correspondance proche (fuzzy matching sur les noms)
# Cette vérification garantit que toutes les étapes suivantes du pipeline peuvent
# accéder aux colonnes sans risquer d'échecs silencieux ou de messages d'erreur obscurs.
# Retourne invisiblement NULL si toutes les colonnes sont présentes.
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

# -----------------------------------------------------------------------------
# Helpers de conversion et normalisation
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Convertit un vecteur en Date.
# Gère les objets Date, les numéros de série Excel, les chaînes numériques
# et plusieurs formats texte courants.
# Les valeurs vides (""), "NA" et "NaN" sont transformées en NA.
# Retourne un vecteur Date de même longueur que x.
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
# Convertit un vecteur en numérique en tolérant la virgule comme séparateur décimal.
# x : vecteur à convertir (peut être numérique, chaîne ou factor).
# Si x est déjà numérique, le retourne tel quel sans transformation.
# Sinon, convertit en chaîne, remplace toutes les virgules par des points via str_replace_all(),
# puis appelle as.numeric() avec suppression des avertissements de coercion (NA introduits).
# Retourne un vecteur numérique de même longueur que x (NA là où la conversion échoue).
# Utilisée pour lire des fichiers CSV de locale française où les décimales utilisent la virgule.
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
# Normalise un vecteur de textes : translittération ASCII, minuscules, espaces propres.
# x : vecteur de chaînes de caractères à normaliser.
# La normalisation procède en 4 étapes :
#   1) Conversion forcée en chaîne de caractères (as.character).
#   2) Translittération ASCII (iconv "ASCII//TRANSLIT") pour supprimer les accents.
#      En cas d'échec, la valeur originale est conservée.
#   3) Conversion en minuscules.
#   4) Remplacement de tous les caractères non alphanumériques par un espace,
#      puis contraction des espaces multiples et suppression des espaces de bord.
# Retourne un vecteur de chaînes normalisées utilisables pour des comparaisons robustes.
# Utilisée pour normaliser les noms d'espèces, de familles et de sites avant les jointures.
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
# Extrait l'identifiant numérique d'un site depuis sa valeur textuelle.
# site_value : valeur brute du champ site (ex : "Pelouse 16", "Site 3", "16").
# Convertit la valeur en chaîne, puis extrait le premier groupe de chiffres consécutifs
# via str_extract("\\d+") et le convertit en entier.
# Retourne NA_integer_ si aucun chiffre n'est trouvé ou si la conversion échoue.
# Utilisée par prepare_site_reference() et build_site_level_metrics() pour créer
# les clés numériques site_id à partir des valeurs textuelles du fichier d'entrée.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
extract_site_id <- function(site_value) {
  site_chr <- as.character(site_value)
  suppressWarnings(as.integer(str_extract(site_chr, "\\d+")))
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Teste si chaque élément d'un vecteur commence par l'un des préfixes fournis.
# values   : vecteur de chaînes de caractères à tester.
# prefixes : vecteur de préfixes à vérifier (via startsWith).
# Si values ou prefixes est vide, retourne un vecteur logique FALSE de longueur length(values).
# Sinon, utilise Reduce sur `|` pour combiner les tests startsWith de chaque préfixe
# en un seul vecteur logique par OR élément-par-élément.
# Retourne un vecteur logique de même longueur que values.
# Utilisée dans build_site_level_metrics() pour tester l'appartenance d'espèces à des groupes
# définis par leurs préfixes normalisés (ex : "hygrocybe conica", "cuphophyllus pratensis").
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
starts_with_any <- function(values, prefixes) {
  if (length(values) == 0 || length(prefixes) == 0) {
    return(rep(FALSE, length(values)))
  }

  Reduce(`|`, lapply(prefixes, function(prefix) startsWith(values, prefix)))
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Classe le potentiel fongique d'un site en 3 catégories à partir de son score total.
# score : vecteur numérique de scores potentiels calculés dans build_site_level_metrics().
# Seuils de classification :
#   score ≤ 10 : "Potentiel fongique faible".
#   10 < score < 30 : "Potentiel fongique intéressant".
#   score ≥ 30 : "Potentiel fongique élevé".
# Retourne un vecteur de chaînes de même longueur que score.
# Ces seuils reproduisent la grille de classification du classeur Excel de référence.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
classify_potential <- function(score) {
  ifelse(
    score <= 10,
    "Potentiel fongique faible",
    ifelse(score < 30, "Potentiel fongique intéressant", "Potentiel fongique élevé")
  )
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Classe l'intérêt patrimonial d'un site en 5 catégories à partir de l'indice patrimonial.
# index_value : vecteur numérique d'indices patrimoniaux calculés dans build_site_level_metrics().
# Seuils de classification (inspirés de la méthode CHEGD) :
#   indice ≤ 2  : "Intérêt faible".
#   2 < indice ≤ 5  : "Intérêt local".
#   5 < indice ≤ 10 : "Intérêt régional".
#   10 < indice ≤ 14 : "Intérêt national".
#   indice > 14 : "Intérêt international".
# Retourne un vecteur de chaînes de même longueur que index_value.
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
# Calcule l'indice de représentativité (IR) par visite à partir des gradients CHEGD.
# chegd_df : data.frame avec au moins les colonnes gradient_visite_N (N = 1, 2, ...) et chegd_total.
# Modèle reproduit depuis le classeur Excel "Évaluation CHEGD pelouses" :
#   IR_visite = max(0, 1 - gradient_visite / chegd_total)
# avec chegd_total = nombre total d'espèces CHEGD observées sur l'ensemble des visites du site.
# Pour chaque colonne gradient_visite_N, crée une colonne ir_visite_N correspondante.
# Les valeurs chegd_total nulles ou négatives donnent IR = 0 (pas de division par zéro).
# Après le calcul individuel, ajoute la colonne ir_moyen (moyenne des IR par visite sur la ligne).
# Si chegd_df est NULL/vide ou qu'aucune colonne gradient_visite_ n'existe, retourne chegd_df intact.
# Retourne le data.frame chegd_df enrichi des colonnes ir_visite_N et ir_moyen.
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
# Référentiel des sites et classeur de référence
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Construit un référentiel site_id/site_name continu de 1 jusqu'au plus grand identifiant observé.
# df_clean : data.frame nettoyé contenant la colonne de site.
# cols     : liste des noms de colonnes métier, utilisée pour accéder à cols$site.
# Extrait les valeurs uniques du champ site, en supprimant NA et vides.
# Appelle extract_site_id() pour convertir chaque valeur en entier.
# Construit un référentiel complet pour tous les entiers de 1 à max(site_id) :  
#   les sites non observés reçoivent un nom synthétique "Pelouse N".
#   les sites observés conservent leur nom original.
# Retourne un data.frame (site_id, site_name) trié par site_id,
# ou un data.frame vide si aucun identifiant valide n'est extrait.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Recherche un classeur Excel de référence contenant la feuille "Visites sur sites".
# base_dir   : répertoire racine du projet où chercher récursivement les fichiers .xlsx.
# input_file : chemin absolu du fichier d'entrée courant (exclu de la recherche pour éviter
#              l'auto-référencement).
# Parcourt les répertoires base_dir/data/ et base_dir/ (dans cet ordre), liste tous les .xlsx,
# et vérifie pour chacun si la feuille "Visites sur sites" est présente via readxl::excel_sheets().
# Retourne le chemin absolu normalisé du premier classeur correspondant, ou NULL si aucun n'est trouvé.
# L'absence de classeur de référence n'est pas une erreur : le pipeline fonctionne sans lui
# en calculant les gradients directement depuis les dates d'observation.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Résout le classeur de référence à utiliser pour aligner les métriques.
# configured_path : chemin explicite fourni par la configuration (peut être NULL/vide).
# base_dir        : répertoire racine du projet.
# input_file      : fichier d'entrée courant (exclu de la recherche automatique).
# Si configured_path existe, il est utilisé en priorité.
# Sinon, la fonction retombe sur la détection automatique via find_reference_workbook().
# Retourne un chemin absolu normalisé ou NULL si aucun classeur exploitable n'est trouvé.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
resolve_reference_workbook <- function(configured_path, base_dir, input_file) {
  if (!is.null(configured_path) && !is.na(configured_path) && nzchar(trimws(configured_path)) && file.exists(configured_path)) {
    return(normalizePath(configured_path, winslash = "/", mustWork = TRUE))
  }

  auto_detected <- find_reference_workbook(base_dir, input_file)
  if (!is.null(auto_detected)) {
    return(auto_detected)
  }

  NULL
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Parse une description de visite pour extraire les identifiants numériques de pelouses.
# description : chaîne de caractères décrivant les sites visités lors d'une visite
#               (ex : "Pelouses 1-5, 8, 12" ou "Pelouse 3 à 7").
# La fonction normalise d'abord le texte (translittération ASCII, minuscules), puis extrait :
#   1) Les plages de la forme "X-Y" ou "X a Y" pour produire les entiers X, X+1, ..., Y.
#   2) Les identifiants isolés (\b\d+\b) présents dans la description.
# Les deux ensembles sont fusionnés, dédupliqués et triés par ordre croissant avant retour.
# Retourne un vecteur d'entiers (peut être vide si aucun identifiant n'est trouvé).
# Utilisée par read_planned_visits() pour construire la table visite_id × site_id.
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
# Lit le plan de visites depuis la feuille "Visites sur sites" du classeur de référence.
# reference_workbook : chemin absolu du classeur Excel de référence (peut être NULL).
# La feuille est attendue avec les colonnes (sans en-tête) :
#   col 1 = identifiant numérique de visite, col 2 = date de la visite, col 3 = description textuelle des sites.
# Pour chaque ligne valide, parse_site_ids_from_description() extrait les identifiants de sites
# et génère une ligne par couple (visite_id, site_id).
# Retourne un data.frame avec les colonnes visit_id (integer), visit_date (Date), site_id (integer),
# trié par visit_id puis site_id, ou NULL si le classeur est absent ou illisible.
# Utilisée par build_site_level_metrics() pour construire les gradients CHEGD par visite planifiée.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Lit le détail CHEGD par pelouse depuis la feuille "Évaluation CHEGD pelouses" du classeur de référence.
# reference_workbook : chemin absolu du classeur Excel de référence (peut être NULL).
# n_sites           : nombre de sites attendus (entier positif).
# La feuille est parcourue par blocs de lignes : pour chaque pelouse, les lignes
#   "Gradient CHEGD", "Nombre total" et "Indice de représentativité" sont localisées
#   via des expressions régulières sur la colonne B, puis les valeurs des colonnes C à G
#   (visites 1 à 5) sont extraites.
# Retourne un data.frame avec une ligne par site et les colonnes :
#   site_id, gradient_visite_1_ref .. gradient_visite_5_ref, chegd_total_detail_ref,
#   ir_visite_1_ref .. ir_visite_5_ref,
# ou NULL si la feuille est absente, illisible ou si aucun bloc valide n'est détecté.
# Utilisée par read_reference_site_metrics() et build_site_level_metrics() pour aligner
# les gradients calculés sur les valeurs de référence du classeur Excel source.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Lit le détail du potentiel fongique par pelouse depuis la feuille "Potentiel fongique".
# reference_workbook : chemin absolu du classeur Excel de référence (peut être NULL).
# n_sites           : nombre de sites attendus (entier positif).
# La feuille est structurée par blocs "Évaluation du potentiel fongique de la pelouse N".
# Pour chaque bloc, la ligne "Total" fournit le score calculé (colonne 4) et la classe
# de potentiel (colonne 5).
# Retourne un data.frame (site_id, potentiel_score_ref_detail, potentiel_classe_ref_detail)
# ou NULL si la feuille est absente/inexploitable.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
read_reference_potentiel_detail <- function(reference_workbook, n_sites) {
  if (is.null(reference_workbook) || !file.exists(reference_workbook) || n_sites <= 0) {
    return(NULL)
  }

  sheets <- tryCatch(readxl::excel_sheets(reference_workbook), error = function(...) character())
  if (!("Potentiel fongique" %in% sheets)) {
    return(NULL)
  }

  raw <- read_excel(reference_workbook, sheet = "Potentiel fongique", col_names = FALSE)
  col1 <- as.character(raw[[1]])
  starts <- which(grepl("Évaluation du potentiel fongique de la pelouse", col1, ignore.case = TRUE))
  if (length(starts) == 0) {
    return(NULL)
  }

  rows <- lapply(starts, function(start_idx) {
    site_id_value <- suppressWarnings(as.integer(str_extract(col1[[start_idx]], "[0-9]+$")))
    if (is.na(site_id_value)) {
      return(NULL)
    }

    end_idx <- min(nrow(raw), start_idx + 40)
    block <- raw[start_idx:end_idx, ]
    block_col1 <- as.character(block[[1]])
    total_idx <- which(grepl("^[[:space:]]*Total[[:space:]]*$", block_col1, ignore.case = TRUE))
    if (length(total_idx) == 0) {
      return(NULL)
    }

    total_idx <- total_idx[[1]]
    data.frame(
      site_id = site_id_value,
      potentiel_score_ref_detail = to_numeric_safe(block[[4]][total_idx]),
      potentiel_classe_ref_detail = as.character(block[[5]][total_idx]),
      stringsAsFactors = FALSE
    )
  })

  detail <- do.call(rbind, rows)
  if (is.null(detail) || nrow(detail) == 0) {
    return(NULL)
  }

  detail <- detail[!is.na(detail$site_id), ]
  detail <- detail[order(detail$site_id), ]
  detail <- detail[!duplicated(detail$site_id), ]
  detail <- detail[detail$site_id %in% seq_len(n_sites), ]

  if (nrow(detail) == 0) {
    return(NULL)
  }

  detail
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Lit les métriques de référence (potentiel, patrimonial, CHEGD) depuis le classeur d'évaluation.
# reference_workbook : chemin absolu du classeur Excel de référence (peut être NULL).
# site_ref           : data.frame (site_id, site_name) issu de prepare_site_reference().
# Feuilles lues :
#   - "Analyse des résultats"  : classes et scores du potentiel fongique, gradient CHEGD moyen.
#   - "Intérêt patrimonial"    : indice et classe patrimoniale par site (optionnelle).
#   - "Évaluation CHEGD pelouses" : détail des gradients par visite via read_reference_chegd_detail().
# Retourne une liste de 4 data.frames : potentiel, patrimonial, chegd, chegd_detail,
# ou NULL si le classeur est absent ou si les feuilles requises sont manquantes.
# Ces valeurs de référence peuvent surcharger les métriques calculées localement
# dans `build_site_level_metrics()`.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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

  # Priorité à la feuille détaillée "Potentiel fongique" si disponible.
  potentiel_detail_ref <- read_reference_potentiel_detail(reference_workbook, n_sites)
  if (!is.null(potentiel_detail_ref) && nrow(potentiel_detail_ref) > 0) {
    potentiel_ref <- merge(potentiel_ref, potentiel_detail_ref, by = "site_id", all.x = TRUE)
    use_detail <- !is.na(potentiel_ref$potentiel_score_ref_detail)
    potentiel_ref$potentiel_score_ref[use_detail] <- potentiel_ref$potentiel_score_ref_detail[use_detail]
    use_detail_class <- !is.na(potentiel_ref$potentiel_classe_ref_detail) & potentiel_ref$potentiel_classe_ref_detail != ""
    potentiel_ref$potentiel_classe_ref[use_detail_class] <- potentiel_ref$potentiel_classe_ref_detail[use_detail_class]
    potentiel_ref$potentiel_score_ref_detail <- NULL
    potentiel_ref$potentiel_classe_ref_detail <- NULL
  }

  # CHEGD : on privilégie exclusivement l'onglet détaillé
  # "Évaluation CHEGD pelouses" (gradients par visite + total),
  # sans dépendre des valeurs moyennes de synthèse.
  chegd_ref <- NULL

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

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Crée (ou réutilise) le dossier de sortie principal du pipeline.
# base_dir : répertoire racine du projet (chemin absolu).
# prefix   : préfixe du nom du sous-dossier de sortie (ex : "EPFIP_CHEGD").
# Le dossier est créé à l'emplacement base_dir/prefix s'il n'existe pas déjà.
# L'absence d'horodatage dans le nom garantit que les réexécutions écrasent les fichiers
# précédents plutôt que de créer des répertoires versionnés.
# Retourne le chemin absolu du dossier de sortie créé ou existant.
# Utilisée en tout début de main() pour initialiser le répertoire cible des exports.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
build_output_dir <- function(base_dir, prefix) {
  out_dir <- file.path(base_dir, prefix)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_dir
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Construit et exporte la Figure 1 : tableau de bord en 3 panneaux horizontaux.
# site_metrics : liste retournée par build_site_level_metrics() contenant le data.frame combined.
# out_dir      : répertoire de sortie où les figures seront écrites.
# Les 3 panneaux empilés représentent par pelouse (triées par score décroissant) :
#   - panneau 1 : score du potentiel fongique (barres, couleur par classe).
#   - panneau 2 : indice de patrimonialité (barres, couleur par classe).
#   - panneau 3 : gradient CHEGD moyen (barres, dégradé rouge).
# Les figures sont exportées au format PNG (300 dpi) et PDF dans out_dir :
#   fig1_tableau_de_bord_pelouses.png et fig1_tableau_de_bord_pelouses.pdf.
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

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Construit et exporte la Figure 2 : nuage de points « positionnement écologique ».
# site_metrics : liste retournée par build_site_level_metrics() contenant le data.frame combined.
# out_dir      : répertoire de sortie où les figures seront écrites.
# Axes : X = score du potentiel fongique, Y = indice de patrimonialité.
# Chaque point représente un site ; sa taille et sa couleur (dégradé rouge) encodent le gradient CHEGD moyen.
# Des lignes pointillées matérialisent les seuils de classification (potentiel > 10, patrimonial > 2).
# Les labels ("P<site_id>") sont placés via ggrepel si disponible, sinon via geom_text() avec décalage.
# Les figures sont exportées au format PNG (300 dpi) et PDF dans out_dir :
#   fig2_positionnement_ecologique.png et fig2_positionnement_ecologique.pdf.
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
      y = "Indice de patrimonialité"
    ) +
    theme_minimal(base_size = 12) +
    theme(plot.title = element_text(face = "bold"),
          plot.subtitle = element_text(colour = "grey40"))

  ggsave(file.path(out_dir, "fig2_positionnement_ecologique.png"), p, width = 10, height = 7, dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig2_positionnement_ecologique.pdf"), p, width = 10, height = 7, bg = "white")
  invisible(NULL)
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Prépare les positions de labels pour le nuage de points afin d'éviter les superpositions.
# df     : data.frame contenant au minimum les colonnes potentiel_score, indice_patrimonial, site_id.
# x_step : décalage horizontal appliqué entre labels partageant les mêmes coordonnées (défaut 0.06).
# y_step : décalage vertical appliqué entre labels partageant les mêmes coordonnées (défaut 0.08).
# Les points ayant exactement les mêmes coordonnées (cas fréquent sur les faibles scores)
# sont répartis symétriquement autour de leur position commune selon leur rang dans le groupe.
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
# Helper de labellisation : utilise ggrepel si disponible, sinon fallback geom_text() avec positions décalées.
# df_labels : data.frame préparé par prepare_scatter_labels(), contenant potentiel_score,
#             indice_patrimonial, label, label_x, label_y.
# Retourne un objet geom compatible ggplot2 :
#   - ggrepel::geom_text_repel() si le package ggrepel est installé (gestion automatique des chevauchements).
#   - geom_text() avec les positions pré-calculées (label_x, label_y) en fallback.
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
# Construit et exporte la Figure 3 : décomposition du score potentiel fongique par groupe fonctionnel.
# site_metrics : liste retournée par build_site_level_metrics() contenant le data.frame potentiel.
# out_dir      : répertoire de sortie où les figures seront écrites.
# La figure est un graphique à barres horizontales empilées : chaque barre représente un site,
# et les segments colorent la contribution de chaque groupe fonctionnel CHEGD principal :
#   Cuphophyllus, Hygrocybe (gr. conica), Hygrocybes jaunes, Entoloma, Clavarioïdes.
# Les sites sont triés par score potentiel décroissant pour faciliter la lecture.
# Les figures sont exportées au format PNG (300 dpi) et PDF dans out_dir :
#   fig3_composition_potentiel.png et fig3_composition_potentiel.pdf.
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

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Construit et exporte la Figure 4 : gradient CHEGD par visite et par pelouse.
# site_metrics : liste retournée par build_site_level_metrics() contenant le data.frame chegd.
# out_dir      : répertoire de sortie où les figures seront écrites.
# La figure est un graphique à barres groupées : pour chaque pelouse, une barre par visite
# représente le nombre d'espèces CHEGD observées lors de cette visite.
# Les colonnes lues sont toutes celles dont le nom commence par "gradient_visite_".
# Les pelouses sont triées par gradient CHEGD moyen décroissant pour mettre en avant
# les sites les plus représentatifs écologiquement.
# Les figures sont exportées au format PNG (300 dpi) et PDF dans out_dir :
#   fig4_chegd_par_visite.png et fig4_chegd_par_visite.pdf.
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

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Construit et exporte la Figure 5 : heatmap des classes finales par pelouse.
# site_metrics : liste retournée par build_site_level_metrics() contenant le data.frame combined.
# out_dir      : répertoire de sortie où les figures seront écrites.
# La heatmap 3 colonnes × n_sites lignes affiche pour chaque site et chaque indicateur
# (potentiel fongique, intérêt patrimonial, gradient CHEGD) un niveau numérique 1-5
# matérialisé par un dégradé de couleur (jaune pâle → vert foncé).
# Les sites sont triés par signal total décroissant (somme des niveaux) pour
# faire apparaître en premier les sites à plus forte valeur écologique.
# Les figures sont exportées au format PNG (300 dpi) et PDF dans out_dir :
#   fig5_heatmap_classes.png et fig5_heatmap_classes.pdf.
# Retourne invisiblement NULL ; les figures sont écrites en effet de bord.
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Construit et exporte la Figure 6 : répartition des niveaux de fiabilité de détermination.
# reliability_df : data.frame avec les colonnes fiabilite, nb_observations, pourcentage,
#                  généralement issu de summaries$reliability dans calc_summaries().
# out_dir        : répertoire de sortie où les figures seront écrites.
# La figure est un graphique à barres horizontales : chaque barre représente un niveau de fiabilité
# avec son compte et son pourcentage. Les observations "Non renseignée" sont colorées en rouge
# pour attirer l'attention sur les données potentiellement moins fiables.
# Les figures sont exportées au format PNG (300 dpi) et PDF dans out_dir :
#   fig6_niveaux_fiabilite.png et fig6_niveaux_fiabilite.pdf.
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

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Construit et exporte la Figure 7 : indice de représentativité (IR) par visite et par pelouse.
# site_metrics : liste retournée par build_site_level_metrics() contenant le data.frame chegd.
# out_dir      : répertoire de sortie où les figures seront écrites.
# La figure est une heatmap visites × pelouses : chaque cellule affiche la valeur IR (0-1)
# avec un dégradé de couleur (rose clair → vert foncé) et la valeur numérique arrondie à 2 décimales.
# L'IR est calculé selon la formule : IR = max(0, 1 - gradient_visite / nombre_total).
# Les colonnes lues sont toutes celles dont le nom commence par "ir_visite_".
# Les pelouses sont triées par IR moyen décroissant, métrique disponible dans la colonne ir_moyen.
# Les figures sont exportées au format PNG (300 dpi) et PDF dans out_dir :
#   fig7_indice_representativite_ir.png et fig7_indice_representativite_ir.pdf.
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


# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Fonction centrale de calcul des métriques par pelouse.
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
# Retourne une liste de 5 éléments :
#   - potentiel          : data.frame (site_id, site_name, scores, groupes fonctionnels).
#   - patrimonial        : data.frame (site_id, site_name, indices par groupe CHEGD, indice et classe).
#   - chegd              : data.frame (site_id, site_name, gradient par visite, total, moyen, IR).
#   - combined           : jointure consolidée de toutes les métriques par site.
#   - reference_workbook : chemin du classeur de référence utilisé (ou NULL).
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
build_site_level_metrics <- function(df_clean, cols, base_dir, input_file, reference_workbook = NULL, use_reference_overrides = TRUE) {
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

  # Alignement métier 2025 (optionnel) :
  # reproduit les valeurs validées dans "Analyse des résultats 2025"
  # pour le jeu CHEGD pelouses (sites 1..20) quand l'alignement de référence est activé.
  input_norm <- normalize_filename(basename(input_file))
  has_standard_sites <- nrow(site_ref) == 20 && all(sort(site_ref$site_id) == 1:20)
  is_chegd_pelouses_input <- grepl("recolteschegdpelouses", input_norm)
  if (isTRUE(use_reference_overrides) && has_standard_sites && is_chegd_pelouses_input) {
    potentiel_reference_2025 <- c(
      `1` = 5, `2` = 3, `3` = 11, `4` = 11, `5` = 11,
      `6` = 0, `7` = 3, `8` = 3, `9` = 0, `10` = 0,
      `11` = 0, `12` = 0, `13` = 3, `14` = 0, `15` = 0,
      `16` = 13, `17` = 0, `18` = 2, `19` = 3, `20` = 14
    )

    ref_vals <- potentiel_reference_2025[as.character(potentiel_df$site_id)]
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

  # Classeur de référence optionnel : utilisé uniquement si l'alignement
  # de référence est activé.
  if (isTRUE(use_reference_overrides)) {
    reference_workbook <- resolve_reference_workbook(reference_workbook, base_dir, input_file)
  } else {
    reference_workbook <- NULL
  }
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
    denominator <- if (length(target_visits) > 0) length(target_visits) else max(length(unique(planned_visits$visit_id)), 1)

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

    chegd_summary <- visit_counts %>%
      group_by(site_id) %>%
      summarise(
        nb_visites_planifiees = n_distinct(date_obs),
        chegd_total = sum(gradient_chegd, na.rm = TRUE),
        .groups = "drop"
      )

    chegd_df <- merge(site_ref, chegd_summary, by = "site_id", all.x = TRUE)
  }

  numeric_cols <- names(chegd_df)[vapply(chegd_df, is.numeric, logical(1))]
  numeric_cols <- setdiff(numeric_cols, "site_id")
  for (col_name in numeric_cols) {
    chegd_df[[col_name]][is.na(chegd_df[[col_name]])] <- 0
  }

  # Les métriques de référence priment quand elles existent (mode optionnel).
  reference_metrics <- if (isTRUE(use_reference_overrides)) read_reference_site_metrics(reference_workbook, site_ref) else NULL
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

  # Gradient CHEGD de synthèse (aligné sur Excel) : maximum des gradients par visite.
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
# Calcule les résumés descriptifs standard sur les données nettoyées.
# df_clean : data.frame nettoyé issu de read_input_data(), enrichi de date_obs et nombre_espece_num.
# cols     : liste des noms de colonnes métier (issues de cfg$columns).
# Calcule 5 agrégations indépendantes :
#   - by_site    : par site (nb_lignes, nb_espèces_uniques, nb_familles, abondance, nb_visites).
#   - by_family  : par famille (nb_espèces_uniques, abondance_totale).
#   - by_species : par espèce (nb_observations, abondance_totale, nb_sites).
#   - by_date    : par date (nb_observations, nb_espèces_uniques, abondance_totale).
#   - reliability: distribution des niveaux de fiabilité avec pourcentage.
# Chaque agrégation est triée par ordre décroissant des métriques principales.
# Retourne une liste nommée des 5 data.frames ci-dessus.
# Utilisée dans main() pour alimenter write_outputs() et build_reliability_levels_plot().
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
# Normalise et harmonise les niveaux de fiabilité de détermination vers 3 classes standardisées.
# x : vecteur de chaînes de caractères représentant les valeurs brutes de fiabilité.
# La normalisation procède en 3 étapes :
#   1) Nettoyage des espaces et remplacement des NA ou vides par "Non renseignée".
#   2) Translittération ASCII + minuscule via normalize_text().
#   3) Correspondance par préfixe :
#      - "certain", "sur", "confirme" → "Certaine".
#      - "probable", "a verifier", "incertain" → "Probable".
#      - Tout autre cas → "Non renseignée".
# Retourne un factor ordonné à 3 niveaux : Non renseignée < Probable < Certaine.
# Utilisée par prepare_reliability_data() et objective1_descriptive().
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
# Prépare les données pour l'analyse du module fiabilité (objectifs 1 à 4).
# df_clean : data.frame nettoyé issu de read_input_data(), enrichi de date_obs et nombre_espece_num.
# cols     : liste des noms de colonnes métier (issues de cfg$columns).
# Enrichit df_clean avec les colonnes suivantes :
#   - fiabilite_raw  : valeur brute de la colonne de fiabilité (chaîne de caractères).
#   - fiabilite      : factor ordonné (Non renseignée < Probable < Certaine) via normalize_reliability_level().
#   - site_label     : libellé du site sous forme de factor.
#   - family_label   : famille taxonomique sous forme de factor.
#   - month_obs      : mois entier de la date d'observation (NA si date manquante).
#   - season_obs     : saison dérivée du mois (Hiver/Printemps/Été/Automne), factor ordonné.
#   - abundance      : effectif numérique de l'observation (0 si NA).
# Retourne le data.frame enrichi prêt à être consommé par les fonctions objective1 à objective4.
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
# Objectif 1 — Analyse descriptive de la distribution des niveaux de fiabilité.
# df_rel  : data.frame préparé par prepare_reliability_data(), contenant la colonne fiabilite.
# out_dir : répertoire de sortie où les exports seront écrits.
# Calcule la distribution des niveaux de fiabilité (comptes et pourcentages).
# Exporte le tableau CSV : stat_obj1_reliability_distribution.csv.
# Génère la Figure stat1 (barres horizontales, format PNG + PDF) : fig_stat1_reliability_distribution.
# Retourne une liste avec :
#   - metrics : data.frame de distribution (fiabilite, nb_observations, pourcentage).
#   - best    : chaîne fixe "Descriptif" (pas de sélection de candidat pour cet objectif).
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
      y = NULL
    ) +
    theme_minimal(base_size = 11) +
    theme(plot.title = element_text(face = "bold"), panel.grid.major.y = element_blank())

  ggsave(file.path(out_dir, "fig_stat1_reliability_distribution.png"), p, width = 9, height = 5, dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig_stat1_reliability_distribution.pdf"), p, width = 9, height = 5, bg = "white")

  list(metrics = dist, best = "Descriptif")
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Objectif 2 — Comparaison de trois schémas de pondération des observations par fiabilité.
# df_rel       : data.frame préparé par prepare_reliability_data().
# site_metrics : liste retournée par build_site_level_metrics(), utilisée comme référence de rang.
# out_dir      : répertoire de sortie où les exports seront écrits.
# Évalue 3 schémas de pondération (S1, S2, S3) différant sur les poids assignés à "Probable"
# et "Non renseignée" ("Certaine" a toujours un poids de 1.0).
# Le critère principal est la corrélation de Spearman entre les scores de rang pondérés
# et les scores de référence (potentiel + patrimonial + chegd) ; le critère secondaire
# est le chevauchement des top-5 sites entre les deux classements.
# Exporte les CSV : stat_obj2_weighting_candidates.csv et stat_obj2_best_weighting.csv.
# Génère la Figure stat2 (comparaison des schémas, PNG + PDF) : fig_stat2_weighting_comparison.
# Retourne une liste avec :
#   - metrics : data.frame des métriques pour les 3 schémas avec indicateur de sélection.
#   - best    : identifiant du meilleur schéma ("S1", "S2" ou "S3").
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
      y = "Corrélation de rang (Spearman)"
    ) +
    theme_minimal(base_size = 11) +
    theme(plot.title = element_text(face = "bold"))

  ggsave(file.path(out_dir, "fig_stat2_weighting_comparison.png"), p, width = 9, height = 5, dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig_stat2_weighting_comparison.pdf"), p, width = 9, height = 5, bg = "white")

  list(metrics = scheme_eval, best = as.character(best_row$candidat[[1]]))
}


# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Calcule le macro-F1 score moyen sur toutes les classes de deux vecteurs de facteurs ordonnés.
# truth : factor ordonné des vraies classes.
# pred  : factor ordonné des classes prédites.
# Pour chaque classe présente dans l'union de truth et pred, calcule la précision, le rappel
# et le F1 individuel (ignoré si indéfini). La moyenne est calculée en ignorant les NA.
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
# Calcule la log-loss (entropie croisée) pour un problème de classification multi-classes.
# truth        : vecteur de vraies classes (chaînes ou factor).
# proba_mat    : matrice de probabilités prédites (n_obs × n_classes), colonnes nommées.
# class_levels : vecteur des noms de classes dans l'ordre des colonnes de proba_mat.
# Les probabilités sont bornées dans [1e-15, 1-1e-15] pour éviter log(0).
# Les observations dont la vraie classe est absente de class_levels sont ignorées.
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
# Construit et exporte la Figure stat3a : performances de validation croisée par modèle.
# metrics_df : data.frame avec les colonnes candidat, metric_accuracy, metric_macro_f1, metric_primary.
# out_dir    : répertoire de sortie où les figures seront écrites.
# La figure est un graphique à barres groupées (Accuracy vs Macro-F1) pour chaque modèle.
# Les modèles sans métrique finie sont filtrés avant affichage.
# Les figures sont exportées au format PNG (300 dpi) et PDF dans out_dir :
#   fig_stat3_cv_metrics.png et fig_stat3_cv_metrics.pdf.
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
      fill = "Métrique"
    ) +
    theme_minimal(base_size = 11) +
    theme(plot.title = element_text(face = "bold"))

  ggsave(file.path(out_dir, "fig_stat3_cv_metrics.png"), p, width = 9, height = 5, dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig_stat3_cv_metrics.pdf"), p, width = 9, height = 5, bg = "white")
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Construit et exporte la Figure stat3b : matrice de confusion du meilleur modèle de fiabilité.
# cm_df   : data.frame avec les colonnes truth, prediction, n (issu d'un appel à table()).
# out_dir : répertoire de sortie où les figures seront écrites.
# La figure est une heatmap 2D (vraies classes × classes prédites) avec dégradé bleu
# et annotations des comptes dans chaque cellule.
# Les figures sont exportées au format PNG (300 dpi) et PDF dans out_dir :
#   fig_stat3_confusion_matrix_best.png et fig_stat3_confusion_matrix_best.pdf.
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
      y = "Vérité"
    ) +
    theme_minimal(base_size = 11) +
    theme(plot.title = element_text(face = "bold"), panel.grid = element_blank())

  ggsave(file.path(out_dir, "fig_stat3_confusion_matrix_best.png"), p, width = 7, height = 6, dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig_stat3_confusion_matrix_best.pdf"), p, width = 7, height = 6, bg = "white")
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Construit et exporte la Figure stat3c : distribution des probabilités de confiance du meilleur modèle.
# pred_df : data.frame avec les colonnes max_proba et predicted, issu de objective3_model_selection().
# out_dir : répertoire de sortie où les figures seront écrites.
# La figure est un histogramme de la probabilité maximale prédite par observation,
# coloré par classe prédite, permettant d'évaluer la calibration et la confiance du modèle.
# Les observations hors plage [0, 1] ou non finies sont filtrées avant l'affichage.
# Les figures sont exportées au format PNG (300 dpi) et PDF dans out_dir :
#   fig_stat3_predicted_probabilities_best.png et fig_stat3_predicted_probabilities_best.pdf.
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
      fill = "Classe prédite"
    ) +
    theme_minimal(base_size = 11) +
    theme(plot.title = element_text(face = "bold"))

  ggsave(file.path(out_dir, "fig_stat3_predicted_probabilities_best.png"), p, width = 9, height = 5, dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig_stat3_predicted_probabilities_best.pdf"), p, width = 9, height = 5, bg = "white")
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Entraîne et prédit avec un modèle de classification de la fiabilité de détermination.
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
# Objectif 3 — Sélection du meilleur modèle de prédiction de la fiabilité par validation croisée.
# df_rel  : data.frame préparé par prepare_reliability_data().
# out_dir : répertoire de sortie où les exports seront écrits.
# Exécute une validation croisée k=5 folds pour 3 candidats :
#   "polr" (régression ordinale), "multinom" (multinomiale), "baseline_majority" (naïve).
# Pour chaque fold, appelle fit_predict_reliability_model() et calcule accuracy, macro-F1 et log-loss.
# Si les données sont insuffisantes (< 20 lignes ou < 2 classes), retourne un résultat vide immédiatement.
# Le meilleur modèle est sélectionné selon le macro-F1 moyen (critère principal), puis l'accuracy.
# Exporte les CSV : obj3_model_metrics.csv, stat_obj3_best_model_predictions.csv,
#   stat_obj3_best_model_confusion_matrix.csv, stat_obj3_best_model_coefficients.csv.
# Génère les Figures stat3a/b/c via build_o3_cv_metrics_plot(), build_o3_confusion_plot(),
#   build_o3_probabilities_plot().
# Retourne une liste avec :
#   - metrics : data.frame des métriques par modèle avec indicateur de sélection.
#   - best    : nom du meilleur modèle sélectionné.
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
# Objectif 4 — Test d'inférence statistique sur la dépendance fiabilité × site.
# df_rel  : data.frame préparé par prepare_reliability_data().
# out_dir : répertoire de sortie où les exports seront écrits.
# Construit le tableau de contingence fiabilité × site_label, puis sélectionne
# automatiquement le test statistique adapté :
#   - Chi-2 si toutes les cellules attendues ≥ 5.
#   - Test exact de Fisher si des cellules attendues < 5 existent.
#   - Fisher avec simulation Monte-Carlo (B=10000) si Fisher exact échoue (tableau trop grand).
#   - Fallback Chi-2 si tous les tests échouent.
# La métrique primaire rapportée est -log10(p_value) pour faciliter les comparaisons.
# Exporte le CSV : stat_obj4_inference_tests.csv.
# Génère la Figure stat4 (heatmap site × fiabilité avec résultat du test, PNG + PDF) :
#   fig_stat4_site_reliability_heatmap.png et .pdf.
# Retourne une liste avec :
#   - metrics : data.frame avec le test retenu, -log10(p) et la p-value brute.
#   - best    : nom du test retenu.
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
      y = "Site"
    ) +
    theme_minimal(base_size = 11) +
    theme(plot.title = element_text(face = "bold"), panel.grid = element_blank())

  ggsave(file.path(out_dir, "fig_stat4_site_reliability_heatmap.png"), p, width = 10, height = 7, dpi = 300, bg = "white")
  ggsave(file.path(out_dir, "fig_stat4_site_reliability_heatmap.pdf"), p, width = 10, height = 7, bg = "white")

  list(metrics = infer_df, best = test_name)
}

# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Orchestrateur du module fiabilité : exécute les objectifs 1 à 4 en séquence.
# df_clean     : data.frame nettoyé issu de read_input_data().
# cols         : liste des noms de colonnes métier (issues de cfg$columns).
# site_metrics : liste retournée par build_site_level_metrics() (utilisée par objectif 2).
# out_dir      : répertoire de sortie commun où tous les CSV et figures seront écrits.
# Appelle dans l'ordre :
#   1) prepare_reliability_data() pour normaliser les niveaux de fiabilité.
#   2) objective1_descriptive()    : distribution des niveaux.
#   3) objective2_weighting()      : sélection du schéma de pondération optimal.
#   4) objective3_model_selection(): sélection du meilleur modèle prédictif.
#   5) objective4_inference()      : test d'association fiabilité × site.
# Exporte un CSV de synthèse : stat_model_selection_summary.csv.
# Retourne une liste avec :
#   - summary : data.frame récapitulatif des 4 objectifs (objectif, meilleur candidat, métriques).
#   - details : liste nommée des résultats détaillés de chaque objectif (o1, o2, o3, o4).
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
# Exporte l'ensemble des résultats du pipeline sous forme de fichiers CSV.
# df_clean     : data.frame nettoyé issu de read_input_data().
# summaries    : liste retournée par calc_summaries() (résumés par site, famille, espèce, date, fiabilité).
# site_metrics : liste retournée par build_site_level_metrics() (potentiel, patrimonial, chegd, combined).
# out_dir      : répertoire de sortie où tous les CSV seront écrits.
# cols         : liste des noms de colonnes métier (utilisée pour les indicateurs globaux).
# Exporte les fichiers CSV suivants dans out_dir :
#   - donnees_brutes_nettoyees.csv, resume_par_site/famille/espece/date.csv
#   - resume_fiabilite_determination.csv, niveaux_fiabilite_rencontres.csv
#   - potentiel_fongique_par_site.csv, indice_patrimonial_par_site.csv
#   - gradient_chegd_par_site.csv, indice_representativite_ir_par_site.csv
#   - synthese_evaluation_par_site.csv
#   - resume_global.csv : indicateurs de contrôle qualité globaux (counts, cohérence CHEGD, IR moyen).
# Le contrôle QA vérifie la cohérence entre la somme des gradients par visite et chegd_total.
# Retourne invisiblement NULL ; tous les fichiers sont écrits en encodage UTF-8 sans BOM.
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
# Point d'entrée principal du pipeline d'évaluation fongique.
# Aucun argument : toute la configuration est issue de get_embedded_config().
# Exécute les étapes suivantes dans l'ordre :
#   1) Résolution des chemins (répertoire script, config, fichier d'entrée, répertoire de sortie).
#   2) Initialisation du système de logging (setup_logging, log_header).
#   3) Lecture et nettoyage des données (read_input_data, ensure_required_columns,
#      to_date_safe, to_numeric_safe).
#   4) Résumés descriptifs (calc_summaries) et métriques par site (build_site_level_metrics).
#   5) Génération des 7 figures (build_site_dashboard à build_ir_by_visit_plot).
#   6) Module fiabilité objectifs 1-4 (run_reliability_objectives).
#   7) Export des résultats CSV (write_outputs).
#   8) Récapitulatif des fichiers générés dans le log (log_footer).
# Appelée via tryCatch() en bas de fichier pour capturer toute erreur fatale,
# l'enregistrer dans le log et propager l'exception avec stop().
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
main <- function() {
  # Démarrage et configuration du pipeline d'évaluation fongique.
  script_dir <- get_script_dir()
  base_dir <- if (basename(script_dir) == "scripts") dirname(script_dir) else script_dir
  config_source <- "Configuration intégrée (get_embedded_config)"

  cfg <- get_embedded_config()
  cfg$input_file <- resolve_input_file(cfg$input_file, base_dir)
  cfg$output_dir <- resolve_path_from_base(cfg$output_dir, base_dir)

  # Créer répertoire de sortie si nécessaire et construire le chemin complet avec préfixe.
  if (!dir.exists(cfg$output_dir)) { 
    dir.create(cfg$output_dir, recursive = TRUE)
  }
  # Construire le répertoire de sortie final avec le préfixe spécifié dans la configuration.
  out_dir <- build_output_dir(cfg$output_dir, cfg$output_prefix)

  # Initialiser logging dans /logs à la racine du projet et enregistrer l'en-tête avec la source de configuration et le fichier d'entrée.
  setup_logging(base_dir, cfg$output_prefix)
  log_header(config_source, cfg$input_file)
  log_info(paste0("Fichier d'entrée résolu : ", cfg$input_file))
  log_info(paste0("Répertoire de sortie : ", out_dir))

  ext <- tolower(tools::file_ext(cfg$input_file))
  if (ext == "csv") {
    log_info("Format CSV détecté, le paramètre de feuille est ignoré")
  }

  # Lecture et traitement des données d'entrée.
  log_section("Lecture et traitement des données d'entrée")
  log_info(paste0("Lecture du fichier : ", cfg$input_file))
  raw <- read_input_data(cfg$input_file, cfg$input_sheet)
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
    cfg$input_file,
    cfg$reference_workbook,
    cfg$use_reference_overrides
  )
  log_info("Métriques par site calculées")

  # Générer les graphiques et les figures pour le rapport.
  # Les figures sont enregistrées dans le répertoire de sortie et un message de log est affiché pour chaque figure générée.
  # Les figures incluent le tableau de bord des sites, le positionnement écologique, la décomposition du potentiel, le CHEGD par visite, la carte thermique des classes, 
  # la distribution des niveaux de fiabilité et l'indice de représentativité (IR).
  # Les figures sont générées à partir des métriques calculées précédemment et sont destinées à fournir une visualisation claire des données et des résultats.
  # Les figures sont enregistrées au format PNG et PDF pour une utilisation flexible dans les rapports et les présentations.
  # Les messages de log permettent de suivre l'avancement de la génération des figures et de vérifier que toutes les figures ont été créées avec succès.
  # Les figures sont essentielles pour l'analyse visuelle des données et pour communiquer les résultats de manière efficace aux parties prenantes.
  log_section("Génération des résultats graphiques et des figures")
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

  # Objectifs de fiabilité (1-4) : descriptif, pondération, modèles, inférence.
  # Chaque objectif est exécuté séquentiellement, et les résultats sont enregistrés dans le répertoire de sortie.
  # Les meilleurs candidats pour chaque objectif sont affichés dans le log pour référence.
  # Les résultats finaux sont exportés sous forme de fichiers CSV, et un résumé des fichiers générés est affiché dans le log.
  # Les objectifs de fiabilité permettent d'évaluer la qualité des données et de fournir des indicateurs pour la prise de décision.
  log_section("Objectifs de fiabilité (1-4)")
  reliability_objectives <- run_reliability_objectives(df_clean, cols, site_metrics, out_dir)
  if (!is.null(reliability_objectives$summary)) {
    log_info("Objectifs de fiabilité terminés - Meilleurs candidats :")
    for (i in seq_len(nrow(reliability_objectives$summary))) {
      r <- reliability_objectives$summary[i, ]
      log_info(paste0("  - ", r$objectif, ": ", r$candidat))
    }
  }

  # Exporter les résultats finaux et les fichiers CSV.
  # Cela inclut les données nettoyées, les résumés par site/famille/espèce/date, les métriques de fiabilité et les synthèses par site.
  # Les fichiers CSV sont écrits dans le répertoire de sortie spécifié, et un résumé des fichiers générés est affiché dans le log pour référence.
  log_section("Export des résultats finaux et des fichiers CSV")
  write_outputs(df_clean, summaries, site_metrics, out_dir, cols)
  log_info("Tous les fichiers CSV ont été exportés")

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