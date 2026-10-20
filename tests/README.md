# 普通模式验证

## 陶瓷图片与字体换皮

运行资源位于 `assets/reskin/ceramic/`，来源、逐项映射、许可证、原资源摘要与截图见 [换皮清单](../docs/实际引用图片与换皮清单.md)。图片和字体已替换，14 种原作音效仍需授权或重制。原图片与字体保留为历史证据并由 `.gdignore` 排除。

```powershell
python -X utf8 tools/audit_image_usage.py --output docs/reskin/after.json --check
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-method gl_compatibility --script res://tests/ceramic_skin_test.gd -- --visual
```

专项检查覆盖 42 张动态币图的加载与尺寸、11 组币面与箭头配色、所有翻译字符和禁用系统字体回退。`--visual` 另保存中英菜单、设置与配色图到 `docs/reskin/after/`，使用临时设置对象，不保存玩家偏好。现有挑战流程的锁关关闭检查仍有 1 项基线失败，换皮没有新增失败。

## 普通模式规则与流程

在项目根目录使用 Godot 4.7（Windows 使用带 `_console.exe` 的命令）运行：

```powershell
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/normal_game_test.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/game_flow_test.gd
```

规则测试覆盖固定教程、连续顶部选择、部分搬运、隐藏币揭示、10→2 合并、五阶段推进、发牌分布与容量约束、满盘救援、重试、存档验证和文件替换。

贯通测试把鼠标和触摸事件送入真实 Godot 视口，跑完教程、发牌、批量合并、目标解锁、救援、下一大关、设置重开与重新进入后的恢复。测试使用独立的 `user://normal_game_ui_test.json`，不会覆盖正常进度。

需要渲染预览时运行：

```powershell
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-method gl_compatibility --script res://tests/game_flow_test.gd -- --visual
```

静态预览写入 `previews/normal-mode-*.png`，连续帧写入 `previews/normal-alignment/`。可使用 `python tools/build_motion_previews.py` 汇总为画面条带和动图。预览产物已加入 Git 忽略规则，不随代码提交。

## 运行入口与广告预留

运行 `scenes/main_menu.tscn`，点击「开始游戏」；也可以直接运行 `scenes/game.tscn`。正常进度保存在 `user://normal_game.json`，返回菜单、重进场景或重新启动后恢复。

`Game.bypass_reward_ads` 默认开启：普通模式奖励槽与后两次整理直接放行，方便完整试玩玩法。以后关闭该开关，连接 `reward_requested(placement, completion)`，平台处理后调用 `completion.call(earned)` 即可；取消和失败不会授予奖励或扣整理次数。未接入广告 SDK、插屏或计费。

## 挑战模式

从主菜单点击「挑战一下」进入每页 16 项的 4×4 选关，也可直接运行 `scenes/challenge_menu.tscn`。左右滑动或鼠标拖动翻页，页面跟随手指，松手吸附；短拖与首尾越界回弹，滑动不触发卡片点击，也支持键盘左右键。每次打开回到首页，共 7 页；第 101 项是待更新占位。锁关可以点击查看所需硬币，并跳转普通模式。解锁条件读取普通存档的历史最高硬币等级；首关始终可玩，第二关要求达到 8 级。首次进入首关先显示文档中的三个槽教学盘，完成后自动进入正式首关。

点击源槽、目标槽搬运顶部连续同色币。每槽最多 10 枚，容量不足时部分搬运；正常搬运不成立时，两个未完成的整摞纯色币可以互换，数量可以不同。按箭头颜色装满才打勾并锁定，挑战中不升级、不发牌、不判满盘失败。大棋盘按原版 680×1084 区域、110×200 槽和 45/60 间距自动适配；不再用常驻缩放和导航压缩棋盘。

正式挑战盘面、隐藏标记、累计耗时、首次金币和最佳纪录单独保存在 `user://challenge_game.json`。每次动作及退出时保存，计时每 5 秒补存；关闭再进入继续当前盘面。设置支持语言、音效、振动、重开和返回主页，保留已选中的币组；教学期间忽略重开。教学只在首关无纪录且没有正式盘存档时触发，不保存教学断点；旧教学存档迁移时清盘，保留金币和纪录。续局立即继续计时，不播入场；重开、下一关和教学转正式盘播放 0.8 秒水平切盘及币入场，这段时间不计时。完成关先展示隐藏勾的棋盘，点击屏幕再打开纪录和重玩；只查看纪录不会覆盖另一关的进行中存档。首次完成且下一关已解锁才提供下一关，其余结算返回选关。第 100 关完成后保存内部 101 待更新标记。

