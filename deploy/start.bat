@echo off
chcp 65001 >nul 2>&1
title OpenClaw 中文版 启动器

:: ============================================================
:: OpenClaw 中文版 一键启动器
:: 本文件会运行 start.ps1 启动 OpenClaw 服务
:: 双击本文件即可启动
:: ============================================================

echo.
echo ============================================================
echo   OpenClaw 中文版  一键启动器
echo ============================================================
echo.

:: 检测 PowerShell 是否可用
where powershell >nul 2>&1
if %errorlevel% neq 0 (
    echo [错误] 未找到 PowerShell，无法运行启动脚本。
    echo         请确认系统已安装 Windows PowerShell 5.1 或更高版本。
    pause
    exit /b 1
)

echo [信息] 正在启动 OpenClaw，请稍候...
echo.

:: 运行启动脚本（不强制要求管理员权限，普通用户即可启动服务）
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start.ps1" %*

set EXIT_CODE=%errorlevel%

echo.
if %EXIT_CODE% equ 0 (
    echo [信息] OpenClaw 已停止。
) else (
    echo [警告] OpenClaw 异常退出（退出码: %EXIT_CODE%）。
    echo         请查看 logs\ 目录下的日志文件以了解详情。
)

echo.
pause
exit /b %EXIT_CODE%
