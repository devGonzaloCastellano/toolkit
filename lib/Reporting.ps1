<#
.SYNOPSIS
    Modulo de generacion de reportes estructurados en formato JSON y HTML.
.DESCRIPTION
    Provee las funciones necesarias para crear, completar y guardar
    reportes en formato JSON para cada modulo de la toolkit, siguiendo
    un schema fijo y versionado independiente del resto del proyecto.
    Tambien provee la generacion de reportes HTML orientados a cliente
    a partir de ese mismo reporte, con un armazon comun (header,
    veredicto general, estilos) y contenido especifico por modulo.
    Debe importarse via dot-sourcing al inicio de cada script:
        . "$PSScriptRoot\..\lib\Reporting.ps1"
.NOTES
    Version JSON : 1.0.0 (schema JSON)
    Version HTML : 1.0.0 (schema HTML)
    Proyecto     : Portable Windows Toolkit
#>

#region CONSTANTES

$script:ToolkitVersion = "3.1.0"

#endregion

#region NOMENCLATURA DE ARCHIVOS

<#
.SYNOPSIS
    Genera el nombre de archivo para el reporte de un modulo.
.DESCRIPTION
    El nombre se compone del nombre del modulo y la fecha en formato
    corto (yyMMdd), pensado para facilitar la agrupacion de reportes
    generados el mismo dia. Si ya existe un reporte con ese nombre
    (por ejecutarse el modulo mas de una vez en el mismo dia), agrega
    un sufijo numerico incremental para no sobreescribirlo.
    Los archivos se guardan en una subcarpeta segun su extension
    (reports/json/ o reports/html/), creandola si no existe.
.PARAMETER ReportsDir
    Ruta al directorio base donde se guardan los reportes.
.PARAMETER ModuleName
    Nombre del modulo en ejecucion (ej: "reporte_disco").
.PARAMETER Extension
    Extension del archivo a generar: "json" (por defecto) o "html".
.OUTPUTS
    [string] Ruta completa al archivo a generar.
.EXAMPLE
    Get-ReportFileName -ReportsDir "C:\Toolkit\reports" -ModuleName "reporte_disco"
    # C:\Toolkit\reports\json\reporte_disco_260710.json

    Get-ReportFileName -ReportsDir "C:\Toolkit\reports" -ModuleName "reporte_disco" -Extension "html"
    # C:\Toolkit\reports\html\reporte_disco_260710.html
#>
function Get-ReportFileName {
    param(
        [Parameter(Mandatory)]
        [string]$ReportsDir,

        [Parameter(Mandatory)]
        [string]$ModuleName,

        [ValidateSet("json", "html")]
        [string]$Extension = "json"
    )

    $subDir = Join-Path $ReportsDir $Extension
    if (-not (Test-Path $subDir)) {
        New-Item -ItemType Directory -Path $subDir | Out-Null
    }

    $datePart  = Get-Date -Format "yyMMdd"
    $baseName  = "${ModuleName}_${datePart}"
    $reportFile = Join-Path $subDir "$baseName.$Extension"

    $counter = 2
    while (Test-Path $reportFile) {
        $reportFile = Join-Path $subDir "${baseName}_${counter}.$Extension"
        $counter++
    }

    return $reportFile
}

#endregion

#region CONSTRUCCION DEL REPORTE

<#
.SYNOPSIS
    Crea el esqueleto inicial de un reporte de modulo.
.DESCRIPTION
    Inicializa el objeto de reporte con los campos fijos del schema
    (schemaVersion, toolkitVersion, module, executionId, startTime),
    dejando 'data' vacio para que el modulo lo complete con su propio
    contenido, y 'errors' como array vacio para fallos no fatales.
.PARAMETER ModuleName
    Nombre del modulo en ejecucion (ej: "reporte_disco").
.PARAMETER ToolkitVersion
    Version actual de la toolkit (ej: "3.0.0").
.OUTPUTS
    [hashtable] Objeto de reporte inicializado.
.EXAMPLE
    $report = New-ModuleReport -ModuleName "reporte_disco" -ToolkitVersion "3.0.0"
#>
function New-ModuleReport {
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName
    )

    $script:reportStartTime = Get-Date

    return @{
        schemaVersion   = "1.0"
        toolkitVersion  = $script:ToolkitVersion
        module          = $ModuleName
        executionId     = (Get-Date -Format "yyyyMMdd-HHmmss")
        durationSeconds = $null
        status          = "OK"
        data            = @{}
        errors          = @()
    }
}

<#
.SYNOPSIS
    Finaliza un reporte de modulo, completando endTime y status.
.PARAMETER Report
    Objeto de reporte generado por New-ModuleReport.
