# =====================================================================
#  DSH 服务进程 —— 由 DSH-Launcher.ps1 静默启动，一般不用手动运行。
#  可选参数 -Port 指定监听端口（默认 3080），对应 dsh web 的 --port。
#  所有输出写入 %TEMP%\DSH-Server.log；如果该日志被上次残留的服务进程
#  锁住，会自动改用 %TEMP%\DSH-Server-<PID>.log（启动器报错时会读它）。
#  出问题先看这两个日志。
#  由启动器自动关闭；想手动停，关掉浏览器应用窗口即可。
# =====================================================================

param([int]$Port = 3080)

# 让工作目录和"手动打开 PowerShell 敲 npx"时保持一致
Set-Location $env:USERPROFILE

$logPath = Join-Path $env:TEMP 'DSH-Server.log'
$failMarker = Join-Path $env:TEMP 'DSH-Server-Exited.tmp'

# 主日志被残留进程锁住时，退回到本进程专属日志，避免服务一起动就挂掉
try {
    $lockTest = [System.IO.File]::Open($logPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $lockTest.Close()
} catch {
    $logPath = Join-Path $env:TEMP ("DSH-Server-" + $PID + ".log")
}

Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $failMarker -Force -ErrorAction SilentlyContinue

npx --yes @deepseek-ai/dsh web --port $Port *>> $logPath

Set-Content -LiteralPath $failMarker -Value 'exited' -Encoding ASCII
Add-Content -LiteralPath $logPath -Value ("`r`n--- DSH 服务已停止（退出码 " + $LASTEXITCODE + "）---`r`n") -Encoding UTF8
