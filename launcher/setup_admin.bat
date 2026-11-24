@echo off
title TianGuan13 Add Admin
setlocal
set "ADMINS=%~dp0config\admins.txt"

if not exist "%ADMINS%" (
  echo ERROR: config\admins.txt not found - is the config folder copied?
  pause
  exit /b 1
)

echo ============================================================
echo   Give a player Host admin on this server.
echo   The name is the BYOND account login (lowercase, no spaces).
echo ============================================================
echo.

set "NAME="
set /p "NAME=BYOND account name: "
if "%NAME%"=="" echo No input, aborting. & pause & exit /b 1

echo.>> "%ADMINS%"
echo %NAME% = Host>> "%ADMINS%"

echo.
echo Added: %NAME% = Host
echo Restart the server (or reload admins in-game) to apply.
pause
