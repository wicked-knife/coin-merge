from pathlib import Path
from collections import Counter, defaultdict
import base64
import hashlib
import html
import io
import json
import math
import plistlib
import re
import shutil
import sys
import zlib
from PIL import Image, ImageDraw, ImageFont
from acquire_tidy_art import ROOT, WORK, CACHE, BASE, load, save, decode_uuid, fetch_many

OUT = ROOT / 'outputs/coin-merge-art'
ART = OUT / 'assets/rea_original'
META = ART / 'reference'
REPORT = OUT / '美术资源获取说明.md'
PROJECT = Path('D:/projects/coin-merge')

def safe_name(value):
    value = re.sub(r'[<>:"/\\|?*\x00-\x1f]', '_', str(value)).strip(' .') or 'unnamed'
    if value.upper().split('.')[0] in {'CON','PRN','AUX','NUL', *{'COM'+str(i) for i in range(10)}, *{'LPT'+str(i) for i in range(10)}}:
        value = '_' + value
    return value

def read_root(data):
    instances = data[5]
    custom = data[6] if isinstance(data[6], list) else []
    marker = instances[-1]
    has_marker = isinstance(marker, int)
    root_idx = (~marker if marker < 0 else marker) if has_marker else 0
    ordinary_count = len(instances) - len(custom) - int(has_marker)
    native = has_marker and marker < 0
    if root_idx >= ordinary_count:
        kind_idx = custom[root_idx - ordinary_count]
        if kind_idx < 0:
            return 'compiled-value', {'encoded':instances[root_idx]}, native
        kind = data[3][kind_idx]
        kind = kind if isinstance(kind, str) else kind[0]
        raw = instances[root_idx]
        return kind, raw if isinstance(raw,dict) else {'custom_data':raw}, native
    raw = instances[root_idx]
    mask = data[4][raw[0]]
    schema = data[3][mask[0]]
    props = schema[1]
    values = {props[mask[i]]:raw[i] for i in range(1,len(raw))}
    return schema[0], values, native

def unpack_records():
    entries = load(WORK / 'import-inventory.json')
    cfgs = {name:load(CACHE / f'assets/{name}/config.json') for name in ['resources','main','internal']}
    records, missing = [], []
    for entry in entries:
        file = CACHE / entry['relative']
        if not file.is_file():
            missing.append(entry)
            continue
        data = load(file)
        cfg = cfgs[entry['bundle']]
        if isinstance(data,dict) and data.get('type') == 'cc.Texture2D':
            values = data['data'].split('|')
            assert len(values) == len(entry['indices'])
            bodies = [('cc.Texture2D', {'custom_data':value, '_native':'.png'}, True, []) for value in values]
        else:
            files = [data[:5]+body for body in data[5]] if entry['packed'] else [data]
            assert len(files) == len(entry['indices']), entry
            bodies = []
            for obj in files:
                kind, attributes, native = read_root(obj)
                deps = []
                for owner, prop, uid in zip(obj[8],obj[9],obj[10]):
                    prop = obj[2][prop] if isinstance(prop,int) and prop >= 0 else (~prop if isinstance(prop,int) else prop)
                    deps.append({'owner':owner,'property':prop,'uuid':decode_uuid(obj[1][uid]) if isinstance(uid,int) else decode_uuid(uid)})
                bodies.append((kind,attributes,native,deps))
        for idx, (kind,attributes,native,deps) in zip(entry['indices'],bodies):
            uuid = decode_uuid(cfg['uuids'][idx])
            config_path = cfg.get('paths',{}).get(str(idx))
            records.append({'uuid':uuid,'bundle':entry['bundle'],'config_index':idx,
                            'logical_path':config_path[0] if config_path else None,
                            'class':kind,'attributes':attributes,'native':native,'dependencies':deps,
                            'import_file':entry['relative'], 'import_url':BASE+entry['relative']})
    save(WORK / 'asset-records.json',records)
    save(WORK / 'missing-imports.json',missing)
    return records,missing

