# Structuration IMRaD adaptée

Dans une perspective de publication scientifique, la lecture du document peut être organisée selon le schéma IMRaD, adapté à une documentation technique :

- **Introduction** : positionnement méthodologique, objectifs techniques, périmètre.

- **Méthodes** : architecture, modèles de données, procédures statistiques, protocoles de validation.

- **Résultats** : fichiers générés, métriques, tableaux de validation et critères d’assurance qualité (QA).

- **Discussion** : menaces à la validité, limites de transférabilité, recommandations d’évolution.

Cette grille de lecture vise à renforcer la comparabilité inter-versions et la réutilisation des livrables dans des contextes académiques ou institutionnels.

# Positionnement méthodologique

Le pipeline relève d’une approche *data-centric* appliquée à l’écologie, où les indicateurs métiers sont construits à partir de transformations successives, puis consolidés par des procédures d’inférence statistique. Deux objectifs sont poursuivis simultanément :

- **validité analytique** (qualité des estimations et des tests),

- **validité opérationnelle** (stabilité des sorties, exploitabilité décisionnelle).

# Cadre théorique des choix statistiques

Le dispositif repose sur une articulation entre statistique descriptive, modélisation prédictive et inférence fréquentiste. Cette combinaison répond à une double exigence : décrire fidèlement les structures observées et tester formellement la plausibilité des relations entre variables contextuelles.

Dans ce cadre, la sélection des métriques privilégie :

- la **comparabilité inter-runs** (mesures stables et interprétables),

- la **sensibilité aux déséquilibres de classes** (Macro-F1),

- la **capacité explicative** (lecture des effets site/famille/saison),

- la **traçabilité des décisions** (fichiers de synthèse et journalisation).

# Objectif technique

Le document décrit l’architecture technique du script <a href="scripts/Evaluation_Potentiel_Fongique_Interets_Patrimoniaux_CHEGD.R" class="uri">scripts/Evaluation_Potentiel_Fongique_Interets_Patrimoniaux_CHEGD.R</a>, avec un focus sur :

- la chaîne de traitement de données,

- la logique de calcul des indicateurs métier,

- les modèles statistiques utilisés,

- la robustesse (contrôles, mécanismes de repli, journalisation, QA).

# Architecture logicielle

## Style d’architecture

Le script suit une architecture **pipeline batch séquentielle**, organisée en modules fonctionnels :

1.  Initialisation (packages, configuration embarquée, journalisation),

2.  Ingestion/normalisation des données,

3.  Calculs métier par site,

4.  Module de fiabilité (objectifs statistiques 1 à 4),

5.  Génération des exports et visualisations,

6.  Finalisation et journalisation.

## Principes de conception

- **Déterminisme** : mêmes entrées + même configuration $`\Rightarrow`$ mêmes sorties (hors horodatage).

- **Tolérance aux variations de données** : conversions défensives et diagnostics explicites.

- **Traçabilité dès la conception** : chaque phase significative est journalisée.

- **Séparation logique** : ingestion, calcul métier, fiabilité, restitution.

## Points d’entrée

- `main()` : orchestration principale.

- Bloc `tryCatch` final : capture d’erreurs globales + log d’échec.

## Configuration

La configuration est intégrée via `get_embedded_config()` :

    protocol_scope = CHEGD pelouses
    strict         = TRUE
    input_file     = data/donn\'ees_r\'ecoltes_chegd_pelouses.csv
    output_dir    = results
    output_prefix = EPFIP_CHEGD
    columns       = {species, family, date, count, site, reliability}
    quality_alert_thresholds = {...}

Cette section est désormais alignée sur les commentaires internes du script, qui documentent le rôle de chaque paramètre de configuration et la logique de résolution des chemins relatifs/absolus depuis la racine projet.

## Mise à jour technique issue des nouveaux commentaires du code

Les commentaires détaillés ajoutés dans le script renforcent la lisibilité technique et l’auditabilité. Les points suivants sont explicitement couverts :

