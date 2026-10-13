"""Read alpha components and write frame regions; never modifies source images.

Generated sheets have approximate gutters. Region metadata preserves full actors
and assigns a common virtual canvas/foot origin through Godot AtlasTexture margins.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

def alpha_components(mask):
    """Connected alpha regions via row spans; avoids another runtime dependency."""
    parents = []
    spans = []
    previous = []

    def root(index):
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index

    for y, row in enumerate(mask):
        edges = np.flatnonzero(np.diff(np.pad(row.astype(np.int8), (1, 1))))
        current = []
        cursor = 0
        for x0, x1 in zip(edges[::2], edges[1::2]):
            identifier = len(parents)
            parents.append(identifier)
            while cursor < len(previous) and previous[cursor][1] < x0:
                cursor += 1
            neighbor = cursor
            while neighbor < len(previous) and previous[neighbor][0] <= x1:
                parents[root(identifier)] = root(previous[neighbor][2])
                neighbor += 1
            current.append((int(x0), int(x1), identifier))
            spans.append((identifier, int(x0), int(x1), y))
        previous = current
    components = {}
    for identifier, x0, x1, y in spans:
        key = root(identifier)
        if key not in components:
            components[key] = [0, x0, y, x1, y + 1]
        extent = components[key]
        extent[0] += x1 - x0
        extent[1] = min(extent[1], x0)
        extent[2] = min(extent[2], y)
        extent[3] = max(extent[3], x1)
        extent[4] = max(extent[4], y + 1)
    return components.values()


def index(path):
    with Image.open(path) as image:
        alpha = np.asarray(image.convert("RGBA"))[:, :, 3]
    height, width = alpha.shape
    candidates = {}
    for count, x0, y0, x1, y1 in alpha_components(alpha >= 80):
        if count < 600:
            continue
        cy, cx = (y0 + y1) / 2, (x0 + x1) / 2
        row = min(3, int(cy * 4 / height))
        column = min(3, int(cx * 4 / width))
        key = row * 4 + column
        if key not in candidates or count > candidates[key][0]:
            candidates[key] = (count, [x0, y0, x1 - x0, y1 - y0])
    if len(candidates) != 16:
        raise ValueError(f"{path}: identified {len(candidates)}/16 main actor frames")
    regions = [candidates[i][1] for i in range(16)]
    # One scale for the whole sheet: animation must not resize each pose independently.
    canvas_side = max(max(rect[2:]) for rect in regions) * 1.20
    for i, rect in enumerate(regions):
        if rect[2] > width / 4 * 1.25 or rect[3] > height / 4 * 1.25:
            raise ValueError(f"{path}: frame {i} overlaps neighboring actor")
    return {"schema_version": 1, "source_size": [width, height], "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "virtual_canvas": canvas_side, "foot_baseline_fraction": 0.88, "regions": regions}


def main(directory):
    for path in sorted(directory.glob("*.png")):
        metadata = index(path)
        path.with_suffix(".json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
        print(f"{path.name}: indexed 16 full actor regions", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    main(parser.parse_args().directory)
