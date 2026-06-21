# Audit packaging — myco_apps_releases

## Contenu détecté

Le dépôt initial contient deux scripts principaux :

- `scripts/Inventaires_completude_representativite.R` — ICR, version 1.4 ;
- `scripts/Evaluation_Potentiel_Fongique_Interets_Patrimoniaux_CHEGD.R` — EPFIP-CHEGD, version 1.0.

Il contient également :

- des données d'exemple dans `data/` ;
- une documentation méthodologique dans `docs/` ;
- des résultats et logs déjà générés dans `results/` et `logs/` ;
- un dossier `.git/` et des fichiers macOS `.DS_Store` dans l'archive initiale.

## Modifications apportées dans la release utilisateur

- Ajout de `LANCER_WINDOWS.bat`.
- Ajout de `LANCER_MAC.command`.
- Ajout de `LANCER_LINUX.sh`.
- Ajout de `application/app.R` pour l'interface Shiny locale.
- Ajout de `application/run_app.R` pour lancer l'interface.
- Ajout de `application/install_packages.R` pour installer les packages simples.
- Création de dossiers vides `application/logs/` et `application/results/`.
- Copie des données d'exemple dans `exemples/`.
- Exclusion du dossier `.git/`, des anciens logs, des anciens résultats et des métadonnées macOS.

## Adaptation technique

Le script CHEGD a été adapté dans cette release pour accepter :

- `CHEGD_INPUT_FILE` ;
- `CHEGD_INPUT_SHEET` ;
- `CHEGD_OUTPUT_DIR`.

Le script ICR acceptait déjà :

- `INVENTAIRES_INPUT_FILE` ;
- `INVENTAIRES_OUTPUT_DIR` ;
- `INVENTAIRES_AUTO_RUN`.

## Limites de test

L'environnement de packaging utilisé ici ne dispose pas de `Rscript`. Les scripts ont donc été inspectés et empaquetés, mais pas exécutés complètement dans le sandbox.

À tester localement sur une machine ayant R installé :

1. lancement Windows/macOS/Linux ;
2. installation des packages ;
3. exécution ICR avec `observations.csv` ;
4. exécution CHEGD avec `données_récoltes_chegd_pelouses.csv` ;
5. exécution avec fichiers utilisateur.
