// ThesknaepHost - controles con estilo neon rosado (WinForms, C# 5 para Windows PowerShell 5.1)
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

namespace TH
{
    public static class Pal
    {
        public static readonly Color Bg       = Color.FromArgb(9, 4, 16);
        public static readonly Color BgTop    = Color.FromArgb(30, 6, 38);
        public static readonly Color Panel    = Color.FromArgb(20, 8, 30);
        public static readonly Color PanelTop = Color.FromArgb(34, 11, 48);
        public static readonly Color Pink     = Color.FromArgb(255, 46, 151);
        public static readonly Color PinkSoft = Color.FromArgb(255, 140, 210);
        public static readonly Color Magenta  = Color.FromArgb(170, 30, 160);
        public static readonly Color Cyan     = Color.FromArgb(0, 229, 255);
        public static readonly Color Text     = Color.FromArgb(250, 235, 255);
        public static readonly Color Dim      = Color.FromArgb(150, 112, 170);
        public static readonly Color Green    = Color.FromArgb(60, 255, 175);
        public static readonly Color Red      = Color.FromArgb(255, 70, 110);
        public static readonly Color Amber    = Color.FromArgb(255, 205, 90);

        static FontFamily fam;
        public static FontFamily Tech
        {
            get
            {
                if (fam == null)
                {
                    try { fam = new FontFamily("Bahnschrift"); }
                    catch { fam = new FontFamily("Segoe UI"); }
                }
                return fam;
            }
        }
        public static Font F(float size, FontStyle st) { return new Font(Tech, size, st, GraphicsUnit.Point); }
        public static Font Mono(float size) { return new Font("Consolas", size, FontStyle.Regular, GraphicsUnit.Point); }
        public static Color A(Color c, int a) { return Color.FromArgb(Math.Max(0, Math.Min(255, a)), c); }

        public static GraphicsPath Chamfer(RectangleF r, float c)
        {
            GraphicsPath p = new GraphicsPath();
            p.AddLines(new PointF[] {
                new PointF(r.Left + c, r.Top), new PointF(r.Right, r.Top),
                new PointF(r.Right, r.Bottom - c), new PointF(r.Right - c, r.Bottom),
                new PointF(r.Left, r.Bottom), new PointF(r.Left, r.Top + c) });
            p.CloseFigure();
            return p;
        }

