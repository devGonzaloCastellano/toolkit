<#
.SYNOPSIS
    Modulo de reporte y diagnostico de discos del sistema.
.DESCRIPTION
    Ejecuta chkdsk en modo lectura por cada unidad,
    lista las carpetas mas pesadas en C:\ para identificar consumo de espacio.
    El progreso de chkdsk se muestra en tiempo real.
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

$envInfo = Initialize-Environment -LogDir $LogDir -ModuleName "reporte_disco"
$LogFile = $envInfo.LogFile

Set-CurrentExecution -ModuleName "reporte_disco" -TxtPath $LogFile

$reportsDir = Join-Path (Split-Path $LogDir -Parent) "reports"
$reportFile = Get-ReportFileName -ReportsDir $reportsDir -ModuleName "reporte_disco"
$script:report = New-ModuleReport -ModuleName "reporte_disco"

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
        Write-Log "No se pudieron obtener las particiones: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al obtener particiones: $($_.Exception.Message)" -Severity ERROR -Source TOOLKIT
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
    try{
        Get-PSDrive -PSProvider FileSystem -ErrorAction Stop |
            Where-Object { $_.Used -ne $null } |
            Select-Object -ExpandProperty Name
    }catch{
        Write-Log "No se pudieron obtener las unidades logicas: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al obtener unidades logicas: $($_.Exception.Message)" -Severity ERROR -Source TOOLKIT
        return @()
    }
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
        Write-Log "No se pudo calcular el tamanio de $($Carpeta.Name): $($_.Exception.Message)" -Level WARNING -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al calcular tamanio de $($Carpeta.Name): $($_.Exception.Message)" -Severity WARNING -Source TOOLKIT
        return 0
    }
}

#endregion

