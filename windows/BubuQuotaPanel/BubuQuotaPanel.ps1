param(
    [switch]$PrintConfiguration,
    [switch]$ValidateXaml,
    [switch]$ValidateTrackingFilters,
    [switch]$ValidateTaskProgress,
    [switch]$ValidateSkinSelection,
    [switch]$PrintTaskProgress
)

$ErrorActionPreference = "Stop"

$script:PanelVersion = "17"
$script:PanelLogPath = Join-Path $PSScriptRoot "panel.log"
$script:CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }
$script:MarketPricesEnabled = $true
$marketSetting = [string]$env:BUBU_SHOW_MARKET_PRICES
if (-not [string]::IsNullOrWhiteSpace($marketSetting)) {
    $script:MarketPricesEnabled = $marketSetting.Trim().ToLowerInvariant() -notmatch '^(0|false|no|off)$'
} elseif (Test-Path -LiteralPath (Join-Path $PSScriptRoot "CODEX-ONLY.txt")) {
    $script:MarketPricesEnabled = $false
}
$script:TaskProgressRowHeight = 23
$script:MaximumVisibleTaskRows = 5
$script:CompletedTaskFallbackMinutes = 2
# Blue Bubu keeps the 93 px quota header, followed by task rows and one BTC row.
$script:BaseExpandedHeight = if ($script:MarketPricesEnabled) { 137 } else { 116 }
$script:TaskProgressRowCount = 1
$script:ExpandedHeight = $script:BaseExpandedHeight + $script:TaskProgressRowHeight
$script:ExpandedBodyHeight = $script:ExpandedHeight - 13
$script:ExpandedPointerTipY = $script:ExpandedHeight - 1
$script:ExpandedWidth = 224.0
$script:CollapsedWidth = 64.0
$script:CollapsedHeight = 44.0
$script:CanonicalPetWidth = 163.0
$script:CanonicalPetHeight = 177.0
$script:PetAtlasFrameWidth = 192.0
$script:PetAtlasFrameHeight = 208.0
$script:PetFrameVisiblePixelSizes = @(
    '109x166', '109x186', '110x172', '110x185', '110x186', '110x187',
    '111x186', '113x153', '113x181', '114x181', '116x182', '116x185',
    '118x187', '118x189', '118x192', '118x193', '118x194', '119x152',
    '119x155', '119x167', '119x194', '120x185', '120x189', '120x192',
    '120x194', '121x190', '121x192', '121x196', '121x198', '122x190',
    '122x191', '122x192', '122x194', '123x185', '123x196', '123x198',
    '124x191', '124x194', '124x198', '125x198', '132x198', '133x198',
    '136x198', '138x196', '141x196', '144x198', '153x198', '154x198',
    '155x198', '157x198', '161x198',
    # Orange Bubu uses the same 192x208 cells. Its beach chair and limbless
    # singing pose create a second set of visible alpha bounds.
    '127x198', '128x198', '129x198', '130x198', '132x182', '132x189',
    '133x185', '133x186', '133x191', '133x192', '133x195', '133x196',
    '133x197', '134x193', '134x194', '134x195', '134x196', '134x197',
    '134x198', '137x198', '138x198', '139x198', '140x198', '141x198',
    '142x198', '146x198', '151x198', '152x198', '156x198', '158x198',
    '163x198', '170x198', '182x165', '182x171', '182x173', '182x174',
    '182x177'
)
$script:PanelScale = 1.0
$script:MinimumPanelScale = 0.20
$script:MaximumPanelScale = 8.0
$script:VisualScaleTolerance = 0.12
$script:VisualProbeIntervalMilliseconds = 120
$script:VisualScaleConfirmationSamples = 3
$script:VisualScalePendingTolerance = 0.045
$script:CachedVisualMetrics = $null
$script:CachedVisualWindowHandle = [IntPtr]::Zero
$script:LastVisualProbeAt = [DateTime]::MinValue
$script:CachedVisualAt = [DateTime]::MinValue
$script:PendingPanelScale = [double]::NaN
$script:PendingPanelScaleSamples = 0
$script:PendingPanelScaleWindowHandle = [IntPtr]::Zero

if ($PrintConfiguration) {
    Write-Output (
        "panel-config: version=" + $script:PanelVersion +
        " marketPricesEnabled=" + $script:MarketPricesEnabled.ToString().ToLowerInvariant() +
        " width=" + [int]$script:ExpandedWidth + " height=" + $script:ExpandedHeight
    )
    exit 0
}

function Write-PanelLog([string]$message) {
    try {
        $safeMessage = [string]$message
        foreach ($privatePath in @($env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA, $env:CODEX_HOME, $PSScriptRoot)) {
            if (-not [string]::IsNullOrWhiteSpace($privatePath)) {
                $safeMessage = $safeMessage.Replace($privatePath, "<redacted-path>")
            }
        }
        $safeMessage = [Text.RegularExpressions.Regex]::Replace(
            $safeMessage,
            '(?i)[A-Z]:\\Users\\[^\\\s"'']+',
            '<redacted-user-path>'
        )
        $safeMessage = [Text.RegularExpressions.Regex]::Replace(
            $safeMessage,
            '(?i)[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}',
            '<redacted-email>'
        )
        $safeMessage = [Text.RegularExpressions.Regex]::Replace(
            $safeMessage,
            '(?i)(?:ghp_|github_pat_|sk-)[A-Z0-9_-]+',
            '<redacted-token>'
        )
        $line = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff") + " " + $safeMessage
        [IO.File]::AppendAllText($script:PanelLogPath, $line + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    } catch {
    }
}

trap {
    Write-PanelLog ("FATAL " + $_.Exception.ToString())
    $isValidationRun = $ValidateXaml -or $ValidateTrackingFilters -or
        $ValidateTaskProgress -or $ValidateSkinSelection -or $PrintTaskProgress
    if ($isValidationRun) {
        [Console]::Error.WriteLine($_.Exception.ToString())
    } else {
        try {
            [Windows.MessageBox]::Show(
                "卜卜看板启动失败。请运行分享包里的【检查安装环境.cmd】，并发送生成的报告。",
                "卜卜看板",
                [Windows.MessageBoxButton]::OK,
                [Windows.MessageBoxImage]::Warning
            ) | Out-Null
        } catch {
        }
    }
    exit 1
}

Write-PanelLog ("START version=" + $script:PanelVersion + " powershell=" + $PSVersionTable.PSVersion)

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Net.Http
Add-Type -AssemblyName System.Drawing

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$createdNew = $false
$script:instanceMutex = [Threading.Mutex]::new($true, "Local\BubuQuotaPanel", [ref]$createdNew)
if (-not $createdNew) {
    exit 0
}

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace BubuPanel {
    public sealed class NativeWindowInfo {
        public IntPtr Handle { get; set; }
        public uint ProcessId { get; set; }
        public string Title { get; set; }
        public string ClassName { get; set; }
        public int Left { get; set; }
        public int Top { get; set; }
        public int Right { get; set; }
        public int Bottom { get; set; }
        public int Width { get { return Right - Left; } }
        public int Height { get { return Bottom - Top; } }
    }

    public sealed class NativeVisualInfo {
        public int Left { get; set; }
        public int Top { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
        public double VisibleFraction { get; set; }
    }

    public static class NativeWindows {
        private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [StructLayout(LayoutKind.Sequential)]
        private struct RECT {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct POINT {
            public int X;
            public int Y;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MONITORINFO {
            public int cbSize;
            public RECT rcMonitor;
            public RECT rcWork;
            public uint dwFlags;
        }

        [DllImport("user32.dll")]
        private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

        [DllImport("dwmapi.dll")]
        private static extern int DwmGetWindowAttribute(
            IntPtr hWnd, int dwAttribute, out RECT attribute, int cbAttribute);

        [DllImport("user32.dll")]
        private static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint flags);

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

        [DllImport("user32.dll")]
        private static extern bool IsWindow(IntPtr hWnd);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int count);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder text, int count);

        [DllImport("user32.dll")]
        private static extern uint GetDpiForWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr dpiContext);

        [DllImport("user32.dll")]
        private static extern bool SetWindowPos(
            IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int width, int height, uint flags);

        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", ExactSpelling = true)]
        private static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int index);

        [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", ExactSpelling = true)]
        private static extern IntPtr SetWindowLongPtr(IntPtr hWnd, int index, IntPtr newLong);

        [DllImport("user32.dll")]
        private static extern IntPtr MonitorFromWindow(IntPtr hWnd, uint flags);

        [DllImport("user32.dll")]
        private static extern IntPtr MonitorFromPoint(POINT point, uint flags);

        [DllImport("user32.dll")]
        private static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);

        [DllImport("user32.dll")]
        private static extern short GetAsyncKeyState(int virtualKey);

        [DllImport("user32.dll")]
        private static extern bool GetCursorPos(out POINT point);

        [DllImport("user32.dll")]
        private static extern uint GetDoubleClickTime();

        [DllImport("user32.dll")]
        private static extern int GetSystemMetrics(int index);

        private static bool TryGetPhysicalWindowRect(IntPtr hWnd, out RECT rect) {
            // GetWindowRect is DPI-virtualized when the hosting PowerShell/WPF
            // thread is not per-monitor aware. DWM always reports physical
            // screen pixels, so a 250% display cannot make the panel derive a
            // 0.4x/0.2x pet scale from an otherwise full-size overlay.
            const int DWMWA_EXTENDED_FRAME_BOUNDS = 9;
            try {
                int result = DwmGetWindowAttribute(hWnd,
                    DWMWA_EXTENDED_FRAME_BOUNDS, out rect, Marshal.SizeOf(typeof(RECT)));
                if (result == 0 && rect.Right > rect.Left && rect.Bottom > rect.Top) {
                    return true;
                }
            } catch (DllNotFoundException) {
            } catch (EntryPointNotFoundException) {
            }
            return GetWindowRect(hWnd, out rect);
        }

        private static NativeWindowInfo ReadWindow(IntPtr hWnd) {
            if (hWnd == IntPtr.Zero || !IsWindow(hWnd) || !IsWindowVisible(hWnd)) return null;
            RECT rect;
            if (!TryGetPhysicalWindowRect(hWnd, out rect)) return null;
            if (rect.Right <= rect.Left || rect.Bottom <= rect.Top) return null;
            uint processId;
            GetWindowThreadProcessId(hWnd, out processId);
            var title = new System.Text.StringBuilder(512);
            var className = new System.Text.StringBuilder(256);
            GetWindowText(hWnd, title, title.Capacity);
            GetClassName(hWnd, className, className.Capacity);
            return new NativeWindowInfo {
                Handle = hWnd,
                ProcessId = processId,
                Title = title.ToString(),
                ClassName = className.ToString(),
                Left = rect.Left,
                Top = rect.Top,
                Right = rect.Right,
                Bottom = rect.Bottom
            };
        }

        public static NativeWindowInfo GetWindow(IntPtr hWnd) {
            return ReadWindow(hWnd);
        }

        public static bool HasPhysicalWindowBounds(IntPtr hWnd) {
            RECT rect;
            if (hWnd == IntPtr.Zero || !IsWindow(hWnd)) return false;
            const int DWMWA_EXTENDED_FRAME_BOUNDS = 9;
            try {
                return DwmGetWindowAttribute(hWnd, DWMWA_EXTENDED_FRAME_BOUNDS,
                    out rect, Marshal.SizeOf(typeof(RECT))) == 0 &&
                    rect.Right > rect.Left && rect.Bottom > rect.Top;
            } catch (DllNotFoundException) {
                return false;
            } catch (EntryPointNotFoundException) {
                return false;
            }
        }

        public static bool IsLeftMouseButtonDown() {
            const int VK_LBUTTON = 0x01;
            return (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0;
        }

        public static Point GetCursorPosition() {
            POINT point;
            return GetCursorPos(out point) ? new Point(point.X, point.Y) : Point.Empty;
        }

        public static int GetDoubleClickTimeMilliseconds() {
            uint value = GetDoubleClickTime();
            return value > 0 && value <= Int32.MaxValue ? (int)value : 500;
        }

        public static Size GetDoubleClickSize() {
            const int SM_CXDOUBLECLK = 36;
            const int SM_CYDOUBLECLK = 37;
            return new Size(Math.Max(1, GetSystemMetrics(SM_CXDOUBLECLK)),
                Math.Max(1, GetSystemMetrics(SM_CYDOUBLECLK)));
        }

        public static NativeVisualInfo CaptureVisibleBounds(IntPtr hWnd) {
            RECT rect;
            if (hWnd == IntPtr.Zero || !IsWindow(hWnd) ||
                !TryGetPhysicalWindowRect(hWnd, out rect)) return null;
            int width = rect.Right - rect.Left;
            int height = rect.Bottom - rect.Top;
            if (width < 40 || height < 40 || width > 2000 || height > 2000) return null;

            using (var bitmap = new Bitmap(width, height, PixelFormat.Format32bppArgb)) {
                bool captured = false;
                using (Graphics graphics = Graphics.FromImage(bitmap)) {
                    IntPtr hdc = graphics.GetHdc();
                    try {
                        // PW_RENDERFULLCONTENT captures Chromium/Electron
                        // transparent windows even when another app overlaps.
                        captured = PrintWindow(hWnd, hdc, 2u);
                    } finally {
                        graphics.ReleaseHdc(hdc);
                    }
                }
                if (!captured) return null;

                var area = new Rectangle(0, 0, width, height);
                BitmapData data = bitmap.LockBits(area, ImageLockMode.ReadOnly,
                    PixelFormat.Format32bppArgb);
                try {
                    int rowBytes = Math.Abs(data.Stride);
                    byte[] pixels = new byte[rowBytes * height];
                    Marshal.Copy(data.Scan0, pixels, 0, pixels.Length);
                    int alphaPixels = 0;
                    int colorPixels = 0;
                    int totalPixels = width * height;

                    for (int y = 0; y < height; y++) {
                        int row = data.Stride >= 0 ? y * rowBytes : (height - 1 - y) * rowBytes;
                        for (int x = 0; x < width; x++) {
                            int offset = row + x * 4;
                            if (pixels[offset + 3] > 20) alphaPixels++;
                            if (pixels[offset] > 20 || pixels[offset + 1] > 20 ||
                                pixels[offset + 2] > 20) colorPixels++;
                        }
                    }

                    bool useAlpha = alphaPixels >= 64 && alphaPixels < totalPixels * 0.80;
                    bool useColor = !useAlpha && colorPixels >= 64 && colorPixels < totalPixels * 0.80;
                    if (!useAlpha && !useColor) return null;

                    int minX = width, minY = height, maxX = -1, maxY = -1, visible = 0;
                    for (int y = 0; y < height; y++) {
                        int row = data.Stride >= 0 ? y * rowBytes : (height - 1 - y) * rowBytes;
                        for (int x = 0; x < width; x++) {
                            int offset = row + x * 4;
                            bool isVisible = useAlpha
                                ? pixels[offset + 3] > 20
                                : pixels[offset] > 20 || pixels[offset + 1] > 20 ||
                                  pixels[offset + 2] > 20;
                            if (!isVisible) continue;
                            visible++;
                            if (x < minX) minX = x;
                            if (x > maxX) maxX = x;
                            if (y < minY) minY = y;
                            if (y > maxY) maxY = y;
                        }
                    }
                    if (visible < 64 || maxX < minX || maxY < minY) return null;
                    return new NativeVisualInfo {
                        Left = minX,
                        Top = minY,
                        Width = maxX - minX + 1,
                        Height = maxY - minY + 1,
                        VisibleFraction = visible / (double)totalPixels
                    };
                } finally {
                    bitmap.UnlockBits(data);
                }
            }
        }

        public static uint GetWindowDpi(IntPtr hWnd) {
            try {
                uint dpi = GetDpiForWindow(hWnd);
                return dpi == 0 ? 96u : dpi;
            } catch (EntryPointNotFoundException) {
                return 96u;
            }
        }

        public static bool EnablePerMonitorV2() {
            try {
                // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2. Keeping the UI
                // thread in this context makes GetWindowRect and SetWindowPos
                // use the same physical coordinate system on every monitor.
                return SetThreadDpiAwarenessContext(new IntPtr(-4)) != IntPtr.Zero;
            } catch (EntryPointNotFoundException) {
                return false;
            }
        }

        public static bool MoveWindowNoActivate(IntPtr hWnd, int x, int y) {
            const uint SWP_NOSIZE = 0x0001;
            const uint SWP_NOZORDER = 0x0004;
            const uint SWP_NOACTIVATE = 0x0010;
            const uint SWP_SHOWWINDOW = 0x0040;
            return SetWindowPos(hWnd, IntPtr.Zero, x, y, 0, 0,
                SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW);
        }

        public static void ApplyNoActivateStyle(IntPtr hWnd) {
            const int GWL_EXSTYLE = -20;
            const long WS_EX_TOOLWINDOW = 0x00000080L;
            const long WS_EX_NOACTIVATE = 0x08000000L;
            long style = GetWindowLongPtr(hWnd, GWL_EXSTYLE).ToInt64();
            SetWindowLongPtr(hWnd, GWL_EXSTYLE,
                new IntPtr(style | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE));
        }

        public static bool HasNoActivateStyle(IntPtr hWnd) {
            const int GWL_EXSTYLE = -20;
            const long WS_EX_NOACTIVATE = 0x08000000L;
            return (GetWindowLongPtr(hWnd, GWL_EXSTYLE).ToInt64() & WS_EX_NOACTIVATE) != 0;
        }

        public static NativeWindowInfo GetMonitorWorkArea(IntPtr hWnd) {
            const uint MONITOR_DEFAULTTONEAREST = 2;
            IntPtr monitor = MonitorFromWindow(hWnd, MONITOR_DEFAULTTONEAREST);
            if (monitor == IntPtr.Zero) return null;
            MONITORINFO info = new MONITORINFO();
            info.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
            if (!GetMonitorInfo(monitor, ref info)) return null;
            return new NativeWindowInfo {
                Handle = monitor,
                Left = info.rcWork.Left,
                Top = info.rcWork.Top,
                Right = info.rcWork.Right,
                Bottom = info.rcWork.Bottom
            };
        }

        public static NativeWindowInfo GetMonitorBounds(IntPtr hWnd) {
            const uint MONITOR_DEFAULTTONEAREST = 2;
            IntPtr monitor = MonitorFromWindow(hWnd, MONITOR_DEFAULTTONEAREST);
            if (monitor == IntPtr.Zero) return null;
            MONITORINFO info = new MONITORINFO();
            info.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
            if (!GetMonitorInfo(monitor, ref info)) return null;
            return new NativeWindowInfo {
                Handle = monitor,
                Left = info.rcMonitor.Left,
                Top = info.rcMonitor.Top,
                Right = info.rcMonitor.Right,
                Bottom = info.rcMonitor.Bottom
            };
        }

        public static NativeWindowInfo GetMonitorWorkAreaAtPoint(int x, int y) {
            const uint MONITOR_DEFAULTTONEAREST = 2;
            POINT point = new POINT { X = x, Y = y };
            IntPtr monitor = MonitorFromPoint(point, MONITOR_DEFAULTTONEAREST);
            if (monitor == IntPtr.Zero) return null;
            MONITORINFO info = new MONITORINFO();
            info.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
            if (!GetMonitorInfo(monitor, ref info)) return null;
            return new NativeWindowInfo {
                Handle = monitor,
                Left = info.rcWork.Left,
                Top = info.rcWork.Top,
                Right = info.rcWork.Right,
                Bottom = info.rcWork.Bottom
            };
        }

        public static NativeWindowInfo GetMonitorBoundsAtPoint(int x, int y) {
            const uint MONITOR_DEFAULTTONEAREST = 2;
            POINT point = new POINT { X = x, Y = y };
            IntPtr monitor = MonitorFromPoint(point, MONITOR_DEFAULTTONEAREST);
            if (monitor == IntPtr.Zero) return null;
            MONITORINFO info = new MONITORINFO();
            info.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
            if (!GetMonitorInfo(monitor, ref info)) return null;
            return new NativeWindowInfo {
                Handle = monitor,
                Left = info.rcMonitor.Left,
                Top = info.rcMonitor.Top,
                Right = info.rcMonitor.Right,
                Bottom = info.rcMonitor.Bottom
            };
        }

        public static NativeWindowInfo[] GetVisibleWindows() {
            var windows = new List<NativeWindowInfo>();
            EnumWindows(delegate (IntPtr hWnd, IntPtr lParam) {
                NativeWindowInfo info = ReadWindow(hWnd);
                if (info != null) windows.Add(info);
                return true;
            }, IntPtr.Zero);
            return windows.ToArray();
        }
    }
}
"@ -ReferencedAssemblies @([Drawing.Bitmap].Assembly.Location)

$script:PerMonitorDpiEnabled = [BubuPanel.NativeWindows]::EnablePerMonitorV2()
Write-PanelLog ("DPI per-monitor-v2=" + $script:PerMonitorDpiEnabled)

function Get-BubuSkinAvatarId([string]$skin) {
    switch ($skin) {
        "orange" { return "custom:bubu-orange" }
        default { return "custom:bubu-office" }
    }
}

function Update-CodexSkinSelectionText([string]$configText, [string]$avatarId) {
    $lines = [Text.RegularExpressions.Regex]::Split(
        ([string]$configText).Replace("`r`n", "`n"),
        "`n"
    )
    $output = New-Object Collections.Generic.List[string]
    $section = ""
    $desktopSeen = $false
    $desktopSelectionWritten = $false

    foreach ($line in $lines) {
        $trimmed = ([string]$line).Trim()
        if ($trimmed -match '^\[([^\]]+)\]') {
            if ($section -eq "desktop" -and -not $desktopSelectionWritten) {
                [void]$output.Add('selected-avatar-id = "' + $avatarId + '"')
            }
            $section = $matches[1].Trim()
            if ($section -eq "desktop") {
                $desktopSeen = $true
                $desktopSelectionWritten = $false
            }
            [void]$output.Add($line)
            continue
        }

        if (($section -eq "" -or $section -eq "desktop") -and
            $trimmed -match '^selected-avatar-id\s*=') {
            if ($section -eq "desktop" -and -not $desktopSelectionWritten) {
                [void]$output.Add('selected-avatar-id = "' + $avatarId + '"')
                $desktopSelectionWritten = $true
            }
            continue
        }
        [void]$output.Add($line)
    }

    if ($section -eq "desktop" -and -not $desktopSelectionWritten) {
        [void]$output.Add('selected-avatar-id = "' + $avatarId + '"')
    } elseif (-not $desktopSeen) {
        while ($output.Count -gt 0 -and [string]::IsNullOrWhiteSpace($output[$output.Count - 1])) {
            $output.RemoveAt($output.Count - 1)
        }
        if ($output.Count -gt 0) { [void]$output.Add("") }
        [void]$output.Add("[desktop]")
        [void]$output.Add('selected-avatar-id = "' + $avatarId + '"')
    }

    return ($output -join "`r`n").TrimEnd() + "`r`n"
}

