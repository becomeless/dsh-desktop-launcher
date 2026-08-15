# =====================================================================
#  DeepSeek Harness 桌面启动器
#
#  双击桌面上的 "DeepSeek Harness" 快捷方式即可运行本脚本：
#    1) 先在候选端口里找已经在运行的 DSH 服务（默认 127.0.0.1:3080），
#       没找到就在后台静默启动 npx @deepseek-ai/dsh web（输出写入
#       %TEMP%\DSH-Server.log）。
#       · 首选端口被 Windows 系统保留（Hyper-V/WSL2 的 TCP 排除端口段，
#         表现为 listen EACCES）或被占用时，自动换到 $FallbackPorts
#         里的下一个可用端口，无需手动处理。
#    2) 等待服务就绪
#    3) 用 Chrome 的 "应用模式"（--app，无地址栏的独立窗口）打开
#    4) 关闭应用窗口后，自动结束由本启动器创建的服务进程
#
#  整个过程不会弹出任何命令行窗口，失败时会弹提示框并附日志。
#  已经手动开着的服务不会被本脚本关掉。
# =====================================================================

param([string]$Browser = '')

# ------------------------- 配置区（按需修改） -------------------------
$DshPort    = 3080                  # 首选端口
$FallbackPorts = @(8080, 18080, 18081, 30800, 33080)   # 首选端口被系统保留/占用时依次尝试
$PreferredBrowser = 'chrome'        # 'chrome' 或 'edge'；找不到时自动回退到另一个
$StopServerWhenAppCloses = $true    # 关闭应用窗口后是否自动停掉服务
$StartupTimeoutSec = 180            # 等待服务就绪的最长时间（首次要下载依赖时可放宽）
$ServerWindowStyle = 'Hidden'       # 服务窗口样式：Hidden（推荐）/ Minimized
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

function Get-ExcludedTcpPorts {
    # 查询 Windows 为 Hyper-V/WSL2(WinNAT) 等保留的 TCP 排除端口段。
    # 查询失败或解析不到时返回空数组（后面靠"起不来就换下一个端口"兜底）。
    $ranges = @()
    try {
        $out = netsh int ipv4 show excludedportrange protocol=tcp 2>$null
        foreach ($line in $out) {
            if ($line -match '^\s*(\d+)\s+(\d+)\s*\*?\s*$') {
                $start = [int]$Matches[1]; $end = [int]$Matches[2]
                if ($start -ge 1 -and $end -le 65535 -and $start -le $end) {
                    $ranges += [pscustomobject]@{ Start = $start; End = $end }
                }
            }
        }
    } catch { }
    return $ranges
}

function Test-PortExcluded {
    param([int]$Port)
    foreach ($r in $script:ExcludedTcpPorts) {
        if ($Port -ge $r.Start -and $Port -le $r.End) { return $true }
    }
    return $false
}

function Test-DshWeb {
    # 端口上有服务在听，并且确认是 DeepSeek Harness 页面（而不是别的程序）
    param([int]$Port)
    if (-not (Test-DshPort -Port $Port)) { return $false }
    try {
        $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -UseBasicParsing -TimeoutSec 3
        return ($resp.Content -match 'DeepSeek Harness')
    } catch { return $false }
}

function Test-PortUsable {
    param([int]$Port)
    if (Test-PortExcluded -Port $Port) { return $false }
    if (Test-DshPort -Port $Port) { return $false }
    return $true
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

    $script:ExcludedTcpPorts = @(Get-ExcludedTcpPorts)
    $portCandidates = @($DshPort)
    foreach ($fp in $FallbackPorts) {
        if ($fp -ne $DshPort -and $portCandidates -notcontains $fp) { $portCandidates += $fp }
    }

    $chosenPort = 0
    $lastFailLog = ''

    # 1a) 候选端口上已有 DSH 服务在跑 → 直接复用，不重复启动
    foreach ($p in $portCandidates) {
        if (Test-DshWeb -Port $p) { $chosenPort = $p; break }
    }

    # 1b) 没有可复用的 → 在第一个"未被系统保留且空闲"的端口上启动
    if ($chosenPort -eq 0) {
        $serverScript = Join-Path $PSScriptRoot 'DSH-Server.ps1'
        $deadline = (Get-Date).AddSeconds($StartupTimeoutSec)
        foreach ($p in $portCandidates) {
            if (-not (Test-PortUsable -Port $p)) { continue }
            Remove-Item -LiteralPath $failMarker -Force -ErrorAction SilentlyContinue
            $serverProc = Start-Process -FilePath 'powershell.exe' `
                -WindowStyle $ServerWindowStyle -PassThru `
                -ArgumentList "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$serverScript`" -Port $p"
            $serverStartedHere = $true
            $startedOk = $false
            while ($true) {
                if (Test-DshPort -Port $p) { $startedOk = $true; break }
                if (Test-Path -LiteralPath $failMarker -or $serverProc.HasExited) { break }
                if ((Get-Date) -ge $deadline) {
                    throw ('等待服务就绪超时（' + $StartupTimeoutSec + ' 秒）。日志：' + $logPath + "`r`n`r`n" + (Get-LogTail -Path $logPath))
                }
                Start-Sleep -Milliseconds 800
            }
            if ($startedOk) { $chosenPort = $p; break }
            # 这个端口起不来（被系统保留或启动瞬间被抢占），收尾后试下一个
            taskkill.exe /PID $serverProc.Id /T /F 2>$null | Out-Null
            $serverProc = $null
            $lastFailLog = Get-LogTail -Path $logPath
        }
        if ($chosenPort -eq 0) {
            $msg = 'DSH 服务启动失败：候选端口（' + ($portCandidates -join ', ') + '）都被系统保留或被占用。'
            if ($lastFailLog) { $msg += "`r`n`r`n最后一次尝试的日志：`r`n" + $lastFailLog }
            throw $msg
        }
        Start-Sleep -Milliseconds 400
    }

    $DshUrl = "http://127.0.0.1:$chosenPort"

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
