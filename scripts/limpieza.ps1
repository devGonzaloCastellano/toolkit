<#
.SYNOPSIS
    Modulo de limpieza y optimizacion del sistema.
.DESCRIPTION
    Elimina archivos temporales de usuario y sistema, limpia el Prefetch,
    historial de archivos recientes, cache de Windows Update, flush DNS,
    vacia la papelera y ejecuta Disk Cleanup. Muestra conteo de archivos
    eliminados, espacio liberado y duracion del proceso.
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

$envInfo = Initialize-Environment -LogDir $LogDir -ModuleName "limpieza"
$LogFile = $envInfo.LogFile

#endregion

#region FUNCIONES INTERNAS

<#
.SYNOPSIS
    Elimina archivos y carpetas de una ruta y retorna el conteo eliminado.
.PARAMETER Ruta
    Ruta a limpiar.
.OUTPUTS
    Int con la cantidad de items eliminados.
#>
function Remove-Temporales {
    param([string]$Ruta)

    if (-not (Test-Path $Ruta)) { return 0 }

    $items = Get-ChildItem -Path $Ruta -Recurse -Force -ErrorAction SilentlyContinue
    $count = 0

    foreach ($item in $items) {
        try {
            Remove-Item -Path $item.FullName -Force -Recurse -ErrorAction Stop
            $count++
        } catch {
            # Archivo en uso por el sistema - se ignora
        }
    }

    return $count
}

#endregion

#region LOGICA PRINCIPAL

Write-Section "LIMPIEZA DE SISTEMA" -LogFile $LogFile
Write-Blank -LogFile $LogFile

# Capturar espacio libre antes y tiempo de inicio
$espacioAntes = (Get-PSDrive C).Free
$inicio       = Get-Date
$totalItems   = 0

# -- Paso 1: Temporales de usuario --
Write-Log "[1/7] Limpiando temporales de usuario..." -LogFile $LogFile
$tempUser = $env:TEMP
$count    = Remove-Temporales -Ruta $tempUser
$totalItems += $count
Write-Log "      OK. Items eliminados: $count" -Level SUCCESS -LogFile $LogFile
Write-Blank -LogFile $LogFile


# -- Paso 2: Temporales del sistema --
Write-Log "[2/7] Limpiando temporales del sistema..." -LogFile $LogFile
$count = Remove-Temporales -Ruta "C:\Windows\Temp"
$totalItems += $count
Write-Log "      OK. Items eliminados: $count" -Level SUCCESS -LogFile $LogFile
Write-Blank -LogFile $LogFile


# -- Paso 3: Prefetch (opcional) --
Write-Log "[3/7] Limpieza de Prefetch..." -LogFile $LogFile
Write-Log "      El Prefetch acelera el arranque de programas." -Level NOTE -LogFile $LogFile
Write-Log "      Limpiarlo ralentiza las primeras ejecuciones hasta que se regenere." -Level NOTE -LogFile $LogFile
Write-Log "      Recomendado solo si el sistema esta muy lento o hay archivos corruptos." -Level WARNING -LogFile $LogFile

$respuesta = Read-Host "      Limpiar Prefetch? (s/n)"
if ($respuesta -eq "s") {
    $count = Remove-Temporales -Ruta "C:\Windows\Prefetch"
    $totalItems += $count
    Write-Log "      OK. Items eliminados: $count" -Level SUCCESS -LogFile $LogFile
} else {
    Write-Log "      Omitido." -LogFile $LogFile
}
Write-Blank -LogFile $LogFile


# -- Paso 4: Archivos recientes --
Write-Log "[4/7] Limpiando historial de archivos recientes..." -LogFile $LogFile
$count = Remove-Temporales -Ruta "$env:APPDATA\Microsoft\Windows\Recent"
$totalItems += $count
Write-Log "      OK. Items eliminados: $count" -Level SUCCESS -LogFile $LogFile
Write-Blank -LogFile $LogFile


# -- Paso 5: Cache de Windows Update --
Write-Log "[5/7] Limpiando cache de Windows Update..." -LogFile $LogFile
try {
    Stop-Service -Name wuauserv, bits -Force -ErrorAction SilentlyContinue
    $count = Remove-Temporales -Ruta "C:\Windows\SoftwareDistribution\Download"
    $totalItems += $count
    Start-Service -Name wuauserv, bits -ErrorAction SilentlyContinue
    Write-Log "      OK. Items eliminados: $count" -Level SUCCESS -LogFile $LogFile
} catch {
    Write-Log "      Error al limpiar cache de Windows Update: $_" -Level ERROR -LogFile $LogFile
}
Write-Blank -LogFile $LogFile


# -- Paso 6: Flush DNS y papelera --
Write-Log "[6/7] Flush DNS y vaciando papelera..." -LogFile $LogFile
try {
    Clear-DnsClientCache -ErrorAction Stop
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Write-Log "      OK." -Level SUCCESS -LogFile $LogFile
} catch {
    Write-Log "      Error: $_" -Level ERROR -LogFile $LogFile
}
Write-Blank -LogFile $LogFile


# -- Paso 7: Disk Cleanup --
Write-Log "[7/7] Ejecutando Disk Cleanup..." -LogFile $LogFile
try {
    $regBase = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
    $categorias = @(
        "Temporary Files",
        "Thumbnail Cache",
        "Recycle Bin",
        "Internet Cache Files",
        "Delivery Optimization Files",
        "Windows Error Reporting Files"
    )
    foreach ($cat in $categorias) {
        $regPath = Join-Path $regBase $cat
        if (Test-Path $regPath) {
            Set-ItemProperty -Path $regPath -Name "StateFlags0002" -Value 2 -Type DWord -ErrorAction SilentlyContinue
        }
    }
    Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:2" -WindowStyle Hidden
    Write-Log "      OK. Disk Cleanup ejecutandose en segundo plano." -Level SUCCESS -LogFile $LogFile
} catch {
    Write-Log "      Error al ejecutar Disk Cleanup: $_" -Level ERROR -LogFile $LogFile
}
Write-Blank -LogFile $LogFile


#endregion

#region RESUMEN

$espacioDespues = (Get-PSDrive C).Free
$liberadoBytes  = $espacioDespues - $espacioAntes
if ($liberadoBytes -lt 0) { $liberadoBytes = 0 }
$liberadoMB     = [math]::Round($liberadoBytes / 1MB, 1)
$liberadoGB     = [math]::Round($liberadoBytes / 1GB, 2)
$duracion       = [math]::Round(((Get-Date) - $inicio).TotalSeconds, 1)

$espacioStr = if ($liberadoGB -ge 1) { "$liberadoGB GB" } else { "$liberadoMB MB" }

Write-Blank -LogFile $LogFile
Write-Section "RESUMEN" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "Duracion          : $duracion segundos"                         -LogFile $LogFile
Write-Log "Items eliminados  : $totalItems"                                -LogFile $LogFile
Write-Log "Espacio liberado  : $espacioStr"                                -Level SUCCESS -LogFile $LogFile
Write-Log "(No incluye Disk Cleanup que corre en segundo plano)"           -Level NOTE -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "Nota: Disk Cleanup puede seguir corriendo en segundo plano." -Level WARNING -LogFile $LogFile

Write-Blank -LogFile $LogFile
Write-Section -LogFile $LogFile
Write-Log "Log guardado en: $LogFile" -LogFile $LogFile
Write-Blank

Invoke-Pause

#endregion