function Get-BubuSkinFromConfig {
    $configPath = Join-Path $script:CodexHome "config.toml"
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { return "blue" }
    try {
        $section = ""
        foreach ($line in [IO.File]::ReadAllLines($configPath, [Text.Encoding]::UTF8)) {
            $trimmed = ([string]$line).Trim()
            if ($trimmed -match '^\[([^\]]+)\]') {
                $section = $matches[1].Trim()
                continue
            }
            if ($section -ne "desktop") { continue }
            if ($trimmed -match '^selected-avatar-id\s*=\s*"([^"]+)"') {
                if ($matches[1] -eq "custom:bubu-orange") { return "orange" }
                if ($matches[1] -eq "custom:bubu-office") { return "blue" }
            }
        }
    } catch {
        Write-PanelLog ("SKIN read failed " + $_.Exception.Message)
    }
    return "blue"
}

function Set-BubuSkinSelection([string]$skin) {
    if ($skin -ne "blue" -and $skin -ne "orange") { return $false }
    $configPath = Join-Path $script:CodexHome "config.toml"
    $tempPath = $configPath + ".bubu-" + [Guid]::NewGuid().ToString("N") + ".tmp"
    $backupPath = $configPath + ".bubu-backup"
    try {
        [IO.Directory]::CreateDirectory($script:CodexHome) | Out-Null
        $original = if (Test-Path -LiteralPath $configPath -PathType Leaf) {
            [IO.File]::ReadAllText($configPath, [Text.Encoding]::UTF8)
        } else { "" }
        $avatarId = Get-BubuSkinAvatarId $skin
        $updated = Update-CodexSkinSelectionText $original $avatarId
        [IO.File]::WriteAllText($tempPath, $updated, [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $configPath -PathType Leaf) {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
            [IO.File]::Replace($tempPath, $configPath, $backupPath, $true)
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        } else {
            [IO.File]::Move($tempPath, $configPath)
        }
        $selected = Get-BubuSkinFromConfig
        Write-PanelLog ("SKIN selected=" + $selected)
        return $selected -eq $skin
    } catch {
        Write-PanelLog ("SKIN write failed " + $_.Exception.Message)
        return $false
    } finally {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }
}

if ($ValidateSkinSelection) {
    $sample = @'
selected-avatar-id = "codex"
[general]
model = "gpt"
[desktop]
avatar-overlay-mascot-width-px = 163
selected-avatar-id = "custom:old-pet"
[features]
test = true
'@
    $orange = Update-CodexSkinSelectionText $sample "custom:bubu-orange"
    $blue = Update-CodexSkinSelectionText $orange "custom:bubu-office"
    $missing = Update-CodexSkinSelectionText "[general]`nmodel = `"gpt`"`n" "custom:bubu-orange"
    $orangeValid = $orange -match 'selected-avatar-id = "custom:bubu-orange"'
    $blueValid = $blue -match 'selected-avatar-id = "custom:bubu-office"'
    $oneKey = ([Text.RegularExpressions.Regex]::Matches($orange, 'selected-avatar-id')).Count -eq 1
    $missingValid = $missing -match '(?ms)^\[desktop\]\r?\nselected-avatar-id = "custom:bubu-orange"'
    if (-not $orangeValid -or -not $blueValid -or -not $oneKey -or -not $missingValid) {
        throw "Skin-selection config update validation failed."
    }
    Write-Output "skin-selection-valid: blue=True orange=True persistence=True duplicate-key=True"
    exit 0
}

# Release 17 is the blue Bubu edition. Clear any orange preview selection
# left by an earlier local build before the panel starts following the pet.
$script:SelectedSkin = "blue"
[void](Set-BubuSkinSelection "blue")

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="卜卜额度面板"
        Width="224" Height="$($script:ExpandedHeight)"
        WindowStyle="None" ResizeMode="NoResize"
        AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ShowActivated="False"
        Focusable="False" SnapsToDevicePixels="True"
        TextOptions.TextFormattingMode="Display">
    <Window.Resources>
        <Style x:Key="PanelButton" TargetType="Button">
            <Setter Property="Foreground" Value="#E8FFFFFF"/>
            <Setter Property="Background" Value="#1CFFFFFF"/>
            <Setter Property="BorderBrush" Value="#34FFFFFF"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontFamily" Value="Microsoft YaHei UI"/>
            <Setter Property="FontSize" Value="9.5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Padding" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="ButtonBorder"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="8">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ButtonBorder" Property="Background" Value="#34FFFFFF"/>
                                <Setter TargetName="ButtonBorder" Property="BorderBrush" Value="#58FFFFFF"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="ButtonBorder" Property="Background" Value="#48FFFFFF"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="SkinButton" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderBrush" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Padding" Value="0"/>
            <Setter Property="Focusable" Value="False"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="SkinRing"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="17"/>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="SkinRing" Property="Background" Value="#16FFFFFF"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="SkinRing" Property="Background" Value="#2AFFFFFF"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid x:Name="PanelScaleRoot" RenderTransformOrigin="0,0">
        <Canvas x:Name="ExpandedRoot" Width="224" Height="$($script:ExpandedHeight)">
            <Polygon x:Name="ExpandedPointer" Points="104,$($script:ExpandedBodyHeight) 112,$($script:ExpandedPointerTipY) 120,$($script:ExpandedBodyHeight)"
                     Fill="#F7080B17" Stroke="#38FFFFFF" StrokeThickness="1"/>
            <Border x:Name="ExpandedPanelBorder" Canvas.Left="3" Canvas.Top="3" Width="218" Height="$($script:ExpandedBodyHeight)"
                    CornerRadius="17" Background="#F7080B17"
                    BorderBrush="#38FFFFFF" BorderThickness="1">
                <Grid ClipToBounds="True">
                    <Rectangle x:Name="BackgroundBand" Height="93" VerticalAlignment="Top"/>
                    <Canvas x:Name="ExpandedContentCanvas" Width="218" Height="$($script:ExpandedBodyHeight)">
                        <TextBlock x:Name="CodexName" Canvas.Left="14" Canvas.Top="11"
                                   Width="62" Height="18" Text="Codex"
                                   FontFamily="Microsoft YaHei UI" FontSize="11" FontWeight="SemiBold"
                                   Foreground="#E8FFFFFF"/>
                        <TextBlock x:Name="RemainingText" Canvas.Left="82" Canvas.Top="11"
                                   Width="82" Height="18" Text="正在读取…"
                                   TextAlignment="Right" FontFamily="Consolas" FontSize="10.5"
                                   FontWeight="SemiBold" Foreground="#FF3899"/>
                        <Button x:Name="HideButton" Canvas.Left="170" Canvas.Top="7"
                                Width="38" Height="18" Content="隐藏"
                                Style="{StaticResource PanelButton}"/>
                        <Grid Canvas.Left="14" Canvas.Top="65" Width="190" Height="4">
                            <Border Background="#4D000000" CornerRadius="2"/>
                            <Border x:Name="QuotaProgressFill" Width="3" HorizontalAlignment="Left"
                                    Background="#3899FF" CornerRadius="2"/>
                        </Grid>
                        <TextBlock x:Name="ResetText" Canvas.Left="14" Canvas.Top="74"
                                   Width="96" Height="15" Text="重置时间未知"
                                   FontFamily="Microsoft YaHei UI" FontSize="9.2"
                                   Foreground="#B8FFFFFF"/>
                        <TextBlock x:Name="QuotaStatusText" Canvas.Left="106" Canvas.Top="74"
                                   Width="98" Height="15" Text="5 分钟后重试"
                                   TextAlignment="Right" FontFamily="Microsoft YaHei UI" FontSize="9.2"
                                   Foreground="#B8FFFFFF"/>

                        <Canvas x:Name="TaskProgressRows" Canvas.Left="0" Canvas.Top="93"
                                Width="218" Height="23"/>

                        <Canvas x:Name="MarketRows" Width="218" Height="$($script:ExpandedBodyHeight)">
                        <Border Canvas.Left="14" Canvas.Top="116" Width="190" Height="1"
                                Background="#21FFFFFF"/>
                        <Ellipse Canvas.Left="14" Canvas.Top="123" Width="15" Height="15"
                                 Fill="#F7931A"/>
                        <TextBlock Canvas.Left="14" Canvas.Top="122.5" Width="15" Height="15"
                                   Text="₿" TextAlignment="Center" FontFamily="Segoe UI Symbol"
                                   FontSize="10" FontWeight="Bold" Foreground="White"/>
                        <TextBlock Canvas.Left="34" Canvas.Top="123" Width="62" Height="16"
                                   Text="BTC/USDT" FontFamily="Microsoft YaHei UI"
                                   FontSize="9.6" FontWeight="SemiBold" Foreground="#C8FFFFFF"/>
                        <TextBlock x:Name="BTCPriceText" Canvas.Left="92" Canvas.Top="121.5"
                                   Width="80" Height="18" Text="--" TextAlignment="Right"
                                   FontFamily="Consolas" FontSize="11.4" FontWeight="Bold"
                                   Foreground="#F0FFFFFF"/>
                        <TextBlock x:Name="BTCStatusText" Canvas.Left="176" Canvas.Top="124"
                                   Width="28" Height="14" Text="读取中"
                                   TextAlignment="Right" FontFamily="Microsoft YaHei UI"
                                   FontSize="8.2" Foreground="#8AFFFFFF"/>

                        </Canvas>
                    </Canvas>
                </Grid>
            </Border>
        </Canvas>

        <Canvas x:Name="CollapsedRoot" Width="64" Height="44" Visibility="Collapsed"
                HorizontalAlignment="Left" VerticalAlignment="Top">
            <Polygon x:Name="CollapsedPointer" Points="24,31 32,43 40,31"
                     Fill="#F7080B17" Stroke="#38FFFFFF" StrokeThickness="1"/>
            <Border Canvas.Left="3" Canvas.Top="3" Width="58" Height="31"
                    CornerRadius="13" Background="#F7080B17"
                    BorderBrush="#38FFFFFF" BorderThickness="1">
                <Button x:Name="ShowButton" Width="50" Height="22" Content="显示"
                        Style="{StaticResource PanelButton}"/>
            </Border>
        </Canvas>
    </Grid>
</Window>
"@

$xml = New-Object Xml.XmlDocument
$xml.LoadXml($xaml)
$reader = [Xml.XmlNodeReader]::new($xml)
$script:Window = [Windows.Markup.XamlReader]::Load($reader)
$script:Window.WindowStartupLocation = [Windows.WindowStartupLocation]::Manual
$script:Window.Left = -32000
$script:Window.Top = -32000
$script:WindowHandle = [Windows.Interop.WindowInteropHelper]::new($script:Window).EnsureHandle()
[BubuPanel.NativeWindows]::ApplyNoActivateStyle($script:WindowHandle)

$lightstickXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Bubu Quota Lightstick"
        Width="38" Height="122"
        WindowStyle="None" ResizeMode="NoResize"
        AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ShowActivated="False"
        Focusable="False" IsHitTestVisible="False" SnapsToDevicePixels="True">
    <Grid x:Name="LightstickScaleRoot" Width="38" Height="122"
          RenderTransformOrigin="0.5,0.5">
        <Grid.RenderTransform>
            <RotateTransform Angle="-5.5"/>
        </Grid.RenderTransform>
        <Canvas Width="38" Height="122">
            <Border Canvas.Left="10" Canvas.Top="84" Width="18" Height="33"
                    CornerRadius="7" BorderBrush="#B8FFFFFF" BorderThickness="0.8">
                <Border.Background>
                    <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                        <GradientStop Color="#FFFFFFFF" Offset="0"/>
                        <GradientStop Color="#FFC7CBD0" Offset="1"/>
                    </LinearGradientBrush>
                </Border.Background>
            </Border>
            <Border Canvas.Left="13" Canvas.Top="101" Width="12" Height="13"
                    CornerRadius="5" Background="#16000000"/>
            <Border Canvas.Left="9" Canvas.Top="77" Width="20" Height="8" CornerRadius="2.5">
                <Border.Background>
                    <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                        <GradientStop Color="#FF4D4D4D" Offset="0"/>
                        <GradientStop Color="#FF080808" Offset="0.5"/>
                        <GradientStop Color="#FF3E3E3E" Offset="1"/>
                    </LinearGradientBrush>
                </Border.Background>
            </Border>
            <Border Canvas.Left="8.5" Canvas.Top="4" Width="21" Height="74"
                    CornerRadius="10.5" BorderBrush="#70FFFFFF" BorderThickness="0.8"
                    Background="#3DC0D6E5" ClipToBounds="True">
                <Canvas x:Name="LightstickTubeCanvas" Width="21" Height="74" ClipToBounds="True">
                    <Border x:Name="QuotaLightstickFill" Canvas.Left="0" Canvas.Top="74"
                            Width="21" Height="0" Background="#FF00CFFF">
                        <Border.Effect>
                            <DropShadowEffect x:Name="QuotaLightstickGlow" Color="#FF064DFF"
                                              BlurRadius="7" ShadowDepth="0" Opacity="0.9"/>
                        </Border.Effect>
                    </Border>
                    <Rectangle x:Name="QuotaLightstickSurface" Canvas.Left="2.5" Canvas.Top="73"
                               Width="16" Height="1" Fill="#C8FFFFFF"/>
                    <Line X1="2.5" X2="5" Y1="18.5" Y2="18.5" Stroke="#50FFFFFF" StrokeThickness="0.65"/>
                    <Line X1="2.5" X2="5" Y1="37" Y2="37" Stroke="#50FFFFFF" StrokeThickness="0.65"/>
                    <Line X1="2.5" X2="5" Y1="55.5" Y2="55.5" Stroke="#50FFFFFF" StrokeThickness="0.65"/>
                    <Border Canvas.Left="2.5" Canvas.Top="8" Width="3.2" Height="59"
                            CornerRadius="1.6" Background="#42FFFFFF"/>
                </Canvas>
            </Border>
            <Path Data="M 14.2,93 L 16.3,97.5 L 18.5,94.1 L 20.7,97.5 L 23,93 M 14.2,93 L 14.2,99.1 L 23,99.1 L 23,93"
                  Stroke="#FF0875FF" StrokeThickness="1.4"
                  StrokeLineJoin="Round" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
        </Canvas>
    </Grid>
</Window>
"@

$lightstickXml = New-Object Xml.XmlDocument
$lightstickXml.LoadXml($lightstickXaml)
$lightstickReader = [Xml.XmlNodeReader]::new($lightstickXml)
$script:QuotaLightstickWindow = [Windows.Markup.XamlReader]::Load($lightstickReader)
$script:QuotaLightstickWindow.WindowStartupLocation = [Windows.WindowStartupLocation]::Manual
$script:QuotaLightstickWindow.Left = -32000
$script:QuotaLightstickWindow.Top = -32000
$script:QuotaLightstickWindowHandle = [Windows.Interop.WindowInteropHelper]::new(
    $script:QuotaLightstickWindow
).EnsureHandle()
[BubuPanel.NativeWindows]::ApplyNoActivateStyle($script:QuotaLightstickWindowHandle)
$script:LightstickScaleRoot = $script:QuotaLightstickWindow.FindName("LightstickScaleRoot")
$script:QuotaLightstickFill = $script:QuotaLightstickWindow.FindName("QuotaLightstickFill")
$script:QuotaLightstickSurface = $script:QuotaLightstickWindow.FindName("QuotaLightstickSurface")
$script:QuotaLightstickGlow = $script:QuotaLightstickWindow.FindName("QuotaLightstickGlow")
$script:QuotaLightstickBaseWidth = 38.0
$script:QuotaLightstickBaseHeight = 122.0
$script:QuotaLightstickTubeHeight = 74.0
$script:QuotaLightstickRemaining = $null

$script:HealthPath = Join-Path $PSScriptRoot "panel-health.json"
$script:LastPositionMode = "starting"
$script:LastQuotaStatus = "starting"
$script:LastHealthWrite = [DateTime]::MinValue

function Write-PanelHealth([bool]$force) {
    if (-not $force -and ([DateTime]::UtcNow - $script:LastHealthWrite).TotalSeconds -lt 15) { return }
    try {
        $payload = [ordered]@{
            version = $script:PanelVersion
            processId = $PID
            updatedAt = [DateTimeOffset]::Now.ToString("o")
            positionMode = $script:LastPositionMode
            trackingMode = if ($script:TrackingMode) { $script:TrackingMode } else { "starting" }
            followEngine = "composition-rendering+33ms-fallback"
            perMonitorDpiV2 = $script:PerMonitorDpiEnabled
            marketPricesEnabled = $script:MarketPricesEnabled
            panelBaseHeightPoints = $script:ExpandedHeight
            panelScale = [Math]::Round($script:PanelScale, 4)
            panelWidthPoints = [Math]::Round($script:Window.Width, 2)
            panelHeightPoints = [Math]::Round($script:Window.Height, 2)
            horizontalAlignmentPixels = [Math]::Round($script:TrackingAlignmentX, 2)
            verticalAlignmentPixels = [Math]::Round($script:TrackingAlignmentY, 2)
            fallbackGraceMilliseconds = $script:NativeFallbackGraceMilliseconds
            lastNativeSuccessAt = if (-not $script:LastNativeSuccessAt -or
                $script:LastNativeSuccessAt -eq [DateTime]::MinValue) { $null } else { $script:LastNativeSuccessAt.ToString("o") }
            lastPetMotionAt = if (-not $script:LastPetMotionAt -or
                $script:LastPetMotionAt -eq [DateTime]::MinValue) { $null } else { $script:LastPetMotionAt.ToString("o") }
            quotaStatus = $script:LastQuotaStatus
            taskProgress = if ($script:LastTaskProgress) { $script:LastTaskProgress } else { "reading" }
            selectedSkin = $script:SelectedSkin
            stateSource = if ($script:OverlayState) { "available" } else { "unavailable" }
        } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($script:HealthPath, $payload, [Text.UTF8Encoding]::new($false))
        $script:LastHealthWrite = [DateTime]::UtcNow
    } catch {
    }
}

Write-PanelLog ("WINDOW handle=" + $script:WindowHandle)

function Get-Control([string]$name) {
    return $script:Window.FindName($name)
}

$script:PanelScaleRoot = Get-Control "PanelScaleRoot"
$script:ExpandedRoot = Get-Control "ExpandedRoot"
$script:ExpandedPanelBorder = Get-Control "ExpandedPanelBorder"
$script:ExpandedContentCanvas = Get-Control "ExpandedContentCanvas"
$script:CollapsedRoot = Get-Control "CollapsedRoot"
$script:ExpandedPointer = Get-Control "ExpandedPointer"
$script:CollapsedPointer = Get-Control "CollapsedPointer"
$script:BackgroundBand = Get-Control "BackgroundBand"
$script:RemainingText = Get-Control "RemainingText"
$script:QuotaProgressFill = Get-Control "QuotaProgressFill"
$script:ResetText = Get-Control "ResetText"
$script:QuotaStatusText = Get-Control "QuotaStatusText"
$script:TaskProgressRows = Get-Control "TaskProgressRows"
$script:MarketRows = Get-Control "MarketRows"
$script:BTCPriceText = Get-Control "BTCPriceText"
$script:BTCStatusText = Get-Control "BTCStatusText"
$script:HideButton = Get-Control "HideButton"
$script:ShowButton = Get-Control "ShowButton"

if (-not $script:MarketPricesEnabled) {
    $script:MarketRows.Visibility = [Windows.Visibility]::Collapsed
}

if ($ValidateXaml) {
    if (-not $script:QuotaLightstickWindow -or -not $script:QuotaLightstickFill -or
        -not $script:QuotaLightstickSurface -or -not $script:QuotaLightstickGlow) {
        throw "Quota lightstick XAML controls are missing."
    }
    Write-Output (
        "xaml-valid: version=" + $script:PanelVersion +
        " marketPricesEnabled=" + $script:MarketPricesEnabled.ToString().ToLowerInvariant() +
        " width=" + [int]($script:Window.Width) +
        " height=" + [int]($script:Window.Height) +
        " marketRows=" + $script:MarketRows.Visibility +
        " skinButtons=False lightstick=True"
    )
    exit 0
}

$backgroundPath = Join-Path $PSScriptRoot "quota-panel-background.png"
if (Test-Path -LiteralPath $backgroundPath) {
    $bitmap = New-Object Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit()
    $bitmap.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bitmap.UriSource = [Uri]::new($backgroundPath)
    $bitmap.EndInit()
    $bitmap.Freeze()

    $imageBrush = [Windows.Media.ImageBrush]::new($bitmap)
    $imageBrush.ViewboxUnits = [Windows.Media.BrushMappingMode]::RelativeToBoundingBox
    $imageBrush.Viewbox = [Windows.Rect]::new(0, 0.34, 1, 0.32)
    $imageBrush.Stretch = [Windows.Media.Stretch]::Fill
    $script:BackgroundBand.Fill = $imageBrush
}

function Get-TaskIconBitmap([string]$name) {
    $path = Join-Path $PSScriptRoot $name
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $bitmap = New-Object Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit()
    $bitmap.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bitmap.UriSource = [Uri]::new($path)
    $bitmap.EndInit()
    $bitmap.Freeze()
    return $bitmap
}

$script:RunningTaskIconBitmap = Get-TaskIconBitmap "task-running-icon.png"
$script:WaitingTaskIconBitmap = Get-TaskIconBitmap "task-waiting-icon.png"
$script:CompletedTaskIconBitmap = Get-TaskIconBitmap "task-completed-icon.png"
$script:FailedTaskIconBitmap = Get-TaskIconBitmap "task-failed-icon.png"

function New-Brush([string]$hex) {
    return [Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString($hex))
}

$script:BlueBrush = New-Brush "#FF3899"
$script:AmberBrush = New-Brush "#FFB338"
$script:RedBrush = New-Brush "#FF646E"
$script:GreenBrush = New-Brush "#3DDB94"
$script:WhiteBrush = New-Brush "#F0FFFFFF"
$script:TaskReadingBrush = New-Brush "#8FFFFFFF"
$script:TaskRunningBrush = New-Brush "#38ADFF"
$script:TaskWaitingBrush = New-Brush "#FFB338"
$script:TaskCompletedBrush = New-Brush "#3DDB94"
$script:TaskFailedBrush = New-Brush "#FF5C4D"
$script:SkinSelectedBrush = New-Brush "#FFFF334F"
$script:SkinUnselectedBrush = New-Brush "#00FFFFFF"
$script:LightstickBlueBrush = New-Brush "#FF00CFFF"
$script:LightstickAmberBrush = New-Brush "#FFFFA81A"
$script:LightstickRedBrush = New-Brush "#FFFF2E24"

function Set-SkinButtonSelection([string]$skin) {
    $script:SelectedSkin = if ($skin -eq "orange") { "orange" } else { "blue" }
    foreach ($entry in @(
        [PSCustomObject]@{ Name = "blue"; Button = $script:BlueSkinButton },
        [PSCustomObject]@{ Name = "orange"; Button = $script:OrangeSkinButton }
    )) {
        $selected = $entry.Name -eq $script:SelectedSkin
        $entry.Button.BorderBrush = if ($selected) {
            $script:SkinSelectedBrush
        } else {
            $script:SkinUnselectedBrush
        }
        $entry.Button.BorderThickness = if ($selected) {
            [Windows.Thickness]::new(2)
        } else {
            [Windows.Thickness]::new(0)
        }
    }
}

function Get-QuotaBrush([int]$remaining) {
    if ($remaining -le 20) { return $script:RedBrush }
    if ($remaining -le 45) { return $script:AmberBrush }
    return $script:BlueBrush
}

function Get-QuotaLightstickBrush([int]$remaining) {
    if ($remaining -lt 25) { return $script:LightstickRedBrush }
    if ($remaining -le 50) { return $script:LightstickAmberBrush }
    return $script:LightstickBlueBrush
}

function Get-QuotaLightstickGlowColor([int]$remaining) {
    if ($remaining -lt 25) {
        return [Windows.Media.ColorConverter]::ConvertFromString("#FFC7000D")
    }
    if ($remaining -le 50) {
        return [Windows.Media.ColorConverter]::ConvertFromString("#FFFF570A")
    }
    return [Windows.Media.ColorConverter]::ConvertFromString("#FF064DFF")
}

function Update-QuotaLightstick([int]$remaining) {
    $safeRemaining = [Math]::Max(0, [Math]::Min(100, $remaining))
    $script:QuotaLightstickRemaining = $safeRemaining
    $fillHeight = $script:QuotaLightstickTubeHeight * $safeRemaining / 100.0
    $fillTop = $script:QuotaLightstickTubeHeight - $fillHeight
    $script:QuotaLightstickFill.Height = $fillHeight
    [Windows.Controls.Canvas]::SetTop($script:QuotaLightstickFill, $fillTop)
    $script:QuotaLightstickFill.Background = Get-QuotaLightstickBrush $safeRemaining
    $script:QuotaLightstickGlow.Color = Get-QuotaLightstickGlowColor $safeRemaining
    if ($fillHeight -le 0) {
        $script:QuotaLightstickSurface.Visibility = [Windows.Visibility]::Collapsed
    } else {
        $script:QuotaLightstickSurface.Visibility = [Windows.Visibility]::Visible
        [Windows.Controls.Canvas]::SetTop(
            $script:QuotaLightstickSurface,
            [Math]::Max(0, $fillTop - 0.5)
        )
    }
}

function Update-QuotaUI([int]$remaining, [string]$resetText, [string]$statusText) {
    $safeRemaining = [Math]::Max(0, [Math]::Min(100, $remaining))
    $brush = Get-QuotaBrush $safeRemaining
    $script:RemainingText.Text = "剩余 $safeRemaining%"
    $script:RemainingText.Foreground = $brush
    $script:QuotaProgressFill.Background = $brush
    $script:QuotaProgressFill.Width = [Math]::Max(3, 190 * $safeRemaining / 100.0)
    Update-QuotaLightstick $safeRemaining
    $script:ResetText.Text = $resetText
    $script:QuotaStatusText.Text = $statusText
    $script:LastQuotaStatus = "ok"
    Write-PanelLog "QUOTA ok"
    Write-PanelHealth $true
}

function Set-QuotaError([string]$message) {
    $script:RemainingText.Text = "暂时无法读取"
    $script:RemainingText.Foreground = $script:AmberBrush
    $script:QuotaProgressFill.Background = $script:AmberBrush
    $script:QuotaProgressFill.Width = 3
    $script:ResetText.Text = $message
    $script:QuotaStatusText.Text = "自动重试"
    $script:LastQuotaStatus = "error:" + $message
    Write-PanelLog ("QUOTA error " + $message)
    Write-PanelHealth $true
}

function Convert-ToCodexLaunch([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) {
        return $null
    }

    $extension = [IO.Path]::GetExtension($path).ToLowerInvariant()
    if ($extension -eq ".cmd" -or $extension -eq ".bat") {
        return [PSCustomObject]@{
            FileName = $env:ComSpec
            Arguments = ('/d /s /c ""{0}" app-server --stdio"' -f $path)
            SourcePath = $path
        }
    }

    if ($extension -eq ".exe" -or $extension -eq "") {
        return [PSCustomObject]@{
            FileName = $path
            Arguments = "app-server --stdio"
            SourcePath = $path
        }
    }

    return $null
}

function Find-CodexLaunch {
    $candidates = New-Object Collections.Generic.List[string]
    $searchRoots = New-Object Collections.Generic.List[string]
    # Windows PowerShell 5.1-safe, case-insensitive de-duplication.
    $seen = @{}
    $addCandidate = {
        param([string]$candidate)
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and -not $seen.ContainsKey($candidate)) {
            $seen[$candidate] = $true
            [void]$candidates.Add($candidate)
        }
    }
    $addSearchRoot = {
        param([string]$candidate)
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            $searchRoots.Add($candidate)
        }
    }

    & $addCandidate $env:CODEX_BIN
    foreach ($name in @("codex.exe", "codex.cmd", "codex")) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command -and $command.Source) { & $addCandidate $command.Source }
    }

    try {
        foreach ($desktopProcess in Get-Process -ErrorAction SilentlyContinue |
            Where-Object { $_.ProcessName -match "ChatGPT|Codex|OpenAI" }) {
            if (-not $desktopProcess.Path) { continue }
            $desktopDirectory = Split-Path -Parent $desktopProcess.Path
            foreach ($relative in @(
                "resources\codex.exe",
                "resources\bin\codex.exe",
                "resources\app\resources\codex.exe",
                "resources\app.asar.unpacked\codex.exe",
                "codex.exe"
            )) {
                & $addCandidate (Join-Path $desktopDirectory $relative)
            }
            & $addSearchRoot (Join-Path $desktopDirectory "resources")
        }
    } catch {
    }

    foreach ($knownPath in @(
        (Join-Path $env:APPDATA "npm\codex.cmd"),
        (Join-Path $env:APPDATA "npm\node_modules\@openai\codex\vendor\x86_64-pc-windows-msvc\codex\codex.exe"),
        (Join-Path $env:APPDATA "npm\node_modules\@openai\codex\vendor\aarch64-pc-windows-msvc\codex\codex.exe"),
        (Join-Path $script:CodexHome "packages\standalone\current\bin\codex.exe"),
        (Join-Path $script:CodexHome "packages\standalone\current\bin\codex.cmd"),
        (Join-Path $env:LOCALAPPDATA "Programs\ChatGPT\resources\codex.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\ChatGPT\resources\app\resources\codex.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\OpenAI ChatGPT\resources\codex.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Codex\resources\codex.exe"),
        (Join-Path $env:ProgramFiles "ChatGPT\resources\codex.exe"),
        (Join-Path $env:ProgramFiles "Codex\resources\codex.exe")
    )) {
        & $addCandidate $knownPath
    }

    foreach ($candidate in $candidates) {
        if ($script:FailedCodexLaunches.ContainsKey($candidate) -and
            $script:FailedCodexLaunches[$candidate] -gt [DateTime]::UtcNow) { continue }
        $launch = Convert-ToCodexLaunch $candidate
        if ($launch) {
            Write-PanelLog ("CODEX found " + $candidate)
            return $launch
        }
    }

    foreach ($root in @(
        (Join-Path $env:LOCALAPPDATA "Programs\ChatGPT"),
        (Join-Path $env:LOCALAPPDATA "Programs\Codex"),
        (Join-Path $env:LOCALAPPDATA "OpenAI"),
        (Join-Path $script:CodexHome "packages")
    )) {
        & $addSearchRoot $root
    }

    try {
        $packages = Get-AppxPackage -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match "ChatGPT|Codex|OpenAI" }
        foreach ($package in $packages) {
            if ($package.InstallLocation) { & $addSearchRoot $package.InstallLocation }
        }
    } catch {
    }

    foreach ($searchRoot in $searchRoots | Select-Object -Unique) {
        try {
            Get-ChildItem -LiteralPath $searchRoot -Filter "codex.exe" -File -Recurse -Depth 6 -ErrorAction SilentlyContinue |
                Select-Object -First 6 |
                ForEach-Object { & $addCandidate $_.FullName }
        } catch {
        }
    }

    foreach ($candidate in $candidates) {
        if ($script:FailedCodexLaunches.ContainsKey($candidate)) {
            if ($script:FailedCodexLaunches[$candidate] -gt [DateTime]::UtcNow) { continue }
            $script:FailedCodexLaunches.Remove($candidate)
        }
        $launch = Convert-ToCodexLaunch $candidate
        if ($launch) {
            Write-PanelLog ("CODEX found " + $candidate)
            return $launch
        }
    }

    Write-PanelLog "CODEX executable not found"
    return $null
}

