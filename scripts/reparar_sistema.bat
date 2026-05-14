@echo off
title Reparacion del Sistema
chcp 65001 >nul
setlocal enabledelayedexpansion

:: ----------------------------------------
:: Auto-elevacion a Administrador
:: ----------------------------------------
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Solicitando permisos de administrador...
    PowerShell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: ----------------------------------------
:: Timestamp via PowerShell
:: ----------------------------------------
for /f %%a in ('PowerShell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HH-mm"') do set "TIMESTAMP=%%a"
set "LOGFILE=%~dp0..\logs\reparacion_%TIMESTAMP%.txt"

if not exist "%~dp0..\logs" mkdir "%~dp0..\logs"
if exist "%LOGFILE%" del "%LOGFILE%"

echo ==========================================  >> "%LOGFILE%"
echo    REPARACION DEL SISTEMA                  >> "%LOGFILE%"
echo ==========================================  >> "%LOGFILE%"
echo.                                           >> "%LOGFILE%"

echo.
echo  ==========================================
echo    REPARACION DEL SISTEMA
echo  ==========================================
echo.

:: ==========================================
:: PASO 1: SFC
:: ==========================================
echo  ------------------------------------------
echo   [1/2] SFC - Verificacion de archivos
echo  ------------------------------------------
echo.
echo  Puede tardar entre 5 y 15 minutos.
echo  No cerrar esta ventana.
echo.

echo [1/2] SFC - System File Checker >> "%LOGFILE%"
echo ------------------------------------------ >> "%LOGFILE%"

sfc /scannow
set "SFC_EXIT=%errorLevel%"

if %SFC_EXIT%==0 (
    echo Resultado SFC: OK - codigo de salida 0 >> "%LOGFILE%"
    echo.
    echo  Resultado SFC: Finalizo sin errores.
) else (
    echo Resultado SFC: codigo de salida %SFC_EXIT% >> "%LOGFILE%"
    echo.
    echo  Resultado SFC: Codigo %SFC_EXIT% - revisar output de pantalla.
)
echo. >> "%LOGFILE%"
echo.

:: ==========================================
:: PASO 2: DISM
:: ==========================================
echo  ------------------------------------------
echo   [2/2] DISM - Reparacion de imagen Windows
echo  ------------------------------------------
echo.
echo  Requiere conexion a internet.
echo  Puede tardar entre 10 y 20 minutos.
echo  No cerrar esta ventana.
echo.

echo [2/2] DISM - RestoreHealth >> "%LOGFILE%"
echo ------------------------------------------ >> "%LOGFILE%"

DISM /Online /Cleanup-Image /RestoreHealth
set "DISM_EXIT=%errorLevel%"

if %DISM_EXIT%==0 (
    echo Resultado DISM: OK - codigo de salida 0 >> "%LOGFILE%"
    echo Log nativo: C:\Windows\Logs\DISM\dism.log >> "%LOGFILE%"
    echo.
    echo  Resultado DISM: Finalizo correctamente.
) else (
    echo Resultado DISM: codigo de salida %DISM_EXIT% >> "%LOGFILE%"
    echo Log nativo: C:\Windows\Logs\DISM\dism.log >> "%LOGFILE%"
    echo.
    echo  Resultado DISM: Codigo %DISM_EXIT% - revisar log.
)

echo. >> "%LOGFILE%"
echo ==========================================  >> "%LOGFILE%"
echo    FIN DEL PROCESO                         >> "%LOGFILE%"
echo ==========================================  >> "%LOGFILE%"

echo.
echo  ==========================================
echo   REPARACION FINALIZADA
echo  ==========================================
echo   SFC:  %SFC_EXIT%
echo   DISM: %DISM_EXIT%
echo.
echo   Recomendacion: REINICIAR el equipo.
echo   Log guardado en:
echo   %LOGFILE%
echo  ==========================================
echo.
pause
endlocal
exit /b