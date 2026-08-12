from __future__ import annotations

import argparse
import math
from pathlib import Path

import cv2
import numpy as np
from PIL import Image


CELL = 512
OUTPUT_FPS = 12.0
ATLAS_COLUMNS = 11
# Match the visible height of the frozen idle atlas (roughly 312-355 px).
# The previous 430 px normalization made movement about 30% larger and left
# too little transparent margin for the widest cape silhouettes.
TARGET_HEIGHT = 320
TARGET_CENTER_X = CELL // 2
TARGET_TOP = 66


def repair_clipped_side(rgba: np.ndarray, side: str) -> np.ndarray:
    """Extend a cut cape from a narrow outer tip to its full source edge."""
    alpha = rgba[:, :, 3]
    edge_alpha = alpha[:, 0] if side == "left" else alpha[:, -1]
    ys = np.where(edge_alpha > 32)[0]
    if len(ys) < 10:
        return rgba

    # Reject tiny antialias contacts. A clipped cape produces a continuous,
    # clearly visible vertical segment at the source boundary.
    groups = np.split(ys, np.where(np.diff(ys) > 1)[0] + 1)
    group = max(groups, key=len)
    if len(group) < 10:
        return rgba

    y0, y1 = int(group[0]), int(group[-1]) + 1
    run_height = y1 - y0
    extension = int(np.clip(run_height * 0.9, 24, 88))
    sample_width = min(40, rgba.shape[1])
    source = rgba[y0:y1, :sample_width] if side == "left" else rgba[y0:y1, -sample_width:]
    strip = cv2.resize(source, (extension, run_height), interpolation=cv2.INTER_LINEAR)
    # Arrange pixels so the inner end reproduces the exact source boundary.
    if side == "left":
        strip = strip[:, ::-1]
    mask = np.zeros((run_height, extension), np.uint8)
    center_y = (run_height - 1) * 0.5
    for x in range(extension):
        # left extension: narrow outside -> full at join; right is mirrored.
        progress = (x + 1) / extension
        half = max(0.75, run_height * 0.5 * progress)
        lo = max(0, int(center_y - half))
        hi = min(run_height, int(center_y + half) + 1)
        mask[lo:hi, x] = 255
    if side == "right":
        strip = strip[:, ::-1]
        mask = mask[:, ::-1]
    strip[:, :, 3] = np.minimum(strip[:, :, 3], mask)

    padded = np.zeros((rgba.shape[0], rgba.shape[1] + extension, 4), np.uint8)
    if side == "left":
        padded[:, extension:] = rgba
        padded[y0:y1, :extension] = strip
    else:
        padded[:, :rgba.shape[1]] = rgba
        padded[y0:y1, rgba.shape[1]:] = strip
    return padded


