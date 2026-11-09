# ThesknaepHost - ventanas "NUEVO SERVIDOR" y "ARCHIVOS"
# Se carga desde ThesknaepHost.ps1 (usa sus funciones Etiqueta y Boton).

function TarjetaEn($padre, $titulo, $codigo, $x, $y, $w, $h) {
    $p = New-Object TH.NeonPanel
    $p.Titulo = $titulo; $p.Codigo = $codigo
    $p.Location = New-Object Drawing.Point($x, $y); $p.Size = New-Object Drawing.Size($w, $h)
    $padre.Controls.Add($p); $p
}
function CajaTexto($padre, $texto, $x, $y, $w, $max) {
    $t = New-Object Windows.Forms.TextBox
    $t.Text = $texto; $t.MaxLength = $max; $t.BorderStyle = 'FixedSingle'
    $t.BackColor = [Drawing.Color]::FromArgb(32, 11, 46); $t.ForeColor = [TH.Pal]::Text
    $t.Font = [TH.Pal]::F(11, [Drawing.FontStyle]::Regular)
    $t.Location = New-Object Drawing.Point($x, $y); $t.Size = New-Object Drawing.Size($w, 28)
    $padre.Controls.Add($t); $t
}
function Titulito($padre, $texto, $x, $y) {
    $l = Etiqueta $padre $texto $x ($y - 6) 380 24 ([TH.Pal]::Dim) ([TH.Pal]::F(9, [Drawing.FontStyle]::Bold))
    $l.Padding = New-Object Windows.Forms.Padding(0, 5, 0, 0)   # deja espacio para la tilde de la Ñ
    $l
}
function NuevaVentana($titulo, $sub, $w, $h) {
    $d = New-Object TH.NeonForm
    $d.Titulo = $titulo; $d.Sub = $sub; $d.Text = "ThesknaepHost - $titulo"
    $d.ClientSize = New-Object Drawing.Size($w, $h)
    $d.StartPosition = 'CenterParent'; $d.ShowInTaskbar = $false
    if ($f.Icon) { $d.Icon = $f.Icon }
    $x = Boton $d '×' ($w - 54) 14 40 32 ([TH.Pal]::Red) $false { $this.FindForm().Close() }
    $x.Font = [TH.Pal]::F(17, [Drawing.FontStyle]::Bold)
    $d
}

# --- Cuadros de aviso y de pregunta con el estilo de la app (reemplazan a los de Windows)
#     Devuelve el indice del boton pulsado; Enter = boton por defecto, Esc o la X = $cancelar
function DialogoNeon([string]$titulo, [string]$mensaje, [string[]]$botones = @('ACEPTAR'), [int]$defecto = 0, [int]$cancelar = -1, [string]$sub = '// THESKNAEPHOST') {
    if ($cancelar -lt 0) { $cancelar = $botones.Count - 1 }
    $fuente = [TH.Pal]::F(10.5, [Drawing.FontStyle]::Regular)
    $alto = [Windows.Forms.TextRenderer]::MeasureText($mensaje, $fuente, (New-Object Drawing.Size(464, 2000)), [Windows.Forms.TextFormatFlags]::WordBreak).Height
    $h = [Math]::Max(250, 128 + $alto + 84)
    $d = NuevaVentana $titulo $sub 520 $h
    $dueno = $null
    if ($f -and $f.Visible) { $dueno = [Windows.Forms.Form]::ActiveForm; if (-not $dueno -or -not $dueno.Visible) { $dueno = $f } }
    if (-not $dueno) { $d.StartPosition = 'CenterScreen'; $d.TopMost = $true; $d.ShowInTaskbar = $true }

    $l = Etiqueta $d $mensaje 28 116 464 ($alto + 8) ([TH.Pal]::Text) $fuente
    $script:RespDlg = $cancelar
    $ancho = 150; $x = 520 - 24 - ($botones.Count * ($ancho + 10) - 10)
    for ($i = 0; $i -lt $botones.Count; $i++) {
        $acento = if ($i -eq $defecto) { [TH.Pal]::Pink } else { [TH.Pal]::PinkSoft }
        $b = Boton $d $botones[$i] ($x + $i * ($ancho + 10)) ($h - 64) $ancho 42 $acento ($i -eq $defecto) {
            $script:RespDlg = [int]$this.Tag; $this.FindForm().Close()
        }
        $b.Tag = $i
    }
    $d.KeyPreview = $true
    $d.Add_KeyDown({
        param($s, $e)
        if ($e.KeyCode -eq 'Return') { $script:RespDlg = $defecto; $s.Close() }
        if ($e.KeyCode -eq 'Escape') { $script:RespDlg = $cancelar; $s.Close() }
    }.GetNewClosure())
    if ($dueno) { [void]$d.ShowDialog($dueno) } else { [void]$d.ShowDialog() }
    $d.Dispose()
    $script:RespDlg
}
function Preguntar([string]$mensaje, [string]$titulo = 'CONFIRMAR', [string]$si = 'SÍ', [string]$no = 'NO', [bool]$noPorDefecto = $false) {
    (DialogoNeon $titulo $mensaje @($si, $no) $(if ($noPorDefecto) { 1 } else { 0 }) 1) -eq 0
}