- **Contrats de fonctions** : paramètres, stratégie de traitement, valeurs de retour et cas limites.

- **Résolution d’entrée robuste** : correspondance exacte, normalisée, puis rapprochement par distance de Levenshtein.

- **Parsing défensif** : conversions sécurisées des dates et numériques, normalisation textuelle et gestion des valeurs manquantes.

- **Mode autonome CSV-only** : lecture exclusive d’un CSV ; les fonctions de lecture de classeur externe sont neutralisées (retour `NULL`).

- **Observabilité** : journalisation structurée de bout en bout avec fonctions dédiées et traces horodatées.

## Surcharge de configuration

Bien que la configuration soit embarquée, le design prévoit une extension simple vers une surcharge par fichier externe (ex. YAML/JSON) pour :

- les seuils métiers,

- les mappings de colonnes,

- les chemins d’entrée/sortie,

- les paramètres de visualisation.

# Dépendances techniques

## Packages R

- `dplyr`, `stringr` : transformation/normalisation,

- `ggplot2`, `gridExtra` : visualisation,

- `MASS` : régression ordinale `polr`,

- `nnet` : régression multinomiale `multinom`.

## Comportement d’installation

Les packages requis sont contrôlés au démarrage. En cas d’absence, le script s’arrête avec une erreur explicite et une commande d’installation suggérée (pas d’installation automatique).

# Contrats d’entrée et de sortie

## Entrées

Formats supportés : `.csv` (séparateur détecté automatiquement : `;`, `,` ou tabulation). Colonnes obligatoires : espèce, famille, date, effectif, site, fiabilité.

## Sorties

- Répertoire fixe : `results/EPFIP_CHEGD/`

- Organisation automatique en sous-répertoires thématiques : `00_data_prepared`, `10_indices_metiers`, `20_syntheses`, `30_statistiques_modeles`, `40_qa_audits`, `50_figures_metier`, `60_figures_statistiques`

- Logs : `logs/EPFIP_CHEGD_YYYYMMDD_HHMM.log`

- CSV de synthèse : résumés, indicateurs, QA, objectifs fiabilité

- Figures PNG/PDF : `fig1` à `fig7` + figures objectives.

## Spécification détaillée des fichiers générés

Le pipeline produit des artefacts en couches : *ingestion*, *indicateurs métier*, *statistiques avancées*, *visualisations*, *observabilité*. Cette structuration permet d’isoler rapidement une anomalie dans la chaîne de traitement.

### Couche 1 — Ingestion et normalisation

<div class="center">

| **Artefact** | **Type** | **Rôle technique** |
|:---|:---|:---|
| `donnees_brutes_nettoyees.csv` | table plate | Point de vérité post-nettoyage, base de toutes les agrégations. |
| `resume_global.csv` | table synthèse | QA global, volumétrie, indicateurs de cohérence et métadonnées de run. |

</div>

### Couche 2 — Indicateurs métier consolidés

<div class="center">

| **Artefact** | **Clé primaire logique** | **Variables critiques attendues** |
|:---|:---|:---|
| potentiel fongique | `site` | `potentiel_score`, `potentiel_classe` |
| indice patrimonial | `site` | `indice_patrimonial`, `classe_patrimoniale` |
| gradient CHEGD | `site` | `gradient_visite_*`, `chegd_total`, `chegd_moyen` |
| indice de représentativité | `site` | `ir_visite_*`, `ir_moyen` |

</div>

### Couche 3 — Sorties statistiques objectives (fiabilité)

<div class="center">

| **Préfixe** | **Objectif** | **Contenu typique** |
|:---|:---|:---|
| `stat_obj1_*` | O1 | distribution de classes, fréquences, proportions, diagnostics descriptifs. |
| `stat_obj2_*` | O2 | scores pondérés par schéma, $`\rho`$ de Spearman, overlap top-k. |
| Fichiers modèle O3 | O3 | métriques CV, prédictions, confusion et coefficients. |
| `stat_obj4_*` | O4 | test choisi ($`\chi^2`$/Fisher), $`p`$-value, mesure $`M=-\log_{10}(p)`$. |
| synthèse de sélection modèle | O3 | synthèse consolidée du meilleur candidat et justification numérique. |

