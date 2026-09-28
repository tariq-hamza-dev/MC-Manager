# MC Manager - by Hamza
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, System.IO.Compression.FileSystem
# If startup ever fails, show the reason instead of silently doing nothing (the console is hidden)
trap { [void][Windows.Forms.MessageBox]::Show("$($_.Exception.Message)`n`n$($_.InvocationInfo.PositionMessage)", 'MC Manager failed to start'); exit 1 }
[Windows.Forms.Application]::EnableVisualStyles()

# Hide the console window safely on startup
if (-not ('Win32.Win32Console' -as [type])) {
    $null = Add-Type -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
'@ -Name Win32Console -Namespace Win32
}
[void][Win32.Win32Console]::ShowWindow([Win32.Win32Console]::GetConsoleWindow(), 0)

# ---------------- config ----------------
$appDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$dataDir = Join-Path $appDir 'data'          # everything the app saves stays here, next to the script
$cfgPath = Join-Path $dataDir 'config.json'
$cfg = [ordered]@{
    saves = ''; backups = ''   # no default folders: they are set when you pick them with Browse
    replace = $false; safety = $false; auto = $false; only = $false; keepOn = $false; keep = '10'; autoMin = '15'
}

if (Test-Path $cfgPath) {
    try {
        $j = Get-Content $cfgPath -Raw | ConvertFrom-Json
        foreach ($k in @($cfg.Keys)) { if ($null -ne $j.$k) { $cfg[$k] = $j.$k } }
    } catch {}
} else {
    try {
        [void][IO.Directory]::CreateDirectory($dataDir)
        $cfg | ConvertTo-Json | Set-Content $cfgPath -Encoding UTF8
    } catch {}
}
# ---------------- layout (one height / margin / button size everywhere) ----------------
$M = 20; $W = 840; $H = 34; $BW = 90; $GAP = 8; $COL = 410; $X2 = $M + $COL + 20; $AB = 130
function C($hex) { [Drawing.ColorTranslator]::FromHtml($hex) }
$BG = C '#16181d'; $CARD = C '#23262d'; $FG = C '#e6e6e6'; $MUTED = C '#8a8f98'
$ACC = C '#3C8527'; $ACCH = C '#52A535'; $GTXT = C '#5fd13d'; $HOVER = C '#2f333c'; $YEL = C '#f5c542'; $RED = C '#ff6b64'; $BORDER = C '#565b66'

