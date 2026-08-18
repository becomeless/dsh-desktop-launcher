# =====================================================================
#  DeepSeek Harness 桌面启动器
#
#  双击桌面上的 "DeepSeek Harness" 快捷方式即可运行本脚本：
#    1) 先在候选端口里找已经在运行的 DSH 服务（默认 127.0.0.1:3080），
#       没找到就在后台静默启动 npx @deepseek-ai/dsh web（输出写入
#       %TEMP%\DSH-Server.log，上一次运行的日志保留为 .old）。
#       · 首选端口被 Windows 系统保留（Hyper-V/WSL2 的 TCP 排除端口段，
#         表现为 listen EACCES）或被占用时，自动换到 $FallbackPorts
#         里的下一个可用端口，无需手动处理。
#       · 单实例互斥：启动过程中再双击时，第二个实例只等待复用
#         第一个实例拉起的服务，不会重复启动。
#    2) 等待服务 HTTP 就绪（而不是端口通了就开浏览器，避免白屏）
#    3) 用 Chrome 的"应用模式"（--app，无地址栏的独立窗口）打开。
#       窗口使用独立的浏览器配置目录（chrome-profile / edge-profile）：
#       Chrome/Edge 是单例模型，若浏览器已在运行，新进程会把窗口交给
#       现有进程后立即退出，导致无法感知关窗；独立配置目录强制新实例，
#       配合 --disable-background-mode，窗口关闭即进程退出。
#    4) 关闭应用窗口后，自动结束由启动器管理的服务进程。服务归属通过
#       %TEMP%\DSH-Server.pid 识别，手动开着的服务不会被关掉。
#
#  整个过程不会弹出任何命令行窗口，失败时会弹提示框并附日志。
#  等待就绪超时不会停掉服务（首次启动/更新时下载依赖较慢），
#  稍后再双击一次即可直接打开。
# =====================================================================

param([string]$Browser = '')

# ------------------------- 配置区（按需修改） -------------------------
$DshPort    = 3080                  # 首选端口
$FallbackPorts = @(8080, 18080, 18081, 30800, 33080)   # 首选端口被系统保留/占用时依次尝试
$PreferredBrowser = 'chrome'        # 'chrome' 或 'edge'；找不到时自动回退到另一个
$StopServerWhenAppCloses = $true    # 关闭应用窗口后是否自动停掉服务
$StartupTimeoutSec = 600            # 等待服务就绪的最长时间；超时不停服（可能正在下载最新版），稍后再双击即可
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
    # 懒加载：只在真正需要判断端口时才查一次（netsh 调用有固定开销）
    if ($null -eq $script:ExcludedTcpPorts) {
        $script:ExcludedTcpPorts = @(Get-ExcludedTcpPorts)
    }
    foreach ($r in $script:ExcludedTcpPorts) {
        if ($Port -ge $r.Start -and $Port -le $r.End) { return $true }
    }
    return $false
}

function Test-DshProcessOnPort {
    # 监听端口进程的命令行确实属于 dsh —— 页面文案改版时的兜底判断
    param([int]$Port)
    try {
        $listeners = netstat -ano | Select-String -Pattern "127\.0\.0\.1:$Port\s.*LISTENING"
        foreach ($line in $listeners) {
            $ownerPid = ($line.ToString() -split '\s+')[-1]
            if ($ownerPid -notmatch '^\d+$') { continue }
            $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$ownerPid" -ErrorAction SilentlyContinue
            if ($proc -and $proc.CommandLine -and $proc.CommandLine -match '@deepseek-ai[/\\]dsh') { return $true }
        }
    } catch { }
    return $false
}

function Test-DshWeb {
    # 端口上有服务在听，并且确认是 DeepSeek Harness（而不是别的程序）
    param([int]$Port)
    if (-not (Test-DshPort -Port $Port)) { return $false }
    try {
        $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -UseBasicParsing -TimeoutSec 3
        return ($resp.Content -match 'DeepSeek Harness')
    } catch {
        return (Test-DshProcessOnPort -Port $Port)
    }
}

function Test-HttpReady {
    # 服务已能响应 HTTP（任意响应码都算就绪；连接被拒才是未就绪）
    param([int]$Port)
    try {
        Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -UseBasicParsing -TimeoutSec 3 | Out-Null
        return $true
    } catch [System.Net.WebException] {
        return ($null -ne $_.Exception.Response)
    } catch {
        return $false
    }
}

function Test-PortUsable {
    param([int]$Port)
    if (Test-PortExcluded -Port $Port) { return $false }
    if (Test-DshPort -Port $Port) { return $false }
    return $true
}

