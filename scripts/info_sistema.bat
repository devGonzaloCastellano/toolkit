@echo off
title Informacion del Sistema
chcp 65001 >nul
setlocal enabledelayedexpansion

:: ----------------------------------------
:: Timestamp via PowerShell para evitar problemas con formato regional de %date%
:: ----------------------------------------
for /f %%a in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HH-mm"') do set "TIMESTAMP=%%a"
set "LOGFILE=%~dp0..\logs\info_%TIMESTAMP%.txt"

if not exist "%~dp0..\logs" mkdir "%~dp0..\logs"
if exist "%LOGFILE%" del "%LOGFILE%"

echo.
echo  Relevando información del sistema...
echo  Esto puede tardar unos segundos.
echo.

call :PRINT "=========================================="
call :PRINT "   INFORMACIÓN DEL SISTEMA"
call :PRINT "=========================================="
call :NEWLINE

:: -- Sistema Operativo --
call :PRINT "[SISTEMA OPERATIVO]"
for /f "tokens=2 delims==" %%a in ('wmic os get Caption /value 2^>nul') do if not "%%a"=="" call :PRINT "  Nombre:       %%a"
for /f "tokens=2 delims==" %%a in ('wmic os get Version /value 2^>nul') do if not "%%a"=="" call :PRINT "  Version:      %%a"

:: UBR (Update Build Revision) complementa el BuildNumber para la version exacta del parche
for /f "tokens=2 delims==" %%a in ('wmic os get BuildNumber /value 2^>nul') do if not "%%a"=="" set "BUILD_BASE=%%a"
set "BUILD_SUB=0"
:: UBR viene en hex desde el registro, set /a lo convierte a decimal automaticamente
for /f "tokens=3" %%a in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v UBR 2^>nul ^| findstr "UBR"') do (
    set /a "BUILD_SUB=%%a"
)
call :PRINT "  Build:        %BUILD_BASE%.%BUILD_SUB%"

for /f "tokens=2 delims==" %%a in ('wmic os get OSArchitecture /value 2^>nul') do if not "%%a"=="" call :PRINT "  Arquitectura: %%a"

:: LastBootUpTime en formato legible via CimInstance, wmic devuelve formato crudo WMI
set "LAST_BOOT="
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "(Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('dd/MM/yyyy HH:mm:ss')"`) do (
    set "LAST_BOOT=%%a"
)
call :PRINT "  Ultimo inicio: %LAST_BOOT%"

call :NEWLINE

:: -- Equipo --
call :PRINT "[EQUIPO]"
for /f "tokens=2 delims==" %%a in ('wmic computersystem get Name /value 2^>nul') do if not "%%a"=="" call :PRINT "  Nombre PC:    %%a"
for /f "tokens=2 delims==" %%a in ('wmic computersystem get Manufacturer /value 2^>nul') do if not "%%a"=="" call :PRINT "  Fabricante:   %%a"
for /f "tokens=2 delims==" %%a in ('wmic computersystem get Model /value 2^>nul') do if not "%%a"=="" call :PRINT "  Modelo:       %%a"
for /f "tokens=2 delims==" %%a in ('wmic bios get SerialNumber /value 2^>nul') do if not "%%a"=="" call :PRINT "  Serie BIOS:   %%a"
call :NEWLINE

:: -- Procesador (skip=1 + goto para evitar duplicados) --
call :PRINT "[PROCESADOR]"
for /f "skip=1 tokens=*" %%a in ('wmic cpu get Name 2^>nul') do (
    if not "%%a"=="" ( call :PRINT "  CPU:          %%a" & goto :CPU_DONE )
)
:CPU_DONE
for /f "skip=1 tokens=*" %%a in ('wmic cpu get NumberOfCores 2^>nul') do (
    if not "%%a"=="" ( call :PRINT "  Nucleos:      %%a" & goto :CORES_DONE )
)
:CORES_DONE
for /f "skip=1 tokens=*" %%a in ('wmic cpu get NumberOfLogicalProcessors 2^>nul') do (
    if not "%%a"=="" ( call :PRINT "  Hilos:        %%a" & goto :THREADS_DONE )
)
:THREADS_DONE
for /f "skip=1 tokens=*" %%a in ('wmic cpu get MaxClockSpeed 2^>nul') do (
    if not "%%a"=="" ( call :PRINT "  Velocidad:    %%a MHz" & goto :SPEED_DONE )
)
:SPEED_DONE
for /f "skip=1 tokens=*" %%a in ('wmic cpu get LoadPercentage 2^>nul') do (
    if not "%%a"=="" ( call :PRINT "  Uso actual:   %%a%%" & goto :LOAD_DONE )
)
:LOAD_DONE
call :NEWLINE

:: -- Memoria RAM --
call :PRINT "[MEMORIA RAM]"
:: RAM fisica real: suma de todos los modulos via CimInstance
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "[math]::Round(((Get-CimInstance Win32_PhysicalMemory) | Measure-Object -Property Capacity -Sum).Sum / 1MB)"`) do set "RAM_FISICA_MB=%%a"

