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
:: Timestamp y rutas
:: ----------------------------------------
for /f %%a in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HH-mm"') do set "TIMESTAMP=%%a"
set "LOGFILE=%~dp0..\logs\limpieza_%TIMESTAMP%.txt"

if not exist "%~dp0..\logs" mkdir "%~dp0..\logs"
if exist "%LOGFILE%" del "%LOGFILE%"

:: ----------------------------------------
:: Variables de contadores (una por seccion)
:: ----------------------------------------
set "COUNT_TEMP_USER=0"
set "COUNT_TEMP_SYS=0"
set "COUNT_PREFETCH=0"
set "COUNT_RECIENTES=0"
set "COUNT_WUPDATE=0"

:: ----------------------------------------
:: Variables de espacio y tiempo
:: ----------------------------------------
set "ANTES=0"
set "DESPUES=0"
set "INICIO="

:: ----------------------------------------
:: Registro de inicio en log
:: ----------------------------------------
echo ==========================================   >> "%LOGFILE%"
echo    LIMPIEZA DE SISTEMA                      >> "%LOGFILE%"
echo    Fecha: %TIMESTAMP%                       >> "%LOGFILE%"
echo ==========================================   >> "%LOGFILE%"
echo.                                            >> "%LOGFILE%"

echo.
echo ==========================================
echo   LIMPIEZA DE SISTEMA
echo ==========================================
echo.

:: ----------------------------------------
:: Espacio ANTES y tiempo de inicio
:: Captura el espacio libre en C: antes de limpiar
:: y el timestamp de inicio para calcular duracion
:: ----------------------------------------
for /f %%a in ('powershell -NoProfile -Command "(Get-PSDrive C).Free"') do set "ANTES=%%a"
for /f %%a in ('powershell -NoProfile -Command "Get-Date -Format HH:mm:ss"') do set "INICIO=%%a"

:: ----------------------------------------
echo [1/7] Limpiando archivos temporales de usuario...
:: del no devuelve conteo, se captura la salida y se cuentan
:: las lineas que contienen la palabra "eliminado"
:: ----------------------------------------
set "TMP_OUT=%TEMP%\limpieza_count.tmp"

del /s /f /q %temp%\*.* > "%TMP_OUT%" 2>nul
for /d %%p in (%temp%\*) do rmdir "%%p" /s /q 2>nul
for /f %%a in ('findstr /i /c:"eliminado" "%TMP_OUT%" 2^>nul ^| find /c /v ""') do set "COUNT_TEMP_USER=%%a"
if exist "%TMP_OUT%" del "%TMP_OUT%" >nul
echo     OK. Archivos eliminados: %COUNT_TEMP_USER%
echo [1/7] Temporales usuario: %COUNT_TEMP_USER% archivos eliminados >> "%LOGFILE%"

:: ----------------------------------------
echo [2/7] Limpiando temporales del sistema...
:: ----------------------------------------
del /s /f /q C:\Windows\Temp\*.* > "%TMP_OUT%" 2>nul
for /d %%p in (C:\Windows\Temp\*) do rmdir "%%p" /s /q 2>nul
for /f %%a in ('findstr /i /c:"eliminado" "%TMP_OUT%" 2^>nul ^| find /c /v ""') do set "COUNT_TEMP_SYS=%%a"
if exist "%TMP_OUT%" del "%TMP_OUT%" >nul
echo     OK. Archivos eliminados: %COUNT_TEMP_SYS%
echo [2/7] Temporales sistema: %COUNT_TEMP_SYS% archivos eliminados >> "%LOGFILE%"

:: ----------------------------------------
echo [3/7] Limpiando Prefetch...
:: ----------------------------------------
del /s /f /q C:\Windows\Prefetch\*.* > "%TMP_OUT%" 2>nul
for /f %%a in ('findstr /i /c:"eliminado" "%TMP_OUT%" 2^>nul ^| find /c /v ""') do set "COUNT_PREFETCH=%%a"
if exist "%TMP_OUT%" del "%TMP_OUT%" >nul
echo     OK. Archivos eliminados: %COUNT_PREFETCH%
echo [3/7] Prefetch: %COUNT_PREFETCH% archivos eliminados >> "%LOGFILE%"

:: ----------------------------------------
echo [4/7] Limpiando historial de archivos recientes...
:: ----------------------------------------
del /s /f /q "%APPDATA%\Microsoft\Windows\Recent\*" > "%TMP_OUT%" 2>nul
for /f %%a in ('findstr /i /c:"eliminado" "%TMP_OUT%" 2^>nul ^| find /c /v ""') do set "COUNT_RECIENTES=%%a"
if exist "%TMP_OUT%" del "%TMP_OUT%" >nul
echo     OK. Archivos eliminados: %COUNT_RECIENTES%
echo [4/7] Recientes: %COUNT_RECIENTES% archivos eliminados >> "%LOGFILE%"

