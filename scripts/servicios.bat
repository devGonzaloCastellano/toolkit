@echo off
title Servicios Innecesarios
chcp 65001 >nul
setlocal enabledelayedexpansion

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Solicitando permisos de administrador...
    PowerShell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

for /f %%a in ('PowerShell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HH-mm"') do set "TIMESTAMP=%%a"
set "LOGFILE=%~dp0..\logs\servicios_%TIMESTAMP%.txt"

if not exist "%~dp0..\logs" mkdir "%~dp0..\logs"
if exist "%LOGFILE%" del "%LOGFILE%"

echo.
echo  ==========================================
echo    SERVICIOS INNECESARIOS
echo  ==========================================
echo.
echo  Solo muestra estado. No desactiva nada.
echo.

echo ==========================================   >> "%LOGFILE%"
echo    SERVICIOS INNECESARIOS                   >> "%LOGFILE%"
echo ==========================================   >> "%LOGFILE%"
echo.                                            >> "%LOGFILE%"

:: Usar PowerShell para consultar estado de cada servicio
:: Get-Service devuelve Status: Running/Stopped/Disabled de forma confiable

echo  [TELEMETRIA Y DIAGNOSTICO]
echo [TELEMETRIA Y DIAGNOSTICO] >> "%LOGFILE%"
for %%S in (DiagTrack dmwappushservice PcaSvc WerSvc) do (
    for /f %%x in ('PowerShell -NoProfile -Command "try { (Get-Service %%S).Status } catch { Write-Output NoExiste }"') do set "ESTADO=%%x"
    echo   %%S - !ESTADO!
    echo   %%S - !ESTADO! >> "%LOGFILE%"
)
echo.
echo. >> "%LOGFILE%"

echo  [XBOX Y GAMING]
echo [XBOX Y GAMING] >> "%LOGFILE%"
for %%S in (XblAuthManager XblGameSave XboxNetApiSvc XboxGipSvc) do (
    for /f %%x in ('PowerShell -NoProfile -Command "try { (Get-Service %%S).Status } catch { Write-Output NoExiste }"') do set "ESTADO=%%x"
    echo   %%S - !ESTADO!
    echo   %%S - !ESTADO! >> "%LOGFILE%"
)
echo.
echo. >> "%LOGFILE%"

echo  [SERVICIOS RARAMENTE USADOS]
echo [SERVICIOS RARAMENTE USADOS] >> "%LOGFILE%"
for %%S in (Fax MapsBroker RetailDemo RemoteRegistry TabletInputService WMPNetworkSvc icssvc lfsvc SharedAccess) do (
    for /f %%x in ('PowerShell -NoProfile -Command "try { (Get-Service %%S).Status } catch { Write-Output NoExiste }"') do set "ESTADO=%%x"
    echo   %%S - !ESTADO!
    echo   %%S - !ESTADO! >> "%LOGFILE%"
)
echo.
echo. >> "%LOGFILE%"

echo  ==========================================
echo  Para deshabilitar un servicio:
echo    sc config NombreServicio start= disabled
echo    sc stop NombreServicio
echo.
echo  Para revertir:
echo    sc config NombreServicio start= auto
echo    sc start NombreServicio
echo  ==========================================
echo.
echo  Log: %LOGFILE%
echo.

echo ==========================================   >> "%LOGFILE%"
echo    FIN DEL REPORTE                          >> "%LOGFILE%"
echo ==========================================   >> "%LOGFILE%"

pause
endlocal
exit /b