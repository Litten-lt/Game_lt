from pathlib import Path

import cv2
import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
CHARACTER = ROOT / "game" / "FighterRPGDemo" / "assets" / "characters" / "liulan"
SOURCE = CHARACTER / "xiuer-video-replica-idle-v2-enhanced.png"
OUTPUT = CHARACTER / "xiuer-idle-motion-jump-v1.png"
CELL = 512
FRAME_COUNT = 6


def remove_ground_shadow(frame: np.ndarray) -> None:
    """Remove only the large neutral ellipse embedded below the character."""
    hsv = cv2.cvtColor(frame[:, :, :3], cv2.COLOR_RGB2HSV)
    yy = np.indices((CELL, CELL))[0]
    neutral = (
        (hsv[:, :, 1] < 45)
        & (hsv[:, :, 2] > 45)
        & (hsv[:, :, 2] < 245)
        & (frame[:, :, 3] > 20)
        & (yy > 285)
    ).astype(np.uint8)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(neutral)
    candidates = [index for index in range(1, count) if stats[index, cv2.CC_STAT_AREA] > 1200]
    if len(candidates) != 1:
        raise ValueError(f"Expected one ground-shadow component, found {len(candidates)}")
    shadow = labels == candidates[0]
    # Include the antialiased rim without touching colored armor that overlaps it.
    expanded = cv2.dilate(shadow.astype(np.uint8), np.ones((3, 3), np.uint8), iterations=1) > 0
    soft_neutral = (hsv[:, :, 1] < 60) & (yy > 285)
    frame[:, :, 3][expanded & soft_neutral] = 0


def main() -> None:
    atlas = np.array(Image.open(SOURCE).convert("RGBA"))
    for index in range(FRAME_COUNT):
        x = index % 3 * CELL
        y = index // 3 * CELL
        remove_ground_shadow(atlas[y : y + CELL, x : x + CELL])
    Image.fromarray(atlas, "RGBA").save(OUTPUT)
    print(OUTPUT)


if __name__ == "__main__":
    main()
