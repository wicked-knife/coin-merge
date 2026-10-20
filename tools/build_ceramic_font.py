"""Download an OFL font and build a deterministic, renamed UI subset."""
import hashlib
import json
from pathlib import Path
from urllib.request import Request, urlopen

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / 'art-source/ceramic/fonts'
DEST = ROOT / 'assets/reskin/ceramic/fonts'
BASE = 'https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/'


def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    DEST.mkdir(parents=True, exist_ok=True)
    source = CACHE / 'NotoSansSC-variable.ttf'
    urls = {'font': BASE + 'NotoSansSC%5Bwght%5D.ttf', 'license': BASE + 'OFL.txt'}
    for file, url in [(source, urls['font']), (DEST / 'OFL.txt', urls['license'])]:
        if not file.exists():
            with urlopen(Request(url, headers={'User-Agent': 'Mozilla/5.0'}), timeout=60) as response:
                file.write_bytes(response.read())
    chars = set(chr(i) for i in range(32, 127))
    for folder, extension in [('scripts', '*.gd'), ('scenes', '*.tscn'), ('translations', '*.csv')]:
        for path in (ROOT / folder).glob(extension):
            chars.update(path.read_text(encoding='utf-8-sig'))
    chars.update('合并硬币瓷器陶瓷Coin Merge·×→✓…！？：，。★')
    chars = {c for c in chars if ord(c) >= 32}
    font = TTFont(source)
    font = instantiateVariableFont(font, {'wght': 650}, inplace=True)
    options = subset.Options()
    options.name_IDs = ['*']
    options.name_legacy = True
    options.name_languages = ['*']
    job = subset.Subsetter(options=options)
    job.populate(text=''.join(sorted(chars)))
    job.subset(font)
    for record in font['name'].names:
        replacements = {1: 'Coin Merge UI', 2: 'SemiBold', 3: 'CoinMergeUI-SemiBold-20261020',
                        4: 'Coin Merge UI SemiBold', 6: 'CoinMergeUI-SemiBold', 16: 'Coin Merge UI', 17: 'SemiBold'}
        if record.nameID in replacements:
            record.string = replacements[record.nameID].encode(record.getEncoding())
    target = DEST / 'CoinMergeUI.ttf'
    font.save(target)
    glyphs = font.getBestCmap()
    # Decorative symbols are drawn as vectors; all game text must be covered.
    missing = sorted({c for c in chars if ord(c) not in glyphs and ord(c) > 127})
    provenance = {'source_urls': urls, 'license': 'SIL Open Font License 1.1',
                  'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                  'subset_sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
                  'font_weight': 650, 'family': 'Coin Merge UI', 'unicode_count': len(glyphs),
                  'requested_missing_symbols': missing, 'bytes': target.stat().st_size}
    (DEST / 'provenance.json').write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(provenance, ensure_ascii=False))


if __name__ == '__main__':
    main()
