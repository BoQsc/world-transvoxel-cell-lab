from __future__ import annotations

import argparse
import json
import struct
import zlib
from pathlib import Path


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def _paeth(a: int, b: int, c: int) -> int:
    estimate = a + b - c
    pa = abs(estimate - a)
    pb = abs(estimate - b)
    pc = abs(estimate - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def read_png(path: Path) -> tuple[int, int, int, bytes]:
    data = path.read_bytes()
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError(f"{path} is not a PNG")
    offset = len(PNG_SIGNATURE)
    width = height = color_type = bit_depth = 0
    compressed = bytearray()
    while offset < len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_type = data[offset + 4 : offset + 8]
        payload = data[offset + 8 : offset + 8 + length]
        offset += 12 + length
        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type = struct.unpack(
                ">IIBB", payload[:10]
            )
        elif chunk_type == b"IDAT":
            compressed.extend(payload)
        elif chunk_type == b"IEND":
            break
    if bit_depth != 8 or color_type not in (2, 6):
        raise ValueError(
            f"{path} uses unsupported PNG format depth={bit_depth} type={color_type}"
        )
    channels = 3 if color_type == 2 else 4
    stride = width * channels
    raw = zlib.decompress(bytes(compressed))
    expected = height * (stride + 1)
    if len(raw) != expected:
        raise ValueError(f"{path} has unexpected decoded byte count")
    decoded = bytearray(height * stride)
    previous = bytearray(stride)
    source_offset = 0
    for row_index in range(height):
        filter_type = raw[source_offset]
        source_offset += 1
        row = bytearray(raw[source_offset : source_offset + stride])
        source_offset += stride
        for index in range(stride):
            left = row[index - channels] if index >= channels else 0
            above = previous[index]
            upper_left = previous[index - channels] if index >= channels else 0
            if filter_type == 1:
                row[index] = (row[index] + left) & 0xFF
            elif filter_type == 2:
                row[index] = (row[index] + above) & 0xFF
            elif filter_type == 3:
                row[index] = (row[index] + ((left + above) // 2)) & 0xFF
            elif filter_type == 4:
                row[index] = (row[index] + _paeth(left, above, upper_left)) & 0xFF
            elif filter_type != 0:
                raise ValueError(f"{path} uses unsupported PNG filter {filter_type}")
        start = row_index * stride
        decoded[start : start + stride] = row
        previous = row
    if channels == 4:
        rgb = bytearray(width * height * 3)
        for pixel in range(width * height):
            rgb_start = pixel * 3
            rgba_start = pixel * 4
            rgb[rgb_start : rgb_start + 3] = decoded[rgba_start : rgba_start + 3]
        return width, height, 3, bytes(rgb)
    return width, height, channels, bytes(decoded)


def compare_images(
    reference_path: Path,
    candidate_path: Path,
    channel_threshold: int,
) -> dict[str, object]:
    ref_width, ref_height, ref_channels, reference = read_png(reference_path)
    width, height, channels, candidate = read_png(candidate_path)
    if (ref_width, ref_height, ref_channels) != (width, height, channels):
        return {
            "status": "FAIL",
            "error": "image_shape_mismatch",
            "reference_shape": [ref_width, ref_height, ref_channels],
            "candidate_shape": [width, height, channels],
        }
    pixel_count = width * height
    changed_pixels = 0
    maximum_channel_delta = 0
    total_channel_delta = 0
    for pixel in range(pixel_count):
        start = pixel * channels
        deltas = [
            abs(reference[start + channel] - candidate[start + channel])
            for channel in range(channels)
        ]
        pixel_delta = max(deltas)
        maximum_channel_delta = max(maximum_channel_delta, pixel_delta)
        total_channel_delta += sum(deltas)
        if pixel_delta > channel_threshold:
            changed_pixels += 1
    return {
        "status": "MEASURED",
        "width": width,
        "height": height,
        "channels": channels,
        "pixel_count": pixel_count,
        "changed_pixels": changed_pixels,
        "changed_ratio": changed_pixels / max(pixel_count, 1),
        "maximum_channel_delta": maximum_channel_delta,
        "mean_channel_delta": total_channel_delta
        / max(pixel_count * channels, 1),
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Compare captured Cell Lab images with committed standards."
    )
    parser.add_argument("--candidate-dir", type=Path, required=True)
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parents[3],
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path(
            "addons/world_transvoxel_cell_lab/standards/visual_manifest.json"
        ),
    )
    parser.add_argument("--output", type=Path)
    parser.add_argument("--channel-threshold", type=int, default=8)
    parser.add_argument("--maximum-changed-ratio", type=float, default=0.02)
    parser.add_argument("--maximum-mean-delta", type=float, default=2.0)
    args = parser.parse_args()

    project_root = args.project_root.resolve()
    manifest_path = (
        args.manifest
        if args.manifest.is_absolute()
        else project_root / args.manifest
    )
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    results: list[dict[str, object]] = []
    failures = 0
    for visual in manifest.get("visuals", []):
        visual_id = str(visual["id"])
        reference_relative = str(visual["path"]).removeprefix("res://")
        reference_path = project_root / reference_relative
        candidate_path = args.candidate_dir.resolve() / f"{visual_id}.png"
        entry: dict[str, object] = {
            "id": visual_id,
            "reference_path": str(reference_path),
            "candidate_path": str(candidate_path),
        }
        try:
            metrics = compare_images(
                reference_path,
                candidate_path,
                args.channel_threshold,
            )
            entry.update(metrics)
            passes = (
                metrics.get("status") == "MEASURED"
                and float(metrics["changed_ratio"]) <= args.maximum_changed_ratio
                and float(metrics["mean_channel_delta"]) <= args.maximum_mean_delta
            )
            entry["status"] = "PASS" if passes else "FAIL"
        except (OSError, ValueError, zlib.error) as error:
            entry.update({"status": "FAIL", "error": str(error)})
        if entry["status"] != "PASS":
            failures += 1
        results.append(entry)

    report = {
        "schema": "world_transvoxel.cell_lab.visual_diff.v1",
        "status": "PASS" if failures == 0 else "FAIL",
        "visual_count": len(results),
        "passing_visuals": len(results) - failures,
        "failing_visuals": failures,
        "channel_threshold": args.channel_threshold,
        "maximum_changed_ratio": args.maximum_changed_ratio,
        "maximum_mean_delta": args.maximum_mean_delta,
        "results": results,
    }
    rendered = json.dumps(report, indent=2)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
