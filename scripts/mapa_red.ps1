<#
.SYNOPSIS
    Modulo de mapeo de red local.
.DESCRIPTION
    Muestra informacion de red del equipo actual, escanea dispositivos
    activos en el rango local via ping paralelo, muestra la tabla ARP
    con dispositivos recientes y lista recursos compartidos visibles.
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

$envInfo = Initialize-Environment -LogDir $LogDir -ModuleName "mapa_red"
$LogFile = $envInfo.LogFile

#endregion

#region FUNCIONES INTERNAS

<#
.SYNOPSIS
    Obtiene la informacion de red del equipo actual.
.OUTPUTS
    PSCustomObject con Nombre, IP, Mascara, Gateway y DNS.
#>
function Get-InfoEquipo {
    $ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notmatch '^127\.' } |
            Select-Object -First 1

    $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Sort-Object RouteMetric |
            Select-Object -First 1).NextHop

    $dns = (Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.ServerAddresses } |
            Select-Object -First 1).ServerAddresses -join ", "

    return [PSCustomObject]@{
        Nombre  = $env:COMPUTERNAME
        IP      = if ($ip)  { $ip.IPAddress }       else { "No detectada" }
        Mascara = if ($ip)  { "/$($ip.PrefixLength)" } else { "N/A" }
        Gateway = if ($gw)  { $gw }                 else { "No detectado" }
        DNS     = if ($dns) { $dns }                 else { "No detectado" }
    }
}

<#
.SYNOPSIS
    Escanea el rango IPv4 local haciendo ping paralelo.
.DESCRIPTION
    Detecta el prefijo de red desde la IP local y hace ping a las 254
    direcciones del rango. Usa jobs paralelos para reducir el tiempo
    de escaneo de varios minutos a aproximadamente 30-60 segundos.
.OUTPUTS
    Array de PSCustomObject con IP y Hostname de los dispositivos activos.
#>
function Get-DispositivosRed {
    $ipLocal = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notmatch '^127\.' } |
            Select-Object -First 1).IPAddress

    if (-not $ipLocal) { return @() }

    $prefijo = $ipLocal -replace '\.\d+$', ''

    Write-Log "Escaneando $prefijo.1 - $prefijo.254 ..." -LogFile $LogFile
    Write-Log "Esto puede tardar 30-60 segundos." -Level WARNING -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    # PS 7+ soporta ForEach-Object -Parallel
    # PS 5.1 usa Start-Job para paralelismo
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $resultados = 1..254 | ForEach-Object -ThrottleLimit 50 -Parallel {
            $ip   = "$using:prefijo.$_"
            $ping = Test-Connection -ComputerName $ip -Count 1 -TimeoutSeconds 1 -Quiet -ErrorAction SilentlyContinue
            if ($ping) {
                $hostname = try { [System.Net.Dns]::GetHostEntry($ip).HostName } catch { "sin nombre" }
                [PSCustomObject]@{ IP = $ip; Hostname = $hostname }
            }
        } | Where-Object { $_ -ne $null } | Sort-Object { [Version]$_.IP }

    } else {
        # Start-Job en lotes de 50 para no saturar el sistema
        $tamanoLote = 50
        $resultados = @()

        for ($i = 1; $i -le 254; $i += $tamanoLote) {
            $fin  = [math]::Min($i + $tamanoLote - 1, 254)
            $jobs = $i..$fin | ForEach-Object {
                $ip = "$prefijo.$_"
                Start-Job -ScriptBlock {
                    param($ip)
                    $ping   = New-Object System.Net.NetworkInformation.Ping
                    $result = $ping.Send($ip, 500)
                    if ($result.Status -eq 'Success') {
                        $hostname = try { [System.Net.Dns]::GetHostEntry($ip).HostName } catch { "sin nombre" }
                        [PSCustomObject]@{ IP = $ip; Hostname = $hostname }
                    }
                } -ArgumentList $ip
            }

            # Esperar que terminen todos los jobs del lote
            $jobs | Wait-Job | Out-Null
            $resultados += $jobs | Receive-Job | Where-Object { $_ -ne $null }
            $jobs | Remove-Job
        }

        $resultados = $resultados | Sort-Object { [Version]$_.IP }
    }

    return $resultados
}

