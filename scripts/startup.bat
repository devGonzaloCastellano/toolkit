@echo off
title Programas al Inicio
chcp 65001 >nul
setlocal enabledelayedexpansion

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Solicitando permisos de administrador...
    PowerShell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

for /f %%a in ('PowerShell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HH-mm"') do set "TIMESTAMP=%%a"
set "LOGFILE=%~dp0..\logs\startup_%TIMESTAMP%.txt"

if not exist "%~dp0..\logs" mkdir "%~dp0..\logs"
if exist "%LOGFILE%" del "%LOGFILE%"

echo.
echo  ==========================================
echo    PROGRAMAS AL INICIO DE WINDOWS
echo  ==========================================
echo.
echo  Solo muestra. No desactiva nada.
echo.

echo ==========================================   >> "%LOGFILE%"
echo    PROGRAMAS AL INICIO DE WINDOWS          >> "%LOGFILE%"
echo ==========================================   >> "%LOGFILE%"
echo.                                            >> "%LOGFILE%"

:: ==========================================
:: SECCION 1: Registro - usuario actual (HKCU)
:: ==========================================
echo  [REGISTRO - USUARIO ACTUAL]
echo [REGISTRO - USUARIO ACTUAL] >> "%LOGFILE%"
echo  (HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run)
echo.

for /f "usebackq tokens=1,* delims= " %%a in (`PowerShell -NoProfile -Command ^
    "Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 2>$null | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { $val = (Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run').$($_.Name); '{0,-40} {1}' -f $_.Name, $val }" 2^>nul`) do (
    echo   %%a %%b
    echo   %%a %%b >> "%LOGFILE%"
)
echo.
echo. >> "%LOGFILE%"

:: ==========================================
:: SECCION 2: Registro - sistema (HKLM)
:: ==========================================
echo  [REGISTRO - SISTEMA]
echo [REGISTRO - SISTEMA] >> "%LOGFILE%"
echo  (HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run)
echo.

for /f "usebackq tokens=1,* delims= " %%a in (`PowerShell -NoProfile -Command ^
    "Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 2>$null | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { $val = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run').$($_.Name); '{0,-40} {1}' -f $_.Name, $val }" 2^>nul`) do (
    echo   %%a %%b
    echo   %%a %%b >> "%LOGFILE%"
)
echo.
echo. >> "%LOGFILE%"

:: ==========================================
:: SECCION 3: Carpeta Inicio del usuario
:: ==========================================
echo  [CARPETA INICIO - USUARIO]
echo [CARPETA INICIO - USUARIO] >> "%LOGFILE%"
echo  (%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup)
echo.

set "STARTUP_USER=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
for /f "usebackq delims=" %%a in (`dir /b "%STARTUP_USER%" 2^>nul`) do (
    echo   %%a
    echo   %%a >> "%LOGFILE%"
)
echo.
echo. >> "%LOGFILE%"

:: ==========================================
:: SECCION 4: Carpeta Inicio del sistema
:: ==========================================
echo  [CARPETA INICIO - SISTEMA]
echo [CARPETA INICIO - SISTEMA] >> "%LOGFILE%"
echo  (C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp)
echo.

set "STARTUP_SYS=C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"
for /f "usebackq delims=" %%a in (`dir /b "%STARTUP_SYS%" 2^>nul`) do (
    echo   %%a
    echo   %%a >> "%LOGFILE%"
)
echo.
echo. >> "%LOGFILE%"

:: ==========================================
:: SECCION 5: Task Scheduler - tareas al inicio
:: ==========================================
echo  [TAREAS PROGRAMADAS AL INICIO]
echo [TAREAS PROGRAMADAS AL INICIO] >> "%LOGFILE%"
echo  (Task Scheduler con trigger AtStartup)
echo.

for /f "usebackq delims=" %%a in (`PowerShell -NoProfile -Command ^
    "Get-ScheduledTask | Where-Object { $_.Triggers -match 'Boot' -or $_.Triggers -match 'Logon' } | Where-Object { $_.State -ne 'Disabled' } | ForEach-Object { '{0,-50} [{1}]' -f $_.TaskName, $_.State }" 2^>nul`) do (
    echo   %%a
    echo   %%a >> "%LOGFILE%"
)
echo.
echo. >> "%LOGFILE%"

echo  ==========================================
echo  Para deshabilitar un programa del registro:
echo    reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "NombrePrograma" /f
echo.
echo  Para deshabilitar una tarea programada:
echo    schtasks /Change /TN "NombreTarea" /Disable
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