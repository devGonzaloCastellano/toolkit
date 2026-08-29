<#
.SYNOPSIS
    Modulo de auditoria de procesos en ejecucion.
.DESCRIPTION
    Muestra los procesos activos clasificados por origen y nivel de riesgo,
    agrupando instancias multiples del mismo proceso. Abrevia rutas largas
    para mejorar la legibilidad. Incluye resumen de uso de CPU y RAM.
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

$envInfo = Initialize-Environment -LogDir $LogDir -ModuleName "procesos"
$LogFile = $envInfo.LogFile

Set-CurrentExecution -ModuleName "procesos" -TxtPath $LogFile

$reportsDir = Join-Path (Split-Path $LogDir -Parent) "reports"
$reportFile = Get-ReportFileName -ReportsDir $reportsDir -ModuleName "procesos"
$script:report = New-ModuleReport -ModuleName "procesos"

#endregion

#region DATOS - TABLAS DE CLASIFICACION

$ProcesosSistema = @(Import-DataList -FileName "procesos_sistema.json")
$ProcesosAplicaciones = @(Import-DataList -FileName "procesos_aplicaciones.json")
$ProcesosMalware = @(Import-DataList -FileName "procesos_malware.json")

if(@($ProcesosSistema).Count -eq 0){
    Write-Log "Listado de procesos de sistema no disponible, la clasificacion puede ser menos precisa" -Level WARNING -LogFile $LogFile
    Add-ReportError -Report $script:report -Message "Listado procesos_sistema.json no disponible o vacio" -Severity WARNING -Source TOOLKIT
}

if(@($ProcesosAplicaciones).Count -eq 0){
    Write-Log "Listado de procesos de sistema no disponible, la clasificacion puede ser menos precisa" -Level WARNING -LogFile $LogFile
    Add-ReportError -Report $script:report -Message "Listado procesos_aplicaciones.json no disponible o vacio" -Severity WARNING -Source TOOLKIT
}

if(@($ProcesosMalware).Count -eq 0){
    Write-Log "Listado de procesos de sistema no disponible, la clasificacion puede ser menos precisa" -Level ERROR -LogFile $LogFile
    Add-ReportError -Report $script:report -Message "Listado procesos_malware.json no disponible o vacio" -Severity WARNING -Source TOOLKIT
}

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

    #region GENERACION HTML

    $procesosNoReconocidos = @($procesosAgrupados | Where-Object { $_.Categoria -in @("DES", "EXT") })

    $healthScore = 100 - (@($procesosMalware).Count * 5)
    if ($healthScore -lt 0) { $healthScore = 0 }

    $script:report.healthScore = $healthScore

    $nivelSalud = if (@($procesosMalware).Count -eq 0) { "OK" } else { "ERROR" }

    $filasMalware = ""
    foreach ($p in $procesosMalware) {
        $filasMalware += "<tr><td>$($p.Nombre)</td><td>$($p.Instancias)</td></tr>`n"
    }

    $seccionMalware = if (@($procesosMalware).Count -gt 0) {
        @"
    <h2>Alerta de seguridad</h2>
    <p style="font-size:13px; color:#c62828; font-weight:bold;">
        Se detectaron procesos que coinciden con nombres de malware conocido.
        Se recomienda contactar a su tecnico de inmediato.
    </p>
    <table>
        <tr><th>Proceso</th><th>Instancias</th></tr>
        $filasMalware
    </table>
"@
    } else {
        "<h2>Seguridad</h2><p>$(New-HtmlBadge -Texto "Sin coincidencias de malware conocido" -Nivel OK)</p>"
    }

    $filasNoReconocidos = ""
    foreach ($p in ($procesosNoReconocidos | Select-Object -First 15)) {
        $filasNoReconocidos += "<tr><td>$($p.Nombre)</td><td>$($p.Instancias)</td></tr>`n"
    }

    $seccionNoReconocidos = if (@($procesosNoReconocidos).Count -gt 0) {
        @"
    <h2>Procesos no reconocidos</h2>
    <p style="font-size:13px;">Estos procesos no estan en nuestra base de aplicaciones conocidas.
    En la mayoria de los casos son programas legitimos que aun no incluimos en nuestra base:</p>
    <table>
        <tr><th>Proceso</th><th>Instancias</th></tr>
        $filasNoReconocidos
    </table>
"@
    } else { "" }

    $contentHtml = @"
    <h2>Resumen</h2>
    <div class="metric"><div class="valor">$cpuUso%</div><div class="label">Uso de CPU</div></div>
    <div class="metric"><div class="valor">$ramPct%</div><div class="label">Uso de RAM</div></div>
    <div class="metric"><div class="valor">$(@($procesosMalware).Count)</div><div class="label">Alertas de seguridad</div></div>
    $seccionMalware
    $seccionNoReconocidos
"@

    $reportFileHtml = Get-ReportFileName -ReportsDir $reportsDir -ModuleName "procesos" -Extension "html"
    Save-ModuleReportHtml -Report $script:report -ReportFile $reportFileHtml -TituloModulo "Procesos en Ejecucion" -ContentHtml $contentHtml -NivelOverride $nivelSalud

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