@echo off
chcp 65001 >nul
title TianGuan13 Server
setlocal
set "ROOT=%~dp0"
set "DD=%ROOT%byond\bin\dreamdaemon.exe"
set "DMB=%ROOT%tgstation.dmb"
set "LOGF=%ROOT%data\server.log"
set "PORT=1337"

if not exist "%ROOT%data" mkdir "%ROOT%data"

if not exist "%DD%" (
  echo ERROR: dreamdaemon.exe not found at:
  echo   %DD%
  pause
  exit /b 1
)
if not exist "%DMB%" (
  echo ERROR: tgstation.dmb not found at:
  echo   %DMB%
  pause
  exit /b 1
)

echo ============================================================
echo   TianGuan13 server
echo   This machine : byond://127.0.0.1:%PORT%
echo   LAN players  : byond://YOUR-LAN-IP:%PORT%
echo.
echo   The server runs in its own window (TianGuan13 DreamDaemon).
echo   THIS window shows its live log (data\server.log).
echo   Closing THIS window does NOT stop the server.
echo   To stop the server: close the DreamDaemon window,
echo   or just double-click stop_server.bat (recommended).
echo ============================================================
echo.

if exist "%LOGF%" del "%LOGF%" >nul 2>&1

echo [%date% %time%] starting DreamDaemon on port %PORT% ...
start "TianGuan13 DreamDaemon (close this to stop the server)" "%DD%" "%DMB%" -port %PORT% -trusted -log "%LOGF%" -verbose

echo [%date% %time%] waiting for the world to come up (first boot takes ~2-3 minutes) ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "while(-not (Test-Path '%LOGF%')){Start-Sleep -Milliseconds 500}; Get-Content -LiteralPath '%LOGF%' -Wait -Encoding UTF8"

echo.
echo [%date% %time%] log viewer closed. Server window may still be running.
echo.
pause