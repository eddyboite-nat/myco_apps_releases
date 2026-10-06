# Introduction

Ce document suit une structure IMRaD stricte afin de distinguer clairement le contexte, les méthodes, les résultats produits et la discussion des limites. L’introduction précise le périmètre fonctionnel du pipeline, son objet écologique et les pré-requis d’exécution.

## À propos

Ce document décrit la spécification fonctionnelle complète du script :

<div class="center">

`scripts/Evaluation_Potentiel_Fongique_Interets_Patrimoniaux_CHEGD.R`

</div>

Le script a été conçu pour automatiser l’évaluation mycologique de pelouses en s’appuyant sur la méthode CHEGD (**C**lavaria, **H**ygrocybe/Cuphophyllus, **E**ntoloma, **G**eoglossaceae, **D**ermoloma), qui constitue un indicateur de référence pour l’évaluation de la valeur patrimoniale des prairies en Europe occidentale.

## Objectifs du pipeline

Le pipeline réalise automatiquement, pour chaque site (pelouse) :

1.  Lecture et validation d’un fichier de données brutes CSV.

2.  Production de résumés descriptifs globaux (par site, famille, espèce, date, fiabilité).

3.  Calcul du **potentiel fongique** : score pondéré par groupe fonctionnel.

4.  Calcul de l’**intérêt patrimonial** : indice CHEGD et classification en 5 niveaux.

5.  Calcul du **gradient CHEGD** : nombre d’espèces CHEGD par visite.

6.  Calcul de l’**Indice de Représentativité (IR)** par visite et par site.

7.  Génération de 7 figures de synthèse (PNG 300 dpi + PDF vectoriel).

8.  Module statistique : analyse de la fiabilité des déterminations (4 objectifs).

9.  Export de tous les résultats en fichiers CSV encodés UTF-8.

## Dépendances et pré-requis

| **Package** | **Rôle**                                                      |
|:------------|:--------------------------------------------------------------|
| `dplyr`     | Manipulation de tableaux (filtrage, jointures, agrégations)   |
| `stringr`   | Traitements de chaînes (regex, normalisation, extraction)     |
| `ggplot2`   | Génération des figures                                        |
| `gridExtra` | Assemblage de graphiques multi-panneaux                       |
| `MASS`      | Régression ordinale (`polr`) pour le module fiabilité         |
| `nnet`      | Régression multinomiale (`multinom`) pour le module fiabilité |

Packages R requis

| **Package** | **Utilisation**                                             |
|:------------|:------------------------------------------------------------|
| `ggrepel`   | Gestion automatique des chevauchements de labels (Figure 2) |

Packages R optionnels

Les packages requis sont vérifiés au démarrage. Si un package manque, l’exécution s’arrête avec un message explicite et une commande `install.packages(...)` à lancer.

# Méthodes

Les méthodes décrivent les choix fonctionnels nécessaires à la reproductibilité du pipeline : organisation du projet, configuration, structure des données, transformations, métriques et module statistique.

## Structure du projet

```
statistics/
+-- data/
|   \-- données_récoltes_chegd_pelouses.csv   # Données d'entrée (configurable)
+-- docs/
|   \-- Evaluation_Potentiel_Fongique_CHEGD_Conception_Fonctionnelle.tex
+-- results/
|   \-- EPFIP_CHEGD/                           # Répertoire de sortie fixe
|       +-- 00_data_prepared/
|       +-- 10_indices_metiers/
|       +-- 20_syntheses/
|       +-- 30_statistiques_modeles/
|       +-- 40_qa_audits/
|       +-- 50_figures_metier/
|       \-- 60_figures_statistiques/
+-- logs/
|   \-- EPFIP_CHEGD_YYYYMMDD_HHMM.log         # Log horodate par execution
+-- scripts/
|   \-- Evaluation_Potentiel_Fongique_Interets_Patrimoniaux_CHEGD.R
\-- statistics.Rproj
```

<div class="infobox">

Tous les fichiers générés par ce script sont produits dans le sous-répertoire `results/EPFIP_CHEGD/` (préfixe configurable via `output_prefix`). Le script organise ensuite automatiquement les artefacts dans des sous-répertoires thématiques (`00_data_prepared` à `60_figures_statistiques`). En cas d’échec d’une étape non bloquante (figure ou objectif fiabilité), un journal `non_blocking_failures.csv` est exporté dans `40_qa_audits/`.

</div>

## Configuration

La configuration est centralisée dans la fonction `get_embedded_config()`.

| **Paramètre** | **Valeur par défaut** | **Description** |
|:---|:---|:---|
| `protocol_scope` | `CHEGD pelouses` | Libellé de périmètre protocolaire (logs) |
| `strict` | `TRUE` | Mode d’exécution : strict (arrêt) / tolérant (warning) |
| `input_file` |  |  |
|  | Chemin du fichier d’entree |  |
| `output_dir` | `results` | Répertoire de base pour les sorties |
| `output_prefix` | `EPFIP_CHEGD` | Préfixe du sous-répertoire de sortie |
| `columns$species` | `Espèces` | Nom de la colonne espèce |
| `columns$family` | `Famille` | Nom de la colonne famille |
| `columns$date` | `Date` | Nom de la colonne date |
| `columns$count` | `Nombre d’espèce` | Nom de la colonne effectif |
| `columns$site` | `Site` | Nom de la colonne site |
| `columns$reliability` | `Fiabilité détermination` | Nom de la colonne fiabilité |
| `quality_alert_thresholds` | liste de seuils % | Seuils d’alerte QA (lignes vides, dates invalides, etc.) |

