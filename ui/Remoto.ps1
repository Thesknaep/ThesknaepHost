# ThesknaepHost - ventana "ACCESO REMOTO": jugar desde cualquier lugar con Tailscale (funciona con CGNAT y datos moviles).
# La app usa el programa oficial de Tailscale por debajo; aqui solo se ve su estado y las direcciones para compartir.
# Se carga desde ThesknaepHost.ps1.

$TailscaleExe = "$env:ProgramFiles\Tailscale\tailscale.exe"
$script:VentanaRemoto = $null
$script:LeyendoRemoto = $false

$EstadosTs = @{
    Running          = @{ txt = 'CONECTADO';            color = [TH.Pal]::Green; boton = 'DESCONECTAR' }
    Starting         = @{ txt = 'CONECTANDO…';          color = [TH.Pal]::Amber; boton = 'DESCONECTAR' }
    NeedsLogin       = @{ txt = 'INICIA SESIÓN';        color = [TH.Pal]::Amber; boton = 'INICIAR SESIÓN' }
    NeedsMachineAuth = @{ txt = 'FALTA APROBAR ESTE PC'; color = [TH.Pal]::Amber; boton = 'ABRIR APROBACIÓN' }
    Stopped          = @{ txt = 'DESCONECTADO';         color = [TH.Pal]::Red;   boton = 'CONECTAR' }
    NoInstalado      = @{ txt = 'TAILSCALE NO INSTALADO'; color = [TH.Pal]::Amber; boton = 'INSTALAR TAILSCALE' }
    SinRespuesta     = @{ txt = 'TAILSCALE NO RESPONDE'; color = [TH.Pal]::Red;   boton = 'CONECTAR' }
}

# ---------------------------------------------------------------- modo de uso: LOCAL o REMOTO (Tailscale obligatorio)
function ArchivoModo { Join-Path $Base 'modo.txt' }
function LeerModo { $a = ArchivoModo; if (Test-Path $a) { $m = (Get-Content $a -Raw).Trim(); if ($m -in 'local', 'remoto') { return $m } }; $null }
function GuardarModo([string]$m) { New-Item -ItemType Directory -Force $Base | Out-Null; Set-Content (ArchivoModo) $m -Encoding ASCII; $script:Modo = $m }
function PreguntarModo {
    $r = DialogoNeon 'MODO DE USO' ("¿Dónde van a jugar?`n`n" +
        "LOCAL: solo personas en tu misma red (mismo WiFi o cable).`n`n" +
        "REMOTO: tú y tus amigos desde cualquier lugar (datos móviles, otras casas). " +
        "Requiere Tailscale (gratis), una red privada entre tus equipos y los de tus amigos que funciona aunque tu internet tenga CGNAT. " +
        "Sin Tailscale el modo REMOTO no funciona.") @('LOCAL', 'REMOTO (TAILSCALE)') 0 0 '// ¿DÓNDE VAN A JUGAR?'
    if ($r -eq 1) { GuardarModo 'remoto'; RevisarModoRemoto $true } else { GuardarModo 'local' }
    Log "Modo de uso: $($script:Modo.ToUpper())"
    if ($script:Estado) { MostrarEstado $script:Estado }
}
# En modo REMOTO Tailscale es obligatorio: si falta o esta desconectado, se avisa y se ofrece arreglarlo
function RevisarModoRemoto([bool]$recienElegido = $false) {
    if ($script:Modo -ne 'remoto') { return }
    Async {
        $exe = "$env:ProgramFiles\Tailscale\tailscale.exe"
        $est = 'NoInstalado'
        if (Test-Path $exe) {
            $x = Ejecutar $exe 'status --json' 10
            $est = try { [string]($x.out | ConvertFrom-Json).BackendState } catch { 'SinRespuesta' }
        }
        [pscustomobject]@{ estado = $est; nuevo = [bool]$A }
    } {
        param($res, $err)
        $estado = $res.estado; $recienElegido = $res.nuevo
        if ($estado -eq 'Running') { if ($recienElegido) { Notificar 'MODO REMOTO LISTO' 'Tailscale está conectado. Copia las direcciones en ACCESO REMOTO.' ([TH.Pal]::Green) 5000 }; return }
        if ($estado -eq 'NoInstalado') {
            if (Preguntar "El modo REMOTO necesita Tailscale y no está instalado en este PC.`n`nSe instalará con el instalador oficial de Windows (gratis, de Tailscale Inc.). Al instalarlo aceptas sus términos (tailscale.com/terms)." 'TAILSCALE' 'INSTALAR' 'MÁS TARDE') {
                if (Get-Command winget -ErrorAction SilentlyContinue) { Start-Process winget -ArgumentList 'install --id Tailscale.Tailscale -e --accept-package-agreements --accept-source-agreements' }
                else { Start-Process 'https://tailscale.com/download/windows' }
                Notificar 'INSTALANDO TAILSCALE' 'Cuando termine, inicia sesión desde ACCESO REMOTO.' ([TH.Pal]::Cyan) 6000
            } else { Notificar 'MODO REMOTO SIN TAILSCALE' 'Tus amigos de fuera no podrán entrar hasta que instales Tailscale.' ([TH.Pal]::Red) 7000 }
            return
        }
        Notificar 'TAILSCALE DESCONECTADO' 'Estás en modo REMOTO pero Tailscale no está conectado. Ábrelo en ACCESO REMOTO.' ([TH.Pal]::Red) 7000
        if ($recienElegido) { AbrirRemoto }
    } $recienElegido
}

