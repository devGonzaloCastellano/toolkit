<#
.SYNOPSIS
    Modulo de auditoria de puertos y conexiones activas.
.DESCRIPTION
    Analiza las conexiones TCP activas, puertos en escucha y puertos UDP,
    clasificando cada entrada por nivel de riesgo segun el puerto,
    el proceso asociado y el origen/destino de la conexion.
    Ayuda a identificar conexiones sospechosas o inesperadas.
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

$envInfo = Initialize-Environment -LogDir $LogDir -ModuleName "puertos"
$LogFile = $envInfo.LogFile

Set-CurrentExecution -ModuleName "puertos" -TxtPath $LogFile

$reportsDir = Join-Path (Split-Path $LogDir -Parent) "reports"
$reportFile = Get-ReportFileName -ReportsDir $reportsDir -ModuleName "puertos"
$script:report = New-ModuleReport -ModuleName "puertos"

#endregion

#region DATOS - TABLAS DE CLASIFICACION

$PuertosConocidos = Import-DataList -FileName "puertos_conocidos.json" -AsHashtable
$PuertosRiesgo = Import-DataList -FileName "puertos_riesgo.json" -AsHashtable
$ProcesosSistema = Import-DataList -FileName "procesos_sistema.json"

if($PuertosConocidos.Count -eq 0){
    Write-Log "Listado de puertos conocidos no disponible, la clasificacion puede ser menos precisa" -Level WARNING -LogFile $LogFile
    Add-ReportError -Report $script:report -Message "Listado puertos_conocidos.json no disponible o vacio" -Severity WARNING -Source TOOLKIT
}
if ($PuertosRiesgo.Count -eq 0) {
    Write-Log "Listado de puertos de riesgo no disponible, no se detectaran coincidencias por puerto." -Level ERROR -LogFile $LogFile
    Add-ReportError -Report $script:report -Message "Listado puertos_riesgo.json no disponible o vacio" -Severity WARNING -Source TOOLKIT
}
if (@($ProcesosSistema).Count -eq 0) {
    Write-Log "Listado de procesos de sistema no disponible, la clasificacion puede ser menos precisa." -Level WARNING -LogFile $LogFile
    Add-ReportError -Report $script:report -Message "Listado procesos_sistema.json no disponible o vacio" -Severity WARNING -Source TOOLKIT
}

#endregion

#region FUNCIONES INTERNAS

<#
.SYNOPSIS
    Obtiene el nombre del proceso dueño de una conexion por su PID.
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
        return [PSCustomObject]@{ Nivel = "ERROR"; Descripcion = $PuertosRiesgo[$Puerto] }
    }

    # Prioridad 2: conexion externa con proceso desconocido -> WARNING
    $esExterno   = -not (Test-IPLocal -IP $IPRemota)
    $esConfiable = $ProcesosSistema -contains $Proceso

    if ($esExterno -and -not $esConfiable) {
        return [PSCustomObject]@{ Nivel = "WARNING"; Descripcion = "Conexion externa - proceso no reconocido" }
    }

    # Prioridad 3: puerto conocido del sistema -> SUCCESS con descripcion
    if ($PuertosConocidos.ContainsKey($Puerto)) {
        return [PSCustomObject]@{ Nivel = "SUCCESS"; Descripcion = $PuertosConocidos[$Puerto] }
    }

    # Prioridad 4: conexion externa con proceso confiable -> INFO
    if ($esExterno -and $esConfiable) {
        return [PSCustomObject]@{ Nivel = "INFO"; Descripcion = "Conexion externa - proceso del sistema" }
    }

    # Default: conexion local o interna sin riesgo identificado -> INFO
    return [PSCustomObject]@{ Nivel = "INFO"; Descripcion = "Conexion local o interna" }

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

#endregion