:: ----------------------------------------
echo [5/7] Limpiando cache de Windows Update...
:: ----------------------------------------
net stop wuauserv >nul 2>&1
net stop bits >nul 2>&1
del /s /f /q C:\Windows\SoftwareDistribution\Download\*.* > "%TMP_OUT%" 2>nul
for /d %%p in (C:\Windows\SoftwareDistribution\Download\*) do rmdir "%%p" /s /q 2>nul
for /f %%a in ('findstr /i /c:"eliminado" "%TMP_OUT%" 2^>nul ^| find /c /v ""') do set "COUNT_WUPDATE=%%a"
if exist "%TMP_OUT%" del "%TMP_OUT%" >nul
net start wuauserv >nul 2>&1
net start bits >nul 2>&1
echo     OK. Archivos eliminados: %COUNT_WUPDATE%
echo [5/7] Windows Update cache: %COUNT_WUPDATE% archivos eliminados >> "%LOGFILE%"

:: ----------------------------------------
echo [6/7] Limpiando cache de DNS y vaciando Papelera...
:: ----------------------------------------
ipconfig /flushdns >nul
PowerShell -Command "Clear-RecycleBin -Force -ErrorAction SilentlyContinue"
echo     OK.
echo [6/7] DNS flush y Papelera: completado >> "%LOGFILE%"

:: ----------------------------------------
echo [7/7] Ejecutando Limpieza de Disco (Disk Cleanup)...
:: ----------------------------------------
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Temporary Files" /v StateFlags0002 /t REG_DWORD /d 2 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Thumbnail Cache" /v StateFlags0002 /t REG_DWORD /d 2 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Recycle Bin" /v StateFlags0002 /t REG_DWORD /d 2 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Internet Cache Files" /v StateFlags0002 /t REG_DWORD /d 2 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Delivery Optimization Files" /v StateFlags0002 /t REG_DWORD /d 2 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Windows Error Reporting Files" /v StateFlags0002 /t REG_DWORD /d 2 /f >nul 2>&1
cleanmgr /sagerun:2
echo     OK.
echo [7/7] Disk Cleanup: completado >> "%LOGFILE%"

:: ----------------------------------------
:: Espacio DESPUES y calculo de duracion
:: New-TimeSpan calcula la diferencia entre dos timestamps
:: ----------------------------------------
for /f %%a in ('powershell -NoProfile -Command "(Get-PSDrive C).Free"') do set "DESPUES=%%a"
for /f %%a in ('powershell -NoProfile -Command ^
    "$dur = New-TimeSpan -Start ([datetime]::ParseExact('%INICIO%','HH:mm:ss',$null)) -End (Get-Date); '{0}s' -f [math]::Round($dur.TotalSeconds,1)"') do set "DURACION=%%a"
:: ----------------------------------------
:: Calculo de espacio liberado en MB y GB
:: Se usa InvariantCulture para forzar punto como separador decimal
:: ----------------------------------------
for /f %%a in ('powershell -NoProfile -Command ^
    "$lib = %DESPUES%-%ANTES%; if ($lib -lt 0) { '0' } else { [math]::Round($lib/1MB,1).ToString([System.Globalization.CultureInfo]::InvariantCulture) }"') do set "LIBERADO_MB=%%a"
for /f %%a in ('powershell -NoProfile -Command ^
    "$lib = %DESPUES%-%ANTES%; if ($lib -lt 0) { '0' } else { [math]::Round($lib/1GB,2).ToString([System.Globalization.CultureInfo]::InvariantCulture) }"') do set "LIBERADO_GB=%%a"
:: ----------------------------------------
:: Suma total de archivos eliminados
:: ----------------------------------------
set /a "TOTAL_ARCHIVOS=%COUNT_TEMP_USER%+%COUNT_TEMP_SYS%+%COUNT_PREFETCH%+%COUNT_RECIENTES%+%COUNT_WUPDATE%"

:: ----------------------------------------
:: Resumen en consola y log
:: ----------------------------------------
echo.
echo ==========================================
echo   LIMPIEZA COMPLETA
echo ==========================================
echo.
echo   Duracion:          %DURACION%
echo   Archivos totales:  %TOTAL_ARCHIVOS%
echo     - Temp usuario:  %COUNT_TEMP_USER%
echo     - Temp sistema:  %COUNT_TEMP_SYS%
echo     - Prefetch:      %COUNT_PREFETCH%
echo     - Recientes:     %COUNT_RECIENTES%
echo     - Windows Update:%COUNT_WUPDATE%
echo.
echo   Espacio liberado:  %LIBERADO_MB% MB  (%LIBERADO_GB% GB)
echo.
echo   Nota: Disk Cleanup puede seguir corriendo
echo   en segundo plano unos segundos mas.
echo.

echo.                                            >> "%LOGFILE%"
echo ==========================================   >> "%LOGFILE%"
echo    RESUMEN                                  >> "%LOGFILE%"
echo ==========================================   >> "%LOGFILE%"
echo    Duracion:          %DURACION%            >> "%LOGFILE%"
echo    Archivos totales:  %TOTAL_ARCHIVOS%      >> "%LOGFILE%"
echo      - Temp usuario:  %COUNT_TEMP_USER%     >> "%LOGFILE%"
echo      - Temp sistema:  %COUNT_TEMP_SYS%      >> "%LOGFILE%"
echo      - Prefetch:      %COUNT_PREFETCH%      >> "%LOGFILE%"
echo      - Recientes:     %COUNT_RECIENTES%     >> "%LOGFILE%"
echo      - Windows Update:%COUNT_WUPDATE%       >> "%LOGFILE%"
echo    Espacio liberado:  %LIBERADO_MB% MB  (%LIBERADO_GB% GB) >> "%LOGFILE%"
echo ==========================================   >> "%LOGFILE%"

pause