def download_native(records):
    paths = []
    for record in records:
        if record['class']=='cc.Texture2D' and '_native' not in record['attributes']:
            encoding=record['attributes']['custom_data'].split(',')[0].split('_')[0].split('@')[0]
            extensions=['.png','.jpg','.jpeg','.bmp','.webp','.pvr','.pkm','.astc']
            ext=extensions[int(encoding)] if encoding.isdigit() else encoding
            record['attributes']['_native']=ext
        ext = record['attributes'].get('_native')
        if not record['native'] or not ext:
            continue
        if ext != '.' + ext.lstrip('.') or not re.fullmatch(r'\.[a-zA-Z0-9]+',ext):
            raise ValueError(('Unexpected native extension',ext))
        uuid,bundle = record['uuid'],record['bundle']
        rel = f'assets/{bundle}/native/{uuid[:2]}/{uuid}{ext}'
        record['native_relative'] = rel
        record['native_url'] = BASE+rel
        paths.append(rel)
    results = fetch_many(paths,'native-downloads.json')
    return results

def export(records,missing,downloads):
    ART.mkdir(parents=True,exist_ok=True)
    META.mkdir(parents=True,exist_ok=True)
    (META/'.gdignore').write_text('# Analysis snapshots, not Godot runtime assets.\n',encoding='utf-8')
    by_uuid = {r['uuid']:r for r in records}
    emitted,unresolved = [],[]
    texture_paths = {}
    for record in records:
        if not record.get('native_relative'):
            continue
        src = CACHE/record['native_relative']
        if not src.exists():
            unresolved.append({'uuid':record['uuid'],'reason':'native-download-failed'})
            continue
        kind = record['class']
        if kind == 'cc.Texture2D':
            dest = ART/'atlases'/src.name
            with Image.open(src) as im:
                im.verify()
            texture_paths[record['uuid']] = dest
        elif kind == 'cc.AudioClip':
            dest = ART/'audio'/(safe_name(record['attributes'].get('_name',record['uuid']))+src.suffix)
        elif kind == 'sp.SkeletonData':
            dest = ART/'spine'/safe_name(record['attributes'].get('_name',record['uuid']))/'skeleton.skel'
        elif kind == 'cc.ParticleAsset':
            dest = ART/'particles'/(safe_name(record['attributes'].get('_name',record['uuid']))+src.suffix)
        else:
            dest = META/'native'/src.name
        dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(src,dest)
        record['exported_native'] = dest.relative_to(OUT).as_posix()
        emitted.append({'kind':kind,'file':dest.relative_to(OUT).as_posix(),'uuid':record['uuid'],
                        'source_url':record['native_url'],'sha256':hashlib.sha256(src.read_bytes()).hexdigest(),
                        'bytes':src.stat().st_size})
    previous_sprite_paths={s['file'] for s in load(ART/'sprite_manifest.json')} if (ART/'sprite_manifest.json').exists() else set()
    sprite_records=[]
    used_paths={}
    for record in records:
        if record['class'] != 'cc.SpriteFrame':
            continue
        attrs = record['attributes']
        tex = [dep['uuid'] for dep in record['dependencies'] if dep['property']=='_textureSetter']
        if len(tex)!=1 or tex[0] not in texture_paths:
            unresolved.append({'uuid':record['uuid'],'name':attrs.get('name'),'reason':'unresolved-texture','texture_dependencies':tex})
            continue
        logical = record['logical_path'] or 'ui/'+safe_name(attrs.get('name',record['uuid']))
        parts=[safe_name(p) for p in logical.split('/')]
        dest=ART/'sprites'/Path(str(Path(*parts))+'.png')
        key=str(dest).casefold()
        if key in used_paths:
            dest=dest.with_stem(dest.stem+'_'+record['uuid'][:8])
        used_paths[str(dest).casefold()] = record['uuid']
        x,y,w,h=attrs['rect']
        assert all(float(v).is_integer() for v in [x,y,w,h]),attrs
        x,y,w,h=map(int,[x,y,w,h])
        rotated=bool(attrs.get('rotated',False))
        with Image.open(texture_paths[tex[0]]) as image:
            tw,th=image.size
            physical_w,physical_h=(h,w) if rotated else (w,h)
            assert x>=0 and y>=0 and x+physical_w<=tw and y+physical_h<=th,(record,tw,th)
            crop=image.convert('RGBA').crop((x,y,x+physical_w,y+physical_h))
        if rotated:
            crop=crop.transpose(Image.Transpose.ROTATE_90)
        assert crop.size==(w,h)
        ow,oh=map(int,attrs.get('originalSize',[w,h]))
        offset=attrs.get('offset',[0,0])
        left=(ow-w)/2+offset[0]
        top=(oh-h)/2-offset[1]
        assert float(left).is_integer() and float(top).is_integer(),record
        left,top=int(left),int(top)
        assert left>=0 and top>=0 and left+w<=ow and top+h<=oh,(record,left,top,ow,oh)
        restored=Image.new('RGBA',(ow,oh))
        restored.paste(crop,(left,top))
        dest.parent.mkdir(parents=True,exist_ok=True)
        restored.save(dest)
        sprite={'uuid':record['uuid'],'name':attrs.get('name'), 'logical_path':record['logical_path'],
                'file':dest.relative_to(OUT).as_posix(),'size':[ow,oh],'texture_uuid':tex[0],
                'atlas_file':texture_paths[tex[0]].relative_to(OUT).as_posix(),
                'source_rect':[x,y,w,h],'rotated_in_atlas':rotated,'original_offset':offset,
                'restored_trim_origin':[left,top], 'cap_insets_ltrb':attrs.get('capInsets',[0,0,0,0]),
                'source_import_url':record['import_url']}
        sprite_records.append(sprite)
        record['exported_sprite']=sprite['file']
    current_sprite_paths={s['file'] for s in sprite_records}
    for relative in previous_sprite_paths-current_sprite_paths:
        stale=(OUT/relative).resolve()
        assert stale.is_relative_to((ART/'sprites').resolve())
        stale.unlink(missing_ok=True)
    save(ART/'sprite_manifest.json',sprite_records)
    save(META/'asset_records.json',records)
    save(META/'missing_imports.json',missing)
    save(META/'unresolved_exports.json',unresolved)
    save(META/'native-downloads.json',downloads)
    save(META/'import-downloads.json',load(WORK/'import-downloads.json'))
    save(META/'bootstrap-downloads.json',load(WORK/'bootstrap-downloads.json'))
    shutil.copytree(CACHE/'assets',META/'cocos-published/assets',dirs_exist_ok=True)
    # Keep engine only as static provenance; never run it during extraction.
    shutil.copy2(CACHE/'cocos2d-js-min.js',META/'cocos-published/cocos2d-js-min.js')

    # Preserve root animation curves and full compiled prefab payloads separately.
    for record in records:
        kind=record['class']
        name=safe_name(record['attributes'].get('_name',record['uuid']))
        if kind=='cc.AnimationClip':
            save(META/'cocos_animation_clips'/(name+'_'+record['uuid'][:8]+'.json'),record)
        elif kind=='cc.Prefab':
            save(META/'prefab_root_metadata'/(name+'_'+record['uuid'][:8]+'.json'),record)
        elif kind=='cc.BitmapFont':
            export_font(record,by_uuid)
        elif kind=='sp.SkeletonData':
            export_spine(record,by_uuid)
        elif kind=='cc.ParticleAsset':
            export_particle(record,by_uuid)
    summary={'records':len(records),'class_counts':dict(Counter(r['class'] for r in records)),
             'native_files':len(emitted),'sprite_pngs':len(sprite_records),
             'missing_imports':missing,'unresolved_exports':unresolved,
             'native_download_failures':[r for r in downloads if r['status']!=200],
             'native_exports':emitted}
    save(ART/'acquisition_summary.json',summary)
    return sprite_records,summary

