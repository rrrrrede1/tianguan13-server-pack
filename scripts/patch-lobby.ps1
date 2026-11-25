# scripts/patch-lobby.ps1 —— 让"天关大厅"不被同路径重定义覆盖
#
# 背景（实测）：
#   modular_skyrat/modules/title_screen/code/title_screen_html.dm  (561 行，天关定制大厅)
#     定义 /mob/dead/new_player/proc/get_title_html()
#   modular_zzplurt/code/modules/mob/dead/new_player/title_screen_html.dm (5 行)
#     又定义了 /mob/dead/new_player/get_title_html()  ← 同一个 proc
#   tgstation.dme 里 zzplurt 那份编译在后（11042 > 9103）→ 覆盖前者；
#   而它的 ..() 只能调到父类型 /mob（没有这个 proc）→ 返回 null
#   → update_title_screen() 里 src << browse(get_title_html(), "window=title_browser") 得到空白
#   → 玩家看到的大厅没有背景、没有按钮。
#
# 这个脚本在**编译前**改源码（只改工作区里的 src/，仓库本身保持零差异）：
#   1. 把 zzplurt 那份改名成 tg_lobby_suppressed()，保留它"启动期/自定义载入条时不显示大厅"的原意
#   2. 在天关版 get_title_html() 开头调用这个守卫
#
# 用法：./pack/scripts/patch-lobby.ps1 -SrcDir src

[CmdletBinding()]
param([string]$SrcDir = 'src')

$ErrorActionPreference = 'Stop'

$skyrat  = Join-Path $SrcDir 'modular_skyrat/modules/title_screen/code/title_screen_html.dm'
$zzplurt = Join-Path $SrcDir 'modular_zzplurt/code/modules/mob/dead/new_player/title_screen_html.dm'

foreach ($f in @($skyrat, $zzplurt)) {
  if (-not (Test-Path $f)) { throw "patch-lobby: 找不到 $f（上游改了目录结构？）" }
}

# ---------- 1. zzplurt：不再覆盖 ----------
$zz = [IO.File]::ReadAllText($zzplurt, [Text.Encoding]::UTF8)
if ($zz -match '(?m)^\s*/mob/dead/new_player(/proc)?/get_title_html\s*\(') {
  $stub = @'
// [pack-patch] 本文件原本在这里重新定义 /mob/dead/new_player/get_title_html()。
// 由于 modular_skyrat 的同名 proc 在 .dme 中编译更早，本文件（较晚）会整段覆盖它；
// 而 ..() 只能调用父类型 /mob 的实现（不存在）→ 大厅 HTML 变空白。
// 打包时改名为 tg_lobby_suppressed()，把"启动期/自定义载入条时不显示大厅"的原意保留为被调用的守卫。
/mob/dead/new_player/proc/tg_lobby_suppressed()
	. = (SSticker.current_state == GAME_STATE_STARTUP)
	if(!. && SStitle.splashscreen_name)
		. = findtext(SStitle.splashscreen_name, "has_title")
	return .
'@
  [IO.File]::WriteAllText($zzplurt, ($stub -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))
  Write-Host "  [ok] zzplurt: get_title_html() 已改名成 tg_lobby_suppressed()"
} else {
  Write-Host "  [skip] zzplurt: 已经不含 get_title_html()（上游自己修了？）"
}

# ---------- 2. 天关版：接上守卫 ----------
$sk = [IO.File]::ReadAllText($skyrat, [Text.Encoding]::UTF8)
if ($sk -notmatch 'TG_LOBBY_ART_CANDIDATES') {
  throw "patch-lobby: $skyrat 看起来不是天关大厅那份（找不到 TG_LOBBY_ART_CANDIDATES）"
}
if ($sk -match 'tg_lobby_suppressed\(\)') {
  Write-Host "  [skip] 天关版已带守卫"
} else {
  # 允许 CRLF / LF 两种写法
  $pat = '(?m)^/mob/dead/new_player/proc/get_title_html\(\)\r?\n(\t+)var/dat = SStitle\.title_html'
  $m = [regex]::Match($sk, $pat)
  if (-not $m.Success) { throw "patch-lobby: 天关版 get_title_html() 的开头不是预期形状，请人工看一下 $skyrat" }
  # 注意：用 Remove/Insert 拼，不要用正则替换的 `$1`（PowerShell 双引号里的 $1 会被当变量展开）
  $tab = $m.Groups[1].Value
  $insert = "/mob/dead/new_player/proc/get_title_html()`n" +
            $tab + "if(tg_lobby_suppressed())`n" +
            $tab + "`treturn`n" +
            $tab + "var/dat = SStitle.title_html"
  $sk2 = $sk.Remove($m.Index, $m.Length).Insert($m.Index, $insert)
  [IO.File]::WriteAllText($skyrat, $sk2, (New-Object Text.UTF8Encoding($false)))
  Write-Host "  [ok] 天关版: get_title_html() 开头已插入 tg_lobby_suppressed() 守卫"
}

# ---------- 3. 自检（改完必须验，别信"写成功"） ----------
$zzAfter = [IO.File]::ReadAllText($zzplurt, [Text.Encoding]::UTF8)
$skAfter = [IO.File]::ReadAllText($skyrat, [Text.Encoding]::UTF8)
if ($zzAfter -match '(?m)^\s*/mob/dead/new_player(/proc)?/get_title_html\s*\(') { throw "自检失败：zzplurt 里仍有 get_title_html() 覆盖" }
if ($zzAfter -notmatch 'tg_lobby_suppressed')                { throw "自检失败：zzplurt 里没有 tg_lobby_suppressed()" }
if ($skAfter -notmatch 'if\(tg_lobby_suppressed\(\)\)')      { throw "自检失败：天关版没有接上守卫" }
if (([regex]::Matches($skAfter, 'get_title_html\(\)')).Count -lt 1) { throw "自检失败：天关版 get_title_html() 不见了" }

Write-Host "  [verify] 天关大厅 HTML 现在是唯一的 get_title_html() 实现"
Write-Host ("  [verify] 天关版行数 = {0}，zzplurt 版行数 = {1}" -f `
  ($skAfter -split "`n").Count, ($zzAfter -split "`n").Count)
