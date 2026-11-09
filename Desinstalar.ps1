#Requires -RunAsAdministrator
# Borra la maquina Linux ThesknaepHost con TODOS los servidores y mundos que contiene.
$r = Read-Host "Esto borra ThesknaepHost y TODOS tus mundos/servidores. Escribe BORRAR para confirmar"
if ($r -ne 'BORRAR') { Write-Host 'Cancelado.'; return }
wsl.exe --unregister ThesknaepHost
Remove-NetFirewallRule -DisplayName 'ThesknaepHost Juegos' -ErrorAction SilentlyContinue
if (Get-Command Remove-NetFirewallHyperVRule -ErrorAction SilentlyContinue) {
    'TCP', 'UDP' | ForEach-Object { Remove-NetFirewallHyperVRule -Name "ThesknaepHost-Juegos-$_" -ErrorAction SilentlyContinue }
}
# Windows 10: reenvios de puertos y su tarea
Unregister-ScheduledTask -TaskName 'ThesknaepHost-Puertos' -Confirm:$false -ErrorAction SilentlyContinue
foreach ($p in 7777, 7778, 7779, 7780, 25565, 25566) {
    netsh.exe interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=$p 2>$null | Out-Null
}
Remove-Item (Join-Path $env:LOCALAPPDATA 'ThesknaepHost') -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'ThesknaepHost desinstalado. (Tu .wslconfig se deja como está.)'
