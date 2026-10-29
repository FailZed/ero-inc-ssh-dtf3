"""Build experimental separated Cubism PSDs from the original concept cutouts.

This is a geometric cut-up for rigging research. It does not paint hidden
anatomy, so joints/face still need manual redraw before production use.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "reference"
OUTPUT = ROOT / "layered"


def largest_component(mask: np.ndarray) -> np.ndarray:
    count, labels, stats, _ = cv2.connectedComponentsWithStats(mask.astype(np.uint8), 8)
    if count <= 1:
        return np.zeros_like(mask, dtype=bool)
    component = 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA])
    return labels == component


def expand(mask: np.ndarray, pixels: int) -> np.ndarray:
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (pixels * 2 + 1,) * 2)
    return cv2.dilate(mask.astype(np.uint8), kernel) != 0


def split(image: np.ndarray, form: str) -> dict[str, np.ndarray]:
    height, width = image.shape[:2]
    yy, xx = np.mgrid[:height, :width]
    red, green, blue, alpha = [image[:, :, i].astype(np.int16) for i in range(4)]
    subject = alpha > 8
    shirt_bottom = {"lean": 657, "medium": 682, "full": 770}[form]
    shirt_seed = (
        subject & (yy >= 225) & (yy < shirt_bottom)
        & (red < 125) & ((blue - red) > 5)
    )
    shirt_seed = cv2.morphologyEx(
        shirt_seed.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8)
    ) != 0
    shirt = expand(largest_component(shirt_seed), 5) & subject

    arm_skin = (
        subject & (yy >= 385) & (yy < 900) & (red > 115)
        & (red > green + 22) & (green > blue + 14)
    )
    arm_left = expand(largest_component(arm_skin & (xx < width // 2)), 3) & subject & ~shirt
    arm_right = expand(largest_component(arm_skin & (xx >= width // 2)), 3) & subject & ~shirt

    # Assign every opaque pixel to exactly one layer. Edge ink is deliberately
    # kept with whichever body part owns that pixel, so the neutral composite
    # reproduces the original cutout without overpainting.
    pending = subject.copy()
    masks: dict[str, np.ndarray] = {}

    def take(name: str, proposal: np.ndarray) -> None:
        nonlocal pending
        masks[name] = pending & proposal
        pending &= ~masks[name]

    take("shirt_torso_and_sleeves", shirt)
    take("left_arm_hand", arm_left)
    take("right_arm_hand", arm_right)
    take("hair_front", (yy < 168) & (red < 125) & (xx > 300) & (xx < 725))
    take("head_neck", yy < 300)
    take("left_shoe", (yy >= 1400) & (xx < width // 2))
    take("right_shoe", (yy >= 1400) & (xx >= width // 2))
    take("pelvis", yy < 850)
    take("left_leg", xx < width // 2)
    take("right_leg", pending)
    assert not pending.any()
    return masks


def make_layer(source: np.ndarray, mask: np.ndarray) -> Image.Image:
    rgba = source.copy()
    rgba[:, :, 3] = np.where(mask, rgba[:, :, 3], 0)
    rgba[~mask, :3] = 0
    return Image.fromarray(rgba, "RGBA")


def build(form: str) -> dict:
    image = np.array(Image.open(SOURCE / f"{form}-concept.png").convert("RGBA"))
    masks = split(image, form)
    folder = OUTPUT / form
    folder.mkdir(parents=True, exist_ok=True)
    counts = {}
    for name, mask in masks.items():
        layer = make_layer(image, mask)
        layer.save(folder / f"{name}.png")
        ys, xs = np.nonzero(mask)
        if len(xs) == 0:
            continue
        counts[name] = int(mask.sum())
    if len(counts) != 10:
        raise ValueError(f"{form}: expected 10 populated layers, got {len(counts)}")
    psd_path = folder / f"{form}-segmented-pilot.psd"
    subprocess.run(["node", str(ROOT / "write_layered_psd.js"), form, str(psd_path)], check=True)
    return {"form": form, "psd": str(psd_path.relative_to(ROOT)), "layers": counts,
            "status": "segmented_pilot_not_rig_ready"}


def main() -> None:
    results = [build(form) for form in ("lean", "medium", "full")]
    (OUTPUT / "manifest.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
