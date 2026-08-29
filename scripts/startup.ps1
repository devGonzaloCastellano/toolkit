<#
.SYNOPSIS
    Modulo de auditoria de programas al inicio de Windows.
.DESCRIPTION
    Muestra todos los programas y tareas configurados para ejecutarse
    al iniciar Windows, consultando el registro del sistema, las carpetas
    de inicio del usuario y del sistema, y el Programador de Tareas.
    No desactiva ni modifica nada, solo reporta para auditoria.
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

$envInfo = Initialize-Environment -LogDir $LogDir -ModuleName "startup"
$LogFile = $envInfo.LogFile

Set-CurrentExecution -ModuleName "startup" -TxtPath $LogFile

$reportsDir = Join-Path (Split-Path $LogDir -Parent) "reports"
$reportFile = Get-ReportFileName -ReportsDir $reportsDir -ModuleName "startup"
$script:report = New-ModuleReport -ModuleName "startup"

#endregion

#region FUNCIONES INTERNAS

<#
.SYNOPSIS
    Obtiene las entradas de inicio desde una clave del registro.
.PARAMETER RegistryPath
    Ruta completa a la clave del registro (HKCU o HKLM).
.OUTPUTS
    Array de PSCustomObject con Nombre y Comando.
#>
function Get-RegistryStartup {
    param([string]$RegistryPath)

    try {
        $props = Get-ItemProperty -Path $RegistryPath -ErrorAction Stop
        $props.PSObject.Properties |
                Where-Object { $_.Name -notmatch '^PS' } |
                ForEach-Object {
                    [PSCustomObject]@{
                        Nombre  = $_.Name
                        Comando = $_.Value
                    }
                }
    } catch {
        Write-Log "No se pudo leer el registro ($RegistryPath): $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al leer $RegistryPath : $($_.Exception.Message)" -Severity ERROR -Source TOOLKIT
        return @()
    }
}

<#
.SYNOPSIS
    Obtiene los archivos presentes en una carpeta de inicio.
.PARAMETER FolderPath
    Ruta a la carpeta de inicio (usuario o sistema).
.OUTPUTS
    Array de PSCustomObject con Nombre y Comando.
#>
function Get-FolderStartup {
    param([string]$FolderPath)

    if (-not (Test-Path $FolderPath)) { return @() }

    try{
        Get-ChildItem -Path $FolderPath -ErrorAction SilentlyContinue |
                ForEach-Object {
                    [PSCustomObject]@{
                        Nombre  = $_.Name
                        Comando = $_.FullName
                    }
                }
    }catch{
        Write-Log "No se pudo leer la carpeta ($FolderPath): $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al leer $FolderPath : $($_.Exception.Message)" -Severity ERROR -Source TOOLKIT
        return @()
    }

}

<#
.SYNOPSIS
    Obtiene las tareas programadas configuradas para ejecutarse al inicio.
.OUTPUTS
    Array de PSCustomObject con Nombre y Estado.
#>
function Get-ScheduledStartup {
    try {
        Get-ScheduledTask -ErrorAction Stop |
                Where-Object {
                    $_.State -ne 'Disabled' -and
                            ($_.Triggers | Where-Object { $_ -match 'Boot|Logon' })
                } |
                ForEach-Object {
                    [PSCustomObject]@{
                        Nombre  = $_.TaskName
                        Comando = $_.TaskPath
                        Estado  = $_.State.ToString()
                    }
                }
    } catch {
        Write-Log "No se pudieron obtener las tareas programadas: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al obtener tareas programadas: $($_.Exception.Message)" -Severity ERROR -Source TOOLKIT
        return @()
    }
}

<#
.SYNOPSIS
    Imprime una lista de entradas de startup en consola y log.
.PARAMETER Entradas
    Array de PSCustomObject con al menos Nombre y Comando.
.PARAMETER ConEstado
    Si es true, muestra tambien la columna Estado (para tareas programadas).
#>
function Show-StartupEntries {
    param(
        $Entradas,
        [switch]$ConEstado
    )

    if (-not $Entradas -or @($Entradas).Count -eq 0) {
        Write-Log "Sin entradas registradas." -Level SUCCESS -LogFile $LogFile
        return
    }

    foreach ($entrada in $Entradas) {
        $NombreMostrar = $entrada.Nombre

        if ($NombreMostrar.Length -gt 30) {
            $NombreMostrar = $NombreMostrar.Substring(0,25) + "..."
        }

        if ($ConEstado) {
            $tag   = Get-CenteredTag -Text $entrada.Estado -TotalWidth 9

            switch ($entrada.Estado) {
                "Running" { $nivel = "SUCCESS" }
                "Ready"   { $nivel = "INFO" }
                default   { $nivel = "NOTE" }
            }

            $linea = "{0,-35} {1}" -f  $NombreMostrar, $tag
            Write-Log $linea -Level $nivel -LogFile $LogFile
        }
        else {
            $ComandoMostrar = Get-CommandDisplay $entrada.Comando
            $linea = "{0,-35} {1}" -f $NombreMostrar, $ComandoMostrar
            Write-Log $linea -LogFile $LogFile
        }
    }
}

