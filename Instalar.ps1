#Requires -RunAsAdministrator
# ThesknaepHost - instalador para Windows 10 (22H2) y Windows 11
# Crea una maquina Linux (WSL2) llamada "ThesknaepHost" e instala dentro Pterodactyl Panel + Wings.
$ErrorActionPreference = 'Stop'
$env:WSL_UTF8 = '1'
$Distro  = 'ThesknaepHost'
$Base    = Join-Path $env:LOCALAPPDATA 'ThesknaepHost'
$RootFs  = 'https://cloud-images.ubuntu.com/wsl/releases/24.04/current/ubuntu-noble-wsl-amd64-wsl.rootfs.tar.gz'
$VmId    = '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}'   # identificador de WSL para el firewall Hyper-V
$Puertos = @(7777, 7778, 7779, 7780, 25565, 25566)

$Tarea   = 'ThesknaepHost-ContinuarInstalacion'
$TareaPuertos = 'ThesknaepHost-Puertos'
$Build   = [Environment]::OSVersion.Version.Build
$Win10   = $Build -lt 22621      # Windows 10 (y Windows 11 21H2): no tienen la red "mirrored" de WSL

function Paso($t) { Write-Host "`n==> $t" -ForegroundColor Cyan }

# Tailscale: winget si existe (Windows 11), si no el instalador oficial de pkgs.tailscale.com (Windows 10)
function InstalarTailscale {
    Write-Host 'Instalador oficial de Tailscale Inc. Al instalarlo aceptas sus términos: https://tailscale.com/terms'
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id Tailscale.Tailscale -e --accept-package-agreements --accept-source-agreements
    }
    if (-not (Test-Path "$env:ProgramFiles\Tailscale\tailscale.exe")) {
        $exe = Join-Path $env:TEMP 'tailscale-setup.exe'
        curl.exe -L --fail -o $exe 'https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe'
        if ($LASTEXITCODE -eq 0) { Start-Process $exe -ArgumentList '/quiet' -Wait; Remove-Item $exe -Force -ErrorAction SilentlyContinue }
    }
    if (-not (Test-Path "$env:ProgramFiles\Tailscale\tailscale.exe")) {
        Write-Warning 'No se pudo instalar Tailscale solo. Instálalo desde https://tailscale.com/download y sigue.'
    }
}

New-Item -ItemType Directory -Force $Base | Out-Null
try { Start-Transcript -Path (Join-Path $Base 'instalar.log') -Append | Out-Null } catch {}

# Tarea de un solo uso que reabre este instalador al volver a entrar a Windows despues de reiniciar
function ProgramarContinuacion {
    $usuario = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $accion = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $disparo = New-ScheduledTaskTrigger -AtLogOn -User $usuario
    $quien = New-ScheduledTaskPrincipal -UserId $usuario -LogonType Interactive -RunLevel Highest
    Register-ScheduledTask -TaskName $Tarea -Action $accion -Trigger $disparo -Principal $quien -Force | Out-Null
}
function PedirReinicio {
    ProgramarContinuacion
    Write-Host "`n============================================================" -ForegroundColor Yellow
    Write-Host "  HAY QUE REINICIAR EL PC para terminar de activar WSL." -ForegroundColor Yellow
    Write-Host "  Al volver a entrar a Windows, la instalación SIGUE SOLA" -ForegroundColor Yellow
    Write-Host "  (se abrirá esta ventana otra vez; no tienes que hacer nada)." -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
    $r = Read-Host "`n¿Reiniciar ahora? Guarda tu trabajo antes. (S/N)"
    if ($r -match '^[sSyY]') { Restart-Computer -Force }
    else { Write-Host 'Bien. Cuando reinicies, la instalación continuará sola.' -ForegroundColor Yellow }
}

