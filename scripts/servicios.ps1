<#
.SYNOPSIS
    Modulo de auditoria de servicios innecesarios del sistema.
.DESCRIPTION
    Muestra el estado actual de servicios de telemetria, Xbox, y otros
    servicios raramente utilizados. No desactiva ni modifica nada,
    solo reporta el estado para que el tecnico tome decisiones informadas.
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

$envInfo = Initialize-Environment -LogDir $LogDir -ModuleName "servicios"
$LogFile = $envInfo.LogFile

#endregion

#region DATOS - CATALOGO DE SERVICIOS

# Cada entrada define el nombre tecnico del servicio y una descripcion
# legible para que el tecnico entienda para que sirve sin tener que buscarlo.
$Categorias = @(
    @{
        Titulo    = "TELEMETRIA Y DIAGNOSTICO"
        Servicios = @(
            @{ Nombre = "DiagTrack";        Descripcion = "Telemetria de uso y diagnostico hacia Microsoft" },
            @{ Nombre = "dmwappushservice"; Descripcion = "Enrutamiento de mensajes WAP (usado por telemetria)" },
            @{ Nombre = "PcaSvc";           Descripcion = "Asistente de compatibilidad de programas" },
            @{ Nombre = "WerSvc";           Descripcion = "Informe de errores de Windows" }
        )
    },
    @{
        Titulo    = "XBOX Y GAMING"
        Servicios = @(
            @{ Nombre = "XblAuthManager";  Descripcion = "Autenticacion de cuenta Xbox Live" },
            @{ Nombre = "XblGameSave";     Descripcion = "Sincronizacion de partidas guardadas Xbox" },
            @{ Nombre = "XboxNetApiSvc";   Descripcion = "API de red para funciones Xbox" },
            @{ Nombre = "XboxGipSvc";      Descripcion = "Protocolo de entrada para accesorios Xbox" }
        )
    },
    @{
        Titulo    = "SERVICIOS RARAMENTE USADOS"
        Servicios = @(
            @{ Nombre = "Fax";             Descripcion = "Envio y recepcion de faxes" },
            @{ Nombre = "MapsBroker";      Descripcion = "Descarga de mapas offline" },
            @{ Nombre = "RetailDemo";      Descripcion = "Modo demostracion para tiendas" },
            @{ Nombre = "RemoteRegistry";  Descripcion = "Permite edicion remota del registro" },
            @{ Nombre = "WMPNetworkSvc";   Descripcion = "Compartir biblioteca de Windows Media Player" },
            @{ Nombre = "icssvc";          Descripcion = "Zona de acceso movil (hotspot)" },
            @{ Nombre = "lfsvc";           Descripcion = "Servicio de geolocalizacion" },
            @{ Nombre = "SharedAccess";    Descripcion = "Compartir conexion a internet (ICS)" }
        )
    }
)

#endregion

#region FUNCIONES INTERNAS

<#
.SYNOPSIS
    Obtiene el estado de un servicio por nombre.
.PARAMETER Nombre
    Nombre tecnico del servicio (ej: "DiagTrack").
.OUTPUTS
    String con el estado: "Running", "Stopped", "Disabled" o "Absent".
#>
function Get-EstadoServicio {
    param([string]$Nombre)

    try {
        $svc = Get-Service -Name $Nombre -ErrorAction Stop
        return $svc.Status.ToString()
    } catch {
        return "Absent"
    }
}

<#
.SYNOPSIS
    Determina el nivel de log segun el estado del servicio.
.DESCRIPTION
    Running es WARNING porque indica un servicio innecesario activo.
    Stopped y Disabled son SUCCESS porque es el estado esperado.
    No instalado es INFO porque es neutral.
.PARAMETER Estado
    String con el estado del servicio.
.OUTPUTS
    String con el nivel de log: WARNING, SUCCESS o INFO.
#>
function Get-NivelPorEstado {
    param([string]$Estado)

    switch ($Estado) {
        "Running"   { return "WARNING" }
        "Stopped"   { return "SUCCESS" }
        "Disabled"  { return "SUCCESS" }
        "Absent"    { return "INFO"    }
        default     { return "INFO"    }
    }
}

#endregion

#region RECOLECCION DE DATOS

# Consultamos todos los servicios antes de mostrar nada
# para separar la obtencion de datos de la presentacion
$Resultados = foreach ($categoria in $Categorias) {
    $serviciosEvaluados = foreach ($svc in $categoria.Servicios) {
        $estado = Get-EstadoServicio -Nombre $svc.Nombre
        [PSCustomObject]@{
            Nombre      = $svc.Nombre
            Descripcion = $svc.Descripcion
            Estado      = $estado
            Nivel       = Get-NivelPorEstado -Estado $estado
        }
    }
    [PSCustomObject]@{
        Titulo    = $categoria.Titulo
        Servicios = $serviciosEvaluados
    }
}

#endregion

#region PRESENTACION

Write-Section "SERVICIOS INNECESARIOS" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "Solo muestra estado. No desactiva ni modifica nada." -Level NOTE -LogFile $LogFile
Write-Blank -LogFile $LogFile

foreach ($categoria in $Resultados) {
    Write-Section $categoria.Titulo -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    foreach ($svc in $categoria.Servicios) {
        $tag   = Get-CenteredTag -Text $svc.Estado -TotalWidth 9
        $linea = "{0,-18} {1} {2}" -f $svc.Nombre, $tag, $svc.Descripcion
        Write-Log $linea -Level $svc.Nivel -LogFile $LogFile
    }

    Write-Blank -LogFile $LogFile
}

#endregion

#region REFERENCIA DE COMANDOS

Write-Section "REFERENCIA DE COMANDOS" -Level NOTE -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "Para deshabilitar un servicio:" -Level NOTE -LogFile $LogFile
Write-Log "  Stop-Service -Name 'NombreServicio' -Force" -Level NOTE -LogFile $LogFile
Write-Log "  Set-Service  -Name 'NombreServicio' -StartupType Disabled" -Level NOTE -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "Para reactivar un servicio:" -LogFile $LogFile -Level NOTE
Write-Log "  Set-Service  -Name 'NombreServicio' -StartupType Automatic" -Level NOTE -LogFile $LogFile
Write-Log "  Start-Service -Name 'NombreServicio'" -Level NOTE -LogFile $LogFile
Write-Blank -LogFile $LogFile

#endregion

#region RESUMEN

Write-Section -LogFile $LogFile
Write-Log "Log guardado en: $LogFile" -LogFile $LogFile
Write-Blank

Invoke-Pause

#endregion