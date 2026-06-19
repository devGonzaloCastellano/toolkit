<#
.SYNOPSIS
    Modulo de reparacion de Windows Update.
.DESCRIPTION
    Ejecuta una secuencia de pasos para reparar Windows Update cuando
    falla, se congela o no encuentra actualizaciones. Detiene servicios,
    limpia cache, resetea componentes de red y re-registra DLLs.
    Al finalizar reinicia los servicios y el sistema queda listo para
    buscar actualizaciones nuevamente.
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

$envInfo = Initialize-Environment -LogDir $LogDir -ModuleName "reparar_windows_update"
$LogFile = $envInfo.LogFile

#endregion

#region DATOS - DLLS DE WINDOWS UPDATE

# DLLs que Windows Update necesita registradas correctamente para funcionar.
# Se re-registran con regsvr32 para reparar instalaciones corruptas.
$DllsUpdate = @(
    "atl.dll", "urlmon.dll", "mshtml.dll",
    "shdocvw.dll", "browseui.dll",
    "jscript.dll", "vbscript.dll",
    "scrrun.dll", "msxml.dll", "msxml3.dll", "msxml6.dll",
    "actxprxy.dll", "softpub.dll", "wintrust.dll",
    "dssenh.dll", "rsaenh.dll", "gpkcsp.dll", "sccbase.dll",
    "slbcsp.dll", "cryptdlg.dll", "oleaut32.dll", "ole32.dll",
    "shell32.dll", "wuapi.dll", "wuaueng.dll", "wuaueng1.dll",
    "wucltui.dll", "wups.dll", "wups2.dll", "wuweb.dll",
    "qmgr.dll", "qmgrprxy.dll", "wucltux.dll", "muweb.dll",
    "wuwebv.dll"
)

# Servicios de Windows Update que deben detenerse antes de limpiar
# y reiniciarse al finalizar
$ServiciosUpdate = @("wuauserv", "cryptSvc", "bits", "msiserver")

#endregion

#region FUNCIONES INTERNAS

<#
.SYNOPSIS
    Ejecuta un paso de reparacion y loguea el resultado.
    Reutiliza el mismo patron que reparar_red.ps1.
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
    Write-Log "[$Numero/$Total] $Titulo" -LogFile $LogFile
    Write-Blank -LogFile $LogFile
    Write-Log $Descripcion -Level NOTE -LogFile $LogFile
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

Write-Section "REPARACION DE WINDOWS UPDATE" -LogFile $LogFile
Write-Blank -LogFile $LogFile

$totalPasos = 6

# -- Paso 1: Detener servicios --
Invoke-PasoReparacion -Numero 1 -Total $totalPasos `
    -Titulo "Detener servicios de Windows Update" `
    -Descripcion "Detiene los servicios para evitar que Windows Update recree archivos durante la reparacion." `
    -Accion {
    foreach ($svc in $ServiciosUpdate) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
    }
}

# -- Paso 2: Renombrar carpetas de cache --
Invoke-PasoReparacion -Numero 2 -Total $totalPasos `
    -Titulo "Limpiar cache de Windows Update" `
    -Descripcion "Renombra la cache de Windows Update.
                    Las carpetas originales quedan como respaldo (.bak)." `
    -Accion {
    $carpetas = @(
        @{ Origen = "C:\Windows\SoftwareDistribution"; Backup = "C:\Windows\SoftwareDistribution.bak" },
        @{ Origen = "C:\Windows\System32\catroot2";    Backup = "C:\Windows\System32\catroot2.bak" }
    )

    foreach ($c in $carpetas) {
        if (Test-Path $c.Origen) {
            if (Test-Path $c.Backup) {
                Remove-Item $c.Backup -Recurse -Force -ErrorAction SilentlyContinue
            }
            Rename-Item -Path $c.Origen -NewName $c.Backup -ErrorAction Stop
            Write-Log "Renombrada: $($c.Origen)" -Level SUCCESS -LogFile $LogFile
        } else {
            Write-Log "No encontrada (omitida): $($c.Origen)" -Level WARNING -LogFile $LogFile
        }
    }
}

# -- Paso 3: Limpiar registro --
Invoke-PasoReparacion -Numero 3 -Total $totalPasos `
    -Titulo "Limpiar registro de Windows Update" `
    -Descripcion "Limpia identificadores y estados almacenados por Windows Update." `
    -Accion {
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate"
    $claves  = @("AccountDomainSid", "PingID", "SusClientId")
    foreach ($clave in $claves) {
        Remove-ItemProperty -Path $regPath -Name $clave -ErrorAction SilentlyContinue
    }
}

# -- Paso 4: Reset componentes de red --
Invoke-PasoReparacion -Numero 4 -Total $totalPasos `
    -Titulo "Resetear componentes de red" `
    -Descripcion "Restablece Winsock y la configuracion WinHTTP." `
    -Accion {
    netsh winsock reset | Out-Null
    netsh winhttp reset proxy | Out-Null
}

# -- Paso 5: Reiniciar servicios --
Invoke-PasoReparacion -Numero 5 -Total $totalPasos `
    -Titulo "Reiniciar servicios de Windows Update" `
    -Descripcion "Vuelve a iniciar los servicios de Windows Update." `
    -Accion {
    foreach ($svc in $ServiciosUpdate) {
        Start-Service -Name $svc -ErrorAction SilentlyContinue
    }
}

# -- Paso 6: Re-registrar DLLs --
Invoke-PasoReparacion -Numero 6 -Total $totalPasos `
    -Titulo "Re-registrar DLLs de Windows Update" `
    -Descripcion "Intenta registrar nuevamente componentes utilizados por Windows Update." `
    -Accion {
    $errores = 0
    foreach ($dll in $DllsUpdate) {
        $result = Start-Process -FilePath "regsvr32.exe" `
                -ArgumentList "/s $dll" -Wait -PassThru -ErrorAction SilentlyContinue
        if ($result.ExitCode -ne 0) { $errores++ }
    }
    if ($errores -gt 0) {
        Write-Log "Componentes omitidos: $errores" -Level WARNING -LogFile $LogFile
        Write-Log "Algunos componentes ya no existen o no requieren registro en esta version de Windows." -Level NOTE -LogFile $LogFile
    } else {
        Write-Log "  Todas las DLLs registradas correctamente." -LogFile $LogFile
    }
}

#endregion

#region RESUMEN

Write-Blank -LogFile $LogFile
Write-Section "PROXIMOS PASOS" -LogFile $LogFile
Write-Blank -LogFile $LogFile
Write-Log "1. Reiniciar el equipo." -Level WARNING -LogFile $LogFile
Write-Log "2. Abrir Windows Update y buscar actualizaciones." -Level NOTE -LogFile $LogFile
Write-Log "3. Si sigue fallando, revisar el log de este modulo." -Level NOTE -LogFile $LogFile

Write-Blank -LogFile $LogFile
Write-Section -LogFile $LogFile
Write-Log "Log guardado en: $LogFile" -LogFile $LogFile
Write-Blank

Invoke-Pause

#endregion