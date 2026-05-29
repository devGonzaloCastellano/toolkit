<#
.SYNOPSIS
    Modulo de auditoria de puertos y conexiones activas.
.DESCRIPTION
    Analiza las conexiones TCP activas, puertos en escucha y puertos UDP,
    clasificando cada entrada por nivel de riesgo segun el puerto,
    el proceso asociado y el origen/destino de la conexion.
    Ayuda a identificar conexiones sospechosas o inesperadas.
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

$envInfo = Initialize-Environment -LogDir $LogDir -ModuleName "puertos"
$LogFile = $envInfo.LogFile

#endregion

#region DATOS - TABLAS DE CLASIFICACION

# Puertos conocidos del sistema y aplicaciones comunes
# Clasificados como seguros cuando el proceso asociado es el esperado
$PuertosConocidos = @{
    80    = "HTTP"
    443   = "HTTPS"
    135   = "RPC"
    139   = "NetBIOS"
    445   = "SMB"
    3389  = "RDP - Verificar si es intencional"
    5040  = "WSD (Windows)"
    5357  = "WSD (Windows)"
    7680  = "WUDO - Windows Update"
    1900  = "SSDP/UPnP"
    5353  = "mDNS"
    53    = "DNS"
    67    = "DHCP Server"
    68    = "DHCP Client"
    123   = "NTP"
    8080  = "HTTP alternativo"
    8443  = "HTTPS alternativo"
    49152 = "RPC dinamico"
}

# Puertos asociados a malware, herramientas de hacking o backdoors conocidos
# Su presencia no es definitiva pero requiere investigacion inmediata
$PuertosRiesgo = @{
    4444  = "Metasploit default - RIESGO ALTO"
    1337  = "Leet/Backdoor - RIESGO ALTO"
    31337 = "Back Orifice - RIESGO ALTO"
    12345 = "NetBus - RIESGO ALTO"
    54321 = "Back Orifice 2000 - RIESGO ALTO"
    9001  = "Tor relay - Revisar"
    9050  = "Tor proxy - Revisar"
    6667  = "IRC (usado por botnets) - Revisar"
    1080  = "SOCKS proxy - Revisar"
    3128  = "Squid proxy - Revisar"
    8888  = "Backdoor comun - Revisar"
    2222  = "SSH alternativo - Revisar"
}

# Procesos del sistema operativo que se consideran confiables
$ProcesosConfiables = @(
    "svchost", "lsass", "services", "wininit", "winlogon",
    "explorer", "csrss", "smss", "System", "Registry",
    "spoolsv", "SearchIndexer", "MsMpEng", "NisSrv",
    "dasHost", "WmiPrvSE", "RuntimeBroker", "taskhostw",
    "smartscreen", "MpDefenderCoreService"
)

#endregion

#region FUNCIONES INTERNAS

<#
.SYNOPSIS
    Obtiene el nombre del proceso dueno de una conexion por su PID.
.PARAMETER Pid
    ID del proceso.
.OUTPUTS
    String con el nombre del proceso o "Desconocido" si no se puede obtener.
#>
function Get-NombreProceso {
    param([int]$ProcessId)
    try {
        $p = Get-Process -Id $ProcessId -ErrorAction Stop
        return $p.Name
    } catch {
        return "Desconocido"
    }
}

<#
.SYNOPSIS
    Determina si una IP es local (privada o loopback).
.PARAMETER IP
    String con la direccion IP a evaluar.
.OUTPUTS
    Bool - $true si es local, $false si es publica.
#>
function Test-IPLocal {
    param([string]$IP)
    return $IP -match '^(127\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|::1|0\.0\.0\.0|::)'
}

<#
.SYNOPSIS
    Clasifica una conexion y retorna su nivel de riesgo y descripcion.
.PARAMETER Puerto
    Numero de puerto local.
.PARAMETER IPRemota
    Direccion IP remota de la conexion.
.PARAMETER Proceso
    Nombre del proceso dueno de la conexion.
.OUTPUTS
    PSCustomObject con Nivel (INFO/SUCCESS/WARNING/ERROR) y Descripcion.
