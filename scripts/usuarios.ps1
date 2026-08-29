<#
.SYNOPSIS
    Modulo de auditoria de usuarios del sistema.
.DESCRIPTION
    Muestra cuentas locales, grupos y sus miembros, estado de la cuenta
    de invitado, sesiones activas y los ultimos inicios de sesion
    registrados en el log de eventos de seguridad de Windows.
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

$envInfo = Initialize-Environment -LogDir $LogDir -ModuleName "usuarios"
$LogFile = $envInfo.LogFile

Set-CurrentExecution -ModuleName "usuarios" -TxtPath $LogFile

$reportsDir = Join-Path (Split-Path $LogDir -Parent) "reports"
$reportFile = Get-ReportFileName -ReportsDir $reportsDir -ModuleName "usuarios"
$script:report = New-ModuleReport -ModuleName "usuarios"

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
        return @(Get-LocalUser -ErrorAction Stop | ForEach-Object {
            $ultimoLogin = if ($_.LastLogon) { $_.LastLogon.ToString("yyyy-MM-dd HH:mm") } else { "Nunca" }
            [PSCustomObject]@{
                Nombre      = $_.Name
                Habilitada  = $_.Enabled
                UltimoLogin = $ultimoLogin
            }
        })
    } catch {
        Write-Log "No se pudieron obtener las cuentas locales: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al obtener cuentas locales: $($_.Exception.Message)" -Severity ERROR -Source TOOLKIT
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
        return @(Get-LocalGroup -ErrorAction Stop | ForEach-Object {
            $grupo    = $_.Name
            $miembros = try {
                (Get-LocalGroupMember -Group $grupo -ErrorAction Stop |
                        ForEach-Object { ($_.Name -split '\\')[-1] }) -join ", "
            } catch {
                "-"
            }
            [PSCustomObject]@{
                Grupo    = $grupo
                Miembros = if ($miembros) { $miembros } else { "-" }
            }
        })
    } catch {
        Write-Log "No se pudieron obtener los grupos locales: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al obtener grupos locales: $($_.Exception.Message)" -Severity ERROR -Source TOOLKIT
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
        return Get-LocalUser -ErrorAction Stop |
                Where-Object { $_.Name -match '^(Guest|Invitado)$' } |
                Select-Object -First 1
    } catch {
        Write-Log "No se pudo verificar la cuenta de invitado: $($_.Exception.Message)" -Level ERROR -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al verificar cuenta de invitado: $($_.Exception.Message)" -Severity ERROR -Source TOOLKIT
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
        "2" = "Interactivo"; "3" = "Red"; "4" = "Lote"; "5" = "Servicio"
        "7" = "Desbloqueo"; "8" = "Red (texto plano)"; "10" = "Remoto (RDP)"; "11" = "Cache"
    }

    try {
        return @(Get-WinEvent -FilterHashtable @{ LogName = "Security"; Id = 4624 } -MaxEvents $MaxEventos -ErrorAction Stop |
                ForEach-Object {
                    $xml     = [xml]$_.ToXml()
                    $datos   = $xml.Event.EventData.Data
                    $usuario = ($datos | Where-Object { $_.Name -eq "TargetUserName" }).'#text'
                    $tipo    = ($datos | Where-Object { $_.Name -eq "LogonType" }).'#text'

                    if ($usuario -and $usuario -notmatch '^(SYSTEM|LOCAL SERVICE|NETWORK SERVICE|ANONYMOUS|\$)') {
                        [PSCustomObject]@{
                            Fecha   = $_.TimeCreated.ToString("yyyy-MM-dd HH:mm")
                            Usuario = $usuario
                            Tipo    = if ($tiposLogon[$tipo]) { "$tipo - $($tiposLogon[$tipo])" } else { $tipo }
                        }
                    }
                } | Where-Object { $_ -ne $null })
    } catch {
        Write-Log "No se pudieron obtener los eventos de seguridad: $($_.Exception.Message)" -Level WARNING -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al obtener eventos de logon (posible auditoria deshabilitada): $($_.Exception.Message)" -Severity WARNING -Source TOOLKIT
        return @()
    }

}

#endregion

