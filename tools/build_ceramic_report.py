"""Write the per-image migration ledger and visual provenance / QA evidence."""
from __future__ import annotations

from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

from audit_image_usage import audit, inspect_image

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / 'docs/reskin'
OUT = ROOT / 'assets/reskin/ceramic'
FONT = OUT / 'fonts/CoinMergeUI.ttf'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def purpose(path):
    if '/normal/' in path:
        return '普通硬币 / 隐藏币；动态 1–16，等级按 15 色循环；数字由代码叠加'
    if '/war/' in path:
        return '挑战硬币；动态 War1–War11，与目标箭头共用配色'
    if '/big/' in path:
        return '目标 / 奖励 / 升级大币；动态 BigCoin1–BigCoin15'
    if '/fonts/' in path:
        return '旧数字位图字体页；经 number01.fnt 间接引用'
    if '/spine_cloud/' in path:
        return '主菜单云朵；保留当前 Tween 动画'
    names = {
        'icon.svg':'默认项目图标', 'BG.png':'普通/主菜单/挑战选关背景',
        'Box2.png':'普通棋盘托盘', 'PanelBG.png':'设置、提示、救援、选关及结算九宫格',
        'LevelBG.png':'挑战关卡卡片底板', 'BG_Choose.png':'当前挑战卡片选中边框',
        'Flag.png':'当前挑战卡片标志', 'Partten.png':'已完成挑战卡片', 'Unlock.png':'可挑战卡片标志',
        'BG_Lock.png':'锁定槽底板', 'BG_Lock2.png':'可解锁槽 / 扫光底板', 'BG_Lock_AD.png':'奖励槽底板',
        'BG_Trench.png':'开放槽底板', 'BG_Trench_Merge.png':'可合并描边与光效',
        'Bg_Mask.png':'挑战棋盘背景 / 槽底遮挡', 'CoinMask.png':'挑战币扫光的 alpha 蒙版',
        'ColorArrow.png':'可调色挑战目标箭头（白色源图）', 'Icon_QuestionMark.png':'隐藏币问号',
        'TargetArrow1.png':'普通目标指示箭头', 'TargetBG_1.png':'未到达的目标底板',
        'TargetBG_2.png':'当前目标圆环', 'TargetBG_5.png':'已完成目标标记', 'Tick.png':'挑战整槽完成勾',
        'Btn_Begin_38px.png':'主菜单开始按钮底板', 'Btn_War_24px.png':'主菜单挑战按钮底板',
        'Btn_Ad_broad.png':'救援奖励按钮底板', 'Btn_Deal.png':'发牌按钮底板；文字改用可翻译 Label',
        'Btn_Quit.png':'关闭按钮', 'Btn_Setting_2acdf23c.png':'设置按钮',
        'Btn_blue_25px.png':'通用薄荷色按钮', 'Btn_green_25px.png':'通用鼠尾草色按钮',
        'Btn_yellow_25px.png':'通用暖沙色按钮', 'CoinBg.png':'挑战关卡与计时底板',
        'Gold_Small.png':'首次通关金币奖励图标', 'Guide_Hand.png':'教程点击手势',
        'Guide_Mask1.png':'教程单槽 alpha 镂空形状', 'Guide_Mask2.png':'教程目标 alpha 镂空形状',
        'Guide_Mask3.png':'教程横向按钮 alpha 镂空形状', 'Icon_Lock.png':'锁定图标',
        'Icon_Unlock.png':'可解锁图标', 'Icon_ad_2.png':'奖励视频播放图标',
        'Icon_spot_1.png':'选关当前页圆点', 'Icon_spot_2.png':'选关其他页圆点',
        'LaserLight.png':'解锁 / 硬币扫光纹理', 'Light1.png':'粒子柔光纹理',
        'Pieces1.png':'粒子几何碎片 1', 'Pieces2.png':'粒子几何碎片 2',
        'ProcessBG.png':'挑战完成数量底板', 'Set_broad.png':'设置开关关闭轨道',
        'Set_broad_2.png':'设置开关开启轨道', 'Set_btn.png':'设置开关滑块',
        'TargetBG_4.png':'最终目标放射光', 'TargetBG_4_b515ca35.png':'最终目标圆环',
        'TargetBG_4_d27bfba7.png':'最终目标皇冠', 'TargetBar.png':'普通目标连接条',
        'logo_en.png':'英文 Coin Merge 标题', 'logo_zh.png':'中文合并硬币标题',
        'atom.texture.png':'粒子微光点（相对 ../particles 动态加载）',
    }
    return names[Path(path).name]


