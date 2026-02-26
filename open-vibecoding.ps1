# Cursor VibeCoding - Windows PowerShell
# Opens Instagram Reels + TikTok side-by-side on every prompt submission.
# Skips silently if windows from a previous run are still open.

$globalLockDir  = "$Env:ProgramData\CursorVibeCoding"
$globalLockFile = "$globalLockDir\vibecoding.lock"
$stateDir       = "$Env:USERPROFILE\.cursor-vibecoding"
$stateFile      = "$stateDir\handles.txt"
$lockStream     = $null

if (-not (Test-Path $globalLockDir)) { New-Item -ItemType Directory -Path $globalLockDir -Force | Out-Null }
if (-not (Test-Path $stateDir))      { New-Item -ItemType Directory -Path $stateDir      -Force | Out-Null }

# Load window helper (guarded so re-running in the same PS session never errors)
if (-not ([System.Management.Automation.PSTypeName]'VibeCodingWindowHelper').Type) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public class VibeCodingWindowHelper {
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc e, IntPtr p);
    delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr p);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int GetClassName(IntPtr hWnd, StringBuilder s, int n);
    [DllImport("user32.dll")]
    static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int X, int Y, int w, int h, uint flags);
    [DllImport("user32.dll")]
    static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    const string ChromeClass = "Chrome_WidgetWin_1";

    // Returns handles of all visible top-level Chrome windows.
    public static long[] GetChromeWindows() {
        var list = new List<long>();
        EnumWindows((hWnd, p) => {
            if (!IsWindowVisible(hWnd)) return true;
            var sb = new StringBuilder(256);
            GetClassName(hWnd, sb, 256);
            if (sb.ToString() == ChromeClass) list.Add(hWnd.ToInt64());
            return true;
        }, IntPtr.Zero);
        return list.ToArray();
    }

    // True if the handle still refers to a visible Chrome window.
    public static bool IsValidChromeWindow(long handle) {
        var hWnd = new IntPtr(handle);
        if (!IsWindow(hWnd) || !IsWindowVisible(hWnd)) return false;
        var sb = new StringBuilder(256);
        GetClassName(hWnd, sb, 256);
        return sb.ToString() == ChromeClass;
    }

    // Move + resize a window. Must restore first — SetWindowPos is a no-op on maximized windows.
    public static void MoveWindow(long handle, int x, int y, int w, int h) {
        var hWnd = new IntPtr(handle);
        ShowWindow(hWnd, 9);  // SW_RESTORE — un-maximize before repositioning
        SetWindowPos(hWnd, IntPtr.Zero, x, y, w, h, 0x0044);  // SWP_NOZORDER|SWP_SHOWWINDOW
    }
}
'@
}

# --- Fast path: vibecoding windows are already visible ---
if (Test-Path $stateFile) {
    $stored = @(Get-Content $stateFile | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [long]$_ })
    if ($stored.Count -ge 2) {
        $live = @($stored | Where-Object { [VibeCodingWindowHelper]::IsValidChromeWindow($_) })
        if ($live.Count -ge 2) { exit 0 }
    }
}

# --- Acquire exclusive lock to prevent two concurrent launches ---
try {
    $lockStream = [System.IO.File]::Open(
        $globalLockFile,
        [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )
} catch {
    exit 0   # Another instance is already mid-launch
}

try {
    # Re-check inside lock (closes the race between the fast-path and lock acquire)
    if (Test-Path $stateFile) {
        $stored = @(Get-Content $stateFile | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [long]$_ })
        if ($stored.Count -ge 2) {
            $live = @($stored | Where-Object { [VibeCodingWindowHelper]::IsValidChromeWindow($_) })
            if ($live.Count -ge 2) { exit 0 }
        }
    }

    # Check if disabled via settings
    $settingsPath = ".claude\settings.json"
    if (Test-Path $settingsPath) {
        try {
            $json = Get-Content $settingsPath -Raw | ConvertFrom-Json
            if ($json.vibecoding.disabled -eq $true) { exit 0 }
        } catch {}
    }

    # Locate Chrome
    $chrome = $null
    foreach ($p in @(
        "$Env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "$Env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe"
    )) { if (Test-Path $p) { $chrome = $p; break } }
    if (-not $chrome) {
        $cmd = Get-Command chrome -ErrorAction SilentlyContinue
        if ($cmd) { $chrome = $cmd.Source }
    }
    if (-not $chrome) { exit 1 }

    # Screen dimensions (WorkingArea automatically excludes taskbar)
    Add-Type -AssemblyName System.Windows.Forms
    $screen      = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $screenLeft  = $screen.Left
    $screenTop   = $screen.Top
    $screenWidth = $screen.Width
    $screenHeight = $screen.Height
    $halfWidth   = [math]::Floor($screenWidth / 2)

    # Snapshot Chrome windows that exist BEFORE we launch anything.
    # We detect new windows by comparing handles, not PIDs — this works
    # whether Chrome is already running or not.
    $beforeSet = [System.Collections.Generic.HashSet[long]]::new()
    foreach ($h in [VibeCodingWindowHelper]::GetChromeWindows()) { $beforeSet.Add($h) | Out-Null }

    # Open both URLs in new windows (default profile keeps cached logins)
    $urls = @(
        "https://www.instagram.com/reels/",
        "https://www.tiktok.com/"
    )
    foreach ($url in $urls) {
        Start-Process -FilePath $chrome -ArgumentList @("--new-window", $url)
        Start-Sleep -Milliseconds 600   # slight gap so Chrome registers them separately
    }

    # Poll until exactly 2 new Chrome windows are visible (up to 15 s)
    $newHandles = @()
    $deadline   = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        $all = [VibeCodingWindowHelper]::GetChromeWindows()
        $newHandles = @($all | Where-Object { -not $beforeSet.Contains($_) })
        if ($newHandles.Count -ge 2) { break }
    }

    if ($newHandles.Count -lt 2) { exit 0 }   # Chrome didn't open 2 new windows in time

    # Position them side by side
    [VibeCodingWindowHelper]::MoveWindow($newHandles[0], $screenLeft,              $screenTop, $halfWidth, $screenHeight)
    [VibeCodingWindowHelper]::MoveWindow($newHandles[1], $screenLeft + $halfWidth, $screenTop, $halfWidth, $screenHeight)

    # Persist handles so next invocation can skip and close script knows what to close
    $newHandles[0..1] | Set-Content -Path $stateFile

} finally {
    if ($lockStream) { $lockStream.Close(); $lockStream.Dispose() }
}
