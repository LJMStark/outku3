#!/usr/bin/env python3
"""Split and normalize AI-generated companion action sheets for XCAssets."""

from __future__ import annotations

import argparse
import json
import re
from collections import deque
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


DEFAULT_MOTIONS = ("idle", "greet", "focus", "celebrate", "react")


@dataclass(frozen=True)
class Grid:
    rows: int
    columns: int
    margin_x: int = 0
    margin_y: int = 0
    gutter_x: int = 0
    gutter_y: int = 0

    def bounds(self, image_size: tuple[int, int], row: int, column: int) -> tuple[int, int, int, int]:
        width, height = image_size
        usable_width = width - (2 * self.margin_x) - ((self.columns - 1) * self.gutter_x)
        usable_height = height - (2 * self.margin_y) - ((self.rows - 1) * self.gutter_y)
        if usable_width <= 0 or usable_height <= 0:
            raise ValueError("Grid margins and gutters leave no usable pixels")

        left = self.margin_x + round(column * usable_width / self.columns) + column * self.gutter_x
        right = self.margin_x + round((column + 1) * usable_width / self.columns) + column * self.gutter_x
        top = self.margin_y + round(row * usable_height / self.rows) + row * self.gutter_y
        bottom = self.margin_y + round((row + 1) * usable_height / self.rows) + row * self.gutter_y
        return left, top, right, bottom


def _is_connected_background(pixel: tuple[int, int, int, int]) -> bool:
    red, green, blue, _ = pixel
    return max(red, green, blue) - min(red, green, blue) <= 18 and min(red, green, blue) >= 205


def remove_edge_connected_background(image: Image.Image) -> Image.Image:
    """Make a baked neutral checkerboard transparent without erasing enclosed white fur."""
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    width, height = rgba.size
    pending: deque[tuple[int, int]] = deque()
    visited = bytearray(width * height)

    for x in range(width):
        pending.append((x, 0))
        pending.append((x, height - 1))
    for y in range(height):
        pending.append((0, y))
        pending.append((width - 1, y))

    while pending:
        x, y = pending.popleft()
        index = y * width + x
        if visited[index]:
            continue
        visited[index] = 1
        if not _is_connected_background(pixels[x, y]):
            continue

        red, green, blue, _ = pixels[x, y]
        pixels[x, y] = (red, green, blue, 0)
        if x > 0:
            pending.append((x - 1, y))
        if x + 1 < width:
            pending.append((x + 1, y))
        if y > 0:
            pending.append((x, y - 1))
        if y + 1 < height:
            pending.append((x, y + 1))

    return rgba