Paramètres de configuration

### Résolution des chemins

Le script résout automatiquement les chemins relatifs selon l’environnement d’exécution, par ordre de priorité :

1.  Argument `--file=<chemin>` injecté par `Rscript`.

2.  `sys.frames()[[1]$ofile]` : injecté par `source()` ou RStudio.

3.  `getwd()` : répertoire de travail courant (fallback VSCode / console interactive).

Le fichier d’entrée est résolu via une stratégie à **3 niveaux** :

1.  **Chemin exact** : `file.exists()` sur le chemin résolu.

2.  **Correspondance normalisée** : comparaison après suppression des accents, mise en minuscules et retrait des caractères non alphanumériques.

3.  **Distance de Levenshtein** (`adist`) : candidat le plus proche si la distance est inférieure au seuil $`\max(3,\, \lfloor 0{,}25 \times \text{long}(\text{nom})\rfloor)`$.

## Structure attendue des données d’entrée

### Formats acceptés

- **CSV** : séparateur auto-détecté (tabulation, `;` ou `,` sur les 5 premières lignes). Les lignes ne contenant que des séparateurs sont éliminées. Le BOM et les colonnes vides de bord sont supprimés.

### Colonnes obligatoires

| **Clé config** | **Nom par défaut** | **Description** |
|:---|:---|:---|
| `species` | `Espèces` | Nom scientifique de l’espèce |
| `family` | `Famille` | Famille taxonomique |
| `date` | `Date` | Date de l’observation |
| `count` | `Nombre d’espèce` | Nombre d’individus ou d’occurrences |
| `site` | `Site` | Identifiant du site (ex : « Pelouse 3 ») |
| `reliability` | `Fiabilité détermination` | Niveau de confiance dans la détermination |

Colonnes requises dans le fichier d’entrée (noms configurables)

### Formats de dates acceptés

Le script tolère les formats suivants, dans l’ordre de tentative :

- Numéro de série Excel (origine 1899-12-30).

- `YYYY-MM-DD`, `DD/MM/YYYY`, `DD-MM-YYYY`, `MM/DD/YYYY`, `DD.MM.YYYY`.

Les valeurs vides, `NA` et `NaN` sont remplacées par `NA` avant conversion.

### Exemple minimal

| **Site** | **Date** | **Espèces** | **Famille** | **Nombre** | **Fiabilité** |
|:---|:---|:---|:---|:---|:---|
| Pelouse 1 | 2025-09-12 | Hygrocybe coccinea | Hygrophoraceae | 2 | Certaine |
| Pelouse 1 | 2025-09-12 | Entoloma conferendum | Entolomataceae | 1 | Probable |
| Pelouse 3 | 2025-09-20 | Clavaria fragilis | Clavariaceae | 3 | Certaine |
| Pelouse 3 | 2025-09-20 | Cuphophyllus pratensis | Hygrophoraceae | 1 | Certaine |

Exemple de jeu de données d’entrée

## Pipeline de traitement des données

### Vue d’ensemble

<div class="center">

</div>

### Nettoyage et enrichissement

Après lecture, les colonnes suivantes sont ajoutées au tableau brut :

- `date_obs` : conversion robuste de la colonne date vers le type `Date`.

- `nombre_espece_num` : conversion de l’effectif en numérique, avec tolérance de la virgule décimale.

### Normalisation de texte

La fonction `normalize_text()` est utilisée systématiquement avant toute comparaison de noms d’espèces ou de sites. Elle applique, dans l’ordre :

1.  Conversion en chaîne de caractères.

2.  Translittération ASCII (`iconv` avec `ASCII//TRANSLIT`).

3.  Conversion en minuscules.

4.  Remplacement des caractères non alphanumériques par un espace, puis contraction des espaces multiples.

### Référentiel des sites

La fonction `prepare_site_reference()` construit un référentiel continu de sites de 1 jusqu’au plus grand identifiant détecté :

- Les identifiants sont extraits avec la regex  
  `d+` depuis les valeurs textuelles (ex : « Pelouse 16 » $`\to`$ 16).

- Les sites non observés dans les données reçoivent un nom synthétique « Pelouse N ».

- Le référentiel garantit que les sites intermédiaires manquants sont inclus dans toutes les métriques.

## Calcul des métriques par site

### Principe général

Les trois indicateurs sont calculés dans `build_site_level_metrics()` à partir du tableau dédupliqué des espèces par site (`distinct(site_id, species_raw, species_norm, genus, family_norm)`). Seules les **espèces uniques par site** contribuent aux scores (pas de double comptage par visite).

### Potentiel fongique

**Définition.**

Le potentiel fongique est un **score de richesse pondérée** par groupe fonctionnel CHEGD. Il reflète la valeur écologique globale du site en additionnant les contributions de chaque groupe d’espèces indicatrices, pondérées selon leur rarité et leur valeur diagnostique.

