<#
.SYNOPSIS
    Modulo de limpieza y optimizacion del sistema.
.DESCRIPTION
    Elimina archivos temporales de usuario y sistema, limpia el Prefetch,
    historial de archivos recientes, cache de Windows Update, flush DNS,
    vacia la papelera y ejecuta Disk Cleanup. Muestra conteo de archivos
    eliminados, espacio liberado y duracion del proceso.
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

$envInfo = Initialize-Environment -LogDir $LogDir -ModuleName "limpieza"
$LogFile = $envInfo.LogFile

Set-CurrentExecution -ModuleName "limpieza" -TxtPath $LogFile

$reportsDir = Join-Path (Split-Path $LogDir -Parent) "reports"
$reportFile = Get-ReportFileName -ReportsDir $reportsDir -ModuleName "limpieza"
$script:report = New-ModuleReport -ModuleName "limpieza"

#endregion

#region FUNCIONES INTERNAS

<#
.SYNOPSIS
    Elimina archivos y carpetas de una ruta y retorna el resultado.
.DESCRIPTION
    Los archivos bloqueados por el sistema (en uso) son esperables durante
    la limpieza y no se loggean individualmente: se cuentan como omitidos
    y se reportan de forma agregada, para evitar ruido excesivo en consola.
.PARAMETER Ruta
    Ruta a limpiar.
.OUTPUTS
    [PSCustomObject] con Eliminados y Omitidos.
#>
function Remove-Temporales {
    param([string]$Ruta)

    if (-not (Test-Path $Ruta)) {
        return [PSCustomObject]@{Eliminados = 0; Omitidos = 0} }

    $items = Get-ChildItem -Path $Ruta -Recurse -Force -ErrorAction SilentlyContinue
    $count = 0
    $omitidos = 0

    foreach ($item in $items) {
        try {
            Remove-Item -Path $item.FullName -Force -Recurse -ErrorAction Stop
            $count++
        } catch {
            # Archivo en uso por el sistema - se ignora
            $omitidos++
        }
    }

    return [PSCustomObject]@{Eliminados = $count; Omitidos = $omitidos}
}

#endregion

