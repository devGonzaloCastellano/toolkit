@echo off
:: ============================================================
:: Portable Windows Toolkit v2.0.0 - Launcher
:: ============================================================
:: Único punto de entrada .bat del proyecto.
:: Su único trabajo es elevar PowerShell y lanzar menu.ps1.
:: Toda la lógica real vive en los scripts .ps1.
:: ============================================================

@echo off

PowerShell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Start-Process powershell.exe -ArgumentList '-NoExit -NoProfile -ExecutionPolicy Bypass -File ""%~dp0menu.ps1""' -Verb RunAs"
