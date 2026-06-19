<#
.SYNOPSIS
    Modulo de auditoria de usuarios del sistema.
.DESCRIPTION
    Muestra cuentas locales, grupos y sus miembros, estado de la cuenta
    de invitado, sesiones activas y los ultimos inicios de sesion
    registrados en el log de eventos de seguridad de Windows.
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

$envInfo = Initialize-Environment -LogDir $LogDir -ModuleName "usuarios"
$LogFile = $envInfo.LogFile

#endregion

#region FUNCIONES INTERNAS

<#
.SYNOPSIS
    Obtiene todas las cuentas locales del sistema.
.OUTPUTS
    Array de PSCustomObject con Nombre, Habilitada y UltimoLogin.
#>
function Get-CuentasLocales {
    try {
        Get-LocalUser -ErrorAction Stop | ForEach-Object {
            $ultimoLogin = if ($_.LastLogon) {
                $_.LastLogon.ToString("yyyy-MM-dd HH:mm")
            } else {
                "Nunca"
            }
            [PSCustomObject]@{
                Nombre       = $_.Name
                Habilitada   = $_.Enabled
                UltimoLogin  = $ultimoLogin
            }
        }
    } catch {
        return @()
    }
}

<#
.SYNOPSIS
    Obtiene todos los grupos locales con sus miembros.
.OUTPUTS
    Array de PSCustomObject con Grupo y Miembros.
#>
function Get-GruposLocales {
    try {
        Get-LocalGroup -ErrorAction Stop | ForEach-Object {

            $grupo = $_.Name
            $miembros = try {
                (Get-LocalGroupMember -Group $grupo -ErrorAction Stop |
                        ForEach-Object {
                            ($_.Name -split '\\')[-1]
                        }) -join ", "
            } catch {
                "-"
            }
            [PSCustomObject]@{
                Grupo    = $grupo
                Miembros = if ($miembros) { $miembros } else { "-" }
            }
        }
    } catch {
        return @()
    }
}

<#
.SYNOPSIS
    Obtiene el estado de la cuenta de invitado (Guest/Invitado).
.OUTPUTS
    PSCustomObject con Nombre, Habilitada. Retorna $null si no existe.
#>
function Get-CuentaInvitado {
    try {
        Get-LocalUser -ErrorAction Stop |
                Where-Object { $_.Name -match '^(Guest|Invitado)$' } |
                Select-Object -First 1
    } catch {
        return $null
    }
}

<#
.SYNOPSIS
    Obtiene los ultimos inicios de sesion del log de eventos de seguridad.
.PARAMETER MaxEventos
    Cantidad maxima de eventos a retornar. Por defecto 10.
.OUTPUTS
    Array de PSCustomObject con Fecha, Usuario y TipoLogon.
#>
function Get-UltimosLogins {
    param([int]$MaxEventos = 10)

    # Tipos de logon mas comunes para referencia del tecnico:
    # 2 = Interactivo (consola), 3 = Red, 10 = Remoto (RDP), 11 = Credenciales en cache
    $tiposLogon = @{
        "2"  = "Interactivo"
        "3"  = "Red"
        "4"  = "Lote"
        "5"  = "Servicio"
        "7"  = "Desbloqueo"
        "8"  = "Red (texto plano)"
        "10" = "Remoto (RDP)"
        "11" = "Cache"
    }

    try {
        Get-WinEvent -FilterHashtable @{
            LogName = "Security"
            Id      = 4624
        } -MaxEvents $MaxEventos -ErrorAction Stop |
                ForEach-Object {
                    $xml     = [xml]$_.ToXml()
                    $datos   = $xml.Event.EventData.Data
                    $usuario = ($datos | Where-Object { $_.Name -eq "TargetUserName" }).'#text'
                    $tipo    = ($datos | Where-Object { $_.Name -eq "LogonType" }).'#text'

                    # Filtrar cuentas de sistema que no son relevantes para auditoria
                    if ($usuario -and $usuario -notmatch '^(SYSTEM|LOCAL SERVICE|NETWORK SERVICE|ANONYMOUS|\$)') {
                        [PSCustomObject]@{
                            Fecha    = $_.TimeCreated.ToString("yyyy-MM-dd HH:mm")
                            Usuario  = $usuario
                            Tipo     = if ($tiposLogon[$tipo]) { "$tipo - $($tiposLogon[$tipo])" } else { $tipo }
                        }
                    }
                } | Where-Object { $_ -ne $null }
    } catch {
        return @()
    }
}

#endregion

#region RECOLECCION DE DATOS

$cuentas      = Get-CuentasLocales
$grupos       = Get-GruposLocales
$invitado     = Get-CuentaInvitado
$ultimosLogin = Get-UltimosLogins -MaxEventos 10

#endregion

#region PRESENTACION

Write-Section "USUARIOS DEL SISTEMA" -LogFile $LogFile
Write-Blank -LogFile $LogFile

# -- Seccion 1: Cuentas locales --
Write-Section "CUENTAS LOCALES" -LogFile $LogFile
Write-Log "Se muestra el ultimo inicio de sesion registrado." -Level NOTE -LogFile $LogFile
Write-Blank -LogFile $LogFile