$script:QuotaProcess = $null
$script:QuotaLineTask = $null
$script:QuotaStartedAt = [DateTime]::MinValue
$script:NextQuotaAt = [DateTime]::UtcNow
$script:CachedCodexLaunch = $null
$script:FailedCodexLaunches = @{}

function Stop-QuotaProcess {
    if ($script:QuotaProcess) {
        try { $script:QuotaProcess.StandardInput.Close() } catch { }
        try {
            if (-not $script:QuotaProcess.HasExited) {
                $script:QuotaProcess.Kill()
            }
        } catch { }
        try { $script:QuotaProcess.Dispose() } catch { }
    }
    $script:QuotaProcess = $null
    $script:QuotaLineTask = $null
}

function Start-QuotaRequest {
    if ($script:QuotaProcess) { return }

    if (-not $script:CachedCodexLaunch) {
        $script:CachedCodexLaunch = Find-CodexLaunch
    }
    if (-not $script:CachedCodexLaunch) {
        Set-QuotaError "请先安装或打开 Codex"
        $script:NextQuotaAt = [DateTime]::UtcNow.AddSeconds(30)
        return
    }

    try {
        $info = New-Object Diagnostics.ProcessStartInfo
        $info.FileName = $script:CachedCodexLaunch.FileName
        $info.Arguments = $script:CachedCodexLaunch.Arguments
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardInput = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        if ($script:CachedCodexLaunch.SourcePath -and (Test-Path -LiteralPath $script:CachedCodexLaunch.SourcePath)) {
            $info.WorkingDirectory = Split-Path -Parent $script:CachedCodexLaunch.SourcePath
        }

        $process = New-Object Diagnostics.Process
        $process.StartInfo = $info
        if (-not $process.Start()) { throw "Codex 本机服务启动失败" }

        $initialize = '{"method":"initialize","id":0,"params":{"clientInfo":{"name":"bubu_windows_panel","title":"Bubu Windows Panel","version":"' + $script:PanelVersion + '"},"capabilities":{"experimentalApi":true}}}'
        $initialized = '{"method":"initialized","params":{}}'
        $readLimits = '{"method":"account/rateLimits/read","id":2}'
        $process.StandardInput.WriteLine($initialize)
        $process.StandardInput.WriteLine($initialized)
        $process.StandardInput.WriteLine($readLimits)
        $process.StandardInput.Flush()

        $script:QuotaProcess = $process
        $script:QuotaLineTask = $process.StandardOutput.ReadLineAsync()
        $script:QuotaStartedAt = [DateTime]::UtcNow
        $script:QuotaStatusText.Text = "正在更新…"
        Write-PanelLog ("QUOTA request started via " + $script:CachedCodexLaunch.SourcePath)
    } catch {
        if ($script:CachedCodexLaunch -and $script:CachedCodexLaunch.SourcePath) {
            $script:FailedCodexLaunches[$script:CachedCodexLaunch.SourcePath] = [DateTime]::UtcNow.AddMinutes(10)
        }
        Write-PanelLog ("QUOTA launch failed " + $_.Exception.Message)
        Stop-QuotaProcess
        $script:CachedCodexLaunch = $null
        Set-QuotaError "Codex 额度连接失败"
        $script:NextQuotaAt = [DateTime]::UtcNow.AddSeconds(15)
    }
}

function Complete-QuotaResponse($response) {
    if (-not $response.result) {
        if ($response.error -and $response.error.message) {
            throw [string]$response.error.message
        }
        throw "Codex 未返回额度数据"
    }

    $snapshot = $response.result.rateLimits
    if ($response.result.rateLimitsByLimitId) {
        $codexBucket = $response.result.rateLimitsByLimitId.PSObject.Properties |
            Where-Object { $_.Name -eq "codex" -or $_.Value.limitId -eq "codex" } |
            Select-Object -First 1
        if ($codexBucket) { $snapshot = $codexBucket.Value }
    }
    if (-not $snapshot) { throw "Codex 未返回标准额度桶" }

    $remaining = $null
    $resetText = "重置时间未知"
    if ($snapshot.primary -and $null -ne $snapshot.primary.usedPercent) {
        $remaining = [Math]::Max(0, 100 - [int][Math]::Round([double]$snapshot.primary.usedPercent))
        if ($snapshot.primary.resetsAt) {
            $resetDate = [DateTimeOffset]::FromUnixTimeSeconds([int64]$snapshot.primary.resetsAt).LocalDateTime
            $resetText = $resetDate.ToString("M/d HH:mm") + " 重置"
        }
    } elseif ($snapshot.individualLimit -and $null -ne $snapshot.individualLimit.remainingPercent) {
        $remaining = [int]$snapshot.individualLimit.remainingPercent
        if ($snapshot.individualLimit.resetsAt) {
            $resetDate = [DateTimeOffset]::FromUnixTimeSeconds([int64]$snapshot.individualLimit.resetsAt).LocalDateTime
            $resetText = $resetDate.ToString("M/d HH:mm") + " 重置"
        }
    } elseif ($snapshot.individualLimit -and $null -ne $snapshot.individualLimit.usedPercent) {
        $remaining = [Math]::Max(0, 100 - [int][Math]::Round([double]$snapshot.individualLimit.usedPercent))
    }

    if ($null -eq $remaining) { throw "Codex 额度格式暂不支持" }

    Update-QuotaUI $remaining $resetText ((Get-Date).ToString("HH:mm") + " 更新 · 5分钟")
}

function Poll-QuotaRequest {
    if (-not $script:QuotaProcess) { return }

    if (([DateTime]::UtcNow - $script:QuotaStartedAt).TotalSeconds -gt 15) {
        Stop-QuotaProcess
        Set-QuotaError "Codex 额度读取超时"
        $script:NextQuotaAt = [DateTime]::UtcNow.AddSeconds(30)
        return
    }

    if (-not $script:QuotaLineTask -or -not $script:QuotaLineTask.IsCompleted) {
        try {
            if ($script:QuotaProcess.HasExited) {
                $details = $script:QuotaProcess.StandardError.ReadToEnd()
                if ($script:CachedCodexLaunch -and $script:CachedCodexLaunch.SourcePath) {
                    $script:FailedCodexLaunches[$script:CachedCodexLaunch.SourcePath] = [DateTime]::UtcNow.AddMinutes(10)
                }
                Write-PanelLog ("QUOTA process exited " + $details)
                Stop-QuotaProcess
                $script:CachedCodexLaunch = $null
                Set-QuotaError "正在切换 Codex 连接"
                $script:NextQuotaAt = [DateTime]::UtcNow.AddSeconds(5)
            }
        } catch {
        }
        return
    }

    try {
        $line = $script:QuotaLineTask.GetAwaiter().GetResult()
        if ($null -eq $line) { throw "Codex 额度连接已断开" }
        $response = $line | ConvertFrom-Json
        if ($response.id -eq 2) {
            Complete-QuotaResponse $response
            Stop-QuotaProcess
            $script:NextQuotaAt = [DateTime]::UtcNow.AddMinutes(5)
        } else {
            $script:QuotaLineTask = $script:QuotaProcess.StandardOutput.ReadLineAsync()
        }
    } catch {
        Write-PanelLog ("QUOTA response failed " + $_.Exception.Message)
        Stop-QuotaProcess
        Set-QuotaError "Codex 额度暂时无法读取"
        $script:NextQuotaAt = [DateTime]::UtcNow.AddSeconds(30)
    }
}

$script:CachedTaskRollouts = @()
$script:TaskVisibilityCache = @{}
$script:ParsedTaskCache = @{}
$script:CachedThreadTitles = @{}
$script:ThreadTitleIndexStamp = 0L
$script:CachedUnreadThreadIDs = @{}
$script:UnreadStateStamp = 0L
$script:HasCachedUnreadState = $false
$script:NextTaskRolloutScanAt = [DateTime]::MinValue
$script:NextTaskProgressAt = [DateTime]::UtcNow
$script:LastTaskProgress = "reading"
$script:LastTaskItems = @()
$script:LastTaskSignature = ""
$script:RunningArrowAngle = 0.0
$script:RunningArrowTransforms = New-Object Collections.ArrayList
$script:TaskIconAnimationTimer = [Windows.Threading.DispatcherTimer]::new(
    [Windows.Threading.DispatcherPriority]::Render
)
$script:TaskIconAnimationTimer.Interval = [TimeSpan]::FromMilliseconds(33)
$script:TaskIconAnimationTimer.Add_Tick({
    $script:RunningArrowAngle = ($script:RunningArrowAngle + 10.0) % 360.0
    foreach ($transform in @($script:RunningArrowTransforms)) {
        $transform.Angle = $script:RunningArrowAngle
    }
})

function Get-TaskProgressBrush([string]$kind) {
    switch ($kind) {
        "running" { return $script:TaskRunningBrush }
        "waiting" { return $script:TaskWaitingBrush }
        "completed" { return $script:TaskCompletedBrush }
        "failed" { return $script:TaskFailedBrush }
        default { return $script:TaskReadingBrush }
    }
}

function Get-TaskProgressStatus([string]$kind) {
    switch ($kind) {
        "reading" { return "读取中" }
        "running" { return "正在执行" }
        "waiting" { return "等你确认" }
        "completed" { return "已完成" }
        "failed" { return "执行失败" }
        default { return "等待" }
    }
}

function Set-TaskProgressRowCount([int]$rowCount) {
    $safeCount = [Math]::Max(1, [Math]::Min($script:MaximumVisibleTaskRows, $rowCount))
    if ($safeCount -eq $script:TaskProgressRowCount) { return }

    $script:TaskProgressRowCount = $safeCount
    $script:ExpandedHeight = $script:BaseExpandedHeight + $script:TaskProgressRowHeight * $safeCount
    $script:ExpandedBodyHeight = $script:ExpandedHeight - 13
    $script:ExpandedPointerTipY = $script:ExpandedHeight - 1

    $script:ExpandedRoot.Height = $script:ExpandedHeight
    $script:ExpandedPanelBorder.Height = $script:ExpandedBodyHeight
    $script:ExpandedContentCanvas.Height = $script:ExpandedBodyHeight
    $script:TaskProgressRows.Height = $script:TaskProgressRowHeight * $safeCount
    $script:MarketRows.Height = $script:ExpandedBodyHeight
    $extraHeight = ($safeCount - 1) * $script:TaskProgressRowHeight
    $script:MarketRows.RenderTransform = [Windows.Media.TranslateTransform]::new(0, $extraHeight)

    $points = [Windows.Media.PointCollection]::new()
    [void]$points.Add([Windows.Point]::new(104, $script:ExpandedBodyHeight))
    [void]$points.Add([Windows.Point]::new(112, $script:ExpandedPointerTipY))
    [void]$points.Add([Windows.Point]::new(120, $script:ExpandedBodyHeight))
    $script:ExpandedPointer.Points = $points

    [void](Set-PanelScale $script:PanelScale)
    $script:Window.UpdateLayout()
    $script:LastPointerCenter = [double]::NaN
}

