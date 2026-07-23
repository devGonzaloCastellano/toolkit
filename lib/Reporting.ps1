<#
.SYNOPSIS
    Modulo de generacion de reportes estructurados en formato JSON.
.DESCRIPTION
    Provee las funciones necesarias para crear, completar y guardar
    reportes en formato JSON para cada modulo de la toolkit, siguiendo
    un schema fijo y versionado independiente del resto del proyecto.
    Debe importarse via dot-sourcing al inicio de cada script:
        . "$PSScriptRoot\..\lib\Reporting.ps1"
.NOTES
    Version : 1.0.0 (schema JSON)
    Proyecto: Portable Windows Toolkit
#>

#region CONSTANTES

$script:ToolkitVersion = "3.0.0"

#endregion

#region NOMENCLATURA DE ARCHIVOS

<#
.SYNOPSIS
    Genera el nombre de archivo para el reporte JSON de un modulo.
.DESCRIPTION
    El nombre se compone del nombre del modulo y la fecha en formato
    corto (yyMMdd), pensado para facilitar la agrupacion de reportes
    generados el mismo dia. Si ya existe un reporte con ese nombre
    (por ejecutarse el modulo mas de una vez en el mismo dia), agrega
    un sufijo numerico incremental para no sobreescribirlo.
.PARAMETER ReportsDir
    Ruta al directorio donde se guardan los reportes.
.PARAMETER ModuleName
    Nombre del modulo en ejecucion (ej: "reporte_disco").
.OUTPUTS
    [string] Ruta completa al archivo JSON a generar.
.EXAMPLE
    Get-ReportFileName -ReportsDir "C:\Toolkit\reports" -ModuleName "reporte_disco"
    # C:\Toolkit\reports\reporte_disco_260710.json
#>
function Get-ReportFileName {
    param(
        [Parameter(Mandatory)]
        [string]$ReportsDir,

        [Parameter(Mandatory)]
        [string]$ModuleName
    )

    if (-not (Test-Path $ReportsDir)) {
        New-Item -ItemType Directory -Path $ReportsDir | Out-Null
    }

    $datePart = Get-Date -Format "yyMMdd"
    $baseName = "${ModuleName}_${datePart}"
    $reportFile = Join-Path $ReportsDir "$baseName.json"

    $counter = 2
    while (Test-Path $reportFile) {
        $reportFile = Join-Path $ReportsDir "${baseName}_${counter}.json"
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