# --- Grupos de opciones (solo una elegida) e interruptores ON/OFF
$script:Grupos = @{}
$script:Sel = @{}
function Grupo($padre, [string]$nombre, [string[]]$opciones, $x, $y, $w, $h, $gap, [bool]$vertical, [int]$inicial, [scriptblock]$alCambiar) {
    $lista = @()
    for ($i = 0; $i -lt $opciones.Count; $i++) {
        $bx = if ($vertical) { $x } else { $x + $i * ($w + $gap) }
        $by = if ($vertical) { $y + $i * ($h + $gap) } else { $y }
        $b = Boton $padre $opciones[$i] $bx $by $w $h ([TH.Pal]::Pink) $false { ElegirEnGrupo $this.Tag.g $this.Tag.i }
        $b.Tag = @{ g = $nombre; i = $i }
        $lista += $b
    }
    $script:Grupos[$nombre] = @{ botones = $lista; cambio = $alCambiar }
    ElegirEnGrupo $nombre $inicial
    , $lista
}
function ElegirEnGrupo([string]$nombre, [int]$i) {
    $g = $script:Grupos[$nombre]
    $script:Sel[$nombre] = $i
    for ($k = 0; $k -lt $g.botones.Count; $k++) { $g.botones[$k].Filled = ($k -eq $i); $g.botones[$k].Invalidate() }
    if ($g.cambio) { & $g.cambio $i }
}
function Interruptor($padre, $texto, $x, $y, $w, [bool]$on, [scriptblock]$alCambiar) {
    $b = Boton $padre '' $x $y $w 38 ([TH.Pal]::Cyan) $false {
        $t = $this.Tag; $t.on = -not $t.on; PintarInterruptor $this
        if ($t.cambio) { & $t.cambio $t.on }
    }
    $b.Tag = @{ on = $on; texto = $texto; cambio = $alCambiar }
    PintarInterruptor $b
    $b
}
function PintarInterruptor($b) {
    $b.Filled = $b.Tag.on
    $b.Text = "$($b.Tag.texto)    [ $(if ($b.Tag.on) {'ON'} else {'OFF'}) ]"
    $b.Invalidate()
}

# ==========================================================================================
# NUEVO SERVIDOR
# ==========================================================================================
$TiposTerraria = @(
    @{ id = 'vanilla';    nombre = 'VANILLA';     ram = 4;
       info = 'Terraria original, sin modificaciones. Lo más liviano. Los amigos entran con Terraria normal.' },
    @{ id = 'tshock';     nombre = 'TSHOCK';      ram = 4;
       info = 'Plugins (.dll), permisos, grupos, anti-cheat y comandos de admin. Los amigos entran con Terraria normal. La contraseña se pone en tshock/config.json.' },
    @{ id = 'tmodloader'; nombre = 'TMODLOADER';  ram = 8;
       info = 'Mods (.tmod). Tus amigos necesitan tModLoader (gratis en Steam) y los mismos mods: se descargan solos al entrar.' }
)

# --- Versiones: se descargan en segundo plano (wiki de Terraria y GitHub) y se guardan en memoria
$script:VerCache = @{}
$script:VerLista = @()
$script:VerIdx = 0
$script:VerTipo = ''
$script:VerSel = $null

