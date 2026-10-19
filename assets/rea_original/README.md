# 原作发布资源

请先阅读项目根目录的[美术资源获取说明](../../美术资源获取说明.md)与[可搜索预览](../../美术资源预览.html)。

- sprites：还原成独立透明PNG的界面/硬币图片与云朵部件。
- audio：原MP3音效。
- atlases：原纹理页面。
- fonts：数字BMFont。
- spine：原Spine骨骼文件、atlas和贴图，需要兼容运行时/动画移植。
- particles：原粒子plist、提取参数与关联纹理。
- reference：原编译包、动画数据、来源和依赖记录；Godot忽略导入。
- sprite_manifest.json：图片的原逻辑路径、尺寸、旋转、trim与九宫格参数。

普通贴图中的数字由Label另画；普通小币101×67，大币164×172。来源为Tidy Coins 3D的公开发布构建，文件身份与未知项见获取说明。

当前主界面改用自定义的 `sprites/ui/logo_zh.png`（中文）与 `sprites/ui/logo_en.png`（英文），随语言设置切换。旧的 `sprites/ui/logo.png` 和对应 atlas 运行副本已删除；原始捕获文件保留在 `reference/cocos-published/assets/resources/native/e2/`。原作资源清单记录获取时的文件与来源，不随自定义素材替换而重写。
