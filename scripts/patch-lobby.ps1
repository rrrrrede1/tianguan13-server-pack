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

# ---------- 2.5 外观：去掉侧栏展示图（PLEASE WAIT），背景改全黑 ----------
# 实测：天关仓库里没有横幅尺寸的大厅展示图，只有 modular_tianguan/icons/tianguan_logo.png（32x32）。
# TG_LOBBY_ART_CANDIDATES 的前两个候选（lobby_art.gif/png）不存在 → 回落到
# modular_skyrat/.../loading_screen.gif，就是玩家看到的 "PLEASE WAIT"。
# 展示框 CSS 是 width:100% height:18vmin object-fit:cover，把 32x32 拉进去只会糊成一团，
# 所以按用户要求：不放展示图，背景由纯黑 div 负责。
$skA = [IO.File]::ReadAllText($skyrat, [Text.Encoding]::UTF8)
if ($skA -match 'class="tg_art"') {
  $patArt = '(?m)^\t\tvar/art_tag = tg_lobby_art_html\(\)\r?\n\t\tif\(art_tag\)\r?\n\t\t\tdat \+= \{"<div class="tg_art">\[art_tag\]</div>"\}'
  $mA = [regex]::Match($skA, $patArt)
  if (-not $mA.Success) { throw "patch-lobby: 找不到 tg_art 的输出块（上游改了？）请人工看一下 $skyrat" }
  $replA = "`t`t// [pack-patch] 天关无横幅尺寸的大厅展示图（仅 32x32 logo），此处不再输出 tg_art，" +
           "`n`t`t// 避免回落到 SPLURT 的 loading_screen.gif（玩家看到的 PLEASE WAIT）。"
  $skA = $skA.Remove($mA.Index, $mA.Length).Insert($mA.Index, $replA)
  [IO.File]::WriteAllText($skyrat, $skA, (New-Object Text.UTF8Encoding($false)))
  Write-Host "  [ok] 天关版: 已移除侧栏展示图（tg_art）"
} else { Write-Host "  [skip] 天关版已无 tg_art 输出" }

$skB = [IO.File]::ReadAllText($skyrat, [Text.Encoding]::UTF8)
if ($skB -match 'class="bg"') {
  $patBg = '(?m)^(\t)else\r?\n\t\tdat \+= \{"<img src="loading_screen\.gif" class="bg" alt="">"\}'
  $mB = [regex]::Match($skB, $patBg)
  if (-not $mB.Success) { throw "patch-lobby: 找不到主菜单背景 <img class=bg> 的输出（上游改了？）" }
  $blackDiv = '<div style="position:fixed;left:0;top:0;width:100%;height:100%;background-color:#000"></div>'
  $replB = $mB.Groups[1].Value + "else`n`t`tdat += {`"$blackDiv`"}"
  $skB = $skB.Remove($mB.Index, $mB.Length).Insert($mB.Index, $replB)
  [IO.File]::WriteAllText($skyrat, $skB, (New-Object Text.UTF8Encoding($false)))
  Write-Host "  [ok] 天关版: 主菜单背景改为纯黑（不再显示 SPLURT 那张图）"
} else { Write-Host "  [skip] 天关版背景已处理" }

# ---------- 3. 运行期自检日志（TG-DIAG）----------
# 目的：大厅是否真的用了天关版 HTML、图标能不能从磁盘找到，都写进 data\server.log，
#       玩家一开服就能看到，不用靠猜。看到 TG-DIAG 行就说明这些代码真的在跑。
$np = Join-Path $SrcDir 'modular_skyrat/modules/title_screen/code/new_player.dm'
if (-not (Test-Path $np)) { throw "patch-lobby: 找不到 $np" }

$sk3 = [IO.File]::ReadAllText($skyrat, [Text.Encoding]::UTF8)
if ($sk3 -notmatch 'TG-DIAG html_start') {
  $m2 = [regex]::Match($sk3, '(?m)^(\t+)var/dat = SStitle\.title_html')
  if (-not $m2.Success) { throw "patch-lobby: 找不到 `var/dat = SStitle.title_html`（无法插入 TG-DIAG）" }
  $tab2 = $m2.Groups[1].Value
  # 注意：DM 的字符串插值里不能嵌套双引号（"…[fexists("x")]…" 会把字符串截断），
  #       所以先算成布尔变量再插值 —— 代码库惯例也是用 {"..."} 规避这个问题。
  $diag = @(
    ($tab2 + 'var/tgdiag_wiki = fexists("modular_tianguan/modules/tg_lobby/icons/wiki.png")'),
    ($tab2 + 'var/tgdiag_art = fexists("modular_skyrat/modules/title_screen/icons/loading_screen.gif")'),
    ($tab2 + 'log_world("TG-DIAG html_start state=[SSticker.current_state] preamble_len=[length(dat)] wiki_fexists=[tgdiag_wiki] art_fexists=[tgdiag_art]")')
  ) -join "`n"
  $sk3 = $sk3.Remove($m2.Index, $m2.Length).Insert($m2.Index, $m2.Value + "`n" + $diag)
  [IO.File]::WriteAllText($skyrat, $sk3, (New-Object Text.UTF8Encoding($false)))
  Write-Host "  [ok] 天关版: 已插入 TG-DIAG 起始日志"
} else { Write-Host "  [skip] 天关版已有 TG-DIAG" }

