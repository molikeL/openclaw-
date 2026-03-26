@echo off
chcp 65001 >nul 2>&1
setlocal EnableDelayedExpansion

title OpenClaw 中文版 一键部署程序

echo.
echo  ╔══════════════════════════════════════════════════════════╗
echo  ║          OpenClaw 中文版一键部署程序  v1.0              ║
echo  ║          适用于 Windows 10/11                           ║
echo  ╚══════════════════════════════════════════════════════════╝
echo.

:: ── 检查管理员权限 ──
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo  [信息] 需要管理员权限，正在提升权限...
    echo.
    :: 用 PowerShell 自提升
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "Start-Process cmd.exe -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

:: ── 确认脚本目录 ──
set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%deploy.ps1"

if not exist "%PS_SCRIPT%" (
    echo  [错误] 找不到 deploy.ps1，请确保所有文件在同一目录中
    echo  路径: %PS_SCRIPT%
    pause
    exit /b 1
)

:: ── 执行 PowerShell 部署脚本 ──
echo  [信息] 正在启动 PowerShell 部署脚本...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"

set "PS_EXIT=%errorlevel%"

if %PS_EXIT% neq 0 (
    echo.
    echo  [错误] 部署脚本退出，错误代码: %PS_EXIT%
    echo  请查看 logs\ 目录中的日志文件以了解详情
)

endlocal
exit /b %PS_EXIT%