try{

    #region RECOLECCION DE DATOS

    $cuentas      = Get-CuentasLocales
    $grupos       = Get-GruposLocales
    $invitado     = Get-CuentaInvitado
    $ultimosLogin = Get-UltimosLogins -MaxEventos 10

    if ($invitado -and $invitado.Enabled) {
        Add-ReportError -Report $script:report -Message "Cuenta de invitado habilitada: $($invitado.Name)" -Severity ERROR -Source SYSTEM
    }

    #endregion

    #region PRESENTACION

    Write-Section "USUARIOS DEL SISTEMA" -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    # -- Seccion 1: Cuentas locales --
    Write-Section "CUENTAS LOCALES" -LogFile $LogFile
    Write-Log "Se muestra el ultimo inicio de sesion registrado." -Level NOTE -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    if (@($cuentas).Count -gt 0) {
        $cuentasActivas   = @($cuentas | Where-Object { $_.Habilitada })
        $cuentasInactivas = @($cuentas | Where-Object { -not $_.Habilitada })

        Write-Log "Activas ($($cuentasActivas.Count))" -Level SUCCESS -LogFile $LogFile
        Write-Blank -LogFile $LogFile
        foreach ($cuenta in $cuentasActivas) {
            Write-Log ("{0,-20} {1}" -f $cuenta.Nombre, $cuenta.UltimoLogin) -LogFile $LogFile
        }
        Write-Blank -LogFile $LogFile

        Write-Log "Inactivas ($($cuentasInactivas.Count))" -Level INFO -LogFile $LogFile
        Write-Blank -LogFile $LogFile
        foreach ($cuenta in $cuentasInactivas) {
            Write-Log ("{0,-20} {1}" -f $cuenta.Nombre, $cuenta.UltimoLogin) -LogFile $LogFile
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
        Write-Log ("{0,-50} {1}" -f $grupo.Grupo, $grupo.Miembros) -Level INFO -LogFile $LogFile
    }
    Write-Blank -LogFile $LogFile

    Write-Log "Grupos sin miembros ($($gruposSinMiembros.Count))" -Level INFO -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    foreach ($grupo in $gruposSinMiembros) {
        Write-Log ("{0,-50} -" -f $grupo.Grupo) -Level INFO -LogFile $LogFile
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

    $sesionesParsed = @()
    try {
        $sesiones = query user 2>$null | Select-Object -Skip 1
        if ($sesiones) {
            Write-Log "Sesiones detectadas: $(@($sesiones).Count)" -Level SUCCESS -LogFile $LogFile
            foreach ($linea in $sesiones) {
                $linea = $linea.TrimStart('>')
                if ($linea -match '^(\S+)\s+(\S+)\s+(\d+)\s+(\S+)') {
                    $usuario = $matches[1]
                    $sesion  = $matches[2]
                    $estado  = $matches[4]
                    Write-Log ("{0,-10} {1,-10} {2}" -f $usuario, $estado, $sesion) -LogFile $LogFile
                    $sesionesParsed += [PSCustomObject]@{ Usuario = $usuario; Sesion = $sesion; Estado = $estado }
                }
            }
        } else {
            Write-Log "Sin sesiones activas detectadas." -LogFile $LogFile
        }
    } catch {
        Write-Log "No se pudieron obtener las sesiones activas: $($_.Exception.Message)" -Level WARNING -LogFile $LogFile
        Add-ReportError -Report $script:report -Message "Fallo al obtener sesiones activas: $($_.Exception.Message)" -Severity WARNING -Source TOOLKIT
    }
    Write-Blank -LogFile $LogFile

    # -- Seccion 5: Ultimos logins --
    Write-Section "ULTIMOS 10 INICIOS DE SESION" -LogFile $LogFile
    Write-Blank -LogFile $LogFile

    if (@($ultimosLogin).Count -gt 0) {
        foreach ($login in $ultimosLogin) {
            Write-Log ("{0}  Usuario: {1,-20}  Tipo: {2}" -f $login.Fecha, $login.Usuario, $login.Tipo) -LogFile $LogFile
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

    #region REPORTE

    $script:report.data = @{
        cuentas = @{
            activas   = @($cuentasActivas   | Select-Object Nombre, UltimoLogin)
            inactivas = @($cuentasInactivas | Select-Object Nombre, UltimoLogin)
        }
        grupos = @($grupos | Select-Object Grupo, Miembros)
        cuentaInvitado = if ($invitado) { @{ nombre = $invitado.Name; habilitada = $invitado.Enabled } } else { $null }
        sesionesActivas = @($sesionesParsed)
        ultimosLogins   = @($ultimosLogin)
    }

    $status = if (@($script:report.errors | Where-Object { $_.severity -eq "ERROR" }).Count -gt 0) { "ERROR" } else { "OK" }
    $script:report = Complete-ModuleReport -Report $script:report -Status $status

    #endregion

    #region GENERACION HTML

    $invitadoHabilitado = $invitado -and $invitado.Enabled
    $adminGroup = $grupos | Where-Object { $_.Grupo -eq "Administradores" }
    $adminMiembros = if ($adminGroup) { $adminGroup.Miembros } else { "-" }

    $healthScore = 100
    if ($invitadoHabilitado) { $healthScore -= 50 }
    if ($healthScore -lt 0) { $healthScore = 0 }

    $script:report.healthScore = $healthScore
    $nivelSalud = if ($invitadoHabilitado) { "ERROR" } else { "OK" }

    $seccionInvitado = if ($invitadoHabilitado) {
        @"
    <h2>Alerta de seguridad</h2>
    <p style="font-size:13px; color:#c62828; font-weight:bold;">
        La cuenta de invitado esta habilitada. Esto permite el acceso al equipo sin
        contraseña. Se recomienda deshabilitarla salvo que sea un uso intencional.
    </p>
"@
    } else {
        "<h2>Seguridad</h2><p>$(New-HtmlBadge -Texto "Cuenta de invitado deshabilitada" -Nivel OK)</p>"
    }

    $contentHtml = @"
    <h2>Resumen</h2>
    <div class="metric"><div class="valor">$(@($cuentasActivas).Count)</div><div class="label">Cuentas activas</div></div>
    <div class="metric"><div class="valor">$(@($sesionesParsed).Count)</div><div class="label">Sesiones activas</div></div>
    $seccionInvitado

    <h2>Administradores del equipo</h2>
    <p style="font-size:13px;">Las siguientes cuentas tienen permisos de administrador. Verifique
    que reconoce a todas:</p>
    <p>$adminMiembros</p>
"@

    $reportFileHtml = Get-ReportFileName -ReportsDir $reportsDir -ModuleName "usuarios" -Extension "html"
    Save-ModuleReportHtml -Report $script:report -ReportFile $reportFileHtml -TituloModulo "Usuarios del Equipo" -ContentHtml $contentHtml -NivelOverride $nivelSalud

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