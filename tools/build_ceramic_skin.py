"""Derive game-ready ceramic artwork from original imagegen masters and geometry.

Original assets are read only for the evidence contact sheet; sizes come from the
frozen dependency manifest. They are never inputs to generation or derivation.
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'art-source/ceramic'
OUT = ROOT / 'assets/reskin/ceramic'
DOC = ROOT / 'docs/reskin'
FONT = OUT / 'fonts/CoinMergeUI.ttf'
INK = '#394b4d'
CREAM = '#f5f0e5'
PALETTE = ['#e3be68', '#d98a78', '#e8b8ac', '#8eb4d1', '#88c8c5',
           '#b1a0cf', '#c0cd86', '#e4ad79', '#b99882', '#8fb798', '#889fca',
           '#d3a7bf', '#b9c5a8', '#d2bc98', '#a7bfcb']
MASTERS = {}
RECORDS = []
S = 4


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def cutout(name):
    """Unmix magenta at antialiased boundaries, with neutral edge despilling."""
    src = Image.open(ART / 'masters' / (name + '.png')).convert('RGB')
    pixels = []
    for r, g, b in src.getdata():
        key = min(r, b)
        a = min(1., max(0., (g - 8) / max(1, key - 8)))
        if a < .035:
            pixels.append((0, 0, 0, 0))
        else:
            rr = max(0, min(255, round((r - (1 - a) * 255) / a)))
            bb = max(0, min(255, round((b - (1 - a) * 255) / a)))
            gg = max(0, min(255, round(g / a)))
            # Original masters are ivory: remove residual colored edge fringe.
            if a < .98:
                rr = min(rr, gg + 18)
                bb = min(bb, gg + 10)
            pixels.append((rr, gg, bb, round(255 * a)))
    result = Image.new('RGBA', src.size)
    result.putdata(pixels)
    bbox = result.getchannel('A').point(lambda a: 255 if a > 100 else 0).getbbox()
    if not bbox:
        raise ValueError('Empty master: ' + name)
    result = result.crop(bbox)
    result.save(ART / 'cutouts' / (name + '.png'))
    return result


def tint(im, color):
    rgb = Image.new('RGB', (1, 1), color).getpixel((0, 0))
    gray = ImageOps.grayscale(im)
    # Retain generated relief while keeping the main face close to the palette.
    rgb_im = ImageOps.colorize(gray,
        tuple(round(c * .42) for c in rgb),
        tuple(min(255, round(c * 1.06 + 6)) for c in rgb))
    rgb_im.putalpha(im.getchannel('A'))
    return rgb_im


def master(name, size, color=None, margin=1, contain=False):
    im = MASTERS[name].copy()
    if color:
        im = tint(im, color)
    inner = (max(1, size[0] - 2 * margin), max(1, size[1] - 2 * margin))
    if contain:
        im = ImageOps.contain(im, inner, Image.Resampling.LANCZOS)
    else:
        im = im.resize(inner, Image.Resampling.LANCZOS)
    canvas = Image.new('RGBA', size)
    canvas.alpha_composite(im, ((size[0] - im.width) // 2, (size[1] - im.height) // 2))
    return canvas


def geometry(size, painter):
    im = Image.new('RGBA', (size[0] * S, size[1] * S))
    d = ImageDraw.Draw(im)
    painter(d, im.width, im.height)
    return im.resize(size, Image.Resampling.LANCZOS)


def round_box(size, color=CREAM, edge='#c8c1b1', radius=.2, outline=2):
    return geometry(size, lambda d, w, h: d.rounded_rectangle(
        (S, S, w-S-1, h-S-1), radius=int(min(w, h)*radius), fill=color,
        outline=edge, width=outline*S))


def glyph(size, kind, color=INK):
    def draw(d, w, h):
        sw = max(S * 2, round(min(w, h)*.075))
        if kind == 'lock' or kind == 'unlock':
            box = (w*.2, h*.44, w*.8, h*.92)
            d.rounded_rectangle(box, radius=w*.10, fill=color)
            if kind == 'lock':
                d.arc((w*.29,h*.08,w*.71,h*.68), 180, 360, fill=color, width=sw)
            else:
                d.arc((w*.4,h*.04,w*.88,h*.65), 155, 350, fill=color, width=sw)
            d.ellipse((w*.46,h*.6,w*.54,h*.7), fill=CREAM)
        elif kind == 'tick':
            d.line([(w*.17,h*.51),(w*.41,h*.76),(w*.85,h*.2)], fill=color, width=sw*2, joint='curve')
        elif kind == 'close':
            d.line([(w*.32,h*.32),(w*.68,h*.68)], fill=color,width=sw)
            d.line([(w*.68,h*.32),(w*.32,h*.68)], fill=color,width=sw)
        elif kind == 'gear':
            cx,cy=w*.5,h*.48
            for a in range(8):
                rad=a*math.tau/8
                d.line([(cx+math.cos(rad)*w*.19,cy+math.sin(rad)*w*.19),
                        (cx+math.cos(rad)*w*.32,cy+math.sin(rad)*w*.32)], fill=color,width=sw*2)
            d.ellipse((cx-w*.25,cy-w*.25,cx+w*.25,cy+w*.25),fill=color)
            d.ellipse((cx-w*.11,cy-w*.11,cx+w*.11,cy+w*.11),fill=CREAM)
        elif kind == 'play':
            d.rounded_rectangle((w*.08,h*.15,w*.92,h*.85),radius=w*.13,outline=color,width=sw)
            d.polygon([(w*.42,h*.31),(w*.42,h*.69),(w*.68,h*.5)],fill=color)
        elif kind == 'arrow':
            d.polygon([(w*.04,h*.12),(w*.96,h*.12),(w*.5,h*.9)],fill=color)
        elif kind == 'right':
            d.polygon([(w*.12,h*.06),(w*.9,h*.5),(w*.12,h*.94)],fill=color)
        elif kind == 'flag':
            d.line([(w*.22,h*.14),(w*.22,h*.88)],fill=color,width=sw)
            d.polygon([(w*.25,h*.12),(w*.86,h*.2),(w*.68,h*.4),(w*.25,h*.43)],fill='#83aaa0')
        elif kind == 'crown':
            d.polygon([(w*.12,h*.28),(w*.32,h*.46),(w*.5,h*.08),(w*.68,h*.46),
                       (w*.88,h*.28),(w*.78,h*.84),(w*.22,h*.84)],fill='#ba9753')
        elif kind == 'spark':
            d.polygon([(w*.5,0),(w*.64,h*.36),(w,h*.5),(w*.64,h*.64),
                       (w*.5,h),(w*.36,h*.64),(0,h*.5),(w*.36,h*.36)],fill=color)
        elif kind == 'question':
            f = ImageFont.truetype(str(FONT), round(h*.94))
            d.text((w*.5,h*.43),'?',font=f,fill=color,anchor='mm')
    return geometry(size,draw)


def ring(size, color, width=3, filled=None):
    return geometry(size, lambda d,w,h: d.ellipse((S*2,S*2,w-S*2-1,h-S*2-1),fill=filled,outline=color,width=width*S))


def glow(size, streak=False, rays=False):
    im=Image.new('RGBA',size)
    data=[]
    for y in range(size[1]):
        for x in range(size[0]):
            nx=(x+.5-size[0]/2)/(size[0]/2)
            ny=(y+.5-size[1]/2)/(size[1]/2)
            r=(nx*nx+ny*ny)**.5
            if streak:
                a=math.exp(-((nx-ny*.35)/.15)**2)*max(0,1-abs(ny))
            else:
                a=max(0,1-r)**2
                if rays:
                    a*=.35+.65*abs(math.cos(math.atan2(ny,nx)*9))**8
            data.append((255,255,255,round(a*255)))
    im.putdata(data)
    return im


def logo(size, english=False):
    # New horizontal ceramic emblem over two lines of licensed type.
    im=Image.new('RGBA',size)
    coin=master('coin-angle',(int(size[0]*.39),int(size[1]*.30)),PALETTE[0],contain=True)
    im.alpha_composite(coin,((size[0]-coin.width)//2,int(size[1]*.07)))
    draw=ImageDraw.Draw(im)
    lines=['COIN','MERGE'] if english else ['合并硬币']
    for i,line in enumerate(lines):
        fs=int(size[0]*(.18 if english else .20))
        f=ImageFont.truetype(str(FONT),fs)
        while draw.textbbox((0,0),line,font=f)[2] > size[0]*.90:
            fs-=1
            f=ImageFont.truetype(str(FONT),fs)
        draw.text((size[0]/2,size[1]*(.47+i*.20)),line,fill=INK,font=f,anchor='mm')
    if not english:
        f=ImageFont.truetype(str(FONT),int(size[0]*.06))
        draw.text((size[0]/2,size[1]*.67),'COIN MERGE',font=f,fill='#6b8380',anchor='mm')
    return im


def derive(rel,size):
    name=Path(rel).name
    if '/normal/' in rel or '/war/' in rel:
        number=int(Path(rel).stem.removeprefix('War'))
        return master('coin-angle',size,'#a5ada9' if number==16 else PALETTE[number-1],margin=0),'coin-angle'
    if '/big/' in rel:
        return master('coin-front',size,PALETTE[int(Path(rel).stem[7:])-1],contain=True),'coin-front'
    if name=='BG.png':
        return Image.open(ART/'masters/background.png').convert('RGBA').resize(size,Image.Resampling.LANCZOS),'background'
    if name.startswith('could'):
        im=master('cloud',size,contain=False)
        if name=='could2.png': im=ImageOps.mirror(im)
        return im,'cloud'
    if name.startswith('logo_'):
        return logo(size,name=='logo_en.png'),'coin-angle + OFL font'
    if name=='Box2.png': return master('tray',size),'tray'
    if name=='PanelBG.png': return master('panel',size),'panel'
    if name in ['LevelBG.png','Partten.png']:
        im=master('card',size,'#dce5db' if name=='Partten.png' else '#f0e9dc')
        if name=='Partten.png':
            tick=glyph((int(size[0]*.7),int(size[1]*.4)),'tick','#537f70')
            im.alpha_composite(tick,(int(size[0]*.15),int(size[1]*.28)))
        return im,'card + geometry'
    if name=='BG_Choose.png':
        return geometry(size,lambda d,w,h: d.rounded_rectangle((S,S,w-S-1,h-S-1),radius=14*S,outline='#6c9e92',width=3*S)),'geometry'
    if name.startswith('BG_') and 'Trench_Merge' not in name:
        colors={'BG_Trench.png':'#e3ddd0','BG_Lock.png':'#d3d1c9','BG_Lock2.png':'#e4d7b5','BG_Lock_AD.png':'#d1e2dc'}
        return master('slot',size,colors[name]),'slot'
    if name=='BG_Trench_Merge.png':
        return geometry(size,lambda d,w,h: d.rounded_rectangle((S,S,w-S-1,h-S-1),radius=16*S,outline='#c0a05e',width=3*S)),'geometry'
    if name=='Bg_Mask.png': return Image.new('RGBA',size,CREAM),'geometry'
    if name=='CoinMask.png': return round_box(size,'white','white',.3),'geometry'
    if name.startswith('Guide_Mask'):
        return round_box(size,'white','white',.08,0),'geometry'
    if name=='Guide_Hand.png': return master('hand',size,contain=True),'hand'
    if name.startswith('Btn_') and name not in ['Btn_Quit.png','Btn_Setting_2acdf23c.png']:
        colors={'Btn_Begin_38px.png':'#b2cec2','Btn_War_24px.png':'#dfc99a',
                'Btn_blue_25px.png':'#b0ceca','Btn_yellow_25px.png':'#e4cb99',
                'Btn_green_25px.png':'#b4cbaa','Btn_Ad_broad.png':'#d4c2df','Btn_Deal.png':'#aac7be'}
        return master('button',size,colors[name]),'button'
    if name in ['Btn_Quit.png','Btn_Setting_2acdf23c.png']:
        im=round_box(size,'#eee8da','#c5c6b9',.48)
        im.alpha_composite(glyph(size,'close' if name=='Btn_Quit.png' else 'gear'))
        return im,'geometry'
    if name in ['Set_broad.png','Set_broad_2.png','Set_btn.png','TargetBar.png','ProcessBG.png','CoinBg.png']:
        color='#a1c1b4' if name=='Set_broad_2.png' else '#dedace' if name=='Set_broad.png' else CREAM
        return round_box(size,color,radius=.48),'geometry'
    if name=='Gold_Small.png': return master('coin-front',size,PALETTE[0],contain=True),'coin-front'
    symbols={'Icon_Lock.png':'lock','Icon_Unlock.png':'unlock','Unlock.png':'unlock','Flag.png':'flag',
             'Icon_ad_2.png':'play','Tick.png':'tick','ColorArrow.png':'arrow',
             'TargetArrow1.png':'right','Icon_QuestionMark.png':'question','TargetBG_4_d27bfba7.png':'crown'}
    if name in symbols:
        color='white' if name=='ColorArrow.png' else '#567c70' if name=='Tick.png' else INK
        return glyph(size,symbols[name],color),'geometry + OFL font' if name=='Icon_QuestionMark.png' else 'geometry'
    if name.startswith('Icon_spot'):
        return ring(size,'#79988c',2,'#79988c' if name=='Icon_spot_1.png' else '#e4e3d8'),'geometry'
    if name in ['TargetBG_1.png','TargetBG_2.png','TargetBG_5.png','TargetBG_4_b515ca35.png']:
        color='#bdbbad' if name=='TargetBG_1.png' else '#ac8d54'
        im=ring(size,color,3,'#e8e2d6' if name!='TargetBG_2.png' else None)
        if name=='TargetBG_5.png': im.alpha_composite(glyph(size,'tick','#628474'))
        return im,'geometry'
    if name in ['LaserLight.png','TargetBG_4.png','Light1.png','atom.texture.png']:
        return glow(size,streak=name=='LaserLight.png',rays=name=='TargetBG_4.png'),'geometry gradient'
    if name in ['Pieces1.png','Pieces2.png']:
        return glyph(size,'spark','white'),'geometry'
    raise ValueError('No derivation for '+rel)


def contact_sheet(rows,filename,new=True):
    cw,ch=180,160
    sheet=Image.new('RGB',(cw*7,ch*math.ceil(len(rows)/7)),CREAM)
    draw=ImageDraw.Draw(sheet)
    font=ImageFont.truetype(str(FONT),12)
    for i,row in enumerate(rows):
        path=row.get('replacement') if new else row['original']
        if not path or Path(path).suffix=='.svg': continue
        im=Image.open(ROOT/path).convert('RGBA')
        im=ImageOps.contain(im,(cw-18,ch-44),Image.Resampling.LANCZOS)
        x,y=i%7*cw,i//7*ch
        sheet.paste(im,(x+(cw-im.width)//2,y+5),im)
        draw.text((x+6,y+ch-35),Path(path).name,font=font,fill=INK)
        draw.text((x+6,y+ch-19),str(i+1).zfill(3)+' · '+row['method'][:22],font=font,fill=INK)
    sheet.save(DOC/filename)


def main():
    (ART/'cutouts').mkdir(exist_ok=True)
    for path in sorted((ART/'masters').glob('*.png')):
        if path.stem!='background': MASTERS[path.stem]=cutout(path.stem)
    required={'coin-angle','panel','coin-front','tray','slot','button','card','cloud','hand'}
    if required-MASTERS.keys(): raise ValueError('Missing masters: '+str(required-MASTERS.keys()))
    baseline=json.loads((DOC/'before.json').read_text(encoding='utf8'))
    for old in baseline['images']:
        path=old['path']
        row={'original':path,'original_sha256':old['sha256']}
        if '/fonts/' in path:
            row.update(replacement=None,method='removed: TTF',status='removed')
        else:
            rel=path.removeprefix('assets/rea_original/')
            target=OUT/rel if path!='icon.svg' else OUT/'app-icon.png'
            if path=='icon.svg':
                im=round_box((256,256),'#eee8da','#d2c6aa',.22)
                im.alpha_composite(master('coin-angle',(204,145),PALETTE[0]),(26,65))
                method='coin-angle + geometry'
            else:
                im,method=derive(rel,tuple(old['size']))
            target.parent.mkdir(parents=True,exist_ok=True)
            im.save(target,optimize=True)
            row.update(replacement=target.relative_to(ROOT).as_posix(),method=method,
                       sha256=sha(target),size=list(im.size),alpha_bbox=im.getchannel('A').getbbox(),status='replaced')
        RECORDS.append(row)
    (OUT/'palette.json').write_text(json.dumps({'challenge':PALETTE[:11],'normal':PALETTE,
        'ink':INK,'cream':CREAM},indent=2)+'\n',encoding='utf8')
    manifest={'model':'gpt-image-2.5','mode':'imagegen CLI generate-batch',
              'input_images':[], 'prompts':'art-source/ceramic/prompts.json',
              'masters':[{'path':p.relative_to(ROOT).as_posix(),'sha256':sha(p),'size':list(Image.open(p).size)}
                         for p in sorted((ART/'masters').glob('*.png'))],
              'derivation':'tools/build_ceramic_skin.py','palette':PALETTE,'assets':RECORDS}
    (DOC/'mapping.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    contact_sheet(RECORDS,'contact-after.jpg')
    contact_sheet(RECORDS,'contact-before.jpg',False)
    print(f'Built {sum(r["status"]=="replaced" for r in RECORDS)} replacements; removed old font atlas.')


if __name__=='__main__':
    main()