**Grille de pondération.**

<div class="tabularx">

L2.6cmYcL3.2cm **Groupe** & **Genres / espèces** & **Poids** & **Variable**  
Mycènes et litière & *Mycena, Galerina, Crinipellis* & $`\times`$<!-- -->1 &  
Coprophiles & *Coprinus, Coprinellus, Conocybe, Panaeolus, Psathyrella, Psilocybe, Stropharia, Coprinopsis, Panaeolina* & $`\times`$<!-- -->1 &  
Agarics & *Agaricus* & $`\times`$<!-- -->1 &  
Entolomes & *Entoloma* & $`\times`$<!-- -->2 &  
Clavarioïdes & *Clavaria, Clavulinopsis, Ramariopsis* + Géoglossacées & $`\times`$<!-- -->4 &  
*Clavaria zollingeri* & espèce seule & $`\times`$<!-- -->6 &  
*Cuphophyllus* spp. & genre entier & $`\times`$<!-- -->2 &  
*Hygrocybe conica* & complexe & $`\times`$<!-- -->2 &  
Hygrocybes jaunes & *H. chlorophana, H. glutinipes, H. euroflavescens* & $`\times`$<!-- -->2 &  
*H. psittacina* & et *Gliophorus psittacinus* & $`\times`$<!-- -->2 &  
*C. pratensis* & espèce seule & $`\times`$<!-- -->3 &  
*Hygrocybe reidii* & espèce seule & $`\times`$<!-- -->3 &  
Hygrocybes rouges & *H. coccinea, H. punicea, H. splendidissima* & $`\times`$<!-- -->7 &  
*H. calyptriformis* & et *Porpolomopsis calyptriformis* & $`\times`$<!-- -->10 &  
*Dermoloma* spp. & genre entier & $`\times`$<!-- -->3 &  
*Camarophyllopsis* & genre entier & $`\times`$<!-- -->3 &  
*Porpoloma* spp. & genre entier & $`\times`$<!-- -->6 &  
Grandes vesses & *Langermannia, Calvatia* & $`\times`$<!-- -->1 &  

</div>

**Formule.**

<div class="formulebox">

``` math
\begin{aligned}
    \text{Score}_{\text{potentiel}} ={}&
    n_{\text{litière}} + n_{\text{copro}} + n_{\text{agaricus}}
    + 2n_{\text{entoloma}} + 4n_{\text{clavaria}} + 6n_{\text{C.zollingeri}} \\
    &+ 2n_{\text{Cuphophyllus}} + 2n_{\text{H.conica}}
    + 2n_{\text{hygro.jaunes}} + 2n_{\text{psittacina}} \\
    &+ 3n_{\text{C.pratensis}} + 3n_{\text{H.reidii}}
    + 7n_{\text{hygro.rouges}} + 10n_{\text{H.calyptriformis}} \\
    &+ 3n_{\text{dermoloma}} + 3n_{\text{camarophyllopsis}}
    + 6n_{\text{porpoloma}} + n_{\text{vesses}}.
  \end{aligned}
```
où $`n_X`$ est le **nombre d’espèces uniques** du groupe $`X`$ observées sur le site.

</div>

**Classification.**

| **Seuil** | **Classe** | **Couleur recommandée** |
|:--:|:---|:--:|
| Score $`\leq 10`$ | Potentiel fongique faible | bleu clair (`#D8EAF7`) |
| $`10 <`$ Score $`< 30`$ | Potentiel fongique intéressant | bleu moyen (`#6BAED6`) |
| Score $`\geq 30`$ | Potentiel fongique élevé | bleu foncé (`#08519C`) |

Classes de potentiel fongique

### Intérêt patrimonial

**Définition.**

L’intérêt patrimonial est basé sur la **richesse spécifique maximale parmi les 5 groupes CHEGD**. Il reflète le degré de développement du cortège mycologique prairial indicateur.

**Groupes CHEGD.**

| **Lettre** | **Groupe** | **Genres inclus** |
|:--:|:---|:---|
| C | Clavarioïdes | *Clavaria, Clavulinopsis, Ramariopsis* |
| H | Hygrocybes | *Hygrocybe, Cuphophyllus, Gliophorus, Porpolomopsis* |
| E | Entolomes | *Entoloma* |
| G | Géoglossacées | Famille *Geoglossaceae* ; genres *Geoglossum, Microglossum, Trichoglossum* |
| D | Dermolomes | *Dermoloma, Porpoloma, Camarophyllopsis* |

Groupes fonctionnels pour l’indice patrimonial (méthode CHEGD)

**Formule.**

<div class="formulebox">

``` math
I_{\text{patrimonial}} = \max\!\bigl(n_C,\, n_H,\, n_E,\, n_G,\, n_D\bigr)
```
où $`n_X`$ est le nombre d’espèces uniques du groupe $`X`$ sur le site.

</div>

**Classification en 5 niveaux.**