        public static void Smooth(Graphics g)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
        }
    }

    public static class Win
    {
        [DllImport("user32.dll")] public static extern bool ReleaseCapture();
        [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int msg, int w, int l);
        public static void Drag(Form f) { ReleaseCapture(); SendMessage(f.Handle, 0xA1, 0x2, 0); }
        // Barra de desplazamiento oscura (Windows 10 1809+ y Windows 11); si no existe, queda la normal
        [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] static extern int SetWindowTheme(IntPtr h, string app, string id);
        public static void Oscuro(Control c) { try { SetWindowTheme(c.Handle, "DarkMode_Explorer", null); } catch { } }
        // Traer al frente una ventana ya abierta (para que la app no se abra dos veces)
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindow(string cls, string title);
        [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
        [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
        [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
        public static bool TraerAlFrente(string titulo)
        {
            IntPtr h = FindWindow(null, titulo);
            if (h == IntPtr.Zero) return false;
            if (IsIconic(h)) ShowWindow(h, 9 /* SW_RESTORE */);
            SetForegroundWindow(h);
            return true;
        }

        [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
        // Pedir repintado con prioridad baja: Windows pinta cuando no hay clics ni arrastres pendientes
        [DllImport("user32.dll")] public static extern bool InvalidateRect(IntPtr hWnd, ref RECT r, bool erase);
        [DllImport("user32.dll", EntryPoint = "InvalidateRect")] public static extern bool InvalidateAll(IntPtr hWnd, IntPtr r, bool erase);

        // Espera precisa (<1 ms) con temporizador de alta resolucion de Windows 10/11
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateWaitableTimerExW(IntPtr a, string n, uint flags, uint access);
        [DllImport("kernel32.dll")] static extern bool SetWaitableTimer(IntPtr h, ref long due, int period, IntPtr cb, IntPtr arg, bool resume);
        [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint ms);
        [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
        [DllImport("winmm.dll")] static extern uint timeBeginPeriod(uint ms);

        public static IntPtr CrearTemporizador()
        {
            IntPtr t = IntPtr.Zero;
            try { t = CreateWaitableTimerExW(IntPtr.Zero, null, 0x2 /* HIGH_RESOLUTION */, 0x1F0003); } catch { }
            if (t == IntPtr.Zero) { try { timeBeginPeriod(1); } catch { } }
            return t;
        }
        public static void Esperar(IntPtr t, double ms)
        {
            if (ms <= 0) return;
            if (t != IntPtr.Zero)
            {
                long due = -(long)(ms * 10000);               // unidades de 100 ns, negativo = relativo
                if (SetWaitableTimer(t, ref due, 0, IntPtr.Zero, IntPtr.Zero, false)) { WaitForSingleObject(t, 1000); return; }
            }
            Thread.Sleep(Math.Max(1, (int)ms));
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct DEVMODE
        {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
            public ushort dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
            public uint dmFields;
            public int dmPositionX, dmPositionY;
            public uint dmDisplayOrientation, dmDisplayFixedOutput;
            public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
            public ushort dmLogPixels;
            public uint dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
            public uint dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
        }
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);

        // Hz de la pantalla donde esta la ventana
        public static int HzDe(Control c)
        {
            try
            {
                DEVMODE dm = new DEVMODE();
                dm.dmSize = (ushort)Marshal.SizeOf(typeof(DEVMODE));
                if (EnumDisplaySettings(Screen.FromControl(c).DeviceName, -1, ref dm) && dm.dmDisplayFrequency > 1)
                    return (int)dm.dmDisplayFrequency;
            }
            catch { }
            return 60;
        }
    }

    // Ventana sin bordes. El fondo (degradado, rejilla, titulo con brillo, marco) se dibuja UNA vez en un
    // bitmap; cada cuadro solo se repinta la franja de la linea de escaneo. La animacion va sincronizada
    // con los Hz del monitor (temporizador de alta precision) y se pausa mientras arrastras o minimizas la ventana.
    public class NeonForm : Form
    {
        string titulo = "THESKNAEPHOST", sub = "";
        public string Titulo { get { return titulo; } set { titulo = value; fondoSucio = true; Invalidate(); } }
        public string Sub { get { return sub; } set { sub = value; fondoSucio = true; Invalidate(); } }
        public int Frame = 0;                       // compatibilidad: cuadros de 40 ms
        public int Hz { get; private set; }
        public double Fps { get; private set; }     // cuadros por segundo reales de la animacion
        public readonly List<Control> Animados = new List<Control>();

        Bitmap fondo;
        bool fondoSucio = true;
        volatile bool moviendo, minimizado, visible, vivo;
        volatile int scanY = -1000;
        int cuadros;
        long ultimoFps;
        IntPtr hwnd;
        volatile IntPtr[] animados = new IntPtr[0];
        Thread hilo;
        readonly Stopwatch reloj = Stopwatch.StartNew();
        const double VelScan = 0.075;               // pixeles por milisegundo (75 px/s, igual a cualquier Hz)

        public NeonForm()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                     ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            FormBorderStyle = FormBorderStyle.None;
            BackColor = Pal.Bg;
            ForeColor = Pal.Text;
            Hz = 60;
        }

        protected override CreateParams CreateParams
        {
            get { CreateParams cp = base.CreateParams; cp.Style |= 0x20000 /* WS_MINIMIZEBOX */ | 0x02000000 /* WS_CLIPCHILDREN */; return cp; }
        }

        // ---------------------------------------------------------------- bucle sincronizado con los Hz
        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            hwnd = Handle;
            Hz = Win.HzDe(this);
        }
        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            List<IntPtr> hs = new List<IntPtr>();
            foreach (Control c in Animados) hs.Add(c.Handle);   // los handles se leen aqui, en el hilo de la ventana
            animados = hs.ToArray();
            visible = true;
            vivo = true;
            hilo = new Thread(Bucle);
            hilo.IsBackground = true;
            hilo.Name = "ThesknaepHost-Animacion";
            hilo.Start();
        }
        // Animar controles creados despues de abrir la ventana (llamar desde el hilo de la ventana)
        public void Animar(Control c)
        {
            List<IntPtr> hs = new List<IntPtr>(animados);
            hs.Add(c.Handle);
            animados = hs.ToArray();                     // se reemplaza el arreglo entero: seguro para el hilo de animacion
        }
        public void DejarDeAnimar() { animados = new IntPtr[0]; }

        protected override void OnVisibleChanged(EventArgs e) { visible = Visible; base.OnVisibleChanged(e); }
        protected override void OnResize(EventArgs e) { minimizado = WindowState == FormWindowState.Minimized; base.OnResize(e); }
        protected override void OnHandleDestroyed(EventArgs e) { vivo = false; base.OnHandleDestroyed(e); }

        void Bucle()
        {
            IntPtr t = Win.CrearTemporizador();
            try
            {
                double siguiente = reloj.Elapsed.TotalMilliseconds;
                while (vivo)
                {
                    double periodo = 1000.0 / Math.Max(30, Hz);
                    siguiente += periodo;
                    double ahora = reloj.Elapsed.TotalMilliseconds;
                    if (siguiente < ahora - periodo) siguiente = ahora + periodo;   // si nos atrasamos, no recuperar a la carrera
                    Win.Esperar(t, siguiente - ahora);
                    if (!vivo) break;
                    if (!visible || minimizado || moviendo) continue;
                    Cuadro();
                }
            }
            finally { if (t != IntPtr.Zero) Win.CloseHandle(t); }
        }

        // Corre en el hilo de animacion: solo marca zonas a repintar (InvalidateRect es seguro entre hilos)
        void Cuadro()
        {
            long ms = reloj.ElapsedMilliseconds;
            Frame = (int)(ms / 40);
            int w = ClientSize.Width, h = ClientSize.Height;
            int nuevo = (int)((ms * VelScan) % (h + 160)) - 80;
            int viejo = scanY;
            if (nuevo != viejo)
            {
                scanY = nuevo;
                Win.RECT r = new Win.RECT();
                r.Left = 0; r.Right = w;
                r.Top = Math.Min(viejo, nuevo) - 41; r.Bottom = Math.Max(viejo, nuevo) + 41;
                if (Math.Abs(nuevo - viejo) > 200) { r.Top = nuevo - 41; r.Bottom = nuevo + 41; Win.InvalidateAll(hwnd, IntPtr.Zero, false); }
                else Win.InvalidateRect(hwnd, ref r, false);
            }
            IntPtr[] an = animados;
            for (int i = 0; i < an.Length; i++) Win.InvalidateAll(an[i], IntPtr.Zero, false);

            cuadros++;
            if (ms - ultimoFps >= 1000) { Fps = cuadros * 1000.0 / (ms - ultimoFps); cuadros = 0; ultimoFps = ms; }
        }
        // ---------------------------------------------------------------- arrastrar sin tirones
        protected override void WndProc(ref Message m)
        {
            if (m.Msg == 0x0231) moviendo = true;                       // WM_ENTERSIZEMOVE
            if (m.Msg == 0x0232)                                        // WM_EXITSIZEMOVE
            {
                moviendo = false;
                int hz = Win.HzDe(this);                                // por si la moviste a otro monitor
                if (hz != Hz) { Hz = hz; fondoSucio = true; }
                Invalidate();
            }
            base.WndProc(ref m);
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button == MouseButtons.Left && e.Y < 100) Win.Drag(this);
        }

        protected override void OnSizeChanged(EventArgs e) { fondoSucio = true; base.OnSizeChanged(e); }

        // ---------------------------------------------------------------- dibujo
        void CrearFondo()
        {
            int w = Math.Max(2, ClientSize.Width), h = Math.Max(2, ClientSize.Height);
            if (fondo != null) fondo.Dispose();
            fondo = new Bitmap(w, h, PixelFormat.Format32bppPArgb);
            using (Graphics g = Graphics.FromImage(fondo))
            {
                Pal.Smooth(g);
                using (LinearGradientBrush bg = new LinearGradientBrush(new Rectangle(0, 0, w, h), Pal.BgTop, Pal.Bg, 65f))
                    g.FillRectangle(bg, 0, 0, w, h);
                using (Pen grid = new Pen(Pal.A(Pal.Pink, 13)))
                {
                    for (int x = 0; x < w; x += 28) g.DrawLine(grid, x, 0, x, h);
                    for (int y = 0; y < h; y += 28) g.DrawLine(grid, 0, y, w, y);
                }
                using (GraphicsPath tp = new GraphicsPath())
                {
                    tp.AddString(titulo, Pal.Tech, (int)FontStyle.Bold, 42f, new PointF(24, 14), StringFormat.GenericTypographic);
                    for (int i = 5; i >= 1; i--)
                        using (Pen gp = new Pen(Pal.A(Pal.Pink, 24), i * 3f)) { gp.LineJoin = LineJoin.Round; g.DrawPath(gp, tp); }
                    RectangleF b = tp.GetBounds();
                    if (b.Width > 1 && b.Height > 1)
                        using (LinearGradientBrush tb = new LinearGradientBrush(b, Pal.PinkSoft, Pal.Pink, 0f))
                            g.FillPath(tb, tp);
                }
                using (Font f = Pal.Mono(9.5f))
                using (SolidBrush sb = new SolidBrush(Pal.Cyan))
                using (SolidBrush hb = new SolidBrush(Pal.A(Pal.Cyan, 150)))
                {
                    g.DrawString(sub, f, sb, 30, 68);
                    string hz = "SYNC " + Hz + " Hz";
                    SizeF s = g.MeasureString(hz, f);
                    g.DrawString(hz, f, hb, w - 24 - s.Width, 72);
                }
                Rectangle lr = new Rectangle(24, 94, w - 48, 2);
                using (LinearGradientBrush lb = new LinearGradientBrush(lr, Pal.Pink, Pal.A(Pal.Cyan, 0), 0f))
                    g.FillRectangle(lb, lr);
                using (Pen fr = new Pen(Pal.A(Pal.Pink, 120), 1f)) g.DrawRectangle(fr, 0, 0, w - 1, h - 1);
                using (Pen cn = new Pen(Pal.Pink, 3f))
                {
                    g.DrawLine(cn, 1, 1, 40, 1); g.DrawLine(cn, 1, 1, 1, 40);
                    g.DrawLine(cn, w - 2, h - 2, w - 41, h - 2); g.DrawLine(cn, w - 2, h - 2, w - 2, h - 41);
                }
            }
            fondoSucio = false;
        }

        protected override void OnPaintBackground(PaintEventArgs e) { /* todo se pinta en OnPaint */ }

        protected override void OnPaint(PaintEventArgs e)
        {
            if (fondoSucio || fondo == null || fondo.Width != ClientSize.Width || fondo.Height != ClientSize.Height) CrearFondo();
            Graphics g = e.Graphics;
            Rectangle clip = e.ClipRectangle;
            g.CompositingMode = CompositingMode.SourceCopy;
            g.InterpolationMode = InterpolationMode.NearestNeighbor;
            g.DrawImage(fondo, clip, clip, GraphicsUnit.Pixel);       // copia directa, sin escalar
            g.CompositingMode = CompositingMode.SourceOver;

            Rectangle sr = new Rectangle(1, scanY - 40, ClientSize.Width - 2, 80);
            if (sr.IntersectsWith(clip))
                using (LinearGradientBrush sl = new LinearGradientBrush(new Rectangle(sr.X, sr.Y - 1, sr.Width, sr.Height + 2), Color.Transparent, Color.Transparent, 90f))
                {
                    ColorBlend cb = new ColorBlend();
                    cb.Colors = new Color[] { Color.Transparent, Pal.A(Pal.Pink, 34), Color.Transparent };
                    cb.Positions = new float[] { 0f, 0.5f, 1f };
                    sl.InterpolationColors = cb;
                    g.FillRectangle(sl, Rectangle.Intersect(sr, clip));
                }
        }

        protected override void Dispose(bool disposing)
        {
            vivo = false;
            if (disposing && fondo != null) { fondo.Dispose(); fondo = null; }
            base.Dispose(disposing);
        }
    }

    // Tarjeta con esquina cortada, titulo y acentos
    public class NeonPanel : Panel
    {
        public string Titulo = "";
        public string Codigo = "";

        public NeonPanel()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                     ControlStyles.UserPaint | ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
            ForeColor = Pal.Text;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            Pal.Smooth(g);
            if (Width < 30 || Height < 30) return;
            RectangleF r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
            using (GraphicsPath p = Pal.Chamfer(r, 16))
            {
                using (LinearGradientBrush b = new LinearGradientBrush(new Rectangle(0, 0, Width, Height), Pal.A(Pal.PanelTop, 235), Pal.A(Pal.Panel, 235), 90f))
                    g.FillPath(b, p);
                using (Pen pen = new Pen(Pal.A(Pal.Pink, 95), 1f)) g.DrawPath(pen, p);
            }
            using (Pen acc = new Pen(Pal.Pink, 2.5f))
            {
                g.DrawLine(acc, 1, 17, 17, 1);
                g.DrawLine(acc, Width - 40, Height - 1.5f, Width - 18, Height - 1.5f);
                g.DrawLine(acc, Width - 18, Height - 1.5f, Width - 1.5f, Height - 18);
            }
            using (Font tf = Pal.F(11f, FontStyle.Bold))
            using (SolidBrush tb = new SolidBrush(Pal.PinkSoft))
                g.DrawString("▸ " + Titulo, tf, tb, 18, 11);
            if (Codigo.Length > 0)
                using (Font cf = Pal.Mono(8.5f))
                using (SolidBrush cb = new SolidBrush(Pal.A(Pal.Cyan, 170)))
                {
                    SizeF s = g.MeasureString(Codigo, cf);
                    g.DrawString(Codigo, cf, cb, Width - s.Width - 16, 14);
                }
            Rectangle lr = new Rectangle(18, 38, Width - 36, 1);
            using (LinearGradientBrush lb = new LinearGradientBrush(lr, Pal.A(Pal.Pink, 160), Pal.A(Pal.Pink, 0), 0f))
                g.FillRectangle(lb, lr);
        }
    }

    // Boton neon con hover, brillo y esquinas cortadas
    public class NeonButton : Control
    {
        public Color Accent = Pal.Pink;
        public bool Filled = false;
        bool hover, down;

        public NeonButton()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint |
                     ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
            ForeColor = Pal.Text;
            Cursor = Cursors.Hand;
            Font = Pal.F(10f, FontStyle.Bold);
        }

        protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; down = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { down = true; Invalidate(); base.OnMouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e) { down = false; Invalidate(); base.OnMouseUp(e); }
        protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
        protected override void OnTextChanged(EventArgs e) { Invalidate(); base.OnTextChanged(e); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            Pal.Smooth(g);
            if (Width < 8 || Height < 8) return;
            Color a = Enabled ? Accent : Pal.Dim;
            bool h = hover && Enabled;
            RectangleF r = new RectangleF(2f, 2f, Width - 4.5f, Height - 4.5f);
            float c = Math.Min(10f, Height / 3f);
            using (GraphicsPath p = Pal.Chamfer(r, c))
            {
                if (h)
                    using (Pen gl = new Pen(Pal.A(a, 70), 4f)) g.DrawPath(gl, p);
                if (Filled && Enabled)
                {
                    Color c2 = Pal.Magenta;
                    using (LinearGradientBrush b = new LinearGradientBrush(new Rectangle(0, 0, Width, Height),
                           Pal.A(a, down ? 255 : (h ? 240 : 205)), Pal.A(c2, down ? 255 : (h ? 230 : 190)), 0f))
                        g.FillPath(b, p);
                }
                else
                    using (SolidBrush b = new SolidBrush(Pal.A(a, down ? 95 : (h ? 55 : 20)))) g.FillPath(b, p);
                using (Pen pen = new Pen(Pal.A(a, Enabled ? 235 : 110), 1.4f)) g.DrawPath(pen, p);
            }
            Color tc = !Enabled ? Pal.Dim : (Filled ? Color.White : (h ? Color.White : Pal.Text));
            using (SolidBrush tb = new SolidBrush(tc))
            using (StringFormat sf = new StringFormat())
            {
                sf.Alignment = StringAlignment.Center;
                sf.LineAlignment = StringAlignment.Center;
                g.DrawString(Text, Font, tb, new RectangleF(0, 0, Width, Height), sf);
            }
        }
    }

    // Deslizador neon (raton y flechas del teclado). Con Numeros = true dibuja la escala debajo
    // (1, 2, 3, 4... o de 2 en 2, de 5 en 5, etc. segun el espacio), con el valor actual resaltado.
    public class NeonSlider : Control
    {
        int min = 1, max = 10, val = 1;
        bool drag;
        public Color Accent = Pal.Pink;
        public event EventHandler ValueChanged;

        bool numeros;
        public bool Numeros { get { return numeros; } set { numeros = value; Invalidate(); } }
        public double Divisor = 1;      // valor mostrado = Value / Divisor (RAM en pasos de 0,5 GB -> Divisor 2)
        public string Sufijo = "";

        public NeonSlider()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint |
                     ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor | ControlStyles.Selectable, true);
            BackColor = Color.Transparent;
            Cursor = Cursors.Hand;
            TabStop = true;
            Height = 36;
        }

        public int Minimum { get { return min; } set { min = value; if (max < min) max = min; Value = val; Invalidate(); } }
        public int Maximum { get { return max; } set { max = Math.Max(value, min); Value = val; Invalidate(); } }
        public int Value
        {
            get { return val; }
            set
            {
                int v = Math.Max(min, Math.Min(max, value));
                if (v != val) { val = v; Invalidate(); if (ValueChanged != null) ValueChanged(this, EventArgs.Empty); }
            }
        }

        const float Pad = 14f;
        float CentroY { get { return numeros ? 13f : Height / 2f - 2; } }

        void FromX(int x)
        {
            float t = (x - Pad) / Math.Max(1f, Width - 2 * Pad);
            t = Math.Max(0f, Math.Min(1f, t));
            Value = min + (int)Math.Round(t * (max - min));
        }

        protected override void OnMouseDown(MouseEventArgs e) { base.OnMouseDown(e); drag = true; Focus(); FromX(e.X); }
        protected override void OnMouseMove(MouseEventArgs e) { base.OnMouseMove(e); if (drag) FromX(e.X); }
        protected override void OnMouseUp(MouseEventArgs e) { base.OnMouseUp(e); drag = false; }
        protected override bool IsInputKey(Keys k) { return k == Keys.Left || k == Keys.Right || base.IsInputKey(k); }
        protected override void OnKeyDown(KeyEventArgs e)
        {
            base.OnKeyDown(e);
            if (e.KeyCode == Keys.Left) Value = val - 1;
            if (e.KeyCode == Keys.Right) Value = val + 1;
        }
        protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }

        string Texto(double d)
        {
            return (Math.Abs(d - Math.Round(d)) < 0.001 ? ((int)Math.Round(d)).ToString() : d.ToString("0.#")) + Sufijo;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            Pal.Smooth(g);
            float cy = CentroY, x0 = Pad, x1 = Width - Pad;
            if (x1 - x0 < 4) return;
            float t = max == min ? 0f : (val - min) / (float)(max - min);
            float xv = x0 + (x1 - x0) * t;
            Color a = Enabled ? Accent : Pal.Dim;

            using (Pen tr = new Pen(Pal.A(Pal.Dim, 70), 4f)) g.DrawLine(tr, x0, cy, x1, cy);

            if (numeros) DibujarEscala(g, cy, x0, x1, a);
            else
                using (Pen tk = new Pen(Pal.A(Pal.PinkSoft, 70), 1f))
                    for (int i = 0; i <= 10; i++)
                    {
                        float x = x0 + (x1 - x0) * i / 10f;
                        g.DrawLine(tk, x, cy + 8, x, i % 5 == 0 ? cy + 14 : cy + 11);
                    }

            if (xv - x0 > 1)
            {
                using (Pen glow = new Pen(Pal.A(a, 55), 10f)) g.DrawLine(glow, x0, cy, xv, cy);
                RectangleF fr = new RectangleF(x0, cy - 2.5f, xv - x0, 5f);
                using (LinearGradientBrush fb = new LinearGradientBrush(new RectangleF(x0, cy - 3, Math.Max(2f, x1 - x0), 6), Pal.Magenta, Enabled ? Pal.PinkSoft : Pal.Dim, 0f))
                    g.FillRectangle(fb, fr);
            }
            PointF[] d = { new PointF(xv, cy - 10), new PointF(xv + 10, cy), new PointF(xv, cy + 10), new PointF(xv - 10, cy) };
            PointF[] di = { new PointF(xv, cy - 4), new PointF(xv + 4, cy), new PointF(xv, cy + 4), new PointF(xv - 4, cy) };
            using (SolidBrush gb = new SolidBrush(Pal.A(a, Focused || drag ? 90 : 50))) g.FillEllipse(gb, xv - 14, cy - 14, 28, 28);
            using (SolidBrush bb = new SolidBrush(Pal.Bg)) g.FillPolygon(bb, d);
            using (Pen p = new Pen(a, 2f)) g.DrawPolygon(p, d);
            using (SolidBrush ib = new SolidBrush(Enabled ? Pal.Cyan : Pal.Dim)) g.FillPolygon(ib, di);
        }

        void DibujarEscala(Graphics g, float cy, float x0, float x1, Color a)
        {
            double dmin = min / Divisor, dmax = max / Divisor, rango = dmax - dmin;
            if (rango <= 0) return;
            float px = x1 - x0;
            // el paso mas pequeno (1, 2, 5, 10, 20, 25, 50...) que deje ~30 px entre numeros
            double[] lindos = { 1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000 };
            double paso = lindos[lindos.Length - 1];
            foreach (double n in lindos) if (rango / n * 30 <= px) { paso = n; break; }

            // Orden de prioridad: 1) el valor elegido (siempre, justo debajo del rombo), 2) minimo y maximo,
            // 3) numeros redondos de la escala. Un numero que choca con otro ya dibujado no se dibuja.
            double actual = val / Divisor;
            List<double> marcas = new List<double>();
            marcas.Add(actual);
            marcas.Add(dmin);
            marcas.Add(dmax);
            for (double m = Math.Ceiling(dmin / paso - 1e-9) * paso; m < dmax - 1e-9; m += paso)
                if (m > dmin + 1e-9) marcas.Add(m);

            using (Font f = Pal.F(8f, FontStyle.Regular))
            using (Font fa = Pal.F(9f, FontStyle.Bold))
            using (Pen tk = new Pen(Pal.A(Pal.PinkSoft, 90), 1f))
            using (Pen tka = new Pen(a, 2f))
            using (SolidBrush tb = new SolidBrush(Enabled ? Pal.Dim : Pal.A(Pal.Dim, 120)))
            using (SolidBrush ab = new SolidBrush(a))
            using (StringFormat sf = new StringFormat())
            {
                sf.Alignment = StringAlignment.Center;
                List<RectangleF> ocupado = new List<RectangleF>();
                for (int i = 0; i < marcas.Count; i++)
                {
                    double m = marcas[i];
                    bool esActual = i == 0;
                    if (!esActual && Math.Abs(m - actual) < 1e-6) continue;      // ya dibujado como valor elegido
                    float x = x0 + (float)((m - dmin) / rango) * px;
                    string s = Texto(m);
                    Font fu = esActual ? fa : f;
                    SizeF sz = g.MeasureString(s, fu);
                    float tx = Math.Max(sz.Width / 2, Math.Min(Width - sz.Width / 2, x));
                    RectangleF r = new RectangleF(tx - sz.Width / 2 - 4, cy + 14, sz.Width + 8, sz.Height);
                    bool choca = false;
                    foreach (RectangleF o in ocupado) if (o.IntersectsWith(r)) { choca = true; break; }
                    if (choca) continue;
                    ocupado.Add(r);
                    if (esActual) g.DrawLine(tka, x, cy + 8, x, cy + 14);
                    else g.DrawLine(tk, x, cy + 8, x, cy + 13);
                    g.DrawString(s, fu, esActual ? ab : tb, tx, cy + 14, sf);
                }
            }
        }
    }

    // Punto de estado que late
    public class Pulse : Control
    {
        public Color Accent = Pal.Dim;
        public int Frame = 0;

        public Pulse()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint |
                     ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
            Size = new Size(34, 34);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            Pal.Smooth(g);
            float c = Width / 2f;
            float ph = (Environment.TickCount % 1600) / 1600f;   // por tiempo: igual a 60 o 144 Hz
            float rr = 6 + ph * 10;
            using (Pen ring = new Pen(Pal.A(Accent, (int)((1 - ph) * 200)), 2f)) g.DrawEllipse(ring, c - rr, c - rr, rr * 2, rr * 2);
            using (SolidBrush gl = new SolidBrush(Pal.A(Accent, 70))) g.FillEllipse(gl, c - 9, c - 9, 18, 18);
            using (SolidBrush core = new SolidBrush(Accent)) g.FillEllipse(core, c - 5, c - 5, 10, 10);
        }
    }

    // Identidad propia en Windows: la barra de tareas agrupa y muestra el icono de ThesknaepHost, no el de PowerShell
    public static class AppId
    {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        static extern int SetCurrentProcessExplicitAppUserModelID(string id);
        public static void Fijar(string id) { try { SetCurrentProcessExplicitAppUserModelID(id); } catch { } }
    }

    // Notificacion neon que aparece sobre el reloj (abajo a la derecha), sin robar el foco
    public class NeonToast : Form
    {
        static NeonToast actual;
        string titulo, mensaje;
        Color acento;
        Icon icono;
        Action alClic;
        System.Windows.Forms.Timer anim;
        Stopwatch reloj = Stopwatch.StartNew();
        int duracion, yFinal;
        bool cerrando;
        long inicioCierre;

        public static void Mostrar(string titulo, string mensaje, Color acento, Icon icono, int ms, Action alClic)
        {
            if (actual != null && !actual.IsDisposed) actual.Close();
            actual = new NeonToast(titulo, mensaje, acento, icono, ms, alClic);
            actual.Show();
        }

        NeonToast(string t, string m, Color a, Icon ic, int ms, Action clic)
        {
            titulo = t; mensaje = m; acento = a; icono = ic; duracion = Math.Max(1500, ms); alClic = clic;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true);
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            TopMost = true;
            StartPosition = FormStartPosition.Manual;
            BackColor = Pal.Bg;
            Cursor = Cursors.Hand;
            Size = new Size(380, 104);
            Rectangle wa = Screen.PrimaryScreen.WorkingArea;
            yFinal = wa.Bottom - Height - 16;
            Location = new Point(wa.Right - Width - 16, yFinal + 24);
            Opacity = 0;
            anim = new System.Windows.Forms.Timer();
            anim.Interval = 15;
            anim.Tick += Animar;
            anim.Start();
        }

        protected override bool ShowWithoutActivation { get { return true; } }
        protected override CreateParams CreateParams
        {
            get { CreateParams cp = base.CreateParams; cp.ExStyle |= 0x80 /* TOOLWINDOW */ | 0x08000000 /* NOACTIVATE */ | 0x8 /* TOPMOST */; return cp; }
        }

        void Animar(object s, EventArgs e)
        {
            long ms = reloj.ElapsedMilliseconds;
            if (!cerrando)
            {
                double t = Math.Min(1.0, ms / 220.0);
                double suave = 1 - Math.Pow(1 - t, 3);
                Opacity = suave;
                Top = yFinal + (int)Math.Round(24 * (1 - suave));
                if (ms > duracion && !ClientRectangle.Contains(PointToClient(Cursor.Position))) Cerrar();
                Invalidate(new Rectangle(0, Height - 4, Width, 4));    // barra de tiempo
            }
            else
            {
                double t = Math.Min(1.0, (ms - inicioCierre) / 260.0);
                Opacity = 1 - t;
                if (t >= 1) { anim.Stop(); Close(); }
            }
        }

        void Cerrar() { if (!cerrando) { cerrando = true; inicioCierre = reloj.ElapsedMilliseconds; } }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            if (e.X > Width - 34 && e.Y < 30) { Cerrar(); return; }    // la X
            if (alClic != null) { try { alClic(); } catch { } }
            Cerrar();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            Pal.Smooth(g);
            int w = Width, h = Height;
            using (LinearGradientBrush b = new LinearGradientBrush(new Rectangle(0, 0, w, h), Pal.PanelTop, Pal.Bg, 90f)) g.FillRectangle(b, 0, 0, w, h);
            using (Pen grid = new Pen(Pal.A(Pal.Pink, 12)))
                for (int x = 0; x < w; x += 22) g.DrawLine(grid, x, 0, x, h);
            using (GraphicsPath p = Pal.Chamfer(new RectangleF(0.5f, 0.5f, w - 1.5f, h - 1.5f), 14))
            using (Pen borde = new Pen(Pal.A(acento, 200), 1.2f)) g.DrawPath(borde, p);
            using (SolidBrush franja = new SolidBrush(acento)) g.FillRectangle(franja, 0, 14, 4, h - 28);
            using (Pen c = new Pen(acento, 2.5f)) { g.DrawLine(c, 1, 14, 14, 1); g.DrawLine(c, w - 30, h - 1.5f, w - 14, h - 1.5f); g.DrawLine(c, w - 14, h - 1.5f, w - 1.5f, h - 14); }

            if (icono != null) using (Icon ic = new Icon(icono, 40, 40)) g.DrawIcon(ic, new Rectangle(18, 20, 40, 40));
            using (Font ft = Pal.F(11.5f, FontStyle.Bold))
            using (SolidBrush bt = new SolidBrush(Pal.PinkSoft))
                g.DrawString(titulo, ft, bt, new RectangleF(70, 14, w - 110, 24));
            using (Font fm = Pal.F(9.5f, FontStyle.Regular))
            using (SolidBrush bm = new SolidBrush(Pal.Text))
                g.DrawString(mensaje, fm, bm, new RectangleF(70, 40, w - 86, h - 50));
            using (Font fx = Pal.F(11f, FontStyle.Bold))
            using (SolidBrush bx = new SolidBrush(Pal.Dim))
                g.DrawString("×", fx, bx, w - 28, 6);
            // barra que se va vaciando hasta que se oculta
            float resto = cerrando ? 0f : Math.Max(0f, 1f - reloj.ElapsedMilliseconds / (float)duracion);
            using (SolidBrush bb = new SolidBrush(Pal.A(acento, 160))) g.FillRectangle(bb, 4, h - 4, (w - 8) * resto, 2);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && anim != null) { anim.Stop(); anim.Dispose(); }
            base.Dispose(disposing);
        }
    }

    // Menu del icono de la bandeja en estilo neon (fondo oscuro, rosa al pasar el raton)
    public class NeonMenuRenderer : ToolStripRenderer
    {
        protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e)
        {
            using (LinearGradientBrush b = new LinearGradientBrush(e.AffectedBounds, Pal.PanelTop, Pal.Bg, 90f)) e.Graphics.FillRectangle(b, e.AffectedBounds);
        }
        protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e)
        {
            Rectangle r = new Rectangle(0, 0, e.ToolStrip.Width - 1, e.ToolStrip.Height - 1);
            using (Pen p = new Pen(Pal.A(Pal.Pink, 170))) e.Graphics.DrawRectangle(p, r);
            using (Pen c = new Pen(Pal.Pink, 3f)) { e.Graphics.DrawLine(c, 1, 1, 22, 1); e.Graphics.DrawLine(c, 1, 1, 1, 14); }
        }
        protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e)
        {
            if (!e.Item.Selected || !e.Item.Enabled) return;
            Rectangle r = new Rectangle(3, 1, e.Item.Width - 6, e.Item.Height - 2);
            Color a = e.Item.Tag is Color ? (Color)e.Item.Tag : Pal.Pink;
            using (SolidBrush b = new SolidBrush(Pal.A(a, 70))) e.Graphics.FillRectangle(b, r);
            using (SolidBrush f = new SolidBrush(a)) e.Graphics.FillRectangle(f, r.X, r.Y, 3, r.Height);
        }
        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
        {
            Color a = e.Item.Tag is Color ? (Color)e.Item.Tag : Pal.Text;
            e.TextColor = !e.Item.Enabled ? Pal.Dim : (e.Item.Selected ? Color.White : a);
            e.TextRectangle = new Rectangle(e.TextRectangle.X + 6, e.TextRectangle.Y, e.TextRectangle.Width, e.TextRectangle.Height);
            base.OnRenderItemText(e);
        }
        protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e)
        {
            int y = e.Item.Height / 2;
            using (LinearGradientBrush b = new LinearGradientBrush(new Rectangle(8, y, e.Item.Width - 16, 1), Pal.A(Pal.Pink, 150), Pal.A(Pal.Pink, 0), 0f))
                e.Graphics.FillRectangle(b, 8, y, e.Item.Width - 16, 1);
        }
    }
}
