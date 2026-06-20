<#
.SYNOPSIS
    Modulo de reparacion de archivos del sistema Windows.
.DESCRIPTION
    Ejecuta SFC (System File Checker) y DISM (Deployment Image Servicing)
    en secuencia para detectar y reparar archivos del sistema corruptos.
    SFC verifica la integridad de archivos locales.
    DISM repara la imagen de Windows descargando componentes desde Microsoft.
    Nota: SFC y DISM muestran su progreso directamente en consola en tiempo
    real. El detalle completo queda en sus logs nativos de Windows.
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

$envInfo = Initialize-Environment -LogDir $LogDir -ModuleName "reparar_sistema"
$LogFile = $envInfo.LogFile

#endregion

#region VERIFICACION DE DEPENDENCIAS

Write-Section "VERIFICACION DE DEPENDENCIAS" -LogFile $LogFile

Write-Blank -LogFile $LogFile
if (-not (Test-InternetConnection)) {
    Write-Log "Sin conexion a internet. Este modulo requiere conexion activa." -Level ERROR -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Invoke-Pause exit 1 }
Write-Log "Conexion a internet verificada." -Level SUCCESS -LogFile $LogFile
Write-Blank -LogFile $LogFile

# endregion

#region LOGICA PRINCIPAL

Write-Section "REPARACION DEL SISTEMA" -LogFile $LogFile
Write-Blank -LogFile $LogFile

# -- Paso 1: SFC --
Write-Section "PASO 1/2 - SFC" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "Verifica y repara archivos del sistema Windows." -Level NOTE -LogFile $LogFile
Write-Log "Puede tardar entre 5 y 15 minutos. No cerrar esta ventana." -Level WARNING -LogFile $LogFile
Write-Blank -LogFile $LogFile

# SFC y DISM escriben en UTF-16LE - capturar su output con 2>&1 genera
# caracteres erraticos. Se ejecutan sin redireccion para que muestren
# su progreso nativo en consola en tiempo real.
# El detalle completo queda en: C:\Windows\Logs\CBS\CBS.log

$sfcExit = 0
try {
    $inicio  = Get-Date
    sfc /scannow
    $sfcExit = $LASTEXITCODE
    $duracion = [math]::Round(((Get-Date) - $inicio).TotalMinutes, 1)

    Write-Blank -LogFile $LogFile

    switch ($sfcExit) {
        0 {
            Write-Log "SFC completado en $duracion min: Sin errores detectados." -Level SUCCESS -LogFile $LogFile
        }
        1 {
            Write-Log "SFC completado en $duracion min: Se encontraron y repararon errores." -Level WARNING -LogFile $LogFile
            Write-Log "Detalle: C:\Windows\Logs\CBS\CBS.log" -LogFile $LogFile
        }
        default {
            Write-Log "SFC completado en $duracion min: Codigo $sfcExit - revisar log." -Level ERROR -LogFile $LogFile
            Write-Log "Detalle: C:\Windows\Logs\CBS\CBS.log" -LogFile $LogFile
        }
    }
} catch {
    Write-Log "Error al ejecutar SFC: $_" -Level ERROR -LogFile $LogFile
    $sfcExit = -1
}

Write-Blank -LogFile $LogFile

# -- Paso 2: DISM --
Write-Section "PASO 2/2 - DISM" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "Repara la imagen de Windows descargando componentes desde Microsoft." -Level NOTE -LogFile $LogFile
Write-Log "Puede tardar entre 10 y 20 minutos. No cerrar esta ventana" -Level WARNING -LogFile $LogFile
Write-Blank -LogFile $LogFile

# El detalle completo queda en: C:\Windows\Logs\DISM\dism.log

$dismExit = 0
try {
    $inicio   = Get-Date
    DISM /Online /Cleanup-Image /RestoreHealth
    $dismExit = $LASTEXITCODE
    $duracion = [math]::Round(((Get-Date) - $inicio).TotalMinutes, 1)

    Write-Blank -LogFile $LogFile

    if ($dismExit -eq 0) {
        Write-Log "DISM completado en $duracion min: Imagen reparada correctamente." -Level SUCCESS -LogFile $LogFile
    } else {
        Write-Log "DISM completado en $duracion min: Codigo $dismExit - revisar log." -Level ERROR -LogFile $LogFile
        Write-Log "Detalle: C:\Windows\Logs\DISM\dism.log" -LogFile $LogFile
    }
} catch {
    Write-Log "Error al ejecutar DISM: $_" -Level ERROR -LogFile $LogFile
    $dismExit = -1
}

#endregion

#region RESUMEN

Write-Blank -LogFile $LogFile
Write-Section "RESUMEN" -LogFile $LogFile
Write-Blank -LogFile $LogFile

$nivelSFC  = if ($sfcExit  -eq 0) { "SUCCESS" } elseif ($sfcExit  -eq 1) { "WARNING" } else { "ERROR" }
$nivelDISM = if ($dismExit -eq 0) { "SUCCESS" } else { "ERROR" }

Write-Log "SFC  : codigo de salida $sfcExit"  -Level $nivelSFC  -LogFile $LogFile
Write-Log "DISM : codigo de salida $dismExit" -Level $nivelDISM -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "Reiniciar el equipo para que los cambios tomen efecto." -Level WARNING -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "Logs nativos de Windows:" -LogFile $LogFile
Write-Log "  SFC  : C:\Windows\Logs\CBS\CBS.log" -LogFile $LogFile
Write-Log "  DISM : C:\Windows\Logs\DISM\dism.log" -LogFile $LogFile

Write-Blank -LogFile $LogFile
Write-Section -LogFile $LogFile
Write-Log "Log guardado en: $LogFile" -LogFile $LogFile
Write-Blank

Invoke-Pause

#endregion