if ($cuentas) {

    $cuentasActivas   = @($cuentas | Where-Object { $_.Habilitada })
    $cuentasInactivas = @($cuentas | Where-Object { -not $_.Habilitada })

    Write-Log "Activas ($($cuentasActivas.Count))" -Level SUCCESS -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    foreach ($cuenta in $cuentasActivas) {
        $linea = "{0,-20} {1}" -f $cuenta.Nombre, $cuenta.UltimoLogin
        Write-Log $linea -LogFile $LogFile
    }

    Write-Blank -LogFile $LogFile

    Write-Log "Inactivas ($($cuentasInactivas.Count))" -Level INFO -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    foreach ($cuenta in $cuentasInactivas) {
        $linea = "{0,-20} {1}" -f $cuenta.Nombre, $cuenta.UltimoLogin
        Write-Log $linea -LogFile $LogFile
    }
} else {
    Write-Log "No se pudieron obtener las cuentas locales." -Level WARNING -LogFile $LogFile
}
Write-Blank -LogFile $LogFile

# -- Seccion 2: Grupos y miembros --
Write-Section "GRUPOS Y MIEMBROS" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "Importante: un usuario desconocido en Administradores es alerta critica." -Level WARNING -LogFile $LogFile
Write-Log "Equipo auditado: $env:COMPUTERNAME" -Level NOTE -LogFile $LogFile
Write-Blank -LogFile $LogFile

$gruposConMiembros = @($grupos | Where-Object { $_.Miembros -ne "-" })
$gruposSinMiembros = @($grupos | Where-Object { $_.Miembros -eq "-" })

Write-Log "Grupos con miembros ($($gruposConMiembros.Count))" -Level SUCCESS -LogFile $LogFile
Write-Blank -LogFile $LogFile

foreach ($grupo in $gruposConMiembros) {
    $linea = "{0,-50} {1}" -f $grupo.Grupo, $grupo.Miembros
    Write-Log $linea -Level INFO -LogFile $LogFile
}

Write-Blank -LogFile $LogFile

Write-Log "Grupos sin miembros ($($gruposSinMiembros.Count))" -Level INFO -LogFile $LogFile
Write-Blank -LogFile $LogFile

foreach ($grupo in $gruposSinMiembros) {
    $linea = "{0,-50} -" -f $grupo.Grupo
    Write-Log $linea -Level INFO -LogFile $LogFile
}
Write-Blank -LogFile $LogFile

# -- Seccion 3: Cuenta de invitado --
Write-Section "CUENTA DE INVITADO" -LogFile $LogFile
Write-Blank -LogFile $LogFile

if ($invitado) {
    if ($invitado.Enabled) {
        Write-Log "ATENCION: Cuenta de invitado HABILITADA: $($invitado.Name)" -Level ERROR -LogFile $LogFile
    } else {
        Write-Log "OK: Cuenta de invitado deshabilitada ($($invitado.Name))" -Level SUCCESS -LogFile $LogFile
    }
} else {
    Write-Log "Cuenta de invitado no encontrada." -LogFile $LogFile
}
Write-Blank -LogFile $LogFile

# -- Seccion 4: Sesiones activas --
Write-Section "SESIONES ACTIVAS" -LogFile $LogFile
Write-Blank -LogFile $LogFile


try {
    $sesiones = query user 2>$null | Select-Object -Skip 1
    if ($sesiones) {
        foreach ($linea in $sesiones) {
            $linea = $linea.TrimStart('>')

            if ($linea -match '^(\S+)\s+(\S+)\s+(\d+)\s+(\S+)') {
                $usuario = $matches[1]
                $sesion  = $matches[2]
                $estado  = $matches[4]

                $texto = "{0,-10} {1,-10} {2}" -f $usuario, $estado, $sesion
                Write-Log "Sesiones detectadas: $($sesiones.Count)" -Level SUCCESS -LogFile $LogFile
                Write-Log $texto -LogFile $LogFile
            }
        }
    } else {
        Write-Log "Sin sesiones activas detectadas." -LogFile $LogFile
    }
} catch {
    Write-Log "No se pudieron obtener las sesiones activas." -Level WARNING -LogFile $LogFile
}
Write-Blank -LogFile $LogFile

# -- Seccion 5: Ultimos logins --
Write-Section "ULTIMOS 10 INICIOS DE SESION" -LogFile $LogFile
Write-Blank -LogFile $LogFile

if ($ultimosLogin) {
    foreach ($login in $ultimosLogin) {
        $linea = "{0}  Usuario: {1,-20}  Tipo: {2}" -f $login.Fecha, $login.Usuario, $login.Tipo
        Write-Log $linea -LogFile $LogFile
    }
} else {
    Write-Log "No se pudieron obtener los eventos de seguridad." -Level WARNING -LogFile $LogFile
    Write-Log "Posibles causas:" -Level NOTE -LogFile $LogFile
    Write-Log "  - El log de auditoria de seguridad no esta habilitado." -Level NOTE -LogFile $LogFile
    Write-Log "  - Politica de grupo restringe el acceso al log." -Level NOTE -LogFile $LogFile
    Write-Log "  - Para habilitarlo: secpol.msc > Directivas locales > Auditoria" -Level NOTE -LogFile $LogFile
}
Write-Blank -LogFile $LogFile

#endregion

#region RESUMEN

Write-Section -LogFile $LogFile
Write-Log "Log guardado en: $LogFile" -LogFile $LogFile
Write-Blank

Invoke-Pause

#endregion