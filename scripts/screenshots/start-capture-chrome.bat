@echo off
REM Open the Chrome that capture_gcp.py attaches to.
REM
REM Two things make this a separate launcher rather than "just use Chrome":
REM
REM   1. Remote debugging cannot be enabled on an already-running Chrome. If your
REM      normal browser is open, Chrome ignores the flag and silently reuses the
REM      existing process, and the capture script then finds nothing on 9222.
REM      Hence a dedicated user-data-dir, which forces a separate process.
REM
REM   2. That profile persists, so the Google sign-in survives between sessions.
REM      Sign in once; every later capture run attaches to a browser that is
REM      already authenticated. No password ever passes through the scripts.
REM
REM The profile directory is gitignored. It holds live session cookies for the
REM Cloud console and HCP Terraform and must never be committed.
REM
REM Usage:
REM   scripts\screenshots\start-capture-chrome.bat
REM   ...sign in to console.cloud.google.com and app.terraform.io, then leave it open.

setlocal

set "PROFILE=%~dp0..\..\playwright_profile"
set "CHROME=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if not exist "%CHROME%" set "CHROME=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
if not exist "%CHROME%" set "CHROME=%LocalAppData%\Google\Chrome\Application\chrome.exe"

if not exist "%CHROME%" (
  echo Could not find chrome.exe. Set CHROME by hand in this script.
  exit /b 1
)

if not exist "%PROFILE%" mkdir "%PROFILE%"

echo Opening capture Chrome on port 9222.
echo Profile: %PROFILE%
echo.
echo Sign in to the Cloud console and HCP Terraform in this window, then leave
echo it open. Captures attach to it with --cdp 9222.

start "" "%CHROME%" ^
  --remote-debugging-port=9222 ^
  --user-data-dir="%PROFILE%" ^
  --no-first-run ^
  --no-default-browser-check ^
  https://console.cloud.google.com/

endlocal
