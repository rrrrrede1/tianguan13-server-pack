@echo off
title TianGuan13 Server
setlocal
set "ROOT=%~dp0"
set "DD=%ROOT%byond\bin\dreamdaemon.exe"
set "DMB=%ROOT%tgstation.dmb"
set "PORT=1337"

if not exist "%ROOT%data" mkdir "%ROOT%data"

if not exist "%DD%" (
  echo ERROR: dreamdaemon.exe not found at:
  echo   %DD%
  echo Check that the byond folder was copied correctly.
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
echo   Close this window to stop the server.
echo ============================================================
echo.

:start
echo [%date% %time%] starting DreamDaemon on port %PORT% ...
"%DD%" "%DMB%" -port %PORT% -trusted -log "%ROOT%data\server.log" -verbose
echo.
echo [%date% %time%] server exited, code %ERRORLEVEL%.
echo.
choice /C RQ /M "R = restart, Q = quit"
if errorlevel 2 goto end
goto start

:end
pause
