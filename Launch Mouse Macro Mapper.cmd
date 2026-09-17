@echo off
setlocal
set "AHK=%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe"
if not exist "%AHK%" set "AHK=%ProgramFiles%\AutoHotkey\v2\AutoHotkey.exe"
if not exist "%AHK%" (
  echo AutoHotkey v2 is required. Install it from https://www.autohotkey.com/
  pause
  exit /b 1
)
start "" "%AHK%" "%~dp0MouseMacroMapper.ahk"