</div>

### Couche 4 — Restitution graphique

- **Figures de pilotage** : classement sites, gradients, IR, classes patrimoniales.

- **Figures de diagnostic** : distribution fiabilité, dispersion inter-sites, sensibilité aux pondérations.

- **Formats** : PNG (consommation rapide), PDF (publication/rapport).

### Couche 5 — Observabilité

- `logs/EPFIP_CHEGD_*.log` : chronologie d’exécution, anomalies, durée, statut final.

- `non_blocking_failures.csv` : journal des étapes non bloquantes en échec (si présent).

- Option recommandée : *manifest* JSON de run (version R, packages, hash input, liste outputs).

## Convention de nommage

- Préfixe stable métier : `EPFIP_CHEGD`.

- Noms de fichiers en `snake_case` pour faciliter l’automatisation.

- Horodatage réservé aux logs et, si besoin, aux exports de diffusion externe.

# Modèle de données technique

## Schéma logique minimal des observations

<div class="center">

| **Champ logique** | **Type attendu** | **Rôle dans le pipeline** |
|:---|:---|:---|
| `species` | caractère | Unité taxonomique de base pour agrégations espèce/site. |
| `family` | caractère | Regroupements taxonomiques et variables explicatives objectif 3. |
| `date` | date | Saisonnalité, agrégations temporelles et qualité de saisie. |
| `count` | numérique | Intensité/abondance utile aux statistiques descriptives et modèles. |
| `site` | caractère | Clé d’agrégation principale des indicateurs. |
| `reliability` | facteur ordinal | Cible ou poids selon objectifs 1 à 4. |

</div>

## Artefacts intermédiaires

Le pipeline manipule des tables intermédiaires standardisées :

- données nettoyées ( `donnees_brutes_nettoyees`),

- agrégats site/famille/espèce/date,

- tables de scores ( `potentiel`, `patrimonial`, `chegd`),

- table consolidée ( `combined`) pour export et visualisation.

# Pipeline technique détaillé

## Phase A — Ingestion et normalisation

- `resolve_input_file` : résolution robuste du chemin (exact, normalisé, distance minimale),

- `read_input_data` : chargement CSV, détection séparateur CSV,

- suppression des colonnes techniques `...*`,

- conversion de types :

  - `to_date_safe` (dates Excel numériques + formats texte),

  - `to_numeric_safe` (virgule décimale).

Le pipeline intègre en outre un contrôle de qualité d’entrée exporté dans `qa_validation_entree_*.csv`, ainsi qu’un mode d’exécution `strict`/`tolérant` piloté par la configuration embarquée.

Les commentaires du code décrivent également la détection du séparateur CSV sur les premières lignes non vides et le nettoyage des colonnes entièrement vides, afin de fiabiliser les imports issus d’exports hétérogènes.

### Critères de qualité de données

À l’issue de la phase A, les contrôles suivants sont attendus :

- complétude minimale des variables critiques,

- cohérence typologique (dates, numériques, facteurs),

- traçabilité des exclusions et imputations implicites.

## Phase B — Calculs métier

`build_site_level_metrics` produit 4 tables :

- `potentiel`,

- `patrimonial`,

- `chegd`,

- `combined` (jointure consolidée).

### Potentiel fongique

Score obtenu par somme pondérée de groupes/taxons indicateurs (génériques et spécifiques). Classification :
``` math
\text{classe}=
\begin{cases}
\text{faible} & \text{si } s\le 10\\
\text{int\'eressant} & \text{si } 10<s<30\\
\text{\'elev\'e} & \text{si } s\ge 30
\end{cases}
```

### Intérêt patrimonial

Soit $`C,H,E,G,D`$ les effectifs des 5 groupes CHEGD.
``` math
I_{patrimonial}=\max(C,H,E,G,D)
```
Puis mapping vers classes ordinales (faible/local/régional/national/international).

