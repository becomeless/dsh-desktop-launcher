# =====================================================================
#  DeepSeek Harness 桌面启动器
#
#  双击桌面上的 "DeepSeek Harness" 快捷方式即可运行本脚本：
#    1) 若 http://127.0.0.1:3080 还没运行，就在后台静默启动
#       npx @deepseek-ai/dsh web（输出写入 %TEMP%\DSH-Server.log）
#    2) 等待服务就绪
#    3) 用 Chrome 的 "应用模式"（--app，无地址栏的独立窗口）打开
#    4) 关闭应用窗口后，自动结束由本启动器创建的服务进程
#
#  整个过程不会弹出任何命令行窗口，失败时会弹提示框并附日志。
#  已经手动开着的服务不会被本脚本关掉。
# =====================================================================

param([string]$Browser = '')

# ------------------------- 配置区（按需修改） -------------------------
$DshUrl     = 'http://127.0.0.1:3080'
$DshPort    = 3080
$PreferredBrowser = 'chrome'          # 'chrome' 或 'edge'；找不到时自动回退到另一个
$StopServerWhenAppCloses = $true      # 关闭应用窗口后是否自动停掉服务
$StartupTimeoutSec = 180              # 等待服务就绪的最长时间（首次要下载依赖时可放宽）
$ServerWindowStyle = 'Hidden'          # 服务窗口样式：Hidden（推荐）/ Minimized
# ---------------------------------------------------------------------

if ($Browser) { $PreferredBrowser = $Browser }

function Show-Msg {
    param([string]$Text)
    Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
    [System.Windows.MessageBox]::Show($Text, 'DeepSeek Harness 启动器') | Out-Null
}

function Get-LogTail {
    param([string]$Path, [int]$Lines = 12)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    try { return ((Get-Content -LiteralPath $Path -Tail $Lines -ErrorAction SilentlyContinue) -join "`r`n") }
    catch { return '' }
}

function Test-DshPort {
    param([int]$Port)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        $ok = $async.AsyncWaitHandle.WaitOne(700)
        if (-not $ok) { return $false }
        try { $client.EndConnect($async); return $true } catch { return $false }
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Find-BrowserExe {
    param([string]$Name)
    $candidates = @()
    if ($Name -eq 'edge') {
        $candidates = @(
            (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
            (Join-Path $env:ProgramFiles       'Microsoft\Edge\Application\msedge.exe'),
            (Join-Path $env:LOCALAPPDATA       'Microsoft\Edge\Application\msedge.exe')
        )
    } else {
        $candidates = @(
            (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
            (Join-Path $env:ProgramFiles       'Google\Chrome\Application\chrome.exe'),
            (Join-Path $env:LOCALAPPDATA       'Google\Chrome\Application\chrome.exe')
        )
    }
    foreach ($p in $candidates) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    return $null
}

$ErrorActionPreference = 'Stop'
try {
    # 0) 前置检查：没有 Node.js（npx）时给出友好提示
    if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
        throw '未检测到 Node.js（npx 不存在）。请先到 https://nodejs.org 安装 Node.js，然后重新双击启动。'
    }

    $serverStartedHere = $false
    $serverProc = $null
    $failMarker = Join-Path $env:TEMP 'DSH-Server-Exited.tmp'
    $logPath = Join-Path $env:TEMP 'DSH-Server.log'

    # 1) 确保服务在运行
    if (-not (Test-DshPort -Port $DshPort)) {
        Remove-Item -LiteralPath $failMarker -Force -ErrorAction SilentlyContinue
        $serverScript = Join-Path $PSScriptRoot 'DSH-Server.ps1'
        $serverProc = Start-Process -FilePath 'powershell.exe' `
            -WindowStyle $ServerWindowStyle -PassThru `
            -ArgumentList "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$serverScript`""
        $serverStartedHere = $true

        $deadline = (Get-Date).AddSeconds($StartupTimeoutSec)
        while (-not (Test-DshPort -Port $DshPort)) {
            if (Test-Path -LiteralPath $failMarker) {
                throw ('DSH 服务启动失败。日志：' + $logPath + "`r`n`r`n" + (Get-LogTail -Path $logPath))
            }
            if ($serverProc.HasExited) {
                throw ('DSH 服务进程已退出。日志：' + $logPath + "`r`n`r`n" + (Get-LogTail -Path $logPath))
            }
            if ((Get-Date) -ge $deadline) {
                throw ('等待服务就绪超时（' + $StartupTimeoutSec + ' 秒）。日志：' + $logPath + "`r`n`r`n" + (Get-LogTail -Path $logPath))
            }
            Start-Sleep -Milliseconds 800
        }
        Start-Sleep -Milliseconds 400
    }

    # 2) 用应用模式打开
    $browserExe = Find-BrowserExe -Name $PreferredBrowser
    if (-not $browserExe) {
        $other = 'chrome'
        if ($PreferredBrowser -eq 'chrome') { $other = 'edge' }
        $browserExe = Find-BrowserExe -Name $other
    }
    if (-not $browserExe) { throw '未找到 Chrome 或 Edge 浏览器，无法打开应用窗口。' }

    $appProc = Start-Process -FilePath $browserExe -ArgumentList "--app=$DshUrl" -PassThru

    # 3) 应用窗口关闭后，自动停掉由本启动器创建的服务
    if ($serverStartedHere -and $StopServerWhenAppCloses) {
        Start-Sleep -Seconds 3
        if (-not $appProc.HasExited) {
            $appProc.WaitForExit()
            Start-Sleep -Milliseconds 500
            taskkill.exe /PID $serverProc.Id /T /F 2>$null | Out-Null
        }
    }
} catch {
    Show-Msg -Text ("启动失败：`r`n`r`n" + $_.Exception.Message)
    if ($serverStartedHere -and $serverProc) {
        taskkill.exe /PID $serverProc.Id /T /F 2>$null | Out-Null
    }
    exit 1
}
