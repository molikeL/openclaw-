# ==============================================================
# OpenClaw 中文版 Windows 一键部署脚本
# 版本: 1.0
# 适用系统: Windows 10 / Windows 11
# 依赖: WSL2 + Ubuntu + Node.js 22+ + npm
# ==============================================================

#Requires -Version 5.1

# ── 初始化路径 ──
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir     = Join-Path $ScriptDir "logs"
$StateFile  = Join-Path $ScriptDir ".deploy_state"
$Timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile    = Join-Path $LogDir "deploy_$Timestamp.log"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# ══════════════════════════════════════════════════════════════
# 日志系统
# ══════════════════════════════════════════════════════════════
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","SUCCESS","WARNING","ERROR","STEP","WSL")]
        [string]$Level = "INFO"
    )
    $ts      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$ts] [$Level] $Message"

    switch ($Level) {
        "INFO"    { Write-Host $logLine -ForegroundColor Cyan    }
        "SUCCESS" { Write-Host $logLine -ForegroundColor Green   }
        "WARNING" { Write-Host $logLine -ForegroundColor Yellow  }
        "ERROR"   { Write-Host $logLine -ForegroundColor Red     }
        "STEP"    { Write-Host $logLine -ForegroundColor White   }
        "WSL"     { Write-Host "  $logLine" -ForegroundColor Gray }
    }
    Add-Content -Path $LogFile -Value $logLine -Encoding UTF8
}