function AbrirRemoto {
    $script:EstadoTs = $null
    $d = NuevaVentana 'ACCESO REMOTO' '// TAILSCALE  ::  JUEGA DESDE CUALQUIER LUGAR, CON WIFI O DATOS MÓVILES' 760 630
    $script:VentanaRemoto = $d

    # --- Tarjeta: estado de Tailscale
    $t1 = TarjetaEn $d 'TAILSCALE EN ESTE PC' 'VPN' 24 112 712 196
    $script:RPulso = New-Object TH.Pulse
    $script:RPulso.Location = New-Object Drawing.Point(16, 50)
    $t1.Controls.Add($script:RPulso)
    $script:REstado = Etiqueta $t1 'LEYENDO…' 56 46 640 30 ([TH.Pal]::Text) ([TH.Pal]::F(16, [Drawing.FontStyle]::Bold))
    $script:RInfo = Etiqueta $t1 '' 58 80 640 56 ([TH.Pal]::PinkSoft) ([TH.Pal]::Mono(9.5))
    $script:RBoton = Boton $t1 '…' 18 142 220 40 ([TH.Pal]::Pink) $true { AccionTailscale }
    Boton $t1 'ADMINISTRAR (WEB)' 246 142 220 40 ([TH.Pal]::Cyan) $false { Start-Process 'https://login.tailscale.com/admin/machines' } | Out-Null
    Boton $t1 'ACTUALIZAR' 474 142 220 40 ([TH.Pal]::PinkSoft) $false { LeerTailscale $true } | Out-Null

    # --- Tarjeta: direcciones de cada servidor para compartir
    $t2 = TarjetaEn $d 'DIRECCIONES PARA TUS AMIGOS' 'IP:PUERTO' 24 320 712 226
    $lista = New-Object Windows.Forms.Panel
    $lista.Location = New-Object Drawing.Point(12, 44); $lista.Size = New-Object Drawing.Size(688, 176)
    $lista.AutoScroll = $true; $lista.BackColor = [Drawing.Color]::Transparent
    $t2.Controls.Add($lista)
    $script:RLista = $lista

    # --- Botones de abajo
    Boton $d 'INVITAR AMIGO' 24 562 170 44 ([TH.Pal]::Pink) $false { InvitarAmigo } | Out-Null
    Boton $d 'CÓMO SE CONECTAN' 204 562 170 44 ([TH.Pal]::Cyan) $false { GuiaAmigos } | Out-Null
    $bModo = Boton $d "MODO: $(if ($script:Modo) { $script:Modo.ToUpper() } else { '—' })" 384 562 170 44 ([TH.Pal]::Amber) $false { $this.FindForm().Close(); PreguntarModo }
    $bModo.Font = [TH.Pal]::F(9.5, [Drawing.FontStyle]::Bold)
    Boton $d 'CERRAR' 566 562 170 44 ([TH.Pal]::PinkSoft) $false { $this.FindForm().Close() } | Out-Null

    $tm = New-Object Windows.Forms.Timer; $tm.Interval = 5000
    $tm.Add_Tick({ LeerTailscale $false })
    $script:TimerRemoto = $tm
    $d.Animados.Add($script:RPulso)
    $d.Add_Shown({ $script:TimerRemoto.Start(); LeerTailscale $true })
    $d.Add_FormClosed({ $script:TimerRemoto.Stop(); $script:TimerRemoto.Dispose(); $script:VentanaRemoto = $null })
    [void]$d.ShowDialog($f)
    $d.Dispose()
}

