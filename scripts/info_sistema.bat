@echo off
title Informacion del Sistema
chcp 65001 >nul
setlocal enabledelayedexpansion

:: ----------------------------------------
:: Fecha y hora para el nombre del log
:: ----------------------------------------
for /f "tokens=1-3 delims=/-" %%a in ("%date%") do (
    set "DIA=%%a"
    set "MES=%%b"
    set "ANIO=%%c"
)
for /f "tokens=1,2 delims=:. " %%a in ("%time%") do (
    set "HH=%%a"
    set "MM=%%b"
)
set "HH=%HH: =0%"
set "LOGFILE=%~dp0..\logs\info_%DIA%-%MES%-%ANIO%_%HH%-%MM%.txt"

if not exist "%~dp0..\logs" mkdir "%~dp0..\logs"
if exist "%LOGFILE%" del "%LOGFILE%"

echo.
echo  Relevando informacion del sistema...
echo  Esto puede tardar unos segundos.
echo.

call :PRINT "=========================================="
call :PRINT "   INFORMACION DEL SISTEMA"
call :PRINT "=========================================="
call :NEWLINE

:: -- Sistema Operativo --
call :PRINT "[SISTEMA OPERATIVO]"
for /f "tokens=2 delims==" %%a in ('wmic os get Caption /value 2^>nul') do if not "%%a"=="" call :PRINT "  Nombre:       %%a"
for /f "tokens=2 delims==" %%a in ('wmic os get Version /value 2^>nul') do if not "%%a"=="" call :PRINT "  Version:      %%a"
for /f "tokens=2 delims==" %%a in ('wmic os get BuildNumber /value 2^>nul') do if not "%%a"=="" call :PRINT "  Build:        %%a"
for /f "tokens=2 delims==" %%a in ('wmic os get OSArchitecture /value 2^>nul') do if not "%%a"=="" call :PRINT "  Arquitectura: %%a"
for /f "tokens=2 delims==" %%a in ('wmic os get LastBootUpTime /value 2^>nul') do if not "%%a"=="" call :PRINT "  Ultimo inicio:%%a"
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
for /f "tokens=2 delims==" %%a in ('wmic os get TotalVisibleMemorySize /value 2^>nul') do if not "%%a"=="" set /a "RAM_TOTAL_MB=%%a/1024"
for /f "tokens=2 delims==" %%a in ('wmic os get FreePhysicalMemory /value 2^>nul') do if not "%%a"=="" set /a "RAM_LIBRE_MB=%%a/1024"
set /a "RAM_USADA_MB=%RAM_TOTAL_MB%-%RAM_LIBRE_MB%"
set /a "RAM_TOTAL_GB=(%RAM_TOTAL_MB%+512)/1024"
call :PRINT "  Total:        %RAM_TOTAL_GB% GB  (%RAM_TOTAL_MB% MB)"
call :PRINT "  Usada:        %RAM_USADA_MB% MB"
call :PRINT "  Libre:        %RAM_LIBRE_MB% MB"
call :NEWLINE

:: -- Placa de Video (/value filtra vacios correctamente) --
call :PRINT "[PLACA DE VIDEO]"
for /f "tokens=2 delims==" %%a in ('wmic path win32_VideoController get Name /value 2^>nul') do if not "%%a"=="" call :PRINT "  GPU:          %%a"
call :NEWLINE

:: -- Discos fisicos (/value filtra vacios correctamente) --
call :PRINT "[DISCOS FISICOS]"
for /f "tokens=2 delims==" %%a in ('wmic diskdrive get Model /value 2^>nul') do if not "%%a"=="" call :PRINT "  Modelo:       %%a"
for /f "tokens=2 delims==" %%a in ('wmic diskdrive get Status /value 2^>nul') do if not "%%a"=="" call :PRINT "  Estado SMART: %%a"
call :NEWLINE

:: -- Particiones via PowerShell --
call :PRINT "[PARTICIONES]"
for /f "usebackq tokens=1,2,3 delims=," %%a in (`PowerShell -NoProfile -Command "Get-PSDrive -PSProvider FileSystem | Where-Object {$_.Used -ne $null} | ForEach-Object { $total=[math]::Round(($_.Used+$_.Free)/1GB,1); $libre=[math]::Round($_.Free/1GB,1); Write-Output ($_.Name+','+ $total+','+$libre) }" 2^>nul`) do (
    call :PRINT "  Unidad %%a:    Total: %%b GB  -  Libre: %%c GB"
)
call :NEWLINE

:: -- Red (/value filtra vacios correctamente) --
call :PRINT "[RED]"
for /f "tokens=2 delims==" %%a in ('wmic nic where "NetEnabled=True" get Name /value 2^>nul') do if not "%%a"=="" call :PRINT "  Adaptador:    %%a"
for /f "tokens=2 delims==" %%a in ('wmic nic where "NetEnabled=True" get MACAddress /value 2^>nul') do if not "%%a"=="" call :PRINT "  MAC:          %%a"
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /i "IPv4"') do if not "%%a"=="" call :PRINT "  IP Local:     %%a"
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