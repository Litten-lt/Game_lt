from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


PROJECT_ROOT = Path(__file__).resolve().parents[3]
SELECTION_ROOT = PROJECT_ROOT / "analysis_output" / "normal_attack_references" / "frame_selection"
OUTPUT_ROOT = PROJECT_ROOT / "assets" / "characters" / "xiaoguang" / "animations"
PREVIEW_ROOT = SELECTION_ROOT / "processed_previews"

CANVAS_SIZE = (1024, 512)
ANCHOR = (256, 470)
TARGET_REFERENCE_HEIGHT = 414

JOBS = {
    "attack_1": {
        "frames": SELECTION_ROOT / "attack_1" / "proposed_frames",
        "all_frames": SELECTION_ROOT / "attack_1" / "all_frames",
        "reference": 40,
    },
    "attack_2": {
        "frames": SELECTION_ROOT / "attack_2" / "proposed_frames",
        "all_frames": SELECTION_ROOT / "attack_2" / "all_frames",
        "reference": 34,
        # The long-lived circular effect fools automatic dark-row detection.
        # This is the actual foot/ground line in the generated shot.
        "ground_y": 575,
        "clear_regions": [(820, 500, 1024, 576)],
    },
    "attack_3": {
        "frames": SELECTION_ROOT / "attack_3_v2" / "proposed_frames",
        "all_frames": SELECTION_ROOT / "attack_3_v2" / "all_frames",
        "reference": 55,
    },
}


def estimate_background(frame_dir: Path) -> np.ndarray:
    # Use the complete shot. Sampling every third frame allowed long-lived sword
    # arcs to become part of the median and left grey rings after extraction.
    paths = sorted(frame_dir.glob("frame_*.png"))
    stack = [np.asarray(Image.open(path).convert("RGB"), dtype=np.uint8) for path in paths]
    return np.median(np.stack(stack, axis=0), axis=0).astype(np.uint8)


def foreground_rgba(
    path: Path,
    background: np.ndarray,
    clear_regions: list[tuple[int, int, int, int]] | None = None,
) -> Image.Image:
    rgb = np.asarray(Image.open(path).convert("RGB"), dtype=np.int16)
    delta = np.max(np.abs(rgb - background.astype(np.int16)), axis=2)
    alpha = np.clip((delta - 7) * 15, 0, 255).astype(np.uint8)
    # Remove tiny compression noise while preserving thin sword lines.
    alpha[alpha < 42] = 0
    for left, top, right, bottom in clear_regions or []:
        alpha[top:bottom, left:right] = 0
    rgba = np.dstack((rgb.astype(np.uint8), alpha))
    return Image.fromarray(rgba, "RGBA")


def opaque_bbox(image: Image.Image, threshold: int = 110) -> tuple[int, int, int, int]:
    alpha = np.asarray(image.getchannel("A"))
    ys, xs = np.where(alpha > threshold)
    if not len(xs):
        raise RuntimeError("No foreground subject detected")
    return int(xs.min()), int(ys.min()), int(xs.max() + 1), int(ys.max() + 1)


def opaque_center_x(image: Image.Image, threshold: int = 160) -> float:
    alpha = np.asarray(image.getchannel("A"))
    ys, xs = np.where(alpha > threshold)
    if not len(xs):
        return image.width / 2
    return float(np.median(xs))


def find_ground_y(background: np.ndarray) -> int:
    gray = background.mean(axis=2)
    row_score = gray[:, : int(gray.shape[1] * 0.82)].mean(axis=1)
    start = int(gray.shape[0] * 0.55)
    end = int(gray.shape[0] * 0.85)
    return start + int(np.argmin(row_score[start:end]))


def checkerboard(size: tuple[int, int]) -> Image.Image:
    image = Image.new("RGBA", size)
    draw = ImageDraw.Draw(image)
    tile = 16
    for y in range(0, size[1], tile):
        for x in range(0, size[0], tile):
            value = 52 if (x // tile + y // tile) % 2 else 76
            draw.rectangle((x, y, x + tile - 1, y + tile - 1), fill=(value, value, value, 255))
    return image


def build_job(name: str, config: dict) -> None:
    background = estimate_background(config["all_frames"])
    ground_y = config.get("ground_y", find_ground_y(background))
    reference_path = config["all_frames"] / f"frame_{config['reference']:03d}.png"
    reference = foreground_rgba(reference_path, background, config.get("clear_regions"))
    ref_bbox = opaque_bbox(reference)
    scale = TARGET_REFERENCE_HEIGHT / (ref_bbox[3] - ref_bbox[1])

    destination = OUTPUT_ROOT / name
    destination.mkdir(parents=True)
    # Preserve Godot's sidecar import metadata when rebuilding source PNGs.
    for old_frame in destination.glob("frame_*.png"):
        old_frame.unlink()
    processed: list[Image.Image] = []

    for output_index, source_path in enumerate(sorted(config["frames"].glob("*.png"))):
        foreground = foreground_rgba(source_path, background, config.get("clear_regions"))
        resized = foreground.resize(
            (round(foreground.width * scale), round(foreground.height * scale)),
            Image.Resampling.NEAREST,
        )
        center_x = opaque_center_x(resized)
        canvas = Image.new("RGBA", CANVAS_SIZE)
        x = round(ANCHOR[0] - center_x)
        y = round(ANCHOR[1] - ground_y * scale)
        canvas.alpha_composite(resized, (x, y))
        canvas.save(destination / f"frame_{output_index:03d}.png")
        processed.append(canvas)

    preview = checkerboard((1024, 512 * len(processed)))
    for index, frame in enumerate(processed):
        preview.alpha_composite(frame, (0, index * 512))
        ImageDraw.Draw(preview).text((8, index * 512 + 8), f"{name} frame_{index:03d}", fill="yellow")
    PREVIEW_ROOT.mkdir(parents=True, exist_ok=True)
    preview.convert("RGB").save(PREVIEW_ROOT / f"{name}_vertical.jpg", quality=94)
    print(f"{name}: {len(processed)} frames, scale={scale:.4f}, source_ground={ground_y}")


def main() -> None:
    for name, config in JOBS.items():
        build_job(name, config)


if __name__ == "__main__":
    main()