try{

    #region RECOLECCION DE DATOS

    # Detectar prefijo IPv6 local desde las conexiones activas
    # Es mas confiable que tomarlo de Get-NetIPAddress porque hay multiples IPs IPv6
    # y la que usa para conectarse puede no ser la primera de la lista
    $primeraConexionIPv6 = $null
    try {
        $primeraConexionIPv6 = (Get-NetTCPConnection -State Established -ErrorAction Stop |
                Where-Object { $_.LocalAddress -match ':' -and $_.LocalAddress -notmatch '^(::1|fe80)' } |
                Select-Object -First 1).LocalAddress
    } catch {
        Write-Log "No se pudo detectar el prefijo IPv6 local: $($_.Exception.Message)" -Level WARNING -LogFile $LogFile
    }

    $ipv6Prefix = if ($primeraConexionIPv6) { $primeraConexionIPv6 -replace ':[^:]+$', ':' } else { "" }


    # Conexiones TCP establecidas
    $conexionesTCP = @()
    try {
        $conexionesTCP = @(Get-NetTCPConnection -State Established -ErrorAction Stop |
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
                } | Sort-Object Nivel -Descending)
    } catch {
        Write-Log "No se pudieron obtener las conexiones TCP: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al obtener conexiones TCP: $($_.Exception.Message)" -Severity ERROR -Source TOOLKIT
    }

    # Puertos TCP en escucha
    $puertosListen = @()
    try {
        $puertosListen = @(Get-NetTCPConnection -State Listen -ErrorAction Stop |
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
                } | Sort-Object Nivel -Descending)
    } catch {
        Write-Log "No se pudieron obtener los puertos en escucha: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al obtener puertos en escucha: $($_.Exception.Message)" -Severity ERROR -Source TOOLKIT
    }

    # Puertos UDP activos
    $puertosUDP = @()
    try {
        $puertosUDP = @(Get-NetUDPEndpoint -ErrorAction Stop |
                Sort-Object LocalPort -Unique |
                ForEach-Object {
                    $proceso = Get-NombreProceso -ProcessId $_.OwningProcess
                    [PSCustomObject]@{ Puerto = $_.LocalPort; Proceso = $proceso }
                })
    } catch {
        Write-Log "No se pudieron obtener los puertos UDP: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al obtener puertos UDP: $($_.Exception.Message)" -Severity ERROR -Source TOOLKIT
    }

    # -- Hallazgos de riesgo para el reporte --
    $hallazgosRiesgo = @($conexionesTCP + $puertosListen | Where-Object { $_.Nivel -eq "ERROR" })
    $hallazgosWarning = @($conexionesTCP | Where-Object { $_.Nivel -eq "WARNING" })

    foreach ($h in $hallazgosRiesgo) {
        $ref = if ($h.PSObject.Properties.Name -contains "Puerto") { "puerto $($h.Puerto)" } else { $h.RemoteEndpoint }
        Add-ReportError -Report $script:report -Message "Puerto de riesgo detectado ($ref, proceso: $($h.Proceso)): $($h.Descripcion)" -Severity ERROR -Source SYSTEM
    }
    foreach ($h in $hallazgosWarning) {
        Add-ReportError -Report $script:report -Message "Conexion externa sospechosa: $($h.RemoteEndpoint) (proceso: $($h.Proceso))" -Severity WARNING -Source SYSTEM
    }

    #endregion

    #region PRESENTACION

    Write-Section "PUERTOS Y CONEXIONES ACTIVAS" -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    # -- Seccion 1: Conexiones TCP activas --
    Write-Section "CONEXIONES TCP ACTIVAS" -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    # Separar conexiones externas de locales
    if ($conexionesTCP.Count -gt 0) {
        $tcpExternas = @($conexionesTCP | Where-Object { $_.Descripcion -ne "Conexion local o interna" })
        $tcpLocales  = @($conexionesTCP | Where-Object { $_.Descripcion -eq "Conexion local o interna" })

        # Agrupar externas por proceso
        if (@($tcpExternas).Count -gt 0) {
            Write-Log "Conexiones externas agrupadas por proceso:" -LogFile $LogFile
            Write-Blank -LogFile $LogFile

            # Ordenar por nivel de riesgo: ERROR > WARNING > INFO
            $tcpExternas | Group-Object Proceso | Sort-Object {
                $niveles = @{ ERROR = 0; WARNING = 1; INFO = 2; SUCCESS = 3 }
                ($_.Group | ForEach-Object { $niveles[$_.Nivel] } | Measure-Object -Minimum).Minimum
            } | ForEach-Object {
                $grupo    = $_
                $nivelMax = ($grupo.Group | Where-Object { $_.Nivel -eq "ERROR" } | Select-Object -First 1)
                if (-not $nivelMax) { $nivelMax = $grupo.Group | Where-Object { $_.Nivel -eq "WARNING" } | Select-Object -First 1 }
                if (-not $nivelMax) { $nivelMax = $grupo.Group[0] }

                $puertos = ($grupo.Group.RemoteEndpoint | ForEach-Object { ($_ -split ':')[-1] } | Sort-Object -Unique) -join ", "

                $linea = "{0,-25} {1,2} conexion(es) externa(s)  puertos remotos: {2}" -f `
                         $grupo.Name, $grupo.Count, $puertos
                Write-Log $linea -Level $nivelMax.Nivel -LogFile $LogFile
            }
            Write-Blank -LogFile $LogFile
        }

        # Conexiones locales - mostrar directo, son pocas y relevantes
        if (@($tcpLocales).Count -gt 0) {
            Write-Log "Conexiones locales:" -LogFile $LogFile
            Write-Blank -LogFile $LogFile
            foreach ($c in $tcpLocales) {
                $tagProceso = Get-CenteredTag -Text $c.Proceso -TotalWidth 8
                $linea = "{0,-22} <-> {1,-22} {2}" -f $c.LocalEndpoint, $c.RemoteEndpoint, $tagProceso
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

    if (@($puertosListen).Count -gt 0) {
        foreach ($p in $puertosListen) {
            $ProcesoMostrar = $p.Proceso
            if ($ProcesoMostrar.Length -gt 10 -and $ProcesoMostrar.Contains('.')) {
                $ProcesoMostrar = $ProcesoMostrar.Split('.')[0]
            }
            $tagProceso = Get-CenteredTag -Text $ProcesoMostrar -TotalWidth 10
            $linea = "Puerto {0,-6} {1} {2}" -f $p.Puerto, $tagProceso, $p.Descripcion
            Write-Log $linea -Level $p.Nivel -LogFile $LogFile
        }
    } else {
        Write-Log "Sin puertos en escucha detectados." -LogFile $LogFile
    }
    Write-Blank -LogFile $LogFile

    # -- Seccion 3: Puertos UDP --
    Write-Section "PUERTOS UDP ACTIVOS" -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    if (@($puertosUDP).Count -gt 0) {
        foreach ($p in $puertosUDP) {
            $tag = Get-CenteredTag -Text $p.Proceso -TotalWidth 9
            $linea = "Puerto {0,-6} {1}" -f $p.Puerto, $tag
            Write-Log $linea -LogFile $LogFile
        }
    } else {
        Write-Log "Sin puertos UDP activos." -LogFile $LogFile
    }
    Write-Blank -LogFile $LogFile

    #endregion

    #region REPORTE

    $script:report.data = @{
        totalConexionesTCP = @($conexionesTCP).Count
        totalPuertosListen = @($puertosListen).Count
        totalPuertosUDP    = @($puertosUDP).Count
        puertosRiesgo      = @($hallazgosRiesgo | Select-Object Proceso, Nivel, Descripcion, @{N='Referencia';E={ if ($_.PSObject.Properties.Name -contains "Puerto") { "puerto $($_.Puerto)" } else { $_.RemoteEndpoint } }})
        conexionesSospechosas = @($hallazgosWarning | Select-Object RemoteEndpoint, Proceso)
        puertosListen      = @($puertosListen | Select-Object Puerto, Proceso, Descripcion)
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