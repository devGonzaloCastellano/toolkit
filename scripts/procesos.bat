@echo off
title Procesos en Ejecucion
chcp 65001 >nul
setlocal enabledelayedexpansion

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Solicitando permisos de administrador...
    PowerShell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

for /f %%a in ('PowerShell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HH-mm"') do set "TIMESTAMP=%%a"
set "LOGFILE=%~dp0..\logs\procesos_%TIMESTAMP%.txt"

if not exist "%~dp0..\logs" mkdir "%~dp0..\logs"
if exist "%LOGFILE%" del "%LOGFILE%"

echo.
echo  Relevando procesos... un momento.
echo.

call :PRINT "=========================================="
call :PRINT "   PROCESOS EN EJECUCION"
call :PRINT "=========================================="
call :NEWLINE

:: ==========================================
:: SECCION 1: Resumen de recursos
:: ==========================================
call :PRINT "[RESUMEN DE RECURSOS]"
call :NEWLINE

:: CPU via wmic /value - una sola linea garantizada
set "KSO_CPU="
for /f "tokens=2 delims==" %%a in ('wmic cpu get LoadPercentage /value 2^>nul ^| findstr "="') do (
    if not defined KSO_CPU set "KSO_CPU=%%a"
)

:: RAM via wmic /value
set "KSO_TOTAL="
set "KSO_FREE="
for /f "tokens=2 delims==" %%a in ('wmic os get TotalVisibleMemorySize /value 2^>nul ^| findstr "="') do set "KSO_TOTAL=%%a"
for /f "tokens=2 delims==" %%a in ('wmic os get FreePhysicalMemory /value 2^>nul ^| findstr "="') do set "KSO_FREE=%%a"
set /a "KSO_USADO=%KSO_TOTAL%/1024 - %KSO_FREE%/1024"
set /a "KSO_TOTAL_MB=%KSO_TOTAL%/1024"
set /a "KSO_PCT=(%KSO_TOTAL% - %KSO_FREE%) * 100 / %KSO_TOTAL%"

call :PRINT "  CPU uso global:   %KSO_CPU%%%"
call :PRINT "  RAM usada:        %KSO_USADO% MB de %KSO_TOTAL_MB% MB (%KSO_PCT%%%)"
call :NEWLINE

:: ==========================================
:: SECCION 2: Top 15 por CPU
:: ==========================================
call :PRINT "[TOP 15 PROCESOS POR CPU]"
call :NEWLINE
call :PRINT "  Nombre                           PID     CPU%%    Ruta"
call :PRINT "  ---------------------------------------------------------------"

for /f "usebackq delims=" %%a in (`PowerShell -NoProfile -Command "Get-Process|Sort-Object CPU -Descending|Select-Object -First 15|ForEach-Object{$path='N/A';try{$p=$_.MainModule.FileName;if($p){$path=$p}}catch{};'  {0,-32} {1,6}  {2,6}%%  {3}' -f $_.Name,$_.Id,[math]::Round($_.CPU,1),$path}" 2^>nul`) do call :PRINT "%%a"
call :NEWLINE

:: ==========================================
:: SECCION 3: Top 15 por RAM
:: ==========================================
call :PRINT "[TOP 15 PROCESOS POR RAM]"
call :NEWLINE
call :PRINT "  Nombre                           PID     RAM(MB)  Ruta"
call :PRINT "  ---------------------------------------------------------------"

PowerShell -NoProfile -Command "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Get-Process|Sort-Object WorkingSet -Descending|Select-Object -First 15|ForEach-Object{$path='N/A';try{$path=$_.MainModule.FileName}catch{};'  {0,-32} {1,6}  {2,7} MB  {3}' -f $_.Name,$_.Id,[math]::Round($_.WorkingSet/1MB,1),$path}" > "%TEMP%\kso_ram.tmp" 2>nul
for /f "usebackq delims=" %%a in ("%TEMP%\kso_ram.tmp") do call :PRINT "%%a"
del "%TEMP%\kso_ram.tmp" >nul 2>&1
call :NEWLINE

:: ==========================================
:: SECCION 4: Procesos con ruta inusual
:: ==========================================
call :PRINT "[PROCESOS CON RUTA INUSUAL]"
call :PRINT "  Procesos corriendo desde rutas fuera de"
call :PRINT "  System32, Program Files y AppData."
call :PRINT "  No implica malware, pero vale la pena revisar."
call :NEWLINE
call :PRINT "  Nombre                           PID     Ruta"
call :PRINT "  ---------------------------------------------------------------"

PowerShell -NoProfile -Command "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Get-Process|ForEach-Object{$path='';try{$path=$_.MainModule.FileName}catch{};if($path -and $path -notmatch 'System32|SysWOW64|Program Files|AppData|SystemApps|ImmersiveControlPanel|splwow64|Explorer|\\Windows\\'){'  {0,-32} {1,6}  {2}' -f $_.Name,$_.Id,$path}}" > "%TEMP%\kso_inusual.tmp" 2>nul
for /f "usebackq delims=" %%a in ("%TEMP%\kso_inusual.tmp") do call :PRINT "%%a"
del "%TEMP%\kso_inusual.tmp" >nul 2>&1
call :NEWLINE

:: ==========================================
:: SECCION 5: Lista completa al log
:: ==========================================
call :PRINT "[LISTA COMPLETA -> solo en log]"
echo. >> "%LOGFILE%"
echo Lista completa: >> "%LOGFILE%"
echo --------------------------------------------------------- >> "%LOGFILE%"
PowerShell -NoProfile -Command "Get-Process|Sort-Object Name|Format-Table Name,Id,CPU,@{N='RAM(MB)';E={[math]::Round($_.WorkingSet/1MB,1)}} -AutoSize|Out-String -Width 200" >> "%LOGFILE%" 2>&1
call :PRINT "  Ver log para detalle completo."
call :NEWLINE

call :PRINT "=========================================="
call :PRINT "   FIN DEL REPORTE"
call :PRINT "=========================================="

echo.
echo  ==========================================
echo  Reporte completado.
echo  Log: %LOGFILE%
echo  ==========================================
echo.
pause
endlocal
exit /b

:PRINT
echo  %~1
echo  %~1>> "%LOGFILE%"
exit /b

:NEWLINE
echo.
echo.>> "%LOGFILE%"
exit /b