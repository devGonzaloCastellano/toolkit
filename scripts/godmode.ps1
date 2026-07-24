<#
.SYNOPSIS
    Modulo de activacion de God Mode en el Escritorio.
.DESCRIPTION
    Crea una carpeta especial en el Escritorio del usuario con acceso
    directo a todos los paneles de configuracion de Windows en un solo lugar.
    Si la carpeta ya existe, la abre directamente sin recrearla.
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

$envInfo = Initialize-Environment -LogDir $LogDir -ModuleName "godmode"
$LogFile = $envInfo.LogFile

Set-CurrentExecution -ModuleName "godmode" -TxtPath $LogFile

$reportsDir = Join-Path (Split-Path $LogDir -Parent) "reports"
$reportFile = Get-ReportFileName -ReportsDir $reportsDir -ModuleName "godmode"
$script:report = New-ModuleReport -ModuleName "godmode"

#endregion

#region VARIABLES

# GUID oficial de God Mode - no cambiar
$GodModeGUID   = "ED7BA470-8E54-465E-825C-99712043E01C"
$GodModePath   = "$env:USERPROFILE\Desktop\GodMode.{$GodModeGUID}"

#endregion

try{
    #region LOGICA PRINCIPAL

    Write-Section "GOD MODE" -LogFile $LogFile
    Write-Blank   -LogFile $LogFile

    $carpetLista = Test-Path $GodModePath

    if ($carpetLista) {
        Write-Log "La carpeta God Mode ya existe en el Escritorio." -Level WARNING -LogFile $LogFile
    } else {
        try {
            New-Item -ItemType Directory -Path $GodModePath -ErrorAction Stop | Out-Null
            Write-Log "God Mode creado exitosamente en el Escritorio." -Level SUCCESS -LogFile $LogFile
            $carpetLista = $true
        } catch {
            Write-Log "Error al crear God Mode: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
            Add-ReportError -Report $script:report -Message "Fallo al crear carpeta God Mode: $($_.Exception.Message)" -Severity ERROR -Source TOOLKIT
        }
    }

    Write-Blank -LogFile $LogFile
    if($carpetLista){
        Write-Log "Abriendo God Mode..." -LogFile $LogFile
        Start-Process explorer.exe -ArgumentList "`"$GodModePath`""
    }

    #endregion

    $status = if (@($script:report.errors | Where-Object { $_.severity -eq "ERROR" }).Count -gt 0) { "ERROR" } else { "OK" }
    $script:report = Complete-ModuleReport -Report $script:report -Status $status

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
Write-Log "Log guardado en: $LogFile" -Level INFO -LogFile $LogFile
Write-Blank

Invoke-Pause

#endregion