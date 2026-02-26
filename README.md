# VibeCoding — Windows distraction launcher (PowerShell)

Based on [unoptimal/claude-brainrot](https://github.com/unoptimal/claude-brainrot). Opens **TikTok** and **Instagram Reels** in two Chrome windows (half screen each) whenever Claude Code generates a response. **Windows only (PowerShell).**

## What it does

- **When you submit a prompt**: Opens 2 Chrome windows side-by-side (half screen each), loading TikTok and Instagram Reels.
- **When Claude stops responding**: Closes only those Chrome windows (your other Chrome windows are left alone).

## Prerequisites

- **Windows**
- **Google Chrome**
- **PowerShell** (built-in on Windows)
- **Claude Code**

## Setup (Claude Code hooks)

The open/close behavior is driven by **Claude Code hooks** configured at the user level, so it applies to every project by default.

1. Open or create `%USERPROFILE%\.claude\settings.json` (e.g. `C:\Users\YourName\.claude\settings.json`).
2. Add the following hooks, updating the paths to match where you cloned this folder:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:\\path\\to\\cursor scripts\\open-vibecoding.ps1\""
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:\\path\\to\\cursor scripts\\close-vibecoding.ps1\""
          }
        ]
      }
    ]
  }
}
```

## Disable per-project

Add the following to the project's `.claude/settings.json` to prevent the windows from opening in that project:

```json
{
  "vibecoding": {
    "disabled": true
  }
}
```

## Manual run

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\open-vibecoding.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File ".\close-vibecoding.ps1"
```

## Customization

Edit the `$urls` array in `open-vibecoding.ps1` to change which sites open:

```powershell
$urls = @(
    "https://www.instagram.com/reels/",
    "https://www.tiktok.com/"
)
```

Keep the array at 2 entries for the side-by-side half-screen layout.

## Uninstall

Remove the `hooks` entries from `%USERPROFILE%\.claude\settings.json`.

## Files

| File | Purpose |
|------|---------|
| `open-vibecoding.ps1` | Opens 2 Chrome windows side-by-side (Instagram Reels + TikTok). |
| `close-vibecoding.ps1` | Closes only the vibecoding Chrome windows. |
| `.claude/settings.json` | Project-level settings (e.g. per-project disable flag). |