|     **Seuil**      | **Classe**            |   **Couleur recommandée**   |
|:------------------:|:----------------------|:---------------------------:|
|    $`I \leq 2`$    | Intérêt faible        |       vert très clair       |
|  $`2 < I \leq 5`$  | Intérêt local         |         vert clair          |
| $`5 < I \leq 10`$  | Intérêt régional      |         vert moyen          |
| $`10 < I \leq 14`$ | Intérêt national      |         vert foncé          |
|     $`I > 14`$     | Intérêt international | vert très foncé (`#006D2C`) |

Classes d’intérêt patrimonial (inspirées de la méthode CHEGD)

### Gradient CHEGD et Indice de Représentativité (IR)

**Définition du gradient CHEGD.**

Le gradient CHEGD est le **nombre d’espèces CHEGD uniques observées lors d’une visite**. Il est calculé par site et par visite (visites dérivées des dates observées en mode CSV-only).

Les espèces CHEGD retenues appartiennent aux genres : *Clavaria, Clavulinopsis, Ramariopsis, Hygrocybe, Cuphophyllus, Gliophorus, Porpolomopsis, Entoloma, Geoglossum, Microglossum, Trichoglossum, Dermoloma, Porpoloma, Camarophyllopsis*, ou à la famille *Geoglossaceae*.

**Métriques dérivées par site.**

| **Colonne**             | **Définition**                               |
|:------------------------|:---------------------------------------------|
| `nb_visites_planifiees` | Nombre de visites distinctes (dates)         |
| `gradient_visite_N`     | Nombre d’espèces CHEGD uniques à la visite N |
| `chegd_total`           | Somme des gradients sur toutes les visites   |
| `chegd_moyen`           | Moyenne des gradients par visite             |
| `ir_visite_N`           | Indice de représentativité à la visite N     |
| `ir_moyen`              | Moyenne des IR par visite                    |

Métriques CHEGD exportées par site

**Formule de l’Indice de Représentativité.**

<div class="formulebox">

``` math
IR_{\text{visite}} = \max\!\left(0,\; 1 - \frac{G_{\text{visite}}}{G_{\text{total}}}\right)
```
où :

- $`G_{\text{visite}}`$ : gradient CHEGD de la visite considérée,

- $`G_{\text{total}}`$ : nombre total d’espèces CHEGD distinctes sur l’ensemble des visites du site.

Si $`G_{\text{total}} \leq 0`$, on pose $`IR = 0`$ (pas de division par zéro).

</div>

L’IR moyen par site est la moyenne arithmétique des IR individuels :
``` math
IR_{\text{moyen}} = \frac{1}{V}\sum_{v=1}^{V} IR_{\text{visite}_v}
```

<div class="infobox">

- Un IR proche de **1** indique que le gradient d’une visite est faible par rapport au total du site : la visite apporte peu de nouvelles espèces CHEGD (bon signe de suivi avancé).

- Un IR proche de **0** indique que la visite concentre l’essentiel des espèces CHEGD observées.

- L’IR moyen mesure la **régularité de répartition des espèces CHEGD entre les visites**.

</div>

## Module statistique — Analyse de la fiabilité des déterminations

Le module fiabilité est orchestré par `run_reliability_objectives()` et exécute quatre objectifs séquentiels. Il opère sur les données enrichies par `prepare_reliability_data()`.

### Préparation des données de fiabilité

La fonction `prepare_reliability_data()` enrichit le tableau nettoyé avec :

- `fiabilite` : factor ordonné à 3 niveaux (`Non renseignée < Probable < Certaine`), issu de la normalisation `normalize_reliability_level()`.

- `month_obs` et `season_obs` : mois et saison dérivés de la date (Hiver / Printemps / Été / Automne).

- `abundance` : effectif numérique (0 si NA).

**Normalisation des niveaux de fiabilité.**

| **Préfixes détectés (après normalisation)** | **Classe retournée** |
|:--------------------------------------------|:---------------------|
| `certain`, `sur`, `confirme`                | Certaine             |
| `probable`, `a verifier`, `incertain`       | Probable             |
| Valeur vide, NA, ou non reconnue            | Non renseignée       |

Règles de normalisation des niveaux de fiabilité

### Objectif 1 — Analyse descriptive

**But :** Décrire la distribution des niveaux de fiabilité dans le jeu de données.

**Calcul :** Comptage et pourcentage par niveau.

**Sortie :**

et `fig_stat1_reliability_distribution.{png,pdf}`.

### Objectif 2 — Sélection du schéma de pondération optimal

**But :** Identifier le schéma de pondération des observations par fiabilité qui maximise la cohérence avec les scores de métriques écologiques.

**Schémas évalués :**

| **Schéma** | **$`w_{\text{Certaine}}`$** | **$`w_{\text{Probable}}`$** | **$`w_{\text{Non renseignée}}`$** |
|:--:|:--:|:--:|:--:|
| S1 | 1.0 | 0.7 | 0.3 |
| S2 | 1.0 | 0.8 | 0.5 |
| S3 | 1.0 | 0.6 | 0.2 |

Schémas de pondération candidats

**Critère de sélection :** Corrélation de rang de Spearman entre le score de référence (potentiel + patrimonial + CHEGD) et le score pondéré par site. Le critère secondaire est le chevauchement des 5 premiers sites entre les deux classements.

