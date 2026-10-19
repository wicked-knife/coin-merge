from pathlib import Path
import base64
import concurrent.futures as futures
import hashlib
import json
import re
import shutil
import sys
import time
import urllib.parse
import requests

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / 'work/tidy-art'
CACHE = WORK / 'download'
BASE = 'https://8388451114541855247.playables.usercontent.goog/v/assets/'
B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

def load(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

def decode_uuid(value):
    if len(value) != 22:
        return value
    chars = value[:2]
    for i in range(2, 22, 2):
        a, b = B64.index(value[i]), B64.index(value[i+1])
        chars += f'{a >> 2:x}{((a & 3) << 2) | (b >> 4):x}{b & 15:x}'
    return '-'.join((chars[:8], chars[8:12], chars[12:16], chars[16:20], chars[20:]))

def fetch(relative):
    # Only explicitly inventoried paths on the selected game's asset origin.
    if relative.startswith('/') or '..' in Path(relative).parts:
        raise ValueError(relative)
    url = BASE + urllib.parse.quote(relative, safe='/-._')
    path = CACHE / relative
    if path.is_file():
        data = path.read_bytes()
        return {'relative': relative, 'url': url, 'status': 200, 'bytes': len(data),
                'sha256': hashlib.sha256(data).hexdigest(), 'cache': True}
    for attempt in range(3):
        try:
            response = requests.get(url, timeout=(12, 35), allow_redirects=False)
            if response.status_code != 200:
                if response.status_code >= 500 and attempt < 2:
                    time.sleep(attempt + 1)
                    continue
                return {'relative': relative, 'url': url, 'status': response.status_code}
            data = response.content
            if len(data) > 32 * 1024 * 1024:
                raise ValueError('Resource exceeds 32 MiB per-file budget')
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            return {'relative': relative, 'url': url, 'status': 200, 'bytes': len(data),
                    'sha256': hashlib.sha256(data).hexdigest(),
                    'content_type': response.headers.get('Content-Type')}
        except (requests.RequestException, ValueError) as error:
            if attempt == 2:
                return {'relative': relative, 'url': url, 'status': 'error', 'error': str(error)}
            time.sleep(attempt + 1)

def fetch_many(paths, manifest):
    results = []
    with futures.ThreadPoolExecutor(max_workers=6) as pool:
        jobs = {pool.submit(fetch, p): p for p in sorted(set(paths))}
        for job in futures.as_completed(jobs):
            result = job.result()
            results.append(result)
            if len(results) % 25 == 0:
                print(f'{manifest}: {len(results)}/{len(jobs)} complete', flush=True)
    results.sort(key=lambda x:x['relative'])
    save(WORK / manifest, results)
    print(json.dumps({'manifest':manifest, 'requests':len(results),
                      'ok':sum(r['status']==200 for r in results),
                      'bytes':sum(r.get('bytes',0) for r in results),
                      'failed':[r for r in results if r['status']!=200]}, ensure_ascii=True), flush=True)
    return results

def imports():
    fetch_many(['assets/resources/config.json','assets/main/config.json',
                'assets/internal/config.json','cocos2d-js-min.js'], 'bootstrap-downloads.json')
    prior = load(ROOT / 'work/tidy-configs/manifest.json')
    for item in prior:
        rel = item['url'].removeprefix(BASE)
        if rel == item['url']:
            continue
        src = ROOT / 'work/tidy-configs' / item['file']
        dest = CACHE / rel
        if dest.exists():
            # A changed build should not silently mix configuration identities.
            assert hashlib.sha256(dest.read_bytes()).hexdigest() == item['sha256'], rel
        elif hashlib.sha256(src.read_bytes()).hexdigest() == item['sha256']:
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dest)
    entries, paths = [], []
    for bundle in ['resources','main','internal']:
        cfg = load(CACHE / f'assets/{bundle}/config.json')
        packed = {idx for indices in cfg.get('packs',{}).values() for idx in indices}
        redirect = set(cfg.get('redirect',[])[::2])
        for pack, indices in cfg.get('packs',{}).items():
            rel = f'assets/{bundle}/import/{pack[:2]}/{pack}.json'
            paths.append(rel)
            entries.append({'bundle':bundle,'relative':rel,'indices':indices,'packed':True})
        for idx, uuid in enumerate(cfg['uuids']):
            if idx in packed or idx in redirect:
                continue
            ident = decode_uuid(uuid)
            rel = f'assets/{bundle}/import/{ident[:2]}/{ident}.json'
            paths.append(rel)
            entries.append({'bundle':bundle,'relative':rel,'indices':[idx],'packed':False})
    save(WORK / 'import-inventory.json', entries)
    fetch_many(paths, 'import-downloads.json')

if __name__ == '__main__':
    imports()