# Lee el estado de Tailscale (y, si hace falta, la lista de servidores) en segundo plano
function LeerTailscale([bool]$conServidores) {
    if ($script:LeyendoRemoto -or -not $script:VentanaRemoto) { return }
    $script:LeyendoRemoto = $true
    $pedirLista = $conServidores -and $script:Estado -and $script:Estado.web
    Async {
        $exe = "$env:ProgramFiles\Tailscale\tailscale.exe"
        $r = [pscustomobject]@{ estado = 'NoInstalado'; ip = $null; nombre = $null; equipos = @(); url = $null; servidores = $null }
        if (Test-Path $exe) {
            $x = Ejecutar $exe 'status --json' 10
            if ($x.timeout -or -not $x.out) { $r.estado = 'SinRespuesta' }
            else {
                try {
                    $j = $x.out | ConvertFrom-Json
                    $r.estado = [string]$j.BackendState
                    $r.ip = @($j.Self.TailscaleIPs | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' })[0]
                    $r.nombre = ([string]$j.Self.DNSName).TrimEnd('.')
                    $r.url = [string]$j.AuthURL
                    if ($j.Peer) { $r.equipos = @($j.Peer.PSObject.Properties | ForEach-Object { [pscustomobject]@{ nombre = $_.Value.HostName; so = $_.Value.OS; linea = [bool]$_.Value.Online } }) }
                } catch { $r.estado = 'SinRespuesta' }
            }
        }
        if ($A) { $l = Recursos @('list'); if ($l.ok) { $r.servidores = @($l.servers) } }
        $r
    } {
        param($r, $err)
        $script:LeyendoRemoto = $false
        if (-not $script:VentanaRemoto -or $script:VentanaRemoto.IsDisposed -or -not $r) { return }
        $script:EstadoTs = $r
        if ($r.servidores) { $script:ServidoresRemoto = $r.servidores }
        PintarRemoto
    } $pedirLista
}

function PintarRemoto {
    $r = $script:EstadoTs
    $e = $EstadosTs[[string]$r.estado]
    if (-not $e) { $e = @{ txt = ([string]$r.estado).ToUpper(); color = [TH.Pal]::Dim; boton = 'CONECTAR' } }
    $script:RPulso.Accent = $e.color
    $script:REstado.Text = $e.txt; $script:REstado.ForeColor = $e.color
    $script:RBoton.Text = $e.boton
    $enLinea = @($r.equipos | Where-Object { $_.linea })
    $script:RInfo.Text = switch ($r.estado) {
        'Running' { "IP DE TU PC    $($r.ip)`nNOMBRE         $($r.nombre)`nDISPOSITIVOS   $($r.equipos.Count) en tu red, $($enLinea.Count) en línea" + $(if ($enLinea.Count) { ': ' + (($enLinea | Select-Object -First 3 | ForEach-Object { $_.nombre }) -join ', ') } else { '' }) }
        'NoInstalado' { "Tailscale crea una red privada entre tu PC y los teléfonos o PCs de tus amigos.`nFunciona con CGNAT y datos móviles. Gratis para uso personal." }
        'NeedsLogin' { "Inicia sesión con tu cuenta (Google, Microsoft, Apple o GitHub) para conectar este PC." }
        'NeedsMachineAuth' { "Tu cuenta debe aprobar este PC. Pulsa ABRIR APROBACIÓN y apruébalo en la web de Tailscale." }
        'Stopped' { "Tailscale está instalado pero desconectado. Pulsa CONECTAR." }
        default { "Abre Tailscale desde el icono junto al reloj, o pulsa CONECTAR." }
    }

    # Lista de direcciones IP:puerto
    $servidores = if ($script:ServidoresRemoto) { @($script:ServidoresRemoto) } else { @($script:Servidores) }
    $script:RLista.Controls.Clear()
    if ($servidores.Count -eq 0) {
        Etiqueta $script:RLista 'Pulsa INICIAR en la app para ver tus servidores aquí.' 6 10 660 24 ([TH.Pal]::Dim) ([TH.Pal]::F(10, [Drawing.FontStyle]::Regular)) | Out-Null
        return
    }
    $y = 4
    foreach ($s in $servidores) {
        $tipo = $NombreTipo[[string]$s.tipo]; if (-not $tipo) { $tipo = ([string]$s.egg).ToUpper() }
        Etiqueta $script:RLista ([string]$s.name) 6 $y 250 22 ([TH.Pal]::Text) ([TH.Pal]::F(11, [Drawing.FontStyle]::Bold)) | Out-Null
        Etiqueta $script:RLista $tipo 6 ($y + 20) 250 18 ([TH.Pal]::Dim) ([TH.Pal]::Mono(8.5)) | Out-Null
        $dir = if ($r.estado -eq 'Running' -and $r.ip) { "$($r.ip):$($s.port)" } else { "—  (conecta Tailscale)" }
        Etiqueta $script:RLista $dir 262 ($y + 6) 290 26 ([TH.Pal]::Cyan) ([TH.Pal]::Mono(12)) | Out-Null
        $b = Boton $script:RLista 'COPIAR' 556 ($y + 2) 110 34 ([TH.Pal]::Pink) $false {
            [Windows.Forms.Clipboard]::SetText($this.Tag)
            Notificar 'DIRECCIÓN COPIADA' "$($this.Tag)`nPégala en WhatsApp o Discord para tus amigos." ([TH.Pal]::Cyan) 3500
        }
        $b.Tag = $dir; $b.Enabled = $r.estado -eq 'Running' -and [bool]$r.ip
        $y += 46
    }
}

# Boton principal: instalar / iniciar sesion / conectar / desconectar segun el estado
function AccionTailscale {
    $estado = if ($script:EstadoTs) { [string]$script:EstadoTs.estado } else { 'SinRespuesta' }
    switch ($estado) {
        'NoInstalado' {
            if (-not (Preguntar "Se instalará Tailscale (gratis, de Tailscale Inc.) con el instalador oficial de Windows. Windows te pedirá permiso de administrador.`n`nAl instalarlo aceptas los términos de uso de Tailscale (tailscale.com/terms)." 'INSTALAR' 'INSTALAR' 'CANCELAR')) { return }
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                Start-Process winget -ArgumentList 'install --id Tailscale.Tailscale -e --accept-package-agreements --accept-source-agreements'
                Notificar 'INSTALANDO TAILSCALE' 'Cuando termine, vuelve a esta ventana y pulsa INICIAR SESIÓN.' ([TH.Pal]::Cyan) 6000
            } else { Start-Process 'https://tailscale.com/download/windows' }
        }
        'NeedsMachineAuth' { Start-Process 'https://login.tailscale.com/admin/machines' }
        'Running' {
            if (-not (Preguntar "Tus amigos no podrán entrar por Tailscale hasta que vuelvas a conectar.`n`n¿Desconectar Tailscale en este PC?" 'DESCONECTAR' 'DESCONECTAR' 'CANCELAR' $true)) { return }
            Async { Ejecutar "$env:ProgramFiles\Tailscale\tailscale.exe" 'down' 20 } { param($x, $err) LeerTailscale $false }
        }
        default {
            # Iniciar sesion o conectar: "tailscale up" muestra un enlace de inicio de sesion si hace falta
            $script:REstado.Text = 'CONECTANDO…'
            Async {
                $psi = New-Object Diagnostics.ProcessStartInfo "$env:ProgramFiles\Tailscale\tailscale.exe", 'up'
                $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
                $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
                $p = [Diagnostics.Process]::Start($psi)
                $texto = New-Object Text.StringBuilder
                $err = $p.StandardError.ReadToEndAsync()
                $limite = (Get-Date).AddSeconds(20); $url = $null
                while ((Get-Date) -lt $limite -and -not $p.HasExited -and -not $url) {
                    Start-Sleep -Milliseconds 300
                    if ($err.IsCompleted) { [void]$texto.Append($err.Result) }
                    $m = [regex]::Match($texto.ToString(), 'https://login\.tailscale\.com/\S+')
                    if ($m.Success) { $url = $m.Value }
                }
                if (-not $url) {
                    $todo = $texto.ToString() + $(if ($p.HasExited) { $p.StandardOutput.ReadToEnd() } else { '' })
                    $m = [regex]::Match($todo, 'https://login\.tailscale\.com/\S+'); if ($m.Success) { $url = $m.Value }
                }
                $url
            } {
                param($url, $err)
                if ($url) {
                    Start-Process $url
                    Notificar 'INICIA SESIÓN EN TAILSCALE' 'Se abrió tu navegador. Inicia sesión y vuelve a ThesknaepHost.' ([TH.Pal]::Cyan) 6000
                }
                LeerTailscale $false
            }
        }
    }
}