function Set-TaskProgressUI([object[]]$tasks) {
    $visibleTasks = @($tasks | Where-Object { [string]$_.Kind -ne "completed" })
    if ($visibleTasks.Count -eq 0) {
        $visibleTasks = @([PSCustomObject]@{
            Title = "暂无进行中的任务"
            Kind = "idle"
            Status = "等待"
            StartedAt = [DateTime]::MinValue
        })
    } elseif ($visibleTasks.Count -gt $script:MaximumVisibleTaskRows) {
        $visibleTasks = @($visibleTasks | Select-Object -First $script:MaximumVisibleTaskRows)
    }

    $signature = @($visibleTasks | ForEach-Object {
        ([string]$_.Title) + "|" + ([string]$_.Kind) + "|" + ([string]$_.Status)
    }) -join "`n"
    if ($signature -eq $script:LastTaskSignature) { return }

    Set-TaskProgressRowCount $visibleTasks.Count
    $script:TaskProgressRows.Children.Clear()
    $script:RunningArrowTransforms.Clear()

    for ($index = 0; $index -lt $visibleTasks.Count; $index++) {
        $task = $visibleTasks[$index]
        $rowTop = $index * $script:TaskProgressRowHeight
        $brush = Get-TaskProgressBrush ([string]$task.Kind)
        $kind = [string]$task.Kind
        $iconBitmap = switch ($kind) {
            "running" { $script:RunningTaskIconBitmap; break }
            "waiting" { $script:WaitingTaskIconBitmap; break }
            "completed" { $script:CompletedTaskIconBitmap; break }
            "failed" { $script:FailedTaskIconBitmap; break }
            default { $null; break }
        }
        $usesStatusIcon = $null -ne $iconBitmap

        $separator = [Windows.Controls.Border]::new()
        $separator.Width = 190
        $separator.Height = 1
        $separator.Background = New-Brush "#21FFFFFF"
        [Windows.Controls.Canvas]::SetLeft($separator, 14)
        [Windows.Controls.Canvas]::SetTop($separator, $rowTop)
        [void]$script:TaskProgressRows.Children.Add($separator)

        if ($usesStatusIcon) {
            $taskIcon = [Windows.Controls.Image]::new()
            $taskIcon.Source = $iconBitmap
            $taskIcon.Width = 20
            $taskIcon.Height = 15
            $taskIcon.Stretch = [Windows.Media.Stretch]::Uniform
            $taskIcon.SnapsToDevicePixels = $true
            [Windows.Media.RenderOptions]::SetBitmapScalingMode(
                $taskIcon,
                [Windows.Media.BitmapScalingMode]::HighQuality
            )
            [Windows.Controls.Canvas]::SetLeft($taskIcon, 12)
            [Windows.Controls.Canvas]::SetTop($taskIcon, $rowTop + 4)
            [void]$script:TaskProgressRows.Children.Add($taskIcon)

            # Completed and failed artwork already contains its status badge.
            if ($kind -ne "completed" -and $kind -ne "failed") {
                $badge = [Windows.Shapes.Ellipse]::new()
                $badge.Width = 8.4
                $badge.Height = 8.4
                $badge.Fill = switch ($kind) {
                    "running" { New-Brush "#1F76F5"; break }
                    "waiting" { New-Brush "#FFC21A"; break }
                    "failed" { New-Brush "#E83320"; break }
                }
                [Windows.Controls.Canvas]::SetLeft($badge, 22.6)
                [Windows.Controls.Canvas]::SetTop($badge, $rowTop + 4.4)
                [void]$script:TaskProgressRows.Children.Add($badge)

                $badgeSymbol = [Windows.Controls.TextBlock]::new()
                $badgeSymbol.Text = switch ($kind) {
                    "running" { "↻"; break }
                    "waiting" { "?"; break }
                    "failed" { "×"; break }
                }
                $badgeSymbol.Width = 8.4
                $badgeSymbol.Height = 10
                $badgeSymbol.FontFamily = [Windows.Media.FontFamily]::new("Segoe UI Symbol")
                $badgeSymbol.FontSize = if ($kind -eq "failed") { 8.6 } else { 7.8 }
                $badgeSymbol.FontWeight = [Windows.FontWeights]::Bold
                $badgeSymbol.Foreground = $script:WhiteBrush
                $badgeSymbol.TextAlignment = [Windows.TextAlignment]::Center
                [Windows.Controls.Canvas]::SetLeft($badgeSymbol, 22.6)
                [Windows.Controls.Canvas]::SetTop($badgeSymbol, $rowTop + 3.0)
                if ($kind -eq "running") {
                    $rotation = [Windows.Media.RotateTransform]::new($script:RunningArrowAngle)
                    $badgeSymbol.RenderTransformOrigin = [Windows.Point]::new(0.5, 0.5)
                    $badgeSymbol.RenderTransform = $rotation
                    [void]$script:RunningArrowTransforms.Add($rotation)
                }
                [void]$script:TaskProgressRows.Children.Add($badgeSymbol)
            }
        } else {
            $dot = [Windows.Shapes.Ellipse]::new()
            $dot.Width = 7
            $dot.Height = 7
            $dot.Fill = $brush
            [Windows.Controls.Canvas]::SetLeft($dot, 14)
            [Windows.Controls.Canvas]::SetTop($dot, $rowTop + 11)
            [void]$script:TaskProgressRows.Children.Add($dot)
        }

        $title = [Windows.Controls.TextBlock]::new()
        $title.Text = [string]$task.Title
        $titleLeft = if ($usesStatusIcon) { 36 } else { 27 }
        $title.Width = if ($usesStatusIcon) { 112 } else { 121 }
        $title.Height = 16
        $title.FontFamily = [Windows.Media.FontFamily]::new("Microsoft YaHei UI")
        $title.FontSize = 9.4
        $title.FontWeight = if ($index -eq 0) {
            [Windows.FontWeights]::SemiBold
        } else {
            [Windows.FontWeights]::Medium
        }
        $title.Foreground = New-Brush "#D6FFFFFF"
        $title.TextTrimming = [Windows.TextTrimming]::CharacterEllipsis
        [Windows.Controls.Canvas]::SetLeft($title, $titleLeft)
        [Windows.Controls.Canvas]::SetTop($title, $rowTop + 7)
        [void]$script:TaskProgressRows.Children.Add($title)

        $status = [Windows.Controls.TextBlock]::new()
        $status.Text = if ($task.Status) { [string]$task.Status } else {
            Get-TaskProgressStatus ([string]$task.Kind)
        }
        $status.Width = 56
        $status.Height = 16
        $status.TextAlignment = [Windows.TextAlignment]::Right
        $status.FontFamily = [Windows.Media.FontFamily]::new("Microsoft YaHei UI")
        $status.FontSize = 9.2
        $status.FontWeight = [Windows.FontWeights]::SemiBold
        $status.Foreground = $brush
        $status.TextTrimming = [Windows.TextTrimming]::CharacterEllipsis
        [Windows.Controls.Canvas]::SetLeft($status, 148)
        [Windows.Controls.Canvas]::SetTop($status, $rowTop + 7)
        [void]$script:TaskProgressRows.Children.Add($status)
    }

    $script:LastTaskItems = @($visibleTasks)
    $script:LastTaskProgress = (@($visibleTasks | ForEach-Object { [string]$_.Kind }) -join ",")
    $script:LastTaskSignature = $signature
    if ($script:RunningArrowTransforms.Count -gt 0) {
        $script:TaskIconAnimationTimer.Start()
    } else {
        $script:TaskIconAnimationTimer.Stop()
    }
}

function Get-TaskTitle([string]$message) {
    if ([string]::IsNullOrWhiteSpace($message)) { return $null }
    $value = $message
    $marker = [Text.RegularExpressions.Regex]::Match(
        $value,
        '(?is)##\s*My request for Codex:\s*(.+)$'
    )
    if ($marker.Success) { $value = $marker.Groups[1].Value }
    $value = [Text.RegularExpressions.Regex]::Replace($value, '(?is)<image.*$', '')
    $lines = @($value -split "`r?`n" | ForEach-Object {
        $line = ([string]$_).Trim()
        if (-not $line -or
            $line -match '^#\s*Files mentioned' -or
            $line -match '^##\s*My request' -or
            $line -match '^/[A-Za-z0-9._-]+/') {
            $null
        } else {
            $line -replace '^[#*\-\s]+', ''
        }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $title = ([Text.RegularExpressions.Regex]::Replace(($lines -join ' '), '\s+', ' ')).Trim()
    if (-not $title) { return $null }
    if ($title.Length -gt 80) { return $title.Substring(0, 80) }
    return $title
}

function Get-TaskThreadId([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    $filename = [IO.Path]::GetFileNameWithoutExtension($path)
    $match = [Text.RegularExpressions.Regex]::Match(
        $filename,
        '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
    )
    if (-not $match.Success) { return $null }
    return $match.Value.ToLowerInvariant()
}

function Test-TaskSessionMetadataVisible([string]$line) {
    if ([string]::IsNullOrWhiteSpace($line)) { return $true }
    try { $record = $line | ConvertFrom-Json } catch { return $true }
    if (-not $record -or $record.type -ne 'session_meta' -or -not $record.payload) {
        return $true
    }
    $threadSource = ([string]$record.payload.thread_source).ToLowerInvariant()
    if ($threadSource -eq 'subagent' -or $threadSource -eq 'automation') {
        return $false
    }
    $source = $record.payload.source
    if ($source -and $source.PSObject.Properties['subagent']) {
        return $false
    }
    return $true
}

function Test-TaskRolloutUserVisible([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $true }
    if ($script:TaskVisibilityCache.ContainsKey($path)) {
        return [bool]$script:TaskVisibilityCache[$path]
    }

    $visible = $true
    $stream = $null
    $reader = $null
    try {
        $share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
        $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, $share)
        $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $true, 4096, $true)
        $visible = Test-TaskSessionMetadataVisible ([string]$reader.ReadLine())
    } catch {
        $visible = $true
    } finally {
        if ($reader) { $reader.Dispose() }
        if ($stream) { $stream.Dispose() }
    }
    $script:TaskVisibilityCache[$path] = $visible
    return $visible
}

function Resolve-TaskTitle([string]$path, [hashtable]$threadTitles, [string]$fallback) {
    $threadId = Get-TaskThreadId $path
    if ($threadId -and $threadTitles -and $threadTitles.ContainsKey($threadId)) {
        $indexedTitle = ([string]$threadTitles[$threadId]).Trim()
        if ($indexedTitle) { return $indexedTitle }
    }
    return $fallback
}

function Get-ThreadTitleIndex {
    $indexPath = Join-Path $script:CodexHome 'session_index.jsonl'
    if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
        return $script:CachedThreadTitles
    }

    try {
        $file = Get-Item -LiteralPath $indexPath -ErrorAction Stop
        $stamp = $file.LastWriteTimeUtc.Ticks
        if ($stamp -eq $script:ThreadTitleIndexStamp) {
            return $script:CachedThreadTitles
        }

        $share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
        $stream = [IO.File]::Open(
            $indexPath,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Read,
            $share
        )
        $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $true)
        try {
            $text = $reader.ReadToEnd()
        } finally {
            $reader.Dispose()
            $stream.Dispose()
        }

        $titles = @{}
        foreach ($line in @($text -split "`r?`n")) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $record = $line | ConvertFrom-Json } catch { continue }
            if (-not $record.id -or -not $record.thread_name) { continue }
            $title = ([string]$record.thread_name).Trim()
            if (-not $title) { continue }
            if ($title.Length -gt 80) { $title = $title.Substring(0, 80) }
            $titles[([string]$record.id).ToLowerInvariant()] = $title
        }

        $script:CachedThreadTitles = $titles
        $script:ThreadTitleIndexStamp = $stamp
    } catch {
        return $script:CachedThreadTitles
    }
    return $script:CachedThreadTitles
}

function Get-UnreadThreadState {
    $statePath = if ($env:BUBU_CODEX_STATE_FILE) {
        [string]$env:BUBU_CODEX_STATE_FILE
    } else {
        Join-Path $script:CodexHome '.codex-global-state.json'
    }
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        return [PSCustomObject]@{
            Ids = $script:CachedUnreadThreadIDs
            Available = $script:HasCachedUnreadState
        }
    }

    try {
        $file = Get-Item -LiteralPath $statePath -ErrorAction Stop
        $stamp = $file.LastWriteTimeUtc.Ticks
        if ($stamp -eq $script:UnreadStateStamp) {
            return [PSCustomObject]@{
                Ids = $script:CachedUnreadThreadIDs
                Available = $script:HasCachedUnreadState
            }
        }

        $share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
        $stream = [IO.File]::Open(
            $statePath,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Read,
            $share
        )
        $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $true)
        try {
            $state = ($reader.ReadToEnd()) | ConvertFrom-Json
        } finally {
            $reader.Dispose()
            $stream.Dispose()
        }

        $atomState = $state.'electron-persisted-atom-state'
        $unreadByHost = if ($atomState) {
            $atomState.'unread-thread-ids-by-host-v1'
        } else { $null }
        if ($null -eq $unreadByHost) {
            return [PSCustomObject]@{
                Ids = $script:CachedUnreadThreadIDs
                Available = $script:HasCachedUnreadState
            }
        }

        $ids = @{}
        foreach ($property in @($unreadByHost.PSObject.Properties)) {
            foreach ($id in @($property.Value)) {
                $normalized = ([string]$id).Trim().ToLowerInvariant()
                if ($normalized) { $ids[$normalized] = $true }
            }
        }
        $script:CachedUnreadThreadIDs = $ids
        $script:UnreadStateStamp = $stamp
        $script:HasCachedUnreadState = $true
    } catch {
        return [PSCustomObject]@{
            Ids = $script:CachedUnreadThreadIDs
            Available = $script:HasCachedUnreadState
        }
    }
    return [PSCustomObject]@{
        Ids = $script:CachedUnreadThreadIDs
        Available = $true
    }
}

function Test-TaskShouldDisplay(
    [string]$kind,
    [string]$threadId,
    [DateTime]$modificationDate,
    [DateTime]$now,
    $unreadState
) {
    if ($kind -eq 'completed') { return $false }
    if ($kind -ne 'failed') { return $true }
    if ($unreadState -and $unreadState.Available -and $threadId) {
        return [bool]$unreadState.Ids.ContainsKey($threadId.ToLowerInvariant())
    }
    return ($now - $modificationDate).TotalMinutes -le $script:CompletedTaskFallbackMinutes
}

function Find-RecentTaskRollouts([hashtable]$unreadThreadIDs) {
    $override = [string]$env:BUBU_TASK_ROLLOUT_FILE
    if (-not [string]::IsNullOrWhiteSpace($override)) {
        if ((Test-Path -LiteralPath $override -PathType Leaf) -and
            (Test-TaskRolloutUserVisible $override)) {
            return @(Get-Item -LiteralPath $override -ErrorAction SilentlyContinue)
        }
        return @()
    }

    $now = [DateTime]::UtcNow
    if ($script:CachedTaskRollouts.Count -gt 0 -and $now -lt $script:NextTaskRolloutScanAt) {
        return @($script:CachedTaskRollouts | Where-Object {
            Test-Path -LiteralPath $_.FullName -PathType Leaf
        })
    }

    $script:NextTaskRolloutScanAt = $now.AddSeconds(5)
    $sessionsRoot = Join-Path $script:CodexHome "sessions"
    if (-not (Test-Path -LiteralPath $sessionsRoot -PathType Container)) {
        $script:CachedTaskRollouts = @()
        return @()
    }

    try {
        $cutoff = $now.AddMinutes(-30)
        $script:CachedTaskRollouts = @(Get-ChildItem -LiteralPath $sessionsRoot -Filter "rollout-*.jsonl" `
            -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object {
                $threadId = Get-TaskThreadId $_.FullName
                $recentOrUnread = $_.LastWriteTimeUtc -ge $cutoff -or
                    ($threadId -and $unreadThreadIDs -and $unreadThreadIDs.ContainsKey($threadId))
                $recentOrUnread -and (Test-TaskRolloutUserVisible $_.FullName)
            } |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 12)
    } catch {
        $script:CachedTaskRollouts = @()
    }
    return @($script:CachedTaskRollouts)
}

function Read-TaskRolloutTail([string]$path) {
    $stream = $null
    $reader = $null
    try {
        $share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
        $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, $share)
        $maximumBytes = 1048576L
        $start = [Math]::Max(0L, $stream.Length - $maximumBytes)
        [void]$stream.Seek($start, [IO.SeekOrigin]::Begin)
        $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $true, 4096, $true)
        $text = $reader.ReadToEnd()
        if ($start -gt 0) {
            $firstNewline = $text.IndexOf("`n")
            if ($firstNewline -ge 0) { $text = $text.Substring($firstNewline + 1) }
        }
        return @($text -split "`r?`n")
    } finally {
        if ($reader) { $reader.Dispose() }
        if ($stream) { $stream.Dispose() }
    }
}

function Get-TaskProgressKind(
    [object[]]$lines,
    [DateTime]$modificationDate,
    [DateTime]$now
) {
    $lifecycle = $null
    $pendingUserInput = @{}
    foreach ($lineObject in $lines) {
        $line = [string]$lineObject
        if ($line -notmatch 'task_started|task_complete|task_failed|turn_aborted|"type":"error"|request_user_input|function_call_output|custom_tool_call_output') {
            continue
        }
        try { $record = $line | ConvertFrom-Json } catch { continue }
        if (-not $record -or -not $record.payload) { continue }
        $payload = $record.payload
        if ($record.type -eq "event_msg") {
            if ($payload.type -eq "task_started") {
                $lifecycle = "running"
                $pendingUserInput.Clear()
            } elseif ($payload.type -eq "task_complete") {
                $lifecycle = "completed"
                $pendingUserInput.Clear()
            } elseif ($payload.type -eq "task_failed" -or
                $payload.type -eq "turn_aborted" -or
                $payload.type -eq "error") {
                $lifecycle = "failed"
                $pendingUserInput.Clear()
            }
            continue
        }
        if (($payload.type -eq "function_call" -or $payload.type -eq "custom_tool_call") -and
            $payload.name -eq "request_user_input" -and $payload.call_id) {
            $pendingUserInput[[string]$payload.call_id] = $true
            continue
        }
        if (($payload.type -eq "function_call_output" -or
                $payload.type -eq "custom_tool_call_output") -and $payload.call_id) {
            [void]$pendingUserInput.Remove([string]$payload.call_id)
        }
    }

    if ($lifecycle -eq "running" -and $pendingUserInput.Count -gt 0) { return "waiting" }
    if ($lifecycle) { return $lifecycle }
    if ($pendingUserInput.Count -gt 0) { return "waiting" }
    if (($now.ToUniversalTime() - $modificationDate.ToUniversalTime()).TotalMinutes -le 30) {
        return "running"
    }
    return "idle"
}

function Get-TaskProgressItem(
    [object[]]$lines,
    [DateTime]$modificationDate,
    [DateTime]$now
) {
    $kind = Get-TaskProgressKind -lines $lines -modificationDate $modificationDate -now $now
    if ($kind -eq "idle") { return $null }

    $latestTitle = $null
    $activeTitle = $null
    $startedAt = $modificationDate.ToUniversalTime()
    foreach ($lineObject in $lines) {
        $line = [string]$lineObject
        if ($line -notmatch 'user_message|task_started') { continue }
        try { $record = $line | ConvertFrom-Json } catch { continue }
        if (-not $record -or $record.type -ne "event_msg" -or -not $record.payload) { continue }
        if ($record.payload.type -eq "user_message") {
            $candidateTitle = Get-TaskTitle ([string]$record.payload.message)
            if ($candidateTitle) { $latestTitle = $candidateTitle }
        } elseif ($record.payload.type -eq "task_started") {
            if ($latestTitle) { $activeTitle = $latestTitle }
            if ($record.timestamp) {
                $parsedTimestamp = [DateTimeOffset]::MinValue
                if ([DateTimeOffset]::TryParse([string]$record.timestamp, [ref]$parsedTimestamp)) {
                    $startedAt = $parsedTimestamp.UtcDateTime
                }
            }
        }
    }

    return [PSCustomObject]@{
        Title = if ($activeTitle) { $activeTitle } elseif ($latestTitle) { $latestTitle } else { "Codex 任务" }
        Kind = $kind
        Status = Get-TaskProgressStatus $kind
        StartedAt = $startedAt
        ModifiedAt = $modificationDate.ToUniversalTime()
    }
}

