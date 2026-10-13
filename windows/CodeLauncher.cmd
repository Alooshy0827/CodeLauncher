@echo off
rem ============================================================
rem  CodeLauncher - Windows launcher (double-click to run)
rem  This file is intentionally ASCII-only to avoid codepage issues.
rem ============================================================
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0CodeLauncher.ps1" %*