function MostrarVersion {
    if (-not $script:VerSel -or $script:VerSel.IsDisposed) { return }
    if ($script:VerLista.Count -eq 0) { $script:VerSel.Text = 'CARGANDO VERSIONES…'; return }
    $v = $script:VerLista[$script:VerIdx]
    $script:VerSel.Text = "$($v.label)   [$($script:VerIdx + 1)/$($script:VerLista.Count)]"
}
function CambiarVersion([int]$paso) {
    $n = $script:VerLista.Count
    if ($n -lt 2) { return }
    $script:VerIdx = ($script:VerIdx + $paso + $n) % $n
    MostrarVersion
}
function CargarVersiones([string]$tipo) {
    $script:VerTipo = $tipo; $script:VerIdx = 0
    if ($script:VerCache.ContainsKey($tipo)) { $script:VerLista = $script:VerCache[$tipo]; MostrarVersion; return }
    $script:VerLista = @(); MostrarVersion
    Async {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $h = @{ 'User-Agent' = 'ThesknaepHost' }
        $out = @([pscustomobject]@{ v = 'latest'; label = 'ÚLTIMA VERSIÓN (recomendada)' })
        switch ($A) {
            'vanilla' {
                $html = (Invoke-WebRequest 'https://terraria.wiki.gg/wiki/Server' -UseBasicParsing -Headers $h -TimeoutSec 20).Content
                $nums = [regex]::Matches($html, 'terraria-server-(\d+)\.zip') | ForEach-Object { $_.Groups[1].Value } |
                        Select-Object -Unique | Where-Object { $_ -match '^14[4-9]' }
                foreach ($n in $nums) { $dv = $n.ToCharArray() -join '.'; $out += [pscustomobject]@{ v = $dv; label = "TERRARIA $dv" } }
            }
            'tshock' {
                $rel = Invoke-RestMethod 'https://api.github.com/repos/Pryaxis/TShock/releases?per_page=30' -Headers $h -TimeoutSec 20
                foreach ($x in $rel) {
                    if ($x.prerelease -or $x.tag_name -notmatch '^v[5-9]\.') { continue }   # el egg sirve para TShock 5 o mas
                    $tv = ''
                    foreach ($archivo in $x.assets) { if ($archivo.name -match 'for-Terraria-([\d\.]+?)-') { $tv = $Matches[1]; break } }
                    $out += [pscustomobject]@{ v = $x.tag_name; label = "TSHOCK $($x.tag_name)" + $(if ($tv) { "  ·  TERRARIA $tv" } else { '' }) }
                }
            }
            'tmodloader' {
                $rel = Invoke-RestMethod 'https://api.github.com/repos/tModLoader/tModLoader/releases?per_page=30' -Headers $h -TimeoutSec 20
                $rel | Where-Object { -not $_.prerelease } | Select-Object -First 10 |
                    ForEach-Object { $out += [pscustomobject]@{ v = $_.tag_name; label = "TMODLOADER $($_.tag_name)" } }
            }
            'mc-vanilla' {
                $m = Invoke-RestMethod 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json' -Headers $h -TimeoutSec 20
                $m.versions | Where-Object { $_.type -eq 'release' } | Select-Object -First 30 |
                    ForEach-Object { $out += [pscustomobject]@{ v = $_.id; label = "MINECRAFT $($_.id)" } }
            }
            'mc-paper' {
                $p = Invoke-RestMethod 'https://fill.papermc.io/v3/projects/paper' -Headers $h -TimeoutSec 20
                $lista = foreach ($g in $p.versions.PSObject.Properties) { $g.Value }
                $lista | Where-Object { $_ -notmatch '-' } | Select-Object -First 30 |
                    ForEach-Object { $out += [pscustomobject]@{ v = $_; label = "PAPER $_" } }
            }
            'mc-forge' {
                $fp = Invoke-RestMethod 'https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json' -Headers $h -TimeoutSec 20
                $vers = [ordered]@{}
                foreach ($pr in $fp.promos.PSObject.Properties) {
                    $mcv, $clase = $pr.Name -split '-', 2
                    if ($mcv.Length -gt 9) { continue }                       # el egg acepta hasta 9 caracteres
                    if (-not $vers.Contains($mcv)) { $vers[$mcv] = @{} }
                    $vers[$mcv][$clase] = $pr.Value
                }
                $claves = @($vers.Keys); [array]::Reverse($claves)
                foreach ($mcv in ($claves | Select-Object -First 25)) {
                    $rec = $vers[$mcv]['recommended']
                    $clase = if ($rec) { 'recommended' } else { 'latest' }
                    $fv = if ($rec) { $rec } else { $vers[$mcv]['latest'] }
                    $out += [pscustomobject]@{ v = "$mcv|$clase"; label = "FORGE $mcv  ·  $fv" + $(if ($rec) { ' (recomendada)' } else { ' (última)' }) }
                }
            }
        }
        [pscustomobject]@{ tipo = $A; lista = $out }
    } {
        param($r, $err)
        if ($err -or -not $r) {
            Log "No se pudo leer la lista de versiones: $err"
            $lista = @([pscustomobject]@{ v = 'latest'; label = 'ÚLTIMA VERSIÓN (sin conexión a la lista)' })
            $t = $script:VerTipo
        } else {
            $lista = @($r.lista); $t = $r.tipo
            $script:VerCache[$t] = $lista
        }
        if ($script:VerTipo -eq $t) { $script:VerLista = $lista; $script:VerIdx = 0; MostrarVersion }
    } $tipo
}

# Nombre a mostrar de cada tipo de servidor
$NombreTipo = @{ vanilla = 'TERRARIA VANILLA'; tshock = 'TERRARIA TSHOCK'; tmodloader = 'TERRARIA TMODLOADER'
                 'mc-vanilla' = 'MINECRAFT VANILLA'; 'mc-paper' = 'MINECRAFT PAPER'; 'mc-forge' = 'MINECRAFT FORGE' }

$TiposMinecraft = @(
    @{ id = 'mc-vanilla'; nombre = 'VANILLA'; ram = 6;  disco = 8;
       info = 'Minecraft Java oficial de Mojang, sin cambios. Tus amigos entran con Minecraft Java normal.' },
    @{ id = 'mc-paper';   nombre = 'PAPER';   ram = 8;  disco = 8;
       info = 'Más rápido que Vanilla y acepta plugins (.jar): permisos, protecciones, minijuegos. Entran con Minecraft Java normal.' },
    @{ id = 'mc-forge';   nombre = 'FORGE';   ram = 12; disco = 10;
       info = 'Mods (.jar). Tus amigos necesitan Forge con la misma versión y los mismos mods instalados.' }
)

# Resumen en la ventana NUEVO SERVIDOR (usa las variables de DialogoCrear mientras esta abierta)
function ActualizarResumen {
    if (-not $lResumen -or -not $tbSemilla -or -not $tbMundo) { return }
    $sem = $tbSemilla.Text.Trim()
    if ($script:Juego -eq 'minecraft') {
        $sem = $sem -replace '[^A-Za-z0-9-]', ''
        $modo = $mcModoNombres[$script:Sel['mcmodo']]
        $dif = if ($script:Sel['mcmodo'] -eq 3) { 'DIFÍCIL (hardcore)' } else { $mcDifNombres[$script:Sel['mcdif']] }
        $lResumen.Text = "MUNDO      $(($tbMundo.Text -replace '[^A-Za-z0-9_-]', ''))`n" +
                         "MODO       $modo`n" +
                         "DIFICULTAD $dif`n" +
                         "TERRENO    $($mcTipoNombres[$script:Sel['mctipo']])`n" +
                         "SEMILLA    $(if ($sem) { $sem } else { 'aleatoria' })"
    } else {
        $sem = $sem -replace '[^A-Za-z0-9 ._|-]', ''
        $lResumen.Text = "MUNDO      $(($tbMundo.Text -replace '[^A-Za-z0-9_-]', ''))`n" +
                         "TAMAÑO     $($tamNombres[$script:Sel['tamano']])`n" +
                         "DIFICULTAD $($difNombres[$script:Sel['dificultad']])`n" +
                         "MALDAD     $($malNombres[$script:Sel['maldad']])`n" +
                         "SEMILLA    $(if ($sem) { $sem } else { 'aleatoria' })"
    }
}

