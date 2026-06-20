<#
.SYNOPSIS
    Modulo de reporte y diagnostico de discos del sistema.
.DESCRIPTION
    Ejecuta chkdsk en modo lectura por cada unidad,
    lista las carpetas mas pesadas en C:\ para identificar consumo de espacio.
    El progreso de chkdsk se muestra en tiempo real.
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

$envInfo = Initialize-Environment -LogDir $LogDir -ModuleName "reporte_disco"
$LogFile = $envInfo.LogFile

#endregion

#region FUNCIONES INTERNAS

<#
.SYNOPSIS
    Obtiene particiones logicas agrupadas por disco fisico.
.OUTPUTS
    Array de PSCustomObject con DiscoId, Unidad, TotalGB y LibreGB.
#>
function Get-Particiones {
    try {
        $particiones = Get-WmiObject Win32_DiskPartition -ErrorAction Stop
        $resultados  = @()

        foreach ($part in $particiones) {
            $logicos = Get-WmiObject -Query `
                "ASSOCIATORS OF {Win32_DiskPartition.DeviceID='$($part.DeviceID)'} WHERE AssocClass=Win32_LogicalDiskToPartition" `
                -ErrorAction SilentlyContinue

            foreach ($l in $logicos) {
                $resultados += [PSCustomObject]@{
                    DiscoId = $part.DiskIndex
                    Unidad  = $l.DeviceID
                    TotalGB = [math]::Round($l.Size     / 1GB, 1)
                    LibreGB = [math]::Round($l.FreeSpace / 1GB, 1)
                }
            }
        }
        return $resultados
    } catch {
        return @()
    }
}

<#
.SYNOPSIS
    Obtiene las unidades logicas disponibles en el sistema.
.OUTPUTS
    Array de strings con letras de unidad (ej: "C", "D").
#>
function Get-UnidadesLogicas {
    Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
            Where-Object { $_.Used -ne $null } |
            Select-Object -ExpandProperty Name
}

<#
.SYNOPSIS
    Calcula el tamanio de una carpeta mostrando progreso en tiempo real.
.PARAMETER Carpeta
    DirectoryInfo de la carpeta a medir.
.OUTPUTS
    Long con el tamanio en bytes.
#>
function Get-TamanoCarpeta {
    param([System.IO.DirectoryInfo]$Carpeta)

    try {
        (Get-ChildItem -Path $Carpeta.FullName -Recurse -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    } catch {
        return 0
    }
}

#endregion

#region RECOLECCION DE DATOS
$particiones   = Get-Particiones
$unidades      = Get-UnidadesLogicas

#endregion

#region PRESENTACION

Write-Section "REPORTE DE DISCO" -LogFile $LogFile
Write-Blank -LogFile $LogFile

# -- Seccion 1: Verificacion chkdsk --
Write-Section "VERIFICACION DE ERRORES - CHKDSK" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "Modo lectura: no modifica nada, solo reporta." -Level NOTE -LogFile $LogFile
Write-Log "El progreso se muestra en tiempo real por cada unidad." -Level NOTE -LogFile $LogFile
Write-Blank -LogFile $LogFile

# chkdsk escribe en UTF-16 - se ejecuta sin captura igual que SFC/DISM
# para mostrar progreso nativo y evitar output erratico
foreach ($unidad in $unidades) {
    Write-Log "--- Verificando unidad $unidad : ---" -Level NOTE -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    $inicio   = Get-Date
    chkdsk "$unidad`:" /scan
    $chkExit  = $LASTEXITCODE
    $duracion = [math]::Round(((Get-Date) - $inicio).TotalMinutes, 2)

    Write-Blank -LogFile $LogFile

    switch ($chkExit) {
        0 {
            Write-Log "Unidad $unidad : Sin errores detectados. ($duracion min)" -Level SUCCESS -LogFile $LogFile
        }
        1 {
            Write-Log "Unidad $unidad : Se encontraron errores menores. ($duracion min)" -Level WARNING -LogFile $LogFile
            Write-Log "  Sugerido: chkdsk $unidad`: /scan /forceofflinefix" -LogFile $LogFile
        }
        default {
            Write-Log "Unidad $unidad : Codigo $chkExit - posible falso positivo si la unidad esta en uso. ($duracion min)" -Level WARNING -LogFile $LogFile
            Write-Log "  Sugerido: chkdsk $unidad`: /scan /forceofflinefix" -LogFile $LogFile
        }
    }
    Write-Blank -LogFile $LogFile
}

# -- Seccion 2: Carpetas mas pesadas en C:\ --
Write-Section "CARPETAS MAS PESADAS EN C:\" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "Calculando volumen de carpetas... esto puede tardar unos segundos." -Level NOTE -LogFile $LogFile
Write-Blank -LogFile $LogFile

$carpetasC = Get-ChildItem -Path "C:\" -Directory -ErrorAction SilentlyContinue

# Calcular tamanio mostrando progreso en tiempo real
$resultadosCarpetas = foreach ($carpeta in $carpetasC) {
    Write-Host "  Calculando: $($carpeta.Name)..." -ForegroundColor DarkGray -NoNewline
    $bytes = Get-TamanoCarpeta -Carpeta $carpeta
    $gb    = [math]::Round($bytes / 1GB, 2)
    Write-Host " $gb GB" -ForegroundColor DarkGray
    [PSCustomObject]@{ Nombre = $carpeta.Name; GB = $gb; Bytes = $bytes }
}

# Mostrar top 10 ordenado
Write-Blank -LogFile $LogFile
Write-Log "Top 10 por volumen:" -LogFile $LogFile
Write-Blank -LogFile $LogFile

$resultadosCarpetas |
        Sort-Object Bytes -Descending |
        Select-Object -First 10 |
        ForEach-Object {
            $linea = "  {0,-25} {1,8} GB" -f $_.Nombre, $_.GB
            Write-Log $linea -LogFile $LogFile
        }

Write-Blank -LogFile $LogFile

#endregion

#region RESUMEN

Write-Section -LogFile $LogFile
Write-Log "Log guardado en: $LogFile" -LogFile $LogFile
Write-Blank

Invoke-Pause

#endregion