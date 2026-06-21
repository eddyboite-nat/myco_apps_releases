@echo off
title myco_apps_releases

echo.
echo ============================================
echo  myco_apps_releases - lancement local
echo ============================================
echo.

cd /d "%~dp0application"

where Rscript >nul 2>nul
if %errorlevel% neq 0 (
    echo Rscript est introuvable.
    echo Veuillez installer R depuis https://cran.r-project.org/
    echo Puis relancer ce fichier.
    pause
    exit /b 1
)

Rscript run_app.R

echo.
echo Si l'application ne s'est pas ouverte, consultez les messages ci-dessus.
pause
