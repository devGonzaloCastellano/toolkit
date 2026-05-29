<#
.SYNOPSIS
    Modulo de auditoria de programas al inicio de Windows.
.DESCRIPTION
    Muestra todos los programas y tareas configurados para ejecutarse
    al iniciar Windows, consultando el registro del sistema, las carpetas
    de inicio del usuario y del sistema, y el Programador de Tareas.
    No desactiva ni modifica nada, solo reporta para auditoria.
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

$envInfo = Initialize-Environment -LogDir $LogDir -ModuleName "startup"
$LogFile = $envInfo.LogFile

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

    Get-ChildItem -Path $FolderPath -ErrorAction SilentlyContinue |
            ForEach-Object {
                [PSCustomObject]@{
                    Nombre  = $_.Name
                    Comando = $_.FullName
                }
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
        Write-Log "Sin entradas registradas." -Level INFO -LogFile $LogFile
        return
    }

    foreach ($entrada in $Entradas) {
        if ($ConEstado) {
            $linea = "{0,-45} [{1}]" -f $entrada.Nombre, $entrada.Estado
        } else {
            $linea = "{0,-35} {1}" -f $entrada.Nombre, $entrada.Comando
        }
        Write-Log $linea -LogFile $LogFile
    }
}

#endregion

#region RECOLECCION DE DATOS

$startupHKCU      = Get-RegistryStartup "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
$startupHKLM      = Get-RegistryStartup "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
$startupUserDir   = Get-FolderStartup "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$startupSysDir    = Get-FolderStartup "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"
$startupScheduled = Get-ScheduledStartup

#endregion

#region PRESENTACION

Write-Section "PROGRAMAS AL INICIO DE WINDOWS" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "Solo muestra. No desactiva ni modifica nada." -Level WARNING -LogFile $LogFile
Write-Blank -LogFile $LogFile

# -- Registro usuario actual --
Write-Section "REGISTRO - USUARIO ACTUAL" -LogFile $LogFile
Write-Log "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Show-StartupEntries -Entradas $startupHKCU
Write-Blank -LogFile $LogFile

# -- Registro sistema --
Write-Section "REGISTRO - SISTEMA" -LogFile $LogFile
Write-Log "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Show-StartupEntries -Entradas $startupHKLM
Write-Blank -LogFile $LogFile

# -- Carpeta inicio usuario --
Write-Section "CARPETA INICIO - USUARIO" -LogFile $LogFile
Write-Log "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Show-StartupEntries -Entradas $startupUserDir
Write-Blank -LogFile $LogFile

# -- Carpeta inicio sistema --
Write-Section "CARPETA INICIO - SISTEMA" -LogFile $LogFile
Write-Log "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Show-StartupEntries -Entradas $startupSysDir
Write-Blank -LogFile $LogFile

# -- Tareas programadas --
Write-Section "TAREAS PROGRAMADAS AL INICIO" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Show-StartupEntries -Entradas $startupScheduled -ConEstado
Write-Blank -LogFile $LogFile

#endregion

#region REFERENCIA DE COMANDOS

Write-Section "REFERENCIA DE COMANDOS" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "Para deshabilitar una entrada del registro:" -LogFile $LogFile
Write-Log "  Remove-ItemProperty -Path 'HKCU:\...\Run' -Name 'NombrePrograma'" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "Para deshabilitar una tarea programada:" -LogFile $LogFile
Write-Log "  Disable-ScheduledTask -TaskName 'NombreTarea'" -LogFile $LogFile
Write-Blank -LogFile $LogFile

#endregion

#region RESUMEN

Write-Section -LogFile $LogFile
Write-Log "Log guardado en: $LogFile" -LogFile $LogFile
Write-Blank

Invoke-Pause

#endregion