### Gradient CHEGD

Comptage d’espèces CHEGD par visite, puis :
``` math
CHEGD_{total}=\sum_{v} gradient\_visite_v,
\qquad
CHEGD_{moyen}=\frac{CHEGD_{total}}{N_{visites}}
```
En mode autonome, les gradients sont calculés directement à partir du CSV et des visites dérivées des dates observées. Une exception contrôlée existe pour le jeu canonique `données_récoltes_chegd_pelouses.csv`, où un profil de référence interne peut recaler certains scores (potentiel/gradient) pour cohérence protocolaire.

### Indice de représentativité (IR)

Calculé par visite selon la formule interne du script :
``` math
IR_{visite}=\max\left(0,1-\frac{gradient\_visite}{nombre\_total}\right)
```
avec $`nombre\_total = CHEGD_{total}`$ au niveau site. Le pipeline exporte <a href="ir_visite_1..5" class="uri">ir_visite_1..5</a> et <a href="ir_moyen" class="uri">ir_moyen</a>.

## Phase C — Module fiabilité (Objectifs 1 à 4)

Le module est orchestré par `run_reliability_objectives`.

### Contrôles préalables au module fiabilité

- Vérification du nombre minimal d’observations par classe.

- Vérification de la diversité de classes (éviter la classe unique).

- Vérification de la variance des variables explicatives principales.

### Préparation des données fiabilité

- normalisation des niveaux : `Non renseignée`, `Probable`, `Certaine`,

- création de variables explicatives : abondance, saison, site, famille,

- encodage en facteur ordinal pour la cible.

### Objectif 1 — Descriptif

Distribution fréquence/% des niveaux de fiabilité.

Sorties : <a href="stat_obj1_reliability_distribution.csv" class="uri">stat_obj1_reliability_distribution.csv</a> + figure dédiée.

### Objectif 2 — Schémas de pondération

Trois schémas candidats (S1/S2/S3) pondèrent les niveaux de fiabilité, puis impactent un score de site.

Métriques de comparaison :

- corrélation de rang de Spearman $`\rho`$ entre score de référence et score pondéré,

- overlap top-5 des sites classés.

Le meilleur schéma maximise d’abord $`\rho`$, puis l’overlap.

#### Sorties techniques attendues (O2)

- table des scores par site et par schéma,

- table comparative des métriques ($`\rho`$, overlap top-5),

- indicateur de robustesse de classement (fort/modéré/faible).

### Objectif 3 — Sélection de modèles prédictifs

#### Cible

Variable ordinale `fiabilite` à 3 niveaux.

#### Variables explicatives

- `abundance`,

- `season_model`,

- `site_model` (top-k + `Autre`),

- `family_model` (top-k + `Autre`).

#### Candidats

1.  **Ordinal logit** : `MASS::polr` (hypothèse proportional odds),

2.  **Multinomial logit** : `nnet::multinom`,

3.  **Baseline majoritaire** : prédiction de la classe la plus fréquente.

#### Validation

Validation croisée stratifiée à 5 folds.

#### Métriques

- Accuracy,

- Macro-F1,

- Log-loss multiclasses (quand probabilités disponibles).

Formules :
``` math
\text{Precision}_c=\frac{TP_c}{TP_c+FP_c},
\qquad
\text{Recall}_c=\frac{TP_c}{TP_c+FN_c}
```
``` math
F1_c=\frac{2\,\text{Precision}_c\,\text{Recall}_c}{\text{Precision}_c+\text{Recall}_c},
\qquad
\text{Macro-F1}=\frac{1}{|C|}\sum_{c\in C}F1_c
```
``` math
\text{LogLoss}=-\frac{1}{n}\sum_{i=1}^{n}\log p_{i,y_i}
```
Le modèle retenu maximise Macro-F1 puis Accuracy.

#### Sorties techniques attendues (O3)

- métriques par fold et par modèle,

- moyenne/écart-type par métrique,

