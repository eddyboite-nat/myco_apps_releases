# myco_apps_releases — guide utilisateur

## Objectif

Cette archive fournit une interface locale pour lancer deux analyses R sans ouvrir RStudio :

1. **Inventaires fongiques — Complétude & Représentativité (ICR)** ;
2. **Évaluation potentiel fongique / intérêt patrimonial / gradient CHEGD**.

L'application s'ouvre dans votre navigateur, mais les calculs restent exécutés sur votre ordinateur.

## Prérequis

Vous devez installer **R** une fois sur votre ordinateur :

<https://cran.r-project.org/>

RStudio n'est pas obligatoire.

## Lancement

### Windows

Double-cliquez sur :

```text
LANCER_WINDOWS.bat
```

### macOS

Double-cliquez sur :

```text
LANCER_MAC.command
```

Si macOS bloque le lancement, faites clic droit puis **Ouvrir**.

Au premier lancement sur macOS, le système peut afficher :
“Apple n’a pas pu confirmer que ce fichier ne contenait pas de logiciel malveillant.”

Dans ce cas :
1. cliquer sur Terminé ;
2. ouvrir Terminal dans le dossier de l’application ;
3. exécuter :

xattr -dr com.apple.quarantine .
chmod +x LANCER_MAC.command
./LANCER_MAC.command

### Linux

Dans un terminal :

```bash
./LANCER_LINUX.sh
```

## Premier lancement

Au premier lancement, l'application installe automatiquement les composants R nécessaires. Une connexion internet est donc nécessaire.

Les lancements suivants sont normalement plus rapides.

## Utilisation

1. Choisir l'application à lancer.
2. Utiliser le fichier d'exemple ou charger votre propre fichier.
3. Cliquer sur **Lancer l'analyse**.
4. Consulter les fichiers produits dans l'onglet **Résultats** ou dans `application/results/`.

## Colonnes attendues

### ICR

Colonnes obligatoires :

| Colonne | Description |
|---|---|
| `site` | Nom du site |
| `date` | Date de visite |
| `visite_id` | Identifiant de visite |
| `espece` | Nom d'espèce |

Colonne optionnelle :

| Colonne | Description |
|---|---|
| `placette` | Placette ou unité spatiale |

### CHEGD

Colonnes attendues :

| Colonne | Description |
|---|---|
| `Espèces` | Nom de l'espèce |
| `Famille` | Famille taxonomique |
| `Date` | Date d'observation |
| `Nombre d'espèce` | Abondance / effectif |
| `Site` | Site ou pelouse |
| `Fiabilité détermination` | Niveau de fiabilité |

## Où sont les résultats ?

```text
application/results/ICR/
application/results/EPFIP_CHEGD/
```

## Où sont les journaux d'exécution ?

```text
application/logs/
```

En cas de problème, transmettre le dernier fichier `run_...log`.

## Notes techniques

Cette version ajoute une interface Shiny locale et des lanceurs multi-OS autour des scripts existants. Le cœur des scripts métier est conservé. Le script CHEGD a seulement été adapté pour accepter un fichier d'entrée choisi depuis l'interface via variable d'environnement.


## Quitter l'application

Dans l'interface, cliquez sur **Quitter l'application**.

Ensuite, fermez l'onglet du navigateur et, si elle reste ouverte, la fenêtre Terminal.