# Semilla aleatoria real, en el mismo formato que usa cada juego para sus semillas al azar:
#  Terraria: entero de 1 a 2.147.483.646 (el servidor la usa tal cual, igual que el juego)
#  Minecraft: entero de 64 bits con signo (como las semillas que genera Minecraft)
function SemillaAleatoria([string]$juego) {
    $rng = New-Object Security.Cryptography.RNGCryptoServiceProvider
    $b = New-Object byte[] 8
    $rng.GetBytes($b); $rng.Dispose()
    if ($juego -eq 'minecraft') {
        $n = [BitConverter]::ToInt64($b, 0)
        if ($n -eq 0) { $n = 1 }
        return $n.ToString([Globalization.CultureInfo]::InvariantCulture)
    }
    $u = [BitConverter]::ToUInt32($b, 0)
    return ([uint32](($u % 2147483646) + 1)).ToString([Globalization.CultureInfo]::InvariantCulture)
}

function Subpanel($padre, $x, $y, $w, $h) {
    $p = New-Object Windows.Forms.Panel
    $p.BackColor = [Drawing.Color]::Transparent
    $p.Location = New-Object Drawing.Point($x, $y); $p.Size = New-Object Drawing.Size($w, $h)
    $padre.Controls.Add($p); $p
}
function SliderNumeros($padre, $x, $y, $w, $min, $max, $valor, $divisor, $acento) {
    $s = New-Object TH.NeonSlider
    $s.Numeros = $true; $s.Divisor = $divisor
    if ($acento) { $s.Accent = $acento }
    $s.Location = New-Object Drawing.Point($x, $y); $s.Size = New-Object Drawing.Size($w, 54)
    $s.Minimum = $min; $s.Maximum = $max; $s.Value = $valor
    $padre.Controls.Add($s); $s
}

