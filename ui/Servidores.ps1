# ThesknaepHost - ventana "MIS SERVIDORES": ver todos los servidores, prenderlos, apagarlos y reiniciarlos.
# Se carga desde ThesknaepHost.ps1. Es una ventana normal (no bloquea la principal) y se actualiza cada 5 s.

$script:VentanaServ = $null
$script:Tarjetas = @{}
$script:IdsServ = $null
$script:RefrescandoServ = $false

# Como se ve cada estado de Wings
$EstadosServ = @{
    running            = @{ txt = 'EN LÍNEA';          color = [TH.Pal]::Green }
    starting           = @{ txt = 'ARRANCANDO…';       color = [TH.Pal]::Amber }
    stopping           = @{ txt = 'APAGANDO…';         color = [TH.Pal]::Amber }
    offline            = @{ txt = 'APAGADO';           color = [TH.Pal]::Red }
    instalando         = @{ txt = 'INSTALANDO…';       color = [TH.Pal]::Cyan }
    error_instalacion  = @{ txt = 'ERROR AL INSTALAR'; color = [TH.Pal]::Red }
    suspendido         = @{ txt = 'SUSPENDIDO';        color = [TH.Pal]::Dim }
    sin_conexion       = @{ txt = 'SIN CONEXIÓN';      color = [TH.Pal]::Dim }
}

function TiempoEncendido([int]$seg) {
    if ($seg -le 0) { return '' }
    $t = [TimeSpan]::FromSeconds($seg)
    if ($t.TotalDays -ge 1) { return "encendido hace $([int][Math]::Floor($t.TotalDays)) d $($t.Hours) h" }
    if ($t.TotalHours -ge 1) { return "encendido hace $($t.Hours) h $($t.Minutes) min" }
    return "encendido hace $([Math]::Max(1, $t.Minutes)) min"
}

function AbrirServidores {
    if ($script:VentanaServ -and -not $script:VentanaServ.IsDisposed) { $script:VentanaServ.Activate(); return }
    if (-not ($script:Estado -and $script:Estado.web)) { Aviso 'Pulsa INICIAR primero: el panel tiene que estar en línea para ver tus servidores.'; return }

    $w = NuevaVentana 'MIS SERVIDORES' '// PRENDER · APAGAR · REINICIAR  ::  SE ACTUALIZA CADA 5 SEGUNDOS' 900 640
    $w.ShowInTaskbar = $true
    $w.StartPosition = 'Manual'
    $w.Location = New-Object Drawing.Point(($f.Left + [int](($f.Width - 900) / 2)), ([Math]::Max(0, $f.Top - 10)))
    $script:VentanaServ = $w
    $script:Tarjetas = @{}
    $script:IdsServ = $null

    # Lista con desplazamiento
    $lista = New-Object Windows.Forms.Panel
    $lista.Location = New-Object Drawing.Point(24, 108); $lista.Size = New-Object Drawing.Size(852, 462)
    $lista.AutoScroll = $true
    $lista.BackColor = [TH.Pal]::Bg
    $w.Controls.Add($lista)
    $script:ListaServ = $lista

    $script:VacioServ = Etiqueta $lista 'Cargando servidores…' 0 20 828 60 ([TH.Pal]::Dim) ([TH.Pal]::F(12, [Drawing.FontStyle]::Regular))
    $script:VacioServ.TextAlign = 'MiddleCenter'

    # Pie
    $script:PieServ = Etiqueta $w '' 26 584 360 20 ([TH.Pal]::Cyan) ([TH.Pal]::Mono(8.5))
    Boton $w '+ CREAR SERVIDOR' 404 578 170 40 ([TH.Pal]::Pink) $false { CrearServidor } | Out-Null
    Boton $w 'CONSOLA LINUX' 580 578 140 40 ([TH.Pal]::PinkSoft) $false {
        Start-Process wsl.exe -ArgumentList "-d $Distro -u root --cd ~"
    } | Out-Null
    Boton $w 'CERRAR' 726 578 150 40 ([TH.Pal]::PinkSoft) $false { $this.FindForm().Close() } | Out-Null

    $tm = New-Object Windows.Forms.Timer
    $tm.Interval = 5000
    $tm.Add_Tick({ RefrescarServidores })
    $script:TimerServ = $tm
    $w.Add_Shown({ $script:TimerServ.Start(); RefrescarServidores })
    $w.Add_FormClosed({
        $script:TimerServ.Stop(); $script:TimerServ.Dispose()
        $script:VentanaServ = $null; $script:Tarjetas = @{}
    })
    $w.Show($f)
}