function Write-Separator {
    $line = "=" * 62
    Write-Host $line -ForegroundColor DarkGray
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

# ══════════════════════════════════════════════════════════════
# 状态管理 (用于跨重启断点续传)
# ══════════════════════════════════════════════════════════════
function Get-DeployState  { if (Test-Path $StateFile) { return (Get-Content $StateFile -Raw).Trim() } ; return "1" }
function Set-DeployState  { param([string]$s) ; Set-Content -Path $StateFile -Value $s -Encoding UTF8 }
function Clear-DeployState { if (Test-Path $StateFile) { Remove-Item $StateFile -Force } }

# ══════════════════════════════════════════════════════════════
# 辅助检测函数
# ══════════════════════════════════════════════════════════════
function Test-AdminPrivilege {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-WSLFeaturesEnabled {
    $wsl = Get-WindowsOptionalFeature -Online -FeatureName "Microsoft-Windows-Subsystem-Linux" -ErrorAction SilentlyContinue
    $vmp = Get-WindowsOptionalFeature -Online -FeatureName "VirtualMachinePlatform"            -ErrorAction SilentlyContinue
    return ($wsl.State -eq "Enabled" -and $vmp.State -eq "Enabled")
}

function Test-WslExePresent { return $null -ne (Get-Command "wsl" -ErrorAction SilentlyContinue) }

function Test-UbuntuInstalled {
    if (-not (Test-WslExePresent)) { return $false }
    $list = wsl --list --quiet 2>$null
    return ($list -match "Ubuntu")
}

function Get-NodeMajorVersionInWSL {
    if (-not (Test-UbuntuInstalled)) { return 0 }
    $ver = wsl -d Ubuntu -- bash -lc "node --version 2>/dev/null" 2>$null
    if ($ver -match 'v(\d+)') { return [int]$Matches[1] }
    return 0
}

function Test-OpenClawInstalled {
    if (-not (Test-UbuntuInstalled)) { return $false }
    $path = wsl -d Ubuntu -- bash -lc "which openclaw 2>/dev/null" 2>$null
    return ($path -and $path.Trim() -ne "")
}

# 在 WSL Ubuntu 中运行 bash 脚本并把输出流式写入日志
function Invoke-WSLScript {
    param([string]$ScriptBody, [string]$TmpPath = "/tmp/oc_deploy_step.sh")
    $ScriptBody | wsl -d Ubuntu -- bash -c "cat > '$TmpPath' && chmod +x '$TmpPath'" 2>$null
    $output = wsl -d Ubuntu -- bash -l "$TmpPath" 2>&1
    foreach ($line in $output) { Write-Log $line "WSL" }
    return $LASTEXITCODE
}

# ══════════════════════════════════════════════════════════════
# 定时任务 (断点续传)
# ══════════════════════════════════════════════════════════════
$ResumeTaskName = "OpenClawDeployResume"

function Register-ResumeTask {
    $batPath = Join-Path $ScriptDir "deploy.bat"
    $action  = New-ScheduledTaskAction -Execute $batPath
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $settings= New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 1)
    Register-ScheduledTask -TaskName $ResumeTaskName -Action $action `
        -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null
    Write-Log "已注册重启后自动继续任务: $ResumeTaskName" "INFO"
}

function Remove-ResumeTask {
    if (Get-ScheduledTask -TaskName $ResumeTaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $ResumeTaskName -Confirm:$false | Out-Null
        Write-Log "已移除重启续传任务" "INFO"
    }
}

# ══════════════════════════════════════════════════════════════
# 阶段 1 — 检测 Windows 运行环境
# ══════════════════════════════════════════════════════════════
function Invoke-Stage1 {
    Write-Separator
    Write-Log "【阶段 1/6】检测 Windows 运行环境" "STEP"
    Write-Separator

    # Windows 版本
    $osVer   = [System.Environment]::OSVersion.Version
    $build   = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -EA SilentlyContinue).CurrentBuild
    $edition = (Get-WmiObject Win32_OperatingSystem).Caption
    Write-Log "操作系统: $edition" "INFO"
    Write-Log "版本号: $($osVer.Major).$($osVer.Minor) (Build $build)" "INFO"
    if ($osVer.Major -lt 10) {
        Write-Log "错误: 需要 Windows 10 或更高版本才能使用 WSL2" "ERROR"
        return $false
    }

    # 64 位
    if (-not [System.Environment]::Is64BitOperatingSystem) {
        Write-Log "错误: 需要 64 位操作系统" "ERROR"
        return $false
    }
    Write-Log "系统架构: x64 ✓" "SUCCESS"

    # 磁盘空间
    $drvLetter = (Split-Path -Qualifier $ScriptDir).TrimEnd(':')
    $drv = Get-PSDrive -Name $drvLetter -ErrorAction SilentlyContinue
    if ($drv) {
        $freeGB = [math]::Round($drv.Free / 1GB, 1)
        Write-Log "可用磁盘空间: ${freeGB} GB" "INFO"
        if ($freeGB -lt 10) { Write-Log "警告: 磁盘空间不足 10 GB，部署可能失败" "WARNING" }
    }

    # 内存
    $ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    Write-Log "物理内存: ${ramGB} GB" "INFO"
    if ($ramGB -lt 4) { Write-Log "警告: 内存低于 4 GB，建议至少 4 GB" "WARNING" }

    # 网络
    Write-Log "检测网络连通性..." "INFO"
    $online = Test-Connection -ComputerName "registry.npmjs.org" -Count 1 -Quiet -ErrorAction SilentlyContinue
    if ($online) {
        Write-Log "网络连接正常 ✓" "SUCCESS"
    } else {
        Write-Log "警告: 无法连接到 npm registry，如在国内环境请确保能访问 npmjs.org 或配置镜像" "WARNING"
    }

    # 管理员权限
    if (-not (Test-AdminPrivilege)) {
        Write-Log "错误: 需要管理员权限，请右键 deploy.bat → 以管理员身份运行" "ERROR"
        return $false
    }
    Write-Log "管理员权限: 已确认 ✓" "SUCCESS"

    Write-Log "阶段 1 完成" "SUCCESS"
    return $true
}

# ══════════════════════════════════════════════════════════════
# 阶段 2 — 启用 WSL2
# ══════════════════════════════════════════════════════════════
function Invoke-Stage2 {
    Write-Separator
    Write-Log "【阶段 2/6】检测并启用 WSL2" "STEP"
    Write-Separator

    if (Test-WSLFeaturesEnabled) {
        Write-Log "WSL 功能已启用 ✓" "SUCCESS"
        wsl --set-default-version 2 2>$null | Out-Null
        Write-Log "WSL 默认版本已设为 WSL2" "INFO"
        return $true
    }

    Write-Log "WSL2 功能未启用，开始启用..." "INFO"

    # 启用 WSL
    $r1 = Enable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Windows-Subsystem-Linux" -NoRestart -ErrorAction SilentlyContinue
    if ($r1) { Write-Log "Windows Subsystem for Linux 已启用" "INFO" }
    else      { Write-Log "错误: 无法启用 Windows Subsystem for Linux" "ERROR" ; return $false }

    # 启用虚拟机平台
    $r2 = Enable-WindowsOptionalFeature -Online -FeatureName "VirtualMachinePlatform" -NoRestart -ErrorAction SilentlyContinue
    if ($r2) { Write-Log "Virtual Machine Platform 已启用" "INFO" }
    else      { Write-Log "错误: 无法启用 Virtual Machine Platform" "ERROR" ; return $false }

    # 下载 WSL2 内核更新包 (Windows 10 需要)
    $osVer = [System.Environment]::OSVersion.Version
    if ($osVer.Build -lt 19041) {
        Write-Log "检测到旧版 Windows 10，下载 WSL2 内核更新包..." "INFO"
        $msiUrl  = "https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi"
        $msiPath = Join-Path $env:TEMP "wsl_update_x64.msi"
        try {
            Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing -TimeoutSec 120
            Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /quiet /norestart" -Wait
            Write-Log "WSL2 内核更新包安装完成" "INFO"
        } catch {
            Write-Log "警告: WSL2 内核包下载失败 ($($_.Exception.Message))，重启后 Windows Update 会自动补全" "WARNING"
        }
    }

    wsl --set-default-version 2 2>$null | Out-Null
    Write-Log "WSL2 功能已启用，需要重启计算机以使更改生效" "WARNING"
    return "REBOOT_REQUIRED"
}

# ══════════════════════════════════════════════════════════════
# 阶段 3 — 安装 Ubuntu
# ══════════════════════════════════════════════════════════════
function Invoke-Stage3 {
    Write-Separator
    Write-Log "【阶段 3/6】安装 Ubuntu (WSL2)" "STEP"
    Write-Separator

    if (Test-UbuntuInstalled) {
        Write-Log "Ubuntu 已安装 ✓" "SUCCESS"
        return $true
    }

    Write-Log "正在安装 Ubuntu，这可能需要几分钟..." "INFO"
    Write-Log "提示: 安装完成后会弹出一个窗口要求设置 Linux 用户名和密码，请按提示操作" "WARNING"

    # wsl --install -d Ubuntu (Windows 11 / 较新 Windows 10)
    try {
        $p = Start-Process wsl -ArgumentList "--install -d Ubuntu --no-launch" -Wait -PassThru -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
        if (Test-UbuntuInstalled) {
            Write-Log "Ubuntu 安装成功 ✓" "SUCCESS"
            return $true
        }
    } catch { }

    # 备用: 从微软直接下载 Appx
    Write-Log "尝试备用方式安装 Ubuntu..." "INFO"
    try {
        $appxUrl  = "https://aka.ms/wslubuntu2204"
        $appxPath = Join-Path $env:TEMP "Ubuntu2204.appx"
        Invoke-WebRequest -Uri $appxUrl -OutFile $appxPath -UseBasicParsing -TimeoutSec 300
        Add-AppxPackage -Path $appxPath -ErrorAction Stop
        Start-Sleep -Seconds 10
        if (Test-UbuntuInstalled) {
            Write-Log "Ubuntu 安装成功 (备用方式) ✓" "SUCCESS"
            return $true
        }
    } catch {
        Write-Log "错误: Ubuntu 安装失败: $($_.Exception.Message)" "ERROR"
        return $false
    }

    Write-Log "错误: 无法确认 Ubuntu 已安装" "ERROR"
    return $false
}

# ══════════════════════════════════════════════════════════════
# 阶段 4 — 在 WSL Ubuntu 中安装 Node.js 22+
# ══════════════════════════════════════════════════════════════
function Invoke-Stage4 {
    Write-Separator
    Write-Log "【阶段 4/6】安装 Node.js 22+" "STEP"
    Write-Separator

    $major = Get-NodeMajorVersionInWSL
    if ($major -ge 22) {
        Write-Log "Node.js v$major 已满足要求 (>= 22) ✓" "SUCCESS"
        return $true
    }
    if ($major -gt 0) {
        Write-Log "当前 Node.js 版本 v$major 过低，需要 v22+，开始升级..." "WARNING"
    } else {
        Write-Log "未检测到 Node.js，开始安装 Node.js 22..." "INFO"
    }

    $script = @'
#!/usr/bin/env bash
set -e
echo "[Node.js] 更新 apt 包列表..."
sudo apt-get update -y -q

echo "[Node.js] 安装基础依赖..."
sudo apt-get install -y -q curl ca-certificates gnupg

echo "[Node.js] 添加 NodeSource v22 仓库..."
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - 2>&1

echo "[Node.js] 安装 Node.js 22..."
sudo apt-get install -y -q nodejs

echo "[Node.js] 安装结果:"
node --version
npm --version
echo "[Node.js] 安装完成!"
'@

    Write-Log "在 Ubuntu 中执行 Node.js 安装脚本..." "INFO"
    $rc = Invoke-WSLScript -ScriptBody $script -TmpPath "/tmp/oc_install_node.sh"
    if ($rc -ne 0) {
        Write-Log "错误: Node.js 安装脚本退出码 $rc" "ERROR"
        return $false
    }

    $major = Get-NodeMajorVersionInWSL
    if ($major -ge 22) {
        Write-Log "Node.js v$major 安装成功 ✓" "SUCCESS"
        return $true
    }
    Write-Log "错误: 安装后仍未检测到合规的 Node.js 版本" "ERROR"
    return $false
}

# ══════════════════════════════════════════════════════════════
# 阶段 5 — 安装 OpenClaw
# ══════════════════════════════════════════════════════════════
function Invoke-Stage5 {
    Write-Separator
    Write-Log "【阶段 5/6】安装 OpenClaw" "STEP"
    Write-Separator

    if (Test-OpenClawInstalled) {
        Write-Log "OpenClaw 已安装，检查是否有更新..." "INFO"
        $rc = Invoke-WSLScript -ScriptBody "sudo npm update -g openclaw 2>&1 || true" -TmpPath "/tmp/oc_update.sh"
        Write-Log "OpenClaw 已是最新版 ✓" "SUCCESS"
        return $true
    }

    Write-Log "正在安装 OpenClaw..." "INFO"

    # 国内环境可将此变量改为 "https://registry.npmmirror.com" 以使用淘宝镜像
    $npmRegistry = "https://registry.npmjs.org"

    $script = @"
#!/usr/bin/env bash
set -e

echo "[OpenClaw] 配置 npm registry: $npmRegistry"
npm config set registry "$npmRegistry"

echo "[OpenClaw] 全局安装 openclaw..."
sudo npm install -g openclaw@latest 2>&1

echo "[OpenClaw] 检查安装..."
openclaw --version 2>&1 || true

echo "[OpenClaw] 安装完成!"
"@

    Write-Log "在 Ubuntu 中执行 OpenClaw 安装脚本..." "INFO"
    $rc = Invoke-WSLScript -ScriptBody $script -TmpPath "/tmp/oc_install_openclaw.sh"
    if ($rc -ne 0) {
        Write-Log "错误: OpenClaw 安装脚本退出码 $rc" "ERROR"
        return $false
    }

    if (Test-OpenClawInstalled) {
        Write-Log "OpenClaw 安装成功 ✓" "SUCCESS"
        return $true
    }
    Write-Log "错误: 安装后无法检测到 openclaw 命令" "ERROR"
    return $false
}

# ══════════════════════════════════════════════════════════════
# 阶段 6 — 创建桌面快捷方式
# ══════════════════════════════════════════════════════════════
function Invoke-Stage6 {
    Write-Separator
    Write-Log "【阶段 6/6】创建桌面快捷方式" "STEP"
    Write-Separator

    $startBat   = Join-Path $ScriptDir "start_openclaw.bat"
    $desktopDir = [System.Environment]::GetFolderPath("Desktop")
    $lnkPath    = Join-Path $desktopDir "启动 OpenClaw.lnk"

    if (-not (Test-Path $startBat)) {
        Write-Log "警告: 找不到 start_openclaw.bat，跳过快捷方式创建" "WARNING"
        return $true
    }

    try {
        $wsh      = New-Object -ComObject WScript.Shell
        $shortcut = $wsh.CreateShortcut($lnkPath)
        $shortcut.TargetPath      = $startBat
        $shortcut.WorkingDirectory= $ScriptDir
        $shortcut.Description     = "启动 OpenClaw 中文版"
        $shortcut.IconLocation    = "shell32.dll,21"
        $shortcut.Save()
        Write-Log "桌面快捷方式已创建: $lnkPath ✓" "SUCCESS"
    } catch {
        Write-Log "警告: 无法创建桌面快捷方式: $($_.Exception.Message)" "WARNING"
    }

    return $true
}

# ══════════════════════════════════════════════════════════════
# 部署摘要
# ══════════════════════════════════════════════════════════════
function Show-Summary {
    param([bool]$Ok)
    Write-Separator
    if ($Ok) {
        Write-Host ""
        Write-Host " ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host " ║           ✓  OpenClaw 部署成功完成!                     ║" -ForegroundColor Green
        Write-Host " ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Green
        Write-Log "部署成功!" "SUCCESS"
        Write-Log "启动方式 1: 双击桌面快捷方式 [启动 OpenClaw]" "INFO"
        Write-Log "启动方式 2: 双击 start_openclaw.bat" "INFO"
        Write-Log "管理后台地址: http://localhost:18789" "INFO"
        Write-Log "首次使用请在 Ubuntu 终端运行: openclaw onboard" "INFO"
    } else {
        Write-Host ""
        Write-Host " ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Red
        Write-Host " ║           ✗  部署失败，请查看日志                        ║" -ForegroundColor Red
        Write-Host " ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Red
        Write-Log "部署失败，详细日志: $LogFile" "ERROR"
    }
    Write-Host ""
    Write-Log "日志文件: $LogFile" "INFO"
    Write-Separator
    Write-Host ""
    Write-Host " 按任意键退出..." -ForegroundColor DarkGray
    try { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") } catch { Read-Host "按 Enter 键退出" | Out-Null }
}

# ══════════════════════════════════════════════════════════════
# 主流程
# ══════════════════════════════════════════════════════════════
function Main {
    Write-Host ""
    Write-Host " ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host " ║         OpenClaw 中文版 一键部署脚本  v1.0              ║" -ForegroundColor Cyan
    Write-Host " ║         适用于 Windows 10 / Windows 11                  ║" -ForegroundColor Cyan
    Write-Host " ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    Write-Log "========= 部署开始 =========" "INFO"
    Write-Log "脚本目录: $ScriptDir" "INFO"
    Write-Log "日志文件: $LogFile" "INFO"

    $startStage = [int](Get-DeployState)
    if ($startStage -gt 1) {
        Write-Log "检测到上次未完成的部署，从阶段 $startStage 继续..." "WARNING"
    }

    # ── 阶段 1 ──
    if ($startStage -le 1) {
        if (-not (Invoke-Stage1)) { Show-Summary $false ; exit 1 }
        Set-DeployState "2"
    }

    # ── 阶段 2 ──
    if ($startStage -le 2) {
        $r2 = Invoke-Stage2
        if ($r2 -eq "REBOOT_REQUIRED") {
            Set-DeployState "3"
            Register-ResumeTask
            Write-Host ""
            Write-Host " WSL2 功能已启用，需要重启计算机才能继续。" -ForegroundColor Yellow
            Write-Host " 重启后脚本将自动从第 3 阶段继续部署。" -ForegroundColor Yellow
            Write-Host ""
            $ans = Read-Host " 是否立即重启? (输入 Y 确认，其他键取消)"
            if ($ans -match "^[Yy]") {
                Write-Log "用户确认重启" "INFO"
                Restart-Computer -Force
            } else {
                Write-Log "用户取消重启，请手动重启后继续部署" "WARNING"
                Show-Summary $false
            }
            return
        }
        if (-not $r2) { Show-Summary $false ; exit 1 }
        Set-DeployState "3"
    }

    # ── 阶段 3 ──
    if ($startStage -le 3) {
        if (-not (Invoke-Stage3)) { Show-Summary $false ; exit 1 }
        Set-DeployState "4"
    }

    # ── 阶段 4 ──
    if ($startStage -le 4) {
        if (-not (Invoke-Stage4)) { Show-Summary $false ; exit 1 }
        Set-DeployState "5"
    }

    # ── 阶段 5 ──
    if ($startStage -le 5) {
        if (-not (Invoke-Stage5)) { Show-Summary $false ; exit 1 }
        Set-DeployState "6"
    }

    # ── 阶段 6 ──
    Invoke-Stage6 | Out-Null

    # 清理
    Clear-DeployState
    Remove-ResumeTask

    Show-Summary $true
}

Main
