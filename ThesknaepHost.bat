@echo off
rem Crea (o rehace si moviste la carpeta u otro PC) el icono, el lanzador y los accesos directos
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$v = Join-Path '%~dp0' 'ThesknaepHost.vbs'; if (-not ((Test-Path $v) -and (Get-Content $v -Raw).Contains('%~dp0') -and (Test-Path (Join-Path '%~dp0' 'thesknaephost-app-v2.ico')))) { & (Join-Path '%~dp0' 'CrearAccesoDirecto.ps1') }"
start "" wscript.exe "%~dp0ThesknaepHost.vbs"
