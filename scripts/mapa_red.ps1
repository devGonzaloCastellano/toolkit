<#
.SYNOPSIS
    Modulo de mapeo de red local.
.DESCRIPTION
    Muestra informacion de red del equipo actual, escanea dispositivos
    activos en el rango local via ping paralelo, muestra la tabla ARP
    con dispositivos recientes y lista recursos compartidos visibles.
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

$envInfo = Initialize-Environment -LogDir $LogDir -ModuleName "mapa_red"
$LogFile = $envInfo.LogFile

Set-CurrentExecution -ModuleName "mapa_red" -TxtPath $LogFile

$reportsDir = Join-Path (Split-Path $LogDir -Parent) "reports"
$reportFile = Get-ReportFileName -ReportsDir $reportsDir -ModuleName "mapa_red"
$script:report = New-ModuleReport -ModuleName "mapa_red"

#endregion

#region FUNCIONES INTERNAS

<#
.SYNOPSIS
    Determina si una direccion IP pertenece al rango APIPA.
.DESCRIPTION
    El rango 169.254.0.0/16 es asignado automaticamente por Windows
    cuando un equipo no logra obtener una IP via DHCP, indicando un
    problema de conectividad de red.
.PARAMETER IPAddress
    Direccion IP a evaluar.
.OUTPUTS
    [bool]
#>
function Test-IsApipa {
    param([string]$IPAddress)
    return $IPAddress -match '^169\.254\.'
}

<#
.SYNOPSIS
    Obtiene la informacion de red del equipo actual.
.OUTPUTS
    PSCustomObject con Nombre, IP, Mascara, Gateway y DNS.
#>
function Get-InfoEquipo{
    try    {
        $ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.IPAddress -notmatch '^127\.' } |
                Select-Object -First 1

        $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
                Sort-Object RouteMetric |
                Select-Object -First 1).NextHop

        $dns = (Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.ServerAddresses } |
                Select-Object -First 1).ServerAddresses -join ", "

        $ipStr = if ($ip) { $ip.IPAddress } else { $null }

        return [PSCustomObject]@{
            Nombre  = $env:COMPUTERNAME
            IP      = if ($ipStr) { $ipStr } else { "No detectada" }
            Mascara = if ($ip)    { "/$($ip.PrefixLength)" } else { "N/A" }
            Gateway = if ($gw)    { $gw } else { "No detectado" }
            DNS     = if ($dns)   { $dns } else { "No detectado" }
            EsApipa = if ($ipStr) { Test-IsApipa -IPAddress $ipStr } else { $false }
        }

    } catch {
        Write-Log "No se pudo obtener informacion de red del equipo: $( $_.Exception.Message )" -Level ERROR -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al obtener info de red del equipo: $( $_.Exception.Message )" -Severity ERROR -Source TOOLKIT
        return [PSCustomObject]@{
            Nombre = $env:COMPUTERNAME; IP = "No detectada"; Mascara = "N/A"
            Gateway = "No detectado"; DNS = "No detectado"; EsApipa = $false
        }
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

    if (-not $ipLocal) {
        Write-Log "No se pudo determinar la IP local, se omite el escaneo de red." -Level ERROR -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Sin IP local detectada, escaneo de red omitido" -Severity ERROR -Source TOOLKIT
        return @()
    }

    $prefijo = $ipLocal -replace '\.\d+$', ''

    Write-Log "Escaneando $prefijo.1 - $prefijo.254 ..." -Level NOTE -LogFile $LogFile
    Write-Log "Esto puede tardar unos segundos." -Level WARNING -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    # PS 7+ soporta ForEach-Object -Parallel
    # PS 5.1 usa Start-Job para paralelismo

    try{
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
    } catch {
        Write-Log "Error durante el escaneo de red: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo durante el escaneo de red: $($_.Exception.Message)" -Severity ERROR -Source TOOLKIT
        return @()
    }

    return @($resultados | ForEach-Object {
        [PSCustomObject]@{
            IP       = $_.IP
            Hostname = $_.Hostname
            EsApipa  = Test-IsApipa -IPAddress $_.IP
        }
    })
}

