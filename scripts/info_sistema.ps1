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
    Version : 3.1.0
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
. "$PSScriptRoot\..\lib\Reporting.ps1"

#endregion

#region AUTO-ELEVACION

if (-not $NoElevation) {
    Invoke-Elevate -ScriptPath $PSCommandPath -Parameters $PSBoundParameters
}

#endregion

#region INICIALIZACION

$envInfo = Initialize-Environment -LogDir $LogDir -ModuleName "info_sistema"
$LogFile = $envInfo.LogFile

Set-CurrentExecution -ModuleName "info_sistema" -TxtPath $LogFile

$reportsDir = Join-Path (Split-Path $LogDir -Parent) "reports"
$reportFile = Get-ReportFileName -ReportsDir $reportsDir -ModuleName "info_sistema"
$script:report = New-ModuleReport -ModuleName "info_sistema"

#endregion

#region FUNCIONES INTERNAS

<#
.SYNOPSIS
    Determina el nivel de severidad (SUCCESS/WARNING/ERROR) segun umbrales.
.DESCRIPTION
    Centraliza la logica de clasificacion por porcentaje/valor de uso,
    evitando repetir los mismos umbrales en la seccion de presentacion
    y en el diagnostico general.
.PARAMETER Value
    Valor numerico a evaluar (ej: porcentaje de uso).
.PARAMETER WarningThreshold
    A partir de que valor se considera WARNING.
.PARAMETER ErrorThreshold
    A partir de que valor se considera ERROR.
.OUTPUTS
    [string] "SUCCESS", "WARNING" o "ERROR".
.EXAMPLE
    Get-UsageLevel -Value 92 -WarningThreshold 75 -ErrorThreshold 90   # "ERROR"
#>
function Get-UsageLevel {
    param(
        [Parameter(Mandatory)]
        [double]$Value,

        [Parameter(Mandatory)]
        [double]$WarningThreshold,

        [Parameter(Mandatory)]
        [double]$ErrorThreshold
    )

    if ($Value -ge $ErrorThreshold)   { return "ERROR" }
    if ($Value -ge $WarningThreshold) { return "WARNING" }
    return "SUCCESS"
}

<#
.SYNOPSIS
    Ejecuta una consulta CIM protegida, registrando el error si falla.
.DESCRIPTION
    Envuelve Get-CimInstance con try/catch, evitando repetir el mismo
    bloque para cada clase WMI/CIM consultada en el modulo. Si falla,
    registra el error como TOOLKIT (falla del script, no del equipo).
.PARAMETER ClassName
    Nombre de la clase CIM a consultar (ej: "Win32_OperatingSystem").
.PARAMETER FriendlyName
    Nombre descriptivo usado en los mensajes de log/error.
.OUTPUTS
    Resultado de Get-CimInstance, o $null si la consulta fallo.
.EXAMPLE
    $os = Invoke-CimQuerySafe -ClassName "Win32_OperatingSystem" -FriendlyName "Sistema Operativo"
#>
function Invoke-CimQuerySafe {
    param(
        [Parameter(Mandatory)]
        [string]$ClassName,

        [Parameter(Mandatory)]
        [string]$FriendlyName
    )

    try {
        return Get-CimInstance -ClassName $ClassName -ErrorAction Stop
    } catch {
        Write-Log "No se pudo obtener $FriendlyName : $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al obtener $FriendlyName : $($_.Exception.Message)" -Severity ERROR -Source TOOLKIT
        return $null
    }
}

<#
.SYNOPSIS
    Obtiene el UBR (Update Build Revision) del registro de Windows.
.OUTPUTS
    [string] Numero de UBR, o "N/A" si no se pudo leer.
#>
function Get-UBR {
    try {
        return (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name UBR -ErrorAction Stop).UBR
    } catch {
        Write-Log "No se pudo leer el UBR: $($_.Exception.Message)" -Level WARNING -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al leer UBR: $($_.Exception.Message)" -Severity WARNING -Source TOOLKIT
        return "N/A"
    }
}

<#
.SYNOPSIS
    Obtiene particiones logicas agrupadas por disco fisico via CIM.
.OUTPUTS
    Array de PSCustomObject con DiscoId, Unidad, TotalGB y LibreGB.
