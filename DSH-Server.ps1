# =====================================================================
#  DSH 服务进程 —— 由 DSH-Launcher.ps1 静默启动，一般不用手动运行。
#  可选参数 -Port 指定监听端口（默认 3080），对应 dsh web 的 --port。
#  所有输出写入 %TEMP%\DSH-Server.log（上一次运行的日志保留为 .old）；
#  如果该日志被上次残留的服务进程锁住，会自动改用
#  %TEMP%\DSH-Server-<PID>.log（启动器报错时会读它）。
#  启动时把本进程 PID 写入 %TEMP%\DSH-Server.pid，供启动器判断服务
#  归属（"关窗停服"只停由启动器管理的服务，手动开的不会被误杀）。
#  出问题先看这两个日志。
#  由启动器自动关闭；想手动停，关掉浏览器应用窗口即可。
# =====================================================================

param([int]$Port = 3080)

# 让工作目录和"手动打开 PowerShell 敲 npx"时保持一致
Set-Location $env:USERPROFILE

$logPath = Join-Path $env:TEMP 'DSH-Server.log'
$failMarker = Join-Path $env:TEMP 'DSH-Server-Exited.tmp'
$pidFile = Join-Path $env:TEMP 'DSH-Server.pid'

# 标记服务归属：启动器据此判断"关窗停服"时只停自己管理的服务
Set-Content -LiteralPath $pidFile -Value $PID -Encoding ASCII

# 主日志被残留进程锁住时，退回到本进程专属日志，避免服务一起动就挂掉
try {
    $lockTest = [System.IO.File]::Open($logPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $lockTest.Close()
} catch {
    $logPath = Join-Path $env:TEMP ("DSH-Server-" + $PID + ".log")
}

Remove-Item -LiteralPath $failMarker -Force -ErrorAction SilentlyContinue
# 轮转日志：保留上一次运行的日志为 .old，便于排障
if (Test-Path -LiteralPath $logPath) {
    Move-Item -LiteralPath $logPath -Destination ($logPath + '.old') -Force -ErrorAction SilentlyContinue
}
# 清理 7 天前的备用日志（主日志被锁时产生的 DSH-Server-<PID>.log）
Get-ChildItem -LiteralPath $env:TEMP -Filter 'DSH-Server-*.log' -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

# --no-open：新版 dsh web 默认会自动打开系统默认浏览器，
# 与启动器用 --app 打开的独立窗口重复；这里关掉，只保留应用窗口。
npx --yes @deepseek-ai/dsh web --no-open --port $Port *>> $logPath

Set-Content -LiteralPath $failMarker -Value 'exited' -Encoding ASCII
Add-Content -LiteralPath $logPath -Value ("`r`n--- DSH 服务已停止（退出码 " + $LASTEXITCODE + "）---`r`n") -Encoding UTF8
Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
