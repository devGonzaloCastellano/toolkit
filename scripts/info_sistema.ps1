<#
.SYNOPSIS
    Modulo de informacion detallada del sistema.
.DESCRIPTION
    Recopila y muestra informacion completa del hardware y software:
    sistema operativo, uptime, procesador con temperatura, memoria RAM
    fisica y por modulo, GPU, bateria (si existe), discos fisicos,
    particiones, red, servicios criticos y usuario actual.
    Finaliza con un diagnostico general del estado del equipo.
.NOTES
    Version : 2.1.0
    Proyecto: Portable Windows Toolkit
#>

#region PARAMETROS

param(
    [string]$LogDir = "$PSScriptRoot\..\logs",
    [switch]$NoElevation
)

#endregion

#region IMPORTS

. "$PSScriptRoot\..\lib\Utils.ps1"

#endregion

#region AUTO-ELEVACION

if (-not $NoElevation) {
    Invoke-Elevate -ScriptPath $PSCommandPath -Parameters $PSBoundParameters
}

#endregion

#region INICIALIZACION

$envInfo = Initialize-Environment -LogDir $LogDir -ModuleName "info_sistema"
$LogFile = $envInfo.LogFile

#endregion

#region RECOLECCION DE DATOS

Write-Log "Relevando informacion del sistema..." -LogFile $LogFile
Write-Log "Esto puede tardar unos segundos." -Level WARNING -LogFile $LogFile
Write-Blank -LogFile $LogFile

# -- Sistema Operativo --
$os       = Get-CimInstance Win32_OperatingSystem  -ErrorAction SilentlyContinue
$cs       = Get-CimInstance Win32_ComputerSystem   -ErrorAction SilentlyContinue
$mb       = Get-CimInstance Win32_BaseBoard        -ErrorAction SilentlyContinue
$bios     = Get-CimInstance Win32_BIOS             -ErrorAction SilentlyContinue

# -- UBR (Update Build Revision) para version exacta del parche --
$ubr = try {
    (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name UBR -ErrorAction Stop).UBR
} catch { "N/A" }

# -- Uptime --
$uptime    = if ($os) { (Get-Date) - $os.LastBootUpTime } else { $null }
$uptimeStr = if ($uptime) {
    "{0}d {1}h {2}m" -f [math]::Floor($uptime.TotalDays), $uptime.Hours, $uptime.Minutes
} else { "N/A" }

# -- Procesador --
$cpu    = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
$cpuUso = if ($cpu) { $cpu.LoadPercentage } else { 0 }

# -- RAM --
$modulosRAM   = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
$ramFisicaMB  = if ($modulosRAM) {
    [math]::Round(($modulosRAM | Measure-Object -Property Capacity -Sum).Sum / 1MB)
} else { 0 }
$ramSistMB    = if ($os) { [math]::Round($os.TotalVisibleMemorySize / 1KB) } else { 0 }
$ramLibreMB   = if ($os) { [math]::Round($os.FreePhysicalMemory     / 1KB) } else { 0 }
$ramUsadaMB   = $ramSistMB - $ramLibreMB
$ramReservMB  = $ramFisicaMB - $ramSistMB
$ramPct       = if ($ramSistMB -gt 0) { [math]::Round(($ramUsadaMB / $ramSistMB) * 100) } else { 0 }
$ramFisicaGB  = [math]::Round($ramFisicaMB / 1024, 1)
$ramSistGB    = [math]::Round($ramSistMB   / 1024, 1)
$ramUsadaGB   = [math]::Round($ramUsadaMB  / 1024, 1)
$ramLibreGB   = [math]::Round($ramLibreMB  / 1024, 1)
$ramReservGB  = [math]::Round($ramReservMB / 1024, 1)

# -- GPU --
$gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -First 1
$gpuVRAM = if ($gpu -and $gpu.AdapterRAM) {
    [math]::Round($gpu.AdapterRAM / 1GB, 1)
} else { "N/A" }

# -- Bateria --
$bateria = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
$hayBateria = $null -ne $bateria

# -- Discos fisicos --
$discosFisicos = Get-PhysicalDisk -ErrorAction SilentlyContinue | Sort-Object DeviceId

# -- Particiones --
$particiones = Get-WmiObject Win32_DiskPartition -ErrorAction SilentlyContinue |
        ForEach-Object {
            $part    = $_
            $logicos = Get-WmiObject -Query `
            "ASSOCIATORS OF {Win32_DiskPartition.DeviceID='$($part.DeviceID)'} WHERE AssocClass=Win32_LogicalDiskToPartition" `
            -ErrorAction SilentlyContinue
            foreach ($l in $logicos) {
                [PSCustomObject]@{
                    DiscoId = $part.DiskIndex
                    Unidad  = $l.DeviceID.TrimEnd(':')
                    TotalGB = [math]::Round($l.Size      / 1GB, 1)
                    LibreGB = [math]::Round($l.FreeSpace / 1GB, 1)
                }
            }
        }

