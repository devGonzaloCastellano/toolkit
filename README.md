# Portable Windows Toolkit

Toolkit portable desarrollado en PowerShell para tareas de:

- diagnóstico
- mantenimiento
- reparación
- auditoría de seguridad
- soporte técnico Windows

Diseñado con un enfoque modular y portable, 
pensado para asistencia técnica y troubleshooting en entornos Windows.

Actualmente, el sistema se encuentra en su Versión 3 (v3.0.0).

---

## ⚡ Uso rápido
1. Clonar o descargar el repositorio
2. Ejecutar `launcher.bat` como administrador
3. Seleccionar la opción deseada desde el menú

> El launcher solicita elevación UAC automáticamente.
> Todos los módulos corren en la misma ventana de PowerShell.
> Ctrl + C cancela la ejecución en cualquier momento, incluso durante módulos largos.
---

## 🧰 Funcionalidades

### 🖥 Diagnóstico del sistema
- Información completa de hardware y software
- RAM física real vs disponible para el SO (incluye memoria reservada por GPU integrada)
- Detalle por módulo RAM (slot, modelo, fabricante, velocidad)
- GPU con VRAM, resolución y versión de driver
- Batería con nivel y estado (en notebooks)
- Discos físicos con estado SMART
- Particiones con porcentaje de uso y alertas
- Red: IP, MAC, gateway, DNS
- Servicios críticos: Defender, Firewall, Windows Update
- Diagnostico general con semáforo visual al final
- Estado del disco con chkdsk y top 10 carpetas más pesadas (con exclusión automática de la unidad de origen del toolkit)
- Procesos agrupados con clasificación por origen y nivel de riesgo

### 🌐 Red y conectividad
- Reparación de red automática (flush DNS, reset IP, Winsock, TCP/IP, proxy)
- Mapa de red local con escaneo de dispositivos via ping paralelo
- Tabla ARP con dispositivos recientes
- Detección de direcciones IP APIPA (169.254.x.x), tanto en el equipo local como en dispositivos escaneados
- Auditoria de puertos con clasificación de riesgo por puerto y proceso

### 👥 Auditoría y seguridad
- Usuarios locales con último login
- Grupos y miembros (con alerta para Administradores)
- Sesiones activas
- Últimos 10 inicios de sesión del log de seguridad
- Puertos en escucha con detección de puertos de riesgo conocidos
- Conexiones a internet agrupadas por proceso
- Servicios innecesarios (telemetría, Xbox, raramente usados)
- Programas al inicio desde registro, carpetas y Programador de Tareas

### 🧹 Mantenimiento y optimización
- Limpieza de temporales (usuario, sistema, recientes, cache WU)
- Limpieza de Prefetch opcional con explicación del impacto
- Flush DNS y vaciado de papelera
- Instrucciones para limpieza adicional manual (Disk Cleanup) cuando se necesite una pasada más profunda
- Conteo de items eliminados y espacio liberado

### 🛠 Reparación
- SFC y DISM con progreso en tiempo real y tiempo transcurrido
- Reparación de Windows Update (servicios, cache, registro, DLLs)
- Reparación de red con díagnostico antes y después

### 🔌 Energía
- Reinicio normal
- Reinicio forzado 
- Reinicio a BIOS/UEFI 
- Reinicio a Opciones de Recuperación (WinRE) 
- Apagado

> todos con confirmación previa y detección de tipo de firmware

### 🗂 Utilidades
- God Mode en el Escritorio
- Actualización de Windows Defender con escaneo rápido y completo opcionales

---

## 📸 Screenshots