function RefrescarServidores {
    if ($script:RefrescandoServ) { return }
    if (-not $script:VentanaServ -or $script:VentanaServ.IsDisposed) { return }
    $script:RefrescandoServ = $true
    Async { Recursos @('estado') } {
        param($r, $err)
        $script:RefrescandoServ = $false
        $w = $script:VentanaServ
        if (-not $w -or $w.IsDisposed) { return }
        if ($err -or -not $r -or -not $r.ok) {
            $m = if ($err) { $err } elseif ($r) { $r.error } else { 'sin respuesta' }
            $script:PieServ.ForeColor = [TH.Pal]::Amber
            $script:PieServ.Text = "No se pudo leer el estado: $m"
            return
        }
        PintarServidores @($r.servers)
    }
}

function CrearTarjeta($s, [int]$y) {
    $c = New-Object TH.NeonPanel
    # con desplazamiento, las posiciones van relativas a lo que ya se movio la lista
    $c.Location = New-Object Drawing.Point(0, ($y + $script:ListaServ.AutoScrollPosition.Y)); $c.Size = New-Object Drawing.Size(828, 114)
    $script:ListaServ.Controls.Add($c)

    $pulso = New-Object TH.Pulse
    $pulso.Location = New-Object Drawing.Point(16, 50)
    $c.Controls.Add($pulso)
    $script:VentanaServ.Animar($pulso)

    $estado = Etiqueta $c '' 56 46 250 30 ([TH.Pal]::Text) ([TH.Pal]::F(15, [Drawing.FontStyle]::Bold))
    $info = Etiqueta $c '' 58 78 300 32 ([TH.Pal]::PinkSoft) ([TH.Pal]::Mono(8.5))
    $uso = Etiqueta $c '' 330 46 230 62 ([TH.Pal]::Cyan) ([TH.Pal]::Mono(9))

    $bOn = Boton $c 'PRENDER' 574 44 118 32 ([TH.Pal]::Green) $true { AccionServidor $this.Tag.id 'start' $this.Tag.nombre }
    $bOff = Boton $c 'APAGAR' 698 44 118 32 ([TH.Pal]::Red) $false { AccionServidor $this.Tag.id 'stop' $this.Tag.nombre }
    $bRe = Boton $c 'REINICIAR' 574 80 118 28 ([TH.Pal]::Amber) $false { AccionServidor $this.Tag.id 'restart' $this.Tag.nombre }
    $bCon = Boton $c 'CONSOLA' 698 80 118 28 ([TH.Pal]::Cyan) $false { Start-Process "$PanelUrl/server/$($this.Tag.short)" }
    foreach ($b in $bOn, $bOff, $bRe, $bCon) { $b.Tag = @{ id = $s.id; short = $s.short; nombre = $s.name } }
    foreach ($b in $bRe, $bCon) { $b.Font = [TH.Pal]::F(9, [Drawing.FontStyle]::Bold) }

    @{ panel = $c; pulso = $pulso; estado = $estado; info = $info; uso = $uso; on = $bOn; off = $bOff; re = $bRe; pendiente = $null }
}

