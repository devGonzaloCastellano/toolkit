<#
.SYNOPSIS
    Modulo de utilidades compartidas para la Portable Windows Toolkit.
.DESCRIPTION
    Provee funciones auxiliares reutilizables para todos los modulos:
    logging con niveles, formateo de consola, inicializacion de entorno
    y helpers de uso general.
    Debe importarse via dot-sourcing al inicio de cada script:
        . "$PSScriptRoot\..\lib\Utils.ps1"
.NOTES
    Version : 3.0.0
    Proyecto: Portable Windows Toolkit
#>

#region FUNCIONES DE LOGGING

<#
.SYNOPSIS
    Escribe un mensaje en consola y opcionalmente en archivo de log.
.PARAMETER Message
    Texto del mensaje a registrar.
.PARAMETER Level
    Nivel del mensaje: INFO, SUCCESS, WARNING o ERROR.
.PARAMETER LogFile
    Ruta completa al archivo de log. Si se omite, solo escribe en consola.
.EXAMPLE
    Write-Log "Proceso iniciado."
    Write-Log "Archivo eliminado." -Level SUCCESS
    Write-Log "No se pudo acceder." -Level WARNING -LogFile $LogFile
    Write-Log "Error critico." -Level ERROR -LogFile $LogFile
#>
function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR", "NOTE")]
        [string]$Level = "INFO",

        [string]$LogFile
    )

    $colorMap = @{
        INFO    = "White"
        SUCCESS = "Green"
        WARNING = "Yellow"
        ERROR   = "Red"
        NOTE    = "DarkMagenta"
    }

    $timestamp = Get-Date -Format "HH:mm"
    $tag  = Get-CenteredTag -Text $Level -TotalWidth 9
    $line      = "[{0}] {1} {2}" -f $timestamp, $tag, $Message
    $color     = $colorMap[$Level]

    Write-Host $line -ForegroundColor $color

    if ($LogFile) {
        $line | Out-File -FilePath $LogFile -Append -Encoding utf8
    }
}

<#
.SYNOPSIS
    Escribe una linea en blanco en consola y opcionalmente en el log.
.PARAMETER LogFile
    Ruta al archivo de log. Opcional.
#>
function Write-Blank {
    param([string]$LogFile)

    Write-Host ""
    if ($LogFile) {
        "" | Out-File -FilePath $LogFile -Append -Encoding utf8
    }
}

<#
.SYNOPSIS
    Escribe un separador visual de seccion en consola y en el log.
.PARAMETER Title
    Titulo opcional para mostrar centrado dentro del separador.
.PARAMETER LogFile
    Ruta al archivo de log. Opcional.
.EXAMPLE
    Write-Section
    Write-Section "INFORMACION DEL SISTEMA"
    Write-Section "RESUMEN FINAL" -LogFile $LogFile
#>
function Write-Section {
    param(
        [string]$Title,
        [string]$LogFile
    )

    if ($Title) {
        $padTotal = 50 - $Title.Length - 2
        $padLeft  = [math]::Floor($padTotal / 2)
        $padRight = $padTotal - $padLeft
        $line     = "=" * $padLeft + " $Title " + "=" * $padRight
    } else {
        $line = "=" * 50
    }

    Write-Host $line -ForegroundColor Cyan
    if ($LogFile) {
        $line | Out-File -FilePath $LogFile -Append -Encoding utf8
    }
}

#endregion

#region INICIALIZACION DE ENTORNO

<#
.SYNOPSIS
    Inicializa el entorno de ejecucion de un modulo.
.DESCRIPTION
    Crea el directorio de logs si no existe, genera el path del archivo
    de log con timestamp y retorna un objeto con los valores inicializados.
.PARAMETER LogDir
    Ruta al directorio de logs.
.PARAMETER ModuleName
    Nombre del modulo, usado como prefijo del archivo de log.
.OUTPUTS
    PSCustomObject con LogDir, LogFile y Timestamp.
