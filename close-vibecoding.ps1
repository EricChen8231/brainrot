# Close only the VibeCoding Chrome windows we opened
$stateFile = "$Env:USERPROFILE\.cursor-vibecoding\handles.txt"

if (-not (Test-Path $stateFile)) { exit 0 }

$handles = @(Get-Content $stateFile | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [long]$_ })
if ($handles.Count -eq 0) { exit 0 }

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public class VibeCodingCloser {
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr w, IntPtr l);

    // WM_CLOSE to a specific window handle — only closes that window,
    // not the whole Chrome process, so the user's other tabs are unaffected.
    public static void CloseWindow(long handle) {
        var hWnd = new IntPtr(handle);
        if (IsWindow(hWnd)) PostMessage(hWnd, 0x0010, IntPtr.Zero, IntPtr.Zero);
    }
}
'@

# Send WM_CLOSE to each window
foreach ($h in $handles) {
    [VibeCodingCloser]::CloseWindow($h)
}

# Wait up to 4 seconds for Chrome to actually close the windows.
# This prevents the next UserPromptSubmit from launching new windows
# before the old ones have disappeared from the screen.
$deadline = (Get-Date).AddSeconds(4)
while ((Get-Date) -lt $deadline) {
    $anyOpen = $false
    foreach ($h in $handles) {
        if ([VibeCodingCloser]::IsWindow([IntPtr]::new($h))) { $anyOpen = $true; break }
    }
    if (-not $anyOpen) { break }
    Start-Sleep -Milliseconds 200
}

Remove-Item $stateFile -Force -ErrorAction SilentlyContinue