function DialogoCrear {
    $script:ResultadoCrear = $null
    $script:Juego = 'terraria'
    $d = NuevaVentana 'NUEVO SERVIDOR' '// ELIGE EL JUEGO  ::  TIPO, VERSIÓN, MUNDO Y EXTRAS' 1200 716

    # Valores reales que entiende cada servidor
    $difValores = @(3, 0, 1, 2);  $difNombres = @('VIAJE', 'CLÁSICO', 'EXPERTO', 'MAESTRO')       # Terraria
    $malValores = @('random', 'corrupt', 'crimson'); $malNombres = @('ALEATORIO', 'CORRUPCIÓN', 'CARMESÍ')
    $tamNombres = @('PEQUEÑO', 'MEDIANO', 'GRANDE')
    $mcModoValores = @('survival', 'creative', 'adventure', 'hardcore'); $mcModoNombres = @('SUPERVIVENCIA', 'CREATIVO', 'AVENTURA', 'HARDCORE')
    $mcDifValores = @('peaceful', 'easy', 'normal', 'hard'); $mcDifNombres = @('PACÍFICO', 'FÁCIL', 'NORMAL', 'DIFÍCIL')
    $mcTipoValores = @('normal', 'flat', 'large_biomes', 'amplified'); $mcTipoNombres = @('NORMAL', 'PLANO', 'BIOMAS GRANDES', 'AMPLIFICADO')

    # ================================================================ columna 1: JUEGO, TIPO, VERSIÓN
    $tTipo = TarjetaEn $d 'JUEGO Y TIPO' 'GAME' 24 112 420 330
    $lTipoInfo = Etiqueta $tTipo '' 18 224 384 44 ([TH.Pal]::PinkSoft) ([TH.Pal]::F(8.5, [Drawing.FontStyle]::Regular))
    Titulito $tTipo 'VERSIÓN  ·  si juegan desde Android (Terraria), elige la de tu celular' 18 276 | Out-Null
    Boton $tTipo '<' 18 290 34 32 ([TH.Pal]::PinkSoft) $false { CambiarVersion -1 } | Out-Null
    $script:VerSel = Boton $tTipo 'CARGANDO VERSIONES…' 56 290 308 32 ([TH.Pal]::Cyan) $false { CambiarVersion 1 }
    $script:VerSel.Font = [TH.Pal]::F(9.5, [Drawing.FontStyle]::Regular)
    Boton $tTipo '>' 368 290 34 32 ([TH.Pal]::PinkSoft) $false { CambiarVersion 1 } | Out-Null

    $tExt = TarjetaEn $d 'EXTRAS' 'ADD-ON' 24 452 420 200
    $swBackup = Interruptor $tExt 'BACKUPS AUTOMÁTICOS  (cada 6 h, guarda 3)' 18 44 384 $true $null
    $swApi = Interruptor $tExt 'ACCESO API' 18 86 384 $false $null
    $swSlots = Interruptor $tExt 'SLOTS AL MÁXIMO' 18 128 384 $false {
        param($on)
        if ($on) { $slJug.Value = $slJug.Maximum; $slJug.Enabled = $false } else { $slJug.Enabled = $true }
    }
    Etiqueta $tExt "SIN ANUNCIOS: incluido  ·  SOPORTE: no aplica (el host eres tú)`nANTI-DDOS: no en un PC de casa  ·  FAST DL: no aplica" `
        20 170 390 28 ([TH.Pal]::Dim) ([TH.Pal]::Mono(8)) | Out-Null

    # ================================================================ columna 2: MUNDO
    $tMun = TarjetaEn $d 'MUNDO' 'WORLD' 460 112 360 540
    Titulito $tMun 'NOMBRE DEL MUNDO (letras y números)' 18 48 | Out-Null
    $tbMundo = CajaTexto $tMun 'MiMundo' 18 68 324 32
    Titulito $tMun 'SEMILLA  (en blanco = al azar)' 18 104 | Out-Null
    $tbSemilla = CajaTexto $tMun '' 18 124 226 32
    $bAzar = Boton $tMun 'AL AZAR' 250 122 92 32 ([TH.Pal]::Cyan) $true { $tbSemilla.Text = SemillaAleatoria $script:Juego }
    $bAzar.Font = [TH.Pal]::F(9.5, [Drawing.FontStyle]::Bold)

    # --- Terraria
    $pTer = Subpanel $tMun 0 158 360 270
    Titulito $pTer 'TAMAÑO DEL MAPA' 18 8 | Out-Null
    Grupo $pTer 'tamano' $tamNombres 18 28 104 34 6 $false 1 { ActualizarResumen } | Out-Null
    Titulito $pTer 'DIFICULTAD' 18 74 | Out-Null
    Grupo $pTer 'dificultad' $difNombres 18 94 78 34 4 $false 1 { ActualizarResumen } | Out-Null
    Titulito $pTer 'MALDAD DEL MUNDO' 18 140 | Out-Null
    $bMal = Grupo $pTer 'maldad' $malNombres 18 160 104 34 6 $false 0 { ActualizarResumen }
    $lMalNota = Etiqueta $pTer '' 18 200 324 40 ([TH.Pal]::Amber) ([TH.Pal]::F(8.5, [Drawing.FontStyle]::Regular))

    # --- Minecraft
    $pMc = Subpanel $tMun 0 158 360 270
    Titulito $pMc 'MODO DE JUEGO' 18 8 | Out-Null
    $bModo = @()
    $bModo += Grupo $pMc 'mcmodo' $mcModoNombres[0..1] 18 28 159 32 6 $false 0 $null
    # segunda fila del mismo grupo (AVENTURA, HARDCORE)
    $fila2 = @()
    for ($k = 2; $k -lt 4; $k++) {
        $b = Boton $pMc $mcModoNombres[$k] (18 + ($k - 2) * 165) 64 159 32 ([TH.Pal]::Pink) $false { ElegirEnGrupo $this.Tag.g $this.Tag.i }
        $b.Tag = @{ g = 'mcmodo'; i = $k }; $fila2 += $b
    }
    $script:Grupos['mcmodo'].botones = @($script:Grupos['mcmodo'].botones) + $fila2
    $script:Grupos['mcmodo'].cambio = {
        param($i)
        # HARDCORE = supervivencia en difícil con una sola vida: la dificultad queda fija
        $hc = $i -eq 3
        if ($hc) { ElegirEnGrupo 'mcdif' 3 }
        foreach ($b in $script:Grupos['mcdif'].botones) { $b.Enabled = -not $hc }
        ActualizarResumen
    }
    Titulito $pMc 'DIFICULTAD' 18 108 | Out-Null
    Grupo $pMc 'mcdif' $mcDifNombres 18 128 78 32 4 $false 2 { ActualizarResumen } | Out-Null
    Titulito $pMc 'TIPO DE MUNDO' 18 172 | Out-Null
    Grupo $pMc 'mctipo' $mcTipoNombres[0..1] 18 192 159 32 6 $false 0 $null | Out-Null
    $fila2 = @()
    for ($k = 2; $k -lt 4; $k++) {
        $b = Boton $pMc $mcTipoNombres[$k] (18 + ($k - 2) * 165) 228 159 32 ([TH.Pal]::Pink) $false { ElegirEnGrupo $this.Tag.g $this.Tag.i }
        $b.Tag = @{ g = 'mctipo'; i = $k }; $fila2 += $b
    }
    $script:Grupos['mctipo'].botones = @($script:Grupos['mctipo'].botones) + $fila2
    $script:Grupos['mctipo'].cambio = { ActualizarResumen }
    $pMc.Visible = $false

    Titulito $tMun 'SE CREARÁ ASÍ' 18 436 | Out-Null
    $lResumen = Etiqueta $tMun '' 18 454 324 80 ([TH.Pal]::Cyan) ([TH.Pal]::Mono(9))
    $tbMundo.Add_TextChanged({ ActualizarResumen })
    $tbSemilla.Add_TextChanged({ ActualizarResumen })

    # ================================================================ columna 3: SERVIDOR
    $tCfg = TarjetaEn $d 'SERVIDOR' 'CFG' 836 112 340 540
    Titulito $tCfg 'NOMBRE DEL SERVIDOR' 18 48 | Out-Null
    $tbNombre = CajaTexto $tCfg 'Mi Terraria' 18 68 304 40
    $lClave = Titulito $tCfg 'CONTRASEÑA (opcional)' 18 104
    $tbClave = CajaTexto $tCfg '' 18 124 304 20
    $swPvp = Interruptor $tCfg 'PVP (jugadores se pueden atacar)' 18 104 304 $true $null
    $swPvp.Visible = $false

    Titulito $tCfg 'JUGADORES' 18 166 | Out-Null
    $lJug = Etiqueta $tCfg '' 150 158 172 26 ([TH.Pal]::Pink) ([TH.Pal]::F(14, [Drawing.FontStyle]::Bold))
    $lJug.TextAlign = 'TopRight'
    $slJug = SliderNumeros $tCfg 12 184 316 1 255 8 1 $null
    $actJug = { $lJug.Text = if ($slJug.Value -ge $slJug.Maximum) { "$($slJug.Value) · MÁXIMO" } else { "$($slJug.Value)" } }
    $slJug.Add_ValueChanged($actJug); & $actJug

    Titulito $tCfg 'MEMORIA RAM (GB)' 18 250 | Out-Null
    $lR = Etiqueta $tCfg '' 150 242 172 26 ([TH.Pal]::Pink) ([TH.Pal]::F(14, [Drawing.FontStyle]::Bold))
    $lR.TextAlign = 'TopRight'
    $slR = SliderNumeros $tCfg 12 268 316 2 $slRam.Maximum 4 2 $null

    Titulito $tCfg 'ALMACENAMIENTO (GB)' 18 334 | Out-Null
    $lD = Etiqueta $tCfg '' 150 326 172 26 ([TH.Pal]::Cyan) ([TH.Pal]::F(14, [Drawing.FontStyle]::Bold))
    $lD.TextAlign = 'TopRight'
    $slD = SliderNumeros $tCfg 12 352 316 1 $slDisco.Maximum ([Math]::Min(5, $slDisco.Maximum)) 1 ([TH.Pal]::Cyan)
    # Aviso si se pide mucha mas RAM de la que el juego usa (y que le quita memoria a los demas servidores)
    $actRD = {
        $gb = $slR.Value / 2
        $tope = if ($script:Juego -eq 'minecraft') { 8 } elseif ($script:TipoTerraria -eq 'tmodloader') { 6 } else { 3 }
        if ($gb -gt $tope) { $lR.Text = ('{0:0.0} GB · DE MÁS' -f $gb); $lR.ForeColor = [TH.Pal]::Amber }
        else { $lR.Text = ('{0:0.0} GB' -f $gb); $lR.ForeColor = [TH.Pal]::Pink }
        $lD.Text = "$($slD.Value) GB"
    }
    $slR.Add_ValueChanged($actRD); $slD.Add_ValueChanged($actRD); & $actRD

    $lNotaTer = Etiqueta $tCfg ("El mundo se genera la primera vez que arranca el servidor. Tamaño, dificultad, " +
                                "maldad y semilla quedan fijos en ese mundo: para cambiarlos hay que crear otro.") `
        18 418 304 80 ([TH.Pal]::Dim) ([TH.Pal]::F(8.5, [Drawing.FontStyle]::Regular))
    $swEula = Interruptor $tCfg 'ACEPTO EL EULA DE MINECRAFT' 18 416 304 $false $null
    $lEula = New-Object Windows.Forms.LinkLabel
    $lEula.Text = "Lee el EULA en minecraft.net/eula. Sin aceptarlo el servidor no arranca.`nSolo Minecraft Java (PC): Bedrock/celular no puede entrar."
    $lEula.LinkArea = New-Object Windows.Forms.LinkArea(15, 18)
    $lEula.LinkColor = [TH.Pal]::Cyan; $lEula.ActiveLinkColor = [TH.Pal]::Pink; $lEula.ForeColor = [TH.Pal]::Dim
    $lEula.BackColor = [Drawing.Color]::Transparent; $lEula.Font = [TH.Pal]::F(8.5, [Drawing.FontStyle]::Regular)
    $lEula.Location = New-Object Drawing.Point(18, 460); $lEula.Size = New-Object Drawing.Size(304, 60)
    $lEula.Add_LinkClicked({ Start-Process 'https://www.minecraft.net/eula' })
    $tCfg.Controls.Add($lEula)
    $swEula.Visible = $false; $lEula.Visible = $false

    # ================================================================ lógica
    $alTipo = {
        param($i)
        $lista = if ($script:Juego -eq 'minecraft') { $TiposMinecraft } else { $TiposTerraria }
        $t = $lista[$i]
        $lTipoInfo.Text = $t.info
        $script:TipoTerraria = $t.id
        $slR.Value = [Math]::Min($t.ram, $slR.Maximum)
        & $actRD
        $slD.Value = [Math]::Min($(if ($t.disco) { $t.disco } else { 5 }), $slD.Maximum)
        if ($script:Juego -eq 'terraria') {
            $esTshock = $t.id -eq 'tshock'
            $tbClave.Enabled = -not $esTshock
            # Solo TShock puede fijar la maldad (-worldevil); en los otros el servidor la elige al azar
            if ($esTshock) { foreach ($b in $bMal) { $b.Enabled = $true }; $lMalNota.Text = '' }
            else {
                ElegirEnGrupo 'maldad' 0
                foreach ($b in $bMal) { $b.Enabled = $false }
                $lMalNota.Text = 'El servidor Vanilla/tModLoader no permite elegirla: sale al azar. Para elegirla usa TShock.'
            }
        }
        CargarVersiones $t.id
        ActualizarResumen
    }
    $bTipo = Grupo $tTipo 'tipo' @('VANILLA  ::  ORIGINAL', 'TSHOCK  ::  PLUGINS', 'TMODLOADER  ::  MODS') 18 100 384 34 6 $true 0 $alTipo

    $alJuego = {
        param($i)
        $script:Juego = @('terraria', 'minecraft')[$i]
        $mc = $script:Juego -eq 'minecraft'
        $textos = if ($mc) { @('VANILLA  ::  ORIGINAL', 'PAPER  ::  PLUGINS', 'FORGE  ::  MODS') } else { @('VANILLA  ::  ORIGINAL', 'TSHOCK  ::  PLUGINS', 'TMODLOADER  ::  MODS') }
        for ($k = 0; $k -lt 3; $k++) { $bTipo[$k].Text = $textos[$k] }
        $pTer.Visible = -not $mc; $pMc.Visible = $mc
        $lClave.Visible = -not $mc; $tbClave.Visible = -not $mc; $swPvp.Visible = $mc
        $lNotaTer.Visible = -not $mc; $swEula.Visible = $mc; $lEula.Visible = $mc
        if ($tbNombre.Text -in @('Mi Terraria', 'Mi Minecraft')) { $tbNombre.Text = if ($mc) { 'Mi Minecraft' } else { 'Mi Terraria' } }
        if ($tbMundo.Text -in @('MiMundo', 'world')) { $tbMundo.Text = if ($mc) { 'world' } else { 'MiMundo' } }
        $tbSemilla.MaxLength = if ($mc) { 32 } else { 20 }
        $slJug.Enabled = $true; $swSlots.Tag.on = $false; PintarInterruptor $swSlots
        $slJug.Maximum = if ($mc) { 100 } else { 255 }
        $slJug.Value = if ($mc) { 10 } else { 8 }
        & $actJug
        ElegirEnGrupo 'tipo' 0
    }
    Grupo $tTipo 'juego' @('TERRARIA', 'MINECRAFT') 18 48 189 42 6 $false 0 $alJuego | Out-Null
    foreach ($b in $script:Grupos['juego'].botones) { $b.Font = [TH.Pal]::F(13, [Drawing.FontStyle]::Bold) }

    # ================================================================ botones
    Boton $d 'CANCELAR' 24 664 200 42 ([TH.Pal]::PinkSoft) $false { $this.FindForm().Close() } | Out-Null
    Boton $d '+  CREAR SERVIDOR' 916 664 260 42 ([TH.Pal]::Pink) $true {
        $mc = $script:Juego -eq 'minecraft'
        $mundo = ($tbMundo.Text -replace '[^A-Za-z0-9_-]', '')
        if (-not $mundo) { Aviso 'Ponle un nombre al mundo (solo letras y números).' 'FALTA EL NOMBRE'; return }
        if ($mc -and -not $swEula.Tag.on) {
            Aviso "Para crear un servidor de Minecraft tienes que aceptar el EULA de Mojang (minecraft.net/eula).`n`nActiva 'ACEPTO EL EULA DE MINECRAFT'." 'EULA'; return
        }
        $permitido = if ($mc) { '[^A-Za-z0-9-]' } else { '[^A-Za-z0-9 ._|-]' }
        $semilla = ($tbSemilla.Text -replace $permitido, '').Trim()
        if ($semilla -ne $tbSemilla.Text.Trim()) {
            $txt = if ($mc) { 'letras, números y -' } else { 'letras, números, espacios y . _ - |' }
            Aviso "La semilla solo puede tener $txt.`n`nSe usará: '$semilla'" 'SEMILLA'
        }
        $version = if ($script:VerLista.Count -gt 0) { $script:VerLista[$script:VerIdx].v } else { 'latest' }
        $lista = if ($mc) { $TiposMinecraft } else { $TiposTerraria }
        $r = @{
            juego = $script:Juego; tipo = $lista[$script:Sel['tipo']].id; version = $version
            nombre = $tbNombre.Text.Trim(); mundo = $mundo; semilla = $semilla
            jugadores = $slJug.Value; ram = [int]($slR.Value * 512); disco = [int]($slD.Value * 1024)
            backups = [bool]$swBackup.Tag.on; api = [bool]$swApi.Tag.on
        }
        if ($mc) {
            $r.modo = $mcModoValores[$script:Sel['mcmodo']]; $r.dif_mc = $mcDifValores[$script:Sel['mcdif']]
            $r.tipo_mundo = $mcTipoValores[$script:Sel['mctipo']]; $r.pvp = [bool]$swPvp.Tag.on; $r.eula = $true
        } else {
            $r.tamano = $script:Sel['tamano'] + 1; $r.dificultad = $difValores[$script:Sel['dificultad']]
            $r.maldad = $malValores[$script:Sel['maldad']]; $r.clave = $tbClave.Text
        }
        $script:ResultadoCrear = $r
        $d.Close()
    } | Out-Null

    ActualizarResumen
    [void]$d.ShowDialog($f)
    $d.Dispose()
    $script:ResultadoCrear
}