.EXAMPLE
    $env = Initialize-Environment -LogDir $LogDir -ModuleName "limpieza"
    $LogFile = $env.LogFile
#>
function Initialize-Environment {
    param(
        [Parameter(Mandatory)]
        [string]$LogDir,

        [Parameter(Mandatory)]
        [string]$ModuleName
    )

    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir | Out-Null
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
    $logFile   = Join-Path $LogDir "${ModuleName}_${timestamp}.txt"

    return [PSCustomObject]@{
        LogDir    = $LogDir
        LogFile   = $logFile
        Timestamp = $timestamp
    }
}

#endregion

#region AUTO-ELEVACION

<#
.SYNOPSIS
    Verifica si el proceso actual tiene privilegios de Administrador.
.OUTPUTS
    [bool]
#>
function Test-IsAdmin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

<#
.SYNOPSIS
    Relanza el script actual con privilegios de Administrador via UAC.
.DESCRIPTION
    Si el script no esta elevado, lo relanza con Start-Process -Verb RunAs.
    Debe llamarse al inicio del script, antes de cualquier logica.
.PARAMETER ScriptPath
    Ruta completa al script. Usar $PSCommandPath.
.PARAMETER Parameters
    Parametros a pasar al proceso elevado.
.EXAMPLE
    Invoke-Elevate -ScriptPath $PSCommandPath
#>
function Invoke-Elevate {
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath,

        [hashtable]$Parameters = @{}
    )

    if (Test-IsAdmin) { return }

    Write-Warning "Se requieren permisos de administrador. Solicitando elevacion..."

    $paramString = ($Parameters.GetEnumerator() |
            ForEach-Object { "-$($_.Key) `"$($_.Value)`"" }) -join " "

    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" $paramString"

    Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
    exit
}

#endregion

#region HELPERS DE FORMATO

<#
.SYNOPSIS
    Convierte bytes a representacion legible (KB, MB, GB).
.PARAMETER Bytes
    Valor en bytes a convertir.
.OUTPUTS
    [string] con valor y unidad. Ejemplo: "1.23 GB"
.EXAMPLE
    Format-Bytes 1548576    # "1.48 MB"
    Format-Bytes 2147483648 # "2.00 GB"
#>
function Format-Bytes {
    param([long]$Bytes)

    switch ($Bytes) {
        { $_ -ge 1GB } { return "{0:N2} GB" -f ($_ / 1GB) }
        { $_ -ge 1MB } { return "{0:N2} MB" -f ($_ / 1MB) }
        { $_ -ge 1KB } { return "{0:N2} KB" -f ($_ / 1KB) }
        default        { return "$_ bytes" }
    }
}

<#
.SYNOPSIS
    Pausa la ejecucion hasta que el usuario presione Enter.
.PARAMETER Message
    Mensaje a mostrar. Por defecto: "Presiona Enter para continuar..."
#>
function Invoke-Pause {
    param([string]$Message = "Presiona Enter para continuar...")
    Write-Host "`n$Message" -ForegroundColor DarkGray
    Read-Host | Out-Null
}

<#
.SYNOPSIS
    Genera un texto centrado entre delimitadores con relleno de espacios.
.DESCRIPTION
    Distribuye espacios equitativamente a ambos lados del texto para
    mantener alineacion visual uniforme en consola y archivos de log.
    Si el texto supera el ancho solicitado, retorna sin romper el contenido.
.PARAMETER Text
    Texto a centrar dentro de los delimitadores.
.PARAMETER TotalWidth
    Ancho total del contenido interior (sin contar los delimitadores).
    Si se omite, se ajusta automaticamente al texto mas 2 espacios de aire.
.PARAMETER OpenDelimiter
    Caracter de apertura. Por defecto: "["
.PARAMETER CloseDelimiter
    Caracter de cierre. Por defecto: "]"
.OUTPUTS
    [string] Texto encofrado y centrado.
.EXAMPLE
    Get-CenteredTag "INFO"       # "[INFO]"     (modo automatico)
    Get-CenteredTag "INFO" 9       # "[  INFO  ]" (modo ancho fijo)
#>
function Get-CenteredTag {
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$Text,

        [Parameter(Position = 1)]
        [int]$TotalWidth,

        [string]$OpenDelimiter  = "[",
        [string]$CloseDelimiter = "]"
    )

    if (-not $PSBoundParameters.ContainsKey('TotalWidth')) {
        $TotalWidth = $Text.Length + 2
    }

    $SpacesNeeded = $TotalWidth - $Text.Length

    if ($SpacesNeeded -le 0) {
        return "$OpenDelimiter$Text$CloseDelimiter"
    }

    $PadLeft  = [Math]::Floor($SpacesNeeded / 2)
    $PadRight = [Math]::Ceiling($SpacesNeeded / 2)

    return "{0}{1}{2}{3}{4}" -f $OpenDelimiter, (" " * $PadLeft), $Text, (" " * $PadRight), $CloseDelimiter
}

