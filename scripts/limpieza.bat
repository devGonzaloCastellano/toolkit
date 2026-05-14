@echo off
title Limpieza de Sistema
chcp 65001 >nul

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
:: Espacio disponible ANTES de limpiar
:: ----------------------------------------
for /f "tokens=3" %%a in ('dir C:\ /-c ^| findstr /i "bytes libres"') do set ANTES=%%a
if "%ANTES%"=="" (
    for /f "tokens=3" %%a in ('dir C:\ /-c ^| findstr /i "bytes free"') do set ANTES=%%a
)

echo.
echo ==========================================
echo   LIMPIEZA DE SISTEMA - v2
echo ==========================================
echo.

:: ----------------------------------------
echo [1/7] Limpiando archivos temporales de usuario...
:: ----------------------------------------
del /s /f /q %temp%\*.* 2>nul
for /d %%p in (%temp%\*) do rmdir "%%p" /s /q 2>nul
echo     OK.

:: ----------------------------------------
echo [2/7] Limpiando temporales del sistema...
:: ----------------------------------------
del /s /f /q C:\Windows\Temp\*.* 2>nul
for /d %%p in (C:\Windows\Temp\*) do rmdir "%%p" /s /q 2>nul
echo     OK.

:: ----------------------------------------
echo [3/7] Limpiando Prefetch...
:: ----------------------------------------
del /s /f /q C:\Windows\Prefetch\*.* 2>nul
echo     OK.

:: ----------------------------------------
echo [4/7] Limpiando historial de archivos recientes...
:: ----------------------------------------
del /s /f /q "%APPDATA%\Microsoft\Windows\Recent\*" 2>nul
echo     OK.

:: ----------------------------------------
echo [5/7] Limpiando cache de Windows Update...
:: ----------------------------------------
net stop wuauserv >nul 2>&1
net stop bits >nul 2>&1
del /s /f /q C:\Windows\SoftwareDistribution\Download\*.* 2>nul
for /d %%p in (C:\Windows\SoftwareDistribution\Download\*) do rmdir "%%p" /s /q 2>nul
net start wuauserv >nul 2>&1
net start bits >nul 2>&1
echo     OK.

:: ----------------------------------------
echo [6/7] Limpiando cache de DNS y vaciando Papelera...
:: ----------------------------------------
ipconfig /flushdns >nul
PowerShell -Command "Clear-RecycleBin -Force -ErrorAction SilentlyContinue"
echo     OK.

:: ----------------------------------------
echo [7/7] Ejecutando Limpieza de Disco (Disk Cleanup)...
:: ----------------------------------------
:: Configurar Disk Cleanup con todas las categorias posibles (nivel 2)
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Temporary Files" /v StateFlags0002 /t REG_DWORD /d 2 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Thumbnail Cache" /v StateFlags0002 /t REG_DWORD /d 2 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Recycle Bin" /v StateFlags0002 /t REG_DWORD /d 2 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Internet Cache Files" /v StateFlags0002 /t REG_DWORD /d 2 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Delivery Optimization Files" /v StateFlags0002 /t REG_DWORD /d 2 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Windows Error Reporting Files" /v StateFlags0002 /t REG_DWORD /d 2 /f >nul 2>&1
cleanmgr /sagerun:2
echo     OK.

:: ----------------------------------------
:: Espacio disponible DESPUES de limpiar
:: ----------------------------------------
for /f "tokens=3" %%a in ('dir C:\ /-c ^| findstr /i "bytes libres"') do set DESPUES=%%a
if "%DESPUES%"=="" (
    for /f "tokens=3" %%a in ('dir C:\ /-c ^| findstr /i "bytes free"') do set DESPUES=%%a
)

echo.
echo ==========================================
echo   LIMPIEZA COMPLETA
echo ==========================================
echo.
if defined ANTES    echo   Espacio antes:   %ANTES% bytes
if defined DESPUES  echo   Espacio despues: %DESPUES% bytes
echo.
echo   Nota: Disk Cleanup puede seguir corriendo
echo   en segundo plano unos segundos mas.
echo.
pause