<table>
  <tr>
    <td align="center">
      <a href="img/menu.jpg"><img src="img/menu.jpg" width="380"/></a>
      <br/><sub>Menu principal</sub>
    </td>
    <td align="center">
      <a href="img/info_sistema.jpg"><img src="img/info_sistema.jpg" width="380"/></a>
      <br/><sub>Informacion del sistema y diagnostico</sub>
    </td>
  </tr>
  <tr>
    <td align="center">
      <a href="img/puertos.jpg"><img src="img/puertos.jpg" width="380"/></a>
      <br/><sub>Puertos y conexiones activas</sub>
    </td>
    <td align="center">
      <a href="img/reparacion_red.jpg"><img src="img/reparacion_red.jpg" width="380"/></a>
      <br/><sub>Reparacion de red</sub>
    </td>
  </tr>
</table>

---
## 🏛 Arquitectura del proyecto

### Estructura 

```text
toolkit/
|-- launcher.bat
|-- menu.ps1
|-- lib/
|   |-- Utils.ps1
|   |-- Reporting.ps1
|   `-- data/
|       |-- procesos_sistema.json
|       |-- procesos_aplicaciones.json
|       |-- procesos_malware.json
|       |-- puertos_conocidos.json
|       |-- puertos_riesgo.json
|       |-- dlls_windows_update.json
|       `-- servicios_catalogo.json
|-- scripts/
|   |-- defender.ps1
|   |-- godmode.ps1
|   |-- info_sistema.ps1
|   |-- limpieza.ps1
|   |-- mapa_red.ps1
|   |-- procesos.ps1
|   |-- puertos.ps1
|   |-- reinicio.ps1
|   |-- reparar_red.ps1
|   |-- reparar_sistema.ps1
|   |-- reparar_windows_update.ps1
|   |-- reporte_disco.ps1
|   |-- servicios.ps1
|   |-- startup.ps1
|   `-- usuarios.ps1
|-- logs/
`-- reports/
```
La estructura está pensada para facilitar:
- mantenibilidad
- modularidad
- portabilidad
- escalabilidad futura

### lib/Utils.ps1
Módulo compartido importado via dot-sourcing por todos los scripts.
Provee: `Write-Log`, `Write-Blank`, `Write-Section`, `Initialize-Environment`,
`Test-IsAdmin`, `Invoke-Elevate`, `Format-Bytes`, `Invoke-Pause`,
`Get-CenteredTag`, `Test-InternetConnection`, `Import-DataList`,
`Register-CancelHandler`, `Set-CurrentExecution`.

Desde v3.0.0, `Register-CancelHandler` se invoca una única vez al arrancar
`menu.ps1` y queda activo durante toda la vida del proceso: si el usuario
cancela con **Ctrl + C** en cualquier momento (incluso a mitad de un módulo
largo), la toolkit corta la ejecución de forma limpia, elimina el TXT en
curso si existía, y muestra un aviso antes de cerrar. Cada módulo informa
qué está corriendo con `Set-CurrentExecution` al inicio de su región de
inicialización.

### lib/Reporting.ps1
Módulo independiente (separado de `Utils.ps1` a propósito, ya que tiene
su propio ciclo de vida y versionado de schema) encargado de la
generación de reportes estructurados en JSON. Provee:
`Get-ReportFileName`, `New-ModuleReport`, `Complete-ModuleReport`,
`Save-ModuleReport`, `Add-ReportError`.

Cada módulo, al finalizar, guarda un reporte JSON en `reports/` con el
mismo nombre base que su log TXT (agrupado por fecha corta, con sufijo
numérico si se ejecuta más de una vez el mismo día). El TXT se mantiene
como reporte de lectura humana; el JSON es la fuente estructurada que
sirve de base para consolidación e informes futuros.

**Schema del reporte** (`schemaVersion: "1.0"`):

```json
{
  "schemaVersion": "1.0",
  "toolkitVersion": "3.0.0",
  "module": "reporte_disco",
  "executionId": "20260710-143022",
  "durationSeconds": 12.4,
  "status": "OK | ERROR",
  "data": { },
  "errors": [
    {
      "message": "descripcion del hallazgo o fallo",
      "severity": "WARNING | ERROR",
      "source": "TOOLKIT | SYSTEM"
    }
  ]
}
```

