# 构建说明

这份文件是给维护者的。玩家只需要看根目录的 [README](../README.md)。

这个仓库**不含源码**，只有打包脚本和启动器。每次构建都从源码仓库现场拉取指定 commit，编译、组装、真启动一次验收，然后打包发版。

## 触发方式

| 方式 | 结果 |
|---|---|
| CT124 同步上游后 `repository_dispatch`（`event_type=source-updated`，带精确 sha） | 自动构建 + 发 `server-<短sha>` 的 Release |
| Actions → Run workflow，填 `ref`（分支 / tag / 完整或短 sha）、`release_tag` 留空 | 只上传 Artifact，不发 Release |
| Run workflow 且填 `release_tag` | 构建 + 发到指定 tag |
| 往本仓库推 `server-*` 的 tag | 构建 + 发 Release（源码 ref 取 `main`） |

不发 Release 的手动运行适合验证改动，不会污染 Release 页面。

## 流水线做了什么

| # | 步骤 | 为什么必须这样 |
|---|---|---|
| 1 | `Resolve source ref` | `actions/checkout` 不认短 sha，先用 API 补全成 40 位 |
| 2 | 浅克隆源码（`fetch-depth: 1`） | 仓库历史 3.5 GB，全量拉取不现实 |
| 3 | 从 `dependencies.sh` 读 BYOND / Bun 版本 | 版本单一来源，硬编码会在上游升版后悄悄坏掉 |
| 4 | 下载 BYOND（缓存 + 429 重试） | byond.com 会限流 |
| 5 | 安装 x86 VC++ 运行库并**找到** DLL | 安装器可能返回 1638（已装更新版本），所以还要去 `SysWOW64` / VS 的 `VC\Redist` 里把 `mfc140u.dll` 等捞出来 |
| 6 | 构建 tgui / tgfont（绕过 `biome-install`） | `biome-install` 只服务 lint，却是 `tgui` 目标的硬依赖，实测会因 tarball 损坏把 tgui 连带拖死 |
| 7 | **大厅补丁**（`scripts/patch-lobby.ps1`） | 见下节 |
| 8 | `bun tools/build/build.ts dm` | 它内部负责 cutter 下载 → 图标切割 → 行为树(Python) → `dm.exe -DCBT`。别手敲 `dm.exe`，会漏掉图标切割 |
| 9 | `bash tools/deploy.sh` 组装 | 官方最小运行清单 |
| 10 | 补 VC++ / DX9 运行库 | BYOND 的 zip 不自带 MFC 和 `d3dx9_43.dll`，缺了 `dreamdaemon` 直接 `0xC0000135` 秒退；打进 `byond\bin`（app-local）后玩家也不用装 |
| 11 | 补大厅资源 + **运行时磁盘资源** | 见下节 |
| 12 | **审计 `file("...")` 字面路径** | 代码里运行时从磁盘读的文件，包里缺一个就静默坏一块功能，所以逐个比对，缺了就 fail |
| 13 | 冒烟测试（真启动） | 用 `dd.exe` 跑到 `Initializations complete`，不看这一条等于把"能编译但跑不起来"的包发给玩家 |
| 14 | 打包 + 源码归档 + SHA256 | AGPL 要求同页提供对应源码 |
| 15 | Artifact（总是）+ Release（按触发方式） | 手动跑默认不污染 Release |

## 大厅补丁：为什么需要

上游 `tgstation.dme` 里编了**三份** title screen 实现，同路径 proc 后者覆盖前者：

```
modular_skyrat/modules/title_screen/...  (天关定制大厅，564 行)  ← 第 9103 行
modular_zubbers/.../title_screen_subsystem.dm                    ← 第 10475 行
modular_zzplurt/.../new_player/title_screen_html.dm              ← 第 11042 行（最后编译）
```

`modular_zzplurt` 那个文件只有 5 行，重新定义了 `get_title_html()`，会把天关版整段覆盖；而它的 `..()` 只能调到父类型 `/mob`（没有这个 proc），于是返回 null，大厅浏览器渲染成空白。**编译是 `0 errors`，BYOND 静默覆盖，没有任何报警。**