<div class="formulebox">

``` math
\text{Score}_{\text{pondéré}, s} = \text{Score}_{\text{réf}, s} \times \bar{w}_s
    \qquad \text{avec} \quad
    \bar{w}_s = \frac{1}{n_s}\sum_{i \in s} w_{\text{fiabilite}(i)}
```

</div>

**Sorties :**

- 
- 
- 

### Objectif 3 — Sélection du meilleur modèle prédictif de la fiabilité

**But :** Identifier le modèle statistique prédisant le mieux le niveau de fiabilité d’une observation à partir de ses caractéristiques (site, famille, saison, abondance).

**Modèles candidats.**

| **Identifiant** | **Modèle** | **Description** |
|:---|:---|:---|
| `polr` | Régression ordinale (`MASS::polr`) | Tient compte de l’ordre des classes (Non renseignée \< Probable \< Certaine). Lien logistique (`logistic`). |
| `multinom` | Régression multinomiale (`nnet::multinom`) | Classes traitées de façon nominale, sans contrainte d’ordre. |
| `baseline_majority` | Classifieur majoritaire | Prédit systématiquement la classe la plus fréquente. Sert de référence basse. |

Modèles de classification candidats

**Formule des modèles.**

``` math
\text{fiabilite} \sim \text{abundance} + \text{season} + \text{site} + \text{family}
```

Les modalités de site et de famille les moins fréquentes sont regroupées dans une catégorie `Autre` (les 12 modalités les plus fréquentes sont conservées) pour éviter la sur-paramétrisation et les nouvelles modalités sur la partition de test.

**Protocole d’évaluation.**

Validation croisée $`k = 5`$ folds, avec stratification aléatoire (`set.seed(42)`). Conditions minimales : au moins 20 observations et au moins 2 classes de fiabilité distinctes.

**Métriques d’évaluation.**

| **Métrique** | **Définition** |
|:---|:---|
| Accuracy | Proportion de prédictions correctes. |
| Macro-F1 | Moyenne du F1 par classe (précision × rappel harmonique), pondération uniforme. |
| Log-loss | $`-\frac{1}{n}\sum_{i}\log p_i^*`$ où $`p_i^*`$ est la probabilité prédite pour la vraie classe. Borné dans $`[10^{-15}, 1-10^{-15}]`$. |

Métriques calculées par modèle et par fold

<div class="formulebox">

``` math
F1_{\text{macro}} = \frac{1}{|C|}\sum_{c \in C} F1_c
    \qquad \text{avec} \quad
    F1_c = \frac{2 \times \text{Précision}_c \times \text{Rappel}_c}{\text{Précision}_c + \text{Rappel}_c}
```

</div>

**Sélection :** Meilleur macro-F1 moyen sur les 5 folds ; en cas d’égalité, meilleure accuracy.

**Sorties :** matrices de confusion, probabilités prédites, coefficients du modèle final ajusté sur l’ensemble des données, 3 figures.

### Objectif 4 — Test d’inférence : dépendance fiabilité × site

**But :** Tester statistiquement si la répartition des niveaux de fiabilité est indépendante du site d’observation.

**Sélection automatique du test.**

<div class="tabularx">

Y Y l **Condition** & **Test retenu** & **Identifiant**  
Toutes les cellules attendues $`\geq 5`$ & Chi-2 (`chisq.test`) & `Chi2`  
Au moins une cellule attendue $`< 5`$ & Test exact de Fisher & `Fisher`  
Fisher exact échoue (tableau trop grand) & Fisher avec Monte-Carlo ($`B=10000`$) & `Fisher_simule`  
Tous les tests échouent & Chi-2 de secours & `Chi2_fallback`  

</div>

**Hypothèse nulle.**

``` math
H_0 : \text{La répartition des niveaux de fiabilité est indépendante du site.}
```

**Métrique rapportée :** $`-\log_{10}(p\text{-value})`$ pour faciliter les comparaisons (valeur élevée = rejet de l’indépendance).

**Sorties :** + heatmap site $`\times`$ fiabilité.

### Synthèse du module fiabilité

Un CSV de synthèse consolide les meilleurs candidats et métriques des 4 objectifs.

# Résultats

Les résultats correspondent aux artefacts que le pipeline génère de manière reproductible : résumés descriptifs, indicateurs de qualité, figures et fichiers exportés. Ils ne constituent pas une interprétation biologique d’un jeu de données particulier, mais le contrat de sortie attendu du traitement.

## Résumés descriptifs

La fonction `calc_summaries()` produit cinq agrégations indépendantes :

| **Résumé** | **Fichier CSV** | **Colonnes calculées** |
|:---|:---|:---|
| Par site |  | `nb_lignes, nb_especes_uniques, nb_familles_uniques, abondance_totale, nb_visites` |
| Par famille |  | `nb_especes_uniques, abondance_totale` |
| Par espèce |  | `nb_observations, abondance_totale, nb_sites` |
| Par date |  | `nb_observations, nb_especes_uniques, abondance_totale` |
| Fiabilité |  | `fiabilite, nb_observations, pourcentage` |

Résumés descriptifs produits

Chaque résumé est trié par ordre décroissant de la métrique principale.