function Update-TaskProgress {
    try {
        $now = [DateTime]::UtcNow
        $threadTitles = Get-ThreadTitleIndex
        $unreadState = Get-UnreadThreadState
        $tasks = New-Object Collections.Generic.List[object]
        foreach ($file in @(Find-RecentTaskRollouts -unreadThreadIDs $unreadState.Ids)) {
            if (-not $file) { continue }
            $cacheKey = [string]$file.FullName
            $cacheStamp = $file.LastWriteTimeUtc.Ticks
            $cached = $script:ParsedTaskCache[$cacheKey]
            if ($cached -and $cached.Stamp -eq $cacheStamp) {
                $item = $cached.Item
            } else {
                $lines = @(Read-TaskRolloutTail $file.FullName)
                $item = Get-TaskProgressItem -lines $lines `
                    -modificationDate $file.LastWriteTimeUtc -now $now
                $script:ParsedTaskCache[$cacheKey] = [PSCustomObject]@{
                    Stamp = $cacheStamp
                    Item = $item
                }
            }
            if (-not $item) { continue }
            $threadId = Get-TaskThreadId $file.FullName
            if (-not (Test-TaskShouldDisplay -kind ([string]$item.Kind) `
                    -threadId $threadId -modificationDate $item.ModifiedAt `
                    -now $now -unreadState $unreadState)) { continue }
            $resolvedTitle = Resolve-TaskTitle -path $file.FullName `
                -threadTitles $threadTitles -fallback ([string]$item.Title)
            [void]$tasks.Add([PSCustomObject]@{
                Title = $resolvedTitle
                Kind = $item.Kind
                Status = $item.Status
                StartedAt = $item.StartedAt
                ModifiedAt = $item.ModifiedAt
            })
        }
        $ordered = @($tasks | Sort-Object `
            @{ Expression = { if ($_.Kind -eq "completed" -or $_.Kind -eq "failed") { 1 } else { 0 } } }, `
            StartedAt, Title)
        Set-TaskProgressUI $ordered
    } catch {
        Set-TaskProgressUI @([PSCustomObject]@{
            Title = "正在读取任务"
            Kind = "reading"
            Status = "读取中"
            StartedAt = [DateTime]::MinValue
        })
    }
}

$script:HttpClient = $null
if ($script:MarketPricesEnabled) {
    $httpHandler = New-Object Net.Http.HttpClientHandler
    $script:HttpClient = [Net.Http.HttpClient]::new($httpHandler)
    $script:HttpClient.Timeout = [TimeSpan]::FromSeconds(8)
}
$script:BTCTask = $null
$script:BTCStartedAt = [DateTime]::MinValue
$script:NextBTCAt = [DateTime]::UtcNow
$script:LastBTCPrice = $null

function Start-BTCRequest {
    if (-not $script:MarketPricesEnabled) { return }
    if ($script:BTCTask) { return }
    try {
        $url = "https://data-api.binance.vision/api/v3/ticker/price?symbol=BTCUSDT"
        $script:BTCTask = $script:HttpClient.GetStringAsync($url)
        $script:BTCStartedAt = [DateTime]::UtcNow
    } catch {
        $script:BTCTask = $null
        $script:BTCStatusText.Text = "离线"
        $script:NextBTCAt = [DateTime]::UtcNow.AddSeconds(5)
    }
}

function Poll-BTCRequest {
    if (-not $script:BTCTask) { return }
    if (-not $script:BTCTask.IsCompleted) { return }

    try {
        $json = $script:BTCTask.GetAwaiter().GetResult() | ConvertFrom-Json
        $price = [double]::Parse([string]$json.price, [Globalization.CultureInfo]::InvariantCulture)
        $direction = 0
        if ($null -ne $script:LastBTCPrice) {
            if ($price -gt [double]$script:LastBTCPrice) { $direction = 1 }
            if ($price -lt [double]$script:LastBTCPrice) { $direction = -1 }
        }
        $script:LastBTCPrice = $price
        $script:BTCPriceText.Text = $price.ToString("N2", [Globalization.CultureInfo]::GetCultureInfo("en-US"))
        if ($direction -gt 0) {
            $script:BTCPriceText.Foreground = $script:GreenBrush
        } elseif ($direction -lt 0) {
            $script:BTCPriceText.Foreground = $script:RedBrush
        } else {
            $script:BTCPriceText.Foreground = $script:WhiteBrush
        }
        $script:BTCStatusText.Text = "5秒"
    } catch {
        if ($null -eq $script:LastBTCPrice) {
            $script:BTCPriceText.Text = "--"
        }
        $script:BTCStatusText.Text = "离线"
    } finally {
        $script:BTCTask = $null
        $script:NextBTCAt = [DateTime]::UtcNow.AddSeconds(5)
    }
}

$script:StatePath = Join-Path $script:CodexHome ".codex-global-state.json"
$script:StatePaths = New-Object Collections.Generic.List[string]
foreach ($candidateRoot in @(
    $script:CodexHome,
    (Join-Path $env:USERPROFILE ".codex"),
    (Join-Path $env:APPDATA "Codex"),
    (Join-Path $env:LOCALAPPDATA "Codex"),
    (Join-Path $env:APPDATA "OpenAI\Codex"),
    (Join-Path $env:LOCALAPPDATA "OpenAI\Codex")
)) {
    if ([string]::IsNullOrWhiteSpace($candidateRoot)) { continue }
    $candidatePath = Join-Path $candidateRoot ".codex-global-state.json"
    if (-not ($script:StatePaths -contains $candidatePath)) {
        [void]$script:StatePaths.Add($candidatePath)
    }
}
$script:OverlayState = $null
$script:LastStateWrite = [DateTime]::MinValue
$script:NextStateCheckAt = [DateTime]::MinValue
$script:ChatProcessIds = @{}
$script:NextProcessScanAt = [DateTime]::MinValue

function Refresh-OverlayState {
    if ([DateTime]::UtcNow -lt $script:NextStateCheckAt) { return }
    # Reading the timestamp is cheap; JSON is parsed only when it changes. A
    # short interval is required because Codex updates mascot geometry while
    # the user changes pet size, even when the overlay window itself stays put.
    $stateDelay = if ($script:TrackingMode -eq "none") { 150 } else { 75 }
    $script:NextStateCheckAt = [DateTime]::UtcNow.AddMilliseconds($stateDelay)
    try {
        foreach ($candidatePath in @($script:StatePath) + @($script:StatePaths)) {
            if (-not (Test-Path -LiteralPath $candidatePath)) { continue }
            $writeTime = [IO.File]::GetLastWriteTimeUtc($candidatePath)
            if ($candidatePath -eq $script:StatePath -and
                $writeTime -eq $script:LastStateWrite -and $script:OverlayState) { return }
            try {
                $raw = [IO.File]::ReadAllText($candidatePath, [Text.Encoding]::UTF8)
                $state = $raw | ConvertFrom-Json
                $containers = @(
                    $state,
                    $state.'electron-persisted-atom-state',
                    $state.state,
                    $state.settings
                )
                foreach ($container in $containers) {
                    if ($container -and $container.'electron-avatar-overlay-bounds') {
                        $script:StatePath = $candidatePath
                        $script:OverlayState = $container
                        $script:LastStateWrite = $writeTime
                        Write-PanelLog ("STATE overlay bounds loaded from " + $candidatePath)
                        return
                    }
                }
            } catch {
                Write-PanelLog ("STATE candidate failed " + $candidatePath + " " + $_.Exception.Message)
            }
        }
        $script:OverlayState = $null
    } catch {
        Write-PanelLog ("STATE read failed " + $_.Exception.Message)
    }
}

function Refresh-ChatProcesses {
    if ([DateTime]::UtcNow -lt $script:NextProcessScanAt) { return }
    $processDelay = if ($script:TrackingMode -eq "none") { 1 } else { 5 }
    $script:NextProcessScanAt = [DateTime]::UtcNow.AddSeconds($processDelay)
    $updated = @{}
    try {
        foreach ($process in Get-Process -ErrorAction SilentlyContinue) {
            $matchesName = $process.ProcessName -match "ChatGPT|Codex|OpenAI"
            $matchesPath = $false
            try { $matchesPath = $process.Path -match "ChatGPT|Codex|OpenAI" } catch { }
            if ($matchesName -or $matchesPath) {
                $updated[[uint32]$process.Id] = $true
            }
        }
    } catch {
    }
    $script:ChatProcessIds = $updated
    if ($updated.Count -gt 0) { Write-PanelHealth $false }
}

$script:PetWindowHandle = [IntPtr]::Zero
$script:NextExactWindowRescanAt = [DateTime]::MinValue
$script:NextHeuristicWindowRescanAt = [DateTime]::MinValue
$script:TrackingMode = "none"
$script:TrackingBounds = $null
$script:TrackingGeometry = $null
$script:LastPetLeft = [int]::MinValue
$script:LastPetTop = [int]::MinValue
$script:LastPetWidth = [int]::MinValue
$script:LastPetHeight = [int]::MinValue
$script:LastPetMotionAt = [DateTime]::MinValue
$script:TrackingAlignmentX = 0.0
$script:TrackingAlignmentY = 0.0
$script:TrackingAlignmentHandle = [IntPtr]::Zero
$script:TrackingAlignmentStateWrite = [DateTime]::MinValue
$script:LastNativeSuccessAt = [DateTime]::MinValue
$script:NativeFallbackGraceMilliseconds = 750

function Test-PetWindowSize($candidate, $bounds) {
    if (-not $candidate -or -not $bounds) { return $false }
    $expectedWidth = [double]$bounds.width
    $expectedHeight = [double]$bounds.height
    if ($expectedWidth -le 0 -or $expectedHeight -le 0) { return $false }
    if ($candidate.Width -lt 80 -or $candidate.Width -gt 2400) { return $false }
    if ($candidate.Height -lt 72 -or $candidate.Height -gt 2400) { return $false }
    $windowSignature = ([string]$candidate.Title + " " + [string]$candidate.ClassName)
    if ($windowSignature -match '(?i)IME|Candidate|InputMethod|TextInput|Cicero|MSCTF') { return $false }
    $expectedRatio = $expectedWidth / $expectedHeight
    $candidateRatio = $candidate.Width / [double]$candidate.Height
    $relativeRatio = $candidateRatio / $expectedRatio
    if ($relativeRatio -lt 0.72 -or $relativeRatio -gt 1.38) { return $false }
    $scaleX = $candidate.Width / $expectedWidth
    $scaleY = $candidate.Height / $expectedHeight
    if ($scaleX -lt 0.20 -or $scaleX -gt 8.0 -or $scaleY -lt 0.20 -or $scaleY -gt 8.0) { return $false }
    if ([Math]::Abs([Math]::Log($scaleX / $scaleY)) -gt 0.30) { return $false }
    return $true
}

function Test-HeuristicPetWindow($candidate) {
    if (-not $candidate) { return $false }
    if (-not [string]::IsNullOrWhiteSpace($candidate.Title)) { return $false }
    if ($candidate.Width -lt 80 -or $candidate.Width -gt 2400 -or
        $candidate.Height -lt 72 -or $candidate.Height -gt 2400) { return $false }
    $windowSignature = ([string]$candidate.Title + " " + [string]$candidate.ClassName)
    if ($windowSignature -match '(?i)IME|Candidate|InputMethod|TextInput|Cicero|MSCTF') { return $false }

    $dpiScale = [BubuPanel.NativeWindows]::GetWindowDpi($candidate.Handle) / 96.0
    $expectedWidth = 356.0 * $dpiScale
    $expectedHeight = 320.0 * $dpiScale
    $scaleX = $candidate.Width / $expectedWidth
    $scaleY = $candidate.Height / $expectedHeight
    $candidateRatio = $candidate.Width / [double]$candidate.Height
    if ($candidateRatio -lt 0.80 -or $candidateRatio -gt 1.55) { return $false }
    if ($scaleX -lt 0.20 -or $scaleX -gt 8.0 -or $scaleY -lt 0.20 -or $scaleY -gt 8.0) { return $false }
    if ([Math]::Abs([Math]::Log($scaleX / $scaleY)) -gt 0.30) { return $false }
    return $true
}

function Get-StateMonitorBounds($bounds, [IntPtr]$fallbackHandle = [IntPtr]::Zero) {
    if ($bounds -and $bounds.displayBounds) {
        $display = $bounds.displayBounds
        if ([double]$display.width -gt 0 -and [double]$display.height -gt 0) {
            $centerX = [int][Math]::Round([double]$display.x + [double]$display.width / 2.0)
            $centerY = [int][Math]::Round([double]$display.y + [double]$display.height / 2.0)
            $monitor = [BubuPanel.NativeWindows]::GetMonitorBoundsAtPoint($centerX, $centerY)
            if ($monitor) { return $monitor }
        }
    }
    if ($fallbackHandle -ne [IntPtr]::Zero) {
        return [BubuPanel.NativeWindows]::GetMonitorBounds($fallbackHandle)
    }
    return $null
}

function Get-NativeOverlayExpectation($candidate, $bounds, $monitorBounds = $null) {
    if (-not $candidate -or -not $bounds) { return $null }
    if (-not $monitorBounds -and $candidate.Handle -ne [IntPtr]::Zero) {
        $monitorBounds = Get-StateMonitorBounds $bounds $candidate.Handle
    }

    $display = $bounds.displayBounds
    if ($monitorBounds -and $display -and
        [double]$display.width -gt 0 -and [double]$display.height -gt 0) {
        # Electron stores desktop positions in display-independent coordinates,
        # while GetWindowRect returns physical pixels. Map through the monitor
        # origins instead of multiplying absolute coordinates by DPI; that also
        # works for negative-coordinate and mixed-DPI secondary displays.
        $scaleX = $monitorBounds.Width / [double]$display.width
        $scaleY = $monitorBounds.Height / [double]$display.height
        return [PSCustomObject]@{
            Left = $monitorBounds.Left + ([double]$bounds.x - [double]$display.x) * $scaleX
            Top = $monitorBounds.Top + ([double]$bounds.y - [double]$display.y) * $scaleY
            Width = [double]$bounds.width * $scaleX
            Height = [double]$bounds.height * $scaleY
        }
    }

    $dpiScale = 1.0
    if ($candidate.Handle -ne [IntPtr]::Zero) {
        $dpiScale = [BubuPanel.NativeWindows]::GetWindowDpi($candidate.Handle) / 96.0
    }
    return [PSCustomObject]@{
        Left = [double]$bounds.x * $dpiScale
        Top = [double]$bounds.y * $dpiScale
        Width = [double]$bounds.width * $dpiScale
        Height = [double]$bounds.height * $dpiScale
    }
}

function Get-PetWindowCandidateScore($candidate, $bounds, $monitorBounds = $null) {
    if (-not (Test-PetWindowSize $candidate $bounds)) { return [double]::MaxValue }
    $expected = Get-NativeOverlayExpectation $candidate $bounds $monitorBounds
    if (-not $expected -or $expected.Width -le 0 -or $expected.Height -le 0) {
        return [double]::MaxValue
    }

    $candidateCenterX = $candidate.Left + $candidate.Width / 2.0
    $candidateCenterY = $candidate.Top + $candidate.Height / 2.0
    $expectedCenterX = $expected.Left + $expected.Width / 2.0
    $expectedCenterY = $expected.Top + $expected.Height / 2.0
    $positionScore = [Math]::Abs($candidateCenterX - $expectedCenterX) +
        [Math]::Abs($candidateCenterY - $expectedCenterY)
    $sizeScore = [Math]::Abs($candidate.Width - $expected.Width) +
        [Math]::Abs($candidate.Height - $expected.Height)
    $ratioScore = [Math]::Abs(
        ($candidate.Width / [double]$candidate.Height) -
        ($expected.Width / [double]$expected.Height)) * 1200.0
    $scaleX = $candidate.Width / [double]$expected.Width
    $scaleY = $candidate.Height / [double]$expected.Height
    $scaleScore = [Math]::Abs($scaleX - $scaleY) * 900.0
    $titlePenalty = if ([string]::IsNullOrWhiteSpace($candidate.Title)) { 0 } else { 4000 }

    # Position is deliberately authoritative. Codex can expose more than one
    # blank Chrome window with the same size; choosing only by size produced a
    # stable 80-90 px horizontal offset on affected Windows installations.
    return $positionScore * 3.0 + $sizeScore * 0.8 +
        $ratioScore + $scaleScore + $titlePenalty
}

function Get-NativeStateAlignment($petWindow, $bounds, $geometry, $monitorBounds = $null) {
    if (-not $petWindow -or -not $bounds -or -not $geometry -or
        [double]$bounds.width -le 0 -or [double]$bounds.height -le 0) {
        return [PSCustomObject]@{ X = 0.0; Y = 0.0; Valid = $false }
    }
    $expected = Get-NativeOverlayExpectation $petWindow $bounds $monitorBounds
    if (-not $expected) {
        return [PSCustomObject]@{ X = 0.0; Y = 0.0; Valid = $false }
    }

    $liveScaleX = $petWindow.Width / [double]$bounds.width
    $liveScaleY = $petWindow.Height / [double]$bounds.height
    $expectedScaleX = $expected.Width / [double]$bounds.width
    $expectedScaleY = $expected.Height / [double]$bounds.height
    $liveCenterX = $petWindow.Left + ($geometry.Left + $geometry.Width / 2.0) * $liveScaleX
    $liveTop = $petWindow.Top + $geometry.Top * $liveScaleY
    $expectedCenterX = $expected.Left + ($geometry.Left + $geometry.Width / 2.0) * $expectedScaleX
    $expectedTop = $expected.Top + $geometry.Top * $expectedScaleY

    return [PSCustomObject]@{
        X = [double]($expectedCenterX - $liveCenterX)
        Y = [double]($expectedTop - $liveTop)
        Valid = $true
    }
}

function Find-PetWindow($bounds) {
    if (-not $bounds -or $script:ChatProcessIds.Count -eq 0) { return $null }

    if ($script:PetWindowHandle -ne [IntPtr]::Zero) {
        $cached = [BubuPanel.NativeWindows]::GetWindow($script:PetWindowHandle)
        if ($cached -and $script:ChatProcessIds.ContainsKey([uint32]$cached.ProcessId) -and
            (Test-PetWindowSize $cached $bounds)) {
            return $cached
        }
        $script:PetWindowHandle = [IntPtr]::Zero
    }

    if ([DateTime]::UtcNow -lt $script:NextExactWindowRescanAt) { return $null }
    $script:NextExactWindowRescanAt = [DateTime]::UtcNow.AddMilliseconds(120)

    $best = $null
    $bestScore = [double]::MaxValue

    foreach ($candidate in [BubuPanel.NativeWindows]::GetVisibleWindows()) {
        if (-not $script:ChatProcessIds.ContainsKey([uint32]$candidate.ProcessId)) { continue }
        if (-not (Test-PetWindowSize $candidate $bounds)) { continue }
        $monitorBounds = Get-StateMonitorBounds $bounds $candidate.Handle
        $score = Get-PetWindowCandidateScore $candidate $bounds $monitorBounds
        if ($score -lt $bestScore) {
            $bestScore = $score
            $best = $candidate
        }
    }

    if ($best) {
        $script:PetWindowHandle = $best.Handle
        Write-PanelLog ("POSITION native window handle=" + $best.Handle + " pid=" + $best.ProcessId +
            " size=" + $best.Width + "x" + $best.Height + " title=" + $best.Title)
    }
    return $best
}

function Find-PetWindowHeuristic($bounds = $null) {
    if ($script:ChatProcessIds.Count -eq 0) { return $null }

    if ($script:PetWindowHandle -ne [IntPtr]::Zero) {
        $cached = [BubuPanel.NativeWindows]::GetWindow($script:PetWindowHandle)
        if ($cached -and $script:ChatProcessIds.ContainsKey([uint32]$cached.ProcessId) -and
            (Test-HeuristicPetWindow $cached)) {
            return $cached
        }
        $script:PetWindowHandle = [IntPtr]::Zero
    }

    if ([DateTime]::UtcNow -lt $script:NextHeuristicWindowRescanAt) { return $null }
    $script:NextHeuristicWindowRescanAt = [DateTime]::UtcNow.AddMilliseconds(120)
    $best = $null
    $bestScore = [double]::MaxValue
    foreach ($candidate in [BubuPanel.NativeWindows]::GetVisibleWindows()) {
        if (-not $script:ChatProcessIds.ContainsKey([uint32]$candidate.ProcessId)) { continue }
        if (-not (Test-HeuristicPetWindow $candidate)) { continue }
        $dpiScale = [BubuPanel.NativeWindows]::GetWindowDpi($candidate.Handle) / 96.0
        $expectedWidth = 356.0 * $dpiScale
        $expectedHeight = 320.0 * $dpiScale
        $sizeScore = [Math]::Abs($candidate.Width - $expectedWidth) +
            [Math]::Abs($candidate.Height - $expectedHeight)
        $classPenalty = if ($candidate.ClassName -match "Chrome|CEF|Widget") { 0 } else { 250 }
        $score = $sizeScore + $classPenalty
        if ($bounds) {
            $monitorBounds = Get-StateMonitorBounds $bounds $candidate.Handle
            $stateScore = Get-PetWindowCandidateScore $candidate $bounds $monitorBounds
            if ($stateScore -lt [double]::MaxValue) { $score = $stateScore + $classPenalty }
        }
        if ($score -lt $bestScore) {
            $bestScore = $score
            $best = $candidate
        }
    }
    if ($best) {
        $script:PetWindowHandle = $best.Handle
        Write-PanelLog ("POSITION heuristic window handle=" + $best.Handle + " pid=" + $best.ProcessId)
    }
    return $best
}

function Hide-PanelWindow {
    if ($script:Window.IsVisible) {
        $script:Window.Hide()
    }
    if ($script:LastPositionMode -ne "hidden") {
        $script:LastPositionMode = "hidden"
        Write-PanelHealth $true
    }
}

function Hide-QuotaLightstickWindow {
    if ($script:QuotaLightstickWindow.IsVisible) {
        $script:QuotaLightstickWindow.Hide()
    }
}

function Set-PositionMode([string]$mode) {
    if ($script:LastPositionMode -ne $mode) {
        $script:LastPositionMode = $mode
        Write-PanelLog ("POSITION mode=" + $mode)
        Write-PanelHealth $true
    }
}

function Limit-PanelScale([double]$scale) {
    if ([double]::IsNaN($scale) -or [double]::IsInfinity($scale) -or $scale -le 0) {
        return 1.0
    }
    return [Math]::Max($script:MinimumPanelScale, [Math]::Min($script:MaximumPanelScale, $scale))
}

function Set-PanelScale([double]$scale) {
    $safeScale = Limit-PanelScale $scale
    $scaleChanged = [Math]::Abs($script:PanelScale - $safeScale) -ge 0.0025
    if ($scaleChanged) {
        $script:PanelScale = $safeScale
        $script:PanelScaleRoot.LayoutTransform = [Windows.Media.ScaleTransform]::new($safeScale, $safeScale)
        $script:LastPointerCenter = [double]::NaN
    }

    $baseWidth = if ($script:IsCollapsed) { $script:CollapsedWidth } else { $script:ExpandedWidth }
    $baseHeight = if ($script:IsCollapsed) { $script:CollapsedHeight } else { [double]$script:ExpandedHeight }
    $targetWidth = $baseWidth * $safeScale
    $targetHeight = $baseHeight * $safeScale
    if ([Math]::Abs($script:Window.Width - $targetWidth) -ge 0.05) {
        $script:Window.Width = $targetWidth
    }
    if ([Math]::Abs($script:Window.Height - $targetHeight) -ge 0.05) {
        $script:Window.Height = $targetHeight
    }
    if ($scaleChanged) {
        $script:Window.UpdateLayout()
    }
    return $safeScale
}

function Set-QuotaLightstickScale([double]$scale) {
    $safeScale = Limit-PanelScale $scale
    $script:LightstickScaleRoot.LayoutTransform = [Windows.Media.ScaleTransform]::new(
        $safeScale, $safeScale
    )
    $script:QuotaLightstickWindow.Width = $script:QuotaLightstickBaseWidth * $safeScale
    $script:QuotaLightstickWindow.Height = $script:QuotaLightstickBaseHeight * $safeScale
    return $safeScale
}

function Get-NativePetVisualMetrics($petWindow) {
    if (-not $petWindow -or -not $petWindow.Handle -or
        $petWindow.Handle -eq [IntPtr]::Zero) { return $null }

    $now = [DateTime]::UtcNow
    $sameWindow = $script:CachedVisualWindowHandle -eq $petWindow.Handle
    $elapsed = ($now - $script:LastVisualProbeAt).TotalMilliseconds
    if ($sameWindow -and $elapsed -lt $script:VisualProbeIntervalMilliseconds) {
        return $script:CachedVisualMetrics
    }

    try {
        $metrics = [BubuPanel.NativeWindows]::CaptureVisibleBounds($petWindow.Handle)
        $script:LastVisualProbeAt = $now
        $script:CachedVisualWindowHandle = $petWindow.Handle
        if ($metrics -and $metrics.Width -ge 20 -and $metrics.Height -ge 30 -and
            $metrics.Width -lt $petWindow.Width * 0.80 -and
            $metrics.Height -lt $petWindow.Height * 0.98) {
            $script:CachedVisualMetrics = $metrics
            $script:CachedVisualAt = $now
            return $metrics
        }
    } catch {
        Write-PanelLog ("VISUAL-PROBE failed=" + $_.Exception.Message)
    }

    # A single failed Chromium frame must not make the panel jump back to its
    # unscaled size. Keep the most recent measurement briefly, but never carry
    # it over to another native window.
    $cachedAge = ($now - $script:CachedVisualAt).TotalMilliseconds
    if ($sameWindow -and $script:CachedVisualMetrics -and $cachedAge -lt 600) {
        return $script:CachedVisualMetrics
    }
    $script:CachedVisualMetrics = $null
    return $null
}

function Get-VisualCaptureCoordinateScale(
    $petWindow,
    $bounds,
    $geometry,
    $visualMetrics,
    [double]$dpi
) {
    if (-not $petWindow -or -not $bounds -or -not $geometry -or -not $visualMetrics -or
        [double]$bounds.width -le 0 -or [double]$bounds.height -le 0) { return 1.0 }
    $dpiScale = [Math]::Max(0.1, $dpi / 96.0)
    if ($dpiScale -le 1.05) { return 1.0 }

    # Depending on the Windows/Electron build, PrintWindow can return either
    # physical pixels or Chromium's 96-DPI logical pixels inside a physical
    # bitmap. Compare the visible mascot anchor against both coordinate spaces
    # before using the capture for scale or placement.
    $windowScaleX = [double]$petWindow.Width / [double]$bounds.width
    $windowScaleY = [double]$petWindow.Height / [double]$bounds.height
    $physicalCenterX = ($geometry.Left + $geometry.Width / 2.0) * $windowScaleX
    $physicalTop = $geometry.Top * $windowScaleY
    $logicalCenterX = $physicalCenterX / $dpiScale
    $logicalTop = $physicalTop / $dpiScale
    $observedCenterX = [double]$visualMetrics.Left + [double]$visualMetrics.Width / 2.0
    $observedTop = [double]$visualMetrics.Top
    $normalizerX = [Math]::Max(24.0, $geometry.Width * $windowScaleX)
    $normalizerY = [Math]::Max(24.0, $script:CanonicalPetHeight * $windowScaleY)
    $physicalError = [Math]::Abs($observedCenterX - $physicalCenterX) / $normalizerX +
        [Math]::Abs($observedTop - $physicalTop) / $normalizerY
    $logicalError = [Math]::Abs($observedCenterX - $logicalCenterX) / $normalizerX +
        [Math]::Abs($observedTop - $logicalTop) / $normalizerY
    if ($logicalError + 0.08 -lt $physicalError) { return $dpiScale }
    return 1.0
}

function ConvertTo-PhysicalPetVisualMetrics(
    $petWindow,
    $bounds,
    $geometry,
    $visualMetrics,
    [double]$dpi
) {
    if (-not $visualMetrics) { return $null }
    $coordinateScale = Get-VisualCaptureCoordinateScale `
        $petWindow $bounds $geometry $visualMetrics $dpi
    return [PSCustomObject]@{
        Left = [double]$visualMetrics.Left * $coordinateScale
        Top = [double]$visualMetrics.Top * $coordinateScale
        Width = [double]$visualMetrics.Width * $coordinateScale
        Height = [double]$visualMetrics.Height * $coordinateScale
        VisibleFraction = [double]$visualMetrics.VisibleFraction
        CoordinateScale = [double]$coordinateScale
    }
}

function Reset-PanelScaleStabilizer {
    $script:PendingPanelScale = [double]::NaN
    $script:PendingPanelScaleSamples = 0
    $script:PendingPanelScaleWindowHandle = [IntPtr]::Zero
}

function Get-StabilizedPanelScale([double]$candidateScale, [IntPtr]$windowHandle) {
    $safeCandidate = Limit-PanelScale $candidateScale
    $currentScale = Limit-PanelScale $script:PanelScale
    if ([Math]::Abs([Math]::Log($safeCandidate / $currentScale)) -le 0.035) {
        Reset-PanelScaleStabilizer
        return $currentScale
    }

    $sameWindow = $script:PendingPanelScaleWindowHandle -eq $windowHandle
    $sameCandidate = -not [double]::IsNaN($script:PendingPanelScale) -and
        [Math]::Abs([Math]::Log($safeCandidate / $script:PendingPanelScale)) -le
            $script:VisualScalePendingTolerance
    if (-not $sameWindow -or -not $sameCandidate) {
        $script:PendingPanelScale = $safeCandidate
        $script:PendingPanelScaleSamples = 1
        $script:PendingPanelScaleWindowHandle = $windowHandle
        return $currentScale
    }

    $script:PendingPanelScaleSamples++
    if ($script:PendingPanelScaleSamples -lt $script:VisualScaleConfirmationSamples) {
        return $currentScale
    }
    Reset-PanelScaleStabilizer
    return $safeCandidate
}

function Get-VisualPetScaleCandidates($visualMetrics, [double]$dpi) {
    if (-not $visualMetrics -or [double]$visualMetrics.Width -le 0 -or
        [double]$visualMetrics.Height -le 0) { return @() }
    $dpiScale = [Math]::Max(0.1, $dpi / 96.0)
    $allCandidates = @(
        foreach ($encodedSize in $script:PetFrameVisiblePixelSizes) {
            $parts = $encodedSize.Split('x')
            $frameWidth = [double]$parts[0]
            $frameHeight = [double]$parts[1]
            $expectedWidth = $frameWidth * $script:CanonicalPetWidth /
                $script:PetAtlasFrameWidth * $dpiScale
            $expectedHeight = $frameHeight * $script:CanonicalPetHeight /
                $script:PetAtlasFrameHeight * $dpiScale
            $widthScale = [double]$visualMetrics.Width / $expectedWidth
            $heightScale = [double]$visualMetrics.Height / $expectedHeight
            if ($widthScale -gt 0 -and $heightScale -gt 0) {
                [PSCustomObject]@{
                    Scale = Limit-PanelScale ([Math]::Sqrt($widthScale * $heightScale))
                    Distortion = [Math]::Abs([Math]::Log($widthScale / $heightScale))
                }
            }
        }
    )
    if ($allCandidates.Count -eq 0) { return @() }
    $distortionMeasurement = $allCandidates |
        Measure-Object -Property Distortion -Minimum
    $bestDistortion = [double]$distortionMeasurement.Minimum
    if ($bestDistortion -gt 0.15) { return @() }
    return @($allCandidates | Where-Object {
        $_.Distortion -le $bestDistortion + 0.02
    })
}

function Get-NativePetScale($petWindow, $bounds, $geometry, [double]$dpi, $visualMetrics = $null) {
    if (-not $petWindow -or -not $bounds -or -not $geometry -or
        [double]$bounds.width -le 0 -or [double]$bounds.height -le 0) {
        return 1.0
    }
    $dpiScale = [Math]::Max(0.1, $dpi / 96.0)
    $storedPetScale = [double]$geometry.Width / $script:CanonicalPetWidth
    $liveScaleX = $petWindow.Width / [double]$bounds.width / $dpiScale
    $liveScaleY = $petWindow.Height / [double]$bounds.height / $dpiScale
    if ($liveScaleX -le 0 -or $liveScaleY -le 0) { return Limit-PanelScale $storedPetScale }

    # The persisted geometry may lag briefly while the native overlay is being
    # resized. Multiplying its scale by the live/reference window ratio keeps
    # the panel synchronized throughout the resize, not only after JSON saves.
    $liveWindowRatio = [Math]::Sqrt($liveScaleX * $liveScaleY)
    $anchorScale = Limit-PanelScale ($storedPetScale * $liveWindowRatio)
    if (-not $visualMetrics -or [double]$visualMetrics.Height -le 0) {
        return $anchorScale
    }

    $visualCandidates = @(Get-VisualPetScaleCandidates $visualMetrics $dpi)
    if ($visualCandidates.Count -eq 0) { return $anchorScale }
    # Several animation frames can have nearly the same aspect ratio. Prefer
    # the matching frame whose scale is nearest the saved anchor, so coffee,
    # singing and guitar poses cannot make the panel pulse by themselves.
    $bestVisualCandidate = $visualCandidates |
        Sort-Object { [Math]::Abs([Math]::Log($_.Scale / $anchorScale)) } |
        Select-Object -First 1
    $visualScale = [double]$bestVisualCandidate.Scale
    if ($anchorScale -le 0 -or $visualScale -le 0) { return $anchorScale }
    $relativeDifference = [Math]::Abs([Math]::Log($visualScale / $anchorScale))
    # Different animation rows have a little natural transparent padding. Only
    # override the saved anchor when the actual rendered size changed enough
    # to be a real Bubu zoom, not ordinary frame-to-frame motion.
    if ($relativeDifference -gt $script:VisualScaleTolerance) {
        return $visualScale
    }
    return $anchorScale
}

function Get-MascotGeometry($bounds) {
    if ($bounds.mascot) {
        $width = [double]$bounds.mascot.width
        $petScale = Limit-PanelScale ($width / $script:CanonicalPetWidth)
        return [PSCustomObject]@{
            Left = [double]$bounds.mascot.left
            Top = [double]$bounds.mascot.top + 7 * $petScale
            Width = $width
        }
    }
    if ($bounds.anchor) {
        $width = [double]$bounds.anchor.width
        $petScale = Limit-PanelScale ($width / $script:CanonicalPetWidth)
        return [PSCustomObject]@{
            Left = [double]$bounds.anchor.x - [double]$bounds.x
            Top = [double]$bounds.anchor.y - [double]$bounds.y + 7 * $petScale
            Width = $width
        }
    }

    $estimatedWidth = [Math]::Max(24.0,
        [double]$bounds.width * $script:CanonicalPetWidth / 356.0)
    $estimatedLeft = ([double]$bounds.width - $estimatedWidth) / 2.0
    if ($bounds.placement -match "start$") { $estimatedLeft = 8.0 }
    if ($bounds.placement -match "end$") { $estimatedLeft = [double]$bounds.width - $estimatedWidth - 8.0 }
    return [PSCustomObject]@{
        Left = $estimatedLeft
        Top = 15.0 * ([double]$bounds.height / 320.0)
        Width = $estimatedWidth
    }
}

$script:LastPointerCenter = [double]::NaN
function Set-PanelPointer([double]$centerPhysical, [double]$panelPhysicalWidth) {
    if ($panelPhysicalWidth -le 0) { return }
    # Polygon coordinates stay in the unscaled 224/64 design space; the root
    # LayoutTransform scales them with the rest of the panel.
    $logicalWidth = if ($script:IsCollapsed) { $script:CollapsedWidth } else { $script:ExpandedWidth }
    $logicalCenter = $centerPhysical * $logicalWidth / $panelPhysicalWidth
    $safeInset = if ($script:IsCollapsed) { 12.0 } else { 18.0 }
    $logicalCenter = [Math]::Max($safeInset, [Math]::Min($logicalWidth - $safeInset, $logicalCenter))
    if (-not [double]::IsNaN($script:LastPointerCenter) -and
        [Math]::Abs($script:LastPointerCenter - $logicalCenter) -lt 0.25) { return }
    $script:LastPointerCenter = $logicalCenter

    $points = [Windows.Media.PointCollection]::new()
    if ($script:IsCollapsed) {
        $points.Add([Windows.Point]::new($logicalCenter - 8, 31))
        $points.Add([Windows.Point]::new($logicalCenter, 43))
        $points.Add([Windows.Point]::new($logicalCenter + 8, 31))
        $script:CollapsedPointer.Points = $points
    } else {
        $points.Add([Windows.Point]::new($logicalCenter - 8, $script:ExpandedBodyHeight))
        $points.Add([Windows.Point]::new($logicalCenter, $script:ExpandedPointerTipY))
        $points.Add([Windows.Point]::new($logicalCenter + 8, $script:ExpandedBodyHeight))
        $script:ExpandedPointer.Points = $points
    }
}

function Get-NativePetAnchor(
    $petWindow,
    $bounds,
    $geometry,
    [double]$alignmentX = 0.0,
    [double]$alignmentY = 0.0,
    $visualMetrics = $null
) {
    if (-not $petWindow -or -not $bounds -or -not $geometry -or
        [double]$bounds.width -le 0 -or [double]$bounds.height -le 0) { return $null }
    if ($visualMetrics -and [double]$visualMetrics.Width -gt 0 -and
        [double]$visualMetrics.Height -gt 0) {
        return [PSCustomObject]@{
            CenterX = [double]($petWindow.Left + $visualMetrics.Left +
                $visualMetrics.Width / 2.0)
            Top = [double]($petWindow.Top + $visualMetrics.Top)
        }
    }
    $scaleX = $petWindow.Width / [double]$bounds.width
    $scaleY = $petWindow.Height / [double]$bounds.height
    return [PSCustomObject]@{
        CenterX = [double]($petWindow.Left +
            ($geometry.Left + $geometry.Width / 2.0) * $scaleX + $alignmentX)
        Top = [double]($petWindow.Top + $geometry.Top * $scaleY + $alignmentY)
    }
}

function Show-QuotaLightstickAtNativePet(
    $petWindow,
    $anchor,
    $visualMetrics,
    [double]$dpi,
    [double]$petScale,
    $workArea
) {
    if (-not $petWindow -or -not $anchor) { return $false }
    $safeScale = Set-QuotaLightstickScale $petScale
    if (-not $script:QuotaLightstickWindow.IsVisible) {
        $script:QuotaLightstickWindow.Show()
        $script:QuotaLightstickWindow.UpdateLayout()
    }
    $lightstickWindow = [BubuPanel.NativeWindows]::GetWindow(
        $script:QuotaLightstickWindowHandle
    )
    if (-not $lightstickWindow) { return $false }

    $dpiScale = [Math]::Max(0.1, $dpi / 96.0)
    if ($visualMetrics -and [double]$visualMetrics.Width -gt 0 -and
        [double]$visualMetrics.Height -gt 0) {
        $petLeft = [double]($petWindow.Left + $visualMetrics.Left)
        $petBottom = [double]($petWindow.Top + $visualMetrics.Top + $visualMetrics.Height)
    } else {
        $petWidth = $script:CanonicalPetWidth * $safeScale * $dpiScale
        $petHeight = $script:CanonicalPetHeight * $safeScale * $dpiScale
        $petLeft = [double]$anchor.CenterX - $petWidth / 2.0
        $petBottom = [double]$anchor.Top + $petHeight
    }

    $left = [Math]::Round(
        $petLeft - $lightstickWindow.Width + 8.0 * $safeScale * $dpiScale
    )
    $top = [Math]::Round(
        $petBottom - $lightstickWindow.Height - 18.0 * $safeScale * $dpiScale
    )
    if ($workArea) {
        $left = [Math]::Max(
            [double]$workArea.Left,
            [Math]::Min([double]$workArea.Right - $lightstickWindow.Width, $left)
        )
        $top = [Math]::Max(
            [double]$workArea.Top,
            [Math]::Min([double]$workArea.Bottom - $lightstickWindow.Height, $top)
        )
    }
    if ([Math]::Abs($lightstickWindow.Left - $left) -gt 1 -or
        [Math]::Abs($lightstickWindow.Top - $top) -gt 1) {
        [void][BubuPanel.NativeWindows]::MoveWindowNoActivate(
            $script:QuotaLightstickWindowHandle, [int]$left, [int]$top
        )
    }
    return $true
}

function Get-NativePanelPlacement(
    $petWindow,
    $bounds,
    $geometry,
    $panelWindow,
    [double]$dpi,
    [double]$panelScale,
    $workArea,
    [double]$alignmentX = 0.0,
    [double]$alignmentY = 0.0,
    $visualMetrics = $null
) {
    if (-not $petWindow -or -not $bounds -or -not $geometry -or -not $panelWindow) { return $null }
    if ([double]$bounds.width -le 0 -or [double]$bounds.height -le 0 -or
        $panelWindow.Width -le 0 -or $panelWindow.Height -le 0) { return $null }

    $anchor = Get-NativePetAnchor $petWindow $bounds $geometry `
        $alignmentX $alignmentY $visualMetrics
    if (-not $anchor) { return $null }
    $visualCenterX = $anchor.CenterX
    $visualTop = $anchor.Top
    $gap = 14.0 * $dpi / 96.0
    $safePanelScale = Limit-PanelScale $panelScale
    $pointerBottomInset = $safePanelScale * $dpi / 96.0
    $left = [Math]::Round($visualCenterX - $panelWindow.Width / 2.0)
    # The pointer's one-DIP bottom inset grows with both DPI and Bubu's scale.
    # Position the scaled tip, not the outer edge, exactly 14 logical pixels
    # above Bubu. Never clamp vertically because that would detach the panel.
    $top = [Math]::Round($visualTop - $gap - ($panelWindow.Height - $pointerBottomInset))

    if ($workArea) {
        $screenMargin = 8.0 * $dpi / 96.0
        $left = [Math]::Max($workArea.Left + $screenMargin,
            [Math]::Min($workArea.Right - $panelWindow.Width - $screenMargin, $left))
    }

    $pointerCenterPhysical = $visualCenterX - $left
    return [PSCustomObject]@{
        Left = [int]$left
        Top = [int]$top
        PointerCenterPhysical = [double]$pointerCenterPhysical
        PanelScale = [double]$safePanelScale
        GapPixels = [double]$gap
        ActualGapPixels = [double]($visualTop - ($top + $panelWindow.Height - $pointerBottomInset))
        CenterErrorPixels = [double](($left + $pointerCenterPhysical) - $visualCenterX)
    }
}

function Show-PanelAtNativePetWindow($petWindow, $bounds, $geometry) {
    $dpi = [BubuPanel.NativeWindows]::GetWindowDpi($petWindow.Handle)
    $capturedVisualMetrics = Get-NativePetVisualMetrics $petWindow
    $visualMetrics = ConvertTo-PhysicalPetVisualMetrics `
        $petWindow $bounds $geometry $capturedVisualMetrics $dpi
    $candidatePanelScale = Get-NativePetScale `
        $petWindow $bounds $geometry $dpi $visualMetrics
    $panelScale = Get-StabilizedPanelScale $candidatePanelScale $petWindow.Handle
    [void](Set-PanelScale $panelScale)
    if (-not $script:IsPanelHiddenByUser -and -not $script:Window.IsVisible) {
        $script:Window.Show()
        $script:Window.UpdateLayout()
    }

    $panelWindow = [BubuPanel.NativeWindows]::GetWindow($script:WindowHandle)
    if (-not $panelWindow) { return $false }

    # Affected Codex builds can expose a synchronized transparent helper window
    # on another display. The calibrated Bubu center is authoritative; using the
    # helper window's monitor for horizontal clamping makes the panel alternate
    # between Bubu and a screen edge for a single frame.
    $anchor = Get-NativePetAnchor $petWindow $bounds $geometry `
        $script:TrackingAlignmentX $script:TrackingAlignmentY $visualMetrics
    $workArea = if ($anchor) {
        [BubuPanel.NativeWindows]::GetMonitorWorkAreaAtPoint(
            [int][Math]::Round($anchor.CenterX), [int][Math]::Round($anchor.Top))
    } else { $null }
    if (-not $workArea) {
        $workArea = [BubuPanel.NativeWindows]::GetMonitorWorkArea($petWindow.Handle)
    }
    [void](Show-QuotaLightstickAtNativePet `
        $petWindow $anchor $visualMetrics $dpi $panelScale $workArea)
    if ($script:IsPanelHiddenByUser) { return $true }
    $placement = Get-NativePanelPlacement `
        $petWindow $bounds $geometry $panelWindow $dpi $panelScale $workArea `
        $script:TrackingAlignmentX $script:TrackingAlignmentY $visualMetrics
    if (-not $placement) { return $false }

    if ([Math]::Abs($panelWindow.Left - $placement.Left) -gt 1 -or
        [Math]::Abs($panelWindow.Top - $placement.Top) -gt 1) {
        [void][BubuPanel.NativeWindows]::MoveWindowNoActivate(
            $script:WindowHandle, $placement.Left, $placement.Top)
    }
    Set-PanelPointer $placement.PointerCenterPhysical $panelWindow.Width
    $script:LastNativeSuccessAt = [DateTime]::UtcNow
    Set-PositionMode "native-dpi-v2"
    return $true
}

