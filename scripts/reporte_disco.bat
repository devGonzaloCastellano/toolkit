@echo off
title Reporte de Disco
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
for /f %%a in ('PowerShell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HH-mm"') do set "TIMESTAMP=%%a"
set "LOGFILE=%~dp0..\logs\reporte_disco_%TIMESTAMP%.txt"

if not exist "%~dp0..\logs" mkdir "%~dp0..\logs"
if exist "%LOGFILE%" del "%LOGFILE%"

echo.
echo  Analizando discos... esto puede tardar unos segundos.
echo.

call :PRINT "=========================================="
call :PRINT "   REPORTE DE DISCO"
call :PRINT "=========================================="
call :NEWLINE

:: ==========================================
:: SECCION 1: Discos fisicos
:: (capacidad via PowerShell para evitar overflow de 32 bits)
:: ==========================================
call :PRINT "[DISCOS FISICOS]"
call :PRINT "  (SMART: OK = sano / Pred Fail = fallo inminente)"
call :NEWLINE

for /f "usebackq tokens=1,2,3,4 delims=|" %%a in (`PowerShell -NoProfile -Command ^
    "Get-WmiObject Win32_DiskDrive | ForEach-Object { $gb=[math]::Round($_.Size/1GB,1); '{0}|{1}|{2}|{3}' -f $_.Index, $_.Model.Trim(), $gb, $_.InterfaceType }" 2^>nul`) do (
    call :PRINT "  Disco %%a:      %%b"
    call :PRINT "  Capacidad:     %%c GB"
    call :PRINT "  Interfaz:      %%d"

    :: Estado SMART via wmic (mas confiable para esto)
    for /f "tokens=2 delims==" %%s in ('wmic diskdrive where "Index=%%a" get Status /value 2^>nul') do (
        if not "%%s"=="" call :PRINT "  Estado SMART:  %%s"
    )
    call :NEWLINE
)

:: ==========================================
:: SECCION 2: Particiones con espacio y porcentaje
:: (tokens=1,2,3,4,5 para capturar el 5to valor = porcentaje)
:: ==========================================
call :PRINT "[PARTICIONES]"
call :NEWLINE

for /f "usebackq tokens=1,2,3,4,5 delims=|" %%a in (`PowerShell -NoProfile -Command ^
    "Get-PSDrive -PSProvider FileSystem | Where-Object {$_.Used -ne $null} | ForEach-Object { $total=[math]::Round(($_.Used+$_.Free)/1GB,1); $usado=[math]::Round($_.Used/1GB,1); $libre=[math]::Round($_.Free/1GB,1); $pct=[math]::Round($_.Used/($_.Used+$_.Free)*100,0); '{0}|{1}|{2}|{3}|{4}' -f $_.Name,$total,$usado,$libre,$pct }" 2^>nul`) do (
    if not "%%a"=="" (
        call :PRINT "  Unidad %%a:"
        call :PRINT "    Total:     %%b GB"
        call :PRINT "    Usado:     %%c GB"
        call :PRINT "    Libre:     %%d GB"
        if not "%%e"=="" (
            call :PRINT "    Uso:       %%e%%"
            if %%e GEQ 90 call :PRINT "    ATENCION:  disco casi lleno ^(+90%%^)"
        ) else (
            call :PRINT "    Uso:       0%%"
        )
        call :NEWLINE
    )
)

:: ==========================================
:: SECCION 3: chkdsk - solo al log, sin findstr
:: ==========================================
call :PRINT "[VERIFICACION DE ERRORES - CHKDSK]"
call :PRINT "  Modo lectura: no modifica nada, solo reporta."
call :NEWLINE

for /f "usebackq tokens=1 delims=|" %%a in (`PowerShell -NoProfile -Command ^
    "Get-PSDrive -PSProvider FileSystem | Where-Object {$_.Used -ne $null} | ForEach-Object { $_.Name }" 2^>nul`) do (
    call :PRINT "  --- Unidad %%a: ---"
    echo  Verificando unidad %%a:...
    echo --- chkdsk %%a: --- >> "%LOGFILE%"
    chkdsk %%a: >> "%LOGFILE%" 2>&1
    set "CHKDSK_EXIT=!errorLevel!"
    if !CHKDSK_EXIT!==0 (
        call :PRINT "  Sin errores detectados."
    ) else (
        call :PRINT "  Se detectaron advertencias. Ver log para detalle."
    )
    call :NEWLINE
)

:: ==========================================
:: SECCION 4: Carpetas mas pesadas en C:\
:: ==========================================
call :PRINT "[CARPETAS MAS PESADAS EN C:\]"
call :PRINT "  Top 10 por tamanio:"
call :NEWLINE

for /f "usebackq delims=" %%a in (`PowerShell -NoProfile -Command ^
    "Get-ChildItem 'C:\' -Directory -ErrorAction SilentlyContinue | ForEach-Object { $size=(Get-ChildItem $_.FullName -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum; [PSCustomObject]@{Name=$_.Name;SizeGB=[math]::Round($size/1GB,2)} } | Sort-Object SizeGB -Descending | Select-Object -First 10 | ForEach-Object { '{0,-35} {1,8} GB' -f $_.Name,$_.SizeGB }" 2^>nul`) do (
    call :PRINT "  %%a"
)
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