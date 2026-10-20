"""Audit reachable Godot image dependencies, including this game's dynamic families."""
from __future__ import annotations

import argparse
from collections import defaultdict, deque
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
STRINGS = re.compile(r'["\']([^"\'\n]+)["\']')
IMAGE = re.compile(r'\.(png|jpe?g|webp|svg)$', re.I)
SOURCE_EXT = {'.gd', '.tscn', '.tres', '.gdshader', '.fnt'}


def relative(path):
    return path.resolve().relative_to(ROOT).as_posix()


def text(path):
    return path.read_text(encoding='utf-8-sig')


def reachable_sources():
    queue = deque([ROOT / 'project.godot'])
    visited = set()
    while queue:
        path = queue.popleft().resolve()
        if path in visited or not path.is_file():
            continue
        visited.add(path)
        for line in text(path).splitlines():
            if line.lstrip().startswith(('#', ';')):
                continue
            for match in STRINGS.finditer(line):
                value = match.group(1).lstrip('*')
                if value.startswith('res://'):
                    child = ROOT / value[6:]
                    if child.suffix in SOURCE_EXT:
                        queue.append(child)
    return sorted(visited)


def bindings(body, inherited=None):
    values = dict(inherited or {})
    for _ in range(4):
        for name, expression in re.findall(r'^const\s+(\w+)\s*(?::=|=)\s*(.+)$', body, re.M):
            parts = expression.split(' + ')
            resolved = []
            for part in parts:
                part = part.strip()
                if re.fullmatch(r'"[^"]*"', part):
                    resolved.append(part[1:-1])
                elif part in values:
                    resolved.append(values[part])
                else:
                    break
            else:
                values[name] = ''.join(resolved)
    return values


def inspect_image(path):
    result = {'path': relative(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
              'bytes': path.stat().st_size}
    if path.suffix.lower() == '.svg':
        result.update(size=[128, 128], mode='SVG', alpha_bbox=None)
    else:
        with Image.open(path) as im:
            alpha = im.getchannel('A') if 'A' in im.getbands() else None
            result.update(size=list(im.size), mode=im.mode,
                          alpha_bbox=list(alpha.getbbox()) if alpha and alpha.getbbox() else None,
                          alpha_range=list(alpha.getextrema()) if alpha else [255, 255])
    return result


def audit():
    sources = reachable_sources()
    shared = {}
    skin = ROOT / 'scripts/ceramic_skin.gd'
    if skin.exists():
        shared.update({'Ceramic.' + key: val for key, val in bindings(text(skin)).items()})
    parent = ROOT / 'scripts/challenge_screen.gd'
    shared.update(bindings(text(parent), shared))
    particle_root = bindings(text(ROOT / 'scripts/normal_particles.gd'), shared).get('ROOT',
        'res://assets/rea_original/sprites/')
    found = defaultdict(list)
    unresolved = []
    sounds = defaultdict(list)
    fonts = defaultdict(list)
    system_fonts = []
    for source in sources:
        body = text(source)
        if 'SystemFont' in body:
            system_fonts.append(relative(source))
        values = bindings(body, shared)
        for line_no, line in enumerate(body.splitlines(), 1):
            if line.lstrip().startswith(('#', ';')):
                continue
            for sound in re.findall(r'_sound(?:\.bind)?\("([^"\n]+)"\)', line):
                sounds[sound].append(f'{relative(source)}:{line_no}')
            for match in STRINGS.finditer(line):
                value = match.group(1)
                if value.startswith('res://assets/rea_original/audio/') and value.endswith('.mp3') and '%' not in value:
                    sounds[Path(value).stem].append(f'{relative(source)}:{line_no}')
                if value.startswith('res://') and value.endswith(('.ttf', '.fnt', '.otf')):
                    fonts[value[6:]].append(f'{relative(source)}:{line_no}')
                if not IMAGE.search(value):
                    continue
                dynamic = '%d' in value
                if dynamic:
                    count = 16 if '/normal/' in value else 11 if '/war/' in value else 15 if 'BigCoin' in value else 0
                    variants = [value % n for n in range(1, count + 1)]
                    if not variants:
                        unresolved.append({'source': relative(source), 'line': line_no, 'value': value})
                else:
                    variants = [value]
                for name in variants:
                    prefix = re.search(r'([\w.]+)\s*\+\s*$', line[:match.start()])
                    if name.startswith('res://'):
                        target = ROOT / name[6:]
                    elif source.suffix == '.fnt':
                        target = source.parent / name
                    elif prefix and prefix.group(1) in values:
                        target = ROOT / (values[prefix.group(1)] + name)[6:]
                    elif source.name in {'normal_particle_data.gd', 'challenge_slot.gd'} and '"texture"' in line:
                        target = ROOT / (particle_root + name)[6:]
                    elif values.get('ROOT', '').startswith('res://'):
                        target = ROOT / (values['ROOT'] + name)[6:]
                    else:
                        unresolved.append({'source': relative(source), 'line': line_no, 'value': name})
                        continue
                    if not target.is_file():
                        unresolved.append({'source': relative(source), 'line': line_no, 'value': str(target)})
                        continue
                    kind = 'dynamic' if dynamic else 'direct'
                    if source.suffix == '.fnt':
                        kind = 'font-page'
                    if source.suffix == '.tscn' and '[ext_resource' in line:
                        resource_id = re.search(r'id="([^"]+)"', line)
                        if resource_id and f'ExtResource("{resource_id.group(1)}")' not in body:
                            kind = 'scene-declaration-only'
                    found[target.resolve()].append({'source': relative(source), 'line': line_no, 'kind': kind,
                                                    'expression': value})
    images = []
    for path, refs in sorted(found.items(), key=lambda item: str(item[0])):
        row = inspect_image(path)
        row['references'] = refs
        row['runtime_used'] = any(ref['kind'] != 'scene-declaration-only' for ref in refs)
        images.append(row)
    return {'generated_at': datetime.now(timezone.utc).isoformat(),
            'image_count': len(images), 'source_files': [relative(p) for p in sources],
            'images': images, 'unresolved': unresolved,
            'fonts': [{'path': k, 'references': v} for k, v in sorted(fonts.items())],
            'system_font_sources': system_fonts,
            'retained_original_audio': [{'name': k, 'path': f'assets/rea_original/audio/{k}.mp3', 'references': v}
                                        for k, v in sorted(sounds.items())]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    report = audit()
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f"Reachable sources: {len(report['source_files'])}; unique images: {report['image_count']}; retained sounds: {len(report['retained_original_audio'])}")
    if report['unresolved']:
        print(json.dumps(report['unresolved'], ensure_ascii=False, indent=2))
        return 1
    if args.check:
        old = [row['path'] for row in report['images'] if row['path'].startswith('assets/rea_original/')]
        if old:
            print('Original image dependencies remain:', old)
            return 1
        if report['system_font_sources'] or any(row['path'].startswith('assets/rea_original/') for row in report['fonts']):
            print('Old or system font dependencies remain.')
            return 1
        print('PASS: no unresolved image paths or original-art image dependencies.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
