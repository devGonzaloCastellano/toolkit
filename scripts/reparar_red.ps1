<#
.SYNOPSIS
    Modulo de reparacion de red.
.DESCRIPTION
    Ejecuta una secuencia de pasos para reparar problemas de conectividad:
    flush DNS, liberacion y renovacion de IP, reset Winsock, reset TCP/IP
    y limpieza de configuracion de proxy. Muestra diagnostico antes y
    despues de la reparacion para verificar el resultado.
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

$envInfo = Initialize-Environment -LogDir $LogDir -ModuleName "reparar_red"
$LogFile = $envInfo.LogFile

#endregion

#region FUNCIONES INTERNAS

<#
.SYNOPSIS
    Obtiene el estado actual de la red: IP local, gateway y conectividad.
.OUTPUTS
    PSCustomObject con IPLocal, Gateway y Conectividad.
#>
function Get-EstadoRed {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notmatch '^127\.' } |
            Select-Object -First 1).IPAddress

    $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Sort-Object RouteMetric |
            Select-Object -First 1).NextHop

    $ping = Test-Connection -ComputerName "8.8.8.8" -Count 2 -Quiet -ErrorAction SilentlyContinue

    return [PSCustomObject]@{
        IPLocal      = if ($ip) { $ip } else { "No detectada" }
        Gateway      = if ($gw) { $gw } else { "No detectado" }
        Conectividad = if ($ping) { "OK" } else { "SIN CONECTIVIDAD" }
    }
}

<#
.SYNOPSIS
    Muestra el estado de red en consola y log.
.PARAMETER Estado
    PSCustomObject retornado por Get-EstadoRed.
#>
function Show-EstadoRed {
    param($Estado)

    $nivelConec = if ($Estado.Conectividad -eq "OK") { "SUCCESS" } else { "ERROR" }

    Write-Log "IP local     : $($Estado.IPLocal)"      -LogFile $LogFile
    Write-Log "Gateway      : $($Estado.Gateway)"      -LogFile $LogFile
    Write-Log "Internet     : $($Estado.Conectividad)" -Level $nivelConec -LogFile $LogFile
}

<#
.SYNOPSIS
    Ejecuta un paso de reparacion y loguea el resultado.
.PARAMETER Numero
    Numero de paso para mostrar en el encabezado.
.PARAMETER Total
    Total de pasos.
.PARAMETER Titulo
    Titulo del paso.
.PARAMETER Descripcion
    Explicacion de que hace este paso y por que.
.PARAMETER Accion
    ScriptBlock con la logica del paso.
#>
function Invoke-PasoReparacion {
    param(
        [int]$Numero,
        [int]$Total,
        [string]$Titulo,
        [string]$Descripcion,
        [scriptblock]$Accion
    )

    Write-Blank -LogFile $LogFile
    Write-Log "[$Numero/$Total] $Titulo" -Level INFO -LogFile $LogFile
    Write-Log $Descripcion -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    try {
        & $Accion
        Write-Log "OK." -Level SUCCESS -LogFile $LogFile
    } catch {
        Write-Log "Error: $_" -Level ERROR -LogFile $LogFile
    }
}

#endregion

#region LOGICA PRINCIPAL

Write-Section "REPARACION DE RED" -LogFile $LogFile
Write-Blank -LogFile $LogFile

# -- Diagnostico previo --
Write-Section "ESTADO PREVIO" -LogFile $LogFile
Write-Blank -LogFile $LogFile
$estadoPrevio = Get-EstadoRed
Show-EstadoRed -Estado $estadoPrevio
Write-Blank -LogFile $LogFile

# -- Pasos de reparacion --
Write-Section "REPARACION" -LogFile $LogFile

$totalPasos = 5

Invoke-PasoReparacion -Numero 1 -Total $totalPasos `
    -Titulo "Flush DNS" `
    -Descripcion "Elimina respuestas DNS en cache. Util cuando un sitio cambio de IP o hay respuestas incorrectas guardadas." `
    -Accion { Clear-DnsClientCache -ErrorAction Stop }

Invoke-PasoReparacion -Numero 2 -Total $totalPasos `
    -Titulo "Liberar y renovar IP" `
    -Descripcion "Devuelve la IP al router y solicita una nueva. Util cuando hay conflictos de IP o el equipo no obtiene direccion automaticamente." `
    -Accion {
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
    foreach ($adapter in $adapters) {
        $null = ipconfig /release $adapter.Name 2>$null
    }
    $null = ipconfig /renew 2>$null
}

Invoke-PasoReparacion -Numero 3 -Total $totalPasos `
    -Titulo "Reset Winsock" `
    -Descripcion "Restaura la interfaz de red de Windows. Se puede corromper por malware o instalaciones de VPN/proxy mal removidas." `
    -Accion { netsh winsock reset | Out-Null }

Invoke-PasoReparacion -Numero 4 -Total $totalPasos `
    -Titulo "Reset TCP/IP" `
    -Descripcion "Restaura la configuracion TCP/IP a valores de fabrica. Mas profundo que el reset Winsock, afecta toda la pila de red." `
    -Accion { netsh int ip reset | Out-Null }

Invoke-PasoReparacion -Numero 5 -Total $totalPasos `
    -Titulo "Limpiar configuracion de proxy" `
    -Descripcion "Elimina configuracion de proxy del sistema. Algunos malware configuran un proxy para interceptar trafico." `
    -Accion {
    netsh winhttp reset proxy | Out-Null
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" `
            -Name "ProxyEnable" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" `
            -Name "ProxyServer" -ErrorAction SilentlyContinue
}

# -- Diagnostico posterior --
Write-Blank -LogFile $LogFile
Write-Section "ESTADO POST-REPARACION" -LogFile $LogFile
Write-Blank -LogFile $LogFile
$estadoPost = Get-EstadoRed
Show-EstadoRed -Estado $estadoPost
Write-Blank -LogFile $LogFile

# -- Advertencia de reinicio --
if ($estadoPost.Conectividad -ne "OK") {
    Write-Log "Sin conectividad luego del reset." -Level WARNING -LogFile $LogFile
    Write-Log "Reiniciar el equipo para aplicar los cambios correctamente." -Level WARNING -LogFile $LogFile
} else {
    Write-Log "Reparacion completada con conectividad restaurada." -Level SUCCESS -LogFile $LogFile
}
Write-Blank -LogFile $LogFile
Write-Log "IMPORTANTE: Reiniciar el equipo para aplicar Winsock y TCP/IP correctamente." -Level WARNING -LogFile $LogFile

#endregion

#region RESUMEN

Write-Blank -LogFile $LogFile
Write-Section -LogFile $LogFile
Write-Log "Log guardado en: $LogFile" -LogFile $LogFile
Write-Blank

Invoke-Pause

#endregion