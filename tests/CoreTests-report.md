# Core test report

Run date: 2026-09-14.

Result: **PASS**, 15 groups, **20,656 assertions**, process exit code 0, no warnings.

Runtime: AutoHotkey **2.0.26**, `C:/Program Files/AutoHotkey/v2/AutoHotkey64.exe`.

Command (PowerShell; the pipeline waits for the Windows GUI executable and captures its output):

```powershell
& 'C:/Program Files/AutoHotkey/v2/AutoHotkey64.exe' /ErrorStdOut 'tests/CoreTests.ahk' 2>&1 | ForEach-Object { $_ }
exit $LASTEXITCODE
```

Coverage:

- Exact side masks, captured-input ownership, foreground target checks, stale generations, pause, and inhibition.
- All 90 valid down/up event orders for two side buttons and one primary button, repeated for left/right/middle and both preservation modes.
- Cancellation at every event boundary, retaining the original disposition of each primary-button release.
- Duplicate downs, side overlap, repeated fresh clicks, unassigned passthrough ownership, and release-before-rearm behavior.
- Key aliases, shortcut case normalization, Unicode literal text, delay limits, source limits, step limits, and rejection of raw Send syntax or held inputs.
- All nine mapping slots and both preferences persisted through temporary files, including Unicode names/text, CRLF source, replacement saves, cleared mappings, and temporary-file cleanup.
- Unsupported versions, invalid preferences, invalid hex, invalid macros, malformed UTF-8, and embedded NUL input fail safely without overwriting the original settings file.
- A 12,140-character source containing 12,000 Chinese BMP characters across 20 text lines survives save/reload with all 20 steps. Its encoded value is 72,280 characters; the Windows `IniRead` path returned only 6,744 characters during the regression probe. The manual settings parser preserves the complete value.
- An ASCII source at the exact 16,000-character limit survives save/reload and an unchanged save byte for byte.
- Both Mouse/List views and all nine selected mapping IDs persist; legacy files without navigation fields use Mouse/4L and retain their mappings. BOM, comments, whitespace, and case-insensitive section/key names remain compatible.
- Duplicate keys/sections, malformed lines, invalid view/selection values, excessive line lengths, and files over 4 MiB are rejected while retaining the original settings.
- Exclusively locked temporary output forces a save-open failure; a read lock forbidding deletion forces atomic replacement failure. Both preserve the original file. Saving succeeds after locks are released and leaves no temporary output.

The tests operate only on pure classes and per-run temporary files. They do not install input hooks, send mouse/keyboard input, or validate the real native GUI, target applications, or physical mouse hardware. Native runtime validation is separate.
