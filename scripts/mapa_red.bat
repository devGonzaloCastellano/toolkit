@echo off
title Mapa de Red Local
chcp 65001 >nul
setlocal enabledelayedexpansion

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Solicitando permisos de administrador...
    PowerShell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

for /f %%a in ('PowerShell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HH-mm"') do set "TIMESTAMP=%%a"
set "LOGFILE=%~dp0..\logs\mapa_red_%TIMESTAMP%.txt"

if not exist "%~dp0..\logs" mkdir "%~dp0..\logs"
if exist "%LOGFILE%" del "%LOGFILE%"

echo.
echo  ==========================================
echo    MAPA DE RED LOCAL
echo  ==========================================
echo.

echo ==========================================   >> "%LOGFILE%"
echo    MAPA DE RED LOCAL                        >> "%LOGFILE%"
echo ==========================================   >> "%LOGFILE%"
echo.                                            >> "%LOGFILE%"

:: ==========================================
:: SECCION 1: Info de red del equipo actual
:: ==========================================
echo  [ESTE EQUIPO]
echo [ESTE EQUIPO] >> "%LOGFILE%"
echo.

PowerShell -NoProfile -Command "$ip = (Get-NetIPAddress -AddressFamily IPv4 -EA SilentlyContinue | Where-Object { $_.IPAddress -notmatch '^127\.' } | Select-Object -First 1); $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -EA SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1).NextHop; '  Nombre:    ' + $env:COMPUTERNAME; '  IP:        ' + $ip.IPAddress; '  Mascara:   /' + $ip.PrefixLength; '  Gateway:   ' + $gw" >> "%LOGFILE%" 2>nul
PowerShell -NoProfile -Command "$ip = (Get-NetIPAddress -AddressFamily IPv4 -EA SilentlyContinue | Where-Object { $_.IPAddress -notmatch '^127\.' } | Select-Object -First 1); $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -EA SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1).NextHop; '  Nombre:    ' + $env:COMPUTERNAME; '  IP:        ' + $ip.IPAddress; '  Mascara:   /' + $ip.PrefixLength; '  Gateway:   ' + $gw"

echo.
echo. >> "%LOGFILE%"

:: ==========================================
:: SECCION 2: Escaneo de dispositivos en la red
:: Hace ping a cada IP del rango y muestra las que responden
:: ==========================================
echo  [DISPOSITIVOS EN LA RED]
echo  Escaneando rango local... puede tardar 1-2 minutos.
echo  Solo muestra dispositivos que responden a ping.
echo.
echo [DISPOSITIVOS EN LA RED] >> "%LOGFILE%"

:: Obtener el prefijo de red (ej: 192.168.0)
for /f %%a in ('PowerShell -NoProfile -Command "(Get-NetIPAddress -AddressFamily IPv4 -EA SilentlyContinue | Where-Object { $_.IPAddress -notmatch '^127\.' } | Select-Object -First 1).IPAddress -replace '\.\d+$',''"') do set "PREFIJO=%%a"

echo  Escaneando %PREFIJO%.1 - %PREFIJO%.254...
echo  Escaneando %PREFIJO%.1 - %PREFIJO%.254... >> "%LOGFILE%"
echo.

:: Ping paralelo via PowerShell para mayor velocidad
PowerShell -NoProfile -Command "1..254 | ForEach-Object { $ip = '%PREFIJO%.' + $_; $ping = New-Object System.Net.NetworkInformation.Ping; try { $r = $ping.Send($ip, 500); if ($r.Status -eq 'Success') { $hostname = try { [System.Net.Dns]::GetHostEntry($ip).HostName } catch { 'sin nombre' }; '  {0,-18} {1}' -f $ip, $hostname } } catch {} }" >> "%LOGFILE%" 2>nul
PowerShell -NoProfile -Command "1..254 | ForEach-Object { $ip = '%PREFIJO%.' + $_; $ping = New-Object System.Net.NetworkInformation.Ping; try { $r = $ping.Send($ip, 500); if ($r.Status -eq 'Success') { $hostname = try { [System.Net.Dns]::GetHostEntry($ip).HostName } catch { 'sin nombre' }; '  {0,-18} {1}' -f $ip, $hostname } } catch {} }"

echo.
echo. >> "%LOGFILE%"

:: ==========================================
:: SECCION 3: Tabla ARP - dispositivos recientes
:: ==========================================
echo  [TABLA ARP - DISPOSITIVOS RECIENTES]
echo  Muestra dispositivos con los que el equipo
echo  se comunico recientemente, con su MAC address.
echo  La MAC permite identificar el fabricante
echo  del dispositivo (router, celular, PC, etc).
echo.
echo [TABLA ARP] >> "%LOGFILE%"

arp -a >> "%LOGFILE%" 2>nul
arp -a

echo.
echo. >> "%LOGFILE%"

:: ==========================================
:: SECCION 4: Recursos compartidos en la red
:: ==========================================
echo  [RECURSOS COMPARTIDOS DETECTADOS]
echo  Carpetas y dispositivos compartidos visibles.
echo.
echo [RECURSOS COMPARTIDOS] >> "%LOGFILE%"

net view >> "%LOGFILE%" 2>nul
net view 2>nul

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