#>
function Get-Particiones {
    try {
        $particiones = Get-CimInstance Win32_DiskPartition -ErrorAction Stop
        $resultados  = @()

        foreach ($part in $particiones) {
            $logicos = Get-CimInstance -Query `
                "ASSOCIATORS OF {Win32_DiskPartition.DeviceID='$($part.DeviceID)'} WHERE AssocClass=Win32_LogicalDiskToPartition" `
                -ErrorAction SilentlyContinue

            foreach ($l in $logicos) {
                $resultados += [PSCustomObject]@{
                    DiscoId = $part.DiskIndex
                    Unidad  = $l.DeviceID.TrimEnd(':')
                    TotalGB = [math]::Round($l.Size      / 1GB, 1)
                    LibreGB = [math]::Round($l.FreeSpace / 1GB, 1)
                }
            }
        }
        return $resultados
    } catch {
        Write-Log "No se pudieron obtener las particiones: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al obtener particiones: $($_.Exception.Message)" -Severity ERROR -Source TOOLKIT
        return @()
    }
}

<#
.SYNOPSIS
    Determina si una unidad logica es un dispositivo removible.
.DESCRIPTION
    Consulta el tipo de unidad via CIM para distinguir un pendrive/disco
    externo (DriveType 2) de un disco fijo interno (DriveType 3). Se usa
    para decidir si corresponde omitir el chequeo de chkdsk sobre la
    unidad de origen del toolkit: solo tiene sentido omitirla si es
    removible (para evitar el falso positivo de "en uso"), no si el
    toolkit corre desde un disco interno del propio equipo.
.PARAMETER Unidad
    Letra de unidad sin los dos puntos (ej: "E", no "E:").
.OUTPUTS
    [bool] $true si la unidad es removible, $false si es fija o si no
    se pudo determinar.
.EXAMPLE
    Test-EsUnidadRemovible -Unidad "E"
#>
function Test-EsUnidadRemovible {
    param([string]$Unidad)
    try {
        $disco = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='${Unidad}:'" -ErrorAction Stop
        return $disco.DriveType -eq 2
    } catch {
        return $false
    }
}

#endregion

