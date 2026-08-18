from pathlib import Path
import csv
import json
import re
import subprocess
from PIL import Image, ImageDraw

SRC = Path(r"C:\Users\LongTeng\Documents\635-636-637")
OUT = Path(r"C:\Users\LongTeng\Desktop\Allen\Game\analysis_output\etriel")
FFMPEG = Path(r"C:\Users\LongTeng\Desktop\Allen\Game\tools\python_pkgs\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v7.1.exe")
OUT.mkdir(parents=True, exist_ok=True)

def probe(path: Path):
    p = subprocess.run([str(FFMPEG), "-hide_banner", "-i", str(path)], capture_output=True, text=True, encoding="utf-8", errors="replace")
    text = p.stderr
    dm = re.search(r"Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)", text)
    vm = re.search(r"Video:.*?,\s*(\d{2,5})x(\d{2,5})[^\n]*?([\d.]+) fps", text)
    duration = (int(dm.group(1))*3600 + int(dm.group(2))*60 + float(dm.group(3))) if dm else 0
    width, height, fps = (int(vm.group(1)), int(vm.group(2)), float(vm.group(3))) if vm else (0, 0, 0)
    return duration, width, height, fps

rows = []
for path in sorted(SRC.glob("Etriel_Athanasia*.mp4"), key=lambda p: int(re.search(r"_(\d+)_new", p.name).group(1))):
    duration, width, height, fps = probe(path)
    number = int(re.search(r"_(\d+)_new", path.name).group(1))
    rows.append({"number": number, "name": path.name, "duration_sec": duration, "fps": fps,
                 "width": width, "height": height, "bytes": path.stat().st_size})
    interval = max(duration / 6, 0.05)
    out = OUT / f"{number:02d}_contact.jpg"
    cmd = [str(FFMPEG), "-y", "-hide_banner", "-loglevel", "error", "-i", str(path),
           "-vf", f"fps=1/{interval},scale=320:-2,tile=6x1", "-frames:v", "1", str(out)]
    subprocess.run(cmd, check=False)

with (OUT / "metadata.csv").open("w", newline="", encoding="utf-8-sig") as f:
    writer = csv.DictWriter(f, fieldnames=rows[0].keys())
    writer.writeheader(); writer.writerows(rows)
with (OUT / "metadata.json").open("w", encoding="utf-8") as f:
    json.dump(rows, f, ensure_ascii=False, indent=2)

# Overview: two columns, one six-frame strip per clip.
thumbs = []
for row in rows:
    img = Image.open(OUT / f"{row['number']:02d}_contact.jpg").convert("RGB")
    img.thumbnail((900, 130))
    card = Image.new("RGB", (960, 155), "#171b24")
    card.paste(img, (55, 22))
    ImageDraw.Draw(card).text((8, 6), f"#{row['number']}  {row['duration_sec']:.2f}s", fill="white")
    thumbs.append(card)
overview = Image.new("RGB", (1920, ((len(thumbs)+1)//2)*155), "#0d1017")
for i, card in enumerate(thumbs):
    overview.paste(card, ((i%2)*960, (i//2)*155))
overview.save(OUT / "overview.jpg", quality=92)
print(json.dumps(rows, ensure_ascii=False))
