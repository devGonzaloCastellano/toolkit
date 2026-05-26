@echo off
title Reparacion de Windows Update
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
for /f %%a in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HH-mm"') do set "TIMESTAMP=%%a"
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "Get-Date -Format 'dd/MM/yyyy HH:mm:ss'"`) do set "FECHAHORA=%%a"
set "LOGFILE=%~dp0..\logs\reparacion_update_%TIMESTAMP%.txt"

if not exist "%~dp0..\logs" mkdir "%~dp0..\logs"
if exist "%LOGFILE%" del "%LOGFILE%"

echo.
echo  ==========================================
echo    REPARACION DE WINDOWS UPDATE
echo  ==========================================
echo.

echo ==========================================  >> "%LOGFILE%"
echo    REPARACION DE WINDOWS UPDATE             >> "%LOGFILE%"
echo ==========================================  >> "%LOGFILE%"
echo    Inicio: %FECHAHORA%                      >> "%LOGFILE%"
echo.                                            >> "%LOGFILE%"

:: ==========================================
:: PASO 1: Detener servicios de Windows Update
:: ==========================================
echo  ------------------------------------------
echo   [1/6] Deteniendo servicios...
echo  ------------------------------------------
echo  Antes de tocar cualquier archivo de Update
echo  hay que detener los servicios que los usan.
echo  Si no, Windows los regenera al instante.
echo.

echo [1/6] Deteniendo servicios >> "%LOGFILE%"
chcp 1252 >nul
net stop wuauserv >> "%LOGFILE%" 2>&1
net stop cryptSvc >> "%LOGFILE%" 2>&1
net stop bits >> "%LOGFILE%" 2>&1
net stop msiserver >> "%LOGFILE%" 2>&1
chcp 65001 >nul

echo   OK - servicios detenidos.
echo.

:: ==========================================
:: PASO 2: Renombrar carpetas de cache
:: ==========================================
echo  ------------------------------------------
echo   [2/6] Limpiando cache de Windows Update...
echo  ------------------------------------------
echo  En lugar de borrar directamente, renombramos
echo  las carpetas. Windows las recrea limpias al
echo  reiniciar los servicios. Si algo falla, las
echo  carpetas originales siguen disponibles con
echo  el sufijo .bak para hacer rollback.
echo.

echo [2/6] Renombrando carpetas de cache >> "%LOGFILE%"

:: SoftwareDistribution: donde se descargan las actualizaciones
if exist "C:\Windows\SoftwareDistribution" (
    if exist "C:\Windows\SoftwareDistribution.bak" rmdir /s /q "C:\Windows\SoftwareDistribution.bak" 2>nul
    rename "C:\Windows\SoftwareDistribution" "SoftwareDistribution.bak" >> "%LOGFILE%" 2>&1
    echo   SoftwareDistribution renombrada.
    echo   SoftwareDistribution renombrada. >> "%LOGFILE%"
) else (
    echo   SoftwareDistribution no encontrada, omitiendo.
    echo   SoftwareDistribution no encontrada. >> "%LOGFILE%"
)

:: catroot2: donde se guardan las firmas de actualizaciones
if exist "C:\Windows\System32\catroot2" (
    if exist "C:\Windows\System32\catroot2.bak" rmdir /s /q "C:\Windows\System32\catroot2.bak" 2>nul
    rename "C:\Windows\System32\catroot2" "catroot2.bak" >> "%LOGFILE%" 2>&1
    echo   catroot2 renombrada.
    echo   catroot2 renombrada. >> "%LOGFILE%"
) else (
    echo   catroot2 no encontrada, omitiendo.
    echo   catroot2 no encontrada. >> "%LOGFILE%"
)
echo.

:: ==========================================
:: PASO 3: Limpiar entradas del registro de Update
:: ==========================================
echo  ------------------------------------------
echo   [3/6] Limpiando registro de Windows Update...
echo  ------------------------------------------
echo  Elimina claves del registro que guardan el
echo  estado de actualizaciones pendientes o con
echo  error. Fuerza a Windows Update a empezar
echo  desde cero en la proxima busqueda.
echo.

echo [3/6] Limpiando registro >> "%LOGFILE%"

reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" /v AccountDomainSid /f >> "%LOGFILE%" >nul 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" /v PingID /f >> "%LOGFILE%" >nul 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" /v SusClientId /f >> "%LOGFILE%" >nul 2>&1

echo   OK.
echo.

:: ==========================================
:: PASO 4: Resetear Winsock y política de red
:: ==========================================
echo  ------------------------------------------
echo   [4/6] Reseteando componentes de red...
echo  ------------------------------------------
echo  Windows Update necesita red para funcionar.
echo  Un Winsock corrupto puede impedir que el
echo  servicio se conecte a los servidores de MS.
echo.

echo [4/6] Reset de red >> "%LOGFILE%"

chcp 1252 >nul
netsh winsock reset >> "%LOGFILE%" 2>&1
netsh winhttp reset proxy >> "%LOGFILE%" 2>&1
chcp 65001 >nul

echo   OK.
echo.

:: ==========================================
:: PASO 5: Reiniciar servicios
:: ==========================================
echo  ------------------------------------------
echo   [5/6] Reiniciando servicios...
echo  ------------------------------------------
echo  Al reiniciar, Windows detecta que las
echo  carpetas no existen y las recrea limpias.
echo.

echo [5/6] Reiniciando servicios >> "%LOGFILE%"
chcp 1252 >nul
net start wuauserv >> "%LOGFILE%" 2>&1
net start cryptSvc >> "%LOGFILE%" 2>&1
net start bits >> "%LOGFILE%" 2>&1
net start msiserver >> "%LOGFILE%" 2>&1
chcp 65001 >nul

echo   OK - servicios reiniciados.
echo.

:: ==========================================
:: PASO 6: Forzar re-registro de DLLs de Update
:: ==========================================
echo  ------------------------------------------
echo   [6/6] Re-registrando DLLs de Windows Update...
echo  ------------------------------------------
echo  Algunas actualizaciones fallidas corrompen
echo  el registro de las DLLs que usa el servicio.
echo  Esto las vuelve a registrar correctamente.
echo.

echo [6/6] Re-registro de DLLs >> "%LOGFILE%"

for %%i in (
    atl.dll urlmon.dll mshtml.dll
    shdocvw.dll browseui.dll
    jscript.dll vbscript.dll
    scrrun.dll msxml.dll msxml3.dll msxml6.dll
    actxprxy.dll softpub.dll wintrust.dll
    dssenh.dll rsaenh.dll gpkcsp.dll sccbase.dll
    slbcsp.dll cryptdlg.dll oleaut32.dll ole32.dll
    shell32.dll wuapi.dll wuaueng.dll wuaueng1.dll
    wucltui.dll wups.dll wups2.dll wuweb.dll
    qmgr.dll qmgrprxy.dll wucltux.dll muweb.dll
    wuwebv.dll
) do (
    regsvr32 /s %%i >> "%LOGFILE%" 2>&1
)

echo   OK - DLLs re-registradas.
echo.

:: ==========================================
:: RESUMEN
:: ==========================================
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "Get-Date -Format 'dd/MM/yyyy HH:mm:ss'"`) do set "FECHAHORA_FIN=%%a"

echo ==========================================  >> "%LOGFILE%"
echo    FIN: %FECHAHORA_FIN%                     >> "%LOGFILE%"
echo ==========================================  >> "%LOGFILE%"

echo.
echo  ==========================================
echo    REPARACION DE WINDOWS UPDATE FINALIZADA
echo  ==========================================
echo.
echo   Proximos pasos recomendados:
echo   1. REINICIAR el equipo
echo   2. Abrir Windows Update y buscar actualizaciones
echo   3. Si sigue fallando, revisar log:
echo      %LOGFILE%
echo.
echo  ==========================================
echo.
pause
endlocal
exit /b