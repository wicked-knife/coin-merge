"""Prepare reproducible imagegen jobs; never reads or uploads original artwork."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'art-source/ceramic'
STYLE = ('Original art for an independent ceramic coin sorting game. Soft matte ivory porcelain, '
         'handcrafted restrained design, subtle clay texture, rounded bevels, warm diffuse upper-left lighting, '
         'orthographic product render, crisp silhouette, no text, no letters, no numbers, no branding, no watermark. ')
KEY = ('One isolated object centered, fully inside frame with generous empty margin. '
       'Background must be perfectly flat solid bright magenta RGB 255 0 255, no gradient, no ground plane, '
       'no cast shadow outside the object, no other objects. The object itself contains no magenta or pink. ')
SUBJECTS = {
    'coin-angle': 'A single thick circular ivory ceramic token, smooth blank inset face bordered by one soft rounded lip. Viewed from above at 32 degrees, horizontal elliptical face, visible front thickness; silhouette width to height about 1.55. Absolutely no holes, letters or separate stand. ',
    'panel': 'A wide blank rounded rectangular ivory ceramic plaque, directly front-on, width to height 1.30. Broad smooth empty inner area with a subtle recessed rim and gently rounded corners, no header, no markings. ',
    'coin-front': 'A single round ivory ceramic token, viewed exactly front-on, circular silhouette, smooth blank inset face and a restrained rounded ceramic rim, no decoration in the center. ',
    'background': 'An empty softly textured warm cream ceramic work surface filling the entire image edge to edge. Very subtle sand and ivory gradient with almost invisible speckles. Uniform diffuse lighting. No objects, no frame, no seam, no horizon. This is an opaque background texture, NOT a magenta cutout. ',
    'tray': 'A square ivory ceramic sorting tray viewed directly front-on, low rounded raised rim at the perimeter only, large smooth flat empty inner space, no internal subdivisions and no objects. ',
    'slot': 'A single narrow tall recessed ceramic groove, directly front-on, width to height 0.57, rounded rectangular outer outline, soft concave inner surface, continuous shallow rim, no internal lines or objects. ',
    'button': 'A single blank horizontal pill shaped ceramic button, width to height 2.3, exactly front-on. Rounded ivory ceramic body with a softly beveled perimeter, broad plain empty face, no symbols and no text. ',
    'card': 'A single blank vertical rounded rectangular ceramic tile, width to height 0.70. Exactly front-on, softly beveled perimeter, wide empty ivory face, no patterns or symbols. ',
    'cloud': 'One puffy asymmetrical ivory cloud sculpted from smooth matte white ceramic, three rounded lobes of different sizes and a soft gently curved flat base, horizontal silhouette, no face or marks. ',
    'hand': 'One friendly minimal ivory cartoon hand pointer sculpture, index finger pointing diagonally to the upper left, thumb visible, three other fingers curled naturally, simplified mitten-like proportions, soft ceramic material, no sleeve or other objects. ',
}


def main():
    ART.mkdir(parents=True, exist_ok=True)
    jobs = []
    for name, subject in SUBJECTS.items():
        prompt = STYLE + subject + (KEY if name != 'background' else '')
        jobs.append({'model': 'gpt-image-2.5', 'prompt': prompt, 'size': '1024x1024',
                     'quality': 'medium', 'n': 1, 'out': name + '.png'})
    for filename, selected in [('pilot.jsonl', jobs[:2]), ('remaining.jsonl', jobs[2:])]:
        (ART / filename).write_text(''.join(json.dumps(job, ensure_ascii=False) + '\n' for job in selected), encoding='utf-8')
    (ART / 'prompts.json').write_text(json.dumps({'model': 'gpt-image-2.5', 'mode': 'CLI',
        'input_images': [], 'jobs': jobs, 'max_concurrency': 2}, indent=2) + '\n', encoding='utf-8')
    print(f'Prepared {len(jobs)} original-art jobs (pilot 2 + remaining 8).')


if __name__ == '__main__':
    main()
