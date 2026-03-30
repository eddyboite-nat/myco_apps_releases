# Document de Conception Technique

## `Inventaires_completude_representativite.R`

---

**Projet** : Projet hôte / Inventaires fongiques  
**Auteur** : Eddy Boite  
**Version script** : 1.4 (selon en-tête du script)  
**Date doc** : Mars 2026  
**Type de document** : Spécification technique (alignée code source)

---

## Table des matières

1.  [Vue d'ensemble](#1-vue-densemble)
2.  [Architecture du système](#2-architecture-du-syst%C3%A8me)
3.  [Analyses de complétude](#3-analyses-de-compl%C3%A9tude)
4.  [Analyses de représentativité](#4-analyses-de-repr%C3%A9sentativit%C3%A9)
5.  [Configuration réelle du script](#5-configuration-r%C3%A9elle-du-script)
6.  [Portabilité et nom du projet](#6-portabilit%C3%A9-et-nom-du-projet)
7.  [Journalisation et traçabilité](#7-journalisation-et-tra%C3%A7abilit%C3%A9)
8.  [Validation CSV et conformité](#8-validation-csv-et-conformit%C3%A9)
9.  [Rapports et livrables](#9-rapports-et-livrables)
10.  [Flux de traitement](#9-flux-de-traitement)
11.  [Structures de données (exhaustif)](#10-structures-de-donn%C3%A9es-exhaustif)
12.  [Métriques et interprétation](#11-m%C3%A9triques-et-interpr%C3%A9tation)
13.  [Versioning et maintenance](#12-versioning-et-maintenance)
14.  [Exécution, dépendances et limites](#13-ex%C3%A9cution-d%C3%A9pendances-et-limites)
15.  [Annexes](#14-annexes)

---

## 1\. Vue d'ensemble

### 1.1 Objectif

Le script `scripts/Inventaires_completude_representativite.R` automatise l'analyse de complétude et de représentativité des inventaires fongiques, par site et globalement.

Il produit notamment :

*   la courbe temps-espèces,
*   l'ajustement linéaire/hyperbolique (si possible),
*   l'indice `TEE` (taux d'espèces exceptionnelles) et `Ir = 1 - TEE`,
*   les fréquences d'occurrence par espèce,
*   les métriques de pertinence scientifique,
*   les comparaisons inter-sites.

### 1.2 Données manipulées (clarification importante)

Le script utilise la colonne taxonomique `espece`.

*   Clés d'analyse principales : `site`, `date`, `visite_id`, `espece`.
*   Clé de visite : `date + visite_id` (et `site` en multi-sites).

### 1.3 Entrées / sorties de haut niveau

**Entrée principale** :

*   `data/observations.csv` (ou `observations.tsv`, `observations.txt`)

**Sorties globales** :

*   `results/ICR_donnees_preparees.csv`
*   `results/ICR_resume_tous_sites.csv`
*   `results/ICR_metrics_pertinence_tous_sites.csv`
*   graphiques globaux `results/ICR_*.png`

**Sorties par site** (`results/<site>/`) :

*   `ICR_01` à `ICR_07` en CSV et PNG selon disponibilité des données/modèles.

---

## 2\. Architecture du système

### 2.1 Modules fonctionnels

Le script suit la chaîne suivante :

1.  Initialisation (options, packages, constantes)
2.  Validation configuration
3.  Résolution du fichier d'entrée
4.  Lecture auto-délimiteur
5.  Préparation/validation des données (`prepare_data`)
6.  Analyse par site (`analyze_site`)
7.  Consolidation globale (`run_analysis`)
8.  Export CSV/PNG + manifeste de sorties

### 2.2 Fonctions clés

*   `read_delim_auto()` : détection automatique du séparateur (`,` `;` `TAB`) + récupération des problèmes de parsing.
*   `build_csv_colspec()` : schéma de lecture CSV (colonnes attendues en `character`).
*   `audit_csv_conformity()` : audit de conformité (colonnes requises, colonnes extra, parsing).
*   `export_csv_conformity_report()` : export des rapports `ICR_00_*`.
*   `prepare_data()` : validation stricte + déduplication.
*   `calc_cumulative_metrics()` : richesse par visite et cumul.
*   `calc_tee_ir()` : calcul dynamique de `TEE`/`Ir`.
*   `calc_species_frequency()` : fréquence temporelle par espèce.
*   `calc_spatial_occupancy()` : occupation spatiale (si `placette`).
*   `fit_linear_model()` / `fit_hyperbolic_model()` : modélisation de la courbe.
*   `calc_scientific_metrics()` : score synthétique et métriques de robustesse.
*   `log_output_manifest()` : contrôle d'intégrité des livrables.

---

## 3\. Analyses de complétude

### 3.1 Richesse observée et cumulée

Par visite, le script calcule :

*   `nb_especes_trouvees`
*   `nb_nouvelles`
*   `nb_cumule`

Sorties :

*   `ICR_01_courbe_temps_especes.csv`
*   `ICR_01_richesse_par_visite_et_cumul.png`

### 3.2 Complétude observée / asymptote

Quand l'ajustement hyperbolique est disponible :

**Principe** : la complétude correspond au rapport entre la richesse observée et l'asymptote estimée.

avec `S_asymptote = a` (paramètre du modèle hyperbolique).

Conditions d'estimation :

*   `nb_visites >= CONFIG$min_visits_for_model`
*   package optionnel `minpack.lm` installé.

Sorties :

*   `ICR_05_modeles.csv` (si modèle ajusté)
*   `ICR_04_resume_site.csv`
*   `ICR_resume_tous_sites.csv`

### 3.3 Fréquence d'occurrence des espèces

Le script estime :

*   `nb_visites` par espèce,
*   `prop_visites = nb_visites / nb_visites_total`,
*   classe de fréquence via `CONFIG$freq_breaks` + `CONFIG$freq_labels`.

Sorties :

*   `ICR_03_frequence_especes.csv`
*   `ICR_04_histogramme_frequences.png`

### 3.4 Couverture spatiale (optionnelle)

Si `placette` est exploitable :

*   `nb_placettes` par espèce,
*   `prop_placettes`.

Sorties :

*   `ICR_06_occupation_spatiale.csv`
*   `ICR_05_temporel_vs_spatial.png`

---

## 4\. Analyses de représentativité

### 4.1 TEE et indice Ir

À chaque visite :

*   `TEE` = proportion d'espèces observées une seule fois,
*   `Ir = 1 - TEE`.

Sorties :

*   `ICR_02_tee_ir.csv`
*   `ICR_03_tee_ir.png`
*   `ICR_comparaison_ir_sites.png`

### 4.2 Stabilité terminale

Le script calcule :

*   `slope_terminal_cumul` (pente des dernières visites),
*   `tail_novelty_share` (part des nouveautés en fin de série).

Objectif : quantifier la fermeture de l'inventaire.

### 4.3 Cohérence temporelle/spatiale

Si `placette` existe :

*   corrélation de Spearman `spearman_temporal_spatial` entre `prop_visites` et `prop_placettes`,
*   `discordance_rate`.

### 4.4 Score de pertinence scientifique

Le score agrégé `score_pertinence` utilise les pondérations codées dans le script :

*   `Ir final` : 35 %
*   `complétude` : 35 %
*   `stabilité finale` : 20 %
*   `robustesse modèle` : 10 %

Sorties :

*   `ICR_07_metrics_pertinence.csv`
*   `ICR_metrics_pertinence_tous_sites.csv`
*   `ICR_07_metrics_pertinence_dashboard.png`
*   `ICR_metrics_pertinence_heatmap_sites.png`
*   `ICR_metrics_pertinence_score_sites.png`

---

## 5\. Configuration réelle du script

### 5.1 Paramètres runtime (dans le code)

Le script n'utilise pas de `.Renviron` dédié ; la configuration est portée par la liste `CONFIG`.

| Clé CONFIG | Défaut | Rôle |
| --- | --- | --- |
| `input_file` | `data/observations.csv` | Fichier d'entrée |
| `output_dir` | `results/ICR` | Répertoire de sortie |
| `date_format` | `%Y-%m-%d` | Format de parsing des dates |
| `csv_strict_mode` | `TRUE` | Stoppe l'exécution si audit CSV non conforme |
| `csv_allow_extra_cols` | `FALSE` | Autorise ou non les colonnes supplémentaires |
| `csv_required_cols` | `c("site","date","visite_id","espece")` | Colonnes obligatoires attendues |
| `csv_optional_cols` | `c("placette")` | Colonnes optionnelles autorisées |
| `freq_breaks` | `c(0,0.10,0.25,0.50,0.75,1.00)` | Bornes de classes de fréquence |
| `freq_labels` | `exceptionnelle`…`constante` | Labels des classes |
| `make_ca` | `TRUE` | Active CA/AFC (si `vegan`) |
| `min_visits_for_model` | `5` | Seuil mini pour modélisation |
| `width`,`height`,`dpi` | `10`,`6`,`300` | Paramètres d'export graphique |

### 5.2 Flags d'exécution

| Variable/flag | Défaut | Description |
| --- | --- | --- |
| `DEBUG_MODE` | `FALSE` | Verbosité et affichage des avertissements |
| `BENCHMARK_MODE` | `FALSE` | Chronométrage des calculs |
| `CLEAN_ENVIRONMENT` | `FALSE` | Nettoyage environnement (usage expert) |
| `INVENTAIRES_AUTO_RUN` (env) | `TRUE` | Exécute automatiquement `run_analysis()` |

---

## 6\. Portabilité et nom du projet

### 6.1 Principe

Le script est **indépendant du nom du dépôt** : aucun identifiant de projet (ex. `statistics`) n'est requis dans le code d'analyse.

La portabilité repose sur :

*   des chemins relatifs (`data/`, `scripts/`, `results/`),
*   la résolution dynamique du dossier projet (`PROJECT_DIR`),
*   des variables d'environnement pour adapter les chemins/fomat de date.

### 6.2 Variables d'environnement à utiliser

Le nom du projet se configure indirectement en adaptant les chemins à votre repo :

*   `INVENTAIRES_INPUT_FILE` (ex. `data/observations_public.csv`)
*   `INVENTAIRES_OUTPUT_DIR` (ex. `results/public_release`)
*   `INVENTAIRES_DATE_FORMAT` (ex. `%d/%m/%Y` si nécessaire)
*   `INVENTAIRES_CSV_STRICT` (mode strict conformité CSV)
*   `INVENTAIRES_CSV_ALLOW_EXTRA_COLS` (tolérance des colonnes additionnelles)

Ainsi, un même script peut être déplacé d'un projet à l'autre sans modification du code source.

### 6.3 Recommandation de documentation

Pour la diffusion, employer systématiquement un placeholder explicite :

*   `<nom_du_projet>` pour l'arborescence,
*   `<nom_du_projet>.Rproj` pour le fichier RStudio,
*   chemins d'exécution relatifs (`Rscript scripts/...`).

---

## 7\. Journalisation et traçabilité

### 6.1 Mécanisme réel

La journalisation est effectuée via les fonctions :

*   `log_info()`
*   `log_debug()`
*   `log_warning()`

La sortie se fait sur la **console standard** ; ce script n'implémente pas de système de fichiers de logs dédié.

### 6.2 Manifeste de sorties

En fin d'exécution, `log_output_manifest()` publie un état des livrables :

*   `OK`
*   `OPTIONNEL_NON_GENERE`
*   `MANQUANT`

Ce manifeste sert de contrôle qualité de production.

---

## 8\. Validation CSV et conformité

### 8.1 Contrôles appliqués

Avant `prepare_data()`, le script exécute un audit de conformité :

1.  vérification des colonnes obligatoires,
2.  détection de colonnes supplémentaires (selon `csv_allow_extra_cols`),
3.  comptage des problèmes de parsing `readr::problems()`.

### 8.2 Mode strict

Si `csv_strict_mode = TRUE` (défaut), l'exécution est interrompue en cas de non-conformité.

### 8.3 Rapports d'audit

*   `results/ICR/ICR_00_csv_conformite_report.csv` (toujours)
*   `results/ICR/ICR_00_csv_conformite_problems.csv` (si anomalies parsing)

## 9\. Rapports et livrables

### 7.1 CSV globaux (toujours)

*   `results/ICR/ICR_00_csv_conformite_report.csv`
*   `results/ICR_donnees_preparees.csv`
*   `results/ICR_resume_tous_sites.csv`
*   `results/ICR_metrics_pertinence_tous_sites.csv`

### 7.1 bis CSV globaux (conditionnels)

*   `results/ICR/ICR_00_csv_conformite_problems.csv` (si parsing anormal)

### 7.2 CSV par site (`results/<site>/`)

*   `ICR_01_courbe_temps_especes.csv`
*   `ICR_02_tee_ir.csv`
*   `ICR_03_frequence_especes.csv`
*   `ICR_04_resume_site.csv`
*   `ICR_05_modeles.csv` (si modèle)
*   `ICR_06_occupation_spatiale.csv` (si `placette`)
*   `ICR_07_metrics_pertinence.csv`

### 7.3 Graphiques globaux

*   `ICR_comparaison_completude_sites.png`
*   `ICR_comparaison_ir_sites.png`
*   `ICR_metrics_pertinence_heatmap_sites.png`
*   `ICR_metrics_pertinence_score_sites.png`

### 7.4 Graphiques par site

*   `ICR_01_richesse_par_visite_et_cumul.png`
*   `ICR_02_courbe_temps_especes_hyperbole.png`
*   `ICR_03_tee_ir.png`
*   `ICR_04_histogramme_frequences.png`
*   `ICR_05_temporel_vs_spatial.png` (si `placette`)
*   `ICR_06_CA_placettes_especes.png` (si `make_ca` + `vegan`)
*   `ICR_07_metrics_pertinence_dashboard.png`

---

## 9\. Flux de traitement

```
run_analysis(CONFIG)
  ├─ validate_config()
  ├─ resolve_input_file()
  ├─ read_delim_auto()
  ├─ audit_csv_conformity()
  ├─ export_csv_conformity_report()
  ├─ stop si non conforme en mode strict
  ├─ prepare_data()
  ├─ write ICR_donnees_preparees.csv
  ├─ for each site:
  │    └─ analyze_site()
  │         ├─ calc_cumulative_metrics()
  │         ├─ calc_tee_ir()
  │         ├─ calc_species_frequency()
  │         ├─ calc_spatial_occupancy() [optionnel]
  │         ├─ fit models [conditionnel]
  │         ├─ calc_scientific_metrics()
  │         ├─ export CSV site
  │         └─ export PNG site
  ├─ consolidation multi-sites (CSV globaux)
  ├─ export graphiques globaux
  └─ log_output_manifest()
```

---

## 10\. Structures de données (exhaustif)

### 9.1 Entrée

| Fichier | Colonnes obligatoires | Colonnes optionnelles |
| --- | --- | --- |
| `data/observations.csv` (ou `.tsv`, `.txt`) | `site`, `date`, `visite_id`, `espece` | `placette` |

### 9.2 Règles de validation d'entrée

1.  Colonnes obligatoires présentes.
2.  Colonnes supplémentaires refusées par défaut (configurable).
3.  Audit des problèmes de parsing (`readr::problems()`).
4.  Parsing date selon `CONFIG$date_format`.
5.  `site`, `visite_id`, `espece` non vides.
6.  Déduplication sur (`site`, `placette`, `date`, `visite_id`, `espece`).

### 9.3 Colonnes de sortie principales

#### `ICR_01_courbe_temps_especes.csv`

*   `visite_index`, `visite_id`, `date`, `nb_especes_trouvees`, `nb_nouvelles`, `nb_cumule`

#### `ICR_02_tee_ir.csv`

*   `visite_index`, `visite_id`, `date`, `nb_total`, `nb_esp_1fois`, `TEE`, `Ir`

#### `ICR_03_frequence_especes.csv`

*   `espece`, `nb_visites`, `prop_visites`, `classe_frequence`

#### `ICR_04_resume_site.csv`

*   `site`, `nb_observations`, `nb_visites`, `nb_especes_observees`, `nb_placettes`, `asymptote_hyperbolique`, `completude_obs_sur_asymptote`, `tee_final`, `ir_final`

#### `ICR_05_modeles.csv` (conditionnel)

*   `modele`, `equation`, `r2`, `asymptote_y`, `asymptote_x`

#### `ICR_06_occupation_spatiale.csv` (conditionnel)

*   `espece`, `nb_placettes`, `prop_placettes`

#### `ICR_07_metrics_pertinence.csv`

*   `site`, `nb_visites`, `terminal_window_k`, `tee_final`, `ir_final`, `completude`, `r2_lineaire`, `r2_hyperbolique`, `slope_terminal_cumul`, `tail_novelty_share`, `spearman_temporal_spatial`, `discordance_rate`, `score_pertinence`, `class_ir`, `class_completude`

---

## 11\. Métriques et interprétation

### 10.1 Seuils de classes implémentés

`class_ir` :

*   `< 0.60` : `faible`
*   `[0.60, 0.80)` : `moyenne`
*   `>= 0.80` : `bonne`

`class_completude` :

*   `< 0.70` : `insuffisante`
*   `[0.70, 0.90)` : `intermédiaire`
*   `>= 0.90` : `avancée`

### 10.2 Lecture recommandée des indicateurs

*   `Ir final` élevé + `tail_novelty_share` faible : inventaire bien stabilisé.
*   `completude_obs_sur_asymptote` proche de 1 : effort proche de l'asymptote estimée.
*   `spearman_temporal_spatial` élevé et `discordance_rate` faible : cohérence temporelle/spatiale satisfaisante.

---

## 12\. Versioning et maintenance

### 11.1 Version du script

La version est portée dans l'en-tête du fichier script (`Version : 1.4`).

### 11.2 Maintenance recommandée

*   maintenir la cohérence entre `README.md` et ce document ;
*   mettre à jour cette doc si les noms de sorties `ICR_*` évoluent ;
*   conserver les seuils de classes synchronisés avec `calc_scientific_metrics()`.

---

## 13\. Exécution, dépendances et limites

### 12.1 Dépendances

**Requises** :

*   `dplyr`, `tidyr`, `ggplot2`, `purrr`, `readr`, `stringr`, `forcats`, `tibble`, `scales`, `gridExtra`

**Optionnelles** :

*   `minpack.lm` (modèle hyperbolique)
*   `vegan` (CA/AFC)

### 12.2 Exécution

```
Rscript scripts/Inventaires_completude_representativite.R
```

Désactiver l'auto-exécution :

```
INVENTAIRES_AUTO_RUN=FALSE Rscript scripts/Inventaires_completude_representativite.R
```

### 12.3 Limites connues

*   sans `placette` : pas d'analyse spatiale dédiée ;
*   sans `minpack.lm` : complétude asymptotique potentiellement `NA` ;
*   dates non conformes à `CONFIG$date_format` : arrêt de l'exécution ;
*   en mode strict, un CSV mal formé est bloquant (par design qualité) ;
*   faible nombre de visites : qualité des modèles limitée.

---

## 14\. Annexes

### 13.1 Glossaire

| Terme | Définition |
| --- | --- |
| Visite distincte | Couple `date + visite_id` (et `site` en multi-sites) |
| TEE | Taux d'espèces observées une seule fois |
| Ir | Indice de représentativité (`1 - TEE`) |
| Complétude | Ratio richesse observée / asymptote hyperbolique |
| Occupation spatiale | Proportion de placettes où l'espèce est observée |
| Score de pertinence | Score synthétique pondéré multi-indicateurs |

### 13.2 Résumé ultra-compact (1 tableau)

| Type | Fichier | Condition | Finalité |
| --- | --- | --- | --- |
| Entrée | `data/observations.csv` | Obligatoire | Source des observations |
| CSV global | `ICR_donnees_preparees.csv` | Toujours | Base nettoyée |
| CSV global | `ICR_resume_tous_sites.csv` | Toujours | Synthèse par site |
| CSV global | `ICR_metrics_pertinence_tous_sites.csv` | Toujours | Métriques consolidées |
| CSV site | `ICR_01` à `ICR_07` (`*.csv`) | Selon cas | Détails analytiques par site |
| PNG global | `ICR_comparaison_*.png` | Toujours | Comparaisons inter-sites |
| PNG site | `ICR_01` à `ICR_07` (`*.png`) | Selon cas | Visualisations locales |