function Show-PanelAtHeuristicWindow($petWindow) {
    $dpi = [BubuPanel.NativeWindows]::GetWindowDpi($petWindow.Handle)
    $estimatedBounds = [PSCustomObject]@{ width = 356.0; height = 320.0 }
    $estimatedGeometry = [PSCustomObject]@{ Left = 165.0; Top = 15.0; Width = 163.0 }
    $capturedVisualMetrics = Get-NativePetVisualMetrics $petWindow
    $visualMetrics = ConvertTo-PhysicalPetVisualMetrics `
        $petWindow $estimatedBounds $estimatedGeometry $capturedVisualMetrics $dpi
    $candidatePanelScale = Get-NativePetScale `
        $petWindow $estimatedBounds $estimatedGeometry $dpi $visualMetrics
    $panelScale = Get-StabilizedPanelScale $candidatePanelScale $petWindow.Handle
    [void](Set-PanelScale $panelScale)
    if (-not $script:IsPanelHiddenByUser -and -not $script:Window.IsVisible) {
        $script:Window.Show()
        $script:Window.UpdateLayout()
    }
    $panelWindow = [BubuPanel.NativeWindows]::GetWindow($script:WindowHandle)
    if (-not $panelWindow) { return $false }
    $anchor = Get-NativePetAnchor `
        $petWindow $estimatedBounds $estimatedGeometry 0.0 0.0 $visualMetrics
    $workArea = if ($anchor) {
        [BubuPanel.NativeWindows]::GetMonitorWorkAreaAtPoint(
            [int][Math]::Round($anchor.CenterX), [int][Math]::Round($anchor.Top))
    } else { $null }
    if (-not $workArea) {
        $workArea = [BubuPanel.NativeWindows]::GetMonitorWorkArea($petWindow.Handle)
    }
    [void](Show-QuotaLightstickAtNativePet `
        $petWindow $anchor $visualMetrics $dpi $panelScale $workArea)
    if ($script:IsPanelHiddenByUser) { return $true }
    $placement = Get-NativePanelPlacement `
        $petWindow $estimatedBounds $estimatedGeometry $panelWindow $dpi $panelScale $workArea `
        0.0 0.0 $visualMetrics
    if (-not $placement) { return $false }
    if ([Math]::Abs($panelWindow.Left - $placement.Left) -gt 1 -or
        [Math]::Abs($panelWindow.Top - $placement.Top) -gt 1) {
        [void][BubuPanel.NativeWindows]::MoveWindowNoActivate(
            $script:WindowHandle, $placement.Left, $placement.Top)
    }
    Set-PanelPointer $placement.PointerCenterPhysical $panelWindow.Width
    $script:LastNativeSuccessAt = [DateTime]::UtcNow
    Set-PositionMode "native-heuristic-dpi-v2"
    return $true
}

function Show-PanelAtSavedState($bounds, $geometry) {
    $panelScale = Limit-PanelScale ([double]$geometry.Width / $script:CanonicalPetWidth)
    [void](Set-PanelScale $panelScale)
    [void](Set-QuotaLightstickScale $panelScale)
    $visualCenterX = [double]$bounds.x + $geometry.Left + $geometry.Width / 2.0
    $visualTop = [double]$bounds.y + $geometry.Top
    $petLeft = [double]$bounds.x + $geometry.Left
    $petBottom = $visualTop + $script:CanonicalPetHeight * $panelScale
    $stickLeft = $petLeft - $script:QuotaLightstickWindow.Width + 8 * $panelScale
    $stickTop = $petBottom - $script:QuotaLightstickWindow.Height - 18 * $panelScale
    $script:QuotaLightstickWindow.Left = [Math]::Round($stickLeft)
    $script:QuotaLightstickWindow.Top = [Math]::Round($stickTop)
    if (-not $script:QuotaLightstickWindow.IsVisible) {
        $script:QuotaLightstickWindow.Show()
    }
    if ($script:IsPanelHiddenByUser) { return }
    $left = $visualCenterX - $script:Window.Width / 2.0
    $top = $visualTop - 14 - ($script:Window.Height - $panelScale)

    if ($bounds.displayBounds) {
        $display = $bounds.displayBounds
        $left = [Math]::Max([double]$display.x + 8,
            [Math]::Min([double]$display.x + [double]$display.width - $script:Window.Width - 8, $left))
    }

    $script:Window.Left = [Math]::Round($left)
    $script:Window.Top = [Math]::Round($top)
    if (-not $script:Window.IsVisible) { $script:Window.Show() }
    $panelWindow = [BubuPanel.NativeWindows]::GetWindow($script:WindowHandle)
    if ($panelWindow) {
        Set-PanelPointer ($panelWindow.Width / 2.0) $panelWindow.Width
    }
    Set-PositionMode "saved-state-fallback"
}