def export_font(record,by_uuid):
    attrs=record['attributes']
    cfg=attrs['_fntConfig']
    frames=[by_uuid[d['uuid']] for d in record['dependencies'] if d['property']=='spriteFrame']
    if len(frames)!=1 or 'exported_sprite' not in frames[0]:
        return
    path=ART/'fonts'/safe_name(attrs['_name'])
    path.mkdir(parents=True,exist_ok=True)
    source=OUT/frames[0]['exported_sprite']
    image=path/'number01.png'
    shutil.copy2(source,image)
    size=Image.open(image).size
    defs=cfg['fontDefDictionary']
    lines=[f'info face="{safe_name(attrs["_name"])}" size={cfg["fontSize"]} bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=0,0',
           f'common lineHeight={cfg["commonHeight"]} base={cfg["fontSize"]} scaleW={size[0]} scaleH={size[1]} pages=1 packed=0',
           'page id=0 file="number01.png"',f'chars count={len(defs)}']
    for key,entry in sorted(defs.items(),key=lambda item:int(item[0])):
        r=entry['rect']
        lines.append(f'char id={key} x={r["x"]} y={r["y"]} width={r["width"]} height={r["height"]} xoffset={entry["xOffset"]} yoffset={entry["yOffset"]} xadvance={entry["xAdvance"]} page=0 chnl=15')
    kern=cfg.get('kerningDict',{})
    lines.append(f'kernings count={len(kern)}')
    assert not kern,'Handle kerning encoding explicitly before export'
    (path/'number01.fnt').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    save(path/'original_font_metadata.json',attrs)