$form = [Windows.Forms.Form]@{
    Text = 'MC Manager'; ClientSize = "$($W + 2 * $M),576"; BackColor = $BG; ForeColor = $FG
    FormBorderStyle = 'FixedSingle'; MaximizeBox = $false; StartPosition = 'CenterScreen'
    KeyPreview = $true; Font = New-Object Drawing.Font('Segoe UI', 9.5)
}
function New-AppIcon {   # plain square icon: green tile with a white M
    $bmp = New-Object Drawing.Bitmap 32, 32
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.TextRenderingHint = 'AntiAlias'; $g.Clear($ACC)
    $sf = New-Object Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $font = New-Object Drawing.Font('Segoe UI', 20, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
    $g.DrawString('M', $font, [Drawing.Brushes]::White, (New-Object Drawing.RectangleF 0, 0, 32, 32), $sf)
    $g.Dispose(); [Drawing.Icon]::FromHandle($bmp.GetHicon())
}
$form.Icon = New-AppIcon

function Add($ctl, $x, $y, $w, $h) { $ctl.SetBounds($x, $y, $w, $h); $form.Controls.Add($ctl); $ctl }
function Label($text, $x, $y, $w, $h = 20, $col = $MUTED, $align = 'MiddleLeft') {
    [void](Add ([Windows.Forms.Label]@{ Text = $text; ForeColor = $col; TextAlign = $align; UseCompatibleTextRendering = $false }) $x $y $w $h)
}
function Button($text, $x, $y, $w, $bg = $CARD, $fg = $FG, $hover = $HOVER) {
    $b = [Windows.Forms.Button]@{ Text = $text; FlatStyle = 'Flat'; BackColor = $bg; ForeColor = $fg; Cursor = 'Hand'; UseCompatibleTextRendering = $false }
    $b.FlatAppearance.BorderSize = 0; $b.FlatAppearance.MouseOverBackColor = $hover
    Add $b $x $y $w $H
}
$tip = New-Object Windows.Forms.ToolTip
function Field($text, $x, $y, $w, $center = $false, $isPath = $false) {
    $p = Add ([Windows.Forms.Panel]@{ BackColor = $CARD }) $x $y $w $H
    $t = [Windows.Forms.TextBox]@{ Text = "$text"; BorderStyle = 'None'; BackColor = $CARD; ForeColor = $FG
        TextAlign = $(if ($center) { 'Center' } else { 'Left' }) }
    $t.SetBounds(10, [int](($H - $t.Height) / 2), $w - 20, $t.Height)
    $p.Controls.Add($t)
    if ($isPath) { $tip.SetToolTip($t, $t.Text); $t.Add_TextChanged({ param($s, $e) $tip.SetToolTip($s, $s.Text) }) }
    $t
}
$flatSrc = @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
public class FlatCheck : CheckBox {
    public Color BackFill { get; set; }
    public Color BoxColor { get; set; }
    public Color BorderColor { get; set; }
    public Color AccentColor { get; set; }
    public Color HoverColor { get; set; }
    bool hover;
    public FlatCheck() {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        Cursor = Cursors.Hand;
    }
    protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
    protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }
    protected override void OnPaint(PaintEventArgs e) {
        var g = e.Graphics; g.Clear(BackFill);
        int s = 18; int y = (Height - s) / 2;
        bool key = Focused && ShowFocusCues;
        Color edge = Checked ? (hover ? HoverColor : AccentColor) : ((hover || key) ? AccentColor : BorderColor);
        using (var b = new SolidBrush(edge)) g.FillRectangle(b, 0, y, s, s);
        if (!Checked) using (var b = new SolidBrush(BoxColor)) g.FillRectangle(b, 2, y + 2, s - 4, s - 4);
        if (Checked) {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (var pen = new Pen(Color.White, 2.2f)) {
                pen.StartCap = LineCap.Flat; pen.EndCap = LineCap.Flat; pen.LineJoin = LineJoin.Miter;
                g.DrawLines(pen, new PointF[] { new PointF(4.2f, y + 9.2f), new PointF(7.6f, y + 12.6f), new PointF(13.8f, y + 5.4f) });
            }
        }
        TextRenderer.DrawText(g, Text, Font, new Rectangle(s + 7, 0, Width - s - 7, Height), ForeColor,
            TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.NoPrefix | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis);
    }
}
'@
# compiled once and cached in data\ (the name carries a hash of the source), so later starts skip the compiler
$flatDll = Join-Path $dataDir ('FlatCheck.{0}.dll' -f [BitConverter]::ToString([Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($flatSrc))).Replace('-', '').Substring(0, 8))
$refs = 'System.Windows.Forms', 'System.Drawing'
try {
    if (-not [IO.File]::Exists($flatDll)) { [void][IO.Directory]::CreateDirectory($dataDir); Add-Type -TypeDefinition $flatSrc -ReferencedAssemblies $refs -OutputAssembly $flatDll }
    if (-not ('FlatCheck' -as [type])) { Add-Type -Path $flatDll }
} catch { if (-not ('FlatCheck' -as [type])) { Add-Type -TypeDefinition $flatSrc -ReferencedAssemblies $refs } }
function Check($text, $x, $y, $w, $h, $on) {
    Add ([FlatCheck]@{ Text = $text; Checked = [bool]$on; BackFill = $BG; BoxColor = $CARD; BorderColor = $BORDER; AccentColor = $ACC; HoverColor = $ACCH }) $x $y $w $h
}
# Lists are drawn by hand so the selection is Minecraft green and spans the full row
$selBrush = New-Object Drawing.SolidBrush $ACC
$rowBrush = New-Object Drawing.SolidBrush $CARD
$markBrush = New-Object Drawing.SolidBrush $GTXT
$markSelBrush = New-Object Drawing.SolidBrush ([Drawing.Color]::White)
$delBrush = New-Object Drawing.SolidBrush (C '#e5453d')
$delHotBrush = New-Object Drawing.SolidBrush (C '#ff6b64')
$script:delHover = -1
$rowFlags = [Windows.Forms.TextFormatFlags]'VerticalCenter, Left, EndEllipsis, NoPrefix, SingleLine'
$rowImg = New-Object Windows.Forms.ImageList; $rowImg.ImageSize = New-Object Drawing.Size(1, 26)   # sets row height
$drawRow = { param($sender, $e)   # paints the whole row every time, so partial repaints (hover) never erase text
    $e.Graphics.FillRectangle($(if ($e.Item.Selected) { $selBrush } else { $rowBrush }), 0, $e.Bounds.Y, $sender.ClientSize.Width, $e.Bounds.Height)
    $textColor = if ($e.Item.Selected) { [Drawing.Color]::White } else { $FG }
    $cx = 0; $ind = 0
    if ($sender.Tag -eq 'marks') {   # backups list: newest backup of each world gets a small square at the start of its row
        $ind = 18
        if ($e.Item.Name -eq 'latest') { $e.Graphics.FillRectangle($(if ($e.Item.Selected) { $markSelBrush } else { $markBrush }), 9, $e.Bounds.Y + [int](($e.Bounds.Height - 10) / 2), 10, 10) }
    }
    if ($sender.Tag -eq 'delete') {   # worlds list: small red square at the end of each row = delete this world
        $e.Graphics.FillRectangle($(if ($e.Item.Index -eq $script:delHover) { $delHotBrush } else { $delBrush }), $sender.ClientSize.Width - 24, $e.Bounds.Y + [int](($e.Bounds.Height - 10) / 2), 10, 10)
    }
    for ($k = 0; $k -lt $e.Item.SubItems.Count; $k++) {
        $cw = $sender.Columns[$k].Width
        $pad = if ($k -eq 0) { $ind } else { 0 }
        $cellRect = [Drawing.Rectangle]::new($cx + 8 + $pad, $e.Bounds.Y, $cw - 10 - $pad, $e.Bounds.Height)
        [Windows.Forms.TextRenderer]::DrawText($e.Graphics, $e.Item.SubItems[$k].Text, $sender.Font, $cellRect, $textColor, $rowFlags)
        $cx += $cw
    }
}
function Lst($x, $cols) {
    $l = [Windows.Forms.ListView]@{ View = 'Details'; FullRowSelect = $true; HideSelection = $false; MultiSelect = $false
        HeaderStyle = 'None'; BorderStyle = 'None'; BackColor = $CARD; ForeColor = $FG; OwnerDraw = $true; SmallImageList = $rowImg }
    $l.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'Instance,NonPublic').SetValue($l, $true)
    $l.Add_DrawItem($drawRow)
    [void](Add $l $x 102 $COL 240)
    foreach ($c in $cols) { [void]$l.Columns.Add('', $c) }
    $l
}