## Contrôle qualité des données (QA)

Un bilan de qualité global est exporté dans avec les indicateurs suivants :

- Nombre total de lignes, d’espèces uniques, de familles uniques, d’abondance totale.

- Nombre de sites uniques et de dates uniques.

- Nombre de sites avec potentiel fongique $`> 10`$ (« intéressant ou plus »).

- Nombre de sites avec intérêt patrimonial $`> 2`$ (« local ou plus »).

- Gradient CHEGD moyen global et IR moyen global.

- Indicateur booléen de **cohérence CHEGD** : vérifie que $`\sum_v G_{\text{visite}_v} = G_{\text{total}}`$ pour chaque site (tolérance $`< 10^{-9}`$).

## Figures produites

Toutes les figures sont exportées en **PNG 300 dpi** et en **PDF vectoriel** dans `results/EPFIP_CHEGD/`.

### Figure 1 — Tableau de bord des pelouses

**Fichier :** `fig1_tableau_de_bord_pelouses.{png,pdf}`

Graphique à 3 panneaux horizontaux empilés, un par indicateur :

1.  **Panneau haut** : score du potentiel fongique (barres horizontales, couleur par classe).

2.  **Panneau milieu** : indice de patrimonialité (barres, couleur par classe patrimoniale).

3.  **Panneau bas** : gradient CHEGD moyen (barres, dégradé rouge clair → rouge foncé).

Les sites sont triés par rang décroissant de la somme des trois scores.

### Figure 2 — Positionnement écologique

**Fichier :** `fig2_positionnement_ecologique.{png,pdf}`

Nuage de points :

- Axe X : score de potentiel fongique.

- Axe Y : indice de patrimonialité.

- Taille et couleur des points : gradient CHEGD moyen (dégradé rouge).

- Labels (P1, P2…) via `ggrepel` si disponible, sinon décalés géométriquement.

- Lignes pointillées aux seuils : potentiel $`= 10`$, patrimonial $`= 2`$.

### Figure 3 — Composition du potentiel fongique

**Fichier :** `fig3_composition_potentiel.{png,pdf}`

Barres empilées horizontales : contribution de chaque groupe fonctionnel au score potentiel. Cinq groupes représentés : Cuphophyllus, Hygrocybe (gr. conica), Hygrocybes jaunes, Entoloma, Clavarioïdes. Sites triés par score décroissant.

### Figure 4 — Gradient CHEGD par visite

**Fichier :** `fig4_chegd_par_visite.{png,pdf}`

Barres groupées horizontales : une barre par visite et par site. Sites triés par gradient CHEGD moyen décroissant. Palette de couleur `Set2` (daltonien-compatible).

### Figure 5 — Heatmap des classes

**Fichier :** `fig5_heatmap_classes.{png,pdf}`

Heatmap décisionnelle $`3 \times N_{\text{sites}}`$ :

- Colonnes : Potentiel fongique, Intérêt patrimonial, Gradient CHEGD.

- Couleur : dégradé jaune pâle → vert foncé selon le niveau numérique (1 à 5).

- Annotation textuelle du nom de la classe dans chaque cellule.

- Sites triés par signal total décroissant ($`\text{niveau pot} + \text{niveau pat} + \text{niveau chegd}`$).

### Figure 6 — Niveaux de fiabilité

**Fichier :** `fig6_niveaux_fiabilite.{png,pdf}`

Barres horizontales : distribution des niveaux de fiabilité de détermination. Les observations « Non renseignée » sont colorées en rouge pour signaler les données potentiellement moins fiables.

### Figure 7 — Indice de Représentativité par visite

**Fichier :** `fig7_indice_representativite_ir.{png,pdf}`

Heatmap visites × pelouses : chaque cellule affiche la valeur IR (0–1) avec un dégradé rose clair → vert foncé. Sites triés par IR moyen décroissant.

## Sorties générées — vue d’ensemble

<div class="infobox">

Après génération, les fichiers sont déplacés automatiquement dans l’arborescence thématique : `00_data_prepared`, `10_indices_metiers`, `20_syntheses`, `30_statistiques_modeles`, `40_qa_audits`, `50_figures_metier`, `60_figures_statistiques`.

</div>

### Fichiers CSV

<div class="description">

Tableau brut après nettoyage, enrichi de `date_obs` et `nombre_espece_num`.

Résumé par site : lignes, espèces, familles, abondance, visites.

Résumé par famille taxonomique.

Résumé par espèce : observations, abondance, sites.

Résumé par date de sortie.

Distribution des niveaux de fiabilité.

Alias de compatibilité pour les niveaux de fiabilité rencontrés.

Score, classe et détail par groupe fonctionnel.

Indices par groupe CHEGD, indice global et classe.

Gradient CHEGD par visite, total, moyen et IR.

IR par visite et IR moyen.

Jointure consolidée de toutes les métriques.

Indicateurs globaux de qualité et de synthèse.

Distribution des niveaux de fiabilité.

Évaluation des 3 schémas de pondération.

Meilleur schéma retenu.

Comparaison des modèles (Accuracy, Macro-F1, Log-loss).

Prédictions du meilleur modèle sur tous les folds.