# ==========================================================================================
# ARCHIVOS: mundos, plugins y mods
# ==========================================================================================
function DialogoArchivos($s) {
    $script:ResultadoArchivos = $null
    $tipoTxt = $NombreTipo[[string]$s.tipo]
    if (-not $tipoTxt) { $tipoTxt = $s.egg.ToUpper() }
    $esMc = ([string]$s.tipo).StartsWith('mc-')
    $mundoTxt = if ($s.world) { "  ::  MUNDO $($s.world)" } else { '' }
    $d = NuevaVentana 'ARCHIVOS' "// $($s.name.ToUpper())  ::  $tipoTxt$mundoTxt" 640 560

    $t = TarjetaEn $d 'TUS MAPAS, PLUGINS Y MODS' 'FS' 24 112 592 380
    $elegir = {
        param($accion, $filtro)
        $ofd = New-Object Windows.Forms.OpenFileDialog
        $ofd.Filter = $filtro; $ofd.Multiselect = ($accion -notlike 'mundo*')
        if ($ofd.ShowDialog($d) -ne 'OK') { return }
        $principal = $false
        if ($accion -eq 'mundo-mc') {
            if (-not (Preguntar "El mundo se copiará en lugar del mundo actual del servidor (el actual se guarda con otro nombre).`n`nApaga el servidor antes de continuar." 'SUBIR MUNDO' 'CONTINUAR' 'CANCELAR')) { return }
        }
        if ($accion -eq 'mundo') {
            $principal = Preguntar "¿Usar este mundo como el mundo principal del servidor?`n`nSe cargará la próxima vez que lo reinicies." 'MUNDO PRINCIPAL' 'SÍ, USARLO' 'NO'
        }
        $script:ResultadoArchivos = @{ accion = $accion; archivos = @($ofd.FileNames); principal = $principal }
        $d.Close()
    }

    Boton $t 'ABRIR CARPETA DEL SERVIDOR' 18 50 556 42 ([TH.Pal]::Pink) $true {
        $script:ResultadoArchivos = @{ accion = 'carpeta' }; $this.FindForm().Close()
    } | Out-Null
    if ($esMc) {
        Boton $t 'SUBIR MUNDO  (.zip con la carpeta del mundo)' 18 100 556 42 ([TH.Pal]::Pink) $false { & $elegir 'mundo-mc' 'Mundo de Minecraft comprimido (*.zip)|*.zip' } | Out-Null
        $bPlug = Boton $t 'SUBIR PLUGIN  (.jar)  ::  PAPER' 18 150 556 42 ([TH.Pal]::Cyan) $false { & $elegir 'plugin-mc' 'Plugins de Paper/Bukkit (*.jar)|*.jar' }
        $bMod = Boton $t 'SUBIR MOD  (.jar)  ::  FORGE' 18 200 556 42 ([TH.Pal]::Cyan) $false { & $elegir 'mod-mc' 'Mods de Forge (*.jar)|*.jar' }
        $bPlug.Enabled = $s.tipo -eq 'mc-paper'
        $bMod.Enabled = $s.tipo -eq 'mc-forge'
    } else {
        Boton $t 'SUBIR MUNDO  (.wld)' 18 100 556 42 ([TH.Pal]::Pink) $false { & $elegir 'mundo' 'Mundos de Terraria (*.wld)|*.wld' } | Out-Null
        $bPlug = Boton $t 'SUBIR PLUGIN  (.dll)  ::  TSHOCK' 18 150 556 42 ([TH.Pal]::Cyan) $false { & $elegir 'plugin' 'Plugins de TShock (*.dll)|*.dll' }
        $bMod = Boton $t 'SUBIR MOD  (.tmod)  ::  TMODLOADER' 18 200 556 42 ([TH.Pal]::Cyan) $false { & $elegir 'mod' 'Mods de tModLoader (*.tmod)|*.tmod' }
        $bPlug.Enabled = $s.tipo -eq 'tshock'
        $bMod.Enabled = $s.tipo -eq 'tmodloader'
    }
    Boton $t 'GESTOR DE ARCHIVOS WEB' 18 250 556 42 ([TH.Pal]::PinkSoft) $false {
        Start-Process "$PanelUrl/server/$($s.short)/files"
    } | Out-Null

    $donde = switch ($s.tipo) {
        'tshock'     { 'Mundos: carpeta principal   ·   Plugins: ServerPlugins   ·   Config: tshock' }
        'tmodloader' { 'Mundos: saves\Worlds   ·   Mods: mods (se activan solos)' }
        'mc-paper'   { 'Mundo: carpeta del mundo (level-name)   ·   Plugins: plugins' }
        'mc-forge'   { 'Mundo: carpeta del mundo (level-name)   ·   Mods: mods' }
        'mc-vanilla' { 'Mundo: carpeta del mundo (level-name)   ·   Ajustes: server.properties' }
        default      { 'Mundos: saves\Worlds' }
    }
    $nota = "$donde`nSFTP: 127.0.0.1:2022   ·   usuario admin.$($s.short)   ·   tu clave del panel`n" +
            "Apaga el servidor antes de cambiar el mundo. Si arrastras archivos con el Explorador, pulsa ACTUALIZAR después."
    Etiqueta $t $nota 20 302 560 70 ([TH.Pal]::Dim) ([TH.Pal]::Mono(8.5)) | Out-Null

    Boton $d 'CERRAR' 416 504 200 42 ([TH.Pal]::PinkSoft) $false { $this.FindForm().Close() } | Out-Null
    [void]$d.ShowDialog($f)
    $d.Dispose()
    $script:ResultadoArchivos
}