<#
.SYNOPSIS
    Verifica si hay conexion a internet intentando resolver un host conocido.
.OUTPUTS
    [bool]
.EXAMPLE
    if (-not (Test-InternetConnection)) {
        Write-Log "Sin conexion a internet." -Level ERROR
    }
#>
function Test-InternetConnection {
    try {
        $null = [System.Net.Dns]::GetHostEntry("dns.google")
        return $true
    } catch {
        return $false
    }
}

#region CANCELACION GLOBAL

<#
.SYNOPSIS
    Registra el manejador global de cancelacion (Ctrl+C) para toda la toolkit.
.DESCRIPTION
    Suscribe el evento CancelKeyPress de la consola via Register-ObjectEvent,
    que es el mecanismo seguro para ejecutar cmdlets dentro del handler (a
    diferencia de suscribirse directo al evento .NET, que corre en un hilo
    separado y puede generar errores de pipeline).
    Al dispararse, cancela la terminacion inmediata, limpia el reporte TXT
    en curso (si existia) y finaliza la ejecucion de toda la toolkit.
    Debe llamarse una unica vez, al inicio de menu.ps1, antes del loop principal.
.EXAMPLE
    Register-CancelHandler
#>
function Register-CancelHandler {
    $global:CurrentModule  = $null
    $global:CurrentTxtPath = $null

    $null = Register-ObjectEvent -InputObject ([Console]) -EventName CancelKeyPress -Action {
        $Event.SourceEventArgs.Cancel = $true

        Write-Log "Ejecucion cancelada por el usuario (Ctrl+C) durante: $global:CurrentModule" -Level WARNING

        if ($global:CurrentTxtPath -and (Test-Path $global:CurrentTxtPath)) {
            Remove-Item $global:CurrentTxtPath -Force
        }

        Write-Blank
        Write-Host "  Todos los procesos se han cancelado correctamente. Esta ventana se cerrara automaticamente." -ForegroundColor Yellow
        Write-Blank

        Start-Sleep -Seconds 3
        Stop-Process -Id $PID -Force
    }
}

<#
.SYNOPSIS
    Marca el modulo y el archivo TXT actualmente en ejecucion.
.DESCRIPTION
    Debe llamarse al inicio de cada modulo, inmediatamente despues de
    Initialize-Environment, para que el manejador de cancelacion (Ctrl+C)
    sepa que modulo esta corriendo y que archivo limpiar si se interrumpe.
.PARAMETER ModuleName
    Nombre del modulo en ejecucion (ej: "reporte_disco").
.PARAMETER TxtPath
    Ruta completa al archivo de log/reporte TXT en curso.
.EXAMPLE
    Set-CurrentExecution -ModuleName "reporte_disco" -TxtPath $env.LogFile
#>
function Set-CurrentExecution {
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,

        [Parameter(Mandatory)]
        [string]$TxtPath
    )

    $global:CurrentModule  = $ModuleName
    $global:CurrentTxtPath = $TxtPath
}

#endregion

#endregion