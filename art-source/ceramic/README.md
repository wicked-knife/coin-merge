# 陶瓷美术源文件

本目录通过 `.gdignore` 排除于 Godot 游戏资源扫描。`masters/` 保存 10 张 imagegen 原输出，`cutouts/` 保存去品红背景的中间件。游戏使用 `assets/reskin/ceramic/` 中的派生资源。

本轮使用 imagegen 技能的用户已授权 CLI 路径，请求模型为 `gpt-image-2.5`，未上传原作图片。先检查 `pilot.jsonl` 的硬币与面板，再运行 `remaining.jsonl`，最多两个并发请求。精确提示词保存在 `prompts.json`，源输出尺寸、摘要和派生关系见 `docs/reskin/mapping.json`。

在项目根目录重建提示词与资源：

```powershell
python -X utf8 tools/prepare_ceramic_prompts.py
# 仅需要重新请求母版时运行；运行时读取本机 Codex 配置，不在项目保存凭据。
# CODEX_HOME 设置时应使用其路径，否则默认为 ~/.codex。
$ceramicCodexDir = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$ceramicLauncher = Join-Path $ceramicCodexDir 'skills/.system/imagegen/scripts/image_gen_codex.py'
python -X utf8 $ceramicLauncher generate-batch --input art-source/ceramic/pilot.jsonl --out-dir art-source/ceramic/masters --concurrency 2 --max-attempts 1
# 检查两张试制母版后再执行其余八张。
python -X utf8 $ceramicLauncher generate-batch --input art-source/ceramic/remaining.jsonl --out-dir art-source/ceramic/masters --concurrency 2 --max-attempts 1
python -X utf8 tools/build_ceramic_skin.py
```

母版已存在时只运行最后一条即可派生，无需再次请求 API。脚本从冻结的 `docs/reskin/before.json` 读取目标画布尺寸，不使用原作图像像素制作新资源；旧图仅用于生成换皮前缩略图索引。

`fonts/` 中的全量 Noto Sans SC 是下载缓存，已加入 Git 忽略；游戏只分发改名的子集与 OFL 许可证。字体来源 URL、源字体和子集 SHA-256 在 `assets/reskin/ceramic/fonts/provenance.json`。重新制作字体执行 `tools/build_ceramic_font.py`，然后重新导入、检查缺字并更新截图。

重新导入和完成流程检查后，执行 `tools/build_ceramic_report.py` 更新台账与边缘检查图。`before.json` 是换皮前基线，勿用新扫描结果覆盖。