try{

    #region RECOLECCION DE DATOS

    $particiones   = Get-Particiones
    $unidades      = Get-UnidadesLogicas
    $currentDrive = (Get-Item $PSScriptRoot).PSDrive.Name

    #endregion

    #region PRESENTACION

    Write-Section "REPORTE DE DISCO" -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    #endregion

    #region VERIFICACION

    Write-Section "VERIFICACION DE ERRORES - CHKDSK" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "Modo lectura: no modifica nada, solo reporta." -Level NOTE -LogFile $LogFile
    Write-Log "El progreso se muestra en tiempo real por cada unidad." -Level NOTE -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    $resultadosChkdsk = @()
    foreach ($unidad in $unidades) {

        if($unidad -eq $currentDrive){
            Write-Log "--- Unidad $unidad : ---" -Level NOTE -LogFile $LogFile
            Write-Log "Es la unidad de origen del toolkit, se omite el chequeo para evitar falso positivo." -Level NOTE -LogFile $LogFile
            Write-Blank -LogFile $LogFile

            $resultadosChkdsk += [PSCustomObject]@{
                Unidad       = $unidad
                CodigoSalida = $null
                Estado       = "OMITIDA"
                DuracionMin  = 0
            }
            continue
        }

        Write-Log "--- Verificando unidad $unidad : ---" -Level NOTE -LogFile $LogFile
        Write-Blank -LogFile $LogFile

        $inicio   = Get-Date

        try{
            chkdsk "$unidad`:" /scan
            $chkExit  = $LASTEXITCODE
        } catch {
            Write-Log "Error al ejecutar chkdsk en $unidad`: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
            Add-ReportError -Report $script:report -Message "Fallo al ejecutar chkdsk en $unidad`: $($_.Exception.Message)" -Severity ERROR -Source TOOLKIT
            $chkExit = -1
        }

        $duracion = [math]::Round(((Get-Date) - $inicio).TotalMinutes, 2)
        Write-Blank -LogFile $LogFile

        $estadoTexto = switch ($chkExit) {
            0 {
                Write-Log "Unidad $unidad : Sin errores detectados. ($duracion min)" -Level SUCCESS -LogFile $LogFile
                "SIN_ERRORES"
            }
            1 {
                Write-Log "Unidad $unidad : Se encontraron errores menores. ($duracion min)" -Level WARNING -LogFile $LogFile
                Write-Log "  Sugerido: chkdsk $unidad`: /scan /forceofflinefix" -LogFile $LogFile
                Add-ReportError -Report $script:report -Message "Unidad $unidad con errores menores (chkdsk)" -Severity WARNING -Source SYSTEM
                "ERRORES_MENORES"
            }
            -1 {
                "FALLO_EJECUCION"
            }
            default {
                Write-Log "Unidad $unidad : Codigo $chkExit - posible falso positivo si la unidad esta en uso. ($duracion min)" -Level WARNING -LogFile $LogFile
                Write-Log "  Sugerido: chkdsk $unidad`: /scan /forceofflinefix" -LogFile $LogFile
                Add-ReportError -Report $script:report -Message "Unidad $unidad con codigo $chkExit (posible falso positivo)" -Severity WARNING -Source SYSTEM
                "CODIGO_$chkExit"
            }
        }

        $resultadosChkdsk += [PSCustomObject]@{
            Unidad       = $unidad
            CodigoSalida = $chkExit
            Estado       = $estadoTexto
            DuracionMin  = $duracion
        }
        Write-Blank -LogFile $LogFile
    }

    #endregion

    #region CARPETAS PESADAS
    Write-Section "CARPETAS MAS PESADAS EN C:\" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "Calculando volumen de carpetas... esto puede tardar unos segundos." -Level NOTE -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    $resultadosCarpetas = @()

    try{
        $carpetasC = Get-ChildItem -Path "C:\" -Directory -ErrorAction Stop

        # Calcular volumen mostrando progreso en tiempo real
        $resultadosCarpetas = @(foreach ($carpeta in $carpetasC) {
            Write-Host "  Calculando: $($carpeta.Name)..." -ForegroundColor DarkGray -NoNewline
            $bytes = Get-TamanoCarpeta -Carpeta $carpeta
            $gb    = [math]::Round($bytes / 1GB, 2)
            Write-Host " $gb GB" -ForegroundColor DarkGray
            [PSCustomObject]@{ Nombre = $carpeta.Name; GB = $gb; Bytes = $bytes }
        })

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

    }catch{
        Write-Log "No se pudo listar el contenido de C:\: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al listar carpetas de C:\: $($_.Exception.Message)" -Severity ERROR -Source TOOLKIT
    }
    Write-Blank -LogFile $LogFile
    #endregion

    #region REPORTE

    $script:report.data = @{
        particiones      = $particiones
        chkdskResultados = $resultadosChkdsk
        carpetasPesadas  = @($resultadosCarpetas | Sort-Object Bytes -Descending | Select-Object -First 10 -Property Nombre, GB)
    }

    $status = if (@($script:report.errors | Where-Object { $_.severity -eq "ERROR" }).Count -gt 0) { "ERROR" } else { "OK" }
    $script:report = Complete-ModuleReport -Report $script:report -Status $status

    #endregion

    #region GENERACION HTML

    $chkdskCliente     = @($resultadosChkdsk | Where-Object { $_.Estado -ne "OMITIDA" })
    $particionesCliente = @($particiones | Where-Object { $_.Unidad.TrimEnd(':') -ne $currentDrive })

    $unidadesConProblema = @($chkdskCliente | Where-Object { $_.Estado -ne "SIN_ERRORES" })
    $particionesLlenas    = @($particionesCliente | Where-Object {
        $usadoGB = $_.TotalGB - $_.LibreGB
        $pctUso = if ($_.TotalGB -gt 0) { ($usadoGB / $_.TotalGB) * 100 } else { 0 }
        $pctUso -ge 90
    })

    $totalUnidades = @($chkdskCliente).Count
    $penalizacion = (@($unidadesConProblema).Count * 15) + (@($particionesLlenas).Count * 10)
    $healthScore = 100 - $penalizacion
    if ($healthScore -lt 0) { $healthScore = 0 }

    $script:report.healthScore = $healthScore

    $nivelResultado = if (@($unidadesConProblema).Count -gt 0) { "ERROR" }
    elseif (@($particionesLlenas).Count -gt 0) { "WARNING" }
    else { "OK" }

    $filasChkdsk = ""
    foreach ($r in $chkdskCliente) {
        $nivel = if ($r.Estado -eq "SIN_ERRORES") { "OK" } else { "ERROR" }
        $texto = if ($r.Estado -eq "SIN_ERRORES") { "Sin errores" } else { "Requiere revision" }
        $filasChkdsk += "<tr><td>Unidad $($r.Unidad)</td><td>$(New-HtmlBadge -Texto $texto -Nivel $nivel)</td></tr>`n"
    }

    $filasParticiones = ""
    foreach ($p in $particionesCliente) {
        $usadoGB = [math]::Round($p.TotalGB - $p.LibreGB, 1)
        $pctUso  = if ($p.TotalGB -gt 0) { [math]::Round(($usadoGB / $p.TotalGB) * 100) } else { 0 }
        $nivel   = if ($pctUso -ge 90) { "ERROR" } elseif ($pctUso -ge 75) { "WARNING" } else { "OK" }
        $filasParticiones += "<tr><td>Unidad $($p.Unidad)</td><td>$($p.LibreGB) GB libres de $($p.TotalGB) GB</td><td>$(New-HtmlBadge -Texto "$pctUso% usado" -Nivel $nivel)</td></tr>`n"
    }

    $contentHtml = @"
    <h2>Resumen</h2>
    <div class="metric"><div class="valor">$healthScore%</div><div class="label">Salud del disco</div></div>
    <div class="metric"><div class="valor">$totalUnidades</div><div class="label">Unidades evaluadas</div></div>

    <h2>Estado de las unidades</h2>
    <table>
        <tr><th>Unidad</th><th>Estado</th></tr>
        $filasChkdsk
    </table>

    <h2>Espacio disponible</h2>
    <table>
        <tr><th>Unidad</th><th>Espacio</th><th>Uso</th></tr>
        $filasParticiones
    </table>
"@

    $reportFileHtml = Get-ReportFileName -ReportsDir $reportsDir -ModuleName "reporte_disco" -Extension "html"
    Save-ModuleReportHtml -Report $script:report -ReportFile $reportFileHtml -TituloModulo "Estado del Disco" -ContentHtml $contentHtml -NivelOverride $nivelResultado

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