`scripts/patch-lobby.ps1` 在编译前改**工作区里的 `src/`**（不碰源码仓库）：

- 把 zzplurt 那份改名成 `tg_lobby_suppressed()`，保留它"启动期/自定义载入条时不显示大厅"的原意，并在天关版 `get_title_html()` 开头调用
- 移除侧栏展示图（天关没有横幅尺寸的素材，只有 32×32 的 logo；原来会回落到 SPLURT 的 `PLEASE WAIT` gif）
- 主菜单背景改成纯黑（原来用的是 SPLURT 的 `splurt_banner_background.png`）
- 顺带注入 `TG-DIAG` 日志和 `data/tg_lobby_debug.html` 落盘（调试用，正式版可以去掉）

脚本是幂等的，跑第二遍会 `[skip]`，改完自带自检。

## 运行时磁盘资源：deploy.sh 管不到的那批

`tools/deploy.sh` 只拷 dmb/rsc/地图/图标/声音/tgui。但代码里有一批文件是**运行时用 `file()` / `fexists()` 从磁盘读**的，必须单独补：

| 目录 | 缺了会怎样 |
|---|---|
| `html/`（statbrowser + changelogs + jquery + font-awesome） | 右上状态面板全白、没有"状态/管理/IC/OOC"标签（statbrowser 的 html/js/css 就在这里） |
| `modular_tianguan/modules/tg_lobby/{icons,sound}` | 大厅侧栏图标、按钮音效缺失 |
| `modular_skyrat/modules/title_screen/icons` | 大厅载入图缺失 |
| `interface/fonts/`、`modular_zh/modules/i18n/fonts/`、`tgui/packages/tgui-escape-menu/styles/` | 字体/样式缺失 |

`Audit runtime disk files` 步骤会扫 `src/**/*.dm` 里所有 `file("...")` 字面路径，只要仓库里有、包里没有就报错——上游以后新增这类文件时，构建会直接失败而不是发出一个坏包。

## 踩过的坑

**`dreamdaemon.exe` 在无头 runner 上会卡死。** 它是 GUI 程序，60 秒后仍存活、零输出、不写日志。同一个包里 `dd.exe`（控制台版）23 秒就 `World loaded`。所以冒烟测试用 `dd.exe`；玩家端仍用 GUI 版，桌面环境体验更好。

**BYOND 的 zip 不自带运行库。** `dreamdaemon.exe` 依赖 `mfc140u.dll`（VC++ x86），而 `byondwin.dll` 又依赖 `d3d9.dll` + `d3dx9_43.dll`（DirectX June 2010）。缺任何一个都 `0xC0000135` 秒退，而开发机装了这些运行库时**完全复现不出来**。

**`set -o pipefail` + `curl | grep -m1` = SIGPIPE。** `grep -m1` 提前退出会让 curl 报 `curl: (23) Failure writing output to destination`，整步中止。改用 bash 正则解析。

**`git -C src archive -o <相对路径>` 会把 zip 写进 `src/` 里**（`-C` 先切目录），git 返回 0 但文件不在你以为的地方。要给绝对路径。

**冒烟结束后必须清运行时产物。** 服务器还握着 `tgstation.dyn.rsc` / `data\server.log` 时，7z 会报 "The process cannot access the file" 而失败。现在会杀进程、等退出、删运行时产物，并给 7z 三次重试。

**`for ($i...) { } | Tee-Object` 非法**；`? :` 是 PowerShell 7 语法，本地 5.1 验不过。

## 本地复现

```powershell
# 假定源码已经 checkout 到 .\src
$env:DM_EXE = "C:\path\to\byond\bin\dm.exe"
bun tools/build/build.ts dm
bash tools/deploy.sh ../out/TianGuan13_Server
./scripts/smoke-test.ps1 -PackageDir out/TianGuan13_Server
```

## 目录

```
.github/workflows/package-windows.yml   主流水线
scripts/patch-lobby.ps1                 编译前的大厅补丁（幂等 + 自检）
scripts/smoke-test.ps1                  真启动一次并等 Initializations complete
scripts/tianguan-sync.sh                CT124 上跑的那份同步器（同步 fork + 触发打包）
launcher/*.bat                          放进包里的三个启动脚本
```
