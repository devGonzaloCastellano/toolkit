<#
.SYNOPSIS
    Modulo de auditoria de procesos en ejecucion.
.DESCRIPTION
    Muestra los procesos activos clasificados por origen y nivel de riesgo,
    agrupando instancias multiples del mismo proceso. Abrevia rutas largas
    para mejorar la legibilidad. Incluye resumen de uso de CPU y RAM.
.NOTES
    Version : 3.0.0
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

$envInfo = Initialize-Environment -LogDir $LogDir -ModuleName "procesos"
$LogFile = $envInfo.LogFile

Set-CurrentExecution -ModuleName "procesos" -TxtPath $LogFile

$reportsDir = Join-Path (Split-Path $LogDir -Parent) "reports"
$reportFile = Get-ReportFileName -ReportsDir $reportsDir -ModuleName "procesos"
$script:report = New-ModuleReport -ModuleName "procesos"

#endregion

#region DATOS - TABLAS DE CLASIFICACION

# Procesos del sistema operativo Windows considerados seguros
$ProcesosSistema = @(
    "svchost", "lsass", "services", "wininit", "winlogon", "csrss", "smss",
    "System", "Registry", "Idle", "spoolsv", "SearchIndexer", "SearchHost",
    "MsMpEng", "NisSrv", "MpDefenderCoreService", "SecurityHealthService",
    "dasHost", "WmiPrvSE", "RuntimeBroker", "taskhostw", "taskeng",
    "explorer", "dwm", "fontdrvhost", "LogonUI", "userinit",
    "audiodg", "conhost", "dllhost", "sihost", "ctfmon",
    "smartscreen", "ShellExperienceHost", "StartMenuExperienceHost",
    "TextInputHost", "ApplicationFrameHost", "SystemSettingsBroker",
    "LsaIso", "SgrmBroker", "sppsvc", "TrustedInstaller",
    "WUDFHost", "wlanext", "WmiApSrv", "msdtc", "vmcompute",
    "vmmem", "vmwp", "Memory Compression", "SearchApp", "splwow64",
    "backgroundTaskHost", "UserOOBEBroker", "AggregatorHost", "CompPkgSrv",
    "SystemSettings", "Video.UI"
)

# Procesos de aplicaciones conocidas y legitimas
$ProcesosAplicaciones = @(
    "chrome", "msedge", "firefox", "opera", "brave",
    "code", "idea64", "idea", "webstorm", "pycharm", "clion",
    "java", "javaw", "node", "python", "python3",
    "slack", "discord", "teams", "zoom", "skype",
    "spotify", "vlc", "mpv", "OfficeClickToRun",
    "git", "git-bash", "OneDrive.Sync.Service",
    "docker", "com.docker.backend", "com.docker.proxy",
    "powershell", "pwsh", "cmd", "WindowsTerminal", "wt",
    "notepad", "notepad++", "sublime_text",
    "OneDrive", "dropbox", "CalculatorApp",
    "steamwebhelper", "steam", "EpicGamesLauncher",
    "AdobeCollabSync", "acrobat", "acrocef",
    "SecurityHealthSystray", "EPPCCMON", "EPSDNMON",
    "remoting_host", "crash_handler", "PaintStudio.View",
    "jusched", "armsvc", "CCXProcess", "AdobeIPCBroker",
    "EpSecuritySupport"
)

# Nombres de procesos asociados a malware conocido
# Presencia no es definitiva pero requiere investigacion inmediata
$ProcesosMalware = @(
    "njrat", "darkcomet", "nanocore", "remcos", "asyncrat",
    "netbus", "subseven", "bifrost", "poison_ivy",
    "mimikatz", "procdump", "wce", "pwdump",
    "meterpreter", "msf", "payload"
)

#endregion

#region FUNCIONES INTERNAS

<#
.SYNOPSIS
    Clasifica un proceso y retorna su nivel y categoria.
.PARAMETER Nombre
    Nombre del proceso (sin extension).
.PARAMETER Ruta
    Ruta completa del ejecutable.
.OUTPUTS
    PSCustomObject con Nivel y Categoria.
