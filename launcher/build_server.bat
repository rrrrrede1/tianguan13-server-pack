@echo off
title TianGuan13 Rebuild
setlocal
set "ROOT=%~dp0"
set "DM=%ROOT%byond\bin\dm.exe"

if not exist "%DM%" (
  echo ERROR: dm.exe not found at:
  echo   %DM%
  pause
  exit /b 1
)

echo ============================================================
echo   Rebuild tgstation.dmb / tgstation.rsc
echo   IMPORTANT: stop the server FIRST ^(close its window^),
echo   otherwise the compile fails on locked .rsc/.dmb files.
echo   NOTE: -DCBT must come BEFORE tgstation.dme.
echo ============================================================
echo.

choice /C YN /M "Server stopped - rebuild now (Y/N)"
if errorlevel 2 exit /b 1

cd /d "%ROOT%"
"%DM%" -DCBT tgstation.dme

echo.
echo Build finished. You should see "0 errors" above.
echo If you see "Building with Dream Maker is no longer supported"
echo then -DCBT did not take effect - report that instead.
pause
