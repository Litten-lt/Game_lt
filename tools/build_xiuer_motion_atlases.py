from pathlib import Path

import cv2
import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
CONCEPT = ROOT / "game" / "FighterRPGDemo" / "assets" / "concept_art"
CHARACTER = ROOT / "game" / "FighterRPGDemo" / "assets" / "characters" / "xiuer"

CELL = 896
CORE_TARGET_WIDTH = 125.0
CORE_TARGET_TOP = 306.0
CORE_TARGET_CENTER_X = CELL * 0.5


def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("Frame has no visible pixels")
    return bbox


def core_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    rgba = np.asarray(image)
    hsv = cv2.cvtColor(rgba[:, :, :3], cv2.COLOR_RGB2HSV)
    mask = cv2.inRange(hsv, (135, 100, 100), (175, 255, 255))
    count, _, stats, _ = cv2.connectedComponentsWithStats(mask)
    candidates = []
    for x, y, width, height, area in stats[1:count]:
        if y < image.height * 0.58 and width >= 150 and height >= 85:
            candidates.append((area, x, y, width, height))
    if not candidates:
        raise ValueError("Could not locate the central purple core")
    _, x, y, width, height = max(candidates)
    return x, y, width, height


def normalize_frame(path: Path) -> Image.Image:
    source = Image.open(path).convert("RGBA")
    visible = alpha_bbox(source)
    core = core_bbox(source)
    crop = source.crop(visible)

    scale = CORE_TARGET_WIDTH / core[2]
    resized = crop.resize(
        (round(crop.width * scale), round(crop.height * scale)),
        Image.Resampling.LANCZOS,
    )
    core_x_in_crop = (core[0] + core[2] * 0.5 - visible[0]) * scale
    core_y_in_crop = (core[1] - visible[1]) * scale
    paste_x = round(CORE_TARGET_CENTER_X - core_x_in_crop)
    paste_y = round(CORE_TARGET_TOP - core_y_in_crop)

    frame = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    frame.alpha_composite(resized, (paste_x, paste_y))
    return frame


def write_atlas(paths: list[Path], columns: int, output: Path) -> None:
    rows = (len(paths) + columns - 1) // columns
    atlas = Image.new("RGBA", (CELL * columns, CELL * rows), (0, 0, 0, 0))
    for index, path in enumerate(paths):
        atlas.alpha_composite(
            normalize_frame(path), ((index % columns) * CELL, (index // columns) * CELL)
        )
    output.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(output)
    print(output)


def main() -> None:
    movement = [
        CONCEPT / "xiuer-regal-glide-frame-a-v1.png",
        CONCEPT / "xiuer-move-transition-v2.png",
        CONCEPT / "xiuer-move-crest-v2.png",
        CONCEPT / "xiuer-move-transition-v2.png",
        CONCEPT / "xiuer-regal-glide-frame-a-v1.png",
    ]
    write_atlas(movement, 3, CHARACTER / "xiuer-regal-glide-loop-v3.png")


if __name__ == "__main__":
    main()