function PintarServidores($servidores) {
    $ids = ($servidores | ForEach-Object { $_.id }) -join ','
    if ($ids -ne $script:IdsServ) {
        # Cambiaron los servidores (creaste o borraste uno): se rehacen las tarjetas
        $script:VentanaServ.DejarDeAnimar()
        foreach ($t in $script:Tarjetas.Values) { $script:ListaServ.Controls.Remove($t.panel); $t.panel.Dispose() }
        $script:Tarjetas = @{}
        $y = 0
        foreach ($s in $servidores) { $script:Tarjetas[[string]$s.id] = CrearTarjeta $s $y; $y += 124 }
        $script:IdsServ = $ids
    }
    $script:VacioServ.Visible = $servidores.Count -eq 0
    if ($servidores.Count -eq 0) { $script:VacioServ.Text = 'No tienes servidores todavía. Pulsa + CREAR SERVIDOR.' }

    $enLinea = 0
    foreach ($s in $servidores) {
        $t = $script:Tarjetas[[string]$s.id]
        $estado = [string]$s.estado
        # Si pediste prender/apagar hace poco, se muestra eso hasta que Wings cambie de estado
        if ($t.pendiente -and $t.pendiente.hasta -gt (Get-Date) -and $estado -eq $t.pendiente.desde) { $estado = $t.pendiente.estado } else { $t.pendiente = $null }
        $e = $EstadosServ[$estado]
        if (-not $e) { $e = @{ txt = $estado.ToUpper(); color = [TH.Pal]::Dim } }
        if ($estado -eq 'running') { $enLinea++ }

        $t.panel.Titulo = $s.name
        $t.panel.Codigo = "#$($s.id)  ·  PUERTO $($s.port)"
        $t.panel.Invalidate()
        $t.pulso.Accent = $e.color
        $t.estado.Text = $e.txt; $t.estado.ForeColor = $e.color
        $tipo = $NombreTipo[[string]$s.tipo]; if (-not $tipo) { $tipo = ([string]$s.egg).ToUpper() }
        $t.info.Text = "$tipo`n$(TiempoEncendido $s.uptime)"
        $t.uso.Text = if ($estado -in 'running', 'starting', 'stopping') {
            # Wings cuenta 100 % por nucleo (204 % = 2 nucleos): se muestra como % del PC completo
            ("RAM    {0:0.0} / {1:0.0} GB`nCPU    {2:0} % del PC`nDISCO  {3:0.0} / {4:0.0} GB" -f ($s.ram / 1024), ($s.memory / 1024), ($s.cpu / [Environment]::ProcessorCount), ($s.disco_usado / 1024), ($s.disk / 1024))
        } else {
            ("RAM    {0:0.0} GB`nCPU    -`nDISCO  {1:0.0} / {2:0.0} GB" -f ($s.memory / 1024), ($s.disco_usado / 1024), ($s.disk / 1024))
        }
        $listo = $estado -notin 'instalando', 'error_instalacion', 'suspendido', 'sin_conexion'
        $t.on.Enabled  = $listo -and $estado -eq 'offline'
        $t.off.Enabled = $listo -and $estado -in 'running', 'starting'
        $t.re.Enabled  = $listo -and $estado -eq 'running'
    }
    if ($script:Bandeja) { $script:Bandeja.Text = "ThesknaepHost · $enLinea de $($servidores.Count) servidor(es) en línea" }
    $script:PieServ.ForeColor = [TH.Pal]::Cyan
    $script:PieServ.Text = "ACTUALIZADO $(Get-Date -Format 'HH:mm:ss')  ·  $($servidores.Count) SERVIDOR(ES)  ·  $enLinea EN LÍNEA"
}

function AccionServidor([int]$id, [string]$accion, [string]$nombre) {
    $t = $script:Tarjetas[[string]$id]
    $txt = @{ start = 'Prendiendo'; stop = 'Apagando'; restart = 'Reiniciando' }[$accion]
    if ($t) {
        $nuevo = @{ start = 'starting'; stop = 'stopping'; restart = 'starting' }[$accion]
        $desde = @{ start = 'offline'; stop = 'running'; restart = 'running' }[$accion]
        $t.pendiente = @{ estado = $nuevo; desde = $desde; hasta = (Get-Date).AddSeconds(20) }
        $e = $EstadosServ[$nuevo]
        $t.estado.Text = $e.txt; $t.estado.ForeColor = $e.color; $t.pulso.Accent = $e.color
        $t.on.Enabled = $false; $t.off.Enabled = $false; $t.re.Enabled = $false
    }
    Log "$txt '$nombre'..."
    Async { Recursos @('power', "$($A.id)", $A.accion) } {
        param($r, $err)
        if ($err -or -not $r -or -not $r.ok) {
            $m = if ($err) { $err } else { $r.error }
            Log "ERROR: $m"; Aviso "No se pudo cambiar el estado del servidor:`n$m"
        }
        RefrescarServidores
    } @{ id = $id; accion = $accion }
}