Matrice de confusion.

Coefficients du modèle final.

Résultats du test d’inférence.

Synthèse des 4 objectifs.

QA entrée : synthèse des contrôles.

QA entrée : détail des lignes en anomalie.

QA entrée : indicateurs consolidés.

QA entrée : alertes au-dessus des seuils.

QA CHEGD/IR : détail par site.

QA CHEGD/IR : résumé agrégé.

Journal des étapes non bloquantes en échec (si applicable).

</div>

### Figures

<div class="description">

3 panneaux : potentiel, patrimonial, CHEGD moyen.

Nuage de points : potentiel $`\times`$ patrimonial, taille = CHEGD.

Barres empilées : groupes fonctionnels par site.

Barres groupées : gradient CHEGD par visite et par site.

Heatmap décisionnelle 3 indicateurs $`\times`$ N sites.

Distribution des niveaux de fiabilité.

Heatmap IR visites $`\times`$ pelouses.

Barres : distribution des fiabilités.

Comparaison des 3 schémas de pondération.

Accuracy et Macro-F1 par modèle (CV).

Matrice de confusion du meilleur modèle.

Histogramme des probabilités de confiance.

Heatmap site $`\times`$ fiabilité + résultat test.

</div>

## Système de logging

Un fichier log horodaté est créé dans `logs/` à chaque exécution :

``` math
\texttt{logs/EPFIP\_CHEGD\_YYYYMMDD\_HHMM.log}
```

Le log inclut :

- Un en-tête avec la version du script, le fichier d’entrée et la configuration.

- Des sections (`log_section()`) balisées par des lignes de séparation.

- Des messages d’info, de warning et d’erreur horodatés.

- Un résumé des données (nombre d’observations, espèces, sites, dates).

- La durée totale d’exécution en pied de log.

Les messages sont simultanément écrits dans le fichier log et affichés dans la console.

# Discussion

La discussion explicite la portée décisionnelle des indicateurs, les limites méthodologiques et les situations opérationnelles qui nécessitent un contrôle expert.

## Interprétation des indicateurs

### Score de potentiel fongique

- **Score $`\leq 10`$ (faible)** : cortège CHEGD peu développé ou mal documenté. Effort d’inventaire ou contexte écologique à vérifier.

- **$`10 <`$ Score $`< 30`$ (intéressant)** : présence d’espèces indicatrices notables ; site à suivre et à protéger.

- **Score $`\geq 30`$ (élevé)** : richesse indicatrice remarquable, intérêt écologique fort ; site prioritaire pour la conservation.

<div class="warnbox">

Le score de potentiel est sensible à l’effort d’échantillonnage et à la saison. Un score faible ne signifie pas l’absence d’intérêt, mais peut refléter un inventaire incomplet. Toujours croiser avec l’indice patrimonial et le gradient CHEGD.

</div>

### Indice patrimonial

- $`I \leq 2`$ : site peu ou pas développé pour les CHEGD.

- $`2 < I \leq 5`$ : intérêt local, richesse CHEGD modérée.

- $`5 < I \leq 10`$ : intérêt régional, pelouse à forte valeur indicatrice.

- $`10 < I \leq 14`$ : intérêt national, site exceptionnel à conserver en priorité.

- $`I > 14`$ : intérêt international, richesse CHEGD exceptionnelle.

### Gradient CHEGD moyen

Un gradient CHEGD élevé par visite signale une pression de CHEGD constante sur les visites : la pelouse héberge un cortège CHEGD abondant et régulièrement exprimé. Un gradient faible peut indiquer soit une faible richesse CHEGD, soit une forte saisonnalité.

### IR moyen

- IR proche de 1 sur toutes les visites : les espèces CHEGD sont bien réparties entre les visites — signe d’un suivi équilibré ou d’une forte richesse totale.

- IR faible sur une visite : cette visite concentre une grande partie du pool CHEGD du site.

- IR moyen global élevé : bonne représentativité globale du suivi.

### Lecture conjointe des figures 1 et 2

La Figure 1 permet une lecture rapide et comparative par site sur les 3 dimensions. La Figure 2 révèle les **profils écologiques** :

- Sites en haut à droite : forte valeur patrimoniale et potentiel élevé (sites prioritaires).

- Sites en bas à gauche : faible valeur sur les deux axes (à renforcer en effort ou à contextualiser).

- Points gros et rouges : gradient CHEGD élevé — sites à enjeu fort de suivi.

## Limites et perspectives

La portée des indicateurs dépend directement de la qualité taxonomique, de l’effort d’échantillonnage, de la saisonnalité et de la complétude des visites. Un score faible ne doit pas être interprété comme une absence d’intérêt écologique sans vérification du contexte de prospection. Les évolutions prioritaires concernent la validation sur plusieurs campagnes, l’ajout de diagnostics d’effort d’inventaire et la documentation systématique des changements méthodologiques dans le journal de versionnement.

## Dépannage (FAQ)

Le script ne trouve pas le fichier d’entrée.  
Vérifier qu’un fichier `.csv` est présent dans `data/`. Le nom est résolu par correspondance normalisée : les accents et la casse ne sont pas bloquants. Consulter les messages `info` dans la console pour identifier le fichier retenu.

