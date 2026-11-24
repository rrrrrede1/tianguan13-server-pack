# 天关13 · Windows 一键包流水线

把一个 commit 变成「解压双击 `start_server.bat` 就能开服」的 Windows 包，并可选发布到 Release。
**只用事件触发**（`workflow_dispatch` / 打 tag），不用 `schedule`——本环境已实测定时器不可靠。

## 目录

```
.github/workflows/package-windows.yml   # 主流水线
scripts/smoke-test.ps1                  # 打包后"真启动一次"的验收脚本
launcher/*.bat                          # 放进包里的三个启动脚本
```

## 触发方式

| 方式 | 结果 |
|---|---|
| 往**源码仓库**打 tag `server-*` 并推送 | 自动构建 + 发布 Release |
| Actions → Run workflow，填 `ref`（commit/tag/branch） | 只上传 Artifact（除非同时填 `release_tag`） |
| Run workflow 且填 `release_tag` | 构建 + 发布到该 tag |

> 注意：`push: tags` 里的 tag 是**本仓库**的 tag；若想让源码仓库的 tag 触发，需要在源码仓库里 `repository_dispatch` 过来（或改成在源码仓库里也放一份 workflow）。默认设计是**本仓库打 tag 打包源码仓库的任意 ref**——这样可以给历史上的任意 commit 出包。

## 流水线做了什么（顺序与理由）

| # | 步骤 | 为什么必须这样 |
|---|---|---|
| 1 | `checkout` 源码仓库到 `src/`，`fetch-depth: 1` | 仓库历史 3.5GB，浅克隆是硬要求 |
| 2 | 从 `dependencies.sh` 读 BYOND / Bun 版本 | 版本有单一来源；硬编码会在上游升版后悄悄坏掉 |
| 3 | 下载 BYOND `_byond.zip`（Windows 版）+ 缓存 + 429 重试 | byond.com 会限流（实测老版本直接 429） |
| 4 | `setup-bun`（版本来自 `dependencies.sh`） | tgui 构建需要 Bun |
| 5 | 构建 tgui + tgfont（**直接跑脚本，绕过 `biome-install`**） | `biome-install` 只服务 lint，却是 `tgui` 目标的硬依赖；实测它会因 tarball 损坏失败并连带 tgui 失败 |
| 6 | `bun tools/build/build.ts dm` | 它内部负责 cuter 下载 → 图标切割 → 行为树(Python) → `dm.exe -DCBT tgstation.dme`；**别手敲 dm.exe**，否则漏图标切割 |
| 7 | 断言：`dmb`/`rsc` 存在、`tgui/public ≥ 10`、`tgfont.css` 存在 | 编译"成功"但界面没构建是最常见的半成品 |
| 8 | `bash tools/deploy.sh` 组装 | 官方最小运行清单，含 modular 图标与三个 dll（Msys 分支才会拷 dll） |
| 9 | 复制 `byond/`、`config/`、三个 `.bat`、空 `data/` | 引擎 + 配置 + 外壳 |
| 10 | **追加** `SERVERNAME` 与 `I18N_SERVER_LOCALE zh-Hans` | 仓库的 `config.txt` **没有这两行**，且代码默认 `LANGUAGE_LOCALE_EN`；不追加就是英文服 |
| 11 | 镜像 `src` 里**所有** `sound/` 目录 | `deploy.sh` 只拷 `sound/runtime`，而 `rust_g` 算音频时长要读磁盘 ogg → 否则 `play_ambience` 刷 runtime（实测） |
| 12 | 烟雾测试：真启动到 `Initializations complete` | 不看这一条，等于把"编译成功但跑不起来"的包发给玩家 |
| 13 | `7z` 压 zip + `git archive` 出源码 zip + SHA256 | AGPL-3.0 要求同页可取得对应源码；同页附源码最稳 |
| 14 | Artifact（总是）+ Release（显式触发才发） | 手动跑不污染 Release |

## 已知取舍

- **只用 Windows runner**：BYOND 的 Windows 引擎 + 仓库里自带的 `rust_g.dll`/`dreamluau.dll`/`auxlua.dll` 都是 Windows 二进制；公开仓库跑 windows runner 不花钱（按 2 倍计费但公开仓库免费）。
- **不跑 lint / 不跑测试**：这是"出包"流水线，不是 CI 质量门；上游自己的 CI 已经在做。
- **不缓存 `src/`**：源码 + node_modules 每次重建最干净，代价约 2–3 分钟。
- **包体约 600–700MB**（含全量 sound 与地图），zip 后约 350–450MB。Release 单附件上限 2GB，不构成问题。

## 首次上线需要验证的 3 件事

1. **`deploy.sh` 在 windows runner 的 Git Bash 下能跑通**（`uname -o` 是否为 `Msys`，决定三个 dll 是否被拷）。
2. **`bun tools/build/build.ts dm` 在没有 `BUILD.bat` 引导的情况下能跑**（`DM_EXE` 指向解压出来的 `byond\byond\bin\dm.exe`）。
3. **烟雾测试能通过**（首次初始化约 131 秒；脚本给了 8 分钟窗口）。

> 这三条在本地都验证过等价路径，但在 GitHub runner 上是第一次跑，可能需要 1–2 轮微调（路径/编码类问题）。

## 本地复现（不上传、只验证脚本逻辑）

```powershell
# 假定已经在本地把源码 checkout 到 .\src
$env:DM_EXE = "C:\path\to\byond\bin\dm.exe"
bun tools/build/build.ts dm
bash tools/deploy.sh ../out/TianGuan13_Server
./scripts/smoke-test.ps1 -PackageDir out/TianGuan13_Server
```
