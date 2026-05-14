@echo off
title Puertos y Conexiones Activas
chcp 65001 >nul
setlocal enabledelayedexpansion

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Solicitando permisos de administrador...
    PowerShell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

for /f %%a in ('PowerShell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HH-mm"') do set "TIMESTAMP=%%a"
set "LOGFILE=%~dp0..\logs\puertos_%TIMESTAMP%.txt"

if not exist "%~dp0..\logs" mkdir "%~dp0..\logs"
if exist "%LOGFILE%" del "%LOGFILE%"

echo.
echo  ==========================================
echo    PUERTOS Y CONEXIONES ACTIVAS
echo  ==========================================
echo.
echo  Analizando... un momento.
echo.

echo ==========================================   >> "%LOGFILE%"
echo    PUERTOS Y CONEXIONES ACTIVAS             >> "%LOGFILE%"
echo ==========================================   >> "%LOGFILE%"
echo.                                            >> "%LOGFILE%"

:: ==========================================
:: SECCION 1: Conexiones activas ESTABLISHED
:: ==========================================
echo  [CONEXIONES ACTIVAS]
echo  TCP establecidas en este momento.
echo.
echo [CONEXIONES ACTIVAS] >> "%LOGFILE%"

PowerShell -NoProfile -Command "Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | ForEach-Object { $proc = 'N/A'; try { $proc = (Get-Process -Id $_.OwningProcess -EA Stop).Name } catch {}; '  {0,-22} -> {1,-22} [{2}]' -f ($_.LocalAddress+':'+$_.LocalPort), ($_.RemoteAddress+':'+$_.RemotePort), $proc }" >> "%LOGFILE%" 2>nul

PowerShell -NoProfile -Command "Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | ForEach-Object { $proc = 'N/A'; try { $proc = (Get-Process -Id $_.OwningProcess -EA Stop).Name } catch {}; '  {0,-22} -> {1,-22} [{2}]' -f ($_.LocalAddress+':'+$_.LocalPort), ($_.RemoteAddress+':'+$_.RemotePort), $proc }"

echo.
echo. >> "%LOGFILE%"

:: ==========================================
:: SECCION 2: Puertos en LISTEN
:: ==========================================
echo  [PUERTOS ESCUCHANDO]
echo  Puertos abiertos esperando conexiones.
echo  Un puerto desconocido puede indicar malware.
echo.
echo [PUERTOS ESCUCHANDO] >> "%LOGFILE%"

PowerShell -NoProfile -Command "Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Sort-Object LocalPort -Unique | ForEach-Object { $proc = 'N/A'; try { $proc = (Get-Process -Id $_.OwningProcess -EA Stop).Name } catch {}; '  Puerto {0,-6} [{1}]' -f $_.LocalPort, $proc }" >> "%LOGFILE%" 2>nul

PowerShell -NoProfile -Command "Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Sort-Object LocalPort -Unique | ForEach-Object { $proc = 'N/A'; try { $proc = (Get-Process -Id $_.OwningProcess -EA Stop).Name } catch {}; '  Puerto {0,-6} [{1}]' -f $_.LocalPort, $proc }"

echo.
echo. >> "%LOGFILE%"

:: ==========================================
:: SECCION 3: Conexiones a IPs externas
:: ==========================================
echo  [CONEXIONES A INTERNET]
echo  Procesos con conexiones activas a IPs externas.
echo  Si hay un proceso desconocido aqui, vale investigar.
echo.
echo [CONEXIONES A INTERNET] >> "%LOGFILE%"

PowerShell -NoProfile -Command "Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | Where-Object { $_.RemoteAddress -notmatch '^(127\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|::1|0\.0\.0\.0)' } | ForEach-Object { $proc = 'N/A'; try { $proc = (Get-Process -Id $_.OwningProcess -EA Stop).Name } catch {}; '  {0,-20} -> {1}' -f $proc, $_.RemoteAddress } | Sort-Object -Unique" >> "%LOGFILE%" 2>nul

PowerShell -NoProfile -Command "Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | Where-Object { $_.RemoteAddress -notmatch '^(127\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|::1|0\.0\.0\.0)' } | ForEach-Object { $proc = 'N/A'; try { $proc = (Get-Process -Id $_.OwningProcess -EA Stop).Name } catch {}; '  {0,-20} -> {1}' -f $proc, $_.RemoteAddress } | Sort-Object -Unique"

echo.
echo. >> "%LOGFILE%"

:: ==========================================
:: SECCION 4: Puertos UDP
:: ==========================================
echo  [PUERTOS UDP ACTIVOS]
echo.
echo [PUERTOS UDP] >> "%LOGFILE%"

PowerShell -NoProfile -Command "Get-NetUDPEndpoint -ErrorAction SilentlyContinue | Sort-Object LocalPort -Unique | ForEach-Object { $proc = 'N/A'; try { $proc = (Get-Process -Id $_.OwningProcess -EA Stop).Name } catch {}; '  Puerto {0,-6} [{1}]' -f $_.LocalPort, $proc }" >> "%LOGFILE%" 2>nul

PowerShell -NoProfile -Command "Get-NetUDPEndpoint -ErrorAction SilentlyContinue | Sort-Object LocalPort -Unique | ForEach-Object { $proc = 'N/A'; try { $proc = (Get-Process -Id $_.OwningProcess -EA Stop).Name } catch {}; '  Puerto {0,-6} [{1}]' -f $_.LocalPort, $proc }"

echo.
echo. >> "%LOGFILE%"

echo ==========================================   >> "%LOGFILE%"
echo    FIN DEL REPORTE                          >> "%LOGFILE%"
echo ==========================================   >> "%LOGFILE%"

echo  ==========================================
echo  Log: %LOGFILE%
echo  ==========================================
echo.
pause
endlocal
exit /b