#>
function Get-ClasificacionPuerto {
    param(
        [int]$Puerto,
        [string]$IPRemota,
        [string]$Proceso
    )

    # Prioridad 1: puerto de riesgo conocido -> ERROR inmediato
    if ($PuertosRiesgo.ContainsKey($Puerto)) {
        return [PSCustomObject]@{
            Nivel       = "ERROR"
            Descripcion = $PuertosRiesgo[$Puerto]
        }
    }

    # Prioridad 2: conexion externa con proceso desconocido -> WARNING
    $esExterno   = -not (Test-IPLocal -IP $IPRemota)
    $esConfiable = $ProcesosConfiables -contains $Proceso

    if ($esExterno -and -not $esConfiable) {
        return [PSCustomObject]@{
            Nivel       = "WARNING"
            Descripcion = "Conexion externa - proceso no reconocido"
        }
    }

    # Prioridad 3: puerto conocido del sistema -> SUCCESS con descripcion
    if ($PuertosConocidos.ContainsKey($Puerto)) {
        return [PSCustomObject]@{
            Nivel       = "SUCCESS"
            Descripcion = $PuertosConocidos[$Puerto]
        }
    }

    # Prioridad 4: conexion externa con proceso confiable -> INFO
    if ($esExterno -and $esConfiable) {
        return [PSCustomObject]@{
            Nivel       = "INFO"
            Descripcion = "Conexion externa - proceso del sistema"
        }
    }

    # Default: conexion local o interna sin riesgo identificado -> INFO
    return [PSCustomObject]@{
        Nivel       = "INFO"
        Descripcion = "Conexion local o interna"
    }
}

<#
.SYNOPSIS
    Formatea un endpoint IP:Puerto para display compacto.
.DESCRIPTION
    Detecta el prefijo IPv6 local del equipo y lo reemplaza por [local6]
    para reducir el ruido visual de las direcciones IPv6 largas.
    Las IPv4 se muestran sin modificacion.
.PARAMETER Endpoint
    String con formato IP:Puerto o [IPv6]:Puerto
.PARAMETER IPv6LocalPrefix
    Prefijo IPv6 local a abreviar (se detecta automaticamente).
.OUTPUTS
    String con el endpoint formateado.
#>
function Format-Endpoint {
    param(
        [string]$Endpoint,
        [string]$IPv6LocalPrefix
    )

    if ($IPv6LocalPrefix -and $Endpoint.StartsWith($IPv6LocalPrefix)) {
        $puerto = $Endpoint.Substring($IPv6LocalPrefix.Length)
        return "[local6]:$puerto"
    }
    return $Endpoint
}



# Detectar prefijo IPv6 local desde las conexiones activas
# Es mas confiable que tomarlo de Get-NetIPAddress porque hay multiples IPs IPv6
# y la que usa para conectarse puede no ser la primera de la lista
$primeraConexionIPv6 = (Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalAddress -match ':' -and $_.LocalAddress -notmatch '^(::1|fe80)' } |
        Select-Object -First 1).LocalAddress

$ipv6Prefix = if ($primeraConexionIPv6) {
    $primeraConexionIPv6 -replace ':[^:]+$', ':'
} else { "" }

# Conexiones TCP establecidas
$conexionesTCP = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
        ForEach-Object {
            $proceso  = Get-NombreProceso -ProcessId $_.OwningProcess
            $clasif   = Get-ClasificacionPuerto -Puerto $_.LocalPort -IPRemota $_.RemoteAddress -Proceso $proceso
            $localEp  = Format-Endpoint -Endpoint "$($_.LocalAddress):$($_.LocalPort)"   -IPv6LocalPrefix $ipv6Prefix
            $remoteEp = Format-Endpoint -Endpoint "$($_.RemoteAddress):$($_.RemotePort)" -IPv6LocalPrefix $ipv6Prefix
            [PSCustomObject]@{
                LocalEndpoint  = $localEp
                RemoteEndpoint = $remoteEp
                Proceso        = $proceso
                Nivel          = $clasif.Nivel
                Descripcion    = $clasif.Descripcion
            }
        } | Sort-Object Nivel -Descending

# Puertos TCP en escucha
$puertosListen = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Sort-Object LocalPort -Unique |
        ForEach-Object {
            $proceso = Get-NombreProceso -ProcessId $_.OwningProcess
            $clasif  = Get-ClasificacionPuerto -Puerto $_.LocalPort -IPRemota "127.0.0.1" -Proceso $proceso
            [PSCustomObject]@{
                Puerto      = $_.LocalPort
                Proceso     = $proceso
                Nivel       = $clasif.Nivel
                Descripcion = $clasif.Descripcion
            }
        } | Sort-Object Nivel -Descending

