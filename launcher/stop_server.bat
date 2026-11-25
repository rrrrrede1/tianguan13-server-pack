@echo off
chcp 65001 >nul
title TianGuan13 停止服务器
setlocal

echo ============================================================
echo   正在停止天关13服务器
echo ============================================================
echo.

echo [1/3] 让 DreamDaemon 正常退出 ...
taskkill /IM dreamdaemon.exe >nul 2>&1
taskkill /IM dd.exe >nul 2>&1
timeout /t 2 >nul

echo [2/3] 还在跑就强制结束 ...
taskkill /IM dreamdaemon.exe /F >nul 2>&1
taskkill /IM dd.exe /F >nul 2>&1
timeout /t 1 >nul

tasklist /FI "IMAGENAME eq dreamdaemon.exe" 2>nul | find /I "dreamdaemon.exe" >nul
if errorlevel 1 (
  echo      服务器进程已结束。
) else (
  echo      警告：dreamdaemon.exe 仍在运行，请手动在任务管理器里结束它。
)

echo.
echo [3/3] 结束 BYOND 托盘后台程序（pager）...
echo      右下角托盘里的 BYOND 图标就是它，不关掉它会一直留在托盘里。
taskkill /IM byond.exe /F >nul 2>&1
echo      完成。
echo.
echo ============================================================
echo   服务器已停止，可以关闭这个窗口了。
echo ============================================================
timeout /t 5 >nul