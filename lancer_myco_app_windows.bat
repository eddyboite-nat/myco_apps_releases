@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%" || (
  echo ERREUR : impossible d'ouvrir le dossier du projet.
  pause
  exit /b 1
)

echo ========================================
echo Myco Apps Local
echo ========================================
echo Dossier projet : %SCRIPT_DIR%
echo.

set "RSCRIPT_BIN="

where Rscript.exe >nul 2>nul
if %ERRORLEVEL% EQU 0 (
  for /f "delims=" %%I in ('where Rscript.exe 2^>nul') do (
    if not defined RSCRIPT_BIN set "RSCRIPT_BIN=%%I"
  )
)

if not defined RSCRIPT_BIN (
  for %%P in (
    "%ProgramFiles%\R\R-*\bin\Rscript.exe"
    "%ProgramFiles%\R\R-*\bin\x64\Rscript.exe"
    "%ProgramFiles(x86)%\R\R-*\bin\Rscript.exe"
    "%ProgramFiles(x86)%\R\R-*\bin\x64\Rscript.exe"
  ) do (
    for %%F in (%%P) do (
      if exist "%%~fF" set "RSCRIPT_BIN=%%~fF"
    )
  )
)

if not defined RSCRIPT_BIN (
  echo ERREUR : Rscript est introuvable.
  echo Installez R depuis https://cran.r-project.org/bin/windows/base/
  echo.
  echo Apres installation, relancez ce script.
  echo Si R est deja installe :
  echo - ouvrez "Modifier les variables d'environnement systeme" ;
  echo - ajoutez le dossier bin de R au PATH, par exemple :
  echo   C:\Program Files\R\R-4.x.x\bin
  echo.
  pause
  exit /b 1
)

echo Version R :
"%RSCRIPT_BIN%" --version
echo.

"%RSCRIPT_BIN%" -e "min_version <- '4.0.0'; if (getRversion() < min_version) quit(status = 1)" >nul 2>nul
if not "%ERRORLEVEL%"=="0" (
  for /f "usebackq delims=" %%V in (`"%RSCRIPT_BIN%" -e "cat(as.character(getRversion()))"`) do (
    set "CURRENT_R_VERSION=%%V"
  )
  echo ERREUR : version de R insuffisante.
  echo Version detectee : R !CURRENT_R_VERSION!
  echo Version minimale requise : R 4.0.0
  echo.
  echo Installez une version recente de R depuis :
  echo https://cran.r-project.org/bin/windows/base/
  echo.
  echo Apres installation, relancez ce script.
  echo Si R est deja a jour, verifiez que le Rscript trouve est le bon :
  echo %RSCRIPT_BIN%
  echo.
  pause
  exit /b 1
)

for /f "usebackq delims=" %%P in (`"%RSCRIPT_BIN%" -e "pkgs <- c('shiny','processx','later','readxl','dplyr','stringr','ggplot2','gridExtra','MASS','nnet','tidyr','purrr','readr','forcats','tibble','scales'); missing <- pkgs[!vapply(pkgs, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]; cat(paste(missing, collapse = ' '))"`) do (
  set "MISSING_PACKAGES=%%P"
)

if defined MISSING_PACKAGES (
  echo ERREUR : packages R manquants : %MISSING_PACKAGES%
  echo.
  set /p INSTALL_REQUIRED_PACKAGES="Voulez-vous tenter une installation automatique depuis CRAN ? [o/N] "
  if /I "!INSTALL_REQUIRED_PACKAGES!"=="o" goto install_required
  if /I "!INSTALL_REQUIRED_PACKAGES!"=="oui" goto install_required
  if /I "!INSTALL_REQUIRED_PACKAGES!"=="y" goto install_required
  if /I "!INSTALL_REQUIRED_PACKAGES!"=="yes" goto install_required
  echo Installation annulee.
  echo Installez-les dans R avec :
  echo install.packages^(c^("shiny", "processx", "later", "readxl", "dplyr", "stringr", "ggplot2", "gridExtra", "MASS", "nnet", "tidyr", "purrr", "readr", "forcats", "tibble", "scales"^), repos = "https://cloud.r-project.org"^)
  echo.
  pause
  exit /b 1
)
goto after_required_install

