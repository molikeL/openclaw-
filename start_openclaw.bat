@echo off
chcp 65001 >nul 2>&1
setlocal EnableDelayedExpansion

title OpenClaw 中文版 — 启动器

echo.
echo  ╔══════════════════════════════════════════════════════════╗
echo  ║          OpenClaw 中文版 — 一键启动器                   ║
echo  ╚══════════════════════════════════════════════════════════╝
echo.

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%start_openclaw.ps1"

if not exist "%PS_SCRIPT%" (
    echo  [错误] 找不到 start_openclaw.ps1
    echo  请确保所有文件在同一目录中
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"

set "EXIT_CODE=%errorlevel%"
if %EXIT_CODE% neq 0 (
    echo.
    echo  [错误] 启动器异常退出，退出码: %EXIT_CODE%
    echo  请查看 logs\ 目录中的日志文件
    pause
)

endlocal
exit /b %EXIT_CODE%