function InvitarAmigo {
    $nombre = if ($script:EstadoTs -and $script:EstadoTs.nombre) { $script:EstadoTs.nombre.Split('.')[0] } else { 'tu PC' }
    Aviso ("Para que un amigo entre a tus servidores:`n`n" +
           "1. Se abrirá la web de Tailscale (Machines).`n" +
           "2. En '$nombre' pulsa ⋯ y luego 'Share…'.`n" +
           "3. Copia el enlace y mándaselo a tu amigo.`n`n" +
           "Tu amigo solo verá este PC, no tus otros dispositivos, y puedes quitarle el acceso cuando quieras.") 'INVITAR AMIGO'
    Start-Process 'https://login.tailscale.com/admin/machines'
}

function GuiaAmigos {
    Aviso ("Lo que hace tu amigo (una sola vez):`n`n" +
           "1. Instala Tailscale en su teléfono (Google Play / App Store) o PC (tailscale.com/download).`n" +
           "2. Abre el enlace de invitación que le mandaste e inicia sesión (con Google, Apple, etc.).`n" +
           "3. Deja Tailscale conectado.`n`n" +
           "Para jugar:`n" +
           "• Terraria: Multijugador → Unirse por IP → la IP y el puerto que le copiaste.`n" +
           "• Minecraft Java: Multijugador → Agregar servidor → IP:puerto.`n`n" +
           "Tu servidor tiene que estar PRENDIDO (MIS SERVIDORES) y tu PC encendido.") 'CÓMO SE CONECTAN'
}