# -- Red --
$adaptadorRed = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
$ipLocal      = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notmatch '^127\.' } | Select-Object -First 1)
$macAddress   = if ($adaptadorRed) { $adaptadorRed.MacAddress } else { "N/A" }

# -- Servicios criticos --
$serviciosCriticos = @("WinDefend", "MpsSvc", "wuauserv")
$estadosServicios  = foreach ($svc in $serviciosCriticos) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    [PSCustomObject]@{
        Nombre  = $svc
        Display = switch ($svc) {
            "WinDefend" { "Win Defender" }
            "MpsSvc"    { "Win Firewall" }
            "wuauserv"  { "Win Update"   }
        }
        Estado  = if ($s) { $s.Status.ToString() } else { "No encontrado" }
    }
}

#endregion

#region PRESENTACION

Write-Section "INFORMACION DEL SISTEMA" -LogFile $LogFile
Write-Blank -LogFile $LogFile

# -- Sistema Operativo --
Write-Section "SISTEMA OPERATIVO" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "Nombre       : $($os.Caption)"                                    -LogFile $LogFile
Write-Log "Version      : $($os.Version).$ubr"                               -LogFile $LogFile
Write-Log "Arquitectura : $($os.OSArchitecture)"                             -LogFile $LogFile
Write-Log "Ultimo inicio: $($os.LastBootUpTime.ToString('dd/MM/yyyy HH:mm'))" -LogFile $LogFile
Write-Log "Uptime       : $uptimeStr"                                         -LogFile $LogFile
Write-Blank -LogFile $LogFile

# -- Equipo --
Write-Section "EQUIPO" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "Nombre       : $($cs.Name)"         -LogFile $LogFile
Write-Blank -LogFile $LogFile

# -- Placa Madre --
Write-Section "PLACA MADRE" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "Modelo       : $($mb.Product)" -LogFile $LogFile
Write-Log "Fabricante   : $($mb.Manufacturer)" -LogFile $LogFile
Write-Log "Version      : $($mb.Version)"        -LogFile $LogFile
Write-Log "Serial       : $($mb.SerialNumber)"        -LogFile $LogFile
Write-Blank -LogFile $LogFile

# -- BIOS --
Write-Section "BIOS" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "Version      : $($bios.SMBIOSBIOSVersion)" -LogFile $LogFile
Write-Log "Fabricante   : $($bios.Manufacturer)" -LogFile $LogFile
if ($bios.ReleaseDate) {
    try {
        $fechaBios = [datetime]$bios.ReleaseDate
        Write-Log "Fecha        : $($fechaBios.ToString('dd/MM/yyyy'))" -LogFile $LogFile
    }
    catch {
        Write-Log "Fecha        : $($bios.ReleaseDate)" -LogFile $LogFile
    }
}
Write-Blank -LogFile $LogFile

# -- Procesador --
Write-Section "PROCESADOR" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "CPU          : $($cpu.Name)"                      -LogFile $LogFile
Write-Log "Nucleos      : $($cpu.NumberOfCores)"             -LogFile $LogFile
Write-Log "Hilos        : $($cpu.NumberOfLogicalProcessors)" -LogFile $LogFile
Write-Log "Velocidad    : $($cpu.MaxClockSpeed) MHz"         -LogFile $LogFile

$nivelCPU = if ($cpuUso -ge 90) { "ERROR" } elseif ($cpuUso -ge 70) { "WARNING" } else { "SUCCESS" }
Write-Log "Uso actual   : $cpuUso%" -Level $nivelCPU -LogFile $LogFile

Write-Blank -LogFile $LogFile

# -- RAM --
Write-Section "MEMORIA RAM" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "Fisica real  : $ramFisicaGB GB  ($ramFisicaMB MB)" -LogFile $LogFile

if ($ramReservMB -gt 0) {
    Write-Log "Reservada HW : $ramReservGB GB  ($ramReservMB MB)  (GPU integrada u otro hardware)" -Level WARNING -LogFile $LogFile
}

Write-Log "Total SO     : $ramSistGB GB  ($ramSistMB MB)"   -LogFile $LogFile

$nivelRAM = if ($ramPct -ge 90) { "ERROR" } elseif ($ramPct -ge 75) { "WARNING" } else { "SUCCESS" }
Write-Log "En uso       : $ramUsadaGB GB  ($ramPct%)" -Level $nivelRAM -LogFile $LogFile
Write-Log "Libre        : $ramLibreGB GB"             -LogFile $LogFile
Write-Blank -LogFile $LogFile

