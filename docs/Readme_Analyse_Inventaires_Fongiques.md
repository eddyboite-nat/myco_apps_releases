# Inventaires Fongiques – Complétude & Représentativité

[![R](https://img.shields.io/badge/R-%3E%3D4.0-blue.svg)](https://www.r-project.org/)  
[![Script](https://img.shields.io/badge/Script-Inventaires__completude__representativite.R-6f42c1.svg)](../scripts/Inventaires_completude_representativite.R)  
[![Domain](https://img.shields.io/badge/Domain-Mycologie%20%7C%20%C3%89cologie-green.svg)](../README.md)  
[![Status](https://img.shields.io/badge/Status-Op%C3%A9rationnel-brightgreen.svg)](#-quick-start)

Pipeline R pour automatiser l’analyse de la **complétude d’inventaires fongiques** et de leur **représentativité** (Taux d’Espèces Exceptionnelles, **TEE** / Indice de représentativité, **Ir**), avec sorties tabulaires et graphiques prêtes à exploiter.

**Auteur :** Eddy Boite  
**Projet :** `nom_du_projet` (portable)  
**Dernière mise à jour :** 22 Mars 2026

---

## 📖 À Propos

Ce document décrit l’utilisation du script :

*   `scripts/Inventaires_completude_representativite.R`

Le script produit automatiquement, par site :

1.  Courbe temps-espèces
2.  Ajustement linéaire et hyperbolique (si possible)
3.  Estimation d’asymptote (richesse théorique)
4.  Taux d’espèces exceptionnelles (TEE)
5.  Indice de représentativité $Ir = 1 - TEE$
6.  Fréquence des espèces par visite
7.  Occupation spatiale (si `placette` disponible)
8.  Analyse Factorielle des Correspondances (**AFC**, aussi appelée Correspondence Analysis, **CA**) simple (si package `vegan` disponible)
9.  **Métriques de pertinence scientifique** : stabilité, robustesse, cohérence spatiotemporelle et score agrégé, avec visualisations dédiées

En fin d'exécution, un **manifeste automatique** journalise l'état de chaque fichier attendu (OK / MANQUANT / OPTIONNEL\_NON\_GENERE).

## 📋 Table des Matières

*   [Quick Start](#-quick-start)
*   [Structure du projet](#-structure-du-projet)
*   [Configurer le nom du projet (portabilité)](#-configurer-le-nom-du-projet-portabilit%C3%A9)
*   [Structure attendue des données](#-structure-attendue-des-donn%C3%A9es)
*   [Validation CSV stricte (robustesse)](#-validation-csv-stricte-robustesse)
*   [Sorties générées](#-sorties-g%C3%A9n%C3%A9r%C3%A9es)
*   [Installation et dépendances](#-installation-et-d%C3%A9pendances)
*   [Configuration](#-configuration)
*   [Interprétation des indicateurs](#-interpr%C3%A9tation-des-indicateurs)
*   [Glossaire](#-glossaire)
*   [Dépannage (Foire Aux Questions, FAQ)](#-d%C3%A9pannage-faq)

---

## 📁 Structure du projet

Le script s'inscrit dans un projet R standard dont voici une structure type :

```
<nom_du_projet>/
├── data/
│   ├── observations.csv                 # Données d'entrée ICR (à personnaliser)
│   └── mais.txt
├── docs/
│   ├── Readme_Analyse_Inventaires_Fongiques.md
│   ├── rapport_inventaires_fongiques.qmd          # Rapport Quarto
├── results/
│   ├── ICR_donnees_preparees.csv
│   ├── ICR_00_csv_conformite_report.csv
│   ├── ICR_00_csv_conformite_problems.csv
│   ├── ICR_resume_tous_sites.csv
│   ├── ICR_metrics_pertinence_tous_sites.csv
│   ├── ICR_comparaison_completude_sites.png
│   ├── ICR_comparaison_ir_sites.png
│   ├── ICR_metrics_pertinence_heatmap_sites.png   # Heatmap métriques multi-sites
│   ├── ICR_metrics_pertinence_score_sites.png     # Classement global pertinence
│   └── <site>/                          # Un sous-dossier par site
│       ├── ICR_01_courbe_temps_especes.csv
│       ├── ICR_02_tee_ir.csv
│       ├── ICR_03_frequence_especes.csv
│       ├── ICR_04_resume_site.csv
│       ├── ICR_05_modeles.csv           # Si modèles ajustés
│       ├── ICR_06_occupation_spatiale.csv  # Si placette disponible
│       ├── ICR_07_metrics_pertinence.csv
│       ├── ICR_01_richesse_par_visite_et_cumul.png
│       ├── ICR_02_courbe_temps_especes_hyperbole.png
│       ├── ICR_03_tee_ir.png
│       ├── ICR_04_histogramme_frequences.png
│       ├── ICR_05_temporel_vs_spatial.png
│       ├── ICR_06_CA_placettes_especes.png
│       └── ICR_07_metrics_pertinence_dashboard.png  # Dashboard métriques site
├── scripts/
│   └── Inventaires_completude_representativite.R  # ← Script principal (v1.4 Phase 4)
├── tests/
└── <nom_du_projet>.Rproj
```

> **Convention de nommage :** tous les fichiers générés par ce script sont préfixés `ICR_` pour les distinguer des sorties des autres scripts du projet.

---

## 🏷️ Configurer le nom du projet (portabilité)

Ce document est conçu pour être **copié tel quel** dans un autre dépôt.

### Ce qui dépend du nom du projet

Le script n'utilise **pas** le nom du dépôt dans son code métier. Le « nom de projet » intervient surtout pour :

*   l'affichage documentaire (`<nom_du_projet>`),
*   le nom du fichier RStudio (`<nom_du_projet>.Rproj`),
*   l'organisation de vos dossiers dans votre repo.

### Procédure recommandée (2 minutes)

1.  Remplacez les placeholders `<nom_du_projet>` par votre vrai nom de dépôt (ex. `inventaires_fongiques_public`).
2.  Si vous utilisez RStudio, renommez le fichier projet en conséquence :
    *   `<nom_du_projet>.Rproj`
3.  Conservez la structure relative standard : `data/`, `scripts/`, `results/`, `docs/`.

### Configuration sans modifier le script

Le script supporte des variables d'environnement pour s'adapter à votre projet :

*   `INVENTAIRES_INPUT_FILE` : chemin d'entrée (défaut : `data/observations.csv`)
*   `INVENTAIRES_OUTPUT_DIR` : dossier de sortie (défaut : `results/ICR`)
*   `INVENTAIRES_DATE_FORMAT` : format de date (défaut : `%Y-%m-%d`)

Exemple d'usage portable :

*   entrée personnalisée : `data/observations_public.csv`
*   sorties personnalisées : `results/public_release`
*   même script : `scripts/Inventaires_completude_representativite.R`

### Bonnes pratiques pour diffusion publique

*   Évitez les chemins absolus locaux (`/Users/...`).
*   Gardez uniquement des chemins relatifs dans les docs et scripts.
*   Vérifiez que vos noms de dossiers ne révèlent pas d'information interne.

---

## 🚀 Quick Start

### 1) Préparer les données

Placer un fichier d’observations dans `data/` avec le nom recommandé :

*   `data/observations.csv`

> Le script accepte aussi `observations.txt` ou `observations.tsv` (**TSV** = Tab-Separated Values, valeurs séparées par tabulation ; détection automatique du séparateur).

### 2) Lancer l’analyse

Depuis la racine du projet (quel que soit son nom) :

*   `Rscript scripts/Inventaires_completude_representativite.R`

### 3) Consulter les résultats

Les sorties sont produites dans :

*   `results/`
*   puis un sous-dossier par site (`results/<site_sanitize>/`)

---

## 📥 Structure attendue des données

### Colonnes obligatoires

*   `site`
*   `date`
*   `visite_id`
*   `espece`

### Colonne optionnelle

*   `placette` (recommandée pour l’analyse spatiale et la CA)

### Format de date

Par défaut : `%Y-%m-%d` (ex. `2026-03-18`).

## 🛡️ Validation CSV stricte (robustesse)

Le script applique un contrôle de conformité CSV avant les analyses :

1.  schéma de colonnes attendu,
2.  contrôle des colonnes supplémentaires,
3.  audit des problèmes de parsing remontés par `readr::problems()`.

### Schéma attendu

*   Colonnes requises (défaut) : `site`, `date`, `visite_id`, `espece`
*   Colonnes optionnelles (défaut) : `placette`

### Comportement en mode strict

Par défaut, `csv_strict_mode = TRUE` (via `INVENTAIRES_CSV_STRICT`).

Dans ce mode, l'exécution s'arrête si :

*   une colonne obligatoire manque,
*   une colonne non autorisée est détectée,
*   un problème de parsing est présent.

### Rapports produits

*   `results/ICR/ICR_00_csv_conformite_report.csv` (toujours)
*   `results/ICR/ICR_00_csv_conformite_problems.csv` (si anomalies de parsing)

### Paramètres et variables d'environnement

*   `CONFIG$csv_strict_mode` ↔ `INVENTAIRES_CSV_STRICT` (défaut `TRUE`)
*   `CONFIG$csv_allow_extra_cols` ↔ `INVENTAIRES_CSV_ALLOW_EXTRA_COLS` (défaut `FALSE`)
*   `CONFIG$csv_required_cols` (défaut : `site,date,visite_id,espece`)
*   `CONFIG$csv_optional_cols` (défaut : `placette`)

### Définition d'une visite distincte (important)

Le script considère une visite unique via la clé :

*   `date + visite_id` (et `site` lorsque plusieurs sites sont analysés)

Cela permet de gérer les jeux de données où un même `visite_id` peut être réutilisé à des dates différentes.

### Exemple minimal

| site | date | visite\_id | espece | placette |
| --- | --- | --- | --- | --- |
| Site\_A | 2026-03-01 | V1 | Amanita muscaria | P1 |
| Site\_A | 2026-03-01 | V1 | Boletus edulis | P2 |
| Site\_A | 2026-03-15 | V2 | Amanita muscaria | P1 |
| Site\_B | 2026-03-08 | V1 | Cantharellus cibarius | P3 |

---

## 📊 Sorties générées

### Vue d'ensemble du pipeline (9 calculs → fichiers)

```
1) Préparation/validation des données
    -> Global CSV : ICR_donnees_preparees.csv
2) Richesse observée et cumulée (courbe temps-espèces)
    -> Site CSV   : <site>/ICR_01_courbe_temps_especes.csv
    -> Site PNG   : <site>/ICR_01_richesse_par_visite_et_cumul.png
3) Ajustements linéaire/hyperbolique (si conditions remplies)
    -> Site CSV   : <site>/ICR_05_modeles.csv
    -> Site PNG   : <site>/ICR_02_courbe_temps_especes_hyperbole.png
4) Asymptote hyperbolique et ratio de complétude
    -> Site CSV   : <site>/ICR_04_resume_site.csv
    -> Global CSV : ICR_resume_tous_sites.csv
    -> Global PNG : ICR_comparaison_completude_sites.png
5) TEE (taux d'espèces exceptionnelles) et indice Ir
    -> Site CSV   : <site>/ICR_02_tee_ir.csv
    -> Site PNG   : <site>/ICR_03_tee_ir.png
    -> Global PNG : ICR_comparaison_ir_sites.png
6) Fréquences d'occurrence des espèces
    -> Site CSV   : <site>/ICR_03_frequence_especes.csv
    -> Site PNG   : <site>/ICR_04_histogramme_frequences.png
7) Occupation spatiale (si placette disponible)
    -> Site CSV   : <site>/ICR_06_occupation_spatiale.csv
    -> Site PNG   : <site>/ICR_05_temporel_vs_spatial.png
8) CA/AFC placettes-espèces (si vegan et données adaptées)
    -> Site PNG   : <site>/ICR_06_CA_placettes_especes.png
9) Métriques de pertinence scientifique (stabilité, robustesse, cohérence)
    -> Site CSV   : <site>/ICR_07_metrics_pertinence.csv
    -> Global CSV : ICR_metrics_pertinence_tous_sites.csv
    -> Site PNG   : <site>/ICR_07_metrics_pertinence_dashboard.png
    -> Global PNG : ICR_metrics_pertinence_heatmap_sites.png
    -> Global PNG : ICR_metrics_pertinence_score_sites.png
```

> En fin d'exécution, un **manifeste automatique** liste l'état de chaque fichier attendu : OK / MANQUANT / OPTIONNEL\_NON\_GENERE.

---

### Sorties globales (`results/`)

| Fichier | Type | Description |
| --- | --- | --- |
| `ICR_00_csv_conformite_report.csv` | CSV | Rapport de conformité CSV (schéma + parsing) avant traitement. |
| `ICR_00_csv_conformite_problems.csv` | CSV | Détail des anomalies de parsing détectées (si présentes). |
| `ICR_donnees_preparees.csv` | CSV | Données nettoyées et standardisées utilisées pour l'analyse. |
| `ICR_resume_tous_sites.csv` | CSV | Synthèse finale multi-sites (complétude, représentativité, etc.). |
| `ICR_metrics_pertinence_tous_sites.csv` | CSV | Métriques de pertinence scientifique agrégées pour tous les sites. |
| `ICR_comparaison_completude_sites.png` | Graphique | Comparaison du ratio de complétude entre sites. |
| `ICR_comparaison_ir_sites.png` | Graphique | Comparaison de l'indice $Ir$ final entre sites. |
| `ICR_metrics_pertinence_heatmap_sites.png` | Graphique | Heatmap comparative des 7 métriques de pertinence pour tous les sites. |
| `ICR_metrics_pertinence_score_sites.png` | Graphique | Classement global des sites par score de pertinence scientifique agrégé. |

### Sorties par site (`results/<site>/`)

| Fichier | Type | Condition | Description |
| --- | --- | --- | --- |
| `ICR_01_courbe_temps_especes.csv` | CSV | Toujours | Données de richesse observée et cumulée par visite. |
| `ICR_02_tee_ir.csv` | CSV | Toujours | Évolution de TEE et de $Ir$ au fil des visites. |
| `ICR_03_frequence_especes.csv` | CSV | Toujours | Fréquences d’occurrence des espèces par visite. |
| `ICR_04_resume_site.csv` | CSV | Toujours | Résumé synthétique du site analysé. |
| `ICR_05_modeles.csv` | CSV | Si modèles ajustés | Paramètres et qualité d’ajustement des modèles. |
| `ICR_06_occupation_spatiale.csv` | CSV | Si `placette` exploitable | Occupation spatiale des espèces par placette. |
| `ICR_01_richesse_par_visite_et_cumul.png` | Graphique | Toujours | Richesse par visite + richesse cumulée. |
| `ICR_02_courbe_temps_especes_hyperbole.png` | Graphique | Toujours (courbe) / hyperbole si modèle dispo | Courbe temps-espèces avec ajustement hyperbolique si possible. |
| `ICR_03_tee_ir.png` | Graphique | Toujours | Lecture conjointe espèces uniques, total et $Ir$. |
| `ICR_04_histogramme_frequences.png` | Graphique | Toujours | Distribution des fréquences d’observation des espèces. |
| `ICR_05_temporel_vs_spatial.png` | Graphique | Si spatial disponible | Relation fréquence temporelle vs occupation spatiale. |
| `ICR_06_CA_placettes_especes.png` | Graphique | Si `vegan` + données adaptées | Ordination AFC/CA placettes-espèces. |
| `ICR_07_metrics_pertinence.csv` | CSV | Toujours | Métriques de pertinence scientifique (15 colonnes : Ir, complétude, R², score…). |
| `ICR_07_metrics_pertinence_dashboard.png` | Graphique | Toujours | Dashboard des 7 métriques de pertinence scientifique du site (stabilité, robustesse, cohérence). |

---

## 🔧 Installation et dépendances

### Packages requis (base)

| Package | Rôle principal |
| --- | --- |
| `dplyr` | Manipulation de données tabulaires (filtre, jointures, agrégations). |
| `tidyr` | Restructuration des données (format long/large). |
| `ggplot2` | Génération des graphiques. |
| `purrr` | Itérations fonctionnelles sur les sites/listes. |
| `readr` | Lecture/écriture rapide des fichiers texte/CSV. |
| `stringr` | Traitements de chaînes de caractères. |
| `forcats` | Gestion des facteurs et de leurs niveaux. |
| `tibble` | Structures tabulaires modernes. |
| `scales` | Mise en forme des axes et échelles graphiques. |
| `gridExtra` | Assemblage de graphiques multi-panneaux (notamment `ICR_03_tee_ir.png`). |

### Packages optionnels

| Package | Utilisation |
| --- | --- |
| `minpack.lm` | Ajustement du modèle hyperbolique (estimation d’asymptote). |
| `vegan` | Ordination AFC/CA (analyse placettes–espèces). |

Le script vérifie les packages requis au démarrage et affiche une commande d'installation explicite si certains sont manquants.

---

## ⚙️ Configuration

La configuration est centralisée dans l’objet `CONFIG` du script.

| Paramètre | Défaut | Description |
| --- | --- | --- |
| `input_file` | `data/observations.csv` | Chemin du fichier d’entrée des observations. |
| `output_dir` | `results/ICR` | Dossier de sortie pour les CSV et graphiques. |
| `date_format` | `%Y-%m-%d` | Format attendu pour parser la colonne `date`. |
| `csv_strict_mode` | `TRUE` | Stoppe l'exécution si le CSV n'est pas conforme. |
| `csv_allow_extra_cols` | `FALSE` | Autorise/refuse les colonnes supplémentaires non prévues. |
| `csv_required_cols` | `c("site","date","visite_id","espece")` | Colonnes obligatoires du schéma CSV. |
| `csv_optional_cols` | `c("placette")` | Colonnes optionnelles autorisées. |
| `make_ca` | `TRUE` | Active l’ordination AFC/CA si les conditions sont réunies. |
| `min_visits_for_model` | `5` | Nombre minimal de visites pour ajuster les modèles de complétude. |
| `width` | `10` | Largeur (en pouces) des graphiques exportés. |
| `height` | `6` | Hauteur (en pouces) des graphiques exportés. |
| `dpi` | `300` | Résolution d’export des graphiques (dots per inch). |

Le script accepte aussi des surcharges via variables d'environnement :

*   `INVENTAIRES_INPUT_FILE`
*   `INVENTAIRES_OUTPUT_DIR`
*   `INVENTAIRES_DATE_FORMAT`
*   `INVENTAIRES_CSV_STRICT`
*   `INVENTAIRES_CSV_ALLOW_EXTRA_COLS`

Si besoin, adapter ces valeurs directement dans :

*   `scripts/Inventaires_completude_representativite.R`

---

## 🧠 Interprétation des indicateurs

### TEE (Taux d’Espèces Exceptionnelles)

*   Définit la proportion d’espèces observées une seule fois.
*   Plus TEE est élevé, plus l’inventaire peut être incomplet.

Lecture pratique :

*   **TEE élevé en fin de suivi** : beaucoup d’espèces n’ont été vues qu’une fois, ce qui suggère un inventaire encore en phase d’accumulation.
*   **TEE qui diminue avec les visites** : signe positif, les espèces “uniques” deviennent progressivement récurrentes.
*   **TEE stable et bas** : communauté mieux couverte, effort d’échantillonnage proche d’un plateau.

Repères empiriques (à contextualiser selon habitat/saison/protocole) :

*   TEE > 0.40 : inventaire souvent **incomplet**
*   0.20 ≤ TEE ≤ 0.40 : inventaire **intermédiaire**
*   TEE \< 0.20 : inventaire généralement **bien consolidé**

### Ir (Indice de représentativité)

$$Ir = 1 - TEE$$

*   Plus $Ir$ est proche de 1, meilleure est la représentativité de l’inventaire.

Lecture pratique :

*   **Ir en hausse au fil des visites** : le protocole capture mieux la diversité réelle du site.
*   **Ir qui plafonne tôt** : effort potentiellement suffisant, sauf si période écologique incomplète.
*   **Ir faible et stagnant** : effort, calendrier ou stratification spatiale à revoir.

Repères empiriques (indicatifs) :

*   Ir \< 0.60 : représentativité faible
*   0.60 ≤ Ir \< 0.80 : représentativité moyenne
*   Ir ≥ 0.80 : représentativité bonne à élevée

### Complétude observée / asymptote

Le script estime une asymptote de richesse (modèle hyperbolique, si disponible) puis calcule un ratio de complétude :

$$\\text{Complétude} = \\frac{S\_{obs}}{S\_{asymptote}}$$

avec :

*   $S\_{obs}$ : richesse observée finale
*   $S\_{asymptote}$ : richesse théorique estimée

Interprétation :

*   **Complétude proche de 1** : l’inventaire approche la richesse théorique attendue.
*   **Complétude intermédiaire** : des espèces restent probablement à détecter.
*   **Complétude faible** : effort insuffisant ou forte hétérogénéité écologique.

Repères utiles :

*   Complétude \< 0.70 : insuffisante pour conclure sur l’exhaustivité
*   0.70–0.90 : progression correcte, inventaire partiel

> 0.90 : inventaire très avancé

---

### Lecture détaillée des diagrammes (le plus important)

#### `ICR_01_richesse_par_visite_et_cumul.png`

Ce graphique combine :

*   **barres** = richesse observée par visite (`nb_especes_trouvees`)
*   **ligne** = richesse cumulée (`nb_cumule`)

Comment lire :

*   **Barres encore hautes + cumul qui monte vite** : inventaire en phase active de découverte.
*   **Barres qui baissent + cumul qui se tasse** : entrée dans une phase de saturation.
*   **Dents de scie marquées** : forte dépendance météo/saison/observateur.

Signal d’alerte :

*   Si les dernières visites apportent encore beaucoup de nouvelles espèces, l’arrêt de l’inventaire peut être prématuré.

#### `ICR_02_courbe_temps_especes_hyperbole.png`

Ce graphique superpose les observations à un ajustement hyperbolique (si `minpack.lm` disponible) et une asymptote.

Comment lire :

*   **Courbe observée proche de la courbe ajustée** : modèle cohérent.
*   **Écart important** : structure de données non compatible avec ce modèle (saisonnalité forte, ruptures d’effort, etc.).
*   **Asymptote nettement au-dessus de la richesse actuelle** : marge de découverte encore importante.

Point clé :

*   Ne pas interpréter l’asymptote comme une “vérité absolue”, mais comme un **repère quantitatif** de complétude.

#### `ICR_03_tee_ir.png`

Ce graphique présente **deux panneaux complémentaires** :

*   panneau haut : nombre d’espèces observées une seule fois (`nb_esp_1fois`),
*   panneau bas : indice de représentativité $Ir$ sur l’échelle $\[0,1\]$ avec seuils visuels.

Comment lire :

*   **Espèces uniques qui ralentissent** : signal de consolidation de l’inventaire.
*   **Ir qui augmente puis se stabilise** : représentativité qui converge.
*   **Ir sous 0.60** : représentativité faible ; **0.60–0.80** : moyenne ; **≥ 0.80** : bonne.

Point de vigilance :

*   Les seuils sont des repères empiriques : toujours interpréter avec le contexte (saison, effort, habitat).

#### `ICR_04_histogramme_frequences.png`

Histogramme du nombre d’espèces selon leur fréquence d’occurrence (nombre de visites où elles sont observées).

Comment lire :

*   **Pic sur les faibles fréquences (1–2 visites)** : communauté riche en espèces rares/occasionnelles.
*   **Répartition plus équilibrée** : noyau d’espèces régulières bien documenté.
*   **Queue vers les fortes fréquences** : présence d’espèces constantes, potentiels bons indicateurs écologiques.

Usages :

*   Ajuster l’effort d’échantillonnage selon l’objectif (détection rareté vs suivi d’espèces communes).

#### `ICR_05_temporel_vs_spatial.png`

Nuage de points reliant :

*   $x$ = proportion de visites où l’espèce est vue (`prop_visites`)
*   $y$ = proportion de placettes occupées (`prop_placettes`)

Lecture écologique :

*   **Haut-droite** : espèces fréquentes et largement réparties (généralistes/communes).
*   **Bas-gauche** : espèces rares et localisées.
*   **Bas-droite** : espèces temporellement fréquentes mais spatialement confinées (micro-habitats stables).
*   **Haut-gauche** : espèces spatialement larges mais irrégulières dans le temps (phénologie/pulses).

Ce diagramme est très utile pour distinguer :

*   rareté vraie,
*   rareté d’observation,
*   et hétérogénéité spatiale.

#### `ICR_06_CA_placettes_especes.png` (si disponible)

Ordination CA/AFC pour explorer les associations placettes–espèces.

Comment lire :

*   **Points proches** : profils floristiques/mycologiques similaires.
*   **Points éloignés** : composition différente.
*   **Groupes compacts** : unités écologiques homogènes.
*   **Points isolés** : placettes atypiques ou espèces spécialisées.

Précaution d’interprétation :

*   Les axes de CA sont relatifs au jeu de données analysé ; comparer des CA entre jeux différents demande prudence.

---

### Lecture des comparaisons multi-sites

#### `ICR_comparaison_completude_sites.png`

Classe les sites par ratio de complétude $S\_{obs}/S\_{asymptote}$.

*   Permet d’identifier rapidement les sites à renforcer en effort d’inventaire.
*   Un site bas en complétude n’est pas “mauvais” : il peut être plus hétérogène ou plus difficile à prospecter.

#### `ICR_comparaison_ir_sites.png`

Classe les sites par $Ir$ final.

*   Très utile pour prioriser les suivis : sites à $Ir$ faible = priorité de revisite.
*   Croiser avec la complétude est recommandé pour éviter les conclusions hâtives.

---

#### `ICR_metrics_pertinence_heatmap_sites.png`

Heatmap comparative (7 métriques × tous les sites), couleurs du rouge (faible) au vert (bon).

*   Chaque cellule affiche la valeur normalisée (0–1) de l'indicateur pour le site.
*   Permet d'identifier en un coup d'œil les métriques défaillantes et les sites les plus solides.
*   7 métriques visualisées : $Ir$ final, complétude, stabilité finale, robustesse modèle R², cohérence tempo-spatiale Spearman, concordance tempo-spatiale, score de pertinence global.

#### `ICR_metrics_pertinence_score_sites.png`

Classement horizontal des sites par **score de pertinence agrégé** (pondération : Ir 35 %, complétude 35 %, stabilité 20 %, R² 10 %).

*   Zones de fond : rouge (\< 60 % = faible), jaune (60–80 % = intermédiaire), vert (> 80 % = bon).
*   Synthèse exécutive idéale pour prioriser les sites nécessitant un effort supplémentaire.

#### `ICR_07_metrics_pertinence_dashboard.png` (par site)

Dashboard panoramique par site : barres horizontales pour chacun des 7 indicateurs, normalisés de 0 à 1.

*   Lignes de seuil pointillées à 0,60 (acceptable) et 0,80 (bon).
*   Lecture : tout indicateur sous 0,60 motive un complément d'effort ou une révision du protocole.

---

### Bonnes pratiques d’interprétation

*   Interpréter **ensemble** : courbe cumulée + TEE/Ir + fréquences + spatial.
*   Toujours contextualiser avec : saison, pression d’échantillonnage, météo, observateurs.
*   Préférer les tendances sur plusieurs visites plutôt qu’une lecture ponctuelle.
*   Pour décisions de gestion, combiner ces indicateurs avec expertise terrain et connaissance taxonomique.

---

## ❓ Dépannage (FAQ)

### Le manifeste de fin d'exécution signale des fichiers MANQUANT

Le manifeste journalise l'état de chaque fichier attendu à la fin de l'analyse (statuts : OK, MANQUANT, OPTIONNEL\_NON\_GENERE). Un statut MANQUANT indique qu'un fichier obligatoire n'a pas été produit :

*   Vérifier les logs d'exécution pour l'erreur associée.
*   Les fichiers `OPTIONNEL_NON_GENERE` sont normaux si les conditions d'activation ne sont pas réunies (ex. `placette` absent, `vegan` non installé, ou `make_ca = FALSE`).

### Les graphiques de métriques ne sont pas générés

Les 3 graphiques de métriques de pertinence nécessitent que `ICR_07_metrics_pertinence.csv` ait été produit avec des données valides. Vérifier :

*   Que le site comporte au moins 2 visites.
*   Que les colonnes `Ir_final` et `completude` sont présentes dans le résumé du site.

### Le script ne trouve pas mon fichier d’entrée

Vérifier qu’un fichier existe dans `data/` sous l’un des noms suivants :

*   `observations.csv`
*   `observations.txt`
*   `observations.tsv`

et que les colonnes obligatoires sont présentes.

### Le script s'arrête avec "CSV non conforme"

Consulter en priorité :

*   `results/ICR/ICR_00_csv_conformite_report.csv`
*   `results/ICR/ICR_00_csv_conformite_problems.csv` (si présent)

Causes typiques :

*   colonne obligatoire absente (`site`, `date`, `visite_id`, `espece`),
*   colonne supplémentaire non autorisée (`csv_allow_extra_cols = FALSE`),
*   ligne mal formée (parse failure).

Pour assouplir temporairement :

*   `INVENTAIRES_CSV_STRICT=FALSE`
*   `INVENTAIRES_CSV_ALLOW_EXTRA_COLS=TRUE`

### J’ai une erreur sur les dates

Contrôler le format de la colonne `date` et l’option `CONFIG$date_format`.

### Le modèle hyperbolique n’est pas calculé

Installer `minpack.lm` (optionnel). Sans ce package, l’analyse continue mais sans asymptote hyperbolique.

### La CA/AFC n’apparaît pas

Nécessite :

*   package `vegan`
*   colonne `placette` utilisable
*   matrice placette-espèce suffisamment informative

---

## 🧾 Glossaire

| Acronyme | Définition |
| --- | --- |
| **TEE** | **Taux d’Espèces Exceptionnelles** : proportion d’espèces observées une seule fois dans l’inventaire. |
| **Ir** | **Indice de représentativité** : indicateur synthétique défini par $Ir = 1 - TEE$. |
| **Robustesse** | Qualité d'ajustement du modèle d'asymptote : $R^2$ hyperbolique ou linéaire selon disponibilité. |
| **Cohérence** | Corrélation Spearman entre fréquences temporelles et spatiales, normalisée en \[0,1\]. |
| **Score pertinence** | Indicateur agrégé pondéré : $0.35 \\times Ir + 0.35 \\times \\text{complétude} + 0.20 \\times \\text{stabilité} + 0.10 \\times R^2$. |
| **CA** | **Correspondence Analysis** : terme anglophone de l’AFC. |
| **CSV** | **Comma-Separated Values** : format texte tabulaire avec champs séparés par des virgules. |
| **TSV** | **Tab-Separated Values** : format texte tabulaire avec champs séparés par des tabulations. |
| **FAQ** | **Foire Aux Questions** : section de réponses aux problèmes fréquents. |
| **R** | Langage et environnement de calcul statistique utilisé pour ce pipeline. |

---

## 📬 Contact

**Auteur :** Eddy Boite  
Pour les évolutions du script, ouvrir une issue ou documenter les changements dans votre projet hôte.

---

_Document basé sur le modèle éditorial du README du projet FongiFrance (version adaptée au script d’inventaires)._

_Dernière mise à jour : 30 Mars 2026_