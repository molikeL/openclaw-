@echo off
chcp 65001 >nul 2>&1
title OpenClaw 中文版 一键部署工具

:: ============================================================
:: OpenClaw 中文版 一键部署工具 - 启动器
:: 本文件会以管理员身份运行 deploy.ps1
:: 双击本文件即可开始部署
:: ============================================================

echo.
echo ============================================================
echo   OpenClaw 中文版  一键部署工具
echo ============================================================
echo.

:: 检测是否已以管理员权限运行
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [提示] 正在请求管理员权限，请在弹出的 UAC 对话框中点击「是」...
    echo.
    :: 使用 PowerShell 以管理员权限重新启动本脚本
    PowerShell -NoProfile -Command ^
        "Start-Process -FilePath 'cmd.exe' -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

echo [信息] 已获得管理员权限。
echo.

:: 检测 PowerShell 是否可用
where powershell >nul 2>&1
if %errorlevel% neq 0 (
    echo [错误] 未找到 PowerShell，无法运行部署脚本。
    echo         请确认系统已安装 Windows PowerShell 5.1 或更高版本。
    pause
    exit /b 1
)

:: 修改 PowerShell 执行策略（仅对当前进程生效）并运行部署脚本
echo [信息] 正在启动部署脚本，请稍候...
echo.
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1" %*

set EXIT_CODE=%errorlevel%

echo.
if %EXIT_CODE% equ 0 (
    echo ============================================================
    echo   部署成功！按任意键关闭此窗口。
    echo ============================================================
) else (
    echo ============================================================
    echo   部署失败（退出码: %EXIT_CODE%）。
    echo   请查看 logs\ 目录下的日志文件以了解详情。
    echo ============================================================
)

echo.
pause
exit /b %EXIT_CODE%
