# Coin Merge Web 试玩版

Cloudflare Pages 项目：`coin-merge-play`。固定入口：<https://coin-merge-play.pages.dev/>。

此地址用于独立浏览器试玩和提交表单的可玩链接。普通模式和挑战模式均使用当前游戏实现；无需 YouTube SDK 或账号登录。进度和设置保存在当前站点的浏览器存储中，不跨设备同步。首次打开默认英语，可在设置中选择已有的11种语言。

## 构建和部署

使用 Godot 4.7.2 与同版本 Web 导出模板。在项目根目录运行：

```powershell
python -X utf8 tools/export_web.py --godot 'D:/godot/Godot_v4.7.2-stable_win64_console.exe'
npx wrangler@4.149.0 pages deploy build/web --project-name coin-merge-play --branch main --commit-dirty=true
```

部署依赖已经登录且有该项目访问权限的 Cloudflare CLI。构建工具不读取 Cloudflare 凭据。后续更新沿用同一项目和 `main` 生产分支，固定入口保持不变。构建目录为 `build/web/`，文件摘要与大小记录在 `build/web-manifest.json`，Godot 日志在 `build/web-export.log`。

Web 采用单线程、Compatibility 渲染，不要求 SharedArrayBuffer 或跨源隔离响应头。自定义 HTML 页面适配手机可视区域，宽屏居中显示竖屏画面，展示加载进度和启动失败重试按钮。未启用离线 Service Worker，以避免试玩期间留存旧版本缓存。

原始引擎文件为39,514,754字节，超过 Pages 单文件25 MiB上限。构建工具将引擎和资源包预压缩为 `.gz`，发布目录约16.12 MiB，最大文件约9.61 MiB。`web/worker.js` 通过 Pages 的 ASSETS 绑定流式提供压缩内容，并使用 `encodeBody: "manual"` 避免重复压缩。`_routes.json` 只让 `/index.wasm` 和 `/index.pck` 经过该处理脚本，其余文件按静态资源提供。这两个入口的请求属于 Pages Functions 请求；本项目未开通额外存储或数据库。

导出排除编辑器插件、测试、取证文档、美术母版、工具和历史图片；导出插件同时去除编辑器的 MCP autoload。构建检查确认插件已去除、每个静态文件不超过25 MiB，并验证压缩后的内容可无损解压。现有14种游戏音效的权利待办仍见[资源清单](实际引用图片与换皮清单.md)，本次部署未更改音效素材。

## 本地与公网检查

启动与生产一致的 Pages 本地服务器：

```powershell
npx wrangler@4.149.0 pages dev build/web --port 8788
```

浏览器专项使用 Playwright 和 Chromium。运行环境需要可解析 `playwright` 包；可通过 `NODE_PATH` 指向已有依赖。若使用已有 Chromium，可设置 `PLAYWRIGHT_CHROMIUM_PATH`。运行：

```powershell
node tests/web_smoke_test.cjs http://127.0.0.1:8788/ build/web-checks
node tests/web_smoke_test.cjs https://coin-merge-play.pages.dev/ build/web-live-checks
```

每次检查使用独立浏览器上下文，覆盖1280×900桌面鼠标和390×844手机触摸模拟，保存菜单、设置、普通模式、挑战模式和尺寸调整后的截图。检查通过真实输入完成普通教程、两次10→2合并、发牌、刷新后续玩、挑战教程及正式第一关，并读取浏览器 IndexedDB 验证存档。检查也验证设置中的声音偏好保存、压缩响应头和运行时错误。机器结果写入各输出目录的 `verification.json`。

此次 Web 适配将 JavaScriptBridge 的0/1结果显式转换为布尔值，修复了Web端振动检测、语言检测及广告可用状态的类型错误，并保留无宿主时的英语回退。原生语言回归检查通过21,315项，语言与广告JavaScript模拟检查14项通过；带脚本诊断的Web调试版启动和打开设置未出现运行错误。

2026-10-20 17:00（北京时间）公网复验通过：固定入口在桌面鼠标和手机触摸模拟两种环境下均完成上述交互与存档检查，未记录运行时错误。结果保存在 `build/web-live-checks/verification.json`，截图位于同一目录。Cloudflare API 确认生产部署 `382b1955-a3c1-4c8c-baa2-90d7aba7b921` 的状态为 `success`；对应版本地址为 <https://382b1955.coin-merge-play.pages.dev/>。本地同范围检查也已通过。

验证范围不包含iOS Safari或Android真机、100个挑战关卡的逐关求解，也不代表已完成YouTube宿主的SDK、云存档、生命周期和正式平台验收。该链接可独立试玩，YouTube正式提交包仍需按平台要求继续适配。

参考：[Godot Web 导出](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html)、[Pages Direct Upload](https://developers.cloudflare.com/pages/get-started/direct-upload/)、[Pages 文件限制](https://developers.cloudflare.com/pages/platform/limits/)、[Workers Response 的 encodeBody](https://developers.cloudflare.com/workers/runtime-apis/response/)。
