@echo off
title Kit de Soporte Tecnico
chcp 65001 >nul
color 0A

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
:: Guardar directorio del pendrive
:: ----------------------------------------
set "KITDIR=%~dp0"

:MENU
cls
echo.
echo  ==========================================
echo    KIT DE SOPORTE TECNICO v1.0
echo  ==========================================
echo.
echo  -- DIAGNOSTICO --
echo   [1] Informacion del sistema
echo   [2] Estado del disco
echo   [3] Procesos en ejecucion
echo.
echo  -- LIMPIEZA Y OPTIMIZACION --
echo   [4] Limpieza de sistema
echo   [5] Servicios innecesarios
echo   [6] Programas al inicio
echo.
echo  -- REPARACION --
echo   [7] Reparar archivos del sistema
echo   [8] Reparar red
echo   [9] Reparar Windows Update
echo.
echo  -- SEGURIDAD --
echo   [10] Puertos y conexiones activas
echo   [11] Usuarios del sistema
echo   [12] Actualizar Windows Defender
echo.
echo  -- UTILIDADES --
echo   [13] Activar God Mode
echo   [14] Mapa de red local
echo.
echo   [0] Salir
echo.
echo  ==========================================
set /p "opcion= Elegir opcion: "

if "%opcion%"=="1"  call "%KITDIR%scripts\info_sistema.bat"            & goto MENU
if "%opcion%"=="2"  call "%KITDIR%scripts\reporte_disco.bat"           & goto MENU
if "%opcion%"=="3"  call "%KITDIR%scripts\procesos.bat"                & goto MENU
if "%opcion%"=="4"  call "%KITDIR%scripts\limpieza.bat"                & goto MENU
if "%opcion%"=="5"  call "%KITDIR%scripts\servicios.bat"               & goto MENU
if "%opcion%"=="6"  call "%KITDIR%scripts\startup.bat"                 & goto MENU
if "%opcion%"=="7"  call "%KITDIR%scripts\reparar_sistema.bat"         & goto MENU
if "%opcion%"=="8"  call "%KITDIR%scripts\reparar_red.bat"             & goto MENU
if "%opcion%"=="9"  call "%KITDIR%scripts\reparar_windows_update.bat"  & goto MENU
if "%opcion%"=="10" call "%KITDIR%scripts\puertos.bat"                 & goto MENU
if "%opcion%"=="11" call "%KITDIR%scripts\usuarios.bat"                & goto MENU
if "%opcion%"=="12" call "%KITDIR%scripts\defender.bat"                & goto MENU
if "%opcion%"=="13" call "%KITDIR%scripts\godmode.bat"                 & goto MENU
if "%opcion%"=="14" call "%KITDIR%scripts\mapa_red.bat"                & goto MENU
if "%opcion%"=="0"  goto FIN

echo.
echo  Opcion invalida. Intente de nuevo.
echo.
pause
goto MENU

:FIN
cls
echo.
echo  Hasta luego.
echo.
exit /b