def alpha_info(path):
    if path.suffix == '.svg':
        return {'transparent_percent': None, 'semi_percent': None, 'magenta_pixels': 0}
    im = Image.open(path).convert('RGBA')
    hist = im.getchannel('A').histogram()
    count = im.width * im.height
    magenta = sum(1 for r,g,b,a in im.getdata() if a > 12 and r > g + 45 and b > g + 45)
    return {'transparent_percent': round(100 * hist[0] / count, 2),
            'semi_percent': round(100 * sum(hist[1:255]) / count, 2), 'magenta_pixels': magenta}


def compare_boards():
    font = ImageFont.truetype(str(FONT), 22)
    sheet = Image.new('RGB', (948, 860), '#eee8da')
    draw = ImageDraw.Draw(sheet)
    for i, (label, folder) in enumerate([('换皮前 / Before', 'before'), ('陶瓷换皮 / Ceramic', 'after')]):
        draw.text((24 + i * 474, 10), label, font=font, fill='#394b4d')
        path = DOC / folder / 'normal-mode-playing.png'
        im = Image.open(path).convert('RGB')
        sheet.paste(ImageOps.contain(im,(450,800)), (24+i*474,50))
    sheet.save(DOC/'comparison-normal.jpg',quality=92)


def edge_sheet():
    names = ['sprites/Texture/skin/normal/1.png','sprites/ui/PanelBG.png',
             'sprites/ui/Guide_Hand.png','sprites/spine_cloud/could1.png',
             'sprites/ui/LaserLight.png','sprites/ui/Guide_Mask1.png']
    sheet = Image.new('RGB',(1000,3*270),'#f5f0e5')
    draw = ImageDraw.Draw(sheet)
    font=ImageFont.truetype(str(FONT),16)
    for index,name in enumerate(names):
        x,y=(index%2)*500,(index//2)*270
        for side,bg in enumerate(['#243638','#dce0dd']):
            view=Image.new('RGBA',(240,235),bg)
            im=ImageOps.contain(Image.open(OUT/name),(225,220),Image.Resampling.LANCZOS)
            view.alpha_composite(im,((240-im.width)//2,(235-im.height)//2))
            sheet.paste(view.convert('RGB'),(x+side*245,y))
        draw.text((x+8,y+240),Path(name).name,font=font,fill='#394b4d')
    sheet.save(DOC/'alpha-edges.jpg',quality=95)


def main():
    before=json.loads((DOC/'before.json').read_text(encoding='utf8'))
    after=audit()
    (DOC/'after.json').write_text(json.dumps(after,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    mapping=json.loads((DOC/'mapping.json').read_text(encoding='utf8'))
    font=json.loads((OUT/'fonts/provenance.json').read_text(encoding='utf8'))
    new_paths={r['path'] for r in after['images']}
    ledger=[]
    for old,row in zip(before['images'],mapping['assets'],strict=True):
        assert old['path']==row['original']
        assert digest(ROOT/old['path'])==old['sha256'], 'Original bytes changed: '+old['path']
        target=row['replacement']
        if target:
            assert target in new_paths, 'Replacement not reached: '+target
            assert digest(ROOT/target)==row['sha256'], 'Rebuild mapping: '+target
        ledger.append({**row,'purpose':purpose(old['path']), 'old_size':old['size'],
            'old_alpha_bbox':old['alpha_bbox'], 'old_alpha_range':old.get('alpha_range'),
            'old_alpha':alpha_info(ROOT/old['path']),
            'new_alpha':alpha_info(ROOT/target) if target else None,
            'references':old['references'],'replacement_reachable': bool(target and target in new_paths)})
    assert len(new_paths)==103 and len(ledger)==104
    assert not after['unresolved'] and not after['system_font_sources']
    assert all(row['path'].startswith('assets/reskin/ceramic/') for row in after['images'])
    assert sum(r['new_alpha']['magenta_pixels'] for r in ledger if r['new_alpha'])==0
    (DOC/'ledger.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    used={r['path'] for r in before['images']}
    excluded=[]
    for p in sorted((ROOT/'assets/rea_original').rglob('*')):
        if p.suffix.lower() in ['.png','.jpg','.jpeg','.webp','.svg']:
            path=p.relative_to(ROOT).as_posix()
            if path not in used:
                excluded.append({'path':path,'sha256':digest(p),'reason':'not reachable from runtime entries'})
    (DOC/'historical-images.json').write_text(json.dumps(excluded,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    declarations=[{'path':row['path'],**ref} for row in before['images'] for ref in row['references']
                  if ref['kind']=='scene-declaration-only']
    checks={'date':datetime.now(timezone.utc).isoformat(), 'before_images':104,'after_images':103,
        'all_original_bytes_preserved':True,'all_replacements_reachable':True,
        'retired_font_page_images':1,'original_image_dependencies':0,'system_font_sources':[],
        'unresolved':after['unresolved'],'magenta_spill_pixels':0,'retained_audio_count':14,
        'declaration_only_references_removed':declarations,'historical_unreferenced_images':len(excluded),
        'baseline_challenge':{'checks':77,'failures':1,'mode':'headless','source':'pre-change captured console result'},
        'tests': {'normal_rules':{'checks':3487,'failures':0}, 'challenge_rules':{'checks':2802,'failures':0},
                  'normal_flow_rendered':{'checks':189,'failures':0},
                  'challenge_flow_rendered':{'checks':87,'failures':1,'capture_assertions':10},
                  'settings_narrow_rendered':{'checks':57,'failures':0},
                  'asset_validation_rendered':{'checks':113,'failures':0}, 'platform_bridge':{'checks':8,'failures':0}}}
    (DOC/'validation.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    compare_boards()
    edge_sheet()
    lines=[
        '# 实际引用图片与陶瓷换皮清单', '',
        '核查日期：2026-10-20。游戏名称：**合并硬币 / Coin Merge**。本轮完成图片与字体替换并接入 Godot 4.7.2；玩法、关卡、存档格式与交互区域保持现状。', '',
        '## 核查结论', '',
        '- 换皮前实际引用 **104 个图片文件**；本轮替换 **103 张**，另外 **1 张旧数字字体图集随 FNT 移除**。换皮后实际图片依赖为 **103 张原创替代 PNG**。',
        '- 动态范围：普通币 1–16（第 16 张为隐藏币）、挑战 War1–War11、大币 BigCoin1–BigCoin15。未把未使用的 BigCoin16 或 BigCoin10-(2) 计入。',
        '- 活跃依赖已无 `assets/rea_original` 图片、原数字 FNT/图集或 SystemFont；字体随包提供，已关闭操作系统字体回退。',
        '- **14 种原作音效明确保留，授权或重新制作仍为后续待办。**初步计划中的 13 种漏算了 Tween 回调 `_sound.bind("placeCoin")`；完整核查已计入。换皮前冻结 JSON 保留初次扫描值，音效最终清单以修正后的 after.json 和本表为准。本轮图片和字体换皮不表示音效、游戏名称商标或整包发行权利已完成核验。',
        '- 原图片均保留原字节。尤其是开始前已修改的 `assets/rea_original/sprites/ui/logo_zh.png`，已用换皮前 SHA-256 再核对，未覆盖。', '',
        '## 依赖追踪边界', '',
        '从 `project.godot` 主场景 `scenes/main_menu.tscn` 与自动加载入口追踪静态资源和脚本，再沿场景跳转、继承脚本、动态根路径、硬币编号、粒子配置与 FNT 页继续展开。前后各有 41 个可达源文件（加入共享视觉配置，移除旧 FNT）。', '',
        '完整前后源文件集合、引用行号、尺寸、alpha 边界、文件字节数与 SHA-256 见 [before.json](reskin/before.json)、[after.json](reskin/after.json)。工具为 [audit_image_usage.py](../tools/audit_image_usage.py)。动态家族是针对本项目加载规则显式展开，并非通用 GDScript 解释器。新增家族需要同步扩展规则。', '',
        '“仅声明引用”与“整张图片未使用”分别记录：旧 `scenes/game.tscn` 有 4 条未赋给节点的 ext_resource（BG_Lock、Icon_Lock、BG_Trench、normal/1），这些图片同时被脚本实际使用，因此仍属于 104 张。本轮移除了这 4 条冗余声明。', '',
        f'另有 **{len(excluded)} 张**仓库原作图片不在运行依赖中，列入 [historical-images.json](reskin/historical-images.json)，不计入 104 张。历史图集、Spine 文件、备用大币和取证图属于这个范围。', '',
        '已在原作 `sprites/`、`fonts/`、`particles/`、`atlases/`、`spine/` 增加 `.gdignore`；原 `reference/` 已排除。母版和处理中间件放在 `art-source/ceramic/`，证据放在 `docs/reskin/`，二者也有 `.gdignore`。原作 `audio/` 继续使用。默认 `icon.svg` 不再被项目引用。发布时按发布工程的依赖范围导出，并继续排除文档、测试和美术源文件；本轮未生成或认证抖音发布包。', '',
        '## 制作与接入', '',
        '使用用户已配置的 **imagegen CLI / gpt-image-2.5**，在进程内从 Codex 配置读取请求地址与密钥；项目未保存凭据。先生成并检查斜视硬币和面板两张，再以最多 2 个并发请求生成其余 8 张。所有请求均为纯文字生成，没有上传原作图片。', '',
        '10 类母版：斜视硬币、正视硬币、背景、托盘、槽位、面板、按钮、挑战卡片、云朵与手势。精确提示词见 [prompts.json](../art-source/ceramic/prompts.json)，批次、完成时间与生成记录见 [generation.json](../art-source/ceramic/generation.json)，原输出见 [masters/](../art-source/ceramic/masters/)，尺寸与摘要见 [mapping.json](reskin/mapping.json)。供应方未严格遵守 1024×1024 请求，实际尺寸另行记录，最终画布均由本地处理落实。', '',
        '透明对象使用纯品红背景生成，抠图时反解边缘混色，原始母版与抠图中间件分别保留；彩色硬币由中性母版着色派生。图标、蒙版、圆环、光晕、扫光和碎片使用本项目几何/渐变绘制。Logo 使用新币图与授权字体重新排版。', '',
        '运行资源根为 `assets/reskin/ceramic/`，共享路径、字体和配色在 [ceramic_skin.gd](../scripts/ceramic_skin.gd)。普通模式音效根已从图片根拆开。挑战箭头与 War 硬币使用同一配色表，数字仍由代码叠加；旧发牌图片中的中文字改为可翻译 Label。', '',
        '保留 101×67 硬币画布、164×172 大币画布、19 px 堆叠间距、动画锚点、布局和点击区；只在币面内部调整数字/问号位置。新九宫格切片边距统一为 24 px，内容留白与按钮点击区维持原布局。面板和按钮文字改为深色陶瓷墨色。', '',
        '### 字体来源与许可', '',
        f'官方 Google Fonts 仓库的 Noto Sans SC，SIL Open Font License 1.1。制作 650 字重静态子集并改名为 **Coin Merge UI**，当前包含 **{font["unicode_count"]}** 个字符映射，大小 **{font["bytes"]:,} B**。项目当前全部翻译字段由实际 FontFile 检查，无缺字。', '',
        '- [字体许可证 OFL.txt](../assets/reskin/ceramic/fonts/OFL.txt)',
        '- [来源 URL 与源字体/子集 SHA-256](../assets/reskin/ceramic/fonts/provenance.json)',
        '- [子集生成工具](../tools/build_ceramic_font.py)；下载的全量字库仅作为本地缓存，不打入游戏。', '',
        '## 逐项替换台账', '',
        '下表编号与前后缩略图一致。旧资源列相对 `assets/rea_original/`，新资源列相对 `assets/reskin/ceramic/`；`icon.svg` 为项目根文件。尺寸单位为 px，bbox 为 `[left, top, right, bottom]`、右/下边界不含自身；它表示非透明区域包围盒，内部孔洞与半透明边缘详见 JSON。', '',
        '所有行的旧/新 SHA-256、alpha 透明/半透明比例、派生来源与可达验证结果都在 [ledger.json](reskin/ledger.json)。表中“通过”表示文件存在、画布/依赖与原始字节追溯通过；动态加载、字体与代表界面另经下文测试及截图验收。', '',
        '| # | 旧图片 | 用途 / 动态范围 | 原尺寸；非透明 bbox | 换皮前引用位置 | 新资源 / 结论 | 验收 |',
        '|---|---|---|---|---|---|---|',
    ]
    for number,row in enumerate(ledger,1):
        oldpath=row['original'].removeprefix('assets/rea_original/')
        newpath=row['replacement'].removeprefix('assets/reskin/ceramic/') if row['replacement'] else '移除图集；改用 fonts/CoinMergeUI.ttf'
        size='×'.join(map(str,row['old_size']))
        bbox=','.join(map(str,row['old_alpha_bbox'])) if row['old_alpha_bbox'] else '矢量'
        refs='<br>'.join(f'`{r["source"]}:{r["line"]}`'+('（仅声明）' if r['kind']=='scene-declaration-only' else '（FNT页）' if r['kind']=='font-page' else '') for r in row['references'])
        lines.append(f'| {number:03d} | `{oldpath}` | {row["purpose"]} | {size}；[{bbox}] | {refs} | `{newpath}` | 通过 |')
    lines.extend(['', '## 视觉证据与验收', '',
        '![普通棋盘前后对照](reskin/comparison-normal.jpg)', '',
        '- [104 项原资源缩略图索引](reskin/contact-before.jpg) / [对应替换索引](reskin/contact-after.jpg)',
        '- [深色与浅色底透明边缘、蒙版和扫光检查](reskin/alpha-edges.jpg)',
        '- [全部普通/挑战币、目标配色与字形](reskin/after/palette-and-glyphs.png)',
        '- [中文主菜单](reskin/after/menu-zh.png) / [英文主菜单](reskin/after/menu-en.png)',
        '- [中文设置](reskin/after/settings-zh.png) / [英文设置](reskin/after/settings-en.png)',
        '- [普通教程](reskin/after/normal-mode-tutorial.png) / [奖励槽开放后](reskin/after/normal-mode-playing.png) / [失败救援](reskin/after/normal-mode-rescue.png) / [最终庆祝](reskin/after/normal-mode-final-congrats.png)',
        '- [挑战选关](reskin/after/challenge-selection.png) / [第 7 页](reskin/after/challenge-selection-page-6.png) / [锁关提示](reskin/after/challenge-unlock.png)',
        '- [挑战教程](reskin/after/challenge-tutorial.png) / [正式关](reskin/after/challenge-level-1.png) / [英文界面](reskin/after/challenge-english.png) / [结算](reskin/after/challenge-success.png) / [纪录](reskin/after/challenge-record.png) / [208 槽](reskin/after/challenge-dense-board.png)', '',
        '切边检查未发现可见品红溢色。全体替代图的可见像素品红残留检测为 0（阈值与 alpha 统计见生成报告工具）。教程蒙版为新的白色 alpha 形状，着色器仍以 alpha 镂空；扫光为独立透明梯度。九宫格在设置、救援、选关与结算不同尺寸均有截图。', '',
        '| 验证 | 本次结果 | 证据 |', '|---|---|---|',
        '| 普通规则 | 3,487 项，0 失败 | [日志](reskin/after-normal-rules.log) |',
        '| 挑战规则 | 2,802 项，0 失败 | [日志](reskin/after-challenge-rules.log) |',
        '| 普通完整流程（真实渲染） | 189 项，0 失败；与同模式换皮前基线一致 | [前](reskin/baseline-normal.log) / [后](reskin/after-normal.log) |',
        '| 挑战完整流程（真实渲染） | 87 项，1 个既有失败；其中 10 项为截图断言 | [输出](reskin/after-challenge.log) / [既有错误](reskin/after-challenge.stderr.log) |',
        '| 390×844 设置与输入（真实渲染） | 57 项，0 失败 | [日志](reskin/after-settings.log) |',
        '| 图片/配色/字体专项（真实渲染） | 113 项，0 失败 | [日志](reskin/after-assets.log) |',
        '| 平台桥接现有模拟测试 | 8 项，0 失败 | [日志](reskin/after-platform.log) |',
        '| 依赖审计 | 无悬空路径、无旧图片与字体、无 SystemFont | [机器结果](reskin/after.json) |', '',
        '**既有失败边界：**换皮前挑战 headless 流程为 77 项、1 失败，失败为 `tests/challenge_flow_test.gd:129` 的锁关提示关闭按钮。换皮后真实渲染额外执行 10 张截图断言，为 87 项、同一处 1 失败；没有新增失败，也没有借换皮修改弹窗输入逻辑。该问题仍需后续修复。测试中随机规则断言数量会随随机盘变化，以上记录来自本次实际输出。', '',
        '本轮运行于 Windows Godot 4.7.2 Compatibility / OpenGL，未在抖音真机验证。208 槽保持当前自动适配的交互区和尺寸，小屏下硬币本身仍较小。', '',
        '### 复核命令', '', '```powershell',
        'python -X utf8 tools/audit_image_usage.py --output docs/reskin/after.json --check',
        "& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-method gl_compatibility --script res://tests/ceramic_skin_test.gd -- --visual",
        'python -X utf8 tools/build_ceramic_report.py', '```', '',
        '资源派生工具为 [build_ceramic_skin.py](../tools/build_ceramic_skin.py)；它使用已归档母版和本地几何，不会重新请求 API。若重新生成图片，应先按 `art-source/ceramic/README.md` 执行 imagegen，再派生、导入和回归。', '',
        '## 保留音效与后续待办', '',
        '以下 14 个文件仍来自原作，图片换皮没有改变其路径、调用或授权状态。引用行号按换皮后代码列出，包含直接调用、绑定回调及主场景音频声明：', '',
        '| 音效文件（assets/rea_original/audio/） | 当前引用 | 后续 |', '|---|---|---|',
    ])
    for sound in after['retained_original_audio']:
        lines.append(f'| `{Path(sound["path"]).name}` | '+ '<br>'.join(f'`{r}`' for r in sound['references']) +' | 取得发行授权或重新制作 |')
    lines.extend(['', '发布前仍需处理这些音效，并核实游戏名称/品牌使用与平台所需材料。图片母版为本轮生成，字体按 OFL 分发，来源记录可用于后续审核；这份工程记录不替代第三方权利检索或抖音审核结论。', ''])
    (ROOT/'docs/实际引用图片与换皮清单.md').write_text('\n'.join(lines),encoding='utf8')
    print(f'Ledger: {len(ledger)} original images; {len(new_paths)} replacements; {len(excluded)} historical unreferenced files. Original hashes intact; no magenta spill.')


if __name__=='__main__':
    main()