def extract_character(frame_bgr: np.ndarray) -> Image.Image:
    """Remove the flat gray video background and discard detached watermarks."""
    rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
    height, width = rgb.shape[:2]

    border = np.concatenate(
        [rgb[:16].reshape(-1, 3), rgb[-16:].reshape(-1, 3), rgb[:, :16].reshape(-1, 3)]
    )
    background = np.median(border, axis=0)
    color_distance = np.linalg.norm(rgb.astype(np.float32) - background, axis=2)
    saturation = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV)[:, :, 1].astype(np.float32)

    # Saturated armor/cloth is easy to separate. Color distance retains the
    # pale crystal highlights while ignoring compression noise in the gray.
    foreground = ((color_distance > 23.0) | (saturation > 48.0)).astype(np.uint8)
    foreground[: max(0, height // 20)] = 0

    count, labels, stats, centroids = cv2.connectedComponentsWithStats(foreground, 8)
    center = np.array([width * 0.50, height * 0.48])
    candidates: list[tuple[float, int]] = []
    for index in range(1, count):
        area = stats[index, cv2.CC_STAT_AREA]
        if area < 80:
            continue
        distance = np.linalg.norm(centroids[index] - center)
        candidates.append((area - distance * 15.0, index))
    if not candidates:
        raise ValueError("Could not find the character in the video frame")

    main_index = max(candidates)[1]
    main = labels == main_index
    ys, xs = np.where(main)
    main_box = np.array([xs.min(), ys.min(), xs.max(), ys.max()])

    keep = main.copy()
    # Preserve small ribbons adjacent to the body, but not the corner watermark.
    for index in range(1, count):
        if index == main_index or stats[index, cv2.CC_STAT_AREA] < 18:
            continue
        component = labels == index
        # The moving Doubao watermark is nearly gray. Reject it before the
        # proximity check so its letters cannot become detached sprite pieces.
        if float(np.median(saturation[component])) < 65.0:
            continue
        cx, cy = centroids[index]
        dx = max(main_box[0] - cx, 0, cx - main_box[2])
        dy = max(main_box[1] - cy, 0, cy - main_box[3])
        if math.hypot(dx, dy) < 42.0:
            keep |= component

    keep_u8 = keep.astype(np.uint8) * 255
    keep_u8 = cv2.morphologyEx(keep_u8, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8))
    keep_u8 = cv2.dilate(keep_u8, np.ones((3, 3), np.uint8), iterations=1)
    soft_alpha = cv2.GaussianBlur(keep_u8, (0, 0), 0.75)
    rgba = np.dstack([rgb, soft_alpha])
    rgba = repair_clipped_side(rgba, "left")
    rgba = repair_clipped_side(rgba, "right")

    visible_y, visible_x = np.where(rgba[:, :, 3] > 8)
    left, top = visible_x.min(), visible_y.min()
    right, bottom = visible_x.max() + 1, visible_y.max() + 1
    return Image.fromarray(rgba, "RGBA").crop((left, top, right, bottom))


def normalize_frame(character: Image.Image) -> Image.Image:
    scale = TARGET_HEIGHT / character.height
    resized = character.resize(
        (round(character.width * scale), round(character.height * scale)), Image.Resampling.LANCZOS
    )
    canvas = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    x = round(TARGET_CENTER_X - resized.width * 0.5)
    canvas.alpha_composite(resized, (x, TARGET_TOP))
    return canvas


def build(video_path: Path, output_path: Path, preview_path: Path | None) -> None:
    capture = cv2.VideoCapture(str(video_path))
    source_fps = capture.get(cv2.CAP_PROP_FPS)
    source_count = int(capture.get(cv2.CAP_PROP_FRAME_COUNT))
    if source_fps <= 0 or source_count <= 0:
        raise ValueError(f"Could not decode video: {video_path}")

    step = source_fps / OUTPUT_FPS
    source_indices = [round(index * step) for index in range(math.ceil(source_count / step))]
    source_indices = [min(index, source_count - 1) for index in source_indices]
    frames: list[Image.Image] = []
    for source_index in source_indices:
        capture.set(cv2.CAP_PROP_POS_FRAMES, source_index)
        ok, frame = capture.read()
        if not ok:
            raise ValueError(f"Could not read video frame {source_index}")
        frames.append(normalize_frame(extract_character(frame)))

    rows = math.ceil(len(frames) / ATLAS_COLUMNS)
    atlas = Image.new("RGBA", (ATLAS_COLUMNS * CELL, rows * CELL), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        atlas.alpha_composite(frame, ((index % ATLAS_COLUMNS) * CELL, (index // ATLAS_COLUMNS) * CELL))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(output_path, optimize=True)

    if preview_path:
        preview_indices = np.linspace(0, len(frames) - 1, 12, dtype=int)
        preview = Image.new("RGBA", (CELL * 4, CELL * 3), (215, 222, 234, 255))
        for slot, frame_index in enumerate(preview_indices):
            preview.alpha_composite(frames[frame_index], ((slot % 4) * CELL, (slot // 4) * CELL))
        preview.save(preview_path)

    print(
        f"source_fps={source_fps:.3f} source_frames={source_count} "
        f"output_fps={OUTPUT_FPS:.1f} output_frames={len(frames)} "
        f"atlas={ATLAS_COLUMNS}x{rows}"
    )
    print(output_path)


def main() -> None:
    parser = argparse.ArgumentParser(description="Build Xiuer movement atlas from a continuous video")
    parser.add_argument("video", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    build(args.video, args.output, args.preview)


if __name__ == "__main__":
    main()
