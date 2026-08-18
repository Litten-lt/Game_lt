from pathlib import Path
import shutil
import subprocess
from PIL import Image, ImageDraw

ROOT = Path(r"C:\Users\LongTeng\Desktop\Allen\Game\analysis_output\normal_attack_references")
OUT = ROOT / "frame_selection"
FFMPEG = Path(r"C:\Users\LongTeng\Desktop\Allen\Game\tools\python_pkgs\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v7.1.exe")
VIDEOS = [
    ("attack_1", ROOT / "生成2D横版游戏像素角色待机呼吸循环视频 (1).mp4"),
    ("attack_2", ROOT / "生成2D横版游戏像素角色待机呼吸循环视频 (2).mp4"),
    ("attack_3_v2", ROOT / "晓光三段普通攻击连击视频生成.mp4"),
]
SELECTIONS = {
    "attack_1": [40, 43, 46, 49, 52, 55, 58, 61],
    "attack_2": [34, 37, 40, 43, 46, 49, 55, 58, 61, 67],
    # F055 is repurposed as the complete low anticipation pose, then the
    # source's single full-body pass-through sequence resumes at F024.
    "attack_3_v2": [55, 24, 25, 28, 31, 34, 37, 43, 64, 73],
}

OUT.mkdir(exist_ok=True)
for slug, video in VIDEOS:
    frame_dir = OUT / slug / "all_frames"
    if frame_dir.exists():
        shutil.rmtree(frame_dir)
    frame_dir.mkdir(parents=True)
    subprocess.run([
        str(FFMPEG), "-y", "-hide_banner", "-loglevel", "error", "-i", str(video),
        "-vsync", "0", str(frame_dir / "frame_%03d.png")
    ], check=True)
    frames = sorted(frame_dir.glob("frame_*.png"))
    sampled = frames[::3]
    cell_w, cell_h = 320, 205
    cols = 6
    rows = (len(sampled) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell_w, rows * cell_h), "#10131a")
    draw = ImageDraw.Draw(sheet)
    for i, path in enumerate(sampled):
        frame_no = int(path.stem.split("_")[1])
        image = Image.open(path).convert("RGB")
        image.thumbnail((cell_w, 180))
        x, y = (i % cols) * cell_w, (i // cols) * cell_h
        sheet.paste(image, (x + (cell_w-image.width)//2, y + 25))
        draw.text((x + 6, y + 5), f"F{frame_no:03d}  {(frame_no-1)/24:.3f}s", fill="white")
    sheet.save(OUT / f"{slug}_every_3_frames.jpg", quality=94)

    selected_dir = OUT / slug / "proposed_frames"
    if selected_dir.exists():
        shutil.rmtree(selected_dir)
    selected_dir.mkdir()
    selected = []
    for order, frame_no in enumerate(SELECTIONS[slug], 1):
        source = frame_dir / f"frame_{frame_no:03d}.png"
        target = selected_dir / f"{order:02d}_source_F{frame_no:03d}.png"
        shutil.copy2(source, target)
        selected.append((frame_no, source))

    cell_w, cell_h = 480, 295
    cols = 4
    rows = (len(selected) + cols - 1) // cols
    proposal = Image.new("RGB", (cols * cell_w, rows * cell_h), "#10131a")
    proposal_draw = ImageDraw.Draw(proposal)
    for i, (frame_no, path) in enumerate(selected):
        image = Image.open(path).convert("RGB")
        image.thumbnail((cell_w, 265))
        x, y = (i % cols) * cell_w, (i // cols) * cell_h
        proposal.paste(image, (x + (cell_w-image.width)//2, y + 30))
        proposal_draw.text(
            (x + 8, y + 7),
            f"Use {i+1:02d} | Source F{frame_no:03d} | {(frame_no-1)/24:.3f}s",
            fill="white",
        )
    proposal.save(OUT / f"{slug}_proposed.jpg", quality=95)
