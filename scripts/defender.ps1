<#
.SYNOPSIS
    Modulo de actualizacion y escaneo de Windows Defender.
.DESCRIPTION
    Muestra el estado actual de Windows Defender, actualiza las definiciones
    de firmas de antivirus y antispyware, y opcionalmente ejecuta un escaneo
    rapido del sistema detectando amenazas activas.
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

$envInfo = Initialize-Environment -LogDir $LogDir -ModuleName "defender"
$LogFile = $envInfo.LogFile

Set-CurrentExecution -ModuleName "defender" -TxtPath $LogFile

$reportsDir = Join-Path (Split-Path $LogDir -Parent) "reports"
$reportFile = Get-ReportFileName -ReportsDir $reportsDir -ModuleName "defender"
$script:report = New-ModuleReport -ModuleName "defender"

#endregion

#region FUNCIONES INTERNAS

<#
.SYNOPSIS
    Obtiene el estado actual de Windows Defender via CIM.
.OUTPUTS
    CimInstance de MpComputerStatus o $null si no esta disponible.
#>
function Get-DefenderStatus {
    try {
        return Get-MpComputerStatus -ErrorAction Stop
    } catch {
        Write-Log "No se pudo obtener el estado de Windows Defender: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al obtener estado de Defender: $($_.Exception.Message)" -Severity ERROR -Source TOOLKIT
        return $null
    }
}

<#
.SYNOPSIS
    Genera una version resumida y plana del estado de Windows Defender.
.DESCRIPTION
    Extrae unicamente los campos relevantes de un objeto CIM devuelto por
    Get-MpComputerStatus, descartando toda la metadata interna (CimClass,
    CimSystemProperties, Qualifiers, etc.) que no aporta valor al reporte
    y que de incluirse generaria un JSON excesivamente pesado.
.PARAMETER Status
    Objeto CimInstance retornado por Get-MpComputerStatus (via Get-DefenderStatus).
.OUTPUTS
    [hashtable] con los campos relevantes, o $null si Status es $null.
#>
function Get-DefenderStatusSummary {
    param($Status)

    if (-not $Status) { return $null }

    return @{
        realTimeProtection   = $Status.RealTimeProtectionEnabled
        antivirusEnabled     = $Status.AntivirusEnabled
        antispywareEnabled   = $Status.AntispywareEnabled
        signatureVersion     = $Status.AntivirusSignatureVersion
        lastSignatureUpdate  = $Status.AntivirusSignatureLastUpdated.ToString("yyyy-MM-dd HH:mm")
        quickScanAgeDays     = $Status.QuickScanAge
        fullScanAgeDays      = $Status.FullScanAge
    }
}

<#
.SYNOPSIS
    Formatea e imprime el estado de Defender en consola y log.
.PARAMETER Status
    Objeto CimInstance retornado por Get-MpComputerStatus.
#>
function Show-DefenderStatus {
    param($Status)

    if (-not $Status) {
        Write-Log "No se pudo obtener el estado de Windows Defender." -Level WARNING -LogFile $LogFile
        return
    }

    $ultimoRapido = if ($Status.QuickScanAge -eq 0) { "Hoy" } else { "Hace $($Status.QuickScanAge) dia/s" }
    $ultimoEscaneo = if ($Status.FullScanAge -ge 4294967295) { "Nunca" } `
                 elseif ($Status.FullScanAge -eq 0) { "Hoy" } `
                 else { "Hace $($Status.FullScanAge) dia/s" }

    Write-Log "Proteccion en tiempo real : $($Status.RealTimeProtectionEnabled)"       -LogFile $LogFile
    Write-Log "Antivirus habilitado      : $($Status.AntivirusEnabled)"                -LogFile $LogFile
    Write-Log "Antispyware habilitado    : $($Status.AntispywareEnabled)"              -LogFile $LogFile
    Write-Log "Version de firma AV       : $($Status.AntivirusSignatureVersion)"       -LogFile $LogFile
    Write-Log "Ultima actualizacion      : $($Status.AntivirusSignatureLastUpdated)"   -LogFile $LogFile
    Write-Log "Ultimo escaneo rapido     : $ultimoRapido"                              -LogFile $LogFile
    Write-Log "Ultimo escaneo completo   : $ultimoEscaneo"                             -LogFile $LogFile

    if (-not $Status.RealTimeProtectionEnabled -or -not $Status.AntivirusEnabled) {
        Add-ReportError -Report $script:report -Message "Proteccion en tiempo real o antivirus desactivado" -Severity WARNING -Source SYSTEM
    }

}

