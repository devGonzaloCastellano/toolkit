@echo off
title Windows Defender - Actualizacion
chcp 65001 >nul
setlocal enabledelayedexpansion

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Solicitando permisos de administrador...
    PowerShell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

for /f %%a in ('PowerShell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HH-mm"') do set "TIMESTAMP=%%a"
set "LOGFILE=%~dp0..\logs\defender_%TIMESTAMP%.txt"

if not exist "%~dp0..\logs" mkdir "%~dp0..\logs"
if exist "%LOGFILE%" del "%LOGFILE%"

echo.
echo  ==========================================
echo    WINDOWS DEFENDER
echo  ==========================================
echo.

echo ==========================================   >> "%LOGFILE%"
echo    WINDOWS DEFENDER                         >> "%LOGFILE%"
echo ==========================================   >> "%LOGFILE%"
echo.                                            >> "%LOGFILE%"

:: ==========================================
:: SECCION 1: Estado actual de Defender
:: ==========================================
echo  [ESTADO ACTUAL]
echo [ESTADO ACTUAL] >> "%LOGFILE%"
echo.

PowerShell -NoProfile -Command "$s = Get-MpComputerStatus -EA SilentlyContinue; if ($s) { '  Proteccion en tiempo real: ' + $s.RealTimeProtectionEnabled; '  Antivirus habilitado:       ' + $s.AntivirusEnabled; '  Antispyware habilitado:     ' + $s.AntispywareEnabled; '  Version de firma AV:        ' + $s.AntivirusSignatureVersion; '  Ultima actualizacion firma: ' + $s.AntivirusSignatureLastUpdated; '  Version de firma AS:        ' + $s.AntispywareSignatureVersion; '  Ultimo escaneo rapido:      ' + $s.QuickScanAge + ' dias atras'; '  Ultimo escaneo completo:    ' + $(if ($s.FullScanAge -ge 4294967295) { 'Nunca' } else { $s.FullScanAge.ToString() + ' dias atras' }) } else { '  No se pudo obtener estado de Defender' }" >> "%LOGFILE%" 2>nul
PowerShell -NoProfile -Command "$s = Get-MpComputerStatus -EA SilentlyContinue; if ($s) { '  Proteccion en tiempo real: ' + $s.RealTimeProtectionEnabled; '  Antivirus habilitado:       ' + $s.AntivirusEnabled; '  Antispyware habilitado:     ' + $s.AntispywareEnabled; '  Version de firma AV:        ' + $s.AntivirusSignatureVersion; '  Ultima actualizacion firma: ' + $s.AntivirusSignatureLastUpdated; '  Version de firma AS:        ' + $s.AntispywareSignatureVersion; '  Ultimo escaneo rapido:      ' + $s.QuickScanAge + ' dias atras'; '  Ultimo escaneo completo:    ' + $(if ($s.FullScanAge -ge 4294967295) { 'Nunca' } else { $s.FullScanAge.ToString() + ' dias atras' }) } else { '  No se pudo obtener estado de Defender' }"

echo.
echo. >> "%LOGFILE%"

:: ==========================================
:: SECCION 2: Actualizar definiciones
:: ==========================================
echo  [ACTUALIZANDO DEFINICIONES]
echo  Descargando ultimas firmas desde Microsoft.
echo  Requiere conexion a internet.
echo  Puede tardar 1-5 minutos.
echo.
echo [ACTUALIZACION] >> "%LOGFILE%"

PowerShell -NoProfile -Command "Update-MpSignature -EA SilentlyContinue; Write-Output 'Actualizacion solicitada.'" >> "%LOGFILE%" 2>nul
PowerShell -NoProfile -Command "Update-MpSignature -EA SilentlyContinue; Write-Output '  Actualizacion completada.'"

echo.
echo. >> "%LOGFILE%"

:: ==========================================
:: SECCION 3: Estado post-actualizacion
:: ==========================================
echo  [ESTADO POST-ACTUALIZACION]
echo [ESTADO POST-ACTUALIZACION] >> "%LOGFILE%"
echo.

PowerShell -NoProfile -Command "$s = Get-MpComputerStatus -EA SilentlyContinue; if ($s) { '  Version de firma AV:        ' + $s.AntivirusSignatureVersion; '  Ultima actualizacion firma: ' + $s.AntivirusSignatureLastUpdated }" >> "%LOGFILE%" 2>nul
PowerShell -NoProfile -Command "$s = Get-MpComputerStatus -EA SilentlyContinue; if ($s) { '  Version de firma AV:        ' + $s.AntivirusSignatureVersion; '  Ultima actualizacion firma: ' + $s.AntivirusSignatureLastUpdated }"

echo.
echo. >> "%LOGFILE%"

:: ==========================================
:: SECCION 4: Escaneo rapido opcional
:: ==========================================
echo  [ESCANEO RAPIDO]
echo  Un escaneo rapido revisa las areas mas
echo  comunes donde el malware se aloja:
echo  memoria, registro y carpetas de inicio.
echo  Tarda entre 5 y 15 minutos.
echo.
set /p "SCAN=  Ejecutar escaneo rapido ahora? (s/n): "

if /i "!SCAN!"=="s" (
    echo.
    echo  Iniciando escaneo rapido...
    echo  No cerrar esta ventana.
    echo.
    echo [ESCANEO RAPIDO] >> "%LOGFILE%"
    PowerShell -NoProfile -Command "Start-MpScan -ScanType QuickScan -EA SilentlyContinue; Write-Output '  Escaneo completado.'" >> "%LOGFILE%" 2>nul
    PowerShell -NoProfile -Command "Start-MpScan -ScanType QuickScan -EA SilentlyContinue; Write-Output '  Escaneo completado.'"

    :: Mostrar amenazas detectadas si las hay
    echo.
    echo  [AMENAZAS DETECTADAS]
    echo [AMENAZAS DETECTADAS] >> "%LOGFILE%"
    PowerShell -NoProfile -Command "$t = Get-MpThreatDetection -EA SilentlyContinue; if ($t) { $t | ForEach-Object { '  AMENAZA: ' + $_.ThreatName + ' - ' + $_.Resources } } else { '  Sin amenazas detectadas.' }" >> "%LOGFILE%" 2>nul
    PowerShell -NoProfile -Command "$t = Get-MpThreatDetection -EA SilentlyContinue; if ($t) { $t | ForEach-Object { '  AMENAZA: ' + $_.ThreatName + ' - ' + $_.Resources } } else { '  Sin amenazas detectadas.' }"
) else (
    echo  Escaneo omitido.
    echo  Escaneo omitido. >> "%LOGFILE%"
)

echo.
echo. >> "%LOGFILE%"

echo ==========================================   >> "%LOGFILE%"
echo    FIN DEL REPORTE                          >> "%LOGFILE%"
echo ==========================================   >> "%LOGFILE%"

echo.
echo  ==========================================
echo  Log: %LOGFILE%
echo  ==========================================
echo.
pause
endlocal
exit /b