:: RAM visible por el SO y calculos de uso
for /f "tokens=2 delims==" %%a in ('wmic os get TotalVisibleMemorySize /value 2^>nul') do if not "%%a"=="" set /a "RAM_TOTAL_MB=%%a/1024"
for /f "tokens=2 delims==" %%a in ('wmic os get FreePhysicalMemory /value 2^>nul') do if not "%%a"=="" set /a "RAM_LIBRE_MB=%%a/1024"

:: +512 antes de /1024 para redondear en division entera
set /a "RAM_FISICA_GB=(%RAM_FISICA_MB%+512)/1024"
set /a "RAM_TOTAL_GB=(%RAM_TOTAL_MB%+512)/1024"
set /a "RAM_USADA_MB=%RAM_TOTAL_MB%-%RAM_LIBRE_MB%"
set /a "RAM_USADA_GB=(%RAM_USADA_MB%+512)/1024"
set /a "RAM_LIBRE_GB=(%RAM_LIBRE_MB%+512)/1024"

:: Memoria reservada por GPU (diferencia entre fisica real y visible por SO)
set /a "RAM_VIDEO_MB=%RAM_FISICA_MB%-%RAM_TOTAL_MB%"
if %RAM_VIDEO_MB% lss 0 set "RAM_VIDEO_MB=0"
set /a "RAM_VIDEO_GB=(%RAM_VIDEO_MB%+512)/1024"

:: Resumen general
call :PRINT "  Fisica Real:      %RAM_FISICA_GB% GB  (%RAM_FISICA_MB% MB)"
call :PRINT "  Reservada GPU:    %RAM_VIDEO_GB% GB  (%RAM_VIDEO_MB% MB)"
call :PRINT "  Total Sistema:    %RAM_TOTAL_GB% GB  (%RAM_TOTAL_MB% MB)"
call :PRINT "  Usada:            %RAM_USADA_GB% GB  (%RAM_USADA_MB% MB)"
call :PRINT "  Libre:            %RAM_LIBRE_GB% GB  (%RAM_LIBRE_MB% MB)"
call :NEWLINE