if ($modulosRAM) {
    Write-Log "Modulos instalados:" -LogFile $LogFile
    foreach ($modulo in $modulosRAM) {
        $gb       = [math]::Round($modulo.Capacity / 1GB, 1)
        $modelo   = if ($modulo.PartNumber.Trim()) { $modulo.PartNumber.Trim() } else { "Modelo N/A" }
        $fab      = if ($modulo.Manufacturer.Trim()) { $modulo.Manufacturer.Trim() } else { "Fab N/A" }
        $linea    = "  Slot {0,-6} {1,4} GB  {2}  {3}  {4} MHz" -f `
                    $modulo.DeviceLocator, $gb, $modelo, $fab, $modulo.Speed
        Write-Log $linea -LogFile $LogFile
    }
}
Write-Blank -LogFile $LogFile

# -- GPU --
Write-Section "PLACA DE VIDEO" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "GPU          : $($gpu.Name)"                         -LogFile $LogFile
Write-Log "VRAM         : $gpuVRAM GB"                          -LogFile $LogFile
Write-Log "Resolucion   : $($gpu.CurrentHorizontalResolution) x $($gpu.CurrentVerticalResolution)" -LogFile $LogFile
Write-Log "Driver       : $($gpu.DriverVersion)"                -LogFile $LogFile
Write-Blank -LogFile $LogFile

# -- Bateria (solo si existe) --
if ($hayBateria) {
    Write-Section "BATERIA" -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    $estadoBat = switch ($bateria.BatteryStatus) {
        1 { "Descargando" }
        2 { "Conectada a corriente" }
        3 { "Cargando completamente" }
        4 { "Baja" }
        5 { "Critica" }
        6 { "Cargando" }
        7 { "Cargando y alta" }
        8 { "Cargando y baja" }
        9 { "Cargando y critica" }
        default { "Desconocido" }
    }

    $nivelBat = if ($bateria.EstimatedChargeRemaining -le 20) { "ERROR" } `
                elseif ($bateria.EstimatedChargeRemaining -le 40) { "WARNING" } `
                else { "SUCCESS" }

    Write-Log "Estado       : $estadoBat"                                      -LogFile $LogFile
    Write-Log "Carga        : $($bateria.EstimatedChargeRemaining)%" -Level $nivelBat -LogFile $LogFile
    Write-Log "Tiempo rest. : $($bateria.EstimatedRunTime) min"                -LogFile $LogFile
    Write-Blank -LogFile $LogFile
}

# -- Discos fisicos --
Write-Section "DISCOS FISICOS" -LogFile $LogFile
Write-Blank -LogFile $LogFile

foreach ($disco in $discosFisicos) {
    $estadoMap = @{ "Healthy" = "OK"; "Warning" = "Alerta"; "Unhealthy" = "Malo - Reemplazar" }
    $estadoStr = if ($estadoMap[$disco.HealthStatus]) { $estadoMap[$disco.HealthStatus] } else { $disco.HealthStatus }
    $nivelDisco = switch ($disco.HealthStatus) {
        "Healthy"   { "SUCCESS" }
        "Warning"   { "WARNING" }
        "Unhealthy" { "ERROR"   }
        default     { "INFO"    }
    }
    $capacidadGB = [math]::Round($disco.Size / 1GB, 1)
    Write-Log "Disco $($disco.DeviceId) $($disco.Model)  $capacidadGB GB  $($disco.MediaType)  $($disco.BusType)" -LogFile $LogFile
    Write-Log "  SMART: $estadoStr" -Level $nivelDisco -LogFile $LogFile
    Write-Blank -LogFile $LogFile
}

# -- Particiones --
Write-Section "PARTICIONES" -LogFile $LogFile
Write-Blank -LogFile $LogFile

$discoActual = -1
foreach ($p in $particiones) {
    if ($p.DiscoId -ne $discoActual) {
        Write-Log "Disco $($p.DiscoId)" -LogFile $LogFile
        $discoActual = $p.DiscoId
    }
    $usadoGB = [math]::Round($p.TotalGB - $p.LibreGB, 1)
    $pctUso  = if ($p.TotalGB -gt 0) { [math]::Round(($usadoGB / $p.TotalGB) * 100) } else { 0 }
    $nivel   = if ($pctUso -ge 90) { "ERROR" } elseif ($pctUso -ge 75) { "WARNING" } else { "SUCCESS" }
    $linea   = "  Unidad {0}   Total: {1,6} GB   Libre: {2,6} GB   Usado: {3}%" -f `
               $p.Unidad, $p.TotalGB, $p.LibreGB, $pctUso
    Write-Log $linea -Level $nivel -LogFile $LogFile
}
Write-Blank -LogFile $LogFile

# -- Red --
Write-Section "RED" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "Adaptador    : $($adaptadorRed.Name)"        -LogFile $LogFile
Write-Log "MAC          : $macAddress"                   -LogFile $LogFile
Write-Log "IP Local     : $($ipLocal.IPAddress)"        -LogFile $LogFile
Write-Log "Mascara      : /$($ipLocal.PrefixLength)"    -LogFile $LogFile
Write-Blank -LogFile $LogFile

# -- Servicios criticos --
Write-Section "SERVICIOS CRITICOS" -LogFile $LogFile
Write-Blank -LogFile $LogFile

foreach ($svc in $estadosServicios) {
    $nivel  = if ($svc.Estado -eq "Running") { "SUCCESS" } else { "WARNING" }
    $linea  = "{0,-20} : {1}" -f $svc.Display, $svc.Estado
    Write-Log $linea -Level $nivel -LogFile $LogFile
}
Write-Blank -LogFile $LogFile

# -- Usuario actual --
Write-Section "USUARIO ACTUAL" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "Usuario      : $env:USERNAME"     -LogFile $LogFile
Write-Log "Dominio      : $env:USERDOMAIN"   -LogFile $LogFile
Write-Log "Perfil       : $env:USERPROFILE"  -LogFile $LogFile
Write-Blank -LogFile $LogFile

#endregion

#region DIAGNOSTICO GENERAL

Write-Section "DIAGNOSTICO GENERAL" -LogFile $LogFile
Write-Blank -LogFile $LogFile

# CPU
$nivelCPUDiag = if ($cpuUso -ge 90) { "ERROR" } elseif ($cpuUso -ge 70) { "WARNING" } else { "SUCCESS" }
$cpuLimpio = $cpu.Name `
    -replace '\s+with\s+.*graphics.*', '' `
    -replace '\s+@\s+\d+(\.\d+)?\s*[G|M]Hz', '' `
    -replace '\([R|TM|r|tm]\)', '' `
    -replace '\s+', ' '
$cpuNombre = if ($cpuLimpio.Length -gt 35) { $cpuLimpio.Substring(0, 35) + "..." } else { $cpuLimpio }
$lineaCPU     = "{0,-15}: {1}" -f "CPU", "$cpuNombre - Uso: $cpuUso%"
Write-Log $lineaCPU -Level $nivelCPUDiag -LogFile $LogFile

# RAM
$nivelRAMDiag = if ($ramPct -ge 90) { "ERROR" } elseif ($ramPct -ge 75) { "WARNING" } else { "SUCCESS" }
$lineaRam = "{0,-15}: {1}" -f "RAM", "$ramFisicaGB GB fisicos - $ramPct% en uso"
Write-Log $lineaRam -Level $nivelRAMDiag -LogFile $LogFile

# GPU
$lineaGPU = "{0,-15}: {1}" -f "GPU", "$($gpu.Name) - VRAM: $gpuVRAM GB"
Write-Log $lineaGPU -LogFile $LogFile

# Bateria
if ($hayBateria) {
    $nivelBatDiag = if ($bateria.EstimatedChargeRemaining -le 20) { "ERROR" } `
                    elseif ($bateria.EstimatedChargeRemaining -le 40) { "WARNING" } `
                    else { "SUCCESS" }
    $lineaBat = "{0,-15}: {1}% - {2}" -f "Bateria", $bateria.EstimatedChargeRemaining, $estadoBat
    Write-Log $lineaBat -Level $nivelBatDiag -LogFile $LogFile
} else {
    $lineaBat = "{0,-15}: {1}" -f "Bateria", "No aplica (Desktop)"
    Write-Log $lineaBat -LogFile $LogFile
}

# Particiones
foreach ($p in $particiones) {
    $usadoPct = if ($p.TotalGB -gt 0) { [math]::Round((($p.TotalGB - $p.LibreGB) / $p.TotalGB) * 100) } else { 0 }
    $nivelP   = if ($usadoPct -ge 90) { "ERROR" } elseif ($usadoPct -ge 75) { "WARNING" } else { "SUCCESS" }
    $msgP     = if ($usadoPct -ge 90) { "Espacio critico" } elseif ($usadoPct -ge 75) { "Considerar limpieza" } else { "OK" }
    $lineaPart = "{0,-15}: {1}% usado - {2}" -f "Disco $($p.Unidad)", $usadoPct, $msgP
    Write-Log $lineaPart -Level $nivelP -LogFile $LogFile
}

# Servicios criticos
foreach ($svc in $estadosServicios) {
    $nivelSvcDiag = if ($svc.Estado -eq "Running") { "SUCCESS" } else { "WARNING" }
    Write-Log ("{0,-15}: {1}" -f $svc.Display, $svc.Estado) -Level $nivelSvcDiag -LogFile $LogFile
}

Write-Blank -LogFile $LogFile

#endregion

#region RESUMEN

Write-Section -LogFile $LogFile
Write-Log "Log guardado en: $LogFile" -LogFile $LogFile
Write-Blank

Invoke-Pause

#endregion