<#
.SYNOPSIS
    Obtiene la tabla ARP del sistema.
.OUTPUTS
    Array de PSCustomObject con IP, MAC e Interfaz.
#>
function Get-TablaARP {
    try {
        return @(Get-NetNeighbor -AddressFamily IPv4 -ErrorAction Stop |
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
                } | Sort-Object IP)
    } catch {
        Write-Log "No se pudo obtener la tabla ARP: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al obtener tabla ARP: $($_.Exception.Message)" -Severity ERROR -Source TOOLKIT
        return @()
    }
}

#endregion

try{

    #region RECOLECCION DE DATOS

    $infoEquipo = Get-InfoEquipo

    if ($infoEquipo.EsApipa) {
        Add-ReportError -Report $script:report -Message "El equipo tiene una IP APIPA ($($infoEquipo.IP)) - posible falla de DHCP" -Severity ERROR -Source SYSTEM
    }

    #endregion

    #region PRESENTACION

    Write-Section "MAPA DE RED LOCAL" -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    Write-Section "ESTE EQUIPO" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "Nombre  : $($infoEquipo.Nombre)"  -LogFile $LogFile
    Write-Log "IP      : $($infoEquipo.IP)" -Level $(if ($infoEquipo.EsApipa) { "ERROR" } else { "INFO" }) -LogFile $LogFile
    if ($infoEquipo.EsApipa) {
        Write-Log "          IP APIPA detectada - el equipo no esta recibiendo DHCP correctamente." -Level ERROR -LogFile $LogFile
    }
    Write-Log "Mascara : $($infoEquipo.Mascara)" -LogFile $LogFile
    Write-Log "Gateway : $($infoEquipo.Gateway)" -LogFile $LogFile
    Write-Log "DNS     : $($infoEquipo.DNS)"     -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    Write-Section "DISPOSITIVOS EN LA RED" -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    $dispositivos = @(Get-DispositivosRed)
    $dispositivosApipa = @($dispositivos | Where-Object { $_.EsApipa })

    if (@($dispositivos).Count -gt 0) {
        foreach ($d in $dispositivos) {
            $nivel = if ($d.EsApipa) { "WARNING" } else { "INFO" }
            $sufijo = if ($d.EsApipa) { " (APIPA)" } else { "" }
            $linea = "{0,-18} {1}{2}" -f $d.IP, $d.Hostname, $sufijo
            Write-Log $linea -Level $nivel -LogFile $LogFile
        }
        Write-Blank -LogFile $LogFile
        Write-Log "Total dispositivos activos: $(@($dispositivos).Count)" -Level SUCCESS -LogFile $LogFile

        if (@($dispositivosApipa).Count -gt 0) {
            Add-ReportError -Report $script:report -Message "$(@($dispositivosApipa).Count) dispositivo(s) en la red con IP APIPA" -Severity WARNING -Source SYSTEM
        }
    } else {
        Write-Log "No se detectaron dispositivos activos." -Level WARNING -LogFile $LogFile
    }
    Write-Blank -LogFile $LogFile

    Write-Section "TABLA ARP - DISPOSITIVOS RECIENTES" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log "Dispositivos con los que el equipo se comunico recientemente." -Level NOTE -LogFile $LogFile
    Write-Log "La MAC permite identificar el fabricante (router, celular, PC, etc)." -Level NOTE -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    $tablaARP = @(Get-TablaARP)

    if (@($tablaARP).Count -gt 0) {
        foreach ($entry in $tablaARP) {
            $tag = Get-CenteredTag $entry.Estado -TotalWidth 11
            $linea = "{0,-18} {1,-20} {2}" -f $entry.IP, $entry.MAC, $tag
            Write-Log $linea -LogFile $LogFile
        }
        Write-Blank -LogFile $LogFile
        Write-Log "Significado de los estados:" -Level NOTE -LogFile $LogFile
        Write-Log "  Reachable : confirmado activo recientemente, alta confianza." -Level NOTE -LogFile $LogFile
        Write-Log "  Stale     : se comunico en el pasado, pero no se confirmo si sigue activo ahora." -Level NOTE -LogFile $LogFile
        Write-Log "  Permanent : entrada fija del sistema (ej: broadcast), no es un dispositivo real." -Level NOTE -LogFile $LogFile
        Write-Blank -LogFile $LogFile
        Write-Log "Nota: esta tabla y el escaneo por ping pueden no coincidir. El ping requiere" -Level NOTE -LogFile $LogFile
        Write-Log "respuesta inmediata (celulares en reposo suelen no responder), mientras que" -Level NOTE -LogFile $LogFile
        Write-Log "la tabla ARP refleja comunicaciones pasadas. Ninguna de las dos por si sola" -Level NOTE -LogFile $LogFile
        Write-Log "confirma con certeza la ausencia de un dispositivo en la red." -Level NOTE -LogFile $LogFile
    } else {
        Write-Log "No se pudo obtener la tabla ARP." -Level WARNING -LogFile $LogFile
    }
    Write-Blank -LogFile $LogFile

    Write-Section "RECURSOS COMPARTIDOS DETECTADOS" -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    $recursosCompartidos = @()
    try {
        $recursos = net view 2>$null
        if ($recursos) {
            $recursos | ForEach-Object { Write-Log $_ -LogFile $LogFile }
            $recursosCompartidos = @($recursos)
        } else {
            Write-Log "No se detectaron recursos compartidos visibles." -LogFile $LogFile
        }
    } catch {
        Write-Log "No se pudieron obtener los recursos compartidos: $($_.Exception.Message)" -Level WARNING -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al obtener recursos compartidos: $($_.Exception.Message)" -Severity WARNING -Source TOOLKIT
    }
    Write-Blank -LogFile $LogFile

    #endregion

    #region REPORTE

    $script:report.data = @{
        infoEquipo           = $infoEquipo
        dispositivosDetectados = @($dispositivos | Select-Object IP, Hostname, EsApipa)
        totalDispositivos     = @($dispositivos).Count
        tablaARP              = $tablaARP
        recursosCompartidos   = $recursosCompartidos
    }

    $status = if (@($script:report.errors | Where-Object { $_.severity -eq "ERROR" }).Count -gt 0) { "ERROR" } else { "OK" }
    $script:report = Complete-ModuleReport -Report $script:report -Status $status

    #endregion

    #region GENERACION HTML

    $nivelResultado = if ($infoEquipo.EsApipa) { "ERROR" } else { "OK" }

    $textoRed = if ($infoEquipo.EsApipa) {
        "Este equipo no esta recibiendo una direccion de red valida (posible falla de router o cable)"
    } else {
        "Conexion de red funcionando correctamente"
    }

    $contentHtml = @"
    <h2>Estado de la red</h2>
    <p>$(New-HtmlBadge -Texto $textoRed -Nivel $nivelResultado)</p>
    <div class="metric"><div class="valor">$(@($dispositivos).Count)</div><div class="label">Dispositivos detectados en la red</div></div>

    <p style="font-size:13px; color:#666; margin-top:16px;">
        El conteo de dispositivos es aproximado: celulares y tablets en reposo suelen no
        responder a la deteccion, por lo que puede haber mas equipos conectados de los detectados.
    </p>
"@

    $reportFileHtml = Get-ReportFileName -ReportsDir $reportsDir -ModuleName "mapa_red" -Extension "html"
    Save-ModuleReportHtml -Report $script:report -ReportFile $reportFileHtml -TituloModulo "Mapa de Red" -ContentHtml $contentHtml -NivelOverride $nivelResultado
    #endregion

} catch {
    Write-Log "Error fatal en el modulo: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
    Add-ReportError -Report $script:report -Message $_.Exception.Message -Severity ERROR -Source TOOLKIT
    $script:report = Complete-ModuleReport -Report $script:report -Status "ERROR"
} finally {
    Save-ModuleReport -Report $script:report -ReportFile $reportFile}

#region SALIDA

Write-Section -LogFile $LogFile
Write-Log "Log guardado en: $LogFile" -LogFile $LogFile
Write-Blank

Invoke-Pause

#endregion