- **`status`**: `ERROR` únicamente si hubo un fallo real del toolkit
  (`errors` con `severity: ERROR`); un `WARNING`, aunque exista, no baja
  el status del módulo.
- **`data`**: contenido específico de cada módulo — siempre datos
  simples o resúmenes planos, nunca objetos CIM/WMI crudos (para evitar
  reportes de miles de líneas de metadata irrelevante).
- **`errors[].source`**: distingue si el problema es una falla del propio
  toolkit (`TOOLKIT` — ej. no se pudo leer un listado, un cmdlet falló)
  de un hallazgo real sobre el equipo auditado (`SYSTEM` — ej. una unidad
  con errores, un servicio innecesario activo). Esta distinción es la que
  en el futuro va a permitir separar "hay que revisar el toolkit" de
  "hay que avisarle al cliente".

### lib/data/
Listados y catálogos externalizados fuera del código de cada módulo, en
formato JSON con estructura `{ descripcion, ultimaActualizacion, items }`.
Se cargan con `Import-DataList -FileName "archivo.json"` (o
`-AsHashtable` para tablas clave-valor, como los puertos). Si un archivo
no existe o está corrupto, el módulo correspondiente **no corta la
ejecución**: degrada con una lista vacía, avisa en consola/log, y lo
registra en el reporte como `TOOLKIT/WARNING`.

| Archivo | Usado por |
|---|---|
| `procesos_sistema.json` | `procesos.ps1`, `puertos.ps1` (unificado) |
| `procesos_aplicaciones.json` | `procesos.ps1` |
| `procesos_malware.json` | `procesos.ps1` |
| `puertos_conocidos.json` | `puertos.ps1` |
| `puertos_riesgo.json` | `puertos.ps1` |
| `dlls_windows_update.json` | `reparar_windows_update.ps1` |
| `servicios_catalogo.json` | `servicios.ps1` |

Mantener estos archivos actualizados (agregar aplicaciones legítimas
nuevas, revisar puertos, etc.) es la forma prevista de reducir falsos
positivos con el tiempo, sin tocar código.

### launcher.bat
Unico archivo `.bat` del proyecto. Su unico trabajo es elevar PowerShell
y lanzar `menu.ps1`. Toda la logica vive en los scripts `.ps1`.

### Plantilla de modúlo
Cada script sigue la misma estructura:
```
SYNOPSIS / DESCRIPTION / NOTES
PARAMETROS      ($LogDir, $NoElevation)
IMPORTS         (dot-sourcing de Utils.ps1)
AUTO-ELEVACION
INICIALIZACION  (Initialize-Environment)
DATOS           (Get-CimInstance, etc. - separado de la presentacion)
LOGICA/PRESENTACION
RESUMEN
```
---

## Compatibilidad

- Windows 10 / 11
- PowerShell 5.1 (incluido en Windows por defecto)
- PowerShell 7+ (usa funcionalidades mejoradas cuando está disponible,
  como ForEach-Object -Parallel en mapa_red.ps1)

---

## 🛡 Seguridad y Elevación de Privilegios
El toolkit cuenta con un sistema de **auto-elevación de privilegios**.
Al ejecutarse, el script verifica si cuenta con permisos de administrador; de no ser así, solicitará acceso mediante UAC (User Account Control) utilizando PowerShell.

**¿Por qué requiere permisos?**
- Modificación y reparación de interfaces de red (`netsh`).
- Consulta de información de hardware profunda (`wmic` / `CIM`).
- Gestión de servicios críticos del sistema.
- Limpieza de archivos temporales en directorios protegidos.
- Reinicio/apagado del equipo (`shutdown.exe`).
---

## Logs y Reportes

Cada módulo genera, en la misma corrida, dos archivos:
```
logs/
|-- info_sistema_2026-08-06_16-18.txt
|-- reporte_disco_2026-07-24_17-55.txt
`-- ...

