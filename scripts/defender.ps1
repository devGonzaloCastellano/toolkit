<#
.SYNOPSIS
    Modulo de actualizacion y escaneo de Windows Defender.
.DESCRIPTION
    Muestra el estado actual de Windows Defender, actualiza las definiciones
    de firmas de antivirus y antispyware, y opcionalmente ejecuta un escaneo
    rapido del sistema detectando amenazas activas.
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

$envInfo = Initialize-Environment -LogDir $LogDir -ModuleName "defender"
$LogFile = $envInfo.LogFile

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
        return $null
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

    Write-Log "Proteccion en tiempo real : $($Status.RealTimeProtectionEnabled)" -LogFile $LogFile
    Write-Log "Antivirus habilitado      : $($Status.AntivirusEnabled)"          -LogFile $LogFile
    Write-Log "Antispyware habilitado    : $($Status.AntispywareEnabled)"         -LogFile $LogFile
    Write-Log "Version de firma AV       : $($Status.AntivirusSignatureVersion)"  -LogFile $LogFile
    Write-Log "Ultima actualizacion      : $($Status.AntivirusSignatureLastUpdated)" -LogFile $LogFil
    Write-Log "Ultimo escaneo rapido     : $ultimoRapido"                          -LogFile $LogFile
    Write-Log "Ultimo escaneo completo   : $ultimoEscaneo"                         -LogFile $LogFile
}

#endregion

#region RECOLECCION DE DATOS INICIAL

$statusPrevio = Get-DefenderStatus

#endregion

#region LOGICA PRINCIPAL

Write-Section "WINDOWS DEFENDER" -LogFile $LogFile
Write-Blank -LogFile $LogFile

# -- Seccion 1: Estado actual --
Write-Section "ESTADO ACTUAL" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Show-DefenderStatus -Status $statusPrevio
Write-Blank -LogFile $LogFile

# -- Seccion 2: Testeo de Conectividad
Write-Section "Test de Conectividad" -LogFile $LogFile

Write-Blank -LogFile $LogFile
if (-not (Test-InternetConnection)) {
    Write-Log "Sin conexion a internet. Este modulo requiere conexion activa." -Level ERROR -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Invoke-Pause exit 1 }
Write-Log "Conexion a internet verificada." -Level SUCCESS -LogFile $LogFile
Write-Blank -LogFile $LogFile

# -- Seccion 3: Actualizacion de definiciones --
Write-Section "ACTUALIZANDO DEFINICIONES" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "Descargando ultimas firmas desde Microsoft..." -LogFile $LogFile
Write-Log "Puede tardar unos minutos." -Level WARNING -LogFile $LogFile
Write-Blank -LogFile $LogFile

try {
    Update-MpSignature -ErrorAction Stop
    Write-Log "Actualizacion de firmas completada." -Level SUCCESS -LogFile $LogFile
} catch {
    Write-Log "Error al actualizar firmas: $_" -Level ERROR -LogFile $LogFile
}
Write-Blank -LogFile $LogFile

# -- Seccion 4: Estado post-actualizacion --
$statusPost = Get-DefenderStatus

Write-Section "ESTADO POST-ACTUALIZACION" -LogFile $LogFile
Write-Blank -LogFile $LogFile

if ($statusPost) {
    Write-Log "Version de firma AV  : $($statusPost.AntivirusSignatureVersion)"     -LogFile $LogFile
    Write-Log "Ultima actualizacion : $($statusPost.AntivirusSignatureLastUpdated)" -LogFile $LogFile
} else {
    Write-Log "No se pudo obtener estado post-actualizacion." -Level WARNING -LogFile $LogFile
}
Write-Blank -LogFile $LogFile

# -- Seccion 4: Escaneo rapido opcional --
Write-Section "ESCANEO RAPIDO" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "Un escaneo rapido revisa memoria, registro y carpetas de inicio." -Level NOTE -LogFile $LogFile
Write-Log "Tarda entre 5 y 15 minutos." -LogFile $LogFile
Write-Blank -LogFile $LogFile

$respuesta = Read-Host "   Ejecutar escaneo rapido ahora? (s/n)"

if ($respuesta -eq "s") {
    Write-Blank -LogFile $LogFile
    Write-Log "Iniciando escaneo rapido. No cerrar esta ventana..." -Level WARNING -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    try {
        Start-MpScan -ScanType QuickScan -ErrorAction Stop
        Write-Log "Escaneo completado." -Level SUCCESS -LogFile $LogFile
    } catch {
        Write-Log "Error durante el escaneo: $_" -Level ERROR -LogFile $LogFile
    }

    # Amenazas detectadas
    Write-Blank -LogFile $LogFile
    Write-Section "AMENAZAS DETECTADAS" -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    $amenazas = Get-MpThreatDetection -ErrorAction SilentlyContinue

    if ($amenazas) {
        foreach ($amenaza in $amenazas) {
            Write-Log "AMENAZA: $($amenaza.ThreatName) - $($amenaza.Resources)" -Level ERROR -LogFile $LogFile
        }
    } else {
        Write-Log "Sin amenazas detectadas." -Level SUCCESS -LogFile $LogFile
    }

} else {
    Write-Log "Escaneo omitido." -LogFile $LogFile
}

#endregion

#region RESUMEN

Write-Blank -LogFile $LogFile
Write-Section -LogFile $LogFile
Write-Log "Log guardado en: $LogFile" -LogFile $LogFile
Write-Blank

Invoke-Pause

#endregion