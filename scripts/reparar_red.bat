@echo off
title Reparacion de Red
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
set "LOGFILE=%~dp0..\logs\reparacion_red_%TIMESTAMP%.txt"


if not exist "%~dp0..\logs" mkdir "%~dp0..\logs"
if exist "%LOGFILE%" del "%LOGFILE%"

:: ----------------------------------------
:: Encabezado del log
:: ----------------------------------------
echo ==========================================  >> "%LOGFILE%"
echo    REPARACION DE RED                       >> "%LOGFILE%"
echo    Inicio: %FECHAHORA%                     >> "%LOGFILE%"
echo ==========================================  >> "%LOGFILE%"
echo.                                           >> "%LOGFILE%"

echo.
echo  ==========================================
echo    REPARACION DE RED
echo  ==========================================
echo.

:: ==========================================
:: ESTADO ANTES de reparar
:: ==========================================
echo  ------------------------------------------
echo   Diagnostico previo
echo  ------------------------------------------
echo.

echo [ESTADO PREVIO] >> "%LOGFILE%"

:: IP actual
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /i "IPv4"') do (
    if not "%%a"=="" (
        echo   IP actual:    %%a
        echo   IP actual:    %%a >> "%LOGFILE%"
    )
)

:: Gateway via PowerShell para evitar IPv6 y duplicados
for /f %%a in ('powershell -NoProfile -Command "(Get-NetRoute -DestinationPrefix 0.0.0.0/0 | Sort-Object RouteMetric | Select-Object -First 1).NextHop" 2^>nul') do (
    echo   Gateway:      %%a
    echo   Gateway:      %%a >> "%LOGFILE%"
)

:: Test de conectividad basico
echo.
echo  Probando conectividad...
ping -n 2 8.8.8.8 >nul 2>&1
if %errorLevel%==0 (
    echo   Internet:     OK - hay conectividad
    echo   Internet antes: OK >> "%LOGFILE%"
) else (
    echo   Internet:     SIN CONECTIVIDAD
    echo   Internet antes: SIN CONECTIVIDAD >> "%LOGFILE%"
)
echo. >> "%LOGFILE%"
echo.

:: ==========================================
:: PASO 1: Flush DNS
:: ==========================================
echo  ------------------------------------------
echo   [1/5] Limpiando cache DNS...
echo  ------------------------------------------
echo  La cache DNS guarda resoluciones anteriores.
echo  Si un sitio cambio de IP o hay respuestas
echo  incorrectas guardadas, esto las elimina.
echo.

echo [1/5] Flush DNS >> "%LOGFILE%"
chcp 437 >nul
ipconfig /flushdns >> "%LOGFILE%" 2>&1
chcp 65001 >nul
echo   OK.
echo.

:: ==========================================
:: PASO 2: Liberar y renovar IP
:: ==========================================
echo  ------------------------------------------
echo   [2/5] Liberando y renovando IP...
echo  ------------------------------------------
echo  Devuelve la IP al router y solicita una nueva.
echo  Util cuando hay conflictos de IP o el equipo
echo  no obtiene direccion automaticamente.
echo.

echo [2/5] Release y Renew >> "%LOGFILE%"
chcp 437 >nul
ipconfig /release >> "%LOGFILE%" 2>&1
ipconfig /renew >> "%LOGFILE%" 2>&1
chcp 65001 >nul
echo   OK.
echo.

:: ==========================================
:: PASO 3: Reset Winsock
:: ==========================================
echo  ------------------------------------------
echo   [3/5] Reseteando Winsock...
echo  ------------------------------------------
echo  Winsock es la interfaz entre Windows y la
echo  red. Se puede corromper por malware o
echo  instalaciones de VPN/proxy mal removidas.
echo  Este reset lo devuelve a estado limpio.
echo.

echo [3/5] Winsock Reset >> "%LOGFILE%"
chcp 1252 >nul
netsh winsock reset >> "%LOGFILE%" 2>&1
chcp 65001 >nul
echo   OK.
echo.

:: ==========================================
:: PASO 4: Reset TCP/IP
:: ==========================================
echo  ------------------------------------------
echo   [4/5] Reseteando pila TCP/IP...
echo  ------------------------------------------
echo  Restaura la configuracion TCP/IP completa
echo  a valores de fabrica. Mas profundo que el
echo  reset de Winsock, afecta toda la pila de red.
echo.

echo [4/5] TCP/IP Reset >> "%LOGFILE%"
chcp 1252 >nul
netsh int ip reset >> "%LOGFILE%" 2>&1
chcp 65001 >nul
echo   OK.
echo.

:: ==========================================
:: PASO 5: Reset configuracion de proxy
:: ==========================================
echo  ------------------------------------------
echo   [5/5] Limpiando configuracion de proxy...
echo  ------------------------------------------
echo  Algunos malware o programas configuran un
echo  proxy en el sistema para interceptar trafico.
echo  Esto lo elimina y restaura conexion directa.
echo.

echo [5/5] Reset Proxy >> "%LOGFILE%"
chcp 1252 >nul
netsh winhttp reset proxy >> "%LOGFILE%" 2>&1
chcp 65001 >nul
:: Las claves de proxy pueden no existir en todos los equipos, se descartan los errores
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /f >nul 2>&1
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer /f >nul 2>&1
echo   OK.
echo.

:: ==========================================
:: ESTADO DESPUES de reparar
:: ==========================================
echo  ------------------------------------------
echo   Diagnostico posterior
echo  ------------------------------------------
echo.

echo [ESTADO POSTERIOR] >> "%LOGFILE%"

for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /i "IPv4"') do (
    if not "%%a"=="" (
        echo   IP nueva:     %%a
        echo   IP nueva:     %%a >> "%LOGFILE%"
    )
)

ping -n 2 8.8.8.8 >nul 2>&1
if %errorLevel%==0 (
    echo   Internet:     OK - hay conectividad
    echo   Internet despues: OK >> "%LOGFILE%"
) else (
    echo   Internet:     SIN CONECTIVIDAD
    echo   Internet despues: SIN CONECTIVIDAD >> "%LOGFILE%"
    echo.
    echo  ATENCION: Sin conectividad luego del reset.
    echo  Puede requerir reinicio para aplicar cambios.
)

:: ==========================================
:: Timestamp de cierre y resumen
:: ==========================================
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "Get-Date -Format 'dd/MM/yyyy HH:mm:ss'"`) do set "FECHAHORA_FIN=%%a"

echo.
echo ==========================================  >> "%LOGFILE%"
echo    FIN: %FECHAHORA_FIN%                    >> "%LOGFILE%"
echo ==========================================  >> "%LOGFILE%"

echo.
echo  ==========================================
echo    REPARACION DE RED FINALIZADA
echo  ==========================================
echo.
echo   IMPORTANTE: Reiniciar el equipo para
echo   aplicar todos los cambios correctamente.
echo   (especialmente el reset de Winsock y TCP/IP)
echo.
echo   Log: %LOGFILE%
echo  ==========================================
echo.
pause
endlocal
exit /b