def export_spine(record,by_uuid):
    attrs=record['attributes']
    path=ART/'spine'/safe_name(attrs['_name'])
    path.mkdir(parents=True,exist_ok=True)
    (path/'skeleton.atlas').write_text(attrs['_atlasText'],encoding='utf-8')
    deps=[d for d in record['dependencies'] if d['uuid'] in by_uuid and by_uuid[d['uuid']]['class']=='cc.Texture2D']
    names=attrs.get('textureNames',[])
    assert len(deps)==len(names),(deps,names)
    for dep,name in zip(deps,names):
        tex=by_uuid[dep['uuid']]
        shutil.copy2(OUT/tex['exported_native'],path/safe_name(name))
    # Also provide independently usable static PNGs for each cloud region.
    lines=attrs['_atlasText'].splitlines()
    regions=[]
    current=None
    for line in lines:
        if line and not line[0].isspace() and ':' not in line and line not in names:
            current={'name':line.strip()}
            regions.append(current)
        elif current is not None and line.startswith('  ') and ':' in line:
            key,value=line.strip().split(':',1)
            current[key]=value.strip()
    assert len(names)==1
    with Image.open(path/names[0]) as image:
        for region in regions:
            x,y=map(int,region['xy'].split(','))
            w,h=map(int,region['size'].split(','))
            rotated=region['rotate']=='true'
            pw,ph=(h,w) if rotated else (w,h)
            crop=image.convert('RGBA').crop((x,y,x+pw,y+ph))
            if rotated:crop=crop.transpose(Image.Transpose.ROTATE_90)
            dest=ART/'sprites/spine_cloud'/(safe_name(region['name'])+'.png')
            dest.parent.mkdir(parents=True,exist_ok=True)
            crop.save(dest)
    save(path/'extracted_regions.json',regions)
    save(path/'original_spine_metadata.json',record)

def export_particle(record,by_uuid):
    native=OUT/record['exported_native']
    data=plistlib.loads(native.read_bytes())
    save(ART/'particles'/'atom.parameters.json',{k:v for k,v in data.items() if k!='textureImageData'})
    if data.get('textureImageData'):
        raw=base64.b64decode(data['textureImageData'])
        try:raw=zlib.decompress(raw)
        except zlib.error:raw=zlib.decompress(raw,16+zlib.MAX_WBITS)
        with Image.open(io.BytesIO(raw)) as im:
            im.convert('RGBA').save(ART/'particles'/'atom.texture.png')
    elif data.get('spriteFrameUuid'):
        frame=by_uuid[decode_uuid(data['spriteFrameUuid'])]
        shutil.copy2(OUT/frame['exported_sprite'],ART/'particles'/'atom.texture.png')
        save(ART/'particles'/'atom.texture_source.json',{'sprite_frame_uuid':frame['uuid'],
              'exported_sprite':frame['exported_sprite'],'derivation':'Referenced spriteFrameUuid in original plist'})

