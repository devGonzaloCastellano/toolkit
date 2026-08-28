<#
.SYNOPSIS
    Modulo de auditoria de servicios innecesarios del sistema.
.DESCRIPTION
    Muestra el estado actual de servicios de telemetria, Xbox, y otros
    servicios raramente utilizados. No desactiva ni modifica nada,
    solo reporta el estado para que el tecnico tome decisiones informadas.
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

$envInfo = Initialize-Environment -LogDir $LogDir -ModuleName "servicios"
$LogFile = $envInfo.LogFile

Set-CurrentExecution -ModuleName "servicios" -TxtPath $LogFile

$reportsDir = Join-Path (Split-Path $LogDir -Parent) "reports"
$reportFile = Get-ReportFileName -ReportsDir $reportsDir -ModuleName "servicios"
$script:report = New-ModuleReport -ModuleName "servicios"

#endregion

#region DATOS - CATALOGO DE SERVICIOS

$Categorias = @(Import-DataList -FileName "servicios_catalogo.json")

if (@($Categorias).Count -eq 0) {
    Write-Log "Catalogo de servicios no disponible, no se realizara la auditoria." -Level ERROR -LogFile $LogFile
    Add-ReportError -Report $script:report -Message "Listado servicios_catalogo.json no disponible o vacio" -Severity WARNING -Source TOOLKIT
}

#endregion

#region FUNCIONES INTERNAS

<#
.SYNOPSIS
    Obtiene el estado de un servicio por nombre.
.PARAMETER Nombre
    Nombre tecnico del servicio (ej: "DiagTrack").
.OUTPUTS
    String con el estado: "Running", "Stopped", "Disabled" o "Absent".
#>
function Get-EstadoServicio {
    param([string]$Nombre)

    try {
        $svc = Get-Service -Name $Nombre -ErrorAction Stop
        return $svc.Status.ToString()
    } catch {
        return "Absent"
    }
}

<#
.SYNOPSIS
    Determina el nivel de log segun el estado del servicio.
.DESCRIPTION
    Running es WARNING porque indica un servicio innecesario activo.
    Stopped y Disabled son SUCCESS porque es el estado esperado.
    No instalado es INFO porque es neutral.
.PARAMETER Estado
    String con el estado del servicio.
.OUTPUTS
    String con el nivel de log: WARNING, SUCCESS o INFO.
#>
function Get-NivelPorEstado {
    param([string]$Estado)

    switch ($Estado) {
        "Running"   { return "WARNING" }
        "Stopped"   { return "SUCCESS" }
        "Disabled"  { return "SUCCESS" }
        "Absent"    { return "INFO"    }
        default     { return "INFO"    }
    }
}

#endregion