def normalize_frame(
    frame: Image.Image,
    canvas_size: int,
    placement: str,
    padding: int,
    vertical_lift: int = 0,
    remove_background: bool = True,
    resampling: str = "nearest",
) -> Image.Image:
    frame = remove_edge_connected_background(frame) if remove_background else frame.convert("RGBA")
    canvas = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    resample_filter = (
        Image.Resampling.NEAREST if resampling == "nearest" else Image.Resampling.LANCZOS
    )

    if placement == "trim":
        alpha_box = frame.getchannel("A").getbbox()
        if alpha_box is None:
            raise ValueError("Frame contains no foreground after background removal")
        frame = frame.crop(alpha_box)
        available = canvas_size - (2 * padding) - vertical_lift
        if available <= 0:
            raise ValueError("Padding and vertical lift leave no usable canvas")
        scale = min(available / frame.width, available / frame.height)
        target = (max(1, round(frame.width * scale)), max(1, round(frame.height * scale)))
        frame = frame.resize(target, resample_filter)
        origin = (
            (canvas_size - frame.width) // 2,
            canvas_size - padding - vertical_lift - frame.height,
        )
    else:
        scale = min(canvas_size / frame.width, canvas_size / frame.height)
        target = (max(1, round(frame.width * scale)), max(1, round(frame.height * scale)))
        frame = frame.resize(target, resample_filter)
        origin = ((canvas_size - frame.width) // 2, (canvas_size - frame.height) // 2)

    canvas.alpha_composite(frame, origin)
    return canvas


def write_imageset(catalog: Path, name: str, frame: Image.Image) -> Path:
    imageset = catalog / f"{name}.imageset"
    imageset.mkdir(parents=True, exist_ok=True)
    png_path = imageset / f"{name}.png"
    frame.save(png_path, optimize=True)
    contents = {
        "images": [
            {
                "filename": png_path.name,
                "idiom": "universal",
                "scale": "1x",
            }
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (imageset / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")
    return png_path


def validate_export(name: str, path: Path, canvas_size: int) -> None:
    if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)+-\d{2}", name):
        raise ValueError(f"Invalid deterministic frame name: {name}")
    if path.suffix.lower() != ".png":
        raise ValueError(f"Frame is not PNG: {path}")
    with Image.open(path) as image:
        if image.format != "PNG" or image.mode != "RGBA":
            raise ValueError(f"Frame must be an RGBA PNG: {path}")
        if image.size != (canvas_size, canvas_size):
            raise ValueError(f"Frame has unexpected dimensions: {path} {image.size}")


def write_manifest(
    frames: list[tuple[str, Path]],
    output: Path,
    canvas_size: int,
    anchor_y: float,
) -> None:
    payload = {
        "canvas": {"width": canvas_size, "height": canvas_size},
        "frameCount": len(frames),
        "frames": [
            {
                "name": name,
                "file": str(path),
                "anchor": {"x": 0.5, "y": anchor_y},
            }
            for name, path in frames
        ],
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def write_contact_sheet(
    frames: list[tuple[str, Image.Image]],
    output: Path,
    columns: int,
) -> None:
    thumb = 180
    label_height = 28
    rows = (len(frames) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * thumb, rows * (thumb + label_height)), "#F4F1EA")
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()

    for index, (name, frame) in enumerate(frames):
        row, column = divmod(index, columns)
        preview = Image.new("RGBA", (thumb, thumb), (255, 255, 255, 255))
        preview.alpha_composite(frame.resize((thumb, thumb), Image.Resampling.LANCZOS))
        x = column * thumb
        y = row * (thumb + label_height)
        sheet.paste(preview.convert("RGB"), (x, y))
        draw.text((x + 6, y + thumb + 7), name, fill="#243129", font=font)

    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output, optimize=True)


def extract_component_frames(
    sheet: Image.Image,
    expected_count: int,
    columns: int,
    minimum_area: int,
    component_padding: int = 6,
) -> list[Image.Image]:
    """Extract subjects even when the generated art crosses nominal grid boundaries."""
    try:
        import cv2
        import numpy as np
    except ImportError as error:
        raise RuntimeError(
            "Component extraction requires Pillow, numpy, and opencv-python-headless"
        ) from error

    transparent = remove_edge_connected_background(sheet)
    alpha = np.array(transparent.getchannel("A"))
    count, _, stats, centroids = cv2.connectedComponentsWithStats(
        (alpha > 0).astype("uint8"),
        8,
    )
    candidates: list[tuple[int, int, int, int, int, float, float]] = []
    for label in range(1, count):
        x, y, width, height, area = (int(value) for value in stats[label])
        if area >= minimum_area:
            center_x, center_y = (float(value) for value in centroids[label])
            candidates.append((area, x, y, width, height, center_x, center_y))

    if len(candidates) < expected_count:
        raise ValueError(
            f"Expected {expected_count} foreground subjects, found {len(candidates)} "
            f"with minimum area {minimum_area}"
        )

    selected = sorted(candidates, key=lambda item: item[0], reverse=True)[:expected_count]
    selected.sort(key=lambda item: item[6])
    ordered: list[tuple[int, int, int, int, int, float, float]] = []
    for start in range(0, expected_count, columns):
        row = selected[start : start + columns]
        row.sort(key=lambda item: item[5])
        ordered.extend(row)

    frames: list[Image.Image] = []
    for _, x, y, width, height, _, _ in ordered:
        left = max(0, x - component_padding)
        top = max(0, y - component_padding)
        right = min(transparent.width, x + width + component_padding)
        bottom = min(transparent.height, y + height + component_padding)
        frames.append(transparent.crop((left, top, right, bottom)))
    return frames


def split_sheet(
    sheet_path: Path,
    character: str,
    catalog: Path,
    review_output: Path,
    grid: Grid,
    motions: tuple[str, ...],
    canvas_size: int,
    placement: str,
    padding: int,
    vertical_lifts: dict[str, tuple[int, ...]] | None = None,
    extraction: str = "grid",
    minimum_component_area: int = 500,
    layout: str = "motion-rows",
    remove_background: bool = True,
    resampling: str = "nearest",
    manifest_output: Path | None = None,
) -> list[Path]:
    if layout == "motion-rows" and len(motions) != grid.rows:
        raise ValueError("Motion count must equal grid row count")
    if layout == "single-motion" and len(motions) != 1:
        raise ValueError("Single-motion layout requires exactly one motion")

    sheet = Image.open(sheet_path).convert("RGBA")
    written: list[Path] = []
    review_frames: list[tuple[str, Image.Image]] = []
    component_frames: list[Image.Image] | None = None
    if extraction == "components":
        component_frames = extract_component_frames(
            sheet,
            expected_count=grid.rows * grid.columns,
            columns=grid.columns,
            minimum_area=minimum_component_area,
        )

    exported: list[tuple[str, Path]] = []
    cells: list[tuple[int, int, str, int]] = []
    if layout == "motion-rows":
        for row, motion in enumerate(motions):
            for column in range(grid.columns):
                cells.append((row, column, motion, column + 1))
    else:
        motion = motions[0]
        for index in range(grid.rows * grid.columns):
            row, column = divmod(index, grid.columns)
            cells.append((row, column, motion, index + 1))

    for row, column, motion, frame_index in cells:
        if component_frames is not None:
            frame = component_frames[(row * grid.columns) + column]
        else:
            frame = sheet.crop(grid.bounds(sheet.size, row, column))
        lift_values = (vertical_lifts or {}).get(motion, ())
        lift = lift_values[column] if column < len(lift_values) else 0
        frame = normalize_frame(
            frame,
            canvas_size,
            placement,
            padding,
            vertical_lift=lift,
            remove_background=remove_background,
            resampling=resampling,
        )
        name = f"{character}-{motion}-{frame_index:02d}"
        path = write_imageset(catalog, name, frame)
        validate_export(name, path, canvas_size)
        written.append(path)
        exported.append((name, path))
        review_frames.append((name, frame))

    write_contact_sheet(review_frames, review_output, grid.columns)
    if manifest_output is not None:
        anchor_y = (canvas_size - padding) / canvas_size if placement == "trim" else 1.0
        write_manifest(exported, manifest_output, canvas_size, anchor_y)
    return written


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sheet", type=Path)
    parser.add_argument("--character", required=True)
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--review-output", type=Path, required=True)
    parser.add_argument("--manifest-output", type=Path)
    parser.add_argument("--rows", type=int, default=5)
    parser.add_argument("--columns", type=int, default=4)
    parser.add_argument("--margin-x", type=int, default=0)
    parser.add_argument("--margin-y", type=int, default=0)
    parser.add_argument("--gutter-x", type=int, default=0)
    parser.add_argument("--gutter-y", type=int, default=0)
    parser.add_argument("--motions", default=",".join(DEFAULT_MOTIONS))
    parser.add_argument("--canvas-size", type=int, default=512)
    parser.add_argument("--placement", choices=("cell", "trim"), default="cell")
    parser.add_argument("--layout", choices=("motion-rows", "single-motion"), default="motion-rows")
    parser.add_argument("--background", choices=("remove", "preserve"), default="remove")
    parser.add_argument("--resampling", choices=("nearest", "lanczos"), default="nearest")
    parser.add_argument("--extraction", choices=("grid", "components"), default="grid")
    parser.add_argument("--minimum-component-area", type=int, default=500)
    parser.add_argument("--padding", type=int, default=24)
    parser.add_argument(
        "--vertical-lifts",
        default="",
        help="Semicolon-separated motion:pixel,pixel entries, for example celebrate:0,48,64,0",
    )
    return parser.parse_args()


def parse_vertical_lifts(raw: str) -> dict[str, tuple[int, ...]]:
    result: dict[str, tuple[int, ...]] = {}
    for entry in (part.strip() for part in raw.split(";") if part.strip()):
        motion, separator, values = entry.partition(":")
        if not separator:
            raise ValueError(f"Invalid vertical lift entry: {entry}")
        result[motion.strip()] = tuple(int(value.strip()) for value in values.split(","))
    return result


def main() -> None:
    args = parse_args()
    motions = tuple(part.strip() for part in args.motions.split(",") if part.strip())
    written = split_sheet(
        sheet_path=args.sheet,
        character=args.character,
        catalog=args.catalog,
        review_output=args.review_output,
        grid=Grid(
            rows=args.rows,
            columns=args.columns,
            margin_x=args.margin_x,
            margin_y=args.margin_y,
            gutter_x=args.gutter_x,
            gutter_y=args.gutter_y,
        ),
        motions=motions,
        canvas_size=args.canvas_size,
        placement=args.placement,
        padding=args.padding,
        vertical_lifts=parse_vertical_lifts(args.vertical_lifts),
        extraction=args.extraction,
        minimum_component_area=args.minimum_component_area,
        layout=args.layout,
        remove_background=args.background == "remove",
        resampling=args.resampling,
        manifest_output=args.manifest_output,
    )
    print(f"Wrote {len(written)} frames and {args.review_output}")


if __name__ == "__main__":
    main()