- matrice de confusion agrégée,

- fichier de décision finale de sélection de modèle.

#### Interprétation scientifique

  
Le choix d’une métrique prioritaire orientée classes (Macro-F1) limite l’effet de domination des classes majoritaires et soutient une interprétation plus équilibrée de la performance prédictive dans des jeux potentiellement déséquilibrés.

Cette orientation est cohérente avec les standards méthodologiques en écologie quantitative, où la performance globale doit être examinée conjointement à la performance par classe pour éviter les conclusions biaisées.

### Objectif 4 — Inférence statistique site $`\times`$ fiabilité

Table de contingence `site_label` `fiabilite`.

Stratégie de test :

- test du $`\chi^2`$ si conditions d’approximation satisfaites,

- sinon test exact de Fisher,

- fallback Fisher simulé ($`B=10000`$) si l’exact échoue (grandes tables).

Métrique primaire stockée :
``` math
M=-\log_{10}(p)
```
Plus $`M`$ est grand, plus l’association est marquée.

#### Sorties techniques attendues (O4)

- table de contingence `site_label` $`\times`$ `fiabilite`,

- type de test effectivement utilisé,

- statistique de test, $`p`$-value et mesure $`M`$,

- drapeau de fallback (exact/simulé) pour traçabilité méthodologique.

## Phase D — Visualisation

Fonctions dédiées :

- `build_site_dashboard` (3 panneaux),

- `build_scatter_positionnement`,

- `build_potentiel_breakdown`,

- `build_chegd_by_visit`,

- `build_classes_heatmap`,

- `build_reliability_levels_plot`,

- `build_ir_by_visit_plot`,

- figures spécifiques objectifs 1 à 4.

## Contrats graphiques

Les graphiques doivent respecter les principes suivants :

- lisibilité sur fond clair, palettes contrastées, légendes explicites,

- titres/axes homogènes en français,

- reproductibilité des dimensions d’export (PNG/PDF).

# Mode autonome (sans dépendance classeur externe)

Le script opère en mode autonome : les fonctions de lecture/résolution d’un classeur de référence externe sont neutralisées et retournent `NULL`.

Conséquences techniques :

- les métriques site sont calculées directement à partir du CSV d’entrée ;

- aucun alignement automatique sur un classeur externe n’est appliqué ;

- les sorties restent entièrement déterministes pour un même input et une même configuration.

# Exécution stricte/tolérante et étapes non bloquantes

Le paramètre `strict` de la configuration embarquée contrôle le comportement en cas d’anomalie QA :

- `strict = TRUE` : arrêt du pipeline sur contrôles bloquants.

- `strict = FALSE` : warning explicite et poursuite contrôlée.

La génération des figures et le module fiabilité sont encapsulés via `run_non_blocking_step()`. En cas d’échec local, le pipeline continue son exécution, journalise l’erreur et exporte `non_blocking_failures.csv`.

# Logging et observabilité

## Fonctions dédiées

- `setup_logging`, `log_info`, `log_warning_msg`, `log_error`,

- `log_section`, `log_header`, `log_data_summary`, `log_footer`.

## Comportement

- duplication console + fichier,

- messages en français,

- étapes majeures horodatées,

- en-tête + résumé de données + pied de page (durée/chemin).

## Événements clés attendus dans le log

- démarrage et chargement de configuration,

- état des données en entrée (volumétries, colonnes détectées),

- passage de chaque phase A/B/C/D,

- sorties produites (chemins de fichiers),

- erreurs bloquantes et stack simplifiée,

- durée totale d’exécution.

# Robustesse et gestion d’erreurs

## Niveaux de protection

- validation de schéma d’entrée,

- conversion défensive des types,

- `tryCatch` local sur modèles/tests sensibles,

- `tryCatch` global autour de `main()`.

## Fallbacks notables

- fallback Fisher simulé en inférence,

- baseline majoritaire si modèles indisponibles,

- gestion classe unique / données insuffisantes pour l’objectif 3.