try{

    #region RECOLECCION DE DATOS

    # Consultamos todos los servicios antes de mostrar nada
    # para separar la obtencion de datos de la presentacion
    $Resultados = foreach ($categoria in $Categorias) {
        $serviciosEvaluados = foreach ($svc in $categoria.Servicios) {
            $estado = Get-EstadoServicio -Nombre $svc.Nombre
            [PSCustomObject]@{
                Nombre      = $svc.Nombre
                Descripcion = $svc.Descripcion
                Estado      = $estado
                Nivel       = Get-NivelPorEstado -Estado $estado
            }
        }
        [PSCustomObject]@{
            Titulo    = $categoria.Titulo
            Servicios = $serviciosEvaluados
        }
    }

    # -- Hallazgos: servicios innecesarios activos --
    $serviciosActivos = @($Resultados | ForEach-Object { $_.Servicios } | Where-Object { $_.Estado -eq "Running" })

    foreach ($svc in $serviciosActivos) {
        Add-ReportError -Report $script:report -Message "Servicio innecesario activo: $($svc.Nombre) ($($svc.Descripcion))" -Severity WARNING -Source SYSTEM
    }

    #endregion

    #region PRESENTACION

    Write-Section "SERVICIOS INNECESARIOS" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "Solo muestra estado. No desactiva ni modifica nada." -Level NOTE -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    foreach ($categoria in $Resultados) {
        Write-Section $categoria.Titulo -LogFile $LogFile
        Write-Blank -LogFile $LogFile

        foreach ($svc in $categoria.Servicios) {
            $tag   = Get-CenteredTag -Text $svc.Estado -TotalWidth 9
            $linea = "{0,-18} {1} {2}" -f $svc.Nombre, $tag, $svc.Descripcion
            Write-Log $linea -Level $svc.Nivel -LogFile $LogFile
        }

        Write-Blank -LogFile $LogFile
    }

    #endregion

    #region REFERENCIA DE COMANDOS

    Write-Section "REFERENCIA DE COMANDOS" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "Para deshabilitar un servicio:" -Level NOTE -LogFile $LogFile
    Write-Log "  Stop-Service -Name 'NombreServicio' -Force" -Level NOTE -LogFile $LogFile
    Write-Log "  Set-Service  -Name 'NombreServicio' -StartupType Disabled" -Level NOTE -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "Para reactivar un servicio:" -LogFile $LogFile -Level NOTE
    Write-Log "  Set-Service  -Name 'NombreServicio' -StartupType Automatic" -Level NOTE -LogFile $LogFile
    Write-Log "  Start-Service -Name 'NombreServicio'" -Level NOTE -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    #endregion

    #region REPORTE

    $script:report.data = @{
        categorias = @($Resultados | ForEach-Object {
            @{
                titulo = $_.Titulo
                servicios = @($_.Servicios | Select-Object Nombre, Estado, Descripcion)
            }
        })
        totalActivos = @($serviciosActivos).Count
    }

    $status = if (@($script:report.errors | Where-Object { $_.severity -eq "ERROR" }).Count -gt 0) { "ERROR" } else { "OK" }
    $script:report = Complete-ModuleReport -Report $script:report -Status $status

    #endregion

    #region REPORTE

    $script:report.data = @{
        categorias = @($Resultados | ForEach-Object {
            @{
                titulo = $_.Titulo
                servicios = @($_.Servicios | Select-Object Nombre, Estado, Descripcion)
            }
        })
        totalActivos = @($serviciosActivos).Count
    }

    $status = if (@($script:report.errors | Where-Object { $_.severity -eq "ERROR" }).Count -gt 0) { "ERROR" } else { "OK" }
    $script:report = Complete-ModuleReport -Report $script:report -Status $status

    #endregion

    #region GENERACION HTML

    $totalServiciosEvaluados = @($Resultados | ForEach-Object { $_.Servicios }).Count

    $sysWarnings = @($script:report.errors | Where-Object { $_.source -eq "SYSTEM" -and $_.severity -eq "WARNING" }).Count
    $sysErrores  = @($script:report.errors | Where-Object { $_.source -eq "SYSTEM" -and $_.severity -eq "ERROR" }).Count

    $pesoWarning = 0.5
    $pesoError   = 1.0

    $healthScore = 100
    if ($totalServiciosEvaluados -gt 0) {
        $penalizacion = ($sysWarnings * $pesoWarning) + ($sysErrores * $pesoError)
        $healthScore = 100 - (($penalizacion / $totalServiciosEvaluados) * 100)
        if ($healthScore -lt 0) { $healthScore = 0 }
        $healthScore = [math]::Round($healthScore, 1)
    }

    $script:report.healthScore = $healthScore

    $nivelSalud = if ($healthScore -ge 85) { "OK" } elseif ($healthScore -ge 70) { "WARNING" } else { "ERROR" }

    $filasCategoria = ""
    foreach ($categoria in $Resultados) {
        $activosEnCategoria = @($categoria.Servicios | Where-Object { $_.Estado -eq "Running" }).Count
        $totalEnCategoria   = @($categoria.Servicios).Count
        $nivelCategoria     = if ($activosEnCategoria -eq 0) { "OK" } else { "WARNING" }
        $filasCategoria += "<tr><td>$($categoria.Titulo)</td><td>$totalEnCategoria</td><td>$(New-HtmlBadge -Texto "$activosEnCategoria activo(s)" -Nivel $nivelCategoria)</td></tr>`n"
    }

    $contentHtml = @"
    <h2>Resumen</h2>
    <div class="metric"><div class="valor">$healthScore%</div><div class="label">Salud de servicios</div></div>
    <div class="metric"><div class="valor">$totalServiciosEvaluados</div><div class="label">Servicios evaluados</div></div>
    <div class="metric"><div class="valor">$(@($serviciosActivos).Count)</div><div class="label">Activos a revisar</div></div>

    <h2>Detalle por categoria</h2>
    <table>
        <tr><th>Categoria</th><th>Evaluados</th><th>Estado</th></tr>
        $filasCategoria
    </table>

    <p style="font-size:12px; color:#666; margin-top:16px;">
        Los servicios listados aqui suelen estar detenidos de forma segura en la mayoria de los equipos.
        Si necesita mas detalle tecnico sobre cuales estan activos, consulte con su tecnico.
    </p>
"@

    $reportFileHtml = Get-ReportFileName -ReportsDir $reportsDir -ModuleName "servicios" -Extension "html"
    Save-ModuleReportHtml -Report $script:report -ReportFile $reportFileHtml -TituloModulo "Servicios Innecesarios" -ContentHtml $contentHtml -NivelOverride $nivelSalud
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