.PARAMETER Status
    Estado final del modulo: OK o ERROR.
.OUTPUTS
    [hashtable] Reporte completado.
.EXAMPLE
    $report = Complete-ModuleReport -Report $report -Status "OK"
#>
function Complete-ModuleReport {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Report,

        [Parameter(Mandatory)]
        [ValidateSet("OK", "ERROR")]
        [string]$Status
    )

    $Report.durationSeconds = [math]::Round(((Get-Date) - $script:reportStartTime).TotalSeconds, 2)
    $Report.status = $Status

    return $Report
}

<#
.SYNOPSIS
    Guarda un reporte de modulo en formato JSON.
.PARAMETER Report
    Objeto de reporte completo (ya pasado por Complete-ModuleReport).
.PARAMETER ReportFile
    Ruta completa al archivo de salida, generada por Get-ReportFileName.
.EXAMPLE
    Save-ModuleReport -Report $report -ReportFile $reportFile
#>
function Save-ModuleReport {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Report,

        [Parameter(Mandatory)]
        [string]$ReportFile
    )

    $Report | ConvertTo-Json -Depth 10 | Out-File -FilePath $ReportFile -Encoding utf8
}

#endregion

#region MANEJO DE ERRORES

<#
.SYNOPSIS
    Agrega un error al reporte de un modulo, distinguiendo su origen.
.DESCRIPTION
    Registra un error dentro del array 'errors' del reporte, sin
    interrumpir la ejecucion del modulo. Distingue si el error es
    una falla del toolkit (TOOLKIT) o un hallazgo real sobre el
    equipo evaluado (SYSTEM), para que ambos tipos puedan tratarse
    de forma distinta en consolidacion e informes futuros.
.PARAMETER Report
    Objeto de reporte generado por New-ModuleReport.
.PARAMETER Message
    Descripcion del error o hallazgo.
.PARAMETER Severity
    Nivel del error: WARNING o ERROR.
.PARAMETER Source
    Origen del error: TOOLKIT (fallo del script) o SYSTEM (hallazgo
    sobre el equipo evaluado).
.EXAMPLE
    Add-ReportError -Report $report -Message "Fallo al leer particiones" -Severity ERROR -Source TOOLKIT
    Add-ReportError -Report $report -Message "Unidad D con errores menores" -Severity WARNING -Source SYSTEM
#>
function Add-ReportError {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Report,

        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("WARNING", "ERROR")]
        [string]$Severity = "ERROR",

        [Parameter(Mandatory)]
        [ValidateSet("TOOLKIT", "SYSTEM")]
        [string]$Source
    )

    $Report.errors += @{
        message  = $Message
        severity = $Severity
        source   = $Source
    }
}

#endregion

#region GENERACION DE REPORTES HTML

<#
.SYNOPSIS
    Calcula el nivel general del reporte para el veredicto visible al cliente.
.DESCRIPTION
    Se basa unicamente en hallazgos de origen SYSTEM (reales sobre el
    equipo), ignorando errores TOOLKIT (fallas internas del script, que
    no le competen al cliente). ERROR si hay al menos un hallazgo SYSTEM
    de severidad ERROR; WARNING si hay al menos uno de severidad WARNING;
    OK si no hay ninguno.
.PARAMETER Report
    Objeto de reporte generado por New-ModuleReport.
.OUTPUTS
    [string] "OK", "WARNING" o "ERROR".
#>
function Get-NivelGeneral {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Report
    )

    $sysErrores = @($Report.errors | Where-Object { $_.source -eq "SYSTEM" -and $_.severity -eq "ERROR" })
    if (@($sysErrores).Count -gt 0) { return "ERROR" }

    $sysWarnings = @($Report.errors | Where-Object { $_.source -eq "SYSTEM" -and $_.severity -eq "WARNING" })
    if (@($sysWarnings).Count -gt 0) { return "WARNING" }

    return "OK"
}

<#
.SYNOPSIS
    Genera un badge HTML (etiqueta de color) para un valor puntual.
.PARAMETER Texto
    Texto a mostrar dentro del badge.
.PARAMETER Nivel
    "OK", "WARNING" o "ERROR" - determina el color.
.OUTPUTS
    [string] fragmento HTML del badge.
.EXAMPLE
    New-HtmlBadge -Texto "Activo" -Nivel WARNING