:install_required
echo Installation des packages obligatoires...
set "MYCO_REQUIRED_PACKAGES=%MISSING_PACKAGES%"
"%RSCRIPT_BIN%" -e "pkgs <- strsplit(Sys.getenv('MYCO_REQUIRED_PACKAGES'), ' ', fixed = TRUE)[[1]]; install.packages(pkgs, repos = 'https://cloud.r-project.org'); missing <- pkgs[!vapply(pkgs, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]; if (length(missing) > 0) stop('Packages toujours manquants apres installation : ', paste(missing, collapse = ', '), call. = FALSE)"
if not "%ERRORLEVEL%"=="0" (
  echo.
  echo ERREUR : installation automatique incomplete.
  echo Installez manuellement les packages indiques ci-dessus dans R.
  echo.
  pause
  exit /b 1
)

:after_required_install

set "OPTIONAL_MISSING_PACKAGES="
for /f "usebackq delims=" %%P in (`"%RSCRIPT_BIN%" -e "pkgs <- c('vegan','minpack.lm','ggrepel'); missing <- pkgs[!vapply(pkgs, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]; cat(paste(missing, collapse = ' '))"`) do (
  set "OPTIONAL_MISSING_PACKAGES=%%P"
)

if defined OPTIONAL_MISSING_PACKAGES (
  echo AVERTISSEMENT : packages R optionnels absents : %OPTIONAL_MISSING_PACKAGES%
  echo Certaines sorties avancees peuvent etre ignorees par les scripts.
  echo.
  set /p INSTALL_OPTIONAL_PACKAGES="Voulez-vous tenter l'installation automatique des packages optionnels ? [o/N] "
  if /I "!INSTALL_OPTIONAL_PACKAGES!"=="o" goto install_optional
  if /I "!INSTALL_OPTIONAL_PACKAGES!"=="oui" goto install_optional
  if /I "!INSTALL_OPTIONAL_PACKAGES!"=="y" goto install_optional
  if /I "!INSTALL_OPTIONAL_PACKAGES!"=="yes" goto install_optional
  echo Installation optionnelle ignoree.
  echo Installation manuelle possible :
  echo install.packages^(c^("vegan", "minpack.lm", "ggrepel"^), repos = "https://cloud.r-project.org"^)
  echo.
  goto after_optional_install
)
goto after_optional_install

:install_optional
echo Installation des packages optionnels...
set "MYCO_OPTIONAL_PACKAGES=%OPTIONAL_MISSING_PACKAGES%"
"%RSCRIPT_BIN%" -e "pkgs <- strsplit(Sys.getenv('MYCO_OPTIONAL_PACKAGES'), ' ', fixed = TRUE)[[1]]; install.packages(pkgs, repos = 'https://cloud.r-project.org'); missing <- pkgs[!vapply(pkgs, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]; if (length(missing) > 0) warning('Packages optionnels toujours absents : ', paste(missing, collapse = ', '))"
echo.

:after_optional_install

echo Lancement de l'application...
echo URL locale : http://127.0.0.1:8765/
echo.
echo Pour fermer proprement : utilisez le bouton "Fermer l'app" dans l'interface.
echo.

"%RSCRIPT_BIN%" app.R
set "APP_EXIT_CODE=%ERRORLEVEL%"

if not "%APP_EXIT_CODE%"=="0" (
  echo.
  echo ERREUR : l'application s'est arretee avec le code %APP_EXIT_CODE%.
  echo Lisez les messages ci-dessus pour identifier la cause.
  echo.
  pause
  exit /b %APP_EXIT_CODE%
)

echo.
echo Application fermee.
pause
exit /b 0