function Update-NativeTrackingAlignment($petWindow, $bounds, $geometry, [bool]$force) {
    if (-not $petWindow -or -not $bounds -or -not $geometry) {
        $script:TrackingAlignmentX = 0.0
        $script:TrackingAlignmentY = 0.0
        return
    }
    if (-not $force -and (Test-PetIsMoving)) { return }
    if (-not $force -and
        $script:TrackingAlignmentHandle -eq $petWindow.Handle -and
        $script:TrackingAlignmentStateWrite -eq $script:LastStateWrite) { return }

    $monitorBounds = Get-StateMonitorBounds $bounds $petWindow.Handle
    $alignment = Get-NativeStateAlignment $petWindow $bounds $geometry $monitorBounds
    if (-not $alignment.Valid) { return }

    $script:TrackingAlignmentX = [double]$alignment.X
    $script:TrackingAlignmentY = [double]$alignment.Y
    $script:TrackingAlignmentHandle = $petWindow.Handle
    $script:TrackingAlignmentStateWrite = $script:LastStateWrite
    Write-PanelLog ("POSITION alignment x=" + [Math]::Round($alignment.X, 2) +
        " y=" + [Math]::Round($alignment.Y, 2))
}

function Set-NativeTrackingTarget([string]$mode, $bounds, $geometry, $petWindow = $null) {
    $targetChanged = $script:TrackingMode -ne $mode -or
        ($petWindow -and $script:TrackingAlignmentHandle -ne $petWindow.Handle)
    $script:TrackingMode = $mode
    $script:TrackingBounds = $bounds
    $script:TrackingGeometry = $geometry
    if ($targetChanged) {
        Reset-PanelScaleStabilizer
    }
    if ($bounds -and $geometry -and $petWindow) {
        Update-NativeTrackingAlignment $petWindow $bounds $geometry $targetChanged
    } elseif ($mode -eq "heuristic") {
        $script:TrackingAlignmentX = 0.0
        $script:TrackingAlignmentY = 0.0
        $script:TrackingAlignmentHandle = if ($petWindow) { $petWindow.Handle } else { [IntPtr]::Zero }
        $script:TrackingAlignmentStateWrite = [DateTime]::MinValue
    }
}

function Clear-NativeTrackingTarget {
    $script:TrackingMode = "none"
    $script:TrackingBounds = $null
    $script:TrackingGeometry = $null
    $script:TrackingAlignmentX = 0.0
    $script:TrackingAlignmentY = 0.0
    $script:TrackingAlignmentHandle = [IntPtr]::Zero
    $script:TrackingAlignmentStateWrite = [DateTime]::MinValue
    Reset-PanelScaleStabilizer
}

function Test-NativeFallbackGraceAt(
    [DateTime]$now,
    [DateTime]$lastNativeSuccess,
    [int]$graceMilliseconds
) {
    if ($lastNativeSuccess -eq [DateTime]::MinValue -or $graceMilliseconds -le 0) { return $false }
    $elapsed = ($now - $lastNativeSuccess).TotalMilliseconds
    return $elapsed -ge 0 -and $elapsed -le $graceMilliseconds
}

function Test-NativeTrackingGrace {
    return ($script:Window.IsVisible -or $script:QuotaLightstickWindow.IsVisible) -and `
        (Test-NativeFallbackGraceAt ([DateTime]::UtcNow) $script:LastNativeSuccessAt `
            $script:NativeFallbackGraceMilliseconds)
}

function Follow-PetWindowFast {
    if ($script:PetWindowHandle -eq [IntPtr]::Zero -or $script:TrackingMode -eq "none") { return }
    $petWindow = [BubuPanel.NativeWindows]::GetWindow($script:PetWindowHandle)
    $targetIsValid = $petWindow -and (
        ($script:TrackingMode -eq "exact" -and $script:TrackingBounds -and
            (Test-PetWindowSize $petWindow $script:TrackingBounds)) -or
        (($script:TrackingMode -eq "heuristic" -or $script:TrackingMode -eq "heuristic-state") -and
            (Test-HeuristicPetWindow $petWindow))
    )
    if (-not $targetIsValid) {
        $script:PetWindowHandle = [IntPtr]::Zero
        Clear-NativeTrackingTarget
        $script:NextStateCheckAt = [DateTime]::MinValue
        $script:NextProcessScanAt = [DateTime]::MinValue
        $script:NextTargetRefreshAt = [DateTime]::UtcNow
        return
    }

    if ($petWindow.Left -ne $script:LastPetLeft -or
        $petWindow.Top -ne $script:LastPetTop -or
        $petWindow.Width -ne $script:LastPetWidth -or
        $petWindow.Height -ne $script:LastPetHeight) {
        $script:LastPetLeft = $petWindow.Left
        $script:LastPetTop = $petWindow.Top
        $script:LastPetWidth = $petWindow.Width
        $script:LastPetHeight = $petWindow.Height
        $script:LastPetMotionAt = [DateTime]::UtcNow
    }

    if (($script:TrackingMode -eq "exact" -or $script:TrackingMode -eq "heuristic-state") -and
        $script:TrackingBounds -and $script:TrackingGeometry) {
        [void](Show-PanelAtNativePetWindow $petWindow $script:TrackingBounds $script:TrackingGeometry)
        return
    }
    if ($script:TrackingMode -eq "heuristic") {
        [void](Show-PanelAtHeuristicWindow $petWindow)
    }
}

function Test-PetIsMoving {
    return ([DateTime]::UtcNow - $script:LastPetMotionAt).TotalMilliseconds -lt 280
}

function Update-PetTarget {
    Refresh-OverlayState
    Refresh-ChatProcesses

    if (-not $script:OverlayState) {
        $heuristicWindow = Find-PetWindowHeuristic
        if ($heuristicWindow) {
            Set-NativeTrackingTarget "heuristic" $null $null $heuristicWindow
            [void](Show-PanelAtHeuristicWindow $heuristicWindow)
            return
        }
        # Do not hide or reposition the panel for a one-frame native-enumeration
        # miss. This is the visible flash captured in the user recording.
        if (Test-NativeTrackingGrace) { return }
        Clear-NativeTrackingTarget
        Hide-PanelWindow
        Hide-QuotaLightstickWindow
        return
    }

    $bounds = $script:OverlayState.'electron-avatar-overlay-bounds'
    $openProperty = $script:OverlayState.PSObject.Properties['electron-avatar-overlay-open']
    if (-not $bounds -or ($openProperty -and -not [bool]$openProperty.Value)) {
        Clear-NativeTrackingTarget
        Hide-PanelWindow
        Hide-QuotaLightstickWindow
        return
    }

    $geometry = Get-MascotGeometry $bounds
    $petWindow = Find-PetWindow $bounds
    if ($petWindow) {
        Set-NativeTrackingTarget "exact" $bounds $geometry $petWindow
        [void](Show-PanelAtNativePetWindow $petWindow $bounds $geometry)
        return
    }

    # Some Windows builds expose the overlay with a size that does not match the saved
    # logical bounds. Use the native blank-title window before falling back to the
    # state file, otherwise dragging follows only as fast as that file is persisted.
    $heuristicWindow = Find-PetWindowHeuristic $bounds
    if ($heuristicWindow) {
        Set-NativeTrackingTarget "heuristic-state" $bounds $geometry $heuristicWindow
        [void](Show-PanelAtNativePetWindow $heuristicWindow $bounds $geometry)
        return
    }

    # Saved-state coordinates are intentionally a slow startup fallback. Mixing
    # one saved-state frame into active native tracking makes the collapsed
    # button visibly jump between Bubu and a screen edge.
    if (Test-NativeTrackingGrace) { return }
    Clear-NativeTrackingTarget
    Show-PanelAtSavedState $bounds $geometry
}

function Update-PetPosition {
    # Kept as a compatibility entry point for click handlers and older repair logic.
    Update-PetTarget
    Follow-PetWindowFast
}

function Test-PointInsidePetRect($point, $rect) {
    return $point -and $rect -and
        [double]$point.X -ge [double]$rect.Left -and
        [double]$point.X -le [double]$rect.Right -and
        [double]$point.Y -ge [double]$rect.Top -and
        [double]$point.Y -le [double]$rect.Bottom
}

function Test-PetDoubleClickGesture(
    $firstPoint,
    $secondPoint,
    [double]$elapsedMilliseconds,
    [double]$maximumMilliseconds,
    $maximumMovement
) {
    if (-not $firstPoint -or -not $secondPoint -or -not $maximumMovement) { return $false }
    return $elapsedMilliseconds -ge 0 -and
        $elapsedMilliseconds -le $maximumMilliseconds -and
        [Math]::Abs([double]$secondPoint.X - [double]$firstPoint.X) -le
            [double]$maximumMovement.Width -and
        [Math]::Abs([double]$secondPoint.Y - [double]$firstPoint.Y) -le
            [double]$maximumMovement.Height
}