$npTxt = [IO.File]::ReadAllText($np, [Text.Encoding]::UTF8)
if ($npTxt -notmatch 'TG-DIAG final_html') {
  $m3 = [regex]::Match($npTxt, '(?m)^(\t+)var/dat = get_title_html\(\)')
  if (-not $m3.Success) { throw "patch-lobby: 找不到 `var/dat = get_title_html()`（无法插入 TG-DIAG）" }
  $tab3 = $m3.Groups[1].Value
  $diag2 = @(
    ($tab3 + 'log_world("TG-DIAG final_html len=[length(dat)]")'),
    ($tab3 + 'if(dat) text2file(dat, "data/tg_lobby_debug.html")')
  ) -join "`n"
  $npTxt = $npTxt.Remove($m3.Index, $m3.Length).Insert($m3.Index, $m3.Value + "`n" + $diag2)
  [IO.File]::WriteAllText($np, $npTxt, (New-Object Text.UTF8Encoding($false)))
  Write-Host "  [ok] update_title_screen: 已插入 TG-DIAG + HTML 落盘（data/tg_lobby_debug.html）"
} else { Write-Host "  [skip] update_title_screen 已有 TG-DIAG" }

# ---------- 4. 自检（改完必须验，别信"写成功"） ----------
$zzAfter = [IO.File]::ReadAllText($zzplurt, [Text.Encoding]::UTF8)
$skAfter = [IO.File]::ReadAllText($skyrat, [Text.Encoding]::UTF8)
if ($zzAfter -match '(?m)^\s*/mob/dead/new_player(/proc)?/get_title_html\s*\(') { throw "自检失败：zzplurt 里仍有 get_title_html() 覆盖" }
if ($zzAfter -notmatch 'tg_lobby_suppressed')                { throw "自检失败：zzplurt 里没有 tg_lobby_suppressed()" }
if ($skAfter -notmatch 'if\(tg_lobby_suppressed\(\)\)')      { throw "自检失败：天关版没有接上守卫" }
if (([regex]::Matches($skAfter, 'get_title_html\(\)')).Count -lt 1) { throw "自检失败：天关版 get_title_html() 不见了" }

Write-Host "  [verify] 天关大厅 HTML 现在是唯一的 get_title_html() 实现"
Write-Host ("  [verify] 天关版行数 = {0}，zzplurt 版行数 = {1}" -f `
  ($skAfter -split "`n").Count, ($zzAfter -split "`n").Count)
