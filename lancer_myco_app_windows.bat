@echo off
setlocal EnableExtensions

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
  echo Si R est deja installe, ajoutez son dossier bin au PATH.
  echo.
  pause
  exit /b 1
)

echo Version R :
"%RSCRIPT_BIN%" --version
echo.

for /f "usebackq delims=" %%P in (`"%RSCRIPT_BIN%" -e "pkgs <- c('shiny','processx','later'); missing <- pkgs[!vapply(pkgs, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]; cat(paste(missing, collapse = ' '))"`) do (
  set "MISSING_PACKAGES=%%P"
)

if defined MISSING_PACKAGES (
  echo ERREUR : packages R manquants : %MISSING_PACKAGES%
  echo Installez-les dans R avec :
  echo install.packages(c("shiny", "processx", "later"))
  echo.
  pause
  exit /b 1
)

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