try{

    #region LOGICA PRINCIPAL

    Write-Section "LIMPIEZA DE SISTEMA" -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    # Capturar espacio libre antes y tiempo de inicio
    $espacioAntes = (Get-PSDrive C).Free
    $inicio = Get-Date
    $totalItems = 0
    $totalOmitidos = 0

    $resultadosPasos = @{}

    # -- Paso 1: Temporales de usuario --
    Write-Log "[1/6] Limpiando temporales de usuario..." -LogFile $LogFile
    $r1 = Remove-Temporales -Ruta $env:TEMP
    $totalItems += $r1.Eliminados
    $totalOmitidos += $r1.Omitidos
    $resultadosPasos.tempUsuario = $r1
    Write-Log "      Items eliminados: $($r1.Eliminados) " -Level SUCCESS -LogFile $LogFile
    if ($r1.Omitidos -gt 0) {
        Write-Log "      Items omitidos (en uso): $($r1.Omitidos)" -Level WARNING -LogFile $LogFile
    }
    Write-Blank -LogFile $LogFile


    # -- Paso 2: Temporales del sistema --
    Write-Log "[2/6] Limpiando temporales del sistema..." -LogFile $LogFile
    $r2 = Remove-Temporales -Ruta "C:\Windows\Temp"
    $totalItems += $r2.Eliminados
    $totalOmitidos += $r2.Omitidos
    $resultadosPasos.tempSistema = $r2
    Write-Log "      Items eliminados: $($r2.Eliminados)" -Level SUCCESS -LogFile $LogFile
    if ($r2.Omitidos -gt 0) {
        Write-Log "      Items omitidos (en uso): $($r2.Omitidos)" -Level WARNING -LogFile $LogFile
    }
    Write-Blank -LogFile $LogFile


    # -- Paso 3: Prefetch (opcional) --
    Write-Log "[3/6] Limpieza de Prefetch..." -LogFile $LogFile
    Write-Log "      El Prefetch acelera el arranque de programas." -Level NOTE -LogFile $LogFile
    Write-Log "      Limpiarlo ralentiza las primeras ejecuciones hasta que se regenere." -Level NOTE -LogFile $LogFile
    Write-Log "      Recomendado solo si el sistema esta muy lento o hay archivos corruptos." -Level WARNING -LogFile $LogFile

    $respuesta = Read-Host "      Limpiar Prefetch? (s/n)"
    $prefetchEjecutado = $false

    if ($respuesta -eq "s")
    {
        $r3 = Remove-Temporales -Ruta "C:\Windows\Prefetch"
        $totalItems    += $r3.Eliminados
        $totalOmitidos += $r3.Omitidos
        $resultadosPasos.prefetch = $r3
        $prefetchEjecutado = $true
        Write-Log "      Items eliminados: $($r3.Eliminados)" -Level SUCCESS -LogFile $LogFile
        if ($r3.Omitidos -gt 0) {
            Write-Log "      Items omitidos (en uso): $($r3.Omitidos)" -Level WARNING -LogFile $LogFile
        }
    }
    else
    {
        Write-Log "      Eliminacion omitida por el usuario." -Level NOTE -LogFile $LogFile
    }
    Write-Blank -LogFile $LogFile


    # -- Paso 4: Archivos recientes --
    Write-Log "[4/6] Limpiando historial de archivos recientes..." -LogFile $LogFile
    $r4 = Remove-Temporales -Ruta "$env:APPDATA\Microsoft\Windows\Recent"
    $totalItems    += $r4.Eliminados
    $totalOmitidos += $r4.Omitidos
    $resultadosPasos.recientes = $r4
    Write-Log "      Items eliminados: $($r4.Eliminados)" -Level SUCCESS -LogFile $LogFile
    if ($r4.Omitidos -gt 0) {
        Write-Log "      Items omitidos (en uso): $($r4.Omitidos)" -Level WARNING -LogFile $LogFile
    }
    Write-Blank -LogFile $LogFile


    # -- Paso 5: Cache de Windows Update --
    Write-Log "[5/6] Limpiando cache de Windows Update..." -LogFile $LogFile
    $r5 = [PSCustomObject]@{ Eliminados = 0; Omitidos = 0 }
    try {
        Stop-Service -Name wuauserv, bits -Force -ErrorAction Stop
        $r5 = Remove-Temporales -Ruta "C:\Windows\SoftwareDistribution\Download"
        $totalItems    += $r5.Eliminados
        $totalOmitidos += $r5.Omitidos
        Start-Service -Name wuauserv, bits -ErrorAction Stop
        Write-Log "      Items eliminados: $($r5.Eliminados)" -Level SUCCESS -LogFile $LogFile
        if ($r5.Omitidos -gt 0) {
            Write-Log "      Items omitidos (en uso): $($r5.Omitidos)" -Level WARNING -LogFile $LogFile
        }} catch {
        Write-Log "      Error al limpiar cache de Windows Update: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al limpiar cache de Windows Update: $($_.Exception.Message)" -Severity ERROR -Source TOOLKIT
    }
    $resultadosPasos.windowsUpdate = $r5
    Write-Blank -LogFile $LogFile


    # -- Paso 6: Flush DNS y papelera --
    Write-Log "[6/6] Flush DNS y vaciando papelera..." -LogFile $LogFile
    $dnsOk = $true
    $papeleraOk = $true
    try {
        Clear-DnsClientCache -ErrorAction Stop
    } catch {
        Write-Log "      Error al limpiar cache DNS: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al limpiar cache DNS: $($_.Exception.Message)" -Severity ERROR -Source TOOLKIT
        $dnsOk = $false
    }
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
    } catch {
        Write-Log "      Error al vaciar la papelera: $($_.Exception.Message)" -Level WARNING -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al vaciar la papelera: $($_.Exception.Message)" -Severity WARNING -Source TOOLKIT
        $papeleraOk = $false
    }
    if ($dnsOk -and $papeleraOk) {
        Write-Log "      OK." -Level SUCCESS -LogFile $LogFile
    }
    Write-Blank -LogFile $LogFile

    #endregion

    #region NOTA DISK CLEANUP

    Write-Section "LIMPIEZA ADICIONAL (MANUAL)" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "Si se necesita una limpieza mas profunda, ejecutar Disk Cleanup manualmente:" -Level NOTE -LogFile $LogFile
    Write-Log "  1. Ejecutar: cleanmgr.exe" -Level NOTE -LogFile $LogFile
    Write-Log "  2. Seleccionar la unidad C:" -Level NOTE -LogFile $LogFile
    Write-Log "  3. Click en 'Limpiar archivos de sistema' para opciones avanzadas" -Level NOTE -LogFile $LogFile
    Write-Log "  4. Tildar las categorias deseadas y confirmar" -Level NOTE -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    #endregion

    #region RESUMEN

    $espacioDespues = (Get-PSDrive C).Free
    $liberadoBytes  = $espacioDespues - $espacioAntes
    if ($liberadoBytes -lt 0) { $liberadoBytes = 0 }
    $liberadoMB     = [math]::Round($liberadoBytes / 1MB, 1)
    $liberadoGB     = [math]::Round($liberadoBytes / 1GB, 2)
    $duracionProceso = [math]::Round(((Get-Date) - $inicio).TotalSeconds, 1)

    $espacioStr = if ($liberadoGB -ge 1) { "$liberadoGB GB" } else { "$liberadoMB MB" }

    Write-Section "RESUMEN" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "Duracion          : $duracionProceso segundos" -LogFile $LogFile
    Write-Log "Items eliminados  : $totalItems"                -LogFile $LogFile
    Write-Log "Items omitidos    : $totalOmitidos (en uso por el sistema)" -LogFile $LogFile
    Write-Log "Espacio liberado  : $espacioStr" -Level SUCCESS -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    #endregion

    #region REPORTE

    $script:report.data = @{
        itemsEliminados = $totalItems
        itemsOmitidos   = $totalOmitidos
        espacioLiberadoMB = $liberadoMB
        prefetchEjecutado = $prefetchEjecutado
        pasos = @{
            tempUsuario   = $resultadosPasos.tempUsuario
            tempSistema   = $resultadosPasos.tempSistema
            prefetch      = $resultadosPasos.prefetch
            recientes     = $resultadosPasos.recientes
            windowsUpdate = $resultadosPasos.windowsUpdate
            dnsOk         = $dnsOk
            papeleraOk    = $papeleraOk
        }
    }

    $status = if (@($script:report.errors | Where-Object { $_.severity -eq "ERROR" }).Count -gt 0) { "ERROR" } else { "OK" }
    $script:report = Complete-ModuleReport -Report $script:report -Status $status

    #endregion

    #region GENERACION HTML

    $nivelResultado = if (@($script:report.errors | Where-Object { $_.severity -eq "ERROR" }).Count -gt 0) { "WARNING" } else { "OK" }

    $contentHtml = @"
    <h2>Resultado de la limpieza</h2>
    <div class="metric"><div class="valor">$totalItems</div><div class="label">Archivos eliminados</div></div>
    <div class="metric"><div class="valor">$espacioStr</div><div class="label">Espacio liberado</div></div>
    <div class="metric"><div class="valor">$totalOmitidos</div><div class="label">En uso (no eliminados)</div></div>

    <p style="font-size:13px; color:#666; margin-top:16px;">
        Los archivos "en uso" corresponden a temporales bloqueados por programas activos
        en el momento de la limpieza. No representan un problema.
    </p>
"@

    $reportFileHtml = Get-ReportFileName -ReportsDir $reportsDir -ModuleName "limpieza" -Extension "html"
    Save-ModuleReportHtml -Report $script:report -ReportFile $reportFileHtml -TituloModulo "Limpieza del Sistema" -ContentHtml $contentHtml -NivelOverride $nivelResultado

    #endregion

}catch{
    Write-Log "Error fatal en el modulo: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
    Add-ReportError -Report $script:report -Message $_.Exception.Message -Severity ERROR -Source TOOLKIT
    $script:report = Complete-ModuleReport -Report $script:report -Status "ERROR"
}finally{
    Save-ModuleReport -Report $script:report -ReportFile $reportFile
}

#region SALIDA

Write-Section -LogFile $LogFile
Write-Log "Log guardado en: $LogFile" -LogFile $LogFile
Write-Blank

Invoke-Pause

#endregion