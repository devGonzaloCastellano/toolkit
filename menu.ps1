<#
.SYNOPSIS
    Menu principal de la Portable Windows Toolkit.
.DESCRIPTION
    Entry point del sistema. Configura el entorno visual, importa utilidades
    compartidas y presenta el menu de navegacion principal desde el que se
    invocan todos los modulos disponibles.
.NOTES
    Version : 3.0.0
    Proyecto: Portable Windows Toolkit
#>

#region PARAMETROS

param(
    [string]$LogDir    = "$PSScriptRoot\logs",
    [switch]$NoElevation
)

#endregion

#region IMPORTS

. "$PSScriptRoot\lib\Utils.ps1"

#endregion

#region CANCELACION GLOBAL

Register-CancelHandler

#endregion

#region AUTO-ELEVACION

if (-not $NoElevation) {
    Invoke-Elevate -ScriptPath $PSCommandPath -Parameters $PSBoundParameters
}

#endregion

#region CONFIGURACION VISUAL

$Host.UI.RawUI.BackgroundColor = "Black"
$Host.UI.RawUI.ForegroundColor = "White"
Clear-Host

#endregion

#region CONSTANTES

$VERSION     = "3.0.0"
$SCRIPTS_DIR = Join-Path $PSScriptRoot "scripts"

#endregion

#region FUNCIONES DE MENU

function Show-Header {
    Clear-Host
    Write-Host ""
    Write-Host "  ==================================================" -ForegroundColor Cyan
    Write-Host "      PORTABLE WINDOWS TOOLKIT  v$VERSION"            -ForegroundColor White
    Write-Host "  ==================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Show-Menu {
    Show-Header

    Write-Host "   -- DIAGNOSTICO --"                -ForegroundColor DarkCyan
    Write-Host "    [1]  Informacion del sistema"
    Write-Host "    [2]  Estado del disco"
    Write-Host "    [3]  Procesos en ejecucion"
    Write-Host ""

    Write-Host "   -- LIMPIEZA Y OPTIMIZACION --"    -ForegroundColor DarkCyan
    Write-Host "    [4]  Limpieza de sistema"
    Write-Host "    [5]  Servicios innecesarios"
    Write-Host "    [6]  Programas al inicio"
    Write-Host ""

    Write-Host "   -- REPARACION --"                 -ForegroundColor DarkCyan
    Write-Host "    [7]  Reparar archivos del sistema"
    Write-Host "    [8]  Reparar red"
    Write-Host "    [9]  Reparar Windows Update"
    Write-Host ""

    Write-Host "   -- SEGURIDAD --"                  -ForegroundColor DarkCyan
    Write-Host "   [10]  Puertos y conexiones activas"
    Write-Host "   [11]  Usuarios del sistema"
    Write-Host "   [12]  Actualizar Windows Defender"
    Write-Host ""

    Write-Host "   -- UTILIDADES --"                 -ForegroundColor DarkCyan
    Write-Host "   [13]  Activar God Mode"
    Write-Host "   [14]  Mapa de red local"
    Write-Host "   [15]  Reinicio y apagado"
    Write-Host ""

    Write-Host "  ==================================================" -ForegroundColor Cyan
    Write-Host "    [0]  Salir"
    Write-Host "  ==================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Invoke-Module {
    param(
        [Parameter(Mandatory)]
        [string]$ModuleFile
    )

    $modulePath = Join-Path $SCRIPTS_DIR $ModuleFile

    if (-not (Test-Path $modulePath)) {
        Write-Log "Modulo no encontrado: $ModuleFile" -Level ERROR
        Invoke-Pause
        return
    }

    & $modulePath -LogDir $LogDir -NoElevation
}

#endregion

#region TABLA DE MODULOS

$ModuleMap = @{
    "1"  = "info_sistema.ps1"
    "2"  = "reporte_disco.ps1"
    "3"  = "procesos.ps1"
    "4"  = "limpieza.ps1"
    "5"  = "servicios.ps1"
    "6"  = "startup.ps1"
    "7"  = "reparar_sistema.ps1"
    "8"  = "reparar_red.ps1"
    "9"  = "reparar_windows_update.ps1"
    "10" = "puertos.ps1"
    "11" = "usuarios.ps1"
    "12" = "defender.ps1"
    "13" = "godmode.ps1"
    "14" = "mapa_red.ps1"
    "15" = "reinicio.ps1"
}

#endregion

#region LOOP PRINCIPAL

do {
    Show-Menu
    $opcion = Read-Host "   Elegir opcion"

    if ($opcion -eq "0") { break }

    if ($ModuleMap.ContainsKey($opcion)) {
        Invoke-Module -ModuleFile $ModuleMap[$opcion]
    } else {
        Write-Host ""
        Write-Host "  Opcion invalida. Intentalo de nuevo." -ForegroundColor Yellow
        Start-Sleep -Seconds 1
    }

} while ($true)

#endregion

#region SALIDA

Clear-Host
Write-Host ""
Write-Host "  Hasta luego." -ForegroundColor Cyan
Write-Host ""

#endregion