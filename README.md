# 天关13 · Windows 一键开服包

> 基于 [TianguanStation/Tianguan13](https://github.com/TianguanStation/Tianguan13) 自动构建。
> 已编译好的服务器 + 便携 BYOND 引擎 + 官方全量汉化（zh-Hans），解压即玩。

**[⬇ 下载最新版](https://github.com/rrrrrede1/tianguan13-server-pack/releases/latest)**　·　[所有版本](https://github.com/rrrrrede1/tianguan13-server-pack/releases)　·　[上游仓库](https://github.com/TianguanStation/Tianguan13)

> 带 `Latest` 徽章的那条就是最新版；`.../releases/latest` 这个地址永远指向最新。

---

## 一、这是什么

一份**解压就能跑的 SS13 私服**，适合：

- 想体验天关13 中文内容 / 玩法更新的玩家
- 想自己测试某个功能、某张地图、某套配置的人
- 想拉几个朋友开个局域网 / 公网小服的人

包里有：

| 内容 | 说明 |
|---|---|
| `tgstation.dmb` / `tgstation.rsc` | **已编译好的服务器本体**，不需要任何工具就能跑 |
| `byond/` | 便携版 BYOND 引擎（含 `dreamdaemon.exe` 服务端、`dreamseeker.exe` 客户端），绿色免安装 |
| `config/` | 服务器配置（服务器名、中文开关、管理员名单等） |
| `tgui/`、`html/` | 已构建好的游戏内界面（聊天框、电脑、状态面板） |
| `strings/`、`icons/`、`sound/`、`_maps/` | 中文翻译库、图标、音效、地图 |
| `start_server.bat`、`stop_server.bat`、`setup_admin.bat` | 开服 / 停服 / 加管理员 |

**这个包不含源码。** 需要源码请下同一 Release 里的 `TianGuan13-Source-*.zip`（AGPL 要求同页提供）。

---

## 二、快速开始（3 步）

1. **解压**到任意目录，路径建议纯英文，例如 `D:\TianGuan13\`（部分工具在中文路径下会出问题）
2. 双击 **`start_server.bat`** 启动服务器
3. 等窗口出现类似下面的字样就说明开好了（首次约 1–3 分钟）：

   ```
   Initializations complete within 156.7 seconds!
   ```

启动后会开两个窗口：

- **DreamDaemon 窗口** = 服务器本体
- **命令窗口** = 实时日志（也是你确认有没有开好的地方），关掉它不影响服务器

**本机连接：**

- 装并登录 [BYOND 客户端](https://www.byond.com/download)（免费），或直接用包内 `byond\bin\dreamseeker.exe`
- 地址栏输入 `byond://127.0.0.1:1337`
- 本机连接**自动获得管理员权限**（`config/config.txt` 里 `ENABLE_LOCALHOST_RANK` 默认开启）

**局域网朋友连接：** 把 `127.0.0.1` 换成你的内网 IP（`ipconfig` 查看），例如 `byond://192.168.1.50:1337`，并确保 Windows 防火墙放行 1337 端口（首次启动弹窗选「允许」）。

**公网朋友连接：** 路由器上把 **1337/TCP** 转发到这台电脑，或使用内网穿透工具。

---

## 三、怎么停服

双击 **`stop_server.bat`**，它会依次结束：

1. 服务器进程（`dreamdaemon.exe`）
2. **BYOND 托盘后台程序**（右下角那个 BYOND 小图标）

第二步别省：那个托盘图标是 BYOND 的 pager 后台程序，和服务器是两个进程，只关服务器它不会自己退出。手动停服就是——先关 DreamDaemon 窗口，再到托盘图标上右键 → Exit。

---

## 四、管理员设置（给其他玩家）

双击 `setup_admin.bat`，输入对方的 BYOND 账号名（登录名，全小写），会写进 `config\admins.txt`：

```
对方账号 = Host
```

改完**重启服务器**生效。`Host` 是最高权限，其它权限等级见 `config/admin_ranks.txt`。

> `admins.txt` 支持每行一个 `账号 = 权限`，可以手动编辑一次加多人。

---

## 五、常用配置（`config\config.txt`）

| 配置项 | 本包默认 | 说明 |
|---|---|---|
| `SERVERNAME` | `天关13 本地测试服` | 服务器名（游戏顶部显示） |
| `I18N_SERVER_LOCALE` | `zh-Hans` | **全服中文开关**，改成 `en` 切英文 |
| `ENABLE_LOCALHOST_RANK` | 开 | 本机连接自动给管理员 |
| `LOBBY_COUNTDOWN` | `120` | 回合开始倒计时（秒） |
| `I18N_CHAT_FALLBACK` | 关 | 对聊天里残留英文做自动替换，偶尔误翻，默认关 |
| 端口 | `1337` | 在 `start_server.bat` 里改 `PORT=` 那行 |

其它配置：`config\game_options.txt`（玩法）、`config\maps.txt`（地图）、`config\tianguan\`（天关专属数据）。

**默认不连数据库。** 玩法和存档都不需要它，正常开服不用管。也**不要**去 `config\dbconfig.txt` 里打开 `SQL_ENABLED`——没有建库的情况下每次登录都会刷报错。

---

## 六、改代码后重新编译（进阶）

这个包不含源码。要改代码：

1. 下载同一 Release 的 `TianGuan13-Source-*.zip`，把里面的源码解压到服务器目录（和 `tgstation.dmb` 同级）
2. 用编辑器改 `code/`、`modular_tianguan/modules/` 等目录下的 `.dm`
3. **先停服**（否则编译会因 `.rsc` 被占用而失败），然后双击 `build_server.bat`
4. 看到 `0 errors` 后重新开服

**编译必须带 `-DCBT`，而且 `-DCBT` 必须写在 `tgstation.dme` 前面。** `build_server.bat` 已经写对了；命令行手编要写全：

```
byond\bin\dm.exe -DCBT tgstation.dme
```

顺序写反时编译器会**静默忽略** `-DCBT`，照样报 `0 errors`，但游戏里所有电脑/控制台图标会变成红色 error 方块，日志里毫无报错。

改了 `tgui/` 下的 TypeScript 界面还需要 Node 工具链：`tgui/` 目录里 `bun install` 然后 `bun run tgui:build`。只改 DM 不需要。

---

## 七、常见问题

**Q：双击没反应 / 窗口一闪就没了？**
路径里有中文或空格最常见，换到 `D:\TianGuan13` 这类路径。

**Q：卡在开头，迟迟没有 `Initializations complete`？**
首次启动要初始化地图、大气、光照，1–3 分钟正常。看命令窗口最后几行，报错会写在那里。

**Q：提示缺少 dll / 程序无法启动（0xC0000135）？**
早期版本的问题。现在的包已内置 VC++ 和 DirectX 运行库，不需要额外安装；还报的话是下到了旧版本。

**Q：右上角状态面板一片白，没有「状态 / 管理 / IC / OOC」标签？**
同样是早期版本的问题（漏打了状态面板的网页文件），换最新版。

**Q：关了窗口，托盘里 BYOND 图标还在？**
正常现象，那是 BYOND 的 pager 后台程序，不属于服务器。右键它 Exit，或用 `stop_server.bat` 停服，会一并清掉。

**Q：端口被占用？**
`netstat -ano | findstr :1337` 找到 PID，任务管理器结束它；或改 `start_server.bat` 里的 `PORT=`。

**Q：朋友连不上？**
先确认防火墙放行 TCP 1337（控制面板 → Windows Defender 防火墙 → 高级设置 → 入站规则），公网还要做路由器端口转发。

**Q：编译报 `.rsc` 被锁 / 文件被占用？**
服务器还在跑。停服，等 3~5 秒再编译。

**Q：内存占用看着很高？**
启动后实测约 2.3 GB（32 位进程，上限本来就紧）。建议机器留 4 GB 以上可用内存，人多时多留意。

**Q：为什么界面还有零星英文？**
官方翻译在持续更新，个别新增字符串可能还没翻译，属正常现象。

---

## 八、这个包相对上游做了什么

包体由 GitHub Actions 自动构建，每一步都可追溯（构建细节见 [docs/BUILD.md](docs/BUILD.md)）。相对上游源码，打包时做了这些处理：

1. **补运行库**：把 x86 VC++ 运行库和 DX9 的 `d3dx9_43.dll`/`D3DCompiler_43.dll` 打进 `byond\bin`，玩家端无需安装任何运行库
2. **修大厅**：上游编译时 `modular_zzplurt` 里一份 5 行的同路径重定义会覆盖天关大厅的界面代码，导致大厅空白；打包时改名为不覆盖，并移除失效的侧栏展示图、主菜单背景改纯黑
3. **补运行时资源**：`html/`（状态面板的网页文件）、大厅图标、字体等——这些是运行时从磁盘读的，官方最小部署清单不包含
4. **配置**：追加 `SERVERNAME` 与 `I18N_SERVER_LOCALE zh-Hans`
5. **发版前冒烟**：每次构建都会真启动一次服务器，等到 `Initializations complete` 才打包

---

## 九、许可

- 上游代码以 **AGPL-3.0** 分发，全文见 [LICENSE](LICENSE)。
- 对应源码在同一 Release 的 `TianGuan13-Source-*.zip` 里，请与二进制一同分发、保留版权声明。
- 本包是非官方社区包，与上游无隶属关系，仅供个人 / 社区测试使用。

游戏内容来自 [TianguanStation/Tianguan13](https://github.com/TianguanStation/Tianguan13)，及其上游的 /tg/station、Skyrat、Bubber、SPLURT 等社区。
