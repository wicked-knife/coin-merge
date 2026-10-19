from pathlib import Path
from PIL import Image, ImageDraw

BASE = Path(__file__).resolve().parents[1] / 'previews/normal-alignment'
INTERVALS = {'invalid-move': 50, 'reveal': 40, 'selected': 100, 'merge-progress': 150, 'final-win': 150}
frames, durations = [], []
for name in ['selected', 'reveal', 'merge-progress', 'yellow-open', 'rescue', 'final-win', 'next-board', 'retry']:
    folder = BASE / name
    files = sorted(folder.glob('*.png'))
    if not files:
        continue
    chosen = files[::max(1, len(files) // 6)][:6]
    strip = Image.new('RGB', (225 * len(chosen), 425), '#162b43')
    draw = ImageDraw.Draw(strip)
    for index, file in enumerate(chosen):
        with Image.open(file) as original:
            thumbnail = original.convert('RGB')
            thumbnail.thumbnail((225, 400))
        strip.paste(thumbnail, (index * 225, 25))
        draw.text((index * 225 + 6, 6), f'{name} {file.stem}', fill='white')
    strip.save(BASE / (name + '-strip.jpg'))
    for file in files:
        with Image.open(file) as original:
            frame = original.convert('RGB')
            frame.thumbnail((360, 640))
            frames.append(frame.convert('P', palette=Image.Palette.ADAPTIVE))
        durations.append(INTERVALS.get(name, 75))
frames[0].save(BASE.parent / 'normal-mode-aligned.gif', save_all=True, append_images=frames[1:], duration=durations, loop=0, optimize=True)
