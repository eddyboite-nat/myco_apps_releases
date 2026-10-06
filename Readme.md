# Présentation

Ce dépôt publie des scripts R prêts à l’emploi issus de projets de mycologie et d’écologie. Chaque application est fournie avec ses données d’exemple, son script principal, une documentation d’utilisation et des répertoires de sortie standardisés.

# Applications disponibles

<div class="description">

Script ICR version 1.4, dédié à l’analyse de la complétude d’inventaires et à la représentativité des observations par site, date et espèce.

Script EPFIP-CHEGD version 1.0, dédié au calcul du potentiel fongique, de l’indice patrimonial, du gradient CHEGD et de l’indice de représentativité.

</div>

# Structure du dépôt

<div class="CodeBlock">

myco_apps_releases/ \|– data/ \# Donnees d’exemple \|– docs/ \# Documentation \|– logs/ \# Journaux d’execution \|– results/ \# Resultats generes \| \|– ICR/ \| ‘– EPFIP_CHEGD/ \|– scripts/ \# Scripts R principaux ‘– README.pdf

</div>

# Interface web locale

Une interface Shiny locale permet de lancer les scripts sans modifier leur code. Elle fonctionne depuis le poste utilisateur et s’appuie sur les dossiers `scripts/`, `data/`, `logs/` et `results/`.

## Lancement

- Pour macOS, double-cliquer sur `Lancer_Mac.command`.

- Pour Windows, double-cliquer sur `Lancer_Windows.bat`.

# Quick Start CHEGD

1.  Vérifier que R est installé sur la machine.

2.  Placer le fichier d’entrée dans `data/` ou sélectionner un fichier depuis l’interface.

3.  Lancer le script CHEGD depuis l’interface ou avec `Rscript`.

4.  Consulter les résultats dans `results/EPFIP_CHEGD/`.

## Données CHEGD attendues

| **Colonne**               | **Rôle**                                   |
|:--------------------------|:-------------------------------------------|
| `Espèces`                 | Nom scientifique observé.                  |
| `Famille`                 | Famille taxonomique.                       |
| `Date`                    | Date d’observation.                        |
| `Nombre d’espèce`         | Abondance ou effectif.                     |
| `Site`                    | Site ou pelouse inventoriée.               |
| `Fiabilité détermination` | Niveau de confiance dans la détermination. |

## Sorties CHEGD

Les sorties principales sont les fichiers de synthèse par site, les tableaux de potentiel fongique, les indices patrimoniaux, les gradients CHEGD, les indices de représentativité, les figures au format PNG/PDF et les journaux d’exécution.

# Quick Start ICR

1.  Vérifier que R est installé et accessible dans le terminal.

2.  Préparer un fichier d’observations avec les colonnes attendues.

3.  Lancer l’analyse ICR depuis l’interface ou avec `Rscript`.

4.  Consulter les résultats dans `results/ICR/`.

## Données ICR attendues

| **Colonne** | **Rôle**                                            |
|:------------|:----------------------------------------------------|
| `site`      | Identifiant du site inventorié.                     |
| `date`      | Date de visite.                                     |
| `visite_id` | Identifiant unique de visite.                       |
| `espece`    | Nom d’espèce observée.                              |
| `placette`  | Colonne optionnelle pour préciser l’unité spatiale. |

# Installation des dépendances

Les scripts vérifient et installent les packages R nécessaires lorsque cela est possible. Une connexion internet est recommandée au premier lancement. En environnement contrôlé, il est préférable d’installer les dépendances avant la distribution de l’archive.

# Interprétation et bonnes pratiques

- Toujours vérifier la qualité taxonomique et la cohérence des dates avant interprétation.

- Interpréter les scores à la lumière de l’effort d’échantillonnage et de la saison.

- Conserver les logs avec les résultats afin de documenter chaque exécution.

- Ne pas comparer deux campagnes si les méthodes ou les colonnes d’entrée ont changé sans traçabilité.

# Dépannage

<div class="description">

Vérifier le chemin, le nom de fichier et la présence du fichier dans `data/`.

Vérifier la connexion internet, les droits d’écriture de la bibliothèque R et les messages du log.

Consulter le dernier fichier de log dans `logs/` et vérifier que le fichier d’entrée contient les colonnes attendues.

</div>

# Références

- Wickham, H. (2016). *ggplot2: Elegant Graphics for Data Analysis*. Springer.

- Venables, W.N. & Ripley, B.D. (2002). *Modern Applied Statistics with S*. Springer.

- Documentation R et documentation des packages utilisés par les scripts.

# Contact et versionnement

|                         |                                    |
|:------------------------|:-----------------------------------|
| **Auteur**              | Eddy Boite                         |
| **Dépôt GitHub**        | `eddyboite-nat/myco_apps_releases` |
| **Branche**             | `main`                             |
| **Version script**      | 1.0                                |
| **Date de ce document** | 7 juillet 2026                     |

Pour toute évolution du script, ouvrir une issue dans le dépôt GitHub ou documenter les changements dans le journal `CHANGELOG.md` du projet.
