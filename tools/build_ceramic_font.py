"""Build deterministic OFL font subsets, including Arabic shaping and fallbacks."""
import csv
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
FAMILIES = [
    ('notosanssc', 'NotoSansSC', 'CoinMergeUI'),
    ('notosans', 'NotoSans', 'CoinMergeLatin'),
    ('notosansjp', 'NotoSansJP', 'CoinMergeJapanese'),
    ('notosanskr', 'NotoSansKR', 'CoinMergeKorean'),
    ('notosanstc', 'NotoSansTC', 'CoinMergeTraditional'),
    ('notosansarabic', 'NotoSansArabic', 'CoinMergeArabic'),
]


def download(path, url):
    if not path.exists():
        with urlopen(Request(url, headers={'User-Agent': 'CoinMerge-FontBuilder'}), timeout=60) as response:
            path.write_bytes(response.read())


def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    DEST.mkdir(parents=True, exist_ok=True)
    chars = set(chr(i) for i in range(32, 127))
    for folder, extension in [('scripts', '*.gd'), ('scenes', '*.tscn'), ('translations', '*.csv')]:
        for path in (ROOT / folder).glob(extension):
            chars.update(path.read_text(encoding='utf-8-sig'))
    chars.update('合并硬币瓷器陶瓷Coin Merge·×→✓…！？：，。★')
    chars = {c for c in chars if ord(c) >= 32}
    records = []
    covered = set()
    for folder, family, output in FAMILIES:
        base = f'https://raw.githubusercontent.com/google/fonts/main/ofl/{folder}/'
        axes = 'wdth,wght' if family in ['NotoSans', 'NotoSansArabic'] else 'wght'
        url = base + family + '%5B' + axes + '%5D.ttf'
        source = CACHE / (family + '-variable.ttf')
        license_path = DEST / ('OFL.txt' if output == 'CoinMergeUI' else output + '-OFL.txt')
        download(source, url)
        download(license_path, base + 'OFL.txt')
        font = TTFont(source, recalcTimestamp=False)
        font = instantiateVariableFont(font, {'wght': 650, **({'wdth': 100} if axes.startswith('wdth') else {})}, inplace=True)
        options = subset.Options()
        options.name_IDs = ['*']
        options.name_legacy = True
        options.name_languages = ['*']
        options.layout_features = ['*']
        job = subset.Subsetter(options=options)
        job.populate(text=''.join(sorted(chars)))
        job.subset(font)
        for record in font['name'].names:
            replacements = {1: output, 2: 'SemiBold', 3: output + '-SemiBold-20261020',
                            4: output + ' SemiBold', 6: output + '-SemiBold',
                            16: output, 17: 'SemiBold'}
            if record.nameID in replacements:
                record.string = replacements[record.nameID].encode(record.getEncoding())
        target = DEST / (output + '.ttf')
        font.save(target)
        covered.update(font.getBestCmap())
        importer = target.with_suffix('.ttf.import')
        if not importer.exists():
            importer.write_text('[remap]\nimporter="font_data_dynamic"\ntype="FontFile"\n\n'
                                '[deps]\n\n[params]\nallow_system_fallback=false\n', encoding='utf-8')
        records.append({'family': output, 'source_url': url, 'license_url': base + 'OFL.txt',
                        'license': 'SIL Open Font License 1.1', 'font_weight': 650,
                        'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                        'subset_sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
                        'unicode_count': len(font.getBestCmap()), 'bytes': target.stat().st_size})
        print(output, target.stat().st_size, flush=True)
    visible = set('EnglishРусский한국어日本語IndonesiaFrançaisEspañolPortuguêsالعربية简体中文繁體中文')
    with (ROOT / 'translations/menu.csv').open(encoding='utf-8', newline='') as stream:
        for row in csv.reader(stream):
            for field in row:
                visible.update(field)
    missing = sorted(c for c in visible if ord(c) >= 32 and ord(c) not in covered)
    assert not missing, f'Missing visible glyphs: {missing}'
    (DEST / 'provenance.json').write_text(json.dumps({'fonts': records, 'missing_visible_glyphs': missing},
                                                  ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    lines = ['[gd_resource type="FontVariation" load_steps=7 format=3]', '']
    for index, (_, _, output) in enumerate(FAMILIES):
        lines.append(f'[ext_resource type="FontFile" path="res://assets/reskin/ceramic/fonts/{output}.ttf" id="{index}"]')
    lines.extend(['', '[resource]', 'base_font = ExtResource("0")',
                  'fallbacks = Array[Font]([' + ', '.join(f'ExtResource("{i}")' for i in range(1, len(FAMILIES))) + '])'])
    (DEST / 'CoinMergeUI.tres').write_text('\n'.join(lines) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
