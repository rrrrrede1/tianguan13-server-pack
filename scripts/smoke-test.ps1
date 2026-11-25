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
$dmb = Join-Path $pkg 'tgstation.dmb'
$log = Join-Path $pkg 'data\server.log'

# ⚠️ 实测（2026-11-25，GitHub windows-latest）：dreamdaemon.exe 是 GUI 程序，
# 在无桌面的 runner 上会卡在窗口/图形初始化——60 秒后进程仍存活、零输出、不写日志。
# 而 dd.exe（控制台版守护进程）能正常开世界：23 秒就 "World loaded"。
# 所以 CI 冒烟测试优先用 dd.exe；玩家端仍然用 dreamdaemon.exe（有桌面、能看窗口日志）。
$dd = Join-Path $pkg 'byond\bin\dd.exe'
if (-not (Test-Path $dd)) { $dd = Join-Path $pkg 'byond\bin\dreamdaemon.exe' }
Write-Host ("launcher = {0}" -f (Split-Path $dd -Leaf))

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
  # ⚠️ working set 会把 .rsc 的**文件映射页**也算进去（run #11 报 2269 MB），
  #    对 32 位进程的真实压力应该看 private bytes（提交的私有内存）。
  $wsMB   = [math]::Round($p.WorkingSet64 / 1MB, 1)
  $privMB = [math]::Round($p.PrivateMemorySize64 / 1MB, 1)
  Write-Host ("memory: working set = {0} MB | private = {1} MB" -f $wsMB, $privMB)
  Write-Host "(32 位进程：private 才是真实堆压力；working set 含 mmap 的资源文件)"
  if ($privMB -gt 1500) { Write-Warning "私有内存 ${privMB} MB 偏高（32 位上限约 2-4GB，长期跑有风险）" }
  $memMB = $privMB
  # ⚠️ 只 Stop-Process 不够：实测 7z 紧接着就会报
  #    "The process cannot access the file because it is being used by another process"
  #    （运行时还在写 tgstation.dyn.rsc / data\server.log）。所以要等它真退出，再清运行时产物。
  Get-Process -Name dd,dreamdaemon -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  try { $p.WaitForExit(15000) | Out-Null } catch { }
  Start-Sleep -Seconds 2
}

# ---- 清掉运行时生成物（它们会在下次启动时重建；留在包里既占体积又会锁文件）----
$artifacts = @(
  'tgstation.dyn.rsc', 'tgstation.dyn.rsc.lk', 'tgstation.rsc.lk',
  'data\server.log', 'data\console-out.log', 'data\console-err.log', 'data\probe.log'
)
foreach ($rel in $artifacts) {
  $f = Join-Path $pkg $rel
  if (Test-Path $f) {
    for ($try = 1; $try -le 5; $try++) {
      try { Remove-Item $f -Force -ErrorAction Stop; Write-Host "  cleaned $rel"; break }
      catch { if ($try -eq 5) { Write-Warning "cleanup failed: $rel ($($_.Exception.Message))" } else { Start-Sleep -Seconds 2 } }
    }
  }
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