function Get-CurrentPetHitRect {
    if ($script:PetWindowHandle -eq [IntPtr]::Zero) { return $null }
    $petWindow = [BubuPanel.NativeWindows]::GetWindow($script:PetWindowHandle)
    if (-not $petWindow) { return $null }

    $visualMetrics = Get-NativePetVisualMetrics $petWindow
    if ($visualMetrics -and $visualMetrics.Width -gt 0 -and $visualMetrics.Height -gt 0) {
        return [PSCustomObject]@{
            Left = [double]($petWindow.Left + $visualMetrics.Left)
            Top = [double]($petWindow.Top + $visualMetrics.Top)
            Right = [double]($petWindow.Left + $visualMetrics.Left + $visualMetrics.Width)
            Bottom = [double]($petWindow.Top + $visualMetrics.Top + $visualMetrics.Height)
        }
    }

    $bounds = $script:TrackingBounds
    $geometry = $script:TrackingGeometry
    if (-not $bounds -or -not $geometry) {
        $bounds = [PSCustomObject]@{ width = 356.0; height = 320.0 }
        $geometry = [PSCustomObject]@{ Left = 165.0; Top = 15.0; Width = 163.0 }
    }
    $anchor = Get-NativePetAnchor $petWindow $bounds $geometry `
        $script:TrackingAlignmentX $script:TrackingAlignmentY
    if (-not $anchor) { return $null }
    $dpi = [BubuPanel.NativeWindows]::GetWindowDpi($petWindow.Handle)
    $petScale = Get-NativePetScale $petWindow $bounds $geometry $dpi
    $dpiScale = [Math]::Max(0.1, $dpi / 96.0)
    $width = $script:CanonicalPetWidth * $petScale * $dpiScale
    $height = $script:CanonicalPetHeight * $petScale * $dpiScale
    return [PSCustomObject]@{
        Left = [double]($anchor.CenterX - $width / 2.0)
        Top = [double]$anchor.Top
        Right = [double]($anchor.CenterX + $width / 2.0)
        Bottom = [double]($anchor.Top + $height)
    }
}

$script:LeftMouseWasDown = $false
$script:LastPetClickAt = [DateTime]::MinValue
$script:LastPetClickPoint = $null
$script:PetDoubleClickMilliseconds = [BubuPanel.NativeWindows]::GetDoubleClickTimeMilliseconds()
$script:PetDoubleClickMovement = [BubuPanel.NativeWindows]::GetDoubleClickSize()

function Update-PetDoubleClickToggle {
    $isDown = [BubuPanel.NativeWindows]::IsLeftMouseButtonDown()
    if (-not $isDown) {
        $script:LeftMouseWasDown = $false
        return
    }
    if ($script:LeftMouseWasDown) { return }
    $script:LeftMouseWasDown = $true

    $point = [BubuPanel.NativeWindows]::GetCursorPosition()
    $petRect = Get-CurrentPetHitRect
    if (-not (Test-PointInsidePetRect $point $petRect)) {
        $script:LastPetClickAt = [DateTime]::MinValue
        $script:LastPetClickPoint = $null
        return
    }

    $now = [DateTime]::UtcNow
    $elapsed = if ($script:LastPetClickAt -eq [DateTime]::MinValue) {
        [double]::PositiveInfinity
    } else {
        ($now - $script:LastPetClickAt).TotalMilliseconds
    }
    if (Test-PetDoubleClickGesture `
        $script:LastPetClickPoint $point $elapsed $script:PetDoubleClickMilliseconds `
        $script:PetDoubleClickMovement) {
        $script:LastPetClickAt = [DateTime]::MinValue
        $script:LastPetClickPoint = $null
        Set-PanelHiddenByUser (-not $script:IsPanelHiddenByUser)
        Write-PanelLog ("INTERACTION pet-double-click hidden=" + $script:IsPanelHiddenByUser)
        return
    }

    $script:LastPetClickAt = $now
    $script:LastPetClickPoint = $point
}

if ($PrintTaskProgress) {
    Update-TaskProgress
    $summary = @($script:LastTaskItems | ForEach-Object {
        ([string]$_.Title) + "[" + ([string]$_.Kind) + "]"
    }) -join " | "
    Write-Output ("task-progress: count=" + $script:LastTaskItems.Count + " " + $summary)
    $script:Window.Close()
    exit 0
}

if ($ValidateTaskProgress) {
    $now = [DateTime]::UtcNow
    $started = '{"type":"event_msg","payload":{"type":"task_started"}}'
    $completed = '{"type":"event_msg","payload":{"type":"task_complete"}}'
    $failed = '{"type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted"}}'
    $request = '{"type":"response_item","payload":{"type":"function_call","name":"request_user_input","call_id":"call-1"}}'
    $response = '{"type":"response_item","payload":{"type":"function_call_output","call_id":"call-1"}}'
    $cases = @(
        [PSCustomObject]@{ Name = "running"; Lines = @($started); Modified = $now; Expected = "running" },
        [PSCustomObject]@{ Name = "waiting"; Lines = @($started, $request); Modified = $now; Expected = "waiting" },
        [PSCustomObject]@{ Name = "resumed"; Lines = @($started, $request, $response); Modified = $now; Expected = "running" },
        [PSCustomObject]@{ Name = "completed"; Lines = @($started, $completed); Modified = $now; Expected = "completed" },
        [PSCustomObject]@{ Name = "failed"; Lines = @($started, $failed); Modified = $now; Expected = "failed" },
        [PSCustomObject]@{ Name = "fresh-fallback"; Lines = @(); Modified = $now; Expected = "running" },
        [PSCustomObject]@{ Name = "idle"; Lines = @(); Modified = $now.AddMinutes(-31); Expected = "idle" }
    )
    foreach ($case in $cases) {
        $actual = Get-TaskProgressKind -lines @($case.Lines) `
            -modificationDate $case.Modified -now $now
        if ($actual -ne $case.Expected) {
            throw "Task progress case $($case.Name) failed: expected=$($case.Expected) actual=$actual"
        }
    }

    $titledUserMessage = '{"type":"event_msg","payload":{"type":"user_message","message":"# Files mentioned by the user:\n/a.png\n## My request for Codex:\n列出具体任务名称"}}'
    $titled = Get-TaskProgressItem -lines @($titledUserMessage, $started) `
        -modificationDate $now -now $now
    if (-not $titled -or $titled.Title -ne "列出具体任务名称") {
        throw "Task title extraction failed."
    }

    $indexedThreadId = '12345678-1234-4abc-8def-1234567890ab'
    $indexedTitles = @{ $indexedThreadId = '正式任务名称' }
    $indexedPath = "C:\Codex\rollout-2026-07-16T16-52-47-$indexedThreadId.jsonl"
    $indexedTitle = Resolve-TaskTitle -path $indexedPath `
        -threadTitles $indexedTitles -fallback 'Codex 任务'
    if ($indexedTitle -ne '正式任务名称') {
        throw "Task index title mapping failed."
    }

    $unreadState = [PSCustomObject]@{
        Ids = @{ $indexedThreadId = $true }
        Available = $true
    }
    $readState = [PSCustomObject]@{
        Ids = @{}
        Available = $true
    }
    $unavailableState = [PSCustomObject]@{
        Ids = @{}
        Available = $false
    }
    $completedVisibilityCases = @(
        (-not (Test-TaskShouldDisplay -kind 'completed' -threadId $indexedThreadId `
            -modificationDate ($now.AddHours(-1)) -now $now -unreadState $unreadState)),
        (-not (Test-TaskShouldDisplay -kind 'completed' -threadId $indexedThreadId `
            -modificationDate $now -now $now -unreadState $readState)),
        (-not (Test-TaskShouldDisplay -kind 'completed' -threadId $indexedThreadId `
            -modificationDate $now -now $now -unreadState $unavailableState)),
        (-not (Test-TaskShouldDisplay -kind 'completed' -threadId $indexedThreadId `
            -modificationDate ($now.AddMinutes(-3)) -now $now -unreadState $unavailableState)),
        (Test-TaskShouldDisplay -kind 'failed' -threadId $indexedThreadId `
            -modificationDate ($now.AddHours(-1)) -now $now -unreadState $unreadState),
        (-not (Test-TaskShouldDisplay -kind 'failed' -threadId $indexedThreadId `
            -modificationDate $now -now $now -unreadState $readState))
    )
    if (@($completedVisibilityCases | Where-Object { -not $_ }).Count -ne 0 -or
        -not (Test-TaskShouldDisplay -kind 'running' -threadId $indexedThreadId `
            -modificationDate $now -now $now -unreadState $readState)) {
        throw "Completed task filtering failed."
    }

    $topLevelMetadata = '{"type":"session_meta","payload":{"thread_source":"user","source":{"cli":{}}}}'
    $subagentMetadata = '{"type":"session_meta","payload":{"thread_source":"subagent","source":{"subagent":{"thread_spawn":{}}}}}'
    $automationMetadata = '{"type":"session_meta","payload":{"thread_source":"automation","source":"vscode"}}'
    $sourceOnlySubagentMetadata = '{"type":"session_meta","payload":{"source":{"subagent":{"thread_spawn":{}}}}}'
    $rolloutVisibilityCases = @(
        (Test-TaskSessionMetadataVisible $topLevelMetadata),
        (-not (Test-TaskSessionMetadataVisible $subagentMetadata)),
        (-not (Test-TaskSessionMetadataVisible $automationMetadata)),
        (-not (Test-TaskSessionMetadataVisible $sourceOnlySubagentMetadata)),
        (Test-TaskSessionMetadataVisible $started)
    )
    if (@($rolloutVisibilityCases | Where-Object { -not $_ }).Count -ne 0) {
        throw "Task non-user session filtering failed."
    }

    $truncatedTasks = @(0..6 | ForEach-Object {
        [PSCustomObject]@{
            Title = "任务 $($_ + 1)"
            Kind = "running"
            Status = "正在执行"
            StartedAt = $now.AddSeconds($_)
        }
    })
    Set-TaskProgressUI $truncatedTasks
    $expectedDynamicHeight = $script:BaseExpandedHeight +
        $script:TaskProgressRowHeight * $script:MaximumVisibleTaskRows
    if ($script:LastTaskItems.Count -ne $script:MaximumVisibleTaskRows -or
        $script:LastTaskItems[-1].Title -ne "任务 5" -or
        $script:ExpandedHeight -ne $expectedDynamicHeight) {
        throw "Dynamic task-list layout failed."
    }

    $completedUiFixture = @(
        [PSCustomObject]@{ Title = "保留的活动任务"; Kind = "running"; Status = "正在执行"; StartedAt = $now },
        [PSCustomObject]@{ Title = "等待确认任务"; Kind = "waiting"; Status = "等你确认"; StartedAt = $now },
        [PSCustomObject]@{ Title = "保留的已完成任务"; Kind = "completed"; Status = "已完成"; StartedAt = $now },
        [PSCustomObject]@{ Title = "失败任务"; Kind = "failed"; Status = "执行失败"; StartedAt = $now }
    )
    Set-TaskProgressUI $completedUiFixture
    if ($script:LastTaskItems.Count -ne 3 -or
        $script:LastTaskItems[0].Title -ne "保留的活动任务" -or
        $script:LastTaskItems[2].Title -ne "失败任务" -or
        $script:RunningArrowTransforms.Count -ne 1) {
        throw "Task status icon UI rendering failed."
    }

    Write-Output "task-progress-validation: lifecycle=7/7; title=1/1; index=1/1; completed-hidden=pass; read-state=6/6; top-level-filter=5/5; list=5-truncated; status-icons=3/3"
    $script:Window.Close()
    exit 0
}

if ($ValidateTrackingFilters) {
    $script:IsCollapsed = $false
    $layoutScaleSamples = 0
    foreach ($layoutScale in @(0.5, 2.0)) {
        [void](Set-PanelScale $layoutScale)
        $expectedWidth = $script:ExpandedWidth * $layoutScale
        $expectedHeight = $script:ExpandedHeight * $layoutScale
        # WPF rounds a half-DIP outer window dimension to the nearest physical
        # pixel (139 * 0.5 becomes 70). The inner LayoutTransform must remain
        # exact; only the native window edge gets a half-pixel tolerance.
        if ([Math]::Abs($script:Window.Width - $expectedWidth) -gt 0.51 -or
            [Math]::Abs($script:Window.Height - $expectedHeight) -gt 0.51 -or
            [Math]::Abs($script:PanelScaleRoot.LayoutTransform.ScaleX - $layoutScale) -gt 0.001 -or
            [Math]::Abs($script:PanelScaleRoot.LayoutTransform.ScaleY - $layoutScale) -gt 0.001) {
            throw ("WPF proportional layout scaling failed at scale=$layoutScale " +
                "window=$($script:Window.Width)x$($script:Window.Height) " +
                "expected=${expectedWidth}x${expectedHeight} " +
                "transform=$($script:PanelScaleRoot.LayoutTransform.ScaleX)x" +
                "$($script:PanelScaleRoot.LayoutTransform.ScaleY).")
        }
        $layoutScaleSamples++
    }
    [void](Set-PanelScale 1.0)

    $testBounds = [PSCustomObject]@{ width = 356; height = 320; x = 400; y = 240 }
    $petWindow = [PSCustomObject]@{
        Handle = [IntPtr]::Zero; Title = ""; ClassName = "Chrome_WidgetWin_1"
        Width = 356; Height = 320; Left = 400; Top = 240
    }
    $imeWindow = [PSCustomObject]@{
        Handle = [IntPtr]::Zero; Title = ""; ClassName = "Chrome_WidgetWin_1"
        Width = 520; Height = 142; Left = 400; Top = 560
    }
    $imeClassWindow = [PSCustomObject]@{
        Handle = [IntPtr]::Zero; Title = ""; ClassName = "MSCTFIME UI"
        Width = 356; Height = 320; Left = 400; Top = 240
    }
    $petAccepted = (Test-PetWindowSize $petWindow $testBounds) -and
        (Test-HeuristicPetWindow $petWindow)
    $imeRejected = -not (Test-PetWindowSize $imeWindow $testBounds) -and
        -not (Test-HeuristicPetWindow $imeWindow)
    $imeClassRejected = -not (Test-PetWindowSize $imeClassWindow $testBounds) -and
        -not (Test-HeuristicPetWindow $imeClassWindow)
    $noActivateApplied = [BubuPanel.NativeWindows]::HasNoActivateStyle($script:WindowHandle)
    $physicalWindowBounds = [BubuPanel.NativeWindows]::HasPhysicalWindowBounds(
        $script:WindowHandle)
    $placementSamples = 0
    $scaleSamples = 0
    $visualScaleSamples = 0
    $captureCoordinateSamples = 0
    $geometry = [PSCustomObject]@{ Left = 165.0; Top = 15.0; Width = 163.0 }
    foreach ($dpi in @(96.0, 120.0, 144.0, 192.0, 288.0)) {
        foreach ($petScale in @(0.5, 1.0, 1.75, 2.5)) {
            $combinedScale = ($dpi / 96.0) * $petScale
            $syntheticPet = [PSCustomObject]@{
                Left = -640; Top = 26
                Width = [int][Math]::Round(356.0 * $combinedScale)
                Height = [int][Math]::Round(320.0 * $combinedScale)
            }
            $syntheticPanel = [PSCustomObject]@{
                Width = [int][Math]::Round(224.0 * $dpi / 96.0 * $petScale)
                Height = [int][Math]::Round($script:ExpandedHeight * $dpi / 96.0 * $petScale)
            }
            $syntheticWorkArea = [PSCustomObject]@{
                Left = -1920; Top = 0; Right = 1920; Bottom = 2160
            }
            $derivedScale = Get-NativePetScale $syntheticPet $testBounds $geometry $dpi
            if ([Math]::Abs($derivedScale - $petScale) -gt 0.01) {
                throw "Panel scale derivation failed at dpi=$dpi petScale=$petScale derived=$derivedScale."
            }
            $scaleSamples++
            $placement = Get-NativePanelPlacement $syntheticPet $testBounds $geometry `
                $syntheticPanel $dpi $petScale $syntheticWorkArea
            $expectedGap = 14.0 * $dpi / 96.0
            if (-not $placement -or
                [Math]::Abs($placement.ActualGapPixels - $expectedGap) -gt 0.51 -or
                [Math]::Abs($placement.CenterErrorPixels) -gt 0.01) {
                throw "Placement matrix failed at dpi=$dpi petScale=$petScale."
            }
            $placementSamples++
        }
    }
    # Reproduce Codex keeping the 356x320 transparent overlay while rendering
    # a much smaller or larger Bubu inside it. The measured visible pixels must
    # override the stale 1.0 anchor scale on every DPI.
    foreach ($dpi in @(96.0, 144.0)) {
        foreach ($visibleScale in @(0.4, 0.7, 1.5, 2.0)) {
            $dpiScale = $dpi / 96.0
            $visualMetrics = [PSCustomObject]@{
                Left = 120.0
                Top = 40.0
                Width = 161.0 * $script:CanonicalPetWidth /
                    $script:PetAtlasFrameWidth * $visibleScale * $dpiScale
                Height = 198.0 * $script:CanonicalPetHeight /
                    $script:PetAtlasFrameHeight * $visibleScale * $dpiScale
            }
            $syntheticPet = [PSCustomObject]@{
                Left = 400; Top = 240
                Width = [int][Math]::Round(356.0 * $dpiScale)
                Height = [int][Math]::Round(320.0 * $dpiScale)
            }
            $derivedScale = Get-NativePetScale `
                $syntheticPet $testBounds $geometry $dpi $visualMetrics
            # Pixel rounding and the atlas-frame lookup can differ by a little
            # over one percent at 2x; this is still well below a visible scale step.
            if ([Math]::Abs($derivedScale - $visibleScale) -gt 0.02) {
                throw "Visible-pixel scale derivation failed at dpi=$dpi visibleScale=$visibleScale derived=$derivedScale."
            }
            $visualScaleSamples++
        }
    }
    $nearFrameVariation = [PSCustomObject]@{
        Left = 120.0; Top = 40.0
        Width = 161.0 * $script:CanonicalPetWidth /
            $script:PetAtlasFrameWidth * 0.94
        Height = 198.0 * $script:CanonicalPetHeight /
            $script:PetAtlasFrameHeight * 0.94
    }
    $nearFrameScale = Get-NativePetScale `
        $petWindow $testBounds $geometry 96.0 $nearFrameVariation
    if ([Math]::Abs($nearFrameScale - 1.0) -gt 0.01) {
        throw "Ordinary animation-frame height variation changed the panel scale."
    }
    $visualScaleSamples++
    foreach ($shortPoseScale in @(1.0, 0.4)) {
        $shortPose = [PSCustomObject]@{
            Left = 120.0; Top = 40.0
            Width = 119.0 * $script:CanonicalPetWidth /
                $script:PetAtlasFrameWidth * $shortPoseScale
            Height = 152.0 * $script:CanonicalPetHeight /
                $script:PetAtlasFrameHeight * $shortPoseScale
        }
        $derivedShortPoseScale = Get-NativePetScale `
            $petWindow $testBounds $geometry 96.0 $shortPose
        if ([Math]::Abs($derivedShortPoseScale - $shortPoseScale) -gt 0.01) {
            throw "Short animation pose was mistaken for a pet resize at scale=$shortPoseScale."
        }
        $visualScaleSamples++
    }
    # PrintWindow is inconsistent across Electron and Windows DPI combinations:
    # some systems capture physical pixels, while others paint 96-DPI logical
    # pixels into the physical bitmap. Both forms must normalize to the same
    # Bubu size before the panel follows it.
    foreach ($dpi in @(144.0, 192.0, 240.0)) {
        $dpiScale = $dpi / 96.0
        $syntheticPet = [PSCustomObject]@{
            Left = 400; Top = 240
            Width = [int][Math]::Round(356.0 * $dpiScale)
            Height = [int][Math]::Round(320.0 * $dpiScale)
        }
        $windowScaleX = [double]$syntheticPet.Width / [double]$testBounds.width
        $windowScaleY = [double]$syntheticPet.Height / [double]$testBounds.height
        $physicalCenterX = ($geometry.Left + $geometry.Width / 2.0) * $windowScaleX
        $physicalTop = $geometry.Top * $windowScaleY
        foreach ($captureMode in @("physical", "logical")) {
            $captureDivisor = if ($captureMode -eq "logical") { $dpiScale } else { 1.0 }
            foreach ($visibleScale in @(0.5, 1.5)) {
                $rawWidth = 161.0 * $script:CanonicalPetWidth /
                    $script:PetAtlasFrameWidth * $visibleScale * $dpiScale / $captureDivisor
                $rawHeight = 198.0 * $script:CanonicalPetHeight /
                    $script:PetAtlasFrameHeight * $visibleScale * $dpiScale / $captureDivisor
                $rawMetrics = [PSCustomObject]@{
                    Left = $physicalCenterX / $captureDivisor - $rawWidth / 2.0
                    Top = $physicalTop / $captureDivisor
                    Width = $rawWidth
                    Height = $rawHeight
                    VisibleFraction = 0.25
                }
                $physicalMetrics = ConvertTo-PhysicalPetVisualMetrics `
                    $syntheticPet $testBounds $geometry $rawMetrics $dpi
                $expectedCoordinateScale = if ($captureMode -eq "logical") { $dpiScale } else { 1.0 }
                if ([Math]::Abs($physicalMetrics.CoordinateScale - $expectedCoordinateScale) -gt 0.01) {
                    throw "Capture coordinate mode failed at dpi=$dpi mode=$captureMode."
                }
                $derivedScale = Get-NativePetScale `
                    $syntheticPet $testBounds $geometry $dpi $physicalMetrics
                if ([Math]::Abs($derivedScale - $visibleScale) -gt 0.02) {
                    throw ("Normalized capture scale failed at dpi=$dpi mode=$captureMode " +
                        "visibleScale=$visibleScale derived=$derivedScale.")
                }
                $captureCoordinateSamples++
            }
        }
    }

    # A single incomplete Chromium frame must not resize the whole panel. Only
    # commit a materially different size after three matching observations.
    [void](Set-PanelScale 1.0)
    Reset-PanelScaleStabilizer
    $stabilityHandle = [IntPtr]101
    foreach ($sampleNumber in 1..3) {
        $stabilizedScale = Get-StabilizedPanelScale 0.4 $stabilityHandle
        $expectedScale = if ($sampleNumber -lt 3) { 1.0 } else { 0.4 }
        if ([Math]::Abs($stabilizedScale - $expectedScale) -gt 0.01) {
            throw "Panel scale stabilizer committed on sample $sampleNumber."
        }
        [void](Set-PanelScale $stabilizedScale)
    }
    [void](Set-PanelScale 1.0)
    Reset-PanelScaleStabilizer
    $singleSmallFrame = Get-StabilizedPanelScale 0.4 $stabilityHandle
    $singleLargeFrame = Get-StabilizedPanelScale 1.7 $stabilityHandle
    $differentWindowFrame = Get-StabilizedPanelScale 0.4 ([IntPtr]202)
    if ([Math]::Abs($singleSmallFrame - 1.0) -gt 0.01 -or
        [Math]::Abs($singleLargeFrame - 1.0) -gt 0.01 -or
        [Math]::Abs($differentWindowFrame - 1.0) -gt 0.01) {
        throw "Panel scale stabilizer accepted a transient or cross-window sample."
    }
    Reset-PanelScaleStabilizer
    # Reproduce the affected Windows layout: a same-size auxiliary Chrome
    # window sits 90 physical pixels left of the real overlay. The selector must
    # prefer the state-aligned window, while center calibration must also keep a
    # synchronized auxiliary window usable during a low-latency drag.
    $stateBounds = [PSCustomObject]@{
        width = 356; height = 320; x = 400; y = 240
        displayBounds = [PSCustomObject]@{ x = 0; y = 0; width = 1920; height = 1080 }
    }
    $monitorBounds = [PSCustomObject]@{ Left = 0; Top = 0; Right = 1920; Bottom = 1080; Width = 1920; Height = 1080 }
    $correctCandidate = [PSCustomObject]@{
        Handle = [IntPtr]::Zero; Title = ""; ClassName = "Chrome_WidgetWin_1"
        Width = 356; Height = 320; Left = 400; Top = 240
    }
    $offsetCandidate = [PSCustomObject]@{
        Handle = [IntPtr]::Zero; Title = ""; ClassName = "Chrome_WidgetWin_1"
        Width = 356; Height = 320; Left = 310; Top = 240
    }
    $correctScore = Get-PetWindowCandidateScore $correctCandidate $stateBounds $monitorBounds
    $offsetScore = Get-PetWindowCandidateScore $offsetCandidate $stateBounds $monitorBounds
    if ($correctScore -ge $offsetScore) {
        throw "State-aware pet-window selection did not prefer the centered overlay."
    }

    $alignment = Get-NativeStateAlignment $offsetCandidate $stateBounds $geometry $monitorBounds
    if (-not $alignment.Valid -or [Math]::Abs($alignment.X - 90.0) -gt 0.01 -or
        [Math]::Abs($alignment.Y) -gt 0.01) {
        throw "Native pet-center calibration failed for the 90px Windows offset regression."
    }
    $regressionPanel = [PSCustomObject]@{ Width = 224; Height = $script:ExpandedHeight }
    $regressionPlacement = Get-NativePanelPlacement $offsetCandidate $stateBounds $geometry `
        $regressionPanel 96.0 1.0 $monitorBounds $alignment.X $alignment.Y
    $expectedCenter = 400.0 + $geometry.Left + $geometry.Width / 2.0
    $actualCenter = $regressionPlacement.Left + $regressionPlacement.PointerCenterPhysical
    if ([Math]::Abs($actualCenter - $expectedCenter) -gt 0.01) {
        throw "Panel was not centered above the visible pet after calibration."
    }

    $draggedOffsetCandidate = [PSCustomObject]@{
        Handle = [IntPtr]::Zero; Title = ""; ClassName = "Chrome_WidgetWin_1"
        Width = 356; Height = 320; Left = 370; Top = 240
    }
    $dragPlacement = Get-NativePanelPlacement $draggedOffsetCandidate $stateBounds $geometry `
        $regressionPanel 96.0 1.0 $monitorBounds $alignment.X $alignment.Y
    $draggedCenter = $dragPlacement.Left + $dragPlacement.PointerCenterPhysical
    if ([Math]::Abs($draggedCenter - ($expectedCenter + 60.0)) -gt 0.01) {
        throw "Calibrated panel did not preserve center while the pet window moved."
    }
    $calibratedAnchor = Get-NativePetAnchor $offsetCandidate $stateBounds $geometry `
        $alignment.X $alignment.Y
    if (-not $calibratedAnchor -or
        [Math]::Abs($calibratedAnchor.CenterX - $expectedCenter) -gt 0.01) {
        throw "Calibrated pet anchor did not preserve Bubu's visible center."
    }
    $pointWorkArea = [BubuPanel.NativeWindows]::GetMonitorWorkAreaAtPoint(0, 0)
    $pointMonitorBounds = [BubuPanel.NativeWindows]::GetMonitorBoundsAtPoint(0, 0)
    if (-not $pointWorkArea -or $pointWorkArea.Width -le 0 -or $pointWorkArea.Height -le 0 -or
        -not $pointMonitorBounds -or $pointMonitorBounds.Width -le 0 -or $pointMonitorBounds.Height -le 0) {
        throw "Anchor-point monitor lookup failed."
    }
    $graceNow = [DateTime]::UtcNow
    $singleFrameMissHeld = Test-NativeFallbackGraceAt $graceNow $graceNow.AddMilliseconds(-100) 750
    $sustainedMissReleased = Test-NativeFallbackGraceAt $graceNow $graceNow.AddMilliseconds(-900) 750
    if (-not $singleFrameMissHeld -or $sustainedMissReleased) {
        throw "Native fallback grace did not suppress only transient tracking misses."
    }
    $petHitRect = [PSCustomObject]@{ Left = 100; Top = 200; Right = 263; Bottom = 377 }
    $firstPetClick = [Drawing.Point]::new(180, 280)
    $secondPetClick = [Drawing.Point]::new(182, 282)
    $outsidePetClick = [Drawing.Point]::new(264, 280)
    $doubleClickMovement = [Drawing.Size]::new(4, 4)
    $doubleClickValid = (Test-PointInsidePetRect $firstPetClick $petHitRect) -and
        (Test-PointInsidePetRect $secondPetClick $petHitRect) -and
        -not (Test-PointInsidePetRect $outsidePetClick $petHitRect) -and
        (Test-PetDoubleClickGesture $firstPetClick $secondPetClick 300 500 $doubleClickMovement) -and
        -not (Test-PetDoubleClickGesture $firstPetClick $secondPetClick 501 500 $doubleClickMovement)
    if (-not $petAccepted -or -not $imeRejected -or -not $imeClassRejected -or
        -not $noActivateApplied -or -not $physicalWindowBounds -or
        -not $doubleClickValid) {
        throw "Pet-window tracking filters failed validation."
    }
    Write-Output ("tracking-filter-validation: pet=True ime-size=True ime-class=True " +
        "no-activate=True physical-window-bounds=True placement-matrix=" + $placementSamples +
        " scale-matrix=" + $scaleSamples +
        " visual-scale-matrix=" + $visualScaleSamples +
        " capture-coordinate-matrix=" + $captureCoordinateSamples +
        " layout-scale-matrix=" + $layoutScaleSamples +
        " state-aware-selection=True center-calibration=True drag-center=True" +
        " anchor-monitor=True flicker-grace=True scale-stability=True pet-double-click=True")
    $script:Window.Close()
    exit 0
}

$script:IsCollapsed = $false
$script:IsPanelHiddenByUser = $false
function Set-Collapsed([bool]$collapsed) {
    $script:IsCollapsed = $collapsed
    $script:LastPointerCenter = [double]::NaN
    if ($collapsed) {
        $script:ExpandedRoot.Visibility = [Windows.Visibility]::Collapsed
        $script:CollapsedRoot.Visibility = [Windows.Visibility]::Visible
    } else {
        $script:CollapsedRoot.Visibility = [Windows.Visibility]::Collapsed
        $script:ExpandedRoot.Visibility = [Windows.Visibility]::Visible
    }
    [void](Set-PanelScale $script:PanelScale)
    Update-PetPosition
}

function Set-PanelHiddenByUser([bool]$hidden) {
    $script:IsPanelHiddenByUser = $hidden
    if ($hidden) {
        Hide-PanelWindow
        Write-PanelHealth $true
        return
    }
    Update-PetPosition
    Write-PanelHealth $true
}

function Select-BubuSkinFromPanel([string]$skin) {
    if (Set-BubuSkinSelection $skin) {
        Set-SkinButtonSelection $skin
        Write-PanelHealth $true
        return
    }
    [System.Media.SystemSounds]::Beep.Play()
}

$script:HideButton.Add_Click({ Set-PanelHiddenByUser $true })
$script:ShowButton.Add_Click({ Set-PanelHiddenByUser $false })
$script:Window.Add_Closed({
    $script:LastPositionMode = "closed"
    if ($script:QuotaLightstickWindow -and $script:QuotaLightstickWindow.IsVisible) {
        $script:QuotaLightstickWindow.Close()
    }
    Write-PanelHealth $true
    Write-PanelLog "STOP window closed"
    if ($script:FastFollowHandler) {
        [Windows.Media.CompositionTarget]::remove_Rendering($script:FastFollowHandler)
    }
    if ($script:FollowFallbackTimer) { $script:FollowFallbackTimer.Stop() }
    if ($script:TargetTimer) { $script:TargetTimer.Stop() }
    if ($script:ServiceTimer) { $script:ServiceTimer.Stop() }
    if ($script:TaskIconAnimationTimer) { $script:TaskIconAnimationTimer.Stop() }
    Stop-QuotaProcess
    if ($script:HttpClient) { $script:HttpClient.Dispose() }
    if ($script:instanceMutex) {
        try { $script:instanceMutex.ReleaseMutex() } catch { }
        $script:instanceMutex.Dispose()
    }
})

# Native movement runs at the desktop compositor's frame rate and at render priority.
# Disk JSON parsing, process scans, network polling and log writes stay on separate
# background-priority timers so they cannot make the panel trail during a drag.
$script:FastFollowHandler = [EventHandler]{
    param($sender, $eventArgs)
    $script:LastCompositionFollowAt = [DateTime]::UtcNow
    Update-PetDoubleClickToggle
    Follow-PetWindowFast
}
$script:LastCompositionFollowAt = [DateTime]::MinValue
[Windows.Media.CompositionTarget]::add_Rendering($script:FastFollowHandler)

# CompositionTarget is the lowest-latency path when desktop composition is
# active. A 33 ms dispatcher fallback keeps tracking alive on software-rendered,
# remote-desktop, battery-saver and low-refresh configurations where rendering
# callbacks can be sparse or paused.
$script:FollowFallbackTimer = [Windows.Threading.DispatcherTimer]::new(
    [Windows.Threading.DispatcherPriority]::Input
)
$script:FollowFallbackTimer.Interval = [TimeSpan]::FromMilliseconds(33)
$script:FollowFallbackTimer.Add_Tick({
    if (([DateTime]::UtcNow - $script:LastCompositionFollowAt).TotalMilliseconds -ge 24) {
        Update-PetDoubleClickToggle
        Follow-PetWindowFast
    }
})

$script:NextTargetRefreshAt = [DateTime]::UtcNow
$script:TargetTimer = [Windows.Threading.DispatcherTimer]::new(
    [Windows.Threading.DispatcherPriority]::Input
)
$script:TargetTimer.Interval = [TimeSpan]::FromMilliseconds(50)
$script:TargetTimer.Add_Tick({
    $now = [DateTime]::UtcNow
    if ($now -ge $script:NextTargetRefreshAt) {
        Update-PetTarget
        $nextDelay = if ($script:TrackingMode -eq "none") { 100 } else { 75 }
        $script:NextTargetRefreshAt = $now.AddMilliseconds($nextDelay)
    }
})

$script:ServiceTimer = [Windows.Threading.DispatcherTimer]::new(
    [Windows.Threading.DispatcherPriority]::Background
)
$script:ServiceTimer.Interval = [TimeSpan]::FromMilliseconds(50)
$script:ServiceTimer.Add_Tick({
    $now = [DateTime]::UtcNow
    Poll-QuotaRequest
    $petIsMoving = Test-PetIsMoving
    if (-not $petIsMoving -and $now -ge $script:NextTaskProgressAt) {
        Update-TaskProgress
        $script:NextTaskProgressAt = $now.AddSeconds(2)
    }
    if (-not $petIsMoving -and -not $script:QuotaProcess -and $now -ge $script:NextQuotaAt) {
        Start-QuotaRequest
    }

    if ($script:MarketPricesEnabled) {
        Poll-BTCRequest
        if (-not $petIsMoving -and -not $script:BTCTask -and $now -ge $script:NextBTCAt) {
            Start-BTCRequest
        }

    }

    if (-not $petIsMoving) { Write-PanelHealth $false }
})

$script:TargetTimer.Start()
$script:FollowFallbackTimer.Start()
$script:ServiceTimer.Start()
Write-PanelHealth $true
Update-PetTarget
Follow-PetWindowFast

$application = [Windows.Application]::Current
if (-not $application) {
    $application = New-Object Windows.Application
}
[void]$application.Run($script:Window)
