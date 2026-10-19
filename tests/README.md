# 普通模式验证

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

本次只实现普通模式。`Game.bypass_reward_ads` 默认开启：奖励槽与后两次整理直接放行，方便完整试玩玩法。以后关闭该开关，连接 `reward_requested(placement, completion)`，平台处理后调用 `completion.call(earned)` 即可；取消和失败不会授予奖励或扣整理次数。未接入广告 SDK、插屏、计费或挑战玩法。