:: Detalle por modulo:
call :PRINT "  [MODULOS INSTALADOS]"
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command ^
    "Get-CimInstance Win32_PhysicalMemory | ForEach-Object { $gb=[math]::Round($_.Capacity/1GB,1); $mod=if($_.PartNumber.Trim()){'Modelo: '+$_.PartNumber.Trim()}else{'Fab: '+$_.Manufacturer.Trim()}; '  Slot {0}: {1} GB  {2}  {3} MHz' -f $_.DeviceLocator,$gb,$mod,$_.Speed }"`) do (
    call :PRINT "%%a"
)
call :NEWLINE


:: -- Placa de Video (/value filtra vacios correctamente) --
call :PRINT "[PLACA DE VIDEO]"
for /f "tokens=2 delims==" %%a in ('wmic path win32_VideoController get Name /value 2^>nul') do if not "%%a"=="" call :PRINT "  GPU:          %%a"
call :NEWLINE

:: -- Discos Físicos (Estructurado por Unidad) --
call :PRINT "[DISCOS FISICOS]"

for /f "usebackq tokens=1,2,3,4,5,6 delims=|" %%a in (`powershell -NoProfile -Command ^
    "Get-PhysicalDisk | Sort-Object DeviceId | ForEach-Object { $size = [math]::Round($_.Size / 1GB, 1).ToString([System.Globalization.CultureInfo]::InvariantCulture); '{0}|{1}|{2}|{3}|{4}|{5}' -f $_.DeviceId, $_.MediaType, $_.Model, $size, $_.HealthStatus, $_.BusType }"`) do (
    :: %%a=DeviceId  %%b=MediaType  %%c=Model  %%d=SizeGB  %%e=HealthStatus  %%f=BusType
    call :PRINT "  Disco %%a:"
    call :PRINT "    Tipo:          %%b"
    call :PRINT "    Modelo:        %%c"
    call :PRINT "    Capacidad:     %%d GB"
    call :PRINT "    Interfaz:      %%f"

    :: Traduce el estado de salud al formato clasico SMART
    set "HEALTH=%%e"
    if /i "%%e"=="Healthy"   set "HEALTH=OK"
    if /i "%%e"=="Warning"   set "HEALTH=Alerta / Precaucion"
    if /i "%%e"=="Unhealthy" set "HEALTH=Malo / Reemplazar"

    call :PRINT "    Estado SMART:  !HEALTH!"
    call :NEWLINE
)

:: -- Particiones agrupadas por disco fisico --
call :PRINT "[PARTICIONES]"
set "ULTIMO_DISCO="
set "PS_TEMP=%TEMP%\particiones.tmp"

powershell -NoProfile -Command "$particiones = Get-WmiObject Win32_DiskPartition; foreach ($part in $particiones) { $disco = $part.DiskIndex; $logicos = Get-WmiObject -Query (\"ASSOCIATORS OF {Win32_DiskPartition.DeviceID='\" + $part.DeviceID + \"'} WHERE AssocClass=Win32_LogicalDiskToPartition\"); foreach ($l in $logicos) { $total = [math]::Round($l.Size/1GB,1).ToString([System.Globalization.CultureInfo]::InvariantCulture); $libre = [math]::Round($l.FreeSpace/1GB,1).ToString([System.Globalization.CultureInfo]::InvariantCulture); Write-Output ($disco.ToString()+'|'+$l.DeviceID+'|'+$total+'|'+$libre) } }" > "%PS_TEMP%" 2>nul
for /f "usebackq tokens=1,2,3,4 delims=|" %%a in ("%PS_TEMP%") do (
    if not "%%a"=="!ULTIMO_DISCO!" (
        call :PRINT "  Disco %%a:"
        set "ULTIMO_DISCO=%%a"
    )
    call :PRINT "    - Unidad %%b    Total: %%c GB  -  Libre: %%d GB"
)

if exist "%PS_TEMP%" del "%PS_TEMP%" >nul
call :NEWLINE

:: -- Red (/value filtra vacios correctamente) --
call :PRINT "[RED]"
for /f "tokens=2 delims==" %%a in ('wmic nic where "NetEnabled=True" get Name /value 2^>nul') do if not "%%a"=="" call :PRINT "  Adaptador:    %%a"
for /f "tokens=2 delims==" %%a in ('wmic nic where "NetEnabled=True" get MACAddress /value 2^>nul') do if not "%%a"=="" call :PRINT "  MAC:          %%a"
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch '^127\.' } | Select-Object -First 1).IPAddress"`) do call :PRINT "  IP Local:     %%a"
call :NEWLINE

:: -- Usuario --
call :PRINT "[USUARIO ACTUAL]"
call :PRINT "  Usuario:      %USERNAME%"
call :PRINT "  Dominio:      %USERDOMAIN%"
call :PRINT "  Perfil:       %USERPROFILE%"
call :NEWLINE
call :PRINT "=========================================="
call :PRINT "   FIN DEL REPORTE"
call :PRINT "=========================================="

echo.
echo  ==========================================
echo  Log guardado en:
echo  %LOGFILE%
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