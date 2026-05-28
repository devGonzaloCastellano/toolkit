<#
.SYNOPSIS
    Modulo de activacion de God Mode en el Escritorio.
.DESCRIPTION
    Crea una carpeta especial en el Escritorio del usuario con acceso
    directo a todos los paneles de configuracion de Windows en un solo lugar.
    Si la carpeta ya existe, la abre directamente sin recrearla.
.NOTES
    Version : 2.0.0
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

$envInfo = Initialize-Environment -LogDir $LogDir -ModuleName "godmode"
$LogFile = $envInfo.LogFile

#endregion

#region VARIABLES

# GUID oficial de God Mode - no cambiar
$GodModeGUID   = "ED7BA470-8E54-465E-825C-99712043E01C"
$GodModePath   = "$env:USERPROFILE\Desktop\GodMode.{$GodModeGUID}"

#endregion

#region LOGICA PRINCIPAL

Write-Section "GOD MODE" -LogFile $LogFile
Write-Blank   -LogFile $LogFile

if (Test-Path $GodModePath) {
    Write-Log "La carpeta God Mode ya existe en el Escritorio." -Level WARNING -LogFile $LogFile
} else {
    try {
        New-Item -ItemType Directory -Path $GodModePath -ErrorAction Stop | Out-Null
        Write-Log "God Mode creado exitosamente en el Escritorio." -Level SUCCESS -LogFile $LogFile
    } catch {
        Write-Log "Error al crear God Mode: $_" -Level ERROR -LogFile $LogFile
        Invoke-Pause
        return
    }
}

Write-Blank -LogFile $LogFile
Write-Log "Abriendo God Mode..." -LogFile $LogFile

Start-Process explorer.exe -ArgumentList "`"$GodModePath`""

#endregion

#region RESUMEN

Write-Blank -LogFile $LogFile
Write-Section -LogFile $LogFile
Write-Log "Log guardado en: $LogFile" -Level INFO
Write-Blank

Invoke-Pause

#endregion