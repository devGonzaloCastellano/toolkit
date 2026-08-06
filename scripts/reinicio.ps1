<#
.SYNOPSIS
    Modulo de reinicio y apagado del equipo.
.DESCRIPTION
    Ofrece opciones controladas para reiniciar (normal o forzado),
    reiniciar directo a BIOS/UEFI, reiniciar a Opciones de Recuperacion
    de Windows (WinRE), o apagar el equipo. Requiere confirmacion antes
    de ejecutar cualquier accion, dado su caracter disruptivo.
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

$envInfo = Initialize-Environment -LogDir $LogDir -ModuleName "reinicio"
$LogFile = $envInfo.LogFile

Set-CurrentExecution -ModuleName "reinicio" -TxtPath $LogFile

$reportsDir = Join-Path (Split-Path $LogDir -Parent) "reports"
$reportFile = Get-ReportFileName -ReportsDir $reportsDir -ModuleName "reinicio"
$script:report = New-ModuleReport -ModuleName "reinicio"

#endregion

#region FUNCIONES INTERNAS

<#
.SYNOPSIS
    Detecta el tipo de firmware del equipo (UEFI o Legacy BIOS).
.OUTPUTS
    [string] "UEFI" o "Legacy", o "Desconocido" si no se pudo determinar.
#>
function Get-TipoFirmware {
    try {
        $tipo = (Get-ComputerInfo -Property BiosFirmwareType -ErrorAction Stop).BiosFirmwareType
        return $tipo.ToString()
    } catch {
        Write-Log "No se pudo determinar el tipo de firmware: $($_.Exception.Message)" -Level WARNING -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al detectar tipo de firmware: $($_.Exception.Message)" -Severity WARNING -Source TOOLKIT
        return "Desconocido"
    }
}

<#
.SYNOPSIS
    Muestra el submenu de opciones de reinicio/apagado.
.PARAMETER TipoFirmware
    Tipo de firmware detectado, usado para advertir sobre la opcion BIOS/UEFI.
#>
function Show-MenuReinicio {
    param([string]$TipoFirmware)

    Write-Host ""
    Write-Host "   [1] Reiniciar (normal)"
    Write-Host "   [2] Reiniciar (forzado) - usar solo si la opcion 1 dejo el equipo colgado"

    if ($TipoFirmware -eq "Legacy") {
        Write-Host "   [3] Reiniciar a BIOS/UEFI" -ForegroundColor Yellow
        Write-Host "       Firmware Legacy detectado: esta opcion puede no funcionar en este equipo." -ForegroundColor Yellow
    } else {
        Write-Host "   [3] Reiniciar a BIOS/UEFI"
    }

    Write-Host "   [4] Reiniciar a Opciones de Recuperacion (WinRE)"
    Write-Host "   [5] Apagar"
    Write-Host "   [0] Cancelar"
    Write-Host ""
}

<#
.SYNOPSIS
    Pide confirmacion antes de ejecutar una accion disruptiva.
.PARAMETER Accion
    Descripcion de la accion a confirmar.
.OUTPUTS
    [bool] $true si el usuario confirmo con "s".
#>
function Confirm-Accion {
    param([string]$Accion)

    $respuesta = Read-Host "   Confirmar '$Accion'? (s/n)"
    return $respuesta -eq "s"
}

#endregion

try {

    #region LOGICA PRINCIPAL

    Write-Section "REINICIO Y APAGADO" -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    $tipoFirmware = Get-TipoFirmware
    Write-Log "Firmware detectado: $tipoFirmware" -Level NOTE -LogFile $LogFile

    Show-MenuReinicio -TipoFirmware $tipoFirmware

    $opcion = Read-Host "   Elegir opcion"

    $accionEjecutada = $null
    $confirmado       = $false
    $comando          = $null

    switch ($opcion) {
        "1" {
            $accionEjecutada = "Reinicio normal"
            $comando = { shutdown /r /t 0 }
        }
        "2" {
            $accionEjecutada = "Reinicio forzado"
            $comando = { shutdown /r /f /t 0 }
        }
        "3" {
            $accionEjecutada = "Reinicio a BIOS/UEFI"
            $comando = { shutdown /r /fw /t 0 }
        }
        "4" {
            $accionEjecutada = "Reinicio a Opciones de Recuperacion (WinRE)"
            $comando = { shutdown /r /o /t 0 }
        }
        "5" {
            $accionEjecutada = "Apagado"
            $comando = { shutdown /s /t 0 }
        }
        "0" {
            Write-Log "Operacion cancelada por el usuario." -Level NOTE -LogFile $LogFile
        }
        default {
            Write-Log "Opcion invalida." -Level WARNING -LogFile $LogFile
        }
    }

    if ($accionEjecutada -and $comando) {
        Write-Blank -LogFile $LogFile
        $confirmado = Confirm-Accion -Accion $accionEjecutada

        if ($confirmado) {
            Write-Log "Ejecutando: $accionEjecutada" -Level WARNING -LogFile $LogFile

            # El reporte se guarda ANTES de ejecutar el comando, ya que shutdown.exe
            # puede cortar la sesion actual (BIOS/WinRE/apagado) antes de que el
            # script llegue al finally.
            $script:report.data = @{
                firmwareDetectado = $tipoFirmware
                accionSolicitada  = $accionEjecutada
                confirmado        = $true
            }
            $script:report = Complete-ModuleReport -Report $script:report -Status "OK"
            Save-ModuleReport -Report $script:report -ReportFile $reportFile

            try {
                & $comando
            } catch {
                Write-Log "Error al ejecutar el comando: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
            }

            # Si el equipo no se apago/reinicio de inmediato (ej: BIOS no soportado),
            # la ejecucion puede seguir hasta aca.
            exit 0
        } else {
            Write-Log "Accion cancelada por el usuario." -Level NOTE -LogFile $LogFile
        }
    }

    #endregion

    #region REPORTE

    # Solo se llega aca si se cancelo la operacion o la opcion fue invalida
    $script:report.data = @{
        firmwareDetectado = $tipoFirmware
        accionSolicitada  = $accionEjecutada
        confirmado        = $confirmado
    }

    $status = if (@($script:report.errors | Where-Object { $_.severity -eq "ERROR" }).Count -gt 0) { "ERROR" } else { "OK" }
    $script:report = Complete-ModuleReport -Report $script:report -Status $status

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