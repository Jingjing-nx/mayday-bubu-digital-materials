param(
    [switch]$PrintConfiguration,
    [switch]$ValidateXaml,
    [switch]$ValidateTrackingFilters
)

$ErrorActionPreference = "Stop"

$script:PanelVersion = "1.0.2"
$script:PanelLogPath = Join-Path $PSScriptRoot "panel.log"
$script:CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }
$script:MarketPricesEnabled = $true
$marketSetting = [string]$env:BUBU_SHOW_MARKET_PRICES
if (-not [string]::IsNullOrWhiteSpace($marketSetting)) {
    $script:MarketPricesEnabled = $marketSetting.Trim().ToLowerInvariant() -notmatch '^(0|false|no|off)$'
} elseif (Test-Path -LiteralPath (Join-Path $PSScriptRoot "CODEX-ONLY.txt")) {
    $script:MarketPricesEnabled = $false
}
$script:ExpandedHeight = if ($script:MarketPricesEnabled) { 160 } else { 116 }
$script:ExpandedBodyHeight = $script:ExpandedHeight - 13
$script:ExpandedPointerTipY = $script:ExpandedHeight - 1

if ($PrintConfiguration) {
    Write-Output (
        "panel-config: version=" + $script:PanelVersion +
        " marketPricesEnabled=" + $script:MarketPricesEnabled.ToString().ToLowerInvariant() +
        " width=224 height=" + $script:ExpandedHeight
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
    try {
        [Windows.MessageBox]::Show(
            "卜卜看板启动失败。请运行分享包里的【检查安装环境.cmd】，并发送生成的报告。",
            "卜卜看板",
            [Windows.MessageBoxButton]::OK,
            [Windows.MessageBoxImage]::Warning
        ) | Out-Null
    } catch {
    }
    exit 1
}

Write-PanelLog ("START version=" + $script:PanelVersion + " powershell=" + $PSVersionTable.PSVersion)

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Net.Http

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$createdNew = $false
$script:instanceMutex = [Threading.Mutex]::new($true, "Local\BubuQuotaPanel", [ref]$createdNew)
if (-not $createdNew) {
    exit 0
}

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
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
        private static extern bool SetWindowPos(
            IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int width, int height, uint flags);

        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", ExactSpelling = true)]
        private static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int index);

        [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", ExactSpelling = true)]
        private static extern IntPtr SetWindowLongPtr(IntPtr hWnd, int index, IntPtr newLong);

        [DllImport("user32.dll")]
        private static extern IntPtr MonitorFromWindow(IntPtr hWnd, uint flags);

        [DllImport("user32.dll")]
        private static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);

        private static NativeWindowInfo ReadWindow(IntPtr hWnd) {
            if (hWnd == IntPtr.Zero || !IsWindow(hWnd) || !IsWindowVisible(hWnd)) return null;
            RECT rect;
            if (!GetWindowRect(hWnd, out rect)) return null;
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

        public static uint GetWindowDpi(IntPtr hWnd) {
            try {
                uint dpi = GetDpiForWindow(hWnd);
                return dpi == 0 ? 96u : dpi;
            } catch (EntryPointNotFoundException) {
                return 96u;
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
"@

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
    </Window.Resources>

    <Grid>
        <Canvas x:Name="ExpandedRoot" Width="224" Height="$($script:ExpandedHeight)">
            <Polygon Points="104,$($script:ExpandedBodyHeight) 112,$($script:ExpandedPointerTipY) 120,$($script:ExpandedBodyHeight)"
                     Fill="#F7080B17" Stroke="#38FFFFFF" StrokeThickness="1"/>
            <Border Canvas.Left="3" Canvas.Top="3" Width="218" Height="$($script:ExpandedBodyHeight)"
                    CornerRadius="17" Background="#F7080B17"
                    BorderBrush="#38FFFFFF" BorderThickness="1">
                <Grid ClipToBounds="True">
                    <Rectangle x:Name="BackgroundBand" Height="93" VerticalAlignment="Top"/>
                    <Canvas Width="218" Height="$($script:ExpandedBodyHeight)">
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

                        <Canvas x:Name="MarketRows" Width="218" Height="147">
                        <Border Canvas.Left="14" Canvas.Top="93" Width="190" Height="1"
                                Background="#21FFFFFF"/>
                        <Ellipse Canvas.Left="14" Canvas.Top="100" Width="15" Height="15"
                                 Fill="#F7931A"/>
                        <TextBlock Canvas.Left="14" Canvas.Top="99.5" Width="15" Height="15"
                                   Text="₿" TextAlignment="Center" FontFamily="Segoe UI Symbol"
                                   FontSize="10" FontWeight="Bold" Foreground="White"/>
                        <TextBlock Canvas.Left="34" Canvas.Top="100" Width="62" Height="16"
                                   Text="BTC/USDT" FontFamily="Microsoft YaHei UI"
                                   FontSize="9.6" FontWeight="SemiBold" Foreground="#C8FFFFFF"/>
                        <TextBlock x:Name="BTCPriceText" Canvas.Left="92" Canvas.Top="98.5"
                                   Width="80" Height="18" Text="--" TextAlignment="Right"
                                   FontFamily="Consolas" FontSize="11.4" FontWeight="Bold"
                                   Foreground="#F0FFFFFF"/>
                        <TextBlock x:Name="BTCStatusText" Canvas.Left="176" Canvas.Top="101"
                                   Width="28" Height="14" Text="读取中"
                                   TextAlignment="Right" FontFamily="Microsoft YaHei UI"
                                   FontSize="8.2" Foreground="#8AFFFFFF"/>

                        <Border Canvas.Left="14" Canvas.Top="119" Width="190" Height="1"
                                Background="#21FFFFFF"/>
                        <Ellipse Canvas.Left="14" Canvas.Top="123" Width="15" Height="15"
                                 Fill="#627EEA"/>
                        <TextBlock Canvas.Left="14" Canvas.Top="122.5" Width="15" Height="15"
                                   Text="Ξ" TextAlignment="Center" FontFamily="Segoe UI Symbol"
                                   FontSize="10" FontWeight="Bold" Foreground="White"/>
                        <TextBlock Canvas.Left="34" Canvas.Top="123" Width="62" Height="16"
                                   Text="ETH/USDT" FontFamily="Microsoft YaHei UI"
                                   FontSize="9.6" FontWeight="SemiBold" Foreground="#C8FFFFFF"/>
                        <TextBlock x:Name="ETHPriceText" Canvas.Left="92" Canvas.Top="121.5"
                                   Width="80" Height="18" Text="--" TextAlignment="Right"
                                   FontFamily="Consolas" FontSize="11.4" FontWeight="Bold"
                                   Foreground="#F0FFFFFF"/>
                        <TextBlock x:Name="ETHStatusText" Canvas.Left="176" Canvas.Top="124"
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
            <Polygon Points="24,31 32,43 40,31"
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
            followEngine = "composition-rendering"
            marketPricesEnabled = $script:MarketPricesEnabled
            panelHeightPoints = $script:ExpandedHeight
            lastPetMotionAt = if (-not $script:LastPetMotionAt -or
                $script:LastPetMotionAt -eq [DateTime]::MinValue) { $null } else { $script:LastPetMotionAt.ToString("o") }
            quotaStatus = $script:LastQuotaStatus
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

$script:ExpandedRoot = Get-Control "ExpandedRoot"
$script:CollapsedRoot = Get-Control "CollapsedRoot"
$script:BackgroundBand = Get-Control "BackgroundBand"
$script:RemainingText = Get-Control "RemainingText"
$script:QuotaProgressFill = Get-Control "QuotaProgressFill"
$script:ResetText = Get-Control "ResetText"
$script:QuotaStatusText = Get-Control "QuotaStatusText"
$script:MarketRows = Get-Control "MarketRows"
$script:BTCPriceText = Get-Control "BTCPriceText"
$script:BTCStatusText = Get-Control "BTCStatusText"
$script:ETHPriceText = Get-Control "ETHPriceText"
$script:ETHStatusText = Get-Control "ETHStatusText"
$script:HideButton = Get-Control "HideButton"
$script:ShowButton = Get-Control "ShowButton"

if (-not $script:MarketPricesEnabled) {
    $script:MarketRows.Visibility = [Windows.Visibility]::Collapsed
}

if ($ValidateXaml) {
    Write-Output (
        "xaml-valid: version=" + $script:PanelVersion +
        " marketPricesEnabled=" + $script:MarketPricesEnabled.ToString().ToLowerInvariant() +
        " width=" + [int]($script:Window.Width) +
        " height=" + [int]($script:Window.Height) +
        " marketRows=" + $script:MarketRows.Visibility
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

function New-Brush([string]$hex) {
    return [Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString($hex))
}

$script:BlueBrush = New-Brush "#FF3899"
$script:AmberBrush = New-Brush "#FFB338"
$script:RedBrush = New-Brush "#FF646E"
$script:GreenBrush = New-Brush "#3DDB94"
$script:WhiteBrush = New-Brush "#F0FFFFFF"

function Get-QuotaBrush([int]$remaining) {
    if ($remaining -le 20) { return $script:RedBrush }
    if ($remaining -le 45) { return $script:AmberBrush }
    return $script:BlueBrush
}

function Update-QuotaUI([int]$remaining, [string]$resetText, [string]$statusText) {
    $safeRemaining = [Math]::Max(0, [Math]::Min(100, $remaining))
    $brush = Get-QuotaBrush $safeRemaining
    $script:RemainingText.Text = "剩余 $safeRemaining%"
    $script:RemainingText.Foreground = $brush
    $script:QuotaProgressFill.Background = $brush
    $script:QuotaProgressFill.Width = [Math]::Max(3, 190 * $safeRemaining / 100.0)
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

        $initialize = '{"method":"initialize","id":0,"params":{"clientInfo":{"name":"bubu_windows_panel","title":"Bubu Windows Panel","version":"1.0.2"},"capabilities":{"experimentalApi":true}}}'
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

$script:ETHTask = $null
$script:ETHStartedAt = [DateTime]::MinValue
$script:NextETHAt = [DateTime]::UtcNow
$script:LastETHPrice = $null

function Start-ETHRequest {
    if (-not $script:MarketPricesEnabled) { return }
    if ($script:ETHTask) { return }
    try {
        $url = "https://data-api.binance.vision/api/v3/ticker/price?symbol=ETHUSDT"
        $script:ETHTask = $script:HttpClient.GetStringAsync($url)
        $script:ETHStartedAt = [DateTime]::UtcNow
    } catch {
        $script:ETHTask = $null
        $script:ETHStatusText.Text = "离线"
        $script:NextETHAt = [DateTime]::UtcNow.AddSeconds(5)
    }
}

function Poll-ETHRequest {
    if (-not $script:ETHTask) { return }
    if (-not $script:ETHTask.IsCompleted) { return }

    try {
        $json = $script:ETHTask.GetAwaiter().GetResult() | ConvertFrom-Json
        $price = [double]::Parse([string]$json.price, [Globalization.CultureInfo]::InvariantCulture)
        $direction = 0
        if ($null -ne $script:LastETHPrice) {
            if ($price -gt [double]$script:LastETHPrice) { $direction = 1 }
            if ($price -lt [double]$script:LastETHPrice) { $direction = -1 }
        }
        $script:LastETHPrice = $price
        $script:ETHPriceText.Text = $price.ToString("N2", [Globalization.CultureInfo]::GetCultureInfo("en-US"))
        if ($direction -gt 0) {
            $script:ETHPriceText.Foreground = $script:GreenBrush
        } elseif ($direction -lt 0) {
            $script:ETHPriceText.Foreground = $script:RedBrush
        } else {
            $script:ETHPriceText.Foreground = $script:WhiteBrush
        }
        $script:ETHStatusText.Text = "5秒"
    } catch {
        if ($null -eq $script:LastETHPrice) {
            $script:ETHPriceText.Text = "--"
        }
        $script:ETHStatusText.Text = "离线"
    } finally {
        $script:ETHTask = $null
        $script:NextETHAt = [DateTime]::UtcNow.AddSeconds(5)
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
    $stateDelay = if ($script:TrackingMode -eq "none") { 250 } else { 2000 }
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
$script:LastPetMotionAt = [DateTime]::MinValue

function Test-PetWindowSize($candidate, $bounds) {
    if (-not $candidate -or -not $bounds) { return $false }
    $expectedWidth = [double]$bounds.width
    $expectedHeight = [double]$bounds.height
    if ($expectedWidth -le 0 -or $expectedHeight -le 0) { return $false }
    if ($candidate.Width -lt 180 -or $candidate.Width -gt 1600) { return $false }
    if ($candidate.Height -lt 170 -or $candidate.Height -gt 1600) { return $false }
    $windowSignature = ([string]$candidate.Title + " " + [string]$candidate.ClassName)
    if ($windowSignature -match '(?i)IME|Candidate|InputMethod|TextInput|Cicero|MSCTF') { return $false }
    $expectedRatio = $expectedWidth / $expectedHeight
    $candidateRatio = $candidate.Width / [double]$candidate.Height
    $relativeRatio = $candidateRatio / $expectedRatio
    if ($relativeRatio -lt 0.72 -or $relativeRatio -gt 1.38) { return $false }
    $scaleX = $candidate.Width / $expectedWidth
    $scaleY = $candidate.Height / $expectedHeight
    if ($scaleX -lt 0.25 -or $scaleX -gt 6.0 -or $scaleY -lt 0.25 -or $scaleY -gt 6.0) { return $false }
    if ([Math]::Abs($scaleX - $scaleY) -gt 0.35) { return $false }
    return $true
}

function Test-HeuristicPetWindow($candidate) {
    if (-not $candidate) { return $false }
    if (-not [string]::IsNullOrWhiteSpace($candidate.Title)) { return $false }
    if ($candidate.Width -lt 180 -or $candidate.Width -gt 1600 -or
        $candidate.Height -lt 170 -or $candidate.Height -gt 1600) { return $false }
    $windowSignature = ([string]$candidate.Title + " " + [string]$candidate.ClassName)
    if ($windowSignature -match '(?i)IME|Candidate|InputMethod|TextInput|Cicero|MSCTF') { return $false }

    $dpiScale = [BubuPanel.NativeWindows]::GetWindowDpi($candidate.Handle) / 96.0
    $expectedWidth = 356.0 * $dpiScale
    $expectedHeight = 320.0 * $dpiScale
    $scaleX = $candidate.Width / $expectedWidth
    $scaleY = $candidate.Height / $expectedHeight
    $candidateRatio = $candidate.Width / [double]$candidate.Height
    if ($candidateRatio -lt 0.80 -or $candidateRatio -gt 1.55) { return $false }
    if ($scaleX -lt 0.55 -or $scaleX -gt 3.5 -or $scaleY -lt 0.55 -or $scaleY -gt 3.5) { return $false }
    if ([Math]::Abs($scaleX - $scaleY) -gt 0.35) { return $false }
    return $true
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

    $expectedWidth = [double]$bounds.width
    $expectedHeight = [double]$bounds.height
    $expectedX = [double]$bounds.x
    $expectedY = [double]$bounds.y
    $expectedRatio = $expectedWidth / $expectedHeight
    $best = $null
    $bestScore = [double]::MaxValue

    foreach ($candidate in [BubuPanel.NativeWindows]::GetVisibleWindows()) {
        if (-not $script:ChatProcessIds.ContainsKey([uint32]$candidate.ProcessId)) { continue }
        if (-not (Test-PetWindowSize $candidate $bounds)) { continue }
        $scaleX = $candidate.Width / $expectedWidth
        $scaleY = $candidate.Height / $expectedHeight
        $ratioScore = [Math]::Abs(($candidate.Width / [double]$candidate.Height) - $expectedRatio) * 1200.0
        $scaleScore = [Math]::Abs($scaleX - $scaleY) * 900.0
        $positionScore = [Math]::Abs($candidate.Left - $expectedX) + [Math]::Abs($candidate.Top - $expectedY)
        $titlePenalty = if ([string]::IsNullOrWhiteSpace($candidate.Title)) { 0 } else { 4000 }
        $score = $ratioScore + $scaleScore + $positionScore * 0.035 + $titlePenalty
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

function Find-PetWindowHeuristic {
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

function Set-PositionMode([string]$mode) {
    if ($script:LastPositionMode -ne $mode) {
        $script:LastPositionMode = $mode
        Write-PanelLog ("POSITION mode=" + $mode)
        Write-PanelHealth $true
    }
}

function Get-MascotGeometry($bounds) {
    if ($bounds.mascot) {
        return [PSCustomObject]@{
            Left = [double]$bounds.mascot.left
            Top = [double]$bounds.mascot.top + 7
            Width = [double]$bounds.mascot.width
        }
    }
    if ($bounds.anchor) {
        return [PSCustomObject]@{
            Left = [double]$bounds.anchor.x - [double]$bounds.x
            Top = [double]$bounds.anchor.y - [double]$bounds.y + 7
            Width = [double]$bounds.anchor.width
        }
    }

    $estimatedWidth = [Math]::Min(163.0, [double]$bounds.width * 0.46)
    $estimatedLeft = ([double]$bounds.width - $estimatedWidth) / 2.0
    if ($bounds.placement -match "start$") { $estimatedLeft = 8.0 }
    if ($bounds.placement -match "end$") { $estimatedLeft = [double]$bounds.width - $estimatedWidth - 8.0 }
    return [PSCustomObject]@{
        Left = $estimatedLeft
        Top = 15.0
        Width = $estimatedWidth
    }
}

function Show-PanelAtNativePetWindow($petWindow, $bounds, $geometry) {
    if (-not $script:Window.IsVisible) {
        $script:Window.Show()
        $script:Window.UpdateLayout()
    }

    $panelWindow = [BubuPanel.NativeWindows]::GetWindow($script:WindowHandle)
    if (-not $panelWindow) { return $false }

    $scaleX = $petWindow.Width / [double]$bounds.width
    $scaleY = $petWindow.Height / [double]$bounds.height
    $visualCenterX = $petWindow.Left + ($geometry.Left + $geometry.Width / 2.0) * $scaleX
    $visualTop = $petWindow.Top + $geometry.Top * $scaleY
    $dpi = [BubuPanel.NativeWindows]::GetWindowDpi($petWindow.Handle)
    $gap = [Math]::Round(14.0 * $dpi / 96.0)
    $left = [Math]::Round($visualCenterX - $panelWindow.Width / 2.0)
    $top = [Math]::Round($visualTop - $gap - $panelWindow.Height)

    $workArea = [BubuPanel.NativeWindows]::GetMonitorWorkArea($petWindow.Handle)
    if ($workArea) {
        $left = [Math]::Max($workArea.Left + 8, [Math]::Min($workArea.Right - $panelWindow.Width - 8, $left))
        $top = [Math]::Max($workArea.Top + 8, [Math]::Min($workArea.Bottom - $panelWindow.Height - 8, $top))
    }

    if ([Math]::Abs($panelWindow.Left - $left) -gt 1 -or [Math]::Abs($panelWindow.Top - $top) -gt 1) {
        [void][BubuPanel.NativeWindows]::MoveWindowNoActivate($script:WindowHandle, [int]$left, [int]$top)
    }
    Set-PositionMode "native-dpi"
    return $true
}

function Show-PanelAtHeuristicWindow($petWindow) {
    if (-not $script:Window.IsVisible) {
        $script:Window.Show()
        $script:Window.UpdateLayout()
    }
    $panelWindow = [BubuPanel.NativeWindows]::GetWindow($script:WindowHandle)
    if (-not $panelWindow) { return $false }
    $dpi = [BubuPanel.NativeWindows]::GetWindowDpi($petWindow.Handle)
    $dpiScale = $dpi / 96.0
    $visualCenterX = $petWindow.Left + $petWindow.Width * 0.692
    $visualTop = $petWindow.Top + 15.0 * $dpiScale
    $gap = [Math]::Round(14.0 * $dpiScale)
    $left = [Math]::Round($visualCenterX - $panelWindow.Width / 2.0)
    $top = [Math]::Round($visualTop - $gap - $panelWindow.Height)
    $workArea = [BubuPanel.NativeWindows]::GetMonitorWorkArea($petWindow.Handle)
    if ($workArea) {
        $left = [Math]::Max($workArea.Left + 8, [Math]::Min($workArea.Right - $panelWindow.Width - 8, $left))
        $top = [Math]::Max($workArea.Top + 8, [Math]::Min($workArea.Bottom - $panelWindow.Height - 8, $top))
    }
    [void][BubuPanel.NativeWindows]::MoveWindowNoActivate($script:WindowHandle, [int]$left, [int]$top)
    Set-PositionMode "native-heuristic"
    return $true
}

function Show-PanelAtSavedState($bounds, $geometry) {
    $visualCenterX = [double]$bounds.x + $geometry.Left + $geometry.Width / 2.0
    $visualTop = [double]$bounds.y + $geometry.Top
    $left = $visualCenterX - $script:Window.Width / 2.0
    $top = $visualTop - 14 - $script:Window.Height

    if ($bounds.displayBounds) {
        $display = $bounds.displayBounds
        $left = [Math]::Max([double]$display.x + 8,
            [Math]::Min([double]$display.x + [double]$display.width - $script:Window.Width - 8, $left))
        $top = [Math]::Max([double]$display.y + 8,
            [Math]::Min([double]$display.y + [double]$display.height - $script:Window.Height - 8, $top))
    }

    $script:Window.Left = [Math]::Round($left)
    $script:Window.Top = [Math]::Round($top)
    if (-not $script:Window.IsVisible) { $script:Window.Show() }
    Set-PositionMode "saved-state-fallback"
}

function Set-NativeTrackingTarget([string]$mode, $bounds, $geometry) {
    $script:TrackingMode = $mode
    $script:TrackingBounds = $bounds
    $script:TrackingGeometry = $geometry
}

function Clear-NativeTrackingTarget {
    $script:TrackingMode = "none"
    $script:TrackingBounds = $null
    $script:TrackingGeometry = $null
}

function Follow-PetWindowFast {
    if ($script:PetWindowHandle -eq [IntPtr]::Zero -or $script:TrackingMode -eq "none") { return }
    $petWindow = [BubuPanel.NativeWindows]::GetWindow($script:PetWindowHandle)
    $targetIsValid = $petWindow -and (
        ($script:TrackingMode -eq "exact" -and $script:TrackingBounds -and
            (Test-PetWindowSize $petWindow $script:TrackingBounds)) -or
        ($script:TrackingMode -eq "heuristic" -and (Test-HeuristicPetWindow $petWindow))
    )
    if (-not $targetIsValid) {
        $script:PetWindowHandle = [IntPtr]::Zero
        Clear-NativeTrackingTarget
        $script:NextStateCheckAt = [DateTime]::MinValue
        $script:NextProcessScanAt = [DateTime]::MinValue
        $script:NextTargetRefreshAt = [DateTime]::UtcNow
        return
    }

    if ($petWindow.Left -ne $script:LastPetLeft -or $petWindow.Top -ne $script:LastPetTop) {
        $script:LastPetLeft = $petWindow.Left
        $script:LastPetTop = $petWindow.Top
        $script:LastPetMotionAt = [DateTime]::UtcNow
    }

    if ($script:TrackingMode -eq "exact" -and $script:TrackingBounds -and $script:TrackingGeometry) {
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
            Set-NativeTrackingTarget "heuristic" $null $null
            [void](Show-PanelAtHeuristicWindow $heuristicWindow)
            return
        }
        Clear-NativeTrackingTarget
        Hide-PanelWindow
        return
    }

    $bounds = $script:OverlayState.'electron-avatar-overlay-bounds'
    $openProperty = $script:OverlayState.PSObject.Properties['electron-avatar-overlay-open']
    if (-not $bounds -or ($openProperty -and -not [bool]$openProperty.Value)) {
        Clear-NativeTrackingTarget
        Hide-PanelWindow
        return
    }

    $geometry = Get-MascotGeometry $bounds
    $petWindow = Find-PetWindow $bounds
    if ($petWindow) {
        Set-NativeTrackingTarget "exact" $bounds $geometry
        [void](Show-PanelAtNativePetWindow $petWindow $bounds $geometry)
        return
    }

    # Some Windows builds expose the overlay with a size that does not match the saved
    # logical bounds. Use the native blank-title window before falling back to the
    # state file, otherwise dragging follows only as fast as that file is persisted.
    $heuristicWindow = Find-PetWindowHeuristic
    if ($heuristicWindow) {
        Set-NativeTrackingTarget "heuristic" $null $null
        [void](Show-PanelAtHeuristicWindow $heuristicWindow)
        return
    }

    Clear-NativeTrackingTarget
    Show-PanelAtSavedState $bounds $geometry
}

function Update-PetPosition {
    # Kept as a compatibility entry point for click handlers and older repair logic.
    Update-PetTarget
    Follow-PetWindowFast
}

if ($ValidateTrackingFilters) {
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
    if (-not $petAccepted -or -not $imeRejected -or -not $imeClassRejected -or
        -not $noActivateApplied) {
        throw "Pet-window tracking filters failed validation."
    }
    Write-Output "tracking-filter-validation: pet=True ime-size=True ime-class=True no-activate=True"
    $script:Window.Close()
    exit 0
}

$script:IsCollapsed = $false
function Set-Collapsed([bool]$collapsed) {
    $script:IsCollapsed = $collapsed
    if ($collapsed) {
        $script:ExpandedRoot.Visibility = [Windows.Visibility]::Collapsed
        $script:CollapsedRoot.Visibility = [Windows.Visibility]::Visible
        $script:Window.Width = 64
        $script:Window.Height = 44
    } else {
        $script:CollapsedRoot.Visibility = [Windows.Visibility]::Collapsed
        $script:ExpandedRoot.Visibility = [Windows.Visibility]::Visible
        $script:Window.Width = 224
        $script:Window.Height = $script:ExpandedHeight
    }
    Update-PetPosition
}

$script:HideButton.Add_Click({ Set-Collapsed $true })
$script:ShowButton.Add_Click({ Set-Collapsed $false })
$script:Window.Add_Closed({
    $script:LastPositionMode = "closed"
    Write-PanelHealth $true
    Write-PanelLog "STOP window closed"
    if ($script:FastFollowHandler) {
        [Windows.Media.CompositionTarget]::remove_Rendering($script:FastFollowHandler)
    }
    if ($script:TargetTimer) { $script:TargetTimer.Stop() }
    if ($script:ServiceTimer) { $script:ServiceTimer.Stop() }
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
    Follow-PetWindowFast
}
[Windows.Media.CompositionTarget]::add_Rendering($script:FastFollowHandler)

$script:NextTargetRefreshAt = [DateTime]::UtcNow
$script:TargetTimer = [Windows.Threading.DispatcherTimer]::new(
    [Windows.Threading.DispatcherPriority]::Background
)
$script:TargetTimer.Interval = [TimeSpan]::FromMilliseconds(100)
$script:TargetTimer.Add_Tick({
    $now = [DateTime]::UtcNow
    if ($now -ge $script:NextTargetRefreshAt) {
        if ($script:TrackingMode -ne "none" -and (Test-PetIsMoving)) {
            $script:NextTargetRefreshAt = $now.AddMilliseconds(150)
            return
        }
        Update-PetTarget
        $nextDelay = if ($script:TrackingMode -eq "none") { 100 } else { 1000 }
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
    if (-not $petIsMoving -and -not $script:QuotaProcess -and $now -ge $script:NextQuotaAt) {
        Start-QuotaRequest
    }

    if ($script:MarketPricesEnabled) {
        Poll-BTCRequest
        if (-not $petIsMoving -and -not $script:BTCTask -and $now -ge $script:NextBTCAt) {
            Start-BTCRequest
        }

        Poll-ETHRequest
        if (-not $petIsMoving -and -not $script:ETHTask -and $now -ge $script:NextETHAt) {
            Start-ETHRequest
        }
    }

    if (-not $petIsMoving) { Write-PanelHealth $false }
})

$script:TargetTimer.Start()
$script:ServiceTimer.Start()
Write-PanelHealth $true
Update-PetTarget
Follow-PetWindowFast

$application = [Windows.Application]::Current
if (-not $application) {
    $application = New-Object Windows.Application
}
[void]$application.Run($script:Window)