function Test-ProcessAlive {
    # 进程被外部杀掉后，Process 对象访问 HasExited 可能抛异常，
    # 在 $ErrorActionPreference='Stop' 下会误入 catch，统一包一层
    param($Proc)
    if (-not $Proc) { return $false }
    try { return (-not $Proc.HasExited) } catch { return $false }
}

function Get-OwnedServerPid {
    # 读 %TEMP%\DSH-Server.pid 判断服务是否由本启动器管理。
    # 手动启动的服务没有 pid 文件，不会被"关窗停服"误杀。
    $pf = Join-Path $env:TEMP 'DSH-Server.pid'
    if (-not (Test-Path -LiteralPath $pf)) { return 0 }
    try { $svcPid = [int](Get-Content -LiteralPath $pf -Raw) } catch { return 0 }
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$svcPid" -ErrorAction SilentlyContinue
    if ($proc -and $proc.CommandLine -and $proc.CommandLine -match 'DSH-Server\.ps1') { return $svcPid }
    return 0
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
    $serverStartedHere = $false
    $serverProc = $null
    $keepServerOnError = $false
    $failMarker = Join-Path $env:TEMP 'DSH-Server-Exited.tmp'
    $logPath = Join-Path $env:TEMP 'DSH-Server.log'
    $pidFile = Join-Path $env:TEMP 'DSH-Server.pid'

    # 0) 单实例互斥：另一个启动器正在启动/管理服务时，本实例只等待复用
    $launcherMutex = New-Object System.Threading.Mutex($false, 'DSH-Launcher-SingleInstance')
    $isPrimary = $false
    try { $isPrimary = $launcherMutex.WaitOne(0) } catch { $isPrimary = $true }

    # 0b) 前置检查：没有 Node.js（npx）时给出友好提示（只有主实例需要）
    if ($isPrimary -and -not (Get-Command npx -ErrorAction SilentlyContinue)) {
        throw '未检测到 Node.js（npx 不存在）。请先到 https://nodejs.org 安装 Node.js，然后重新双击启动。'
    }

    $script:ExcludedTcpPorts = $null
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

    if ($isPrimary) {
        # 1b) 没有可复用的 → 在第一个"未被系统保留且空闲"的端口上启动
        if ($chosenPort -eq 0) {
            $serverScript = Join-Path $PSScriptRoot 'DSH-Server.ps1'

            # 之前超时被保留的服务可能仍在启动中（pid 文件有效）→ 先等它，
            # 而不是再拉起一个重复下载
            $lingeringPid = Get-OwnedServerPid
            if ($lingeringPid -ne 0) {
                $deadline = (Get-Date).AddSeconds($StartupTimeoutSec)
                while ($chosenPort -eq 0 -and (Get-Date) -lt $deadline) {
                    foreach ($p in $portCandidates) {
                        if (Test-DshWeb -Port $p) { $chosenPort = $p; break }
                    }
                    if ($chosenPort -ne 0) { break }
                    if (-not (Test-ProcessAlive (Get-Process -Id $lingeringPid -ErrorAction SilentlyContinue))) { break }
                    Start-Sleep -Milliseconds 800
                }
                if ($chosenPort -eq 0) {
                    throw ('后台服务仍在启动中，等待超时（' + $StartupTimeoutSec + ' 秒）。请稍后再双击一次。')
                }
            }

            if ($chosenPort -eq 0) {
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
                        # 等 HTTP 就绪（而不只是端口通），避免浏览器打开后白屏
                        if (Test-HttpReady -Port $p) { $startedOk = $true; break }
                        if ((Test-Path -LiteralPath $failMarker) -or -not (Test-ProcessAlive $serverProc)) { break }
                        if ((Get-Date) -ge $deadline) {
                            # 超时不停服：很可能正在下载最新版（首次启动/更新较慢），
                            # 留它继续启动，稍后双击可直接复用（pid 文件标记归属）
                            $keepServerOnError = $true
                            $errLog = $logPath
                            $altLog = Join-Path $env:TEMP ("DSH-Server-" + $serverProc.Id + ".log")
                            if (Test-Path -LiteralPath $altLog) { $errLog = $altLog }
                            throw ('等待服务就绪超时（' + $StartupTimeoutSec + ' 秒）。' +
                                '服务仍在后台继续启动（可能在下载最新版），稍后再双击一次即可直接打开。' +
                                '日志：' + $errLog + "`r`n`r`n" + (Get-LogTail -Path $errLog))
                        }
                        Start-Sleep -Milliseconds 800
                    }
                    if ($startedOk) { $chosenPort = $p; break }
                    # 这个端口起不来（被系统保留或启动瞬间被抢占），收尾后试下一个
                    # 注意：不能用 `taskkill ... 2>$null`——PowerShell 5.1 在
                    # $ErrorActionPreference='Stop' 下会把失败时的 stderr 变成终止性异常；
                    # 由 cmd 内部重定向则完全不经过 PowerShell 的错误流。
                    cmd.exe /c "taskkill /PID $($serverProc.Id) /T /F >nul 2>&1"
                    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
                    $altLog = Join-Path $env:TEMP ("DSH-Server-" + $serverProc.Id + ".log")
                    $errLog = $logPath
                    if (Test-Path -LiteralPath $altLog) { $errLog = $altLog }
                    $lastFailLog = Get-LogTail -Path $errLog
                    $serverProc = $null
                }
                if ($chosenPort -eq 0) {
                    $msg = 'DSH 服务启动失败：候选端口（' + ($portCandidates -join ', ') + '）都被系统保留或被占用。'
                    if ($lastFailLog) { $msg += "`r`n`r`n最后一次尝试的日志：`r`n" + $lastFailLog }
                    throw $msg
                }
                Start-Sleep -Milliseconds 400
            }
        }
    } else {
        # 第二个实例：等主实例把服务拉起来后复用；窗口已在就直接退出
        $deadline = (Get-Date).AddSeconds($StartupTimeoutSec)
        while ($chosenPort -eq 0 -and (Get-Date) -lt $deadline) {
            foreach ($p in $portCandidates) {
                if (Test-DshWeb -Port $p) { $chosenPort = $p; break }
            }
            if ($chosenPort -eq 0) { Start-Sleep -Milliseconds 1000 }
        }
        if ($chosenPort -eq 0) {
            throw ('另一个启动器正在启动服务，等待超时（' + $StartupTimeoutSec + ' 秒）。请稍后再双击一次。')
        }
        $existingWindow = Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and $_.CommandLine -match "--app=http://127\.0\.0\.1:$chosenPort\b" }
        if ($existingWindow) { exit 0 }
    }

    # 服务归属：本启动器起的 → $serverProc.Id；复用但由启动器管理（有 pid 文件）→ 读 pid 文件
    $ownedServerPid = 0
    if ($serverStartedHere -and $serverProc) {
        $ownedServerPid = $serverProc.Id
    } else {
        $ownedServerPid = Get-OwnedServerPid
    }

    $DshUrl = "http://127.0.0.1:$chosenPort"

    # 2) 用应用模式打开（独立浏览器配置目录）
    $browserExe = Find-BrowserExe -Name $PreferredBrowser
    if (-not $browserExe) {
        $other = 'chrome'
        if ($PreferredBrowser -eq 'chrome') { $other = 'edge' }
        $browserExe = Find-BrowserExe -Name $other
    }
    if (-not $browserExe) { throw '未找到 Chrome 或 Edge 浏览器，无法打开应用窗口。' }

    # Chrome/Edge 是单例模型：若浏览器已在运行，新进程会把窗口交给现有
    # 进程后立即退出，导致无法感知关窗。独立配置目录强制新实例，窗口
    # 关闭即进程退出；--disable-background-mode 防止后台驻留导致永不退出。
    $profileName = 'chrome-profile'
    if ($browserExe -match 'msedge') { $profileName = 'edge-profile' }
    $profileDir = Join-Path $PSScriptRoot $profileName
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null

    $appProc = Start-Process -FilePath $browserExe -PassThru `
        -ArgumentList "--app=$DshUrl --user-data-dir=`"$profileDir`" --no-first-run --disable-background-mode"

    # 3) 应用窗口关闭后，自动停掉由本启动器管理的服务
    if ($ownedServerPid -ne 0 -and $StopServerWhenAppCloses) {
        Start-Sleep -Seconds 3
        if (-not $appProc.HasExited) {
            $appProc.WaitForExit()
            Start-Sleep -Milliseconds 500
            cmd.exe /c "taskkill /PID $ownedServerPid /T /F >nul 2>&1"
            Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
        }
    }
} catch {
    # 先清理由本启动器创建的进程，再弹窗（弹窗会阻塞等待用户点击）
    if ($serverStartedHere -and $serverProc -and -not $keepServerOnError) {
        cmd.exe /c "taskkill /PID $($serverProc.Id) /T /F >nul 2>&1"
    }
    Show-Msg -Text ("启动失败：`r`n`r`n" + $_.Exception.Message)
    exit 1
}