# ---------------- controls ----------------
Label 'SAVES FOLDER' $M 12 $COL 20 $GTXT
$tSaves = Field $cfg.saves $M 34 ($COL - $BW - $GAP) $false $true
$bSaves = Button 'Browse' ($M + $COL - $BW) 34 $BW
Label 'BACKUP FOLDER' $X2 12 $COL 20 $GTXT
$tBack = Field $cfg.backups $X2 34 ($COL - $BW - $GAP) $false $true
$bBack = Button 'Browse' ($X2 + $COL - $BW) 34 $BW

Label 'WORLDS' $M 80 90 20 $GTXT
Label 'name  /  last played' ($M + 90) 80 ($COL - 90) 20 $MUTED 'MiddleRight'
Label 'BACKUPS' $X2 80 90 20 $GTXT
Label 'world  /  created  /  size' ($X2 + 90) 80 ($COL - 90) 20 $MUTED 'MiddleRight'
$lvW = Lst $M @(240, 170)
$lvB = Lst $X2 @(150, 150, 110)
$lvW.Tag = 'delete'
$lvB.Tag = 'marks'; $lvB.ShowItemToolTips = $true

# two option columns, aligned with the two lists; every row is the same height
$R1 = 350; $R2 = 384; $R3 = 418   # number boxes below use the same x / width as the buttons ($AB wide, 142 apart)
$chkRep    = Check 'Replace world on restore' $M $R1 $COL $H $cfg.replace
$chkSafe   = Check 'Safety backup before restore' $M $R2 $COL $H $cfg.safety
$NB = 44   # small number boxes
$chkKeep   = Check 'Keep last' $M $R3 84 $H $cfg.keepOn
$tKeep     = Field $cfg.keep ($M + $AB - $NB) $R3 $NB $true   # right edge = end of first button
Label 'backups' ($M + $AB + $GAP) $R3 $AB $H $FG
$tip.SetToolTip($chkRep, 'On: replaces the world folder. Off: restores as a new copy, e.g. HardCore(1) (never merges into the old one)')
$tip.SetToolTip($chkKeep, 'On: older backups are deleted automatically. Off: all backups are kept')
$tip.SetToolTip($tKeep, 'How many backups to keep per world')

$chkOnly   = Check 'Only selected world' $X2 $R1 $COL $H $cfg.only
$chkAuto   = Check 'Auto-select latest backup' $X2 $R2 $COL $H $cfg.auto
$chkAutoBk = Check 'Auto-backup every' $X2 $R3 138 $H $false
$tAuto     = Field $cfg.autoMin ($M + 568) $R3 $NB $true   # left edge = start of fifth button
Label 'minutes' ($M + 568 + $NB + $GAP) $R3 $AB $H $FG

$syncDim = { $tKeep.ForeColor = $(if ($chkKeep.Checked) { $GTXT } else { $MUTED }); $tAuto.ForeColor = $(if ($chkAutoBk.Checked) { $GTXT } else { $MUTED }) }
$chkKeep.Add_CheckedChanged($syncDim); $chkAutoBk.Add_CheckedChanged($syncDim); & $syncDim

