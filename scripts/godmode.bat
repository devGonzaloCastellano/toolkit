@echo off
title God Mode
chcp 65001 >nul

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Solicitando permisos de administrador...
    PowerShell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo  ==========================================
echo    GOD MODE
echo  ==========================================
echo.
echo  Crea una carpeta especial en el Escritorio
echo  con acceso directo a todos los paneles
echo  de configuracion de Windows en un solo lugar.
echo.

set "GODMODE=%USERPROFILE%\Desktop\GodMode.{ED7BA470-8E54-465E-825C-99712043E01C}"

if exist "%GODMODE%" (
    echo  La carpeta God Mode ya existe en el Escritorio.
) else (
    mkdir "%GODMODE%" >nul 2>&1
    if %errorLevel%==0 (
        echo  God Mode creado exitosamente en el Escritorio.
    ) else (
        echo  Error al crear God Mode. Verificar permisos.
    )
)

echo.
echo  Abriendo God Mode...
explorer "%GODMODE%"

echo.
pause
exit /b