规则与输入测试（使用独立测试存档，不覆盖正常游戏进度）：

```powershell
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/challenge_game_test.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/challenge_flow_test.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/challenge_settings_input_test.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-method gl_compatibility --script res://tests/challenge_settings_input_test.gd -- --narrow
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-method gl_compatibility --script res://tests/challenge_flow_test.gd -- --visual
```

规则测试逐关对照原始 100 关配置，每关生成五个随机盘，核对容量、可见顶部、隐藏组数及逐色库存；另覆盖部分搬运、异色整摞交换、完成锁定、计时、首次奖励、纪录更新、末关、损坏存档及恢复。输入测试通过真实视口跑通分页、鼠标/触摸、教学、交换、揭示、重开、续玩、通关、下一关、纪录和 208 槽棋盘，并验证飞行动画中退出后的恢复。渲染图输出到 `previews/challenge-*.png`。

运行配置已嵌入 `scripts/challenge_data.gd`，导出游戏不依赖被 `.gdignore` 排除的参考文档。需要根据参考资料重建时运行 `python tools/build_challenge_data.py`。

设置输入测试在教学盘、正式首关、208 槽棋盘和已完成关卡上，通过真实鼠标与触摸事件打开设置、切换中英文、点击右上角 X 关闭并再次打开。语言切换使用不写磁盘的临时设置对象，测试不修改用户偏好；`--narrow` 使用 390×844 竖屏尺寸。

挑战入口按捕获版本直接放行。成功弹窗打开时发出 `interstitial_requested("war-level-complete")`，并通过 `challenge_platform.gd` 尝试调用当前 Web 宿主的 `ytgame.ads.requestInterstitialAd()`；桌面或无 SDK 环境正常继续，桥接未注入 SDK，真实 YouTube 宿主广告与生命周期仍需环境验收。分享/视频分享沿用原发布版的直接返回选关行为。没有人为给中性空槽加广告锁。生成器沿用文档的库存、隐藏段和加权分组算法，并给原作 50 轮填充上限增加库存守恒的兜底。和捕获版本一样，随机盘没有形式化的可解性保证。


平台桥接模拟测试（直接执行生产脚本中的 JavaScript，不需要真实广告）：

```powershell
node --test tests/challenge_platform_test.cjs
```

本轮实施与已知边界见 `docs/挑战模式_差异实施记录_2026-10-19.md`。此前 REA 取证目录和生成对照探针保留为历史证据；其中的手写 JS 本地生成器描述的是修正前版本，不能拿其结果冒充当前 GDScript 运行结果。

## 多语言专项（11种语言）

支持英语、俄语、韩语、日语、印尼语、法语、西班牙语、葡萄牙语、阿拉伯语、简体和繁体中文。设置优先；无设置时查询 YouTube 语言，2 秒超时或独立运行回退英语。旧 `zh`/`en` 自动兼容。详细实现和验收边界见 [多语言实施与验证](../docs/多语言实施与验证_2026-10-20.md)。

```powershell
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/localization_test.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-method gl_compatibility --script res://tests/localization_test.gd -- --visual --narrow
node --test tests/language_platform_test.cjs tests/challenge_platform_test.cjs
```

专项覆盖全部译文、格式参数、换行、原生语言名称与字形、禁用系统字体回退、缺资源回退、旧设置迁移、保存重载、宿主检测单次调用、手动选择与异步返回竞态、生产轮询超时，以及真实鼠标/触摸选择、拖动滚动、焦点环绕和 Esc 返回。对菜单、普通教程/选中币/救援、挑战选关/锁关/教程/正式盘/完成关纪录/结果，检查语言即时刷新和状态保持。使用独立测试设置与存档，不覆盖玩家偏好和进度。

`--visual --narrow` 以 390×844 窗口生成全部语种界面截图，保存在忽略提交的 `previews/localization/`。同时比较选中硬币堆显示/隐藏时弹窗覆盖区域的像素，确认普通和挑战模式的设置、语言弹窗均盖住悬浮硬币；关闭设置后保留选中硬币和教程步骤。这些截图由 Godot Compatibility 实际渲染；YouTube 桥接测试使用模拟 SDK，不代表真实宿主已验收。

翻译表是运行时来源。`python -X utf8 tools/build_translations.py` 复用原作取证文案并补齐本项目新增文案；`python -X utf8 tools/build_ceramic_font.py` 重建六组 Noto 字体子集和回退资源。工具需要参考资料或下载缓存，导出游戏仅依赖 `translations/` 和 `assets/reskin/ceramic/fonts/`。