def previews(sprites,summary):
    preview=OUT/'previews'
    preview.mkdir(parents=True,exist_ok=True)
    font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',16)
    titlefont=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',24)
    groups={
        'coins':[s for s in sprites if s['logical_path'] and ('/normal/' in s['logical_path'] or '/war/' in s['logical_path'] or '/big/' in s['logical_path'])],
        'ui':[s for s in sprites if not(s['logical_path'] and ('/normal/' in s['logical_path'] or '/war/' in s['logical_path'] or '/big/' in s['logical_path']))],
    }
    for name,items in groups.items():
        items.sort(key=lambda s:s['logical_path'] or s['name'])
        for page in range(math.ceil(len(items)/48)):
            subset=items[page*48:(page+1)*48]
            cols=6
            cellw,cellh=200,180
            sheet=Image.new('RGB',(cols*cellw,55+math.ceil(len(subset)/cols)*cellh),'#e7ecf4')
            draw=ImageDraw.Draw(sheet)
            draw.text((16,12),f'Tidy Coins 3D / {name} / page {page+1}',fill='#1d2c42',font=titlefont)
            for index,item in enumerate(subset):
                x,y=(index%cols)*cellw,55+(index//cols)*cellh
                draw.rounded_rectangle((x+5,y+5,x+cellw-5,y+cellh-5),10,fill='#f7f9fd')
                image=Image.open(OUT/item['file']).convert('RGBA')
                image.thumbnail((180,130),Image.Resampling.LANCZOS)
                sheet.paste(image,(x+(cellw-image.width)//2,y+8+(130-image.height)//2),image)
                label=item['logical_path'] or item['name']
                label=label.replace('Texture/skin/','')
                if len(label)>25:label=label[:22]+'...'
                draw.text((x+10,y+143),label,font=font,fill='#23344b')
                draw.text((x+10,y+160),str(item['size']),font=font,fill='#607085')
            sheet.save(preview/f'{name}-{page+1}.jpg',quality=92)
    cards=[]
    for item in sorted(sprites,key=lambda s:s['logical_path'] or s['name']):
        path=item['file']
        label=item['logical_path'] or item['name']
        category='coin' if item in groups['coins'] else 'ui'
        cards.append(f'<article data-kind="{category}" data-name="{html.escape(label.lower(),quote=True)}"><a href="{html.escape(path,quote=True)}"><div class="checker"><img loading="lazy" src="{html.escape(path,quote=True)}"></div></a><strong>{html.escape(label)}</strong><small>{item["size"][0]} × {item["size"][1]} · {html.escape(str(item["cap_insets_ltrb"]))}</small></article>')
    page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Tidy Coins 3D 美术资源预览</title><style>body{font:15px system-ui;margin:30px;background:#eef2f8;color:#223047}h1{font-size:26px}.bar{display:flex;gap:12px;margin:20px 0;position:sticky;top:0;background:#eef2f8;padding:12px 0}input,select{padding:10px;border:1px solid #aab8cd;border-radius:6px}input{min-width:300px}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:15px}article{background:white;border-radius:10px;padding:12px;overflow:hidden}article strong{display:block;overflow-wrap:anywhere;margin-top:10px}small{display:block;color:#66748c;margin-top:7px}.checker{height:170px;display:grid;place-items:center;background:conic-gradient(#e5e5e5 25%,white 0 50%,#e5e5e5 0 75%,white 0);background-size:20px 20px;border-radius:6px}img{max-width:100%;max-height:160px;object-fit:contain}article[hidden]{display:none}</style><h1>Tidy Coins 3D 美术资源预览</h1><p>透明 PNG 已旋转复原并还原裁剪留白。点击图片打开原文件。括号内为九宫格边距 [left, top, right, bottom]。</p><p>音效：assets/rea_original/audio · 骨骼动画原文件：assets/rea_original/spine · 完整使用说明：美术资源获取说明.md</p><div class="bar"><input id="q" placeholder="搜索，如 normal/1、War、Btn、BG"><select id="kind"><option value="all">全部图片</option><option value="coin">硬币</option><option value="ui">界面/特效</option></select><span id="count"></span></div><div class="grid">'''+''.join(cards)+'''</div><script>const q=document.querySelector('#q'),k=document.querySelector('#kind'),cards=[...document.querySelectorAll('article')];function filter(){let n=0;for(const c of cards){c.hidden=!(c.dataset.name.includes(q.value.toLowerCase())&&(k.value==='all'||c.dataset.kind===k.value));if(!c.hidden)n++}document.querySelector('#count').textContent=n+' 张'}q.addEventListener('input',filter);k.addEventListener('change',filter);filter();</script></html>'''
    (OUT/'美术资源预览.html').write_text(page,encoding='utf-8')

if __name__=='__main__':
    records,missing=unpack_records()
    print(json.dumps({'records':len(records),'classes':dict(Counter(r['class'] for r in records)),'missing':missing},ensure_ascii=True),flush=True)
    downloads=download_native(records)
    sprites,summary=export(records,missing,downloads)
    derived=[]
    for path in sorted((ART/'sprites/spine_cloud').glob('*.png'))+list((ART/'particles').glob('*.texture.png')):
        with Image.open(path) as im:
            size=list(im.size)
        derived.append({'file':path.relative_to(OUT).as_posix(),'name':path.stem,
                        'logical_path':'derived/'+path.stem,'size':size,'cap_insets_ltrb':[0,0,0,0],
                'derivation':'Spine atlas region' if path.parent.name=='spine_cloud' else 'Plist particle texture'})
    save(ART/'derived_sprite_manifest.json',derived)
    previews(sprites+derived,summary)
    print(json.dumps({k:v for k,v in summary.items() if k!='native_exports'},ensure_ascii=True,indent=2),flush=True)