#>
function New-HtmlBadge {
    param(
        [Parameter(Mandatory)]
        [string]$Texto,

        [Parameter(Mandatory)]
        [ValidateSet("OK", "WARNING", "ERROR")]
        [string]$Nivel
    )

    $clase = switch ($Nivel) {
        "OK"      { "badge-ok" }
        "WARNING" { "badge-warning" }
        "ERROR"   { "badge-error" }
    }

    return "<span class=`"badge $clase`">$Texto</span>"
}

<#
.SYNOPSIS
    Genera y guarda el reporte HTML de un modulo, orientado a cliente.
.DESCRIPTION
    Envuelve el contenido especifico del modulo (ya armado en HTML por
    el propio modulo) con un armazon comun: header, veredicto general
    (semaforo calculado con Get-NivelGeneral), estilos, y footer. El
    CSS va embebido en el propio archivo para que el HTML sea portable
    y autocontenido (util para enviar por email o abrir sin conexion).
.PARAMETER Report
    Objeto de reporte generado por New-ModuleReport.
.PARAMETER ReportFile
    Ruta completa al archivo HTML de salida.
.PARAMETER TituloModulo
    Nombre amigable del modulo para mostrar en el reporte (ej: "Estado del Disco").
.PARAMETER ContentHtml
    Fragmento de HTML con el contenido especifico del modulo, ya armado
    por el llamador.
.EXAMPLE
    Save-ModuleReportHtml -Report $report -ReportFile $reportFileHtml -TituloModulo "Estado del Disco" -ContentHtml $contenido
#>
function Save-ModuleReportHtml {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Report,

        [Parameter(Mandatory)]
        [string]$ReportFile,

        [Parameter(Mandatory)]
        [string]$TituloModulo,

        [Parameter(Mandatory)]
        [string]$ContentHtml,

        [ValidateSet("OK", "WARNING", "ERROR")]
        [string]$NivelOverride

    )

    $nivelGeneral = if ($NivelOverride) { $NivelOverride } else { Get-NivelGeneral -Report $Report }

    $colores = @{ OK = "#2e7d32"; WARNING = "#f9a825"; ERROR = "#c62828" }
    $textos  = @{ OK = "Todo en orden"; WARNING = "Requiere atencion"; ERROR = "Accion requerida" }

    $colorGeneral  = $colores[$nivelGeneral]
    $textoGeneral  = $textos[$nivelGeneral]
    $fecha         = Get-Date -Format "dd/MM/yyyy HH:mm"
    $equipo        = $env:COMPUTERNAME

    $html = @"
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<title>$TituloModulo - Reporte</title>
<style>
    body { font-family: 'Segoe UI', Arial, sans-serif; background:#f2f2f2; color:#222; margin:0; padding:0; }
    .contenedor { max-width: 800px; margin: 30px auto; box-shadow: 0 1px 4px rgba(0,0,0,0.1); }
    .header { background:#1a1a2e; color:#fff; padding: 20px 24px; }
    .header h1 { margin:0; font-size: 22px; }
    .header .meta { font-size: 13px; color:#ccc; margin-top:6px; }
    .veredicto { padding: 14px 24px; color:#fff; font-weight:bold; font-size:16px; background:$colorGeneral; }
    .cuerpo { background:#fff; padding:24px; }
    .badge { display:inline-block; padding:2px 10px; border-radius:12px; color:#fff; font-size:12px; font-weight:bold; }
    .badge-ok { background:#2e7d32; }
    .badge-warning { background:#f9a825; color:#222; }
    .badge-error { background:#c62828; }
    .metric { display:inline-block; text-align:center; padding:10px 24px 10px 0; vertical-align:top; }
    .metric .valor { font-size:28px; font-weight:bold; }
    .metric .label { font-size:12px; color:#666; margin-top:2px; }
    .footer { text-align:center; font-size:11px; color:#999; padding: 16px; background:#fafafa; }
    table { width:100%; border-collapse: collapse; margin-top:8px; table-layout: fixed; }
    th, td { text-align:left; padding:6px 8px; border-bottom:1px solid #eee; font-size:13px; word-wrap: break-word; overflow-wrap: break-word; }
    h2 { font-size:15px; color:#1a1a2e; border-bottom: 2px solid #eee; padding-bottom:6px; margin-top:28px; }
    * { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    </style>
</head>
<body>
<div class="contenedor">
    <div class="header">
        <h1>$TituloModulo</h1>
        <div class="meta">Equipo: $equipo &nbsp;|&nbsp; Fecha: $fecha</div>
    </div>
    <div class="veredicto">$textoGeneral</div>
    <div class="cuerpo">
$ContentHtml
    </div>
    <div class="footer">Generado por Portable Windows Toolkit v$($Report.toolkitVersion)</div>
</div>
</body>
</html>
"@

    try {
        $html | Out-File -FilePath $ReportFile -Encoding utf8 -ErrorAction Stop
    } catch {
        Write-Log "No se pudo guardar el reporte HTML: $($_.Exception.Message)" -Level ERROR
    }
}

#endregion
