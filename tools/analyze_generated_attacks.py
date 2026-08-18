from pathlib import Path
import json
import re
import subprocess
from PIL import Image, ImageDraw

SRC = Path(r"C:\Users\LongTeng\Desktop\Allen\Game\analysis_output\normal_attack_references")
OUT = SRC / "video_analysis"
FFMPEG = Path(r"C:\Users\LongTeng\Desktop\Allen\Game\tools\python_pkgs\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v7.1.exe")
OUT.mkdir(exist_ok=True)

videos = sorted(SRC.glob("*.mp4"), key=lambda p: p.stat().st_mtime)
rows = []
for index, path in enumerate(videos, 1):
    result = subprocess.run(
        [str(FFMPEG), "-hide_banner", "-i", str(path)],
        capture_output=True, text=True, encoding="utf-8", errors="replace"
    )
    dm = re.search(r"Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)", result.stderr)
    vm = re.search(r"Video:.*?,\s*(\d{2,5})x(\d{2,5})[^\n]*?([\d.]+) fps", result.stderr)
    duration = int(dm.group(1))*3600 + int(dm.group(2))*60 + float(dm.group(3))
    width, height, fps = int(vm.group(1)), int(vm.group(2)), float(vm.group(3))
    slug = f"{index:02d}"
    sheet = OUT / f"{slug}_contact.jpg"
    interval = max(duration / 12.0, 0.04)
    subprocess.run([
        str(FFMPEG), "-y", "-hide_banner", "-loglevel", "error", "-i", str(path),
        "-vf", f"fps=1/{interval},scale=320:-2,tile=4x3",
        "-frames:v", "1", str(sheet)
    ], check=True)
    rows.append({"index": index, "name": path.name, "duration": duration,
                 "fps": fps, "width": width, "height": height, "sheet": sheet.name})

cards = []
for row in rows:
    image = Image.open(OUT / row["sheet"]).convert("RGB")
    image.thumbnail((960, 540))
    card = Image.new("RGB", (1000, 590), "#151923")
    card.paste(image, ((1000-image.width)//2, 45))
    ImageDraw.Draw(card).text((16, 14), f"#{row['index']} {row['name']}  {row['duration']:.2f}s  {row['fps']:.2f}fps", fill="white")
    cards.append(card)

overview = Image.new("RGB", (2000, ((len(cards)+1)//2)*590), "#0b0e14")
for i, card in enumerate(cards):
    overview.paste(card, ((i % 2)*1000, (i // 2)*590))
overview.save(OUT / "overview.jpg", quality=93)
(OUT / "metadata.json").write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(rows, ensure_ascii=False))