<#
.SYNOPSIS
    Obtiene la tabla ARP del sistema.
.OUTPUTS
    Array de PSCustomObject con IP, MAC e Interfaz.
#>
function Get-TablaARP {
    try {
        Get-NetNeighbor -AddressFamily IPv4 -ErrorAction Stop |
                Where-Object {
                    $_.State -ne 'Unreachable' -and
                            $_.LinkLayerAddress -ne '00-00-00-00-00-00' -and
                            $_.IPAddress -notmatch '^(224\.|239\.|255\.)'
                } |
                ForEach-Object {
                    [PSCustomObject]@{
                        IP        = $_.IPAddress
                        MAC       = $_.LinkLayerAddress
                        Estado    = $_.State.ToString()
                    }
                } | Sort-Object IP
    } catch {
        return @()
    }
}

#endregion

#region RECOLECCION DE DATOS

$infoEquipo = Get-InfoEquipo

#endregion

#region PRESENTACION

Write-Section "MAPA DE RED LOCAL" -LogFile $LogFile
Write-Blank -LogFile $LogFile

# -- Seccion 1: Info del equipo --
Write-Section "ESTE EQUIPO" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "Nombre  : $($infoEquipo.Nombre)"  -LogFile $LogFile
Write-Log "IP      : $($infoEquipo.IP)"      -LogFile $LogFile
Write-Log "Mascara : $($infoEquipo.Mascara)" -LogFile $LogFile
Write-Log "Gateway : $($infoEquipo.Gateway)" -LogFile $LogFile
Write-Log "DNS     : $($infoEquipo.DNS)"     -LogFile $LogFile
Write-Blank -LogFile $LogFile

# -- Seccion 2: Escaneo de dispositivos --
Write-Section "DISPOSITIVOS EN LA RED" -LogFile $LogFile
Write-Blank -LogFile $LogFile

$dispositivos = Get-DispositivosRed

if ($dispositivos) {
    foreach ($d in $dispositivos) {
        $linea = "{0,-18} {1}" -f $d.IP, $d.Hostname
        Write-Log $linea -LogFile $LogFile
    }
    Write-Blank -LogFile $LogFile
    Write-Log "Total dispositivos activos: $($dispositivos.Count)" -Level SUCCESS -LogFile $LogFile
} else {
    Write-Log "No se detectaron dispositivos activos." -Level WARNING -LogFile $LogFile
}
Write-Blank -LogFile $LogFile

# -- Seccion 3: Tabla ARP --
Write-Section "TABLA ARP - DISPOSITIVOS RECIENTES" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "Dispositivos con los que el equipo se comunico recientemente." -LogFile $LogFile
Write-Log "La MAC permite identificar el fabricante (router, celular, PC, etc)." -LogFile $LogFile
Write-Blank -LogFile $LogFile

$tablaARP = Get-TablaARP

if ($tablaARP) {
    foreach ($entry in $tablaARP) {
        $linea = "{0,-18} {1,-20} [{2}]" -f $entry.IP, $entry.MAC, $entry.Estado
        Write-Log $linea -LogFile $LogFile
    }
} else {
    Write-Log "No se pudo obtener la tabla ARP." -Level WARNING -LogFile $LogFile
}
Write-Blank -LogFile $LogFile

# -- Seccion 4: Recursos compartidos --
Write-Section "RECURSOS COMPARTIDOS DETECTADOS" -LogFile $LogFile
Write-Blank -LogFile $LogFile

try {
    $recursos = net view 2>$null
    if ($recursos) {
        $recursos | ForEach-Object { Write-Log $_ -LogFile $LogFile }
    } else {
        Write-Log "No se detectaron recursos compartidos visibles." -LogFile $LogFile
    }
} catch {
    Write-Log "No se pudieron obtener los recursos compartidos." -Level WARNING -LogFile $LogFile
}
Write-Blank -LogFile $LogFile

#endregion

#region RESUMEN

Write-Section -LogFile $LogFile
Write-Log "Log guardado en: $LogFile" -LogFile $LogFile
Write-Blank

Invoke-Pause

#endregion