<#
.SYNOPSIS
    Obtiene una representacion simplificada de un comando de inicio.
.DESCRIPTION
    Extrae el nombre del ejecutable desde una cadena de comando
    para mejorar la legibilidad de los reportes de auditoria.
    Si no se detecta un ejecutable, devuelve el valor original.
.PARAMETER Command
    Cadena de comando completa obtenida desde el registro o una
    entrada de inicio.
.OUTPUTS
    String con el nombre del ejecutable o el comando original.
#>
function Get-CommandDisplay {
    param([string]$Command)

    if ($Command -match '[^\\]+\.exe') {
        return $Matches[0]
    }

    return $Command
}


#endregion

try {

    #region RECOLECCION DE DATOS
    $ProcesosSistema      = @(Import-DataList -FileName "procesos_sistema.json")
    $ProcesosAplicaciones = @(Import-DataList -FileName "procesos_aplicaciones.json")

    $startupHKCU      = @(Get-RegistryStartup "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run")
    $startupHKLM      = @(Get-RegistryStartup "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run")
    $startupUserDir   = @(Get-FolderStartup "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup")
    $startupSysDir    = @(Get-FolderStartup "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp")
    $startupScheduled = @(Get-ScheduledStartup)

    $totalHKCU      = @($startupHKCU).Count
    $totalHKLM      = @($startupHKLM).Count
    $totalUserDir   = @($startupUserDir).Count
    $totalSysDir    = @($startupSysDir).Count

    $runningTasks   = @($startupScheduled | Where-Object Estado -eq "Running")
    $readyTasks     = @($startupScheduled | Where-Object Estado -eq "Ready")

    $totalRunning   = $runningTasks.Count
    $totalReady     = $readyTasks.Count

    #endregion

    #region PRESENTACION

    Write-Section "PROGRAMAS AL INICIO DE WINDOWS" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "Solo muestra. No desactiva ni modifica nada." -Level NOTE -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    # -- Registro usuario actual --
    Write-Section "REGISTRO - USUARIO ACTUAL" -LogFile $LogFile
    Write-Log "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Level NOTE -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "Entradas encontradas: $totalHKCU" -Level INFO -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Show-StartupEntries -Entradas $startupHKCU
    Write-Blank -LogFile $LogFile

    # -- Registro sistema --
    Write-Section "REGISTRO - SISTEMA" -LogFile $LogFile
    Write-Log "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Level NOTE -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "Entradas encontradas: $totalHKLM" -Level INFO -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Show-StartupEntries -Entradas $startupHKLM
    Write-Blank -LogFile $LogFile

    # -- Carpeta inicio usuario --
    Write-Section "CARPETA INICIO - USUARIO" -LogFile $LogFile
    Write-Log "Origen: Carpeta de inicio del usuario" -Level NOTE -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "Entradas encontradas: $totalUserDir" -Level INFO -LogFile $LogFile
    Show-StartupEntries -Entradas $startupUserDir
    Write-Blank -LogFile $LogFile

    # -- Carpeta inicio sistema --
    Write-Section "CARPETA INICIO - SISTEMA" -LogFile $LogFile
    Write-Log "Origen: Carpeta de inicio del sistema" -Level NOTE -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "Entradas encontradas: $totalSysDir" -Level INFO -LogFile $LogFile
    Show-StartupEntries -Entradas $startupSysDir
    Write-Blank -LogFile $LogFile

    # -- Tareas programadas --
    Write-Section "TAREAS PROGRAMADAS AL INICIO" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "Tareas en ejecucion: $totalRunning" -Level SUCCESS -LogFile $LogFile
    Write-Log "Tareas preparadas : $totalReady" -Level INFO -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    # -- Tareas en ejecucion --
    Write-Section "TAREAS EN EJECUCION" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Show-StartupEntries -Entradas $runningTasks -ConEstado
    Write-Blank -LogFile $LogFile

    # -- Tareas preparadas --
    Write-Section "TAREAS PREPARADAS" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Show-StartupEntries -Entradas $readyTasks -ConEstado
    Write-Blank -LogFile $LogFile

    #endregion

    #region REFERENCIA DE COMANDOS

    Write-Section "REFERENCIA DE COMANDOS" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "Para deshabilitar una entrada del registro:" -Level NOTE -LogFile $LogFile
    Write-Log "  Remove-ItemProperty -Path 'HKCU:\...\Run' -Name 'NombrePrograma'" -Level NOTE -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "Para deshabilitar una tarea programada:" -Level NOTE -LogFile $LogFile
    Write-Log "  Disable-ScheduledTask -TaskName 'NombreTarea'" -Level NOTE -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    #endregion

    #region RESUMEN

    Write-Section "RESUMEN" -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    Write-Log ("Registro usuario..... {0}" -f $totalHKCU) -Level INFO -LogFile $LogFile
    Write-Log ("Registro sistema..... {0}" -f $totalHKLM) -Level INFO -LogFile $LogFile
    Write-Log ("Inicio usuario....... {0}" -f $totalUserDir) -Level INFO -LogFile $LogFile
    Write-Log ("Inicio sistema....... {0}" -f $totalSysDir) -Level INFO -LogFile $LogFile
    Write-Log ("Tareas Running....... {0}" -f $totalRunning) -Level SUCCESS -LogFile $LogFile
    Write-Log ("Tareas Ready......... {0}" -f $totalReady) -Level INFO -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    #endregion

    #region REPORTE

    $script:report.data = @{
        registryHKCU      = $startupHKCU
        registryHKLM      = $startupHKLM
        folderUserStartup = $startupUserDir
        folderSystemStartup = $startupSysDir
        scheduledRunning  = $runningTasks
        scheduledReady    = $readyTasks
    }

    $status = if (@($script:report.errors).Count -gt 0) { "ERROR" } else { "OK" }
    $script:report = Complete-ModuleReport -Report $script:report -Status $status

    #endregion

    #region GENERACION HTML

    # Total = registro (HKCU+HKLM) + carpetas de inicio + tareas EN EJECUCION.
    # No se cuentan las tareas "Ready" porque no arrancan con Windows.
    $totalInicio = $totalHKCU + $totalHKLM + $totalUserDir + $totalSysDir + $totalRunning

    # Umbrales provisorios (v3.1.0), basados en una muestra inicial de 4 equipos.
    # A ajustar cuando se acumulen mas datos reales (objetivo: ~15 equipos).
    $nivelCantidad = if ($totalInicio -le 15) { "OK" }
    elseif ($totalInicio -le 25) { "WARNING" }
    else { "ERROR" }

    $textoCantidad = switch ($nivelCantidad) {
        "OK"      { "Cantidad normal" }
        "WARNING" { "Cantidad elevada, puede afectar el tiempo de arranque" }
        "ERROR"   { "Cantidad alta, se recomienda revisar y desactivar innecesarios" }
    }

    # Cruce contra listados conocidos para marcar reconocido/no reconocido
    $todasLasEntradas = @($startupHKCU) + @($startupHKLM) + @($startupUserDir) + @($startupSysDir)
    $entradasNoReconocidas = @($todasLasEntradas | Where-Object {
        $nombreExe = ($_.Comando -replace '.*\\', '' -replace '["'']', '').Split(' ')[0] -replace '\.exe$', ''
        ($ProcesosSistema -notcontains $nombreExe) -and ($ProcesosAplicaciones -notcontains $nombreExe)
    })

    $filasNoReconocidas = ""
    foreach ($entrada in $entradasNoReconocidas) {
        $filasNoReconocidas += "<tr><td>$($entrada.Nombre)</td><td>$($entrada.Comando)</td></tr>`n"
    }

    $seccionNoReconocidas = if (@($entradasNoReconocidas).Count -gt 0) {
        @"
    <h2>Entradas no reconocidas</h2>
    <p style="font-size:13px;">Estas entradas no estan en nuestra base de aplicaciones conocidas.
    No es necesariamente un problema, pero vale la pena confirmar que las reconoce:</p>
    <table>
        <tr><th>Nombre</th><th>Programa</th></tr>
        $filasNoReconocidas
    </table>
"@
    } else { "" }

    $contentHtml = @"
    <h2>Resumen</h2>
    <div class="metric"><div class="valor">$totalInicio</div><div class="label">Total al inicio</div></div>
    <div class="metric"><div class="valor">$(@($entradasNoReconocidas).Count)</div><div class="label">No reconocidas</div></div>
    <p>$(New-HtmlBadge -Texto $textoCantidad -Nivel $nivelCantidad)</p>
    $seccionNoReconocidas
"@

    $reportFileHtml = Get-ReportFileName -ReportsDir $reportsDir -ModuleName "startup" -Extension "html"
    Save-ModuleReportHtml -Report $script:report -ReportFile $reportFileHtml -TituloModulo "Programas al Inicio" -ContentHtml $contentHtml -NivelOverride $nivelCantidad

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