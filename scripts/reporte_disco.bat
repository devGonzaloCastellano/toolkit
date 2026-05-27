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
for /f %%a in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HH-mm"') do set "TIMESTAMP=%%a"
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "Get-Date -Format 'dd/MM/yyyy HH:mm:ss'"`) do set "FECHAHORA=%%a"
set "LOGFILE=%~dp0..\logs\reporte_disco_%TIMESTAMP%.txt"

if not exist "%~dp0..\logs" mkdir "%~dp0..\logs"
if exist "%LOGFILE%" del "%LOGFILE%"

echo.
echo  Analizando discos... esto puede tardar unos segundos.
echo.

echo ==========================================  >> "%LOGFILE%"
echo    REPORTE DE DISCO                         >> "%LOGFILE%"
echo    Inicio: %FECHAHORA%                      >> "%LOGFILE%"
echo ==========================================  >> "%LOGFILE%"
echo.                                            >> "%LOGFILE%"

call :PRINT "=========================================="
call :PRINT "   REPORTE DE DISCO"
call :PRINT "=========================================="
call :NEWLINE

:: ==========================================
:: SECCION 1: chkdsk - solo al log, sin findstr
:: ==========================================
call :PRINT "[VERIFICACION DE ERRORES - CHKDSK]"
call :PRINT "  Modo lectura: no modifica nada, solo reporta."
call :NEWLINE

for /f "usebackq tokens=1 delims=|" %%a in (`PowerShell -NoProfile -Command ^
    "Get-PSDrive -PSProvider FileSystem | Where-Object {$_.Used -ne $null} | ForEach-Object { $_.Name }" 2^>nul`) do (

    call :PRINT "  --- Unidad %%a: ---"

    :: Guardamos el progreso en un archivo temporal para poder filtrar el ruido después
    echo Verificando unidad %%a:...
    echo  Este proceso puede tardar varios minutos en HDDs.
    echo  El programa sigue corriendo en segundo plano.
    echo  Por favor no cerrar esta ventana.
    echo --- chkdsk %%a: --- >> "%LOGFILE%"

    chkdsk %%a: > "%TEMP%\chkdsk_tmp.txt" 2>&1
    set "CHKDSK_EXIT=!errorLevel!"

    :: Filtramos el archivo temporal: solo guardamos las líneas importantes en el log real
    type "%TEMP%\chkdsk_tmp.txt" | findstr /i /c:"error" /c:"dañado" /c:"reparar" /c:"problema" /c:"sectores" /c:"encontró" /c:"Windows comprobó el sistema de archivos" >> "%LOGFILE%"
    del "%TEMP%\chkdsk_tmp.txt" 2>nul

   :: Reporte en la consola basado en el ErrorLevel de CHKDSK
   if !CHKDSK_EXIT!==0 (
       call :PRINT "  [OK] %%a: Sin errores detectados."
   ) else if !CHKDSK_EXIT!==1 (
       call :PRINT "  [OK] %%a: Se encontraron errores menores de formato y se arreglaron (Modo lectura)."
   ) else (
       call :PRINT "  [ALERTA] Se detectaron problemas en %%a:."
       call :PRINT "  Nota: En la unidad del sistema esto suele ser un falso positivo por estar en uso."
       call :PRINT "  Se sugiere ejecutar de forma manual: chkdsk %%a: /scan /forceofflinefix"
   )
    call :NEWLINE
)

:: ==========================================
:: SECCION 2: Carpetas mas pesadas en C:\
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

for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "Get-Date -Format 'dd/MM/yyyy HH:mm:ss'"`) do set "FECHAHORA_FIN=%%a"
echo.
echo  ==========================================
echo  Reporte completado.
echo  FIN: %FECHAHORA_FIN%                    >> "%LOGFILE%"
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