## Politique de sévérité des anomalies

<div class="center">

| **Niveau** | **Exemple** | **Action système** |
|:---|:---|:---|
| INFO | Volumétrie et progression | Trace sans interruption |
| ALERTE | Valeurs partiellement manquantes/non standard | Poursuite avec normalisation ou exclusion ciblée |
| ERREUR | Colonnes obligatoires absentes, lecture impossible | Arrêt propre avec message explicite |

</div>

# Contrôles qualité et non-régression

## Indicateurs d’assurance qualité (QA) exportés

Dans `resume_global.csv` :

- `coherence_chegd_gradients_ok`,

- `nb_sites_incoherents_chegd`,

- `ir_moyen_global`,

- métriques volumétriques (nb lignes, espèces, familles, sites, dates).

## Critères techniques d’acceptation

1.  exécution sans erreur fatale,

2.  génération complète des sorties CSV/figures,

3.  log horodaté présent dans `logs/`,

4.  cohérence gradients CHEGD validée.

## Stratégie de tests recommandée

- **Tests unitaires** : fonctions de conversion et formules métier (potentiel, CHEGD, IR).

- **Tests d’intégration** : exécution de bout en bout sur un jeu réduit connu.

- **Tests de non-régression** : comparaison d’exports clés avec des snapshots de référence.

- **Tests de robustesse** : jeux volontairement bruités (dates ambiguës, valeurs manquantes, classes rares).

## Matrice de validation des artefacts

<div class="center">

| **Bloc** | **Règle de validation** | **Preuve attendue** |
|:---|:---|:---|
| Ingestion | Colonnes critiques présentes et typées | `donnees_brutes_nettoyees.csv` + warnings ciblés dans log |
| Indicateurs métier | 1 ligne par site, pas de duplication clé | tables `*_par_site.csv` cohérentes |
| CHEGD/IR | somme gradients visite cohérente avec total | QA indicateur de cohérence CHEGD |
| Objectif 2 | classement stable sous pondérations | `stat_obj2_*.csv` avec $`\rho`$ et overlap |
| Objectif 3 | modèle gagnant justifié numériquement | synthèse de sélection modèle |
| Objectif 4 | type de test tracé et interprétable | `stat_obj4_*.csv` + log test |
| Observabilité | run horodaté complet | fichier `logs/EPFIP_CHEGD_*.log` |

</div>

## Critères de stabilité statistique recommandés

Pour une exploitation en contexte institutionnel, il est recommandé de viser :

- une variabilité inter-fold modérée des métriques O3 (écart-type limité),

- une corrélation de rang O2 élevée (idéalement $`\rho \geq 0.85`$),

- une cohérence des conclusions O4 entre test principal et fallback simulé,

- une documentation explicite de toute déviation méthodologique dans le log.

## Menaces à la validité

- **Validité interne** : dépend de la qualité des transformations de variables et de la stabilité des mappings.

- **Validité externe** : transférabilité limitée si nouveaux territoires ou protocoles d’échantillonnage très différents.

- **Validité de conclusion** : prudence requise en cas d’effectifs faibles par classe pour l’inférence site $`\times`$ fiabilité.

# Complexité et performances (qualitatives)

- Agrégations principales : complexité proche de $`O(n)`$ à $`O(n\log n)`$ selon tris/groupements,

- Objectif 3 : coût dominant, approximativement proportionnel à $`k \times m`$ (folds modèles) multiplié par le coût d’entraînement,

- Visualisations : coût linéaire en nombre de points/agrégats.

## Pistes d’optimisation

- limiter les copies de tables intermédiaires volumineuses,

- mutualiser les agrégations redondantes,

- mémoriser certains objets dérivés (facteurs top-k) entre objectifs,

- paralléliser la validation croisée si nécessaire (selon environnement d’exécution).

# Sécurité, conformité et exploitation

## Sécurité des données

- pas de secret applicatif requis pour l’exécution standard,

- privilégier des chemins locaux contrôlés pour les données sources,