try{
    #region RECOLECCION DE DATOS

    Write-Log "Relevando informacion del sistema..." -LogFile $LogFile
    Write-Log "Esto puede tardar unos segundos." -Level WARNING -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    # -- Sistema Operativo --
    $os   = Invoke-CimQuerySafe -ClassName "Win32_OperatingSystem" -FriendlyName "Sistema Operativo"
    $cs   = Invoke-CimQuerySafe -ClassName "Win32_ComputerSystem"  -FriendlyName "Equipo"
    $mb   = Invoke-CimQuerySafe -ClassName "Win32_BaseBoard"       -FriendlyName "Placa Madre"
    $bios = Invoke-CimQuerySafe -ClassName "Win32_BIOS"            -FriendlyName "BIOS"
    $ubr  = Get-UBR

    # -- Uptime --
    $uptime    = if ($os) { (Get-Date) - $os.LastBootUpTime } else { $null }
    $uptimeStr = if ($uptime) {
        "{0}d {1}h {2}m" -f [math]::Floor($uptime.TotalDays), $uptime.Hours, $uptime.Minutes
    } else { "N/A" }

    # -- Procesador --
    $cpu    = Invoke-CimQuerySafe -ClassName "Win32_Processor" -FriendlyName "Procesador" | Select-Object -First 1
    $cpuUso = if ($cpu) { $cpu.LoadPercentage } else { 0 }
    $nivelCPU = Get-UsageLevel -Value $cpuUso -WarningThreshold 70 -ErrorThreshold 90
    if ($nivelCPU -ne "SUCCESS") {
        Add-ReportError -Report $script:report -Message "CPU con $cpuUso% de uso" -Severity $nivelCPU -Source SYSTEM
    }

    # -- RAM --
    $modulosRAM   = @(Invoke-CimQuerySafe -ClassName "Win32_PhysicalMemory" -FriendlyName "Modulos de RAM")
    $ramFisicaMB  = if (@($modulosRAM).Count -gt 0) {
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
    $nivelRAM = Get-UsageLevel -Value $ramPct -WarningThreshold 75 -ErrorThreshold 90
    if ($nivelRAM -ne "SUCCESS") {
        Add-ReportError -Report $script:report -Message "RAM con $ramPct% de uso" -Severity $nivelRAM -Source SYSTEM
    }

    # -- GPU --
    $gpu = Invoke-CimQuerySafe -ClassName "Win32_VideoController" -FriendlyName "Placa de Video" | Select-Object -First 1
    $gpuVRAM = if ($gpu -and $gpu.AdapterRAM) {
        [math]::Round($gpu.AdapterRAM / 1GB, 1)
    } else { "N/A" }

    # -- Bateria --
    $bateria    = Invoke-CimQuerySafe -ClassName "Win32_Battery" -FriendlyName "Bateria" | Select-Object -First 1
    $hayBateria = $null -ne $bateria
    $estadoBat  = $null
    $nivelBat   = $null

    if ($hayBateria) {
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
        $nivelBat = Get-UsageLevel -Value (100 - $bateria.EstimatedChargeRemaining) -WarningThreshold 60 -ErrorThreshold 80
    }

    # -- Discos fisicos --
    $discosFisicos = @()
    try {
        $discosFisicos = @(Get-PhysicalDisk -ErrorAction Stop | Sort-Object DeviceId)
    } catch {
        Write-Log "No se pudieron obtener los discos fisicos: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al obtener discos fisicos: $($_.Exception.Message)" -Severity ERROR -Source TOOLKIT
    }

    # -- Particiones --
    $particiones = @(Get-Particiones)

    # -- Red --
    $adaptadorRed = $null
    $ipLocal      = $null
    try {
        $adaptadorRed = Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
        $ipLocal      = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
                Where-Object { $_.IPAddress -notmatch '^127\.' } | Select-Object -First 1
    } catch {
        Write-Log "No se pudo obtener informacion de red: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al obtener informacion de red: $($_.Exception.Message)" -Severity ERROR -Source TOOLKIT
    }
    $macAddress = if ($adaptadorRed) { $adaptadorRed.MacAddress } else { "N/A" }

    if (-not $adaptadorRed) {
        Add-ReportError -Report $script:report -Message "Sin adaptador de red activo" -Severity WARNING -Source SYSTEM
    }

    # -- Servicios criticos --
    $serviciosCriticos = @("WinDefend", "MpsSvc", "wuauserv")
    $estadosServicios  = foreach ($svc in $serviciosCriticos) {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        $nombreDisplay = switch ($svc) {
            "WinDefend" { "Win Defender" }
            "MpsSvc"    { "Win Firewall" }
            "wuauserv"  { "Win Update"   }
        }
        $estadoTexto = if ($s) { $s.Status.ToString() } else { "No encontrado" }

        if ($estadoTexto -ne "Running") {
            Add-ReportError -Report $script:report -Message "$nombreDisplay no esta en ejecucion ($estadoTexto)" -Severity WARNING -Source SYSTEM
        }

        [PSCustomObject]@{
            Nombre  = $svc
            Display = $nombreDisplay
            Estado  = $estadoTexto
        }
    }

    #endregion

    #region PRESENTACION

    Write-Section "INFORMACION DEL SISTEMA" -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    # -- Sistema Operativo --
    Write-Section "SISTEMA OPERATIVO" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "Nombre       : $( $os.Caption )"                                    -LogFile $LogFile
    Write-Log "Version      : $( $os.Version ).$ubr"                               -LogFile $LogFile
    Write-Log "Arquitectura : $( $os.OSArchitecture )"                             -LogFile $LogFile
    Write-Log "Ultimo inicio: $($os.LastBootUpTime.ToString('dd/MM/yyyy HH:mm') )" -LogFile $LogFile
    Write-Log "Uptime       : $uptimeStr"                                          -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    # -- Equipo --
    Write-Section "EQUIPO" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "Nombre       : $( $cs.Name )"  -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    # -- Placa Madre --
    Write-Section "PLACA MADRE" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "Modelo       : $( $mb.Product )" -LogFile $LogFile
    Write-Log "Fabricante   : $( $mb.Manufacturer )" -LogFile $LogFile
    Write-Log "Version      : $( $mb.Version )"        -LogFile $LogFile
    Write-Log "Serial       : $( $mb.SerialNumber )"        -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    # -- BIOS --
    Write-Section "BIOS" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "Version      : $( $bios.SMBIOSBIOSVersion )" -LogFile $LogFile
    Write-Log "Fabricante   : $( $bios.Manufacturer )" -LogFile $LogFile
    if ($bios -and $bios.ReleaseDate){
        Write-Log "Fecha        : $($bios.ReleaseDate.ToString('dd/MM/yyyy'))" -LogFile $LogFile
    }
    Write-Blank -LogFile $LogFile

    # -- Procesador --
    Write-Section "PROCESADOR" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "CPU          : $( $cpu.Name )"                      -LogFile $LogFile
    Write-Log "Nucleos      : $( $cpu.NumberOfCores )"             -LogFile $LogFile
    Write-Log "Hilos        : $( $cpu.NumberOfLogicalProcessors )" -LogFile $LogFile
    Write-Log "Velocidad    : $( $cpu.MaxClockSpeed ) MHz"         -LogFile $LogFile
    Write-Log "Uso actual   : $cpuUso%" -Level $nivelCPU           -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    # -- RAM --
    Write-Section "MEMORIA RAM" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "Fisica real  : $ramFisicaGB GB  ($ramFisicaMB MB)" -LogFile $LogFile

    if ($ramReservMB -gt 0) {
        Write-Log "Reservada HW : $ramReservGB GB  ($ramReservMB MB)  (GPU integrada u otro hardware)" -Level WARNING -LogFile $LogFile
    }
    Write-Log "Total SO     : $ramSistGB GB  ($ramSistMB MB)" -LogFile $LogFile
    Write-Log "En uso       : $ramUsadaGB GB  ($ramPct%)" -Level $nivelRAM -LogFile $LogFile
    Write-Log "Libre        : $ramLibreGB GB" -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    if (@($modulosRAM).Count -gt 0) {
        Write-Log "Modulos instalados:" -LogFile $LogFile
        foreach ($modulo in $modulosRAM) {
            $gb     = [math]::Round($modulo.Capacity / 1GB, 1)
            $modelo = if ($modulo.PartNumber.Trim())   { $modulo.PartNumber.Trim() }   else { "Modelo N/A" }
            $fab    = if ($modulo.Manufacturer.Trim()) { $modulo.Manufacturer.Trim() } else { "Fab N/A" }
            $linea  = "  Slot {0,-6} {1,4} GB  {2}  {3}  {4} MHz" -f `
                      $modulo.DeviceLocator, $gb, $modelo, $fab, $modulo.Speed
            Write-Log $linea -LogFile $LogFile
        }
    }
    Write-Blank -LogFile $LogFile

    # -- GPU --
    Write-Section "PLACA DE VIDEO" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "GPU          : $( $gpu.Name )" -LogFile $LogFile
    Write-Log "VRAM         : $gpuVRAM GB" -LogFile $LogFile
    Write-Log "Resolucion   : $( $gpu.CurrentHorizontalResolution ) x $( $gpu.CurrentVerticalResolution )" -LogFile $LogFile
    Write-Log "Driver       : $( $gpu.DriverVersion )" -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    # -- Bateria (solo si existe) --
    if ($hayBateria) {
        Write-Section "BATERIA" -LogFile $LogFile
        Write-Blank -LogFile $LogFile
        Write-Log "Estado       : $estadoBat" -LogFile $LogFile
        Write-Log "Carga        : $($bateria.EstimatedChargeRemaining)%" -Level $nivelBat -LogFile $LogFile
        Write-Log "Tiempo rest. : $($bateria.EstimatedRunTime) min" -LogFile $LogFile
        Write-Blank -LogFile $LogFile
    }

    # -- Discos fisicos --
    Write-Section "DISCOS FISICOS" -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    $discosResumen = @()
    foreach ($disco in $discosFisicos) {
        $estadoMap  = @{ "Healthy" = "OK"; "Warning" = "Alerta"; "Unhealthy" = "Malo - Reemplazar" }
        $estadoStr  = if ($estadoMap[$disco.HealthStatus]) { $estadoMap[$disco.HealthStatus] } else { $disco.HealthStatus }
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

        if ($disco.HealthStatus -ne "Healthy") {
            Add-ReportError -Report $script:report -Message "Disco $($disco.DeviceId) ($($disco.Model)) con SMART: $estadoStr" -Severity WARNING -Source SYSTEM
        }

        $discosResumen += [PSCustomObject]@{
            DeviceId     = $disco.DeviceId
            Modelo       = $disco.Model
            CapacidadGB  = $capacidadGB
            MediaType    = $disco.MediaType
            BusType      = $disco.BusType
            SmartEstado  = $estadoStr
        }
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
        $nivel   = Get-UsageLevel -Value $pctUso -WarningThreshold 75 -ErrorThreshold 90
        $linea   = "  Unidad {0}   Total: {1,6} GB   Libre: {2,6} GB   Usado: {3}%" -f `
                   $p.Unidad, $p.TotalGB, $p.LibreGB, $pctUso
        Write-Log $linea -Level $nivel -LogFile $LogFile

        if ($nivel -ne "SUCCESS") {
            Add-ReportError -Report $script:report -Message "Unidad $($p.Unidad) con $pctUso% de uso" -Severity WARNING -Source SYSTEM
        }
    }
    Write-Blank -LogFile $LogFile

    # -- Red --
    Write-Section "RED" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "Adaptador    : $( $adaptadorRed.Name )"        -LogFile $LogFile
    Write-Log "MAC          : $macAddress"                   -LogFile $LogFile
    Write-Log "IP Local     : $( $ipLocal.IPAddress )"        -LogFile $LogFile
    Write-Log "Mascara      : /$( $ipLocal.PrefixLength )"    -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    # -- Servicios criticos --
    Write-Section "SERVICIOS CRITICOS" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    foreach ($svc in $estadosServicios) {
        $nivel = if ($svc.Estado -eq "Running") { "SUCCESS" } else { "WARNING" }
        $linea = "{0,-20} : {1}" -f $svc.Display, $svc.Estado
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

    $cpuLimpio = $cpu.Name `
        -replace '\s+with\s+.*graphics.*', '' `
        -replace '\s+@\s+\d+(\.\d+)?\s*[G|M]Hz', '' `
        -replace '\([R|TM|r|tm]\)', '' `
        -replace '\s+', ' '
    $cpuNombre = if ($cpuLimpio.Length -gt 35) { $cpuLimpio.Substring(0, 35) + "..." } else { $cpuLimpio }
    Write-Log ("{0,-15}: {1}" -f "CPU", "$cpuNombre - Uso: $cpuUso%") -Level $nivelCPU -LogFile $LogFile

    Write-Log ("{0,-15}: {1}" -f "RAM", "$ramFisicaGB GB fisicos - $ramPct% en uso") -Level $nivelRAM -LogFile $LogFile

    Write-Log ("{0,-15}: {1}" -f "GPU", "$($gpu.Name) - VRAM: $gpuVRAM GB") -LogFile $LogFile

    if ($hayBateria) {
        Write-Log ("{0,-15}: {1}% - {2}" -f "Bateria", $bateria.EstimatedChargeRemaining, $estadoBat) -Level $nivelBat -LogFile $LogFile
    } else {
        Write-Log ("{0,-15}: {1}" -f "Bateria", "No aplica (Desktop)") -LogFile $LogFile
    }

    foreach ($p in $particiones) {
        $usadoPct = if ($p.TotalGB -gt 0) { [math]::Round((($p.TotalGB - $p.LibreGB) / $p.TotalGB) * 100) } else { 0 }
        $nivelP   = Get-UsageLevel -Value $usadoPct -WarningThreshold 75 -ErrorThreshold 90
        $msgP     = if ($nivelP -eq "ERROR") { "Espacio critico" } elseif ($nivelP -eq "WARNING") { "Considerar limpieza" } else { "OK" }
        Write-Log ("{0,-15}: {1}% usado - {2}" -f "Disco $($p.Unidad)", $usadoPct, $msgP) -Level $nivelP -LogFile $LogFile
    }

    foreach ($svc in $estadosServicios) {
        $nivelSvc = if ($svc.Estado -eq "Running") { "SUCCESS" } else { "WARNING" }
        Write-Log ("{0,-15}: {1}" -f $svc.Display, $svc.Estado) -Level $nivelSvc -LogFile $LogFile
    }

    Write-Blank -LogFile $LogFile

    #endregion

    #region REPORTE

    $script:report.data = @{
        sistemaOperativo = @{
            nombre       = $os.Caption
            version      = "$($os.Version).$ubr"
            arquitectura = $os.OSArchitecture
            uptime       = $uptimeStr
        }
        equipo = @{
            nombre     = $cs.Name
            placaMadre = "$($mb.Manufacturer) $($mb.Product)"
            biosVersion = $bios.SMBIOSBIOSVersion
        }
        procesador = @{
            nombre     = $cpu.Name
            nucleos    = $cpu.NumberOfCores
            hilos      = $cpu.NumberOfLogicalProcessors
            usoPct     = $cpuUso
        }
        ram = @{
            fisicaGB = $ramFisicaGB
            usadaGB  = $ramUsadaGB
            libreGB  = $ramLibreGB
            usoPct   = $ramPct
        }
        gpu = @{
            nombre = $gpu.Name
            vramGB = $gpuVRAM
        }
        bateria = if ($hayBateria) {
            @{ cargaPct = $bateria.EstimatedChargeRemaining; estado = $estadoBat }
        } else { $null }
        discosFisicos = $discosResumen
        particiones   = $particiones
        red = @{
            adaptador = if ($adaptadorRed) { $adaptadorRed.Name } else { $null }
            mac       = $macAddress
            ip        = if ($ipLocal) { $ipLocal.IPAddress } else { $null }
        }
        serviciosCriticos = $estadosServicios
    }

    $status = if (@($script:report.errors | Where-Object { $_.severity -eq "ERROR" }).Count -gt 0) { "ERROR" } else { "OK" }
    $script:report = Complete-ModuleReport -Report $script:report -Status $status

    #endregion

    #region GENERACION HTML

    function Get-PenalizacionEscalonada {
        param([double]$Pct)
        if ($Pct -ge 95) { return 20 }
        if ($Pct -ge 90) { return 10 }
        if ($Pct -ge 75) { return 5 }
        return 0
    }

    $penalizacionRam = Get-PenalizacionEscalonada -Pct $ramPct
    $penalizacionCpu = Get-PenalizacionEscalonada -Pct $cpuUso

    $discosNoSaludables = @($discosResumen | Where-Object { $_.SmartEstado -ne "OK" })
    $serviciosDetenidos = @($estadosServicios | Where-Object { $_.Estado -ne "Running" })

    $currentDrive = $null
    $currentDriveEsRemovible = $false
    try {
        $currentDrive = (Get-Item $PSScriptRoot).PSDrive.Name
        $currentDriveEsRemovible = Test-EsUnidadRemovible -Unidad $currentDrive
    } catch { }

    $particionesCliente = @($particiones | Where-Object {
        -not ($_.Unidad -eq $currentDrive -and $currentDriveEsRemovible)
    })

    $penalizacionParticiones = 0
    foreach ($p in $particionesCliente) {
        $usadoGB = $p.TotalGB - $p.LibreGB
        $pctUso  = if ($p.TotalGB -gt 0) { ($usadoGB / $p.TotalGB) * 100 } else { 0 }
        $penalizacionParticiones += Get-PenalizacionEscalonada -Pct $pctUso
    }

    $sinRed = -not $adaptadorRed

    $penalizacionTotal = $penalizacionRam + $penalizacionCpu + $penalizacionParticiones `
    + (@($discosNoSaludables).Count * 25) `
    + (@($serviciosDetenidos).Count * 15) `
    + $(if ($sinRed) { 5 } else { 0 })

    $healthScore = 100 - $penalizacionTotal
    if ($healthScore -lt 0) { $healthScore = 0 }

    $script:report.healthScore = $healthScore

    $nivelResultado = if (@($discosNoSaludables).Count -gt 0) { "ERROR" }
    elseif ($healthScore -lt 70) { "ERROR" }
    elseif ($healthScore -lt 90) { "WARNING" }
    else { "OK" }

    # -- Recursos --
    $nivelRam = if ($ramPct -ge 95) { "ERROR" } elseif ($ramPct -ge 75) { "WARNING" } else { "OK" }
    $nivelCpu = if ($cpuUso -ge 95) { "ERROR" } elseif ($cpuUso -ge 75) { "WARNING" } else { "OK" }

    # -- Almacenamiento --
    $filasDiscos = ""
    foreach ($d in $discosResumen) {
        $nivel = if ($d.SmartEstado -eq "OK") { "OK" } else { "ERROR" }
        $filasDiscos += "<tr><td>$($d.Modelo)</td><td>$($d.CapacidadGB) GB</td><td>$(New-HtmlBadge -Texto $d.SmartEstado -Nivel $nivel)</td></tr>`n"
    }

    $filasParticiones = ""
    foreach ($p in $particionesCliente) {
        $usadoGB = [math]::Round($p.TotalGB - $p.LibreGB, 1)
        $pctUso  = if ($p.TotalGB -gt 0) { [math]::Round(($usadoGB / $p.TotalGB) * 100) } else { 0 }
        $nivel   = if ($pctUso -ge 95) { "ERROR" } elseif ($pctUso -ge 75) { "WARNING" } else { "OK" }
        $filasParticiones += "<tr><td>Unidad $($p.Unidad)</td><td>$($p.LibreGB) GB libres de $($p.TotalGB) GB</td><td>$(New-HtmlBadge -Texto "$pctUso% usado" -Nivel $nivel)</td></tr>`n"
    }

    # -- Seguridad --
    $filasServicios = ""
    foreach ($s in $estadosServicios) {
        $nivel = if ($s.Estado -eq "Running") { "OK" } else { "WARNING" }
        $texto = if ($s.Estado -eq "Running") { "Activo" } else { "Detenido" }
        $filasServicios += "<tr><td>$($s.Display)</td><td>$(New-HtmlBadge -Texto $texto -Nivel $nivel)</td></tr>`n"
    }

    # -- Red --
    $textoRed = if ($adaptadorRed) { "Conexion activa" } else { "Sin adaptador de red activo" }
    $nivelRed = if ($adaptadorRed) { "OK" } else { "WARNING" }

    $contentHtml = @"
    <h2>Resumen general</h2>
    <div class="metric"><div class="valor">$healthScore%</div><div class="label">Salud general del equipo</div></div>
    <div class="metric"><div class="valor">$uptimeStr</div><div class="label">Tiempo encendido</div></div>

    <h2>Recursos</h2>
    <table>
        <tr><th>Recurso</th><th>Uso</th></tr>
        <tr><td>Procesador</td><td>$(New-HtmlBadge -Texto "$cpuUso%" -Nivel $nivelCpu)</td></tr>
        <tr><td>Memoria RAM</td><td>$(New-HtmlBadge -Texto "$ramPct%" -Nivel $nivelRam)</td></tr>
    </table>

    <h2>Almacenamiento</h2>
    <table>
        <tr><th>Disco</th><th>Capacidad</th><th>Estado</th></tr>
        $filasDiscos
    </table>
    <table>
        <tr><th>Unidad</th><th>Espacio</th><th>Uso</th></tr>
        $filasParticiones
    </table>

    <h2>Seguridad</h2>
    <table>
        <tr><th>Servicio</th><th>Estado</th></tr>
        $filasServicios
    </table>

    <h2>Red</h2>
    <p>$(New-HtmlBadge -Texto $textoRed -Nivel $nivelRed)</p>

     <h2>Ficha tecnica del equipo</h2>
    <table>
        <tr><td>Sistema operativo</td><td>$($os.Caption) ($($os.OSArchitecture))</td></tr>
        <tr><td>Placa madre</td><td>$($mb.Manufacturer) $($mb.Product)</td></tr>
        <tr><td>BIOS</td><td>$($bios.SMBIOSBIOSVersion)</td></tr>
        <tr><td>Procesador</td><td>$($cpu.Name)</td></tr>
        <tr><td>Memoria RAM</td><td>$ramFisicaGB GB</td></tr>
        <tr><td>Placa de video</td><td>$($gpu.Name)</td></tr>
    </table>
"@

    $reportFileHtml = Get-ReportFileName -ReportsDir $reportsDir -ModuleName "info_sistema" -Extension "html"
    Save-ModuleReportHtml -Report $script:report -ReportFile $reportFileHtml -TituloModulo "Diagnostico General" -ContentHtml $contentHtml -NivelOverride $nivelResultado

    #endregion

}catch {
    Write-Log "Error fatal en el modulo: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
    Add-ReportError -Report $script:report -Message $_.Exception.Message -Severity ERROR -Source TOOLKIT
    $script:report = Complete-ModuleReport -Report $script:report -Status "ERROR"
}finally{
    Save-ModuleReport -Report $script:report -ReportFile $reportFile
}

#region SALIDA

Write-Section -LogFile $LogFile
Write-Log "Log guardado en: $LogFile" -LogFile $LogFile
Write-Blank

Invoke-Pause

#endregion