reports/
|-- info_sistema_260806.json
|-- reporte_disco_260724.json
`-- ...
```
- **`logs/*.txt`**: mismo output que la consola, sin colores ANSI. Pensado para lectura humana rápida durante o después del servicio.
- **`reports/*.json`**: reporte estructurado (ver schema más arriba). Pensado como fuente de datos para consolidación e informes futuros.

---

## 🚧 Limitaciones conocidas
- El escaneo de red (mapa_red) puede no detectar dispositivos que
  bloquean ICMP (ping) o que están en modo de ahorro de energía WiFi
  (celulares con pantalla apagada); la tabla ARP puede mostrar dispositivos
  que el ping no confirma, y viceversa — ninguna de las dos fuentes por sí
  sola garantiza el listado completo de dispositivos en la red.
- Los eventos de seguridad en `usuarios.ps1` requieren que la auditoria
  de inicio de sesión esté habilitada en el sistema.
- Las listas de clasificación (procesos, puertos) en `lib/data/` reflejan
  software conocido al momento de su última actualización; procesos o
  conexiones legítimas no incluidos ahí pueden marcarse como
  "desconocido" o "sospechoso" sin que eso implique un riesgo real —
  ver `ultimaActualizacion` en cada archivo.
- El OUI lookup (identificación de fabricante por MAC) fue evaluado y
  pospuesto: la mayoría de los dispositivos móviles usan MAC aleatoria
  por red, lo que vuelve el lookup poco confiable en el escenario típico
  de uso del toolkit (domicilios/pymes con mayoría de celulares).
- El módulo de reinicio a BIOS/UEFI puede no funcionar en equipos con
  firmware Legacy (no UEFI); el módulo detecta y advierte este caso
  antes de ejecutar.
---

## 🧪 Testing
Las pruebas fueron realizadas manualmente en entornos Windows 10 Pro,
y en Windows 11 validando:

- ejecución y funcionamiento de cada módulo
- generación de logs y reportes JSON
- manejo de errores y degradación controlada (listados ausentes, sin
  conectividad, fallos de cmdlets)
- cancelación de ejecución con Ctrl+C en distintos puntos del proceso
- análisis completo del sistema
- reparación de red, sistema y Windows Update
- auditoría de usuarios
- detección de procesos y servicios
- clasificación de riesgo en puertos y procesos
- reinicio/apagado en sus 5 modalidades
- estabilidad general del toolkit
---

## Versionado

### Versión 1.0.0 (Finalizada)
 - Toolkit modular funcional
 - Menú centralizado
 - Scripts de diagnóstico
 - Scripts de mantenimiento
 - Reparación de red
 - Auditoría básica del sistema
 - Generación de logs automáticos

### Versión 1.1.0 (Finalizada)
- info_sistema: build detallado con UBR, último inicio legible,
- RAM física real, reserva GPU, detalle por módulo,
- discos con tipo HDD/SSD e interfaz, particiones agrupadas por disco
- limpieza: agrega log con conteo de archivos, duración y espacio liberado
- reparar_red: timestamp via PowerShell, errores de registro suprimidos
- reparar_windows_update: timestamp via PowerShell, errores de registro suprimidos
- reporte_disco: suprimido ruido visual en log de chkdsk, nota de falso positivo
- Timestamp de logs migrado a PowerShell en todos los scripts afectados
- Supresión de ruido visual en logs de chkdsk y reparaciones

### Versión 2.0.0 (Finalizada)
- Migración completa a PowerShell nativo (eliminación de Batch)
- Modúlo compartido lib/Utils.ps1 con logging por niveles y colores
- Plantilla uniforme para todos los modulos
- Clasificación de riesgo en puertos (por puerto, proceso e IP)
- Clasificación de procesos por origen (sistema, aplicación, desconocido)
- RAM física real vs reservada por hardware
- Temperatura de CPU, VRAM, driver GPU, batería
- Diagnostico general con semáforo visual
- Uptime legible
- Detección automática de PS 5.1 vs. PS 7+ para optimización
- Prefetch con advertencia y confirmación opcional
- Progreso en tiempo real para SFC, DISM y chkdsk