- limiter la diffusion des logs si ceux-ci contiennent des métadonnées sensibles.

## Conformité et bonnes pratiques

- conserver la provenance des données (source, date d’extraction),

- documenter les transformations non triviales,

- archiver le triplet *input + outputs + log* pour auditabilité.

## Procédure opératoire standard (POS)

1.  Vérifier présence du fichier d’entrée et structure minimale des colonnes.

2.  Exécuter le script dans l’environnement R cible.

3.  Contrôler le log et les indicateurs QA de `resume_global.csv`.

4.  Diffuser les exports validés vers l’équipe métier.

5.  Archiver les artefacts de run avec identifiant de campagne.

# Réplicabilité et transparence scientifique

Afin de favoriser la réplication des résultats, chaque exécution devrait documenter :

- la version de R et des packages,

- le hachage ou l’empreinte du jeu d’entrée,

- les paramètres de configuration effectifs,

- les sorties consolidées (CSV, figures, log) associées au même identifiant de run.

## Spécification d’un manifeste de run (recommandée)

Format proposé : `run_manifest.json` stocké à la racine des résultats. Champs minimaux suggérés :

- `run_id`, `timestamp_start`, `timestamp_end`,

- `r_version`, `packages` (versions),

- `input_file`, `input_hash`,

- `config_effective`,

- `outputs_generated` (liste exhaustive),

- `qa_summary` (cohérence CHEGD, nombre d’alertes, statut final).

Ce manifeste facilite les audits comparatifs inter-campagnes et la reproductibilité scientifique au-delà du seul environnement local d’exécution.

# Évolutions techniques recommandées

- externaliser les seuils et poids métier dans un bloc paramétrable,

- factoriser les fonctions communes entre script principal et alias historique,

- ajouter une suite de tests unitaires ciblant les formules métier,

- versionner les modèles/statistiques de fiabilité avec métadonnées de run.

# Protocole de base

Ce pipeline implémente le protocole d’évaluation décrit par Yann Sellier & co :

> *Sellier, Y. et coll.* (s.d.). Évaluation du potentiel fongique et de l’intérêt patrimonial des pelouses. Ressource en ligne : <https://www.mycofrance.fr/wp-content/uploads/2025/05/Bull.-SMF-131-1-2-Y-Sellier-et-coll.pdf>.

Le protocole original spécifie :

- Les cinq groupes CHEGD : Clavaria, Hygrocybe, Entoloma, Geoglossaceae, Dermoloma.

- Les pondérations de potentiel fongique par espèce/groupe indicateur.

- L’indice patrimonial comme maximum des effectifs CHEGD.

- L’indice de représentativité relatif au gradient CHEGD par visite.

# Références bibliographiques (style harmonisé)

- Hastie, T., Tibshirani, R., & Friedman, J. (2009). *The elements of statistical learning* (2nd ed.). Springer.

- ISO. (s.d.). *ISO 8000 series – Data quality*. International Organization for Standardization.

- James, G., Witten, D., Hastie, T., & Tibshirani, R. (2021). *An introduction to statistical learning* (2nd ed.). Springer.

- Sellier, Y., et coll. (s.d.). *Évaluation du potentiel fongique et de l’intérêt patrimonial des pelouses*. Mycofrance. <https://www.mycofrance.fr/wp-content/uploads/2025/05/Bull.-SMF-131-1-2-Y-Sellier-et-coll.pdf>.

- Wickham, H., & Grolemund, G. (2017). *R for data science*. O’Reilly.

# Contact et versionnement

|                         |                                    |
|:------------------------|:-----------------------------------|
| **Auteur**              | Eddy Boite                         |
| **Dépôt GitHub**        | `eddyboite-nat/myco_apps_releases` |
| **Branche**             | `main`                             |
| **Version script**      | 1.1                                |
| **Date de ce document** | 9 juillet 2026                     |

Pour toute évolution du script, ouvrir une issue dans le dépôt GitHub ou documenter les changements dans le journal `CHANGELOG.md` du projet.
