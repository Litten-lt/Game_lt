from __future__ import annotations

import shutil
import subprocess
from pathlib import Path
from statistics import median

from PIL import Image


import imageio_ffmpeg


PROJECT_ROOT = Path(__file__).resolve().parents[3]


SOURCE_ROOT = PROJECT_ROOT / "source_assets" / "monsters" / "rock_crown" / "video_generation"
OUTPUT_ROOT = PROJECT_ROOT / "assets" / "monsters" / "rock_crown" / "animations"
WORK_ROOT = PROJECT_ROOT / "source_assets" / "monsters" / "rock_crown" / "animation_work"
FFMPEG = Path(imageio_ffmpeg.get_ffmpeg_exe())

JOBS = {
    "idle": SOURCE_ROOT / "01_idle_breath" / "idle_breath_source.mp4",
    "crawl": SOURCE_ROOT / "02_crawl" / "crawl_source.mp4",
}

FPS = 8
CANVAS_SIZE = 512
SUBJECT_HEIGHT = 230
ANCHOR = (256, 462)


def remove_green(image: Image.Image) -> Image.Image:
    """Convert the generated green-screen background to transparent pixels."""
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    for y in range(rgba.height):
        for x in range(rgba.width):
            r, g, b, _ = pixels[x, y]
            green_excess = g - max(r, b)
            if g > 72 and green_excess > 22:
                alpha = max(0, min(255, int(255 * (42 - green_excess) / 20)))
                if alpha:
                    spill = min(g, max(r, b) + 12)
                    pixels[x, y] = (r, spill, b, alpha)
                else:
                    pixels[x, y] = (0, 0, 0, 0)
    return rgba


def largest_component(image: Image.Image) -> Image.Image:
    """Keep the connected monster silhouette and discard detached watermarks."""
    alpha = image.getchannel("A")
    width, height = image.size
    source = alpha.load()
    seen = bytearray(width * height)
    largest: list[tuple[int, int]] = []

    for y in range(height):
        for x in range(width):
            offset = y * width + x
            if seen[offset] or source[x, y] <= 40:
                continue
            stack = [(x, y)]
            seen[offset] = 1
            component: list[tuple[int, int]] = []
            while stack:
                current_x, current_y = stack.pop()
                component.append((current_x, current_y))
                for next_x, next_y in (
                    (current_x - 1, current_y),
                    (current_x + 1, current_y),
                    (current_x, current_y - 1),
                    (current_x, current_y + 1),
                ):
                    if not (0 <= next_x < width and 0 <= next_y < height):
                        continue
                    next_offset = next_y * width + next_x
                    if not seen[next_offset] and source[next_x, next_y] > 40:
                        seen[next_offset] = 1
                        stack.append((next_x, next_y))
            if len(component) > len(largest):
                largest = component

    mask = Image.new("L", image.size)
    target = mask.load()
    for x, y in largest:
        target[x, y] = source[x, y]
    cleaned = Image.new("RGBA", image.size)
    cleaned.paste(image, (0, 0), mask)
    return cleaned


def subject_bbox(image: Image.Image) -> tuple[int, int, int, int] | None:
    return image.getchannel("A").point(lambda value: 255 if value > 40 else 0).getbbox()


def build_animation(name: str, video_path: Path) -> int:
    extracted = WORK_ROOT / name / "extracted"
    destination = OUTPUT_ROOT / name
    shutil.rmtree(extracted, ignore_errors=True)
    shutil.rmtree(destination, ignore_errors=True)
    extracted.mkdir(parents=True)
    destination.mkdir(parents=True)

    subprocess.run(
        [
            str(FFMPEG),
            "-y",
            "-i",
            str(video_path),
            "-vf",
            f"fps={FPS}",
            str(extracted / "frame_%03d.png"),
        ],
        check=True,
        capture_output=True,
    )

    frames: list[tuple[Image.Image, tuple[int, int, int, int]]] = []
    for frame_path in sorted(extracted.glob("frame_*.png")):
        frame = largest_component(remove_green(Image.open(frame_path)))
        bbox = subject_bbox(frame)
        if bbox:
            frames.append((frame, bbox))
    if not frames:
        raise RuntimeError(f"No monster frames found in {video_path}")

    typical_height = median(bbox[3] - bbox[1] for _, bbox in frames)
    scale = SUBJECT_HEIGHT / typical_height
    typical_center_x = median((bbox[0] + bbox[2]) / 2 for _, bbox in frames) * scale
    typical_bottom = median(bbox[3] for _, bbox in frames) * scale

    for index, (frame, _) in enumerate(frames):
        resized = frame.resize(
            (round(frame.width * scale), round(frame.height * scale)),
            Image.Resampling.NEAREST,
        )
        canvas = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE))
        x = round(ANCHOR[0] - typical_center_x)
        y = round(ANCHOR[1] - typical_bottom)
        canvas.alpha_composite(resized, (x, y))
        canvas.save(destination / f"frame_{index:03d}.png")

    print(f"{name}: {len(frames)} frames at {FPS} fps")
    return len(frames)


def main() -> None:
    for name, video_path in JOBS.items():
        if not video_path.exists():
            raise FileNotFoundError(video_path)
        build_animation(name, video_path)


if __name__ == "__main__":
    main()
