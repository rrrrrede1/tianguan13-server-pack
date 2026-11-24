# scripts/smoke-test.ps1 —— 打包后的"真启动一次"验证
#
# 目的：光编译成功不代表能开服。这里用包内自带的引擎真起一次服务器，
#       等到日志出现 "Initializations complete" 才算通过，然后关掉。
#
# 判据（实测基线）：
#   日志第 2 行左右会出现 "World opened on network port 1337."
#   首次初始化约 131 秒；这里给 8 分钟窗口。
#
# 用法：./scripts/smoke-test.ps1 -PackageDir out/TianGuan13_Server [-Port 1337] [-TimeoutMinutes 8]

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$PackageDir,
  [int]$Port = 1337,
  [int]$TimeoutMinutes = 8
)

$ErrorActionPreference = 'Stop'

$pkg = (Resolve-Path $PackageDir).Path
$dd  = Join-Path $pkg 'byond\bin\dreamdaemon.exe'
$dmb = Join-Path $pkg 'tgstation.dmb'
$log = Join-Path $pkg 'data\server.log'

foreach ($f in @($dd, $dmb)) {
  if (-not (Test-Path $f)) { throw "smoke test: missing $f" }
}
New-Item -ItemType Directory -Force (Join-Path $pkg 'data') | Out-Null
if (Test-Path $log) { Remove-Item $log -Force }

Write-Host "starting DreamDaemon on port $Port (this takes ~2 minutes) ..."
$p = Start-Process -FilePath $dd `
  -ArgumentList @('tgstation.dmb', '-port', "$Port", '-trusted', '-log', $log, '-verbose') `
  -WorkingDirectory $pkg -PassThru `
  -RedirectStandardOutput (Join-Path $pkg 'data\console-out.log') `
  -RedirectStandardError  (Join-Path $pkg 'data\console-err.log')

$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$ok = $false
$lastSize = -1
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 5
  if ($p.HasExited) {
    Write-Warning "DreamDaemon exited early (code $($p.ExitCode))"
    if ($p.ExitCode -eq -1073741515) {
      Write-Warning "0xC0000135 = STATUS_DLL_NOT_FOUND：dreamdaemon.exe 缺 DLL"
      Write-Warning "最常见是缺 x86 VC++ 运行库的 mfc140u.dll；把 mfc140u.dll / msvcp140.dll / vcruntime140.dll 放进 byond\bin 即可"
    }
    break
  }
  if (Test-Path $log) {
    $size = (Get-Item $log).Length
    if ($size -ne $lastSize) { $lastSize = $size }
    if (Select-String -Path $log -Pattern 'Initializations complete' -Quiet) { $ok = $true; break }
  }
}

$memMB = 0
if (-not $p.HasExited) {
  $p.Refresh()
  $memMB = [math]::Round($p.WorkingSet64 / 1MB, 1)
  Write-Host ("memory peak (working set) = {0} MB" -f $memMB)
  # 32 位进程：这个数字长期接近/超过 1.5GB 就会有稳定性风险
  if ($memMB -gt 1600) { Write-Warning "dreamdaemon 内存 ${memMB}MB 偏高（32 位进程）" }
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
}

if (-not $ok) {
  Write-Host '---- server.log tail ----'
  if (Test-Path $log) { Get-Content $log -Tail 80 } else { Write-Host '(no log produced)' }
  Write-Host '---- console err ----'
  $err = Join-Path $pkg 'data\console-err.log'
  if (Test-Path $err) { Get-Content $err -Tail 40 }
  throw 'SMOKE TEST FAILED: did not see "Initializations complete"'
}

$line = (Select-String -Path $log -Pattern 'Initializations complete' | Select-Object -First 1).Line.Trim()
Write-Host "SMOKE TEST OK: $line"

# 顺带报一下 runtime 噪声，但不判失败（ambience 那类错误不影响玩法）
$amb = (Select-String -Path $log -Pattern 'play_ambience failed' | Measure-Object).Count
if ($amb -gt 0) { Write-Warning "play_ambience runtime x$amb（声音文件缺失的表现；deploy 阶段有镜像 sound/ 的话应该为 0）" }