# Puertos UDP activos
$puertosUDP = Get-NetUDPEndpoint -ErrorAction SilentlyContinue |
        Sort-Object LocalPort -Unique |
        ForEach-Object {
            $proceso = Get-NombreProceso -ProcessId $_.OwningProcess
            [PSCustomObject]@{
                Puerto  = $_.LocalPort
                Proceso = $proceso
            }
        }

#endregion

#region PRESENTACION

Write-Section "PUERTOS Y CONEXIONES ACTIVAS" -LogFile $LogFile
Write-Blank -LogFile $LogFile

# -- Seccion 1: Conexiones TCP activas --
Write-Section "CONEXIONES TCP ACTIVAS" -LogFile $LogFile
Write-Blank -LogFile $LogFile

if ($conexionesTCP) {
    # Separar conexiones externas de locales
    $tcpExternas = $conexionesTCP | Where-Object { $_.Descripcion -ne "Conexion local o interna" }
    $tcpLocales  = $conexionesTCP | Where-Object { $_.Descripcion -eq "Conexion local o interna" }

    # Agrupar externas por proceso
    if ($tcpExternas) {
        Write-Log "Conexiones externas agrupadas por proceso:" -LogFile $LogFile
        Write-Blank -LogFile $LogFile

        $tcpExternas | Group-Object Proceso | Sort-Object {
            # Ordenar por nivel de riesgo: ERROR > WARNING > INFO
            $niveles = @{ ERROR = 0; WARNING = 1; INFO = 2; SUCCESS = 3 }
            ($_.Group | ForEach-Object { $niveles[$_.Nivel] } | Measure-Object -Minimum).Minimum
        } | ForEach-Object {
            $grupo     = $_
            $nivelMax  = ($grupo.Group | Where-Object { $_.Nivel -eq "ERROR" } | Select-Object -First 1)
            if (-not $nivelMax) { $nivelMax = $grupo.Group | Where-Object { $_.Nivel -eq "WARNING" } | Select-Object -First 1 }
            if (-not $nivelMax) { $nivelMax = $grupo.Group[0] }

            $puertos   = ($grupo.Group.RemoteEndpoint | ForEach-Object {
                ($_ -split ':')[-1]
            } | Sort-Object -Unique) -join ", "

            $linea = "{0,-25} {1,2} conexion(es) externa(s)  puertos remotos: {2}" -f `
                     $grupo.Name, $grupo.Count, $puertos
            Write-Log $linea -Level $nivelMax.Nivel -LogFile $LogFile
        }
        Write-Blank -LogFile $LogFile
    }

    # Conexiones locales - mostrar directo, son pocas y relevantes
    if ($tcpLocales) {
        Write-Log "Conexiones locales:" -LogFile $LogFile
        Write-Blank -LogFile $LogFile
        foreach ($c in $tcpLocales) {
            $linea = "{0,-22} <-> {1,-22} [{2}]" -f $c.LocalEndpoint, $c.RemoteEndpoint, $c.Proceso
            Write-Log $linea -Level $c.Nivel -LogFile $LogFile
        }
        Write-Blank -LogFile $LogFile
    }
} else {
    Write-Log "Sin conexiones TCP activas." -LogFile $LogFile
}
Write-Blank -LogFile $LogFile

# -- Seccion 2: Puertos en escucha --
Write-Section "PUERTOS EN ESCUCHA" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "Puertos abiertos esperando conexiones entrantes." -LogFile $LogFile
Write-Blank -LogFile $LogFile

if ($puertosListen) {
    foreach ($p in $puertosListen) {
        $linea = "Puerto {0,-6} [{1}] {2}" -f $p.Puerto, $p.Proceso, $p.Descripcion
        Write-Log $linea -Level $p.Nivel -LogFile $LogFile
    }
} else {
    Write-Log "Sin puertos en escucha detectados." -LogFile $LogFile
}
Write-Blank -LogFile $LogFile

# -- Seccion 3: Puertos UDP --
Write-Section "PUERTOS UDP ACTIVOS" -LogFile $LogFile
Write-Blank -LogFile $LogFile

if ($puertosUDP) {
    foreach ($p in $puertosUDP) {
        $linea = "Puerto {0,-6} [{1}]" -f $p.Puerto, $p.Proceso
        Write-Log $linea -LogFile $LogFile
    }
} else {
    Write-Log "Sin puertos UDP activos." -LogFile $LogFile
}
Write-Blank -LogFile $LogFile

#endregion

#region RESUMEN

Write-Section -LogFile $LogFile
Write-Log "Log guardado en: $LogFile" -LogFile $LogFile
Write-Blank

Invoke-Pause

#endregion