#>
function Get-ClasificacionProceso {
    param(
        [string]$Nombre,
        [string]$Ruta
    )

    # Prioridad 1: nombre coincide con malware conocido
    if ($ProcesosMalware -contains $Nombre.ToLower()) {
        return [PSCustomObject]@{Nivel = "ERROR"; Categoria = "MAL" }
    }

    # Prioridad 2: proceso del sistema operativo
    if ($ProcesosSistema -contains $Nombre) {
        return [PSCustomObject]@{ Nivel = "SUCCESS"; Categoria = "S.O" }
    }

    # Prioridad 3: aplicacion conocida y legitima
    if ($ProcesosAplicaciones -contains $Nombre) {
        return [PSCustomObject]@{ Nivel = "INFO"; Categoria = "APP" }
    }

    # Prioridad 4: proceso con ruta inusual (fuera de dirs estandar)
    if ($Ruta -and $Ruta -ne "N/A") {
        $rutaEstandar = $Ruta -match `
            '(\\Windows\\|\\Program Files|\\AppData\\|\\Microsoft\\)'
        if (-not $rutaEstandar) {
            return [PSCustomObject]@{ Nivel = "WARNING"; Categoria = "EXT" }
        }
    }

    # Prioridad 5: sin ruta detectable (proceso protegido o del kernel)
    if (-not $Ruta -or $Ruta -eq "N/A") {
        return [PSCustomObject]@{ Nivel = "INFO"; Categoria = "SYS" }
    }

    # Default: proceso desconocido pero con ruta estandar
    return [PSCustomObject]@{ Nivel = "WARNING"; Categoria = "DES" }
}

#endregion

try{

    #region RECOLECCION DE DATOS

    # Recursos globales del sistema
    $os  = $null
    $cpu = $null

    try {
        $os  = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
    } catch {
        Write-Log "No se pudo obtener informacion de CPU/RAM del sistema: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al obtener info de CPU/RAM: $($_.Exception.Message)" -Severity ERROR -Source TOOLKIT
    }

    $ramTotalMB = if ($os) { [math]::Round($os.TotalVisibleMemorySize / 1KB) } else { 0 }
    $ramLibreMB = if ($os) { [math]::Round($os.FreePhysicalMemory     / 1KB) } else { 0 }
    $ramUsadaMB = $ramTotalMB - $ramLibreMB
    $ramPct     = if ($ramTotalMB -gt 0) { [math]::Round(($ramUsadaMB / $ramTotalMB) * 100) } else { 0 }
    $cpuUso     = if ($cpu) { $cpu.LoadPercentage } else { 0 }

    # Recolectar todos los procesos con sus datos
    $todosProcesos = @()
    try {
        $todosProcesos = Get-Process -ErrorAction Stop | ForEach-Object {
            $ruta   = try { $_.MainModule.FileName } catch { $null }
            $clasif = Get-ClasificacionProceso -Nombre $_.Name -Ruta $ruta

            [PSCustomObject]@{
                Nombre    = $_.Name
                PID       = $_.Id
                CPU       = [math]::Round($_.CPU, 1)
                RAMMB     = [math]::Round($_.WorkingSet / 1MB, 1)
                Nivel     = $clasif.Nivel
                Categoria = $clasif.Categoria
            }
        }
    } catch {
        Write-Log "No se pudo obtener la lista de procesos: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al obtener procesos: $($_.Exception.Message)" -Severity ERROR -Source TOOLKIT
    }


    # Top 15 por RAM
    $topRAM = @($todosProcesos | Sort-Object RAMMB -Descending | Select-Object -First 15)
    # Top 15 por CPU
    $topCPU = @($todosProcesos | Sort-Object CPU -Descending | Select-Object -First 15)

    # Procesos agrupados por nombre con clasificacion
    $procesosAgrupados = @($todosProcesos |
            Group-Object Nombre |
            ForEach-Object {
                $grupo    = $_
                $nivelMax = ($grupo.Group | Where-Object { $_.Nivel -eq "ERROR" }   | Select-Object -First 1)
                if (-not $nivelMax) { $nivelMax = $grupo.Group | Where-Object { $_.Nivel -eq "WARNING" } | Select-Object -First 1 }
                if (-not $nivelMax) { $nivelMax = $grupo.Group[0] }

                $ramTotal = ($grupo.Group | Measure-Object RAMMB -Sum).Sum
                $cpuTotal = ($grupo.Group | Measure-Object CPU  -Sum).Sum

                [PSCustomObject]@{
                    Nombre     = $grupo.Name
                    Instancias = $grupo.Count
                    CPU        = [math]::Round($cpuTotal, 1)
                    RAMMB      = [math]::Round($ramTotal, 1)
                    Nivel      = $nivelMax.Nivel
                    Categoria  = $nivelMax.Categoria
                }
            } | Sort-Object @{Expression={ @{ ERROR=0; WARNING=1; INFO=2; SUCCESS=3 }[$_.Nivel] }; Ascending=$true},
            @{Expression={ $_.RAMMB }; Descending=$true})

    $procesosMalware      = @($procesosAgrupados | Where-Object { $_.Categoria -eq "MAL" })
    $procesosDesconocidos = @($procesosAgrupados | Where-Object { $_.Categoria -eq "DES" })
    $procesosRutaExterna  = @($procesosAgrupados | Where-Object { $_.Categoria -eq "EXT" })

    foreach ($p in $procesosMalware) {
        Add-ReportError -Report $script:report -Message "Posible malware detectado: $($p.Nombre)" -Severity ERROR -Source SYSTEM
    }
    foreach ($p in $procesosDesconocidos) {
        Add-ReportError -Report $script:report -Message "Proceso no reconocido: $($p.Nombre)" -Severity WARNING -Source SYSTEM
    }
    foreach ($p in $procesosRutaExterna) {
        Add-ReportError -Report $script:report -Message "Proceso con ruta externa: $($p.Nombre)" -Severity WARNING -Source SYSTEM
    }

    #endregion

    #region PRESENTACION

    Write-Section "PROCESOS EN EJECUCION" -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    # -- Resumen de recursos --
    Write-Section "RESUMEN DE RECURSOS" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "CPU uso global : $cpuUso%" -LogFile $LogFile
    Write-Log "RAM usada      : $ramUsadaMB MB de $ramTotalMB MB ($ramPct%)" -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    # -- Top 15 por RAM --
    Write-Section "TOP 15 POR RAM" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    foreach ($p in $topRAM) {
        $linea = "{0,-25} RAM:{1,7} MB  CPU:{2,7}s" -f $p.Nombre, $p.RAMMB, $p.CPU
        Write-Log $linea -Level $p.Nivel -LogFile $LogFile
    }
    Write-Blank -LogFile $LogFile

    # -- Top 15 por CPU --
    Write-Section "TOP 15 POR CPU" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    foreach ($p in $topCPU) {
        $linea = "{0,-25} CPU:{1,7}s  RAM:{2,7} MB" -f $p.Nombre, $p.CPU, $p.RAMMB
        Write-Log $linea -Level $p.Nivel -LogFile $LogFile
    }
    Write-Blank -LogFile $LogFile

    # -- Todos los procesos agrupados por clasificacion --
    Write-Section "TODOS LOS PROCESOS" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "Agrupados por nombre. ERROR y WARNING aparecen primero." -Level NOTE -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    foreach ($p in $procesosAgrupados) {
        $instStr    = if ($p.Instancias -gt 1) { " x$($p.Instancias)" } else { "" }
        $nombreInst = "$($p.Nombre)$instStr"
        $tag        = Get-CenteredTag -Text $p.Categoria -TotalWidth 5
        $linea      = "{0,-25} {1}" -f $nombreInst, $tag
        Write-Log $linea -Level $p.Nivel -LogFile $LogFile
    }

    Write-Blank -LogFile $LogFile
    Write-Log "Referencias: S.O = Sistema operativo  APP = Aplicacion conocida  SYS = Sin ruta/kernel" -Level NOTE -LogFile $LogFile
    Write-Log "             EXT = Ruta externa       DES = Desconocido          MAL = Posible malware" -Level NOTE -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    #endregion

    #region REPORTE

    $script:report.data = @{
        cpuUsoPct           = $cpuUso
        ramUsadaMB          = $ramUsadaMB
        ramTotalMB          = $ramTotalMB
        ramPct              = $ramPct
        totalProcesosUnicos = @($procesosAgrupados).Count
        procesosMalware      = @($procesosMalware      | Select-Object Nombre, Instancias)
        procesosDesconocidos = @($procesosDesconocidos | Select-Object Nombre, Instancias)
        procesosRutaExterna  = @($procesosRutaExterna  | Select-Object Nombre, Instancias)
        topRAM = @($topRAM | Select-Object Nombre, RAMMB, CPU, Categoria)
        topCPU = @($topCPU | Select-Object Nombre, CPU, RAMMB, Categoria)
    }

    $status = if (@($script:report.errors | Where-Object { $_.severity -eq "ERROR" }).Count -gt 0) { "ERROR" } else { "OK" }
    $script:report = Complete-ModuleReport -Report $script:report -Status $status

    #endregion

} catch {
    Write-Log "Error fatal en el modulo: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
    Add-ReportError -Report $script:report -Message $_.Exception.Message -Severity ERROR -Source TOOLKIT
    $script:report = Complete-ModuleReport -Report $script:report -Status "ERROR"
} finally {
    Save-ModuleReport -Report $script:report -ReportFile $reportFile
}

#region SALIDA

Write-Section -LogFile $LogFile
Write-Log "Log guardado en: $LogFile" -LogFile $LogFile
Write-Blank

Invoke-Pause

#endregion