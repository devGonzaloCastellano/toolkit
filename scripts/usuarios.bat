@echo off
title Usuarios del Sistema
chcp 65001 >nul
setlocal enabledelayedexpansion

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Solicitando permisos de administrador...
    PowerShell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

for /f %%a in ('PowerShell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HH-mm"') do set "TIMESTAMP=%%a"
set "LOGFILE=%~dp0..\logs\usuarios_%TIMESTAMP%.txt"

if not exist "%~dp0..\logs" mkdir "%~dp0..\logs"
if exist "%LOGFILE%" del "%LOGFILE%"

echo.
echo  ==========================================
echo    USUARIOS DEL SISTEMA
echo  ==========================================
echo.

echo ==========================================   >> "%LOGFILE%"
echo    USUARIOS DEL SISTEMA                     >> "%LOGFILE%"
echo ==========================================   >> "%LOGFILE%"
echo.                                            >> "%LOGFILE%"

:: ==========================================
:: SECCION 1: Cuentas locales
:: ==========================================
echo  [CUENTAS LOCALES]
echo  Todas las cuentas en este equipo.
echo.
echo [CUENTAS LOCALES] >> "%LOGFILE%"

PowerShell -NoProfile -Command "Get-LocalUser | ForEach-Object { $ultimo = 'Nunca'; if ($_.LastLogon) { $ultimo = $_.LastLogon.ToString('yyyy-MM-dd HH:mm') }; '  {0,-20} Habilitada: {1,-5}  Ultimo login: {2}' -f $_.Name, $_.Enabled, $ultimo }" >> "%LOGFILE%" 2>nul
PowerShell -NoProfile -Command "Get-LocalUser | ForEach-Object { $ultimo = 'Nunca'; if ($_.LastLogon) { $ultimo = $_.LastLogon.ToString('yyyy-MM-dd HH:mm') }; '  {0,-20} Habilitada: {1,-5}  Ultimo login: {2}' -f $_.Name, $_.Enabled, $ultimo }"

echo.
echo. >> "%LOGFILE%"

:: ==========================================
:: SECCION 2: Grupos y miembros
:: ==========================================
echo  [GRUPOS Y MIEMBROS]
echo  Especialmente importante: Administradores.
echo  Un usuario desconocido en Administradores
echo  es una señal de alerta critica.
echo.
echo [GRUPOS Y MIEMBROS] >> "%LOGFILE%"

PowerShell -NoProfile -Command "Get-LocalGroup | ForEach-Object { $grupo = $_.Name; $miembros = try { (Get-LocalGroupMember $grupo -EA Stop | ForEach-Object { $_.Name }) -join ', ' } catch { 'sin miembros' }; '  [{0}] -> {1}' -f $grupo, $miembros }" >> "%LOGFILE%" 2>nul
PowerShell -NoProfile -Command "Get-LocalGroup | ForEach-Object { $grupo = $_.Name; $miembros = try { (Get-LocalGroupMember $grupo -EA Stop | ForEach-Object { $_.Name }) -join ', ' } catch { 'sin miembros' }; '  [{0}] -> {1}' -f $grupo, $miembros }"

echo.
echo. >> "%LOGFILE%"

:: ==========================================
:: SECCION 3: Cuenta de invitado
:: ==========================================
echo  [CUENTA DE INVITADO]
echo  La cuenta Guest habilitada es un riesgo
echo  de seguridad en cualquier entorno.
echo.
echo [CUENTA DE INVITADO] >> "%LOGFILE%"

PowerShell -NoProfile -Command "$g = Get-LocalUser -EA SilentlyContinue | Where-Object { $_.Name -match '^(Guest|Invitado)$' }; if ($g) { if ($g.Enabled) { '  ATENCION: Cuenta de invitado HABILITADA: ' + $g.Name } else { '  OK: Cuenta de invitado deshabilitada (' + $g.Name + ')' } } else { '  Cuenta de invitado no encontrada' }" >> "%LOGFILE%" 2>nul
PowerShell -NoProfile -Command "$g = Get-LocalUser -EA SilentlyContinue | Where-Object { $_.Name -match '^(Guest|Invitado)$' }; if ($g) { if ($g.Enabled) { '  ATENCION: Cuenta de invitado HABILITADA: ' + $g.Name } else { '  OK: Cuenta de invitado deshabilitada (' + $g.Name + ')' } } else { '  Cuenta de invitado no encontrada' }"

echo.
echo. >> "%LOGFILE%"

:: ==========================================
:: SECCION 4: Sesiones activas
:: ==========================================
echo  [SESIONES ACTIVAS]
echo  Usuarios con sesion abierta en este momento.
echo.
echo [SESIONES ACTIVAS] >> "%LOGFILE%"

query user >> "%LOGFILE%" 2>nul
query user 2>nul

echo.
echo. >> "%LOGFILE%"

:: ==========================================
:: SECCION 5: Ultimos inicios de sesion (Event Log)
:: ==========================================
echo  [ULTIMOS 10 INICIOS DE SESION]
echo  Extraido del registro de eventos de Windows.
echo.
echo [ULTIMOS 10 INICIOS DE SESION] >> "%LOGFILE%"

PowerShell -NoProfile -Command "Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4624} -MaxEvents 10 -EA SilentlyContinue | ForEach-Object { $xml = [xml]$_.ToXml(); $user = $xml.Event.EventData.Data | Where-Object { $_.Name -eq 'TargetUserName' } | Select-Object -ExpandProperty '#text'; $type = $xml.Event.EventData.Data | Where-Object { $_.Name -eq 'LogonType' } | Select-Object -ExpandProperty '#text'; if ($user -and $user -notmatch '^(SYSTEM|LOCAL SERVICE|NETWORK SERVICE|ANONYMOUS|\$)') { '  {0}  Usuario: {1,-20} Tipo: {2}' -f $_.TimeCreated.ToString('yyyy-MM-dd HH:mm'), $user, $type } }" >> "%LOGFILE%" 2>nul
PowerShell -NoProfile -Command "Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4624} -MaxEvents 10 -EA SilentlyContinue | ForEach-Object { $xml = [xml]$_.ToXml(); $user = $xml.Event.EventData.Data | Where-Object { $_.Name -eq 'TargetUserName' } | Select-Object -ExpandProperty '#text'; $type = $xml.Event.EventData.Data | Where-Object { $_.Name -eq 'LogonType' } | Select-Object -ExpandProperty '#text'; if ($user -and $user -notmatch '^(SYSTEM|LOCAL SERVICE|NETWORK SERVICE|ANONYMOUS|\$)') { '  {0}  Usuario: {1,-20} Tipo: {2}' -f $_.TimeCreated.ToString('yyyy-MM-dd HH:mm'), $user, $type } }"

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