try {
    # Modo de uso (solo la primera vez): LOCAL o REMOTO. En REMOTO, Tailscale es obligatorio.
    $archivoModo = Join-Path $Base 'modo.txt'
    if (-not (Test-Path $archivoModo)) {
        Write-Host "`n¿Cómo vas a usar ThesknaepHost?" -ForegroundColor Magenta
        Write-Host "  1) LOCAL   Solo personas en tu misma red (mismo WiFi o cable)." -ForegroundColor Green
        Write-Host "  2) REMOTO  Tú y tus amigos desde cualquier lugar (datos móviles, otras casas)." -ForegroundColor Cyan
        Write-Host "             Requiere Tailscale (gratis). Funciona aunque tu internet tenga CGNAT." -ForegroundColor Yellow
        do { $r = Read-Host 'Elige 1 o 2' } until ($r -in '1', '2')
        $modo = if ($r -eq '2') { 'remoto' } else { 'local' }
        Set-Content $archivoModo $modo -Encoding ASCII
        if ($modo -eq 'remoto' -and -not (Test-Path "$env:ProgramFiles\Tailscale\tailscale.exe")) {
            Paso 'Instalando Tailscale (obligatorio para el modo REMOTO)'
            InstalarTailscale
            Write-Host 'Cuando termine la instalación de ThesknaepHost, inicia sesión en Tailscale desde ACCESO REMOTO.' -ForegroundColor Yellow
        }
    }

    # Si venimos de un reinicio, la tarea ya cumplio su funcion
    Unregister-ScheduledTask -TaskName $Tarea -Confirm:$false -ErrorAction SilentlyContinue

    # 1. WSL
    Paso 'Comprobando WSL'
    if ($Build -lt 19044) {
        throw "Tu Windows 10 es muy antiguo (compilación $Build). Actualízalo a Windows 10 22H2 con Windows Update y vuelve a instalar."
    }
    # No llamamos a "wsl --status": sin WSL instalado se queda esperando una tecla.
    $wslApp = Test-Path "$env:ProgramFiles\WSL\wsl.exe"
    $plataforma = [bool](Get-Service vmcompute -ErrorAction SilentlyContinue)
    if (-not $wslApp) {
        Paso 'Instalando WSL y la Plataforma de Máquina Virtual'
        if ($Win10) {
            # Windows 10 trae un WSL viejo integrado: activamos las piezas y bajamos el WSL nuevo (con systemd)
            dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null
            dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null
            wsl.exe --update
        }
        if (-not (Test-Path "$env:ProgramFiles\WSL\wsl.exe")) { wsl.exe --install --no-distribution }
        if (-not (Test-Path "$env:ProgramFiles\WSL\wsl.exe")) { wsl.exe --update --web-download }
        $wslApp = Test-Path "$env:ProgramFiles\WSL\wsl.exe"
        if (-not $wslApp) {
            # Muchas veces WSL queda instalado pero solo aparece despues de reiniciar: reiniciamos una vez antes de rendirnos
            $marca = Join-Path $Base 'reinicio-wsl.txt'
            if (-not (Test-Path $marca)) { Set-Content $marca (Get-Date) ; PedirReinicio; return }
            throw 'No se pudo instalar WSL. Ejecuta Windows Update (incluidas las actualizaciones opcionales), reinicia y prueba otra vez.'
        }
        Remove-Item (Join-Path $Base 'reinicio-wsl.txt') -ErrorAction SilentlyContinue
        $plataforma = [bool](Get-Service vmcompute -ErrorAction SilentlyContinue)
    }
    if (-not $plataforma) {
        # WSL ya esta, pero la Plataforma de Maquina Virtual solo se activa al reiniciar
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        if ($cpu.VirtualizationFirmwareEnabled -eq $false) {
            throw 'La virtualización está DESACTIVADA en la BIOS. Actívala (Intel VT-x / AMD SVM) y vuelve a pulsar INSTALAR.'
        }
        dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null
        PedirReinicio
        return
    }
    wsl.exe --update

    # 2. Red en modo "mirrored": el panel y los juegos se ven en localhost y en tu red local
    $cfg = Join-Path $env:USERPROFILE '.wslconfig'
    if ($Win10) {
        Paso 'Windows 10: los puertos de juego se reenviarán a Linux en cada inicio'
    } else {
    Paso 'Configurando la red de WSL (modo mirrored)'
    $txt = if (Test-Path $cfg) { Get-Content $cfg -Raw } else { '' }
    if ($null -eq $txt) { $txt = '' }
    if ($txt -notmatch '(?m)^\s*networkingMode\s*=') {
        if (Test-Path $cfg) { Copy-Item $cfg "$cfg.bak" -Force }
        if ($txt -match '(?m)^\[wsl2\]') {
            $txt = $txt -replace '(?m)^\[wsl2\]', "[wsl2]`r`nnetworkingMode=mirrored"
        } else {
            $txt = $txt.TrimEnd() + "`r`n[wsl2]`r`nnetworkingMode=mirrored`r`n"
        }
        [IO.File]::WriteAllText($cfg, $txt.TrimStart())
        wsl.exe --shutdown
    } elseif ($txt -notmatch '(?m)^\s*networkingMode\s*=\s*mirrored') {
        Write-Warning "Tu .wslconfig ya define otro networkingMode. Cámbialo a 'mirrored' para que tus amigos puedan entrar."
    }
    }

    # 3. Maquina Linux propia (no toca otras distros que tengas)
    $existe = (wsl.exe -l -q | ForEach-Object { $_.Trim() }) -contains $Distro
    if (-not $existe) {
        Paso 'Descargando Ubuntu 24.04 (~350 MB)'
        New-Item -ItemType Directory -Force $Base | Out-Null
        $tar = Join-Path $Base 'ubuntu.rootfs.tar.gz'
        curl.exe -L --fail -o $tar $RootFs
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo descargar Ubuntu.' }
        Paso "Creando la maquina Linux '$Distro'"
        wsl.exe --import $Distro (Join-Path $Base 'disco') $tar --version 2
        if ($LASTEXITCODE -ne 0) { throw 'wsl --import falló.' }
        Remove-Item $tar -Force
    }

    # 4. Instalar Pterodactyl dentro de Linux
    function ARutaLinux($p) { (wsl.exe -d $Distro -u root -e wslpath -a ($p -replace '\\', '/')).Trim() }
    $sh  = ARutaLinux (Join-Path $PSScriptRoot 'linux\instalar-pterodactyl.sh')
    $out = ARutaLinux $Base
    $cmd = "tr -d '\r' < '$sh' > /root/thesknaephost-install.sh && bash /root/thesknaephost-install.sh '$out'"
    for ($i = 0; $i -lt 3; $i++) {
        Paso 'Instalando Pterodactyl (10-20 minutos la primera vez)'
        wsl.exe -d $Distro -u root -e bash -c $cmd
        $code = $LASTEXITCODE
        if ($code -ne 42) { break }
        Paso 'Reiniciando Linux con systemd'
        wsl.exe --terminate $Distro
        Start-Sleep -Seconds 4
    }
    if ($code -ne 0) { throw "La instalación dentro de Linux falló (código $code). Revisa los mensajes de arriba." }

    # 5. Firewall: solo los puertos de juego
    Paso 'Abriendo puertos de juego en el firewall'
    $lista = $Puertos | ForEach-Object { "$_" }
    Remove-NetFirewallRule -DisplayName 'ThesknaepHost Juegos' -ErrorAction SilentlyContinue
    foreach ($proto in 'TCP', 'UDP') {
        New-NetFirewallRule -DisplayName 'ThesknaepHost Juegos' -Direction Inbound -Protocol $proto `
            -LocalPort $lista -Action Allow -Profile Any | Out-Null
    }
    if (Get-Command New-NetFirewallHyperVRule -ErrorAction SilentlyContinue) {
        foreach ($proto in 'TCP', 'UDP') {
            $n = "ThesknaepHost-Juegos-$proto"
            Remove-NetFirewallHyperVRule -Name $n -ErrorAction SilentlyContinue
            New-NetFirewallHyperVRule -Name $n -DisplayName "ThesknaepHost Juegos $proto" -Direction Inbound `
                -VMCreatorId $VmId -Protocol $proto -LocalPorts $lista -Action Allow | Out-Null
        }
    }

    # Windows 10: tarea que la app lanza al INICIAR para reenviar los puertos de juego a Linux
    # (necesita permisos de administrador; la tarea los tiene y la app la puede lanzar sin pedirlos)
    if ($Win10) {
        Paso 'Creando el reenvío de puertos de juego (Windows 10)'
        $usuario = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $accion = New-ScheduledTaskAction -Execute 'powershell.exe' `
            -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$(Join-Path $PSScriptRoot 'Puertos.ps1')`""
        $quien = New-ScheduledTaskPrincipal -UserId $usuario -LogonType Interactive -RunLevel Highest
        $ajustes = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
        Register-ScheduledTask -TaskName $TareaPuertos -Action $accion -Principal $quien -Settings $ajustes -Force | Out-Null
    } else {
        Unregister-ScheduledTask -TaskName $TareaPuertos -Confirm:$false -ErrorAction SilentlyContinue
    }

    Paso 'Creando accesos directos'
    & (Join-Path $PSScriptRoot 'CrearAccesoDirecto.ps1')

    Write-Host "`nListo. Usuario y contraseña del panel en: $Base\credenciales.txt" -ForegroundColor Green
    Write-Host 'Vuelve a ThesknaepHost y pulsa "Iniciar".' -ForegroundColor Green
} catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Registro completo en: $Base\instalar.log" -ForegroundColor Red
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
