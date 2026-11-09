# ThesknaepHost - reenvio de puertos de juego para Windows 10
# En Windows 10, WSL usa una red interna (NAT) cuya IP cambia en cada arranque, asi que tus amigos no
# llegan a Linux directamente. Este script (lo lanza la app al pulsar INICIAR, mediante la tarea
# "ThesknaepHost-Puertos" con permisos de administrador) reenvia los puertos de juego de Windows a Linux.
$env:WSL_UTF8 = '1'
$Distro  = 'ThesknaepHost'
$Puertos = 7777, 7778, 7779, 7780, 25565, 25566
$log = Join-Path $env:LOCALAPPDATA 'ThesknaepHost\puertos.log'
function Log($t) { Add-Content $log "$(Get-Date -Format 's')  $t" -ErrorAction SilentlyContinue }

# IP de Linux (interfaz eth0; se reintenta mientras Linux termina de arrancar)
$ip = $null
for ($i = 0; $i -lt 20 -and -not $ip; $i++) {
    $o = (wsl.exe -d $Distro -u root -e sh -c "ip -4 -o addr show eth0" 2>$null) -join ' '
    if ($o -match 'inet (\d+\.\d+\.\d+\.\d+)') { $ip = $Matches[1] } else { Start-Sleep -Seconds 2 }
}
if (-not $ip) { Log 'No se pudo obtener la IP de Linux.'; exit 1 }

# El reenvio de netsh necesita el servicio "Aplicacion auxiliar IP"
try { Set-Service iphlpsvc -StartupType Automatic; Start-Service iphlpsvc } catch { Log "iphlpsvc: $_" }

foreach ($p in $Puertos) {
    netsh.exe interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=$p | Out-Null
    netsh.exe interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=$p connectaddress=$ip connectport=$p | Out-Null
}
Log "Puertos $($Puertos -join ',') -> $ip"