### Versión 2.1.0 (Finalizada)
- Revisión completa de formato y consistencia visual de reportes
- Incorporación de etiquetas NOTE en todos los módulos
- Centralización de validación de conectividad mediante Test-InternetConnection()
- Optimización y reducción de ruido visual en logs
- Diagnóstico de sistema reorganizado para lectura rápida
- Eliminación de métricas de temperatura no confiables
- Incorporación de información detallada de placa madre
- Incorporación de versión y fecha de BIOS
- Diagnóstico general unificado y estandarizado
- Mejoras en alineación visual de reportes
- Corrección de inconsistencias entre módulos
- Mejora general de mantenibilidad y experiencia de soporte técnico

### Versión 3.0.0 (Finalizada)
- Reportes estructurados en JSON (`lib/Reporting.ps1`) manteniendo los reportes en `.txt`, con schema versionado y distinción de errores por origen (`TOOLKIT` / `SYSTEM`)
- Cancelación global de ejecución con Ctrl+C, en cualquier punto del proceso
- Módulo `reinicio.ps1`: reinicio normal, forzado, a BIOS/UEFI, a Opciones de Recuperación (WinRE), y apagado — todos con confirmación previa
- Fix de falso positivo en unidades removibles (autodetección y exclusión de la unidad de origen del toolkit en `reporte_disco`)
- Detección de IP APIPA (169.254.x.x), en el equipo local y en dispositivos escaneados
- Estandarización de manejo de errores en los 14 módulos originales, con distinción entre fallos del toolkit y hallazgos reales del equipo
- Forzado de `InvariantCulture` a nivel global (fix de separador decimal)
- Externalización completa de listados hardcodeados a `lib/data/`: procesos (sistema, aplicaciones, malware), puertos (conocidos, riesgo), DLLs de Windows Update (verificadas contra documentación oficial de Microsoft), catálogo de servicios innecesarios
- Reemplazo de Disk Cleanup automatizado por instrucciones manuales guiadas en `limpieza.ps1` (evita el problema de proceso en segundo plano no verificable)
- Múltiples bugs corregidos en el proceso: interrupciones de flujo mal ubicadas, mensajes de log silenciosos, serialización incorrecta de arrays vacíos, falsos positivos de éxito con listados ausentes, entre otros

### Versión 3.1.0 (Planificada)
- Reportes HTML generados a partir del JSON, con resumen interpretado orientado a cliente y detalle completo orientado a técnico (no es un renderizado genérico del JSON: cada módulo define su propio criterio de síntesis)
- Descomposición de `lib/Utils.ps1` en módulos de responsabilidad única (Config, Logging, Validation, y ErrorHandling si el patrón lo justifica)

### Versión x.x.x (Visión futura)
- Motor de consolidación de auditorías (múltiples reportes JSON de una sesión en un informe único)
- Informe técnico completo basado en JSON
- Sistema de recomendaciones automáticas
- Evaluación integral de estado del equipo
- Generación de informes profesionales para entrega post-servicio, con branding propio (logo, datos de contacto)
- Recategorización de procesos y puertos desconocidos, en base a datos empíricos recolectados en ~15 equipos distintos
- OUI lookup (identificación de fabricante por MAC), con detección previa de MAC aleatoria/administrada localmente
- Release dedicado a seguridad del toolkit: verificación de integridad de módulos (hash/firma) y manejo de datos sensibles en reportes
---

## Objetivo del proyecto

Este proyecto fue desarrollado con fines:
 - formativos
 - prácticos
 - profesionales

con el objetivo de consolidar conocimientos en:

 - scripting Windows
 - automatización
 - troubleshooting
 - administración básica de sistemas
 - soporte técnico
 - análisis y diagnóstico de PCs Windows

---

## Estado actual

Version 3.0.0 finalizada.
El proyecto continúa evolucionando mediante mejoras progresivas,
refactorización y expansión de funcionalidades.