# myco\_apps\_releases

[![R](https://img.shields.io/badge/R-%3E%3D4.0-blue.svg)](https://www.r-project.org/)  
[![Domain](https://img.shields.io/badge/Domain-Mycologie%20%7C%20%C3%89cologie-green.svg)](#-applications-disponibles)  
[![Status](https://img.shields.io/badge/Status-Op%C3%A9rationnel-brightgreen.svg)](#-applications-disponibles)

Dépôt de publication des scripts R prêts à l'emploi issus des projets de mycologie et d'écologie.  
Chaque application est autonome : données d'exemple, script principal et documentation inclus.

**Auteur :** Eddy Boite  
**Dernière mise à jour :** 23 Mars 2026

---

## 📋 Table des matières

*   [Applications disponibles](#-applications-disponibles)
*   [Structure du dépôt](#-structure-du-d%C3%A9p%C3%B4t)
*   [Inventaires fongiques – Complétude & Représentativité](#-inventaires-fongiques--compl%C3%A9tude--repr%C3%A9sentativit%C3%A9)
    *   [Prérequis système](#-pr%C3%A9requis-syst%C3%A8me-complets)
    *   [Quick Start](#-quick-start)
    *   [Vérifier que tout fonctionne](#-v%C3%A9rifier-que-tout-fonctionne)
    *   [Structure attendue des données](#-structure-attendue-des-donn%C3%A9es)
    *   [Lancer le script – guide détaillé](#%EF%B8%8F-lancer-le-script--guide-d%C3%A9taill%C3%A9)
    *   [Sorties générées](#-sorties-g%C3%A9n%C3%A9r%C3%A9es)
    *   [Installation des dépendances](#-installation-des-d%C3%A9pendances)
    *   [Configuration](#-configuration)
    *   [Interprétation des indicateurs](#-interpr%C3%A9tation-des-indicateurs)
    *   [Lecture des graphiques](#-lecture-des-graphiques)
    *   [Bonnes pratiques](#-bonnes-pratiques-dinterpr%C3%A9tation)
    *   [Dépannage (FAQ)](#-d%C3%A9pannage-faq)
    *   [Historique des versions](#-historique-des-versions)
    *   [Glossaire](#-glossaire)

---

## 📦 Applications disponibles

| # | Application | Script | Version | Domaine |
| --- | --- | --- | --- | --- |
| 1 | [Inventaires fongiques – Complétude & Représentativité](#-inventaires-fongiques--compl%C3%A9tude--repr%C3%A9sentativit%C3%A9) | `scripts/Inventaires_completude_representativite.R` | v1.4 | Mycologie / Écologie |

---

## 🗂 Structure du dépôt

```
myco_apps_releases/
├── data/
│   └── observations.csv                  # Données d'exemple (prêtes à utiliser)
├── docs/
│   ├── Readme_Analyse_Inventaires_Fongiques.md            # Documentation détaillée (ICR)
│   └── Inventaires_completude_representativite_Conception_Technique.md
├── results/                              # Dossier de sortie (créé automatiquement)
├── scripts/
│   └── Inventaires_completude_representativite.R          # Script principal (v1.4)
└── README.md                             # Ce fichier
```

---

## 🍄 Inventaires fongiques – Complétude & Représentativité

Pipeline R pour automatiser l'analyse de la **complétude d'inventaires fongiques** et de leur **représentativité**, via :

*   le **TEE** (Taux d'Espèces Exceptionnelles)
*   l'**Ir** (Indice de représentativité : $Ir = 1 - TEE$)
*   la courbe temps-espèces avec ajustement linéaire et hyperbolique
*   les métriques de pertinence scientifique (stabilité, robustesse, cohérence spatio-temporelle)
*   les comparaisons multi-sites avec classement et heatmap

Le script produit automatiquement des tableaux CSV et des graphiques PNG (export PDF et SVG également disponibles), par site et en synthèse globale, avec un manifeste automatique de traçabilité en fin d'exécution.

> Documentation complète : [docs/Readme\_Analyse\_Inventaires\_Fongiques.md](docs/Readme_Analyse_Inventaires_Fongiques.md)  
> Conception technique : [docs/Inventaires\_completude\_representativite\_Conception\_Technique.md](docs/Inventaires_completude_representativite_Conception_Technique.md)

---

### 💻 Prérequis système complets

#### ➊ Installer R (obligatoire)

**R** est un environnement de calcul statistique gratuit et open-source. Le script s'exécute avec **R ≥ 4.0** sur **Windows**, **macOS** et **Linux**.

##### Télécharger et installer R

1.  **Accéder au site officiel :** [cran.r-project.org](https://cran.r-project.org)
2.  **Sélectionner votre système d'exploitation :**
    *   **Windows** : cliquer sur [Download R for Windows](https://cran.r-project.org/bin/windows/), puis [base](https://cran.r-project.org/bin/windows/base/), puis télécharger le dernier exécutable `.exe`
    *   **macOS** : cliquer sur [Download R for macOS](https://cran.r-project.org/bin/macosx/), puis télécharger le `.pkg` correspondant à votre architecture (Intel ou Apple Silicon)
    *   **Linux** : suivre les instructions pour Debian/Ubuntu, Fedora, Red Hat, CentOS, etc.
3.  **Exécuter l'installateur** et suivre les instructions par défaut (tout en **Next** convient)
4.  **Vérifier l'installation :** ouvrir un **Terminal** (macOS/Linux) ou **Invite de Commandes** (Windows) et taper :Vous devez voir `R version 4.x.x` ou plus récent.

#### ➋ Installer RStudio Desktop (fortement recommandé, mais optionnel)

**RStudio** est un **IDE** (interface graphique) qui rend R beaucoup plus convivial pour les débutants. Ce n'est pas obligatoire, mais **très utile**.

##### Télécharger et installer RStudio

1.  **Accéder au site :** [posit.co/download/rstudio-desktop](https://posit.co/download/rstudio-desktop/)
2.  **Télécharger la version gratuite** (version "Community", open-source)
3.  **Sélectionner votre système d'exploitation** et télécharger l'installateur
4.  **Exécuter l'installateur** et suivre les instructions par défaut
5.  **Ouvrir RStudio** pour la première fois — vous verrez une fenêtre avec 4 panneaux (Editeur, Console, Environnement, Fichiers)

#### ➌ Installer les packages R requis

Les **packages** sont des extensions qui ajoutent des fonctionnalités à R. Le script utilise une dizaine de packages pour manipuler les données et générer les graphiques.

##### Méthode A — Via RStudio (recommandée pour les débutants)

1.  **Ouvrir RStudio**
2.  **Dans le panneau en bas-à-droite** (onglet "Packages"), cliquer sur le bouton **Install**
3.  **Copier-coller** la commande ci-dessous dans la zone qui s'ouvre :
4.  **Vérifier** que "Install from: CRAN repository" est sélectionné
5.  **Cliquer sur "Install"** et attendre (1–5 minutes selon la connexion)

##### Méthode B — Via la console R (texte)

1.  **Ouvrir la console R** (application "R" sur Windows/macOS, ou console classique)
2.  **Copier-coller** cette commande complète et appuyer sur **Entrée** :
3.  **Répondre** `**y**` **ou** `**yes**` aux questions qui s'affichent
4.  **Attendre** que l'installation se termine (aucune erreur rouge au final ne doit présager un problème ; une installation réussie se termine par `Done`)

##### Vérifier l'installation

Après l'installation, exécuter cette commande pour vérifier que tout les packages requis sont présents :

```
required_pkgs <- c("dplyr", "tidyr", "ggplot2", "purrr", "readr", "stringr", "forcats", "tibble", "scales", "gridExtra")
missing <- !sapply(required_pkgs, requireNamespace, quietly = TRUE)
if (any(missing)) {
  cat("❌ Packages manquants :", paste(required_pkgs[missing], collapse = ", \n"))
} else {
  cat("✅ Tous les packages requis sont installés !")
}
```

---

#### ▶️ Résumé : les 3 étapes pour se préparer

| # | Étape | Durée | Difficulté |
| --- | --- | --- | --- |
| **1** | Télécharger et installer **R** | 5–10 min | Facile (suivre les instructions) |
| **2** | Télécharger et installer **RStudio** | 5–10 min | Facile (optionnel mais recommandé) |
| **3** | Installer les **packages R** | 2–5 min | Facile (copier-coller une commande) |

**Résultat :** vous avez tout ce qu'il faut pour lancer le script !

---

#### ℹ️ Besoin d'aide ? Dépannage initial

**"R n'est pas reconnu" dans le Terminal/Invite de Commandes**

*   **Windows** : redémarrer le Terminal **après** l'installation de R
*   **macOS/Linux** : la commande `R --version` fonctionne généralement

**"je ne sais pas ouvrir un Terminal"**

*   **Windows** : appuyer sur **Windows + R**, taper `cmd`, appuyer sur **Entrée**
*   **macOS** : **Cmd + Espace**, taper `Terminal`, appuyer sur **Entrée**
*   **Linux** : **Ctrl + Alt + T** (dépend de la distribution)

**"Un package refuse de s'installer"**

*   Ignorer pour l'instant — le script affichera un message explicite si un package obligatoire manque
*   Réessayer plus tard avec une bonne connexion Internet

**"je veux lancer le script directement sans RStudio"**

*   C'est possible, voir section [Lancer le script – guide détaillé](#%EF%B8%8F-lancer-le-script--guide-d%C3%A9taill%C3%A9), Option A (ligne de commande)

---

### 🚀 Quick Start

**Pour les débutants qui viennent d'installer R et RStudio :**

#### Étape 1️⃣ — Préparer vos données

Placer votre fichier d'observations dans le dossier `data/` du dépôt, sous le nom `observations.csv`.

Un fichier d'exemple (`data/observations.csv`) est **déjà fourni** — vous pouvez l'utiliser directement pour tester !

#### Étape 2️⃣ — Ouvrir RStudio et charger le script

1.  **Ouvrir RStudio**
2.  **Cliquer sur File → Open File** et naviguer vers :
3.  **Cliquer sur "Source"** (bouton en haut-droite du panneau éditeur) pour lancer le script
4.  **Attendre** que l'exécution se termine (vous verrez les messages de progression dans la console en bas)

#### Étape 3️⃣ — Consulter les résultats

Les sorties seront créées dans le dossier `**results/**` :

*   Fichiers **CSV** = tableaux de données à ouvrir avec Excel ou un tableur
*   Fichiers **PNG** = graphiques prêts à consulter

C'est tout ! 🎉

#### Alternative : ligne de commande (pour utilisateurs avancés)

Si vous êtes à l'aise avec le Terminal, ouvrir un terminal, naviguer jusqu'à la racine du dépôt et exécuter :

```
Rscript scripts/Inventaires_completude_representativite.R
```

---

### ✅ Vérifier que tout fonctionne

Avant de lancer le script sur vos vraies données, un simple test de vérification :

#### Test 1 : R fonctionne

Ouvrir **RStudio** (ou la console R), et copier-coller ceci dans la console :

```
print("Hello from R! ✅")
```

Si vous voyez `[1] "Hello from R! ✅"`, c'est bon.

#### Test 2 : Les packages sont bien installés

Copier-coller ceci dans la console :

```
required_pkgs <- c("dplyr", "tidyr", "ggplot2", "purrr", "readr", "stringr", "forcats", "tibble", "scales", "gridExtra")
all_ok <- all(sapply(required_pkgs, requireNamespace, quietly = TRUE))
if (all_ok) {
  print("✅ Tous les packages obligatoires sont prêts !")
} else {
  print("❌ Certains packages manquent. Relancer l'installation.")
}
```

Si vous voyez `✅`, vous êtes prêt à lancer le script.

#### Test 3 : Lancer le script sur les données d'exemple

Maintenant, lancez le script en cliquant sur "Source" (comme dans le Quick Start). Vous devez voir des messages horodatés dans la console, puis un **manifeste** en fin d'exécution listant tous les fichiers créés.

Si tout s'est bien passé, consultez le dossier `results/` — vous y trouverez les fichiers CSV et PNG.

🎉 **Félicitations ! Vous êtes prêt à lancer le script sur vos propres données.**

---

---

### 📥 Structure attendue des données

Le fichier d'entrée doit être en format **CSV** (ou TSV / TXT, détection automatique du séparateur).

#### Colonnes obligatoires

| Colonne | Type | Description |
| --- | --- | --- |
| `site` | Texte | Identifiant du site inventorié |
| `date` | Date (`YYYY-MM-DD`) | Date de la visite |
| `visite_id` | Texte | Identifiant de la visite (ex. `V1`, `V2`…) |
| `espece` | Texte | Nom de l'espèce observée |

#### Colonne optionnelle

| Colonne | Type | Description |
| --- | --- | --- |
| `placette` | Texte | Identifiant de la placette (active l'analyse spatiale et la CA/AFC) |

> **Important :** une visite est identifiée de façon unique par la combinaison `site + date + visite_id`. Cela permet de gérer les jeux de données où un même `visite_id` peut être réutilisé à des dates différentes.

#### Exemple de données

| site | date | visite\_id | espece | placette |
| --- | --- | --- | --- | --- |
| BoisLarge | 2025-09-10 | V1 | Gyrodon lividus | P1 |
| BoisLarge | 2025-09-10 | V1 | Russula leprosa | P1 |
| BoisLarge | 2025-09-17 | V2 | Amanita rubescens | P2 |
| Site\_B | 2025-10-01 | V1 | Cantharellus cibarius | P3 |

Le fichier `data/observations.csv` fourni contient un jeu de données d'exemple fonctionnel avec plusieurs sites et placettes.

---

### ▶️ Lancer le script – guide détaillé

#### Option A — Ligne de commande (Rscript)

Méthode recommandée pour une exécution reproductible et automatisable.

```
# Ouvrir un terminal, se positionner à la racine du dépôt
cd /chemin/vers/myco_apps_releases

# Lancer le script
Rscript scripts/Inventaires_completude_representativite.R
```

#### Option B — Session R interactive (RStudio ou console R)

```
# Définir le répertoire de travail sur la racine du dépôt
setwd("/chemin/vers/myco_apps_releases")

# Charger et exécuter le script
source("scripts/Inventaires_completude_representativite.R")
```

> Dans RStudio, vous pouvez également ouvrir le fichier `.R` et utiliser le bouton **Source** (Ctrl+Shift+S / Cmd+Shift+S).

#### Contrôle de l'exécution via variable d'environnement

| Variable | Valeur | Effet |
| --- | --- | --- |
| `INVENTAIRES_AUTO_RUN` | `TRUE` (défaut) | Lance l'analyse automatiquement au chargement |
| `INVENTAIRES_AUTO_RUN` | `FALSE` (ou `0`, `no`, `off`) | Charge uniquement les fonctions sans les exécuter |

```
# Charger les fonctions sans lancer l'analyse (utile pour tester ou déboguer)
INVENTAIRES_AUTO_RUN=FALSE Rscript scripts/Inventaires_completude_representativite.R
```

#### Ce qui s'affiche dans la console pendant l'exécution

Le script journalise chaque étape avec horodatage `[YYYY-MM-DD HH:MM:SS] [INFO]` :

```
[2026-03-23 10:00:01] [INFO] Initialisation du script ...
[2026-03-23 10:00:01] [INFO] Lecture du fichier : data/observations.csv
[2026-03-23 10:00:01] [INFO] Données valides : 120 lignes, 3 sites, 15 espèces
[2026-03-23 10:00:02] [INFO] Traitement site : BoisLarge (8 visites)
[2026-03-23 10:00:03] [INFO] Traitement site : Site_B (6 visites)
...
[2026-03-23 10:00:08] [INFO] ================ MANIFESTE DES SORTIES ================
[2026-03-23 10:00:08] [INFO] [MANIFEST] OK   results/ICR_donnees_preparees.csv
[2026-03-23 10:00:08] [INFO] [MANIFEST] OK   results/ICR_resume_tous_sites.csv
...
```

En fin d'exécution, le **manifeste** liste l'état de chaque fichier attendu :

*   `OK` — fichier produit avec succès
*   `MANQUANT` — fichier obligatoire non généré (voir les logs pour l'erreur)
*   `OPTIONNEL_NON_GENERE` — fichier optionnel non généré (conditions non réunies)

#### Options de débogage (à modifier directement en tête du script)

| Option | Défaut | Effet si `TRUE` |
| --- | --- | --- |
| `DEBUG_MODE` | `FALSE` | Affiche des messages très détaillés et tous les warnings R |
| `BENCHMARK_MODE` | `FALSE` | Mesure et affiche le temps d'exécution de chaque calcul |
| `CLEAN_ENVIRONMENT` | `FALSE` | Nettoie l'environnement R avant exécution (usage isolé uniquement) |

---

### 📊 Sorties générées

Toutes les sorties sont créées dans `results/` (le dossier est créé automatiquement s'il n'existe pas).

#### Vue d'ensemble du pipeline (9 étapes → fichiers)

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

#### Fichiers globaux (`results/`)

| Fichier | Type | Description |
| --- | --- | --- |
| `ICR_donnees_preparees.csv` | CSV | Données nettoyées et standardisées |
| `ICR_resume_tous_sites.csv` | CSV | Synthèse complétude + représentativité tous sites |
| `ICR_metrics_pertinence_tous_sites.csv` | CSV | Métriques de pertinence scientifique multi-sites |
| `ICR_comparaison_completude_sites.png` | Graphique | Comparaison du ratio de complétude entre sites |
| `ICR_comparaison_ir_sites.png` | Graphique | Comparaison de l'indice $Ir$ entre sites |
| `ICR_metrics_pertinence_heatmap_sites.png` | Graphique | Heatmap comparative des 7 métriques de pertinence |
| `ICR_metrics_pertinence_score_sites.png` | Graphique | Classement global des sites par score de pertinence |

#### Fichiers par site (`results/<nom_du_site>/`)

| Fichier | Type | Condition | Description |
| --- | --- | --- | --- |
| `ICR_01_courbe_temps_especes.csv` | CSV | Toujours | Richesse observée et cumulée par visite |
| `ICR_02_tee_ir.csv` | CSV | Toujours | Évolution de TEE et $Ir$ au fil des visites |
| `ICR_03_frequence_especes.csv` | CSV | Toujours | Fréquences d'occurrence des espèces |
| `ICR_04_resume_site.csv` | CSV | Toujours | Résumé synthétique du site |
| `ICR_05_modeles.csv` | CSV | Si modèles ajustés | Paramètres des modèles linéaire/hyperbolique |
| `ICR_06_occupation_spatiale.csv` | CSV | Si `placette` disponible | Occupation spatiale par placette |
| `ICR_07_metrics_pertinence.csv` | CSV | Toujours | 15 métriques de pertinence scientifique |
| `ICR_01_richesse_par_visite_et_cumul.png` | Graphique | Toujours | Richesse par visite + richesse cumulée |
| `ICR_02_courbe_temps_especes_hyperbole.png` | Graphique | Toujours | Courbe temps-espèces + ajustement hyperbolique |
| `ICR_03_tee_ir.png` | Graphique | Toujours | TEE et $Ir$ en deux panneaux |
| `ICR_04_histogramme_frequences.png` | Graphique | Toujours | Distribution des fréquences d'observabilité |
| `ICR_05_temporel_vs_spatial.png` | Graphique | Si `placette` disponible | Fréquence temporelle vs occupation spatiale |
| `ICR_06_CA_placettes_especes.png` | Graphique | Si `vegan` + `placette` | Ordination CA/AFC placettes-espèces |
| `ICR_07_metrics_pertinence_dashboard.png` | Graphique | Toujours | Dashboard des 7 métriques de pertinence du site |

> **Convention de nommage :** tous les fichiers générés sont préfixés `ICR_` pour les distinguer des sorties des autres scripts du projet.

---

### 🔧 Installation des dépendances

#### Packages requis

| Package | Rôle |
| --- | --- |
| `dplyr` | Manipulation de données tabulaires |
| `tidyr` | Restructuration des données (format long/large) |
| `ggplot2` | Génération des graphiques |
| `purrr` | Itérations fonctionnelles sur les sites |
| `readr` | Lecture/écriture des fichiers CSV/TSV |
| `stringr` | Traitement des chaînes de caractères |
| `forcats` | Gestion des facteurs |
| `tibble` | Structures tabulaires modernes |
| `scales` | Mise en forme des axes graphiques |
| `gridExtra` | Assemblage de graphiques multi-panneaux |

```
install.packages(c(
  "dplyr", "tidyr", "ggplot2", "purrr",
  "readr", "stringr", "forcats", "tibble",
  "scales", "gridExtra"
))
```

#### Packages optionnels

| Package | Fonctionnalité activée |
| --- | --- |
| `minpack.lm` | Ajustement hyperbolique (estimation d'asymptote, ratio de complétude) |
| `vegan` | Ordination CA/AFC (analyse placettes–espèces) |

```
install.packages(c("minpack.lm", "vegan"))
```

> Le script vérifie les packages requis au démarrage et affiche une commande d'installation explicite si certains sont manquants. L'exécution s'arrête proprement avec un message clair plutôt que de produire des résultats partiels silencieux.

---

### ⚙️ Configuration

La configuration est centralisée dans l'objet `CONFIG` au début du script (`scripts/Inventaires_completude_representativite.R`). Toute adaptation se fait directement dans ce bloc.

| Paramètre | Valeur par défaut | Description |
| --- | --- | --- |
| `input_file` | `data/observations.csv` | Chemin du fichier d'entrée (relatif à la racine du projet) |
| `output_dir` | `results` | Dossier de sortie des CSV et graphiques |
| `date_format` | `%Y-%m-%d` | Format de date R attendu (ex. `2026-03-18`) |
| `make_ca` | `TRUE` | Active l'ordination CA/AFC si les conditions sont réunies |
| `min_visits_for_model` | `5` | Nombre minimal de visites pour ajuster les modèles |
| `freq_breaks` | `c(0, .10, .25, .50, .75, 1)` | Bornes des classes de fréquence (en proportion) |
| `freq_labels` | `exceptionnelle … constante` | Noms des 5 classes de fréquence |
| `width` | `10` | Largeur des graphiques exportés (en pouces) |
| `height` | `6` | Hauteur des graphiques exportés (en pouces) |
| `dpi` | `300` | Résolution des PNG exportés (points par pouce) |

**Exemple de personnalisation :**

```
# Dans le script, modifier CONFIG avant l'exécution :
CONFIG$input_file <- "data/mon_inventaire_2026.csv"
CONFIG$date_format <- "%d/%m/%Y"   # si vos dates sont au format jour/mois/année
CONFIG$make_ca <- FALSE            # désactiver la CA/AFC
CONFIG$min_visits_for_model <- 3   # assouplir le seuil si peu de visites
```

---

### 🧠 Interprétation des indicateurs

#### TEE – Taux d'Espèces Exceptionnelles

Proportion d'espèces observées **une seule fois** dans l'inventaire.

| TEE | Interprétation |
| --- | --- |
| \> 0,40 | Inventaire souvent **incomplet** |
| 0,20 – 0,40 | Inventaire **intermédiaire** |
| \< 0,20 | Inventaire généralement **bien consolidé** |

*   **TEE élevé en fin de suivi** : beaucoup d'espèces vues qu'une fois → inventaire en phase d'accumulation.
*   **TEE qui diminue** : signe positif, les espèces "uniques" deviennent progressivement récurrentes.
*   **TEE stable et bas** : communauté mieux couverte, effort proche d'un plateau.

#### Ir – Indice de représentativité

$$Ir = 1 - TEE$$

| $Ir$ | Représentativité |
| --- | --- |
| ≥ 0,80 | Bonne à élevée |
| 0,60 – 0,80 | Moyenne |
| \< 0,60 | Faible |

*   **Ir en hausse au fil des visites** : le protocole capture mieux la diversité réelle du site.
*   **Ir qui plafonne tôt** : effort potentiellement suffisant, sauf si période écologique incomplète.
*   **Ir faible et stagnant** : effort, calendrier ou stratification spatiale à revoir.

#### Complétude / asymptote hyperbolique

$$\\text{Complétude} = \\frac{S\_{obs}}{S\_{asymptote}}$$

| Complétude | Interprétation |
| --- | --- |
| \> 0,90 | Inventaire très avancé |
| 0,70 – 0,90 | Progression correcte, inventaire partiel |
| \< 0,70 | Insuffisante pour conclure sur l'exhaustivité |

> L'asymptote ne doit pas être interprétée comme une "vérité absolue", mais comme un **repère quantitatif** de complétude.

#### Score de pertinence scientifique (agrégé, v1.4)

$$\\text{Score} = 0{,}35 \\times Ir + 0{,}35 \\times \\text{complétude} + 0{,}20 \\times \\text{stabilité} + 0{,}10 \\times R^2$$

---

### 📈 Lecture des graphiques

#### `ICR_01_richesse_par_visite_et_cumul.png`

Combine **barres** (richesse observée par visite) et **ligne** (richesse cumulée).

*   **Barres encore hautes + cumul qui monte vite** → inventaire en phase active de découverte.
*   **Barres qui baissent + cumul qui se tasse** → entrée dans une phase de saturation.
*   **Dents de scie marquées** → forte dépendance météo / saison / observateur.
*   Signal d'alerte : si les dernières visites apportent encore beaucoup de nouvelles espèces, l'arrêt de l'inventaire peut être prématuré.

#### `ICR_02_courbe_temps_especes_hyperbole.png`

Superpose les observations à un ajustement hyperbolique (si `minpack.lm` disponible) et une asymptote estimée.

*   **Courbe observée proche de la courbe ajustée** → modèle cohérent, asymptote fiable.
*   **Écart important** → structure de données non compatible avec ce modèle (saisonnalité forte, ruptures d'effort, etc.).
*   **Asymptote nettement au-dessus de la richesse actuelle** → marge de découverte encore importante.

#### `ICR_03_tee_ir.png`

Deux panneaux complémentaires :

panneau haut : nombre d'espèces observées une seule fois (`nb_esp_1fois`)

panneau bas : indice $Ir$ sur l'échelle $\[0,1\]$ avec seuils visuels (0,60 et 0,80)

**Espèces uniques qui ralentissent** → signal de consolidation de l'inventaire.

**Ir qui augmente puis se stabilise** → représentativité qui converge.

Les seuils sont des repères empiriques : toujours interpréter avec le contexte (saison, effort, habitat).

#### `ICR_04_histogramme_frequences.png`

Distribution du nombre d'espèces selon leur fréquence d'occurrence.

*   **Pic sur les faibles fréquences** → communauté riche en espèces rares/occasionnelles.
*   **Répartition plus équilibrée** → noyau d'espèces régulières bien documenté.
*   **Queue vers les fortes fréquences** → présence d'espèces constantes, potentiels bons indicateurs écologiques.

#### `ICR_05_temporel_vs_spatial.png` _(si_ `_placette_` _disponible)_

Nuage de points reliant fréquence temporelle ($x$ = proportion de visites) et occupation spatiale ($y$ = proportion de placettes).

*   **Haut-droite** → espèces fréquentes et largement réparties (généralistes / communes).
*   **Bas-gauche** → espèces rares et localisées (vraie rareté).
*   **Bas-droite** → espèces temporellement fréquentes mais spatialement confinées (micro-habitats stables).
*   **Haut-gauche** → espèces spatialement larges mais irrégulières dans le temps (phénologie / pulses).

Ce diagramme permet de distinguer rareté vraie, rareté d'observation et hétérogénéité spatiale.

#### `ICR_06_CA_placettes_especes.png` _(si_ `_vegan_` _+_ `_placette_` _disponibles)_

Ordination CA/AFC explorant les associations placettes–espèces.

*   **Points proches** → profils mycologiques similaires.
*   **Groupes compacts** → unités écologiques homogènes.
*   **Points isolés** → placettes atypiques ou espèces spécialisées.
*   Les axes de CA sont relatifs au jeu de données analysé ; comparer des CA entre jeux différents demande prudence.

#### `ICR_07_metrics_pertinence_dashboard.png`

Dashboard panoramique par site : barres horizontales pour chacun des 7 indicateurs (normalisés 0–1).

*   Lignes de seuil pointillées à **0,60** (acceptable) et **0,80** (bon).
*   Tout indicateur sous 0,60 motive un complément d'effort ou une révision du protocole.

#### Graphiques multi-sites

| Graphique | Ce qu'il montre |
| --- | --- |
| `ICR_comparaison_completude_sites.png` | Sites classés par ratio de complétude — identifier rapidement les sites à renforcer |
| `ICR_comparaison_ir_sites.png` | Sites classés par $Ir$ final — prioriser les revisites (sites à $Ir$ faible en premier) |
| `ICR_metrics_pertinence_heatmap_sites.png` | Heatmap 7 métriques × tous sites (rouge = faible, vert = bon) — vue synthétique comparative |
| `ICR_metrics_pertinence_score_sites.png` | Classement par score agrégé avec zones rouge/jaune/vert — synthèse exécutive |

---

### ✅ Bonnes pratiques d'interprétation

*   Interpréter **ensemble** : courbe cumulée + TEE/Ir + fréquences + spatial.
*   Toujours contextualiser avec : saison, pression d'échantillonnage, météo, observateurs.
*   Préférer les **tendances sur plusieurs visites** plutôt qu'une lecture ponctuelle.
*   Un site bas en complétude n'est pas "mauvais" : il peut être plus hétérogène ou plus difficile à prospecter.
*   Croiser complétude et $Ir$ avant de conclure sur l'effort à fournir : un $Ir$ élevé avec une complétude faible peut signifier un site très riche, pas un protocole défaillant.
*   Pour des décisions de gestion, combiner ces indicateurs avec l'expertise terrain et la connaissance taxonomique.

---

### ❓ Dépannage (FAQ)

**Le script ne trouve pas mon fichier d'entrée**  
Vérifier qu'un fichier existe dans `data/` sous : `observations.csv`, `observations.txt` ou `observations.tsv`, et que les 4 colonnes obligatoires (`site`, `date`, `visite_id`, `espece`) sont présentes.

**Erreur "Packages requis manquants"**  
Le script affiche la commande `install.packages(...)` exacte à exécuter. Copier-coller cette commande dans R, puis relancer le script.

**Erreur sur les dates**  
Contrôler le format de la colonne `date` et adapter `CONFIG$date_format` dans le script (défaut : `%Y-%m-%d`, ex. `2026-03-23`). Format courant alternatif : `%d/%m/%Y` pour `23/03/2026`.

**Le modèle hyperbolique n'est pas calculé**  
Installer `minpack.lm`. Sans ce package, l'analyse continue mais sans asymptote hyperbolique ni ratio de complétude. Vérifier aussi que le site a au moins `CONFIG$min_visits_for_model` visites (défaut : 5).

**La CA/AFC n'apparaît pas**  
Nécessite : package `vegan` installé + colonne `placette` présente + matrice placette-espèce suffisamment informative (plusieurs placettes avec plusieurs espèces différentes). Vérifier également que `CONFIG$make_ca` est `TRUE`.

**Le manifeste signale des fichiers MANQUANT**

*   `MANQUANT` : fichier obligatoire non produit — voir les logs d'exécution pour l'erreur associée.
*   `OPTIONNEL_NON_GENERE` : normal si les conditions ne sont pas réunies (ex. `placette` absent, `vegan` non installé, `make_ca = FALSE`).

**Les graphiques de métriques de pertinence ne sont pas générés**  
Le site doit avoir au moins 2 visites et les colonnes `Ir_final` et `completude` doivent être présentes dans le résumé du site.

**Exécution très lente**  
Activer `BENCHMARK_MODE <- TRUE` en tête du script pour identifier les goulots d'étranglement. Sur de grands jeux de données, la phase de calculs cumulés bénéficie de la vectorisation introduite en v1.2.

---

### 🕓 Historique des versions

| Version | Phase | Principales évolutions |
| --- | --- | --- |
| **v1.4** (actuelle) | Phase 4 — Industrialisation | Métriques de pertinence scientifique (stabilité, robustesse, cohérence, score agrégé), rapport Quarto, manifeste automatique des sorties |
| **v1.3** | Phase 3 — Graphiques | Thème unifié CVD-friendly (palette accessible 5 couleurs), annotations scientifiques, diagramme TEE/Ir 2 panneaux avec seuils, comparaisons sites annotées, export multi-formats (PNG, PDF, SVG) |
| **v1.2** | Phase 2 — Performance | Vectorisation des calculs cumulés, mode benchmarking (`BENCHMARK_MODE`) |
| **v1.1** | Phase 1 — Fiabilisation | Validation robuste des données d'entrée, détection automatique du séparateur (CSV/TSV/TXT), messages d'erreur explicites |

---

### 🧾 Glossaire

| Terme | Définition |
| --- | --- |
| **TEE** | Taux d'Espèces Exceptionnelles : proportion d'espèces observées une seule fois |
| **Ir** | Indice de représentativité : $Ir = 1 - TEE$ |
| **Asymptote** | Richesse théorique maximale estimée par le modèle hyperbolique |
| **Complétude** | Ratio $S\_{obs} / S\_{asymptote}$ : avancement de l'inventaire vers la richesse théorique |
| **Robustesse** | Qualité d'ajustement ($R^2$) du modèle d'asymptote |
| **Stabilité** | Convergence de $Ir$ sur les dernières visites |
| **Cohérence** | Corrélation Spearman entre fréquences temporelles et spatiales, normalisée en \[0,1\] |
| **Score pertinence** | Indicateur agrégé pondéré : $0{,}35 \\times Ir + 0{,}35 \\times \\text{complétude} + 0{,}20 \\times \\text{stabilité} + 0{,}10 \\times R^2$ |
| **CA / AFC** | Correspondence Analysis / Analyse Factorielle des Correspondances |
| **CSV** | Comma-Separated Values : fichier texte tabulaire, champs séparés par des virgules |
| **TSV** | Tab-Separated Values : fichier texte tabulaire, champs séparés par des tabulations |
| **ICR** | Préfixe de nommage de tous les fichiers produits par ce script |
| **CVD-friendly** | Compatible daltoniens (Color Vision Deficiency) : palette graphique accessible |

---

## 📬 Contact

**Auteur :** Eddy Boite  
Pour toute question ou évolution, ouvrir une issue sur ce dépôt.

```
myco_apps_releases/scripts/Inventaires_completude_representativite.R
```

```
install.packages(c(
  "dplyr", "tidyr", "ggplot2", "purrr",
  "readr", "stringr", "forcats", "tibble",
  "scales", "gridExtra",
  "minpack.lm", "vegan"
))
```

```
c("dplyr", "tidyr", "ggplot2", "purrr", "readr", "stringr", "forcats", "tibble", "scales", "gridExtra", "minpack.lm", "vegan")
```

```
R --version
```