$BY = 464
$bBackup  = Button 'Backup Now' $M $BY $AB $ACC (C '#ffffff') $ACCH
$bRestore = Button 'Restore Selected' ($M + 142) $BY $AB $ACC (C '#ffffff') $ACCH
$bQuick   = Button 'Quick Restore' ($M + 284) $BY $AB $ACC (C '#ffffff') $ACCH
$bDelete  = Button 'Delete Backup' ($M + 426) $BY $AB $CARD $RED
$bOpenS   = Button 'Open Saves' ($M + 568) $BY $AB
$bOpenB   = Button 'Open Backups' ($M + 710) $BY $AB
$actions  = @($bBackup, $bRestore, $bQuick, $bDelete)

# slim dark progress bar (track + fill)
$pbTrack = Add ([Windows.Forms.Panel]@{ BackColor = $CARD }) $M 524 $W 12
$pbTrack.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'Instance,NonPublic').SetValue($pbTrack, $true)
$status = Add ([Windows.Forms.Label]@{ TextAlign = 'MiddleCenter'; UseCompatibleTextRendering = $false }) $M 546 $W 24

# ---------------- helpers ----------------
$script:pbMax = 1; $script:busy = $false; $script:loading = $false; $script:skipped = 0; $script:restored = $null
$timer = [Windows.Forms.Timer]@{ Interval = 5000 }
$timer.Add_Tick({ $timer.Stop(); $status.Text = '' })
$autoTimer = New-Object Windows.Forms.Timer

# Smooth progress: the work code sets a target; a timer (running only during work) eases the bar toward it,
# the bar edge is blended per pixel, and the bar fades out when finished
$script:pbCur = 0.0; $script:pbTarget = 0.0; $script:pbDone = $false; $script:pbDoneAt = 0.0; $script:pbFade = 1.0; $script:pbLast = 0.0
$sw = [Diagnostics.Stopwatch]::StartNew()      # paces DoEvents while work runs
$clock = [Diagnostics.Stopwatch]::StartNew()   # animation clock
$pbBrush = New-Object Drawing.SolidBrush $ACC
$pbTimer = [Windows.Forms.Timer]@{ Interval = 10 }
function Reset-Pb { $script:pbCur = 0.0; $script:pbTarget = 0.0; $script:pbDone = $false; $script:pbFade = 1.0; $pbTimer.Stop(); $pbTrack.Invalidate() }
function Start-Pb($n) { Reset-Pb; $script:pbMax = [Math]::Max($n, 1); $script:pbLast = $clock.Elapsed.TotalMilliseconds; $pbTimer.Start() }
function Done-Pb { $script:pbTarget = 1.0; $script:pbDone = $true; $script:pbDoneAt = 0.0 }   # glide to 100%, hold, fade out
function Pump($done) {   # called after every data chunk: update the target and let the UI + animation run about every 10 ms
    if ($sw.ElapsedMilliseconds -ge 10) { $script:pbTarget = [Math]::Min($done / $script:pbMax, 1.0); $sw.Restart(); [Windows.Forms.Application]::DoEvents() }
}
$pbTrack.Add_Paint({ param($s, $e)
    $w = $s.ClientSize.Width * $script:pbCur; $a = [int](255 * $script:pbFade)
    if ($w -le 0 -or $a -le 0) { return }
    $full = [int][Math]::Floor($w); $h = $s.ClientSize.Height
    $pbBrush.Color = [Drawing.Color]::FromArgb($a, $ACC)
    if ($full -gt 0) { $e.Graphics.FillRectangle($pbBrush, 0, 0, $full, $h) }
    $frac = $w - $full
    if ($frac -gt 0.02 -and $full -lt $s.ClientSize.Width) {   # partial last pixel, so the edge moves smoothly
        $pbBrush.Color = [Drawing.Color]::FromArgb([int]($a * $frac), $ACC)
        $e.Graphics.FillRectangle($pbBrush, $full, 0, 1, $h)
    }
})
$pbTimer.Add_Tick({
    $now = $clock.Elapsed.TotalMilliseconds; $dt = [Math]::Min($now - $script:pbLast, 100); $script:pbLast = $now
    $changed = $false
    $diff = $script:pbTarget - $script:pbCur
    if ($diff -ne 0) {
        $script:pbCur = if ([Math]::Abs($diff) -lt 0.0004) { $script:pbTarget } else { $script:pbCur + $diff * (1 - [Math]::Exp(-$dt / 110)) }
        $changed = $true
    }
    if ($script:pbDone -and $script:pbCur -ge 0.9995) {
        $script:pbDoneAt += $dt
        if ($script:pbDoneAt -gt 450) {
            $script:pbFade = [Math]::Max(0.0, 1.0 - ($script:pbDoneAt - 450) / 300); $changed = $true
            if ($script:pbFade -le 0) { Reset-Pb; return }
        }
    }
    if ($changed) { $pbTrack.Invalidate(); $pbTrack.Update() }
})
function Say($text, $color, $hide = $false) {
    $timer.Stop(); $status.ForeColor = $color; $status.Text = $text; $status.Refresh()
    if ($hide) { $timer.Start() }
}
function Ask($msg) { [Windows.Forms.MessageBox]::Show($msg, 'MC Manager', 'YesNo', 'Warning', 'Button2') -eq 'Yes' }
function Err($msg) { [void][Windows.Forms.MessageBox]::Show($msg, 'MC Manager', 'OK', 'Error') }
function Busy($on) { $script:busy = $on; foreach ($b in $actions) { $b.Enabled = -not $on } }
function Parse-Int($s, $def) { $n = 0; if ([int]::TryParse($s, [ref]$n) -and $n -ge 0) { $n } else { $def } }
function Pick-Folder($cur) {
    # Explorer-style dialog: open the folder you want, then click Open
    $d = [Windows.Forms.OpenFileDialog]@{ Title = 'Open the folder, then click Open'; ValidateNames = $false
        CheckFileExists = $false; CheckPathExists = $true; FileName = 'Select this folder' }
    if ([IO.Directory]::Exists($cur)) { $d.InitialDirectory = $cur }
    if ($d.ShowDialog() -eq 'OK') { [IO.Path]::GetDirectoryName($d.FileName) }
}
function Open-Dir($p) { if ([string]::IsNullOrWhiteSpace($p)) { Say 'Pick the folder first (Browse)' $YEL $true; return }; [void][IO.Directory]::CreateDirectory($p); Start-Process explorer.exe "`"$p`"" }
function Selected-World { if ($lvW.SelectedItems.Count) { $lvW.SelectedItems[0].Text } }

# ---------------- data ----------------
function Get-Backups {
    if (-not [IO.Directory]::Exists($tBack.Text)) { return }
    $rxMc  = '^(\d{4}-\d\d-\d\d_\d\d-\d\d-\d\d)_(.+?)(?:\(\d+\))?$'   # Minecraft style: <time>_<World>[(n)]
    $rxOld = '^(.+)__\d{4}-\d\d-\d\d_\d\d-\d\d-\d\d$'                  # older versions of this tool
    ([IO.DirectoryInfo]$tBack.Text).EnumerateFiles('*.zip') | ForEach-Object {
        $b = [IO.Path]::GetFileNameWithoutExtension($_.Name)
        $w = $b; $t = $_.LastWriteTime; $d = [datetime]::MinValue
        if ($b -match $rxMc) {
            $w = $matches[2]
            if ([datetime]::TryParseExact($matches[1], 'yyyy-MM-dd_HH-mm-ss', [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$d)) { $t = $d }
        } elseif ($b -match $rxOld) { $w = $matches[1] }
        [pscustomobject]@{ World = $w; Time = $t; File = $_ }
    } | Sort-Object Time, { $_.File.LastWriteTime } -Descending
}

function Load-Worlds {
    $script:loading = $true
    $sel = Selected-World
    $lvW.BeginUpdate(); $lvW.Items.Clear()
    if ([IO.Directory]::Exists($tSaves.Text)) {
        ([IO.DirectoryInfo]$tSaves.Text).EnumerateDirectories() | ForEach-Object {
            $dat = "$($_.FullName)\level.dat"
            if ([IO.File]::Exists($dat)) { [pscustomobject]@{ N = $_.Name; T = [IO.File]::GetLastWriteTime($dat) } }
        } | Sort-Object T -Descending | ForEach-Object {
            $it = $lvW.Items.Add($_.N); [void]$it.SubItems.Add($_.T.ToString('yyyy-MM-dd HH:mm'))
            if ($_.N -eq $sel) { $it.Selected = $true }
        }
        if (-not $lvW.SelectedItems.Count -and $lvW.Items.Count) { $lvW.Items[0].Selected = $true }
    }
    $lvW.EndUpdate(); $script:loading = $false
}

function Load-Backups($pick = $false) {   # $pick: re-select the newest backup (used when the world changes)
    $script:loading = $true
    $selPath = if ($lvB.SelectedItems.Count) { $lvB.SelectedItems[0].Tag }
    $world = Selected-World
    $lvB.BeginUpdate(); $lvB.Items.Clear()
    $seen = @{}; $first = $null   # backups come newest first, so the first one seen for each world is its latest
    foreach ($b in @(Get-Backups)) {
        $isLatest = -not $seen.ContainsKey($b.World); $seen[$b.World] = $true
        if ($chkOnly.Checked -and $world -and $b.World -ne $world) { continue }
        $it = $lvB.Items.Add($b.World); $it.Tag = $b.File.FullName; $it.ToolTipText = $b.File.Name
        if ($isLatest) { $it.Name = 'latest' }
        [void]$it.SubItems.Add($b.Time.ToString('yyyy-MM-dd HH:mm:ss'))
        [void]$it.SubItems.Add(('{0:N1} MB' -f ($b.File.Length / 1MB)))
        if ($it.Tag -eq $selPath) { $it.Selected = $true }
        if (-not $first -and (-not $world -or $b.World -eq $world)) { $first = $it }
    }
    if ($chkAuto.Checked -and $lvB.Items.Count -and ($pick -or -not $lvB.SelectedItems.Count)) {
        $t = if ($first) { $first } else { $lvB.Items[0] }
        $t.Selected = $true; $t.EnsureVisible()
    }
    $lvB.EndUpdate(); $script:loading = $false
}
function Refresh-All { Load-Worlds; Load-Backups }

# ---------------- backup ----------------
function New-Backup($world, $outDir) {
    $src = "$($tSaves.Text.TrimEnd('\'))\$world"
    [void][IO.Directory]::CreateDirectory($outDir)
    # Same scheme as Minecraft's own 'Back Up World': <yyyy-MM-dd_HH-mm-ss>_<World>.zip, entries under '<World>/'
    $stamp = '{0:yyyy-MM-dd_HH-mm-ss}' -f (Get-Date)
    $dst = "$outDir\${stamp}_$world.zip"; $n = 1
    while ([IO.File]::Exists($dst)) { $dst = "$outDir\${stamp}_$world($n).zip"; $n++ }   # Minecraft adds (1), (2)... on a clash
    $root = [IO.DirectoryInfo]$src
    $files = @($root.GetFiles('*', 'AllDirectories') | Where-Object { $_.Name -ne 'session.lock' })
    $total = 0L; foreach ($f in $files) { $total += $f.Length }
    Start-Pb $total
    $script:skipped = 0; $done = 0L; $cut = $root.FullName.TrimEnd('\').Length + 1
    $buf = New-Object byte[] 131072
    try {
        $zip = [IO.Compression.ZipFile]::Open("$dst.tmp", 'Create')
        try {
            foreach ($f in $files) {
                $in = $null
                try { $in = [IO.File]::Open($f.FullName, 'Open', 'Read', 'ReadWrite') } catch { $script:skipped++ }
                if ($in) {
                    try {
                        $e = $zip.CreateEntry("$world/" + $f.FullName.Substring($cut).Replace('\', '/'), 'Fastest')
                        $o = $e.Open()
                        try { while (($rd = $in.Read($buf, 0, $buf.Length)) -gt 0) { $o.Write($buf, 0, $rd); $done += $rd; Pump $done } } finally { $o.Dispose() }
                    } finally { $in.Dispose() }
                }
                Pump $done
            }
        } finally { $zip.Dispose() }
        Move-Item -LiteralPath "$dst.tmp" -Destination $dst -Force
    } catch { Remove-Item -LiteralPath "$dst.tmp" -Force -ErrorAction SilentlyContinue; throw }
    Done-Pb
    $dst
}

function Prune($world) {
    if (-not $chkKeep.Checked) { return }
    $keep = Parse-Int $tKeep.Text 0
    if ($keep -lt 1) { return }
    @(Get-Backups) | Where-Object { $_.World -eq $world } | Select-Object -Skip $keep | ForEach-Object { try { $_.File.Delete() } catch {} }
}

function Do-Backup($world, $quiet = $false) {
    if ($script:busy) { return }
    if (-not [IO.Directory]::Exists($tSaves.Text)) { Say 'Pick the saves folder first (Browse)' $YEL $true; return }
    if ([string]::IsNullOrWhiteSpace($tBack.Text)) { Say 'Pick the backup folder first (Browse)' $YEL $true; return }
    if (-not $world) { Say 'Select a world first' $YEL $true; return }
    Busy $true; Say "Backing up $world..." $YEL
    try {
        $dst = New-Backup $world $tBack.Text
        Prune $world
        $msg = "Backup saved: $([IO.Path]::GetFileName($dst))"
        if ($script:skipped) { $msg += "  ($($script:skipped) locked files skipped)" }
        Say $msg $GTXT $true
    } catch { Reset-Pb; Say 'Backup failed' $RED $true; if (-not $quiet) { Err $_.Exception.Message } }
    Busy $false; Load-Backups
}

# ---------------- restore ----------------
function Restore-Zip($path) {
    $script:restored = $null
    if (@(Get-Process javaw, java -ErrorAction SilentlyContinue).Count -and
        -not (Ask "Minecraft seems to be running.`nRestoring while a world is open can corrupt it.`n`nContinue anyway?")) { return }
    $out = [IO.Path]::GetFullPath($tSaves.Text).TrimEnd('\')
    $zip = [IO.Compression.ZipFile]::OpenRead($path)
    try {
        # only the world folder(s) inside the backup are touched - never anything else in the saves folder
        $tops = New-Object 'System.Collections.Generic.HashSet[string]'
        $bad = [IO.Path]::GetInvalidFileNameChars()
        foreach ($e in $zip.Entries) {
            $p = $e.FullName.Split([char[]]'/\')
            if ($p.Length -gt 1 -and $p[0] -and $p[0] -ne '.' -and $p[0] -ne '..' -and $p[0].IndexOfAny($bad) -lt 0) { [void]$tops.Add($p[0]) }
        }
        # only warn when a world with the same name really exists and is about to be replaced
        $existing = @($tops | Where-Object { [IO.Directory]::Exists("$out\$_") })
        if ($chkRep.Checked -and -not $chkSafe.Checked -and $existing.Count -and
            -not (Ask "The current world '$($existing -join ', ')' will be deleted before restoring (safety backup is off).`n`nContinue?")) { return }
        # Minecraft never merges into an existing world: it either replaces the folder or makes a fresh 'Name(1)' copy
        $map = @{}
        foreach ($n in $tops) {
            $map[$n] = $n
            $dir = "$out\$n"
            if (-not [IO.Directory]::Exists($dir)) { continue }
            if ($chkRep.Checked) {
                if ($chkSafe.Checked) { [void](New-Backup $n "$($tBack.Text.TrimEnd('\'))\_pre-restore") }
                [IO.Directory]::Delete($dir, $true)
            } else {
                $c = $n; $k = 1
                while ([IO.Directory]::Exists("$out\$c")) { $c = "$n($k)"; $k++ }
                $map[$n] = $c
            }
        }
        $total = 0L; foreach ($e in $zip.Entries) { $total += $e.Length }
        Start-Pb $total
        $made = New-Object 'System.Collections.Generic.HashSet[string]'; $done = 0L
        $buf = New-Object byte[] 131072
        foreach ($e in $zip.Entries) {
            $p = $e.FullName.Split([char[]]'/\')
            if ($p.Length -lt 2 -or -not $map.ContainsKey($p[0])) { continue }   # only '<World>/...' entries, like Minecraft's own zips
            $base = "$out\$($map[$p[0]])\"
            $target = [IO.Path]::GetFullPath($base + ($p[1..($p.Length - 1)] -join '\'))
            if (-not $target.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { continue }
            $dir = if ($e.Name) { [IO.Path]::GetDirectoryName($target) } else { $target }
            if ($made.Add($dir)) { [void][IO.Directory]::CreateDirectory($dir) }
            if ($e.Name) {
                $ins = $e.Open()
                try {
                    $fs = [IO.File]::Create($target)
                    try { while (($rd = $ins.Read($buf, 0, $buf.Length)) -gt 0) { $fs.Write($buf, 0, $rd); $done += $rd; Pump $done } } finally { $fs.Dispose() }
                } finally { $ins.Dispose() }
                try { [IO.File]::SetLastWriteTime($target, $e.LastWriteTime.DateTime) } catch {}
            }
            Pump $done
        }
        $script:restored = "$(($tops | ForEach-Object { $map[$_] }) -join ', ')"; Done-Pb
    } finally { $zip.Dispose() }
}

function Do-Restore($path) {
    if ($script:busy) { return }
    if (-not [IO.Directory]::Exists($tSaves.Text)) { Say 'Pick the saves folder first (Browse)' $YEL $true; return }
    if (-not $path) { Say 'Select a backup first' $YEL $true; return }
    Busy $true; Say 'Restoring...' $YEL
    try {
        Restore-Zip $path
        if ($null -ne $script:restored) { Say "Restored $($script:restored)" $GTXT $true } else { Say 'Cancelled' $MUTED $true }
    } catch { Reset-Pb; Say 'Restore failed' $RED $true; Err $_.Exception.Message }
    Busy $false; Refresh-All
}

function Set-Auto {
    $autoTimer.Stop()
    if ($chkAutoBk.Checked) {
        $mins = [Math]::Max((Parse-Int $tAuto.Text 15), 1)
        $autoTimer.Interval = $mins * 60000; $autoTimer.Start()
        Say "Auto-backup on: every $mins min" $GTXT $true
    }
}

# ---------------- events ----------------
$bSaves.Add_Click({ $p = Pick-Folder $tSaves.Text; if ($p) { $tSaves.Text = $p; Refresh-All } })
$bBack.Add_Click({ $p = Pick-Folder $tBack.Text; if ($p) { $tBack.Text = $p; Load-Backups } })
$tSaves.Add_Leave({ Refresh-All })
$tBack.Add_Leave({ Load-Backups })
$lvW.Add_ItemSelectionChanged({ param($s, $e) if ($e.IsSelected -and -not $script:loading) { Load-Backups $true } })
$chkOnly.Add_CheckedChanged({ Load-Backups })
$chkAuto.Add_CheckedChanged({ Load-Backups $true })
$chkAutoBk.Add_CheckedChanged({ Set-Auto })
$tAuto.Add_Leave({ if ($chkAutoBk.Checked) { Set-Auto } })
$autoTimer.Add_Tick({ Do-Backup (Selected-World) $true })

$bBackup.Add_Click({ Do-Backup (Selected-World) })
$bRestore.Add_Click({ if ($lvB.SelectedItems.Count) { Do-Restore $lvB.SelectedItems[0].Tag } else { Do-Restore $null } })
$bQuick.Add_Click({
    $sel = Selected-World
    $latest = @(Get-Backups) | Where-Object { -not $sel -or $_.World -eq $sel } | Select-Object -First 1
    if ($latest) { Do-Restore $latest.File.FullName } else { Say 'No backups found' $YEL $true }
})
$bDelete.Add_Click({
    if (-not $lvB.SelectedItems.Count) { Say 'Select a backup first' $YEL $true; return }
    $f = $lvB.SelectedItems[0].Tag
    if (Ask "Delete this backup?`n`n$([IO.Path]::GetFileName($f))") {
        try { [IO.File]::Delete($f); Say 'Backup deleted' $GTXT $true } catch { Err $_.Exception.Message }
        Load-Backups
    }
})
function Delete-World($name) {
    if ($script:busy -or -not $name -or -not [IO.Directory]::Exists($tSaves.Text)) { return }
    $root = [IO.Path]::GetFullPath($tSaves.Text).TrimEnd('\')
    $dir = [IO.Path]::GetFullPath("$root\$name")
    if ([IO.Path]::GetDirectoryName($dir) -ne $root -or -not [IO.Directory]::Exists($dir)) { return }
    $cnt = @(Get-Backups | Where-Object { $_.World -eq $name }).Count
    $info = if ($cnt) { "$cnt backup(s) of this world exist." } else { 'This world has NO backups!' }
    $run = if (@(Get-Process javaw, java -ErrorAction SilentlyContinue).Count) { "Minecraft seems to be running.`n`n" } else { '' }
    if (Ask "${run}Delete the world '$name'?`n`nThe whole world folder is deleted permanently (not sent to the Recycle Bin).`n$info`n`nDelete it?") {
        try { [IO.Directory]::Delete($dir, $true); Say "Deleted world $name" $GTXT $true } catch { Err $_.Exception.Message }
    }
    $script:delHover = -1; Refresh-All
}
$lvW.Add_MouseMove({ param($s, $e)
    $it = $s.GetItemAt(5, $e.Y)
    $idx = if ($it -and $e.X -ge ($s.ClientSize.Width - 36)) { $it.Index } else { -1 }
    $s.Cursor = if ($idx -ge 0) { [Windows.Forms.Cursors]::Hand } else { [Windows.Forms.Cursors]::Default }
    if ($idx -ne $script:delHover) { $script:delHover = $idx; $s.Invalidate() }
})
$lvW.Add_MouseLeave({ if ($script:delHover -ne -1) { $script:delHover = -1; $lvW.Invalidate() }; $lvW.Cursor = [Windows.Forms.Cursors]::Default })
$lvW.Add_MouseDown({ param($s, $e)
    if ($e.Button -ne 'Left') { return }
    $it = $s.GetItemAt(5, $e.Y)
    if ($it -and $e.X -ge ($s.ClientSize.Width - 36)) { Delete-World $it.Text }
})
$bOpenS.Add_Click({ Open-Dir $tSaves.Text })
$bOpenB.Add_Click({ Open-Dir $tBack.Text })
$form.Add_KeyDown({ if ($_.KeyCode -eq 'F5') { Refresh-All } })
$form.Add_Activated({ if (-not $script:busy) { Refresh-All } })
$form.Add_FormClosing({ param($s, $e)
    if ($script:busy) { $e.Cancel = $true; return }   # never close in the middle of a backup / restore
    $cfg.saves = $tSaves.Text; $cfg.backups = $tBack.Text; $cfg.replace = $chkRep.Checked; $cfg.safety = $chkSafe.Checked
    $cfg.auto = $chkAuto.Checked; $cfg.only = $chkOnly.Checked; $cfg.keepOn = $chkKeep.Checked; $cfg.keep = $tKeep.Text; $cfg.autoMin = $tAuto.Text
    try {
        [void][IO.Directory]::CreateDirectory($dataDir)
        $cfg | ConvertTo-Json | Set-Content $cfgPath -Encoding UTF8
    } catch {}
})

Refresh-All
$form.Add_Shown({ $lvW.Focus() })
[void]$form.ShowDialog()