Colonnes manquantes à l’exécution.  
Le script lève une erreur explicite listant les colonnes introuvables. Vérifier que les noms de colonnes dans `get_embedded_config()$columns` correspondent exactement aux en-têtes du fichier d’entrée (y compris accents et espaces).

Aucune espèce CHEGD détectée / gradients tous à zéro.  
Vérifier que les noms d’espèces sont bien en format binomial latin (*Genre espèce*). La normalisation est insensible aux accents mais requiert un espace entre le genre et l’épithète. Contrôler dans les colonnes `species_norm` et `genus`.

Le module fiabilité affiche « insuffisant ».  
Le module requiert $`\geq 20`$ observations avec au moins 2 niveaux de fiabilité distincts. Si non rempli, les métriques statistiques sont exportées comme `NA`.

Les figures sont vides ou absentes.  
Vérifier que `site_metrics$combined` n’est pas vide. Un tableau d’entrée sans identifiant de site numérique (regex  
`d+`) produira un référentiel de sites vide : toutes les métriques seront nulles.

Incohérence CHEGD signalée dans .  
L’indicateur `coherence_chegd_gradients_ok` vaut 0 si la somme des gradients par visite diffère du total CHEGD d’au moins $`10^{-9}`$. Cela peut survenir si les dates d’observation comportent des doublons ou des valeurs manquantes.

# Annexe — Quick Start

## Étape 1 — Préparer les données

Placer le fichier d’observations dans `data/`, par exemple :

    data/donnees_recoltes_chegd_pelouses.csv

Le script tolère les variantes orthographiques et les accents manquants grâce à la résolution normalisée (§ <a href="#sec:config" data-reference-type="ref" data-reference="sec:config">2.2</a>).

## Étape 2 — Configurer (optionnel)

Modifier la fonction `get_embedded_config()` dans le script pour adapter :

- `input_file` : chemin vers le fichier d’entrée.

- `columns` : noms de colonnes si le fichier utilise un autre vocabulaire.

## Étape 3 — Lancer l’analyse

Depuis la racine du projet :

    Rscript scripts/Evaluation_Potentiel_Fongique_Interets_Patrimoniaux_CHEGD.R

Ou interactivement sous RStudio / VSCode en ouvrant le script et en l’exécutant.

## Étape 4 — Consulter les résultats

Toutes les sorties sont dans :

    results/EPFIP_CHEGD/

# Glossaire

| **Acronyme/terme** | **Définition** |
|:---|:---|
| **CHEGD** | Groupe indicateur des prairies : **C**lavaria, **H**ygrocybe/Cuphophyllus, **E**ntoloma, **G**eoglossaceae, **D**ermoloma. |
| **IR** | Indice de Représentativité : mesure la proportion de « nouveauté » CHEGD d’une visite par rapport au total du site. |
| **Gradient CHEGD** | Nombre d’espèces CHEGD uniques observées lors d’une visite donnée. |
| **Potentiel fongique** | Score pondéré de richesse fonctionnelle CHEGD d’un site. |
| **Indice patrimonial** | Maximum de la richesse CHEGD parmi les 5 groupes du site. |
| **Polr** | Proportional Odds Logistic Regression — régression logistique ordinale (`MASS::polr`). |
| **Multinom** | Régression multinomiale (`nnet::multinom`). |
| **Macro-F1** | Moyenne des F1 individuels par classe, pondération uniforme. |
| **Log-loss** | Entropie croisée — mesure la calibration probabiliste d’un classifieur. |
| **QA** | Quality Assurance — contrôle de qualité des données. |

# Références

- Sellier, Y., et coll. (s.d.). *Évaluation du potentiel fongique et de l’intérêt patrimonial des pelouses*. Mycofrance. <https://www.mycofrance.fr/wp-content/uploads/2025/05/Bull.-SMF-131-1-2-Y-Sellier-et-coll.pdf>.

- Harding, J.S. & al. (2012). *Grassland fungi as biodiversity indicators*.

- Methode CHEGD : Rotheroe, M. & al. (1996). *Waxcap grasslands : an assessment of the British resource.* English Nature Research Reports.

- Cours 24 Inventaires — DU Mycologie 2026 du Professeur Pierre-Arthur Moreau, Université de Lille (UFR3S PHAR).

- Wickham, H. (2016). *ggplot2: Elegant Graphics for Data Analysis*. Springer.

- Venables, W.N. & Ripley, B.D. (2002). *Modern Applied Statistics with S*. Springer. (`MASS::polr`)

- Ripley, B. (2022). *nnet: Feed-Forward Neural Networks and Multinomial Log-Linear Models*. R package.

# Contact et versionnement

|                         |                                    |
|:------------------------|:-----------------------------------|
| **Auteur**              | Eddy Boite                         |
| **Dépôt GitHub**        | `eddyboite-nat/myco_apps_releases` |
| **Branche**             | `main`                             |
| **Version script**      | 1.1                                |
| **Date de ce document** | 9 juillet 2026                     |

Pour toute évolution du script, ouvrir une issue dans le dépôt GitHub ou documenter les changements dans le journal `CHANGELOG.md` du projet.