#endregion

try{

    #region RECOLECCION DE DATOS INICIAL

    $statusPrevio = Get-DefenderStatus
    $statusPrevioResumen = Get-DefenderStatusSummary -Status $statusPrevio

    #endregion

    #region ESTADO ACTUAL

    Write-Section "WINDOWS DEFENDER" -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    Write-Section "ESTADO ACTUAL" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Show-DefenderStatus -Status $statusPrevio
    Write-Blank -LogFile $LogFile

    #endregion

    #region TEST DE CONECTIVIDAD

    Write-Section "Test de Conectividad" -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    if (-not (Test-InternetConnection)) {
        Write-Log "Sin conexion a internet. Este modulo requiere conexion activa." -Level ERROR -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Sin conexion a internet, modulo interrumpido" -Severity ERROR -Source TOOLKIT

        $script:report.data = @{
        statusPrevio = $statusPrevio
    }
    $script:report = Complete-ModuleReport -Report $script:report -Status "ERROR"
    Save-ModuleReport -Report $script:report -ReportFile $reportFile

    Write-Blank -LogFile $LogFile
    Invoke-Pause
    exit 1
    }

    Write-Log "Conexion a internet verificada." -Level SUCCESS -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    #endregion

    #region ACTUALIZACION DE DEFINICIONES

    Write-Section "ACTUALIZANDO DEFINICIONES" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "Descargando ultimas firmas desde Microsoft..." -LogFile $LogFile
    Write-Log "Puede tardar unos minutos." -Level WARNING -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    $actualizacionOk = $true
    try {
        Update-MpSignature -ErrorAction Stop
        Write-Log "Actualizacion de firmas completada." -Level SUCCESS -LogFile $LogFile
    }catch {
        Write-Log "Error al actualizar firmas: $_" -Level ERROR -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al actualizar firmas: $($_.Exception.Message)" -Severity ERROR -Source TOOLKIT
        $actualizacionOk = $false
    }
    Write-Blank -LogFile $LogFile

    #endregion

    #region ESTADO POST-ACTUALIZACION

    $statusPost = Get-DefenderStatus
    $statusPostResumen = Get-DefenderStatusSummary -Status $statusPost

    Write-Section "ESTADO POST-ACTUALIZACION" -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    if ($statusPost) {
        Write-Log "Version de firma AV  : $($statusPost.AntivirusSignatureVersion)"     -LogFile $LogFile
        Write-Log "Ultima actualizacion : $($statusPost.AntivirusSignatureLastUpdated)" -LogFile $LogFile
    } else {
        Write-Log "No se pudo obtener estado post-actualizacion." -Level WARNING -LogFile $LogFile
    }
    Write-Blank -LogFile $LogFile

    #endregion

    #region ESCANEO RAPIDO
    Write-Section "ESCANEO RAPIDO" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "Un escaneo rapido revisa memoria, registro y carpetas de inicio." -Level NOTE -LogFile $LogFile
    Write-Log "Tarda entre 5 y 15 minutos." -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    $respuesta = Read-Host "   Ejecutar escaneo rapido ahora? (s/n)"

    $escaneoEjecutado = $false
    $amenazas = @()

    if ($respuesta -eq "s") {
        Write-Blank -LogFile $LogFile
        Write-Log "Iniciando escaneo rapido. No cerrar esta ventana..." -Level WARNING -LogFile $LogFile
        Write-Blank -LogFile $LogFile

        try {
            Start-MpScan -ScanType QuickScan -ErrorAction Stop
            Write-Log "Escaneo completado." -Level SUCCESS -LogFile $LogFile
            $escaneoEjecutado = $true
        } catch {
            Write-Log "Error durante el escaneo: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
            Add-ReportError -Report $script:report -Message "Fallo al ejecutar quick scan: $($_.Exception.Message)" -Severity ERROR -Source TOOLKIT
        }

        Write-Blank -LogFile $LogFile
        Write-Section "AMENAZAS DETECTADAS" -LogFile $LogFile
        Write-Blank -LogFile $LogFile

        $amenazas = @(Get-MpThreatDetection -ErrorAction SilentlyContinue)

        if (@($amenazas).Count -gt 0) {
            foreach ($amenaza in $amenazas) {
                Write-Log "AMENAZA: $($amenaza.ThreatName) - $($amenaza.Resources)" -Level ERROR -LogFile $LogFile
                Add-ReportError -Report $script:report -Message "Amenaza detectada: $($amenaza.ThreatName)" -Severity ERROR -Source SYSTEM
            }
        } else {
            Write-Log "Sin amenazas detectadas." -Level SUCCESS -LogFile $LogFile
        }

    } else {
        Write-Log "Escaneo omitido." -LogFile $LogFile
    }

    #endregion

    #region REPORTE

    $script:report.data = @{
        statusPrevio      = $statusPrevioResumen
        statusPost        = $statusPostResumen
        actualizacionOk   = $actualizacionOk
        escaneoEjecutado  = $escaneoEjecutado
        amenazas          = $amenazas
    }

    $status = if (@($script:report.errors | Where-Object { $_.severity -eq "ERROR" }).Count -gt 0) { "ERROR" } else { "OK" }
    $script:report = Complete-ModuleReport -Report $script:report -Status $status

    #endregion

    #region GENERACION HTML

    $hayAmenazas = @($amenazas).Count -gt 0
    $proteccionActiva = $statusPostResumen -and $statusPostResumen.realTimeProtection -and $statusPostResumen.antivirusEnabled

    $nivelResultado = if ($hayAmenazas) { "ERROR" }
    elseif (-not $proteccionActiva) { "WARNING" }
    else { "OK" }

    $textoProteccion = if ($proteccionActiva) { "Proteccion activa" } else { "Proteccion desactivada" }
    $nivelProteccion  = if ($proteccionActiva) { "OK" } else { "WARNING" }

    $textoFirmas = if ($actualizacionOk) { "Firmas actualizadas" } else { "No se pudieron actualizar las firmas" }
    $nivelFirmas  = if ($actualizacionOk) { "OK" } else { "WARNING" }

    $seccionAmenazas = if ($hayAmenazas) {
        $filas = ""
        foreach ($a in $amenazas) {
            $filas += "<tr><td>$($a.ThreatName)</td></tr>`n"
        }
        @"
    <h2>Alerta de seguridad</h2>
    <p style="font-size:13px; color:#c62828; font-weight:bold;">
        Se detectaron amenazas activas en el equipo. Se recomienda contactar a su tecnico de inmediato.
    </p>
    <table>
        <tr><th>Amenaza</th></tr>
        $filas
    </table>
"@
    } else {
        "<h2>Seguridad</h2><p>$(New-HtmlBadge -Texto "Sin amenazas detectadas" -Nivel OK)</p>"
    }

    $textoEscaneo = if ($escaneoEjecutado) { "Escaneo rapido ejecutado" } else { "Escaneo no ejecutado en esta sesion" }

    $contentHtml = @"
    <h2>Estado de Windows Defender</h2>
    <p>$(New-HtmlBadge -Texto $textoProteccion -Nivel $nivelProteccion) $(New-HtmlBadge -Texto $textoFirmas -Nivel $nivelFirmas)</p>
    <p style="font-size:13px; color:#666;">$textoEscaneo</p>
    $seccionAmenazas
"@

    $reportFileHtml = Get-ReportFileName -ReportsDir $reportsDir -ModuleName "defender" -Extension "html"
    Save-ModuleReportHtml -Report $script:report -ReportFile $reportFileHtml -TituloModulo "Windows Defender" -ContentHtml $contentHtml -NivelOverride $nivelResultado

    #endregion

} catch {
    Write-Log "Error fatal en el modulo: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
    Add-ReportError -Report $script:report -Message $_.Exception.Message -Severity ERROR -Source TOOLKIT
    $script:report = Complete-ModuleReport -Report $script:report -Status "ERROR"

} finally {
    Save-ModuleReport -Report $script:report -ReportFile $reportFile
}

#region SALIDA

Write-Blank -LogFile $LogFile
Write-Section -LogFile $LogFile
Write-Log "Log guardado en: $LogFile" -LogFile $LogFile
Write-Blank

Invoke-Pause

#endregion