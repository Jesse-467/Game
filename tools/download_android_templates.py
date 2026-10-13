"""Fetch the two Android entries from Godot's official template ZIP using ranges.

The 1.28GB bundle includes unrelated platforms. Entry CRCs are checked; the
bundle's published SHA256 cannot be checked without downloading the full bundle.
"""
import argparse
import json
import pathlib
import struct
import subprocess
import urllib.request
import zlib

URL = "https://godot-releases.nbg1.your-objectstorage.com/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"
SIZE = 1281349702


def fetch_chunk(start, end):
    request = urllib.request.Request(URL, headers={"Range": f"bytes={start}-{end}"})
    with urllib.request.urlopen(request, timeout=60) as response:
        expected = f"bytes {start}-{end}/{SIZE}"
        if response.status != 206 or response.headers.get("Content-Range") != expected:
            raise RuntimeError("Official host did not honor the requested range")
        data = response.read()
    if len(data) != end - start + 1:
        raise RuntimeError("Incomplete range download")
    return data


def fetch(start, end):
    # Keep transfers below proxy idle limits; verified chunks survive interruptions.
    cache = pathlib.Path(".tools/template-ranges")
    cache.mkdir(parents=True, exist_ok=True)
    parts = []
    for offset in range(start, end + 1, 4 * 1048576):
        last = min(end, offset + 4 * 1048576 - 1)
        path = cache / f"{offset}-{last}.bin"
        if path.exists() and path.stat().st_size == last - offset + 1:
            part = path.read_bytes()
        else:
            partial = path.with_suffix(".part")
            subprocess.run(["C:/Windows/System32/curl.exe", "--silent", "--show-error", "--fail", "--location", "--connect-timeout", "15", "--max-time", "90", "--retry", "2", "--range", f"{offset}-{last}", "--output", str(partial), URL], check=True)
            part = partial.read_bytes()
            if len(part) != last - offset + 1:
                raise RuntimeError("Incomplete curl range")
            partial.replace(path)
        parts.append(part)
    return b"".join(parts)


def main(destination):
    destination.mkdir(parents=True, exist_ok=True)
    tail = fetch(SIZE - 65536, SIZE - 1)
    eocd = tail.rfind(b"PK\x05\x06")
    if eocd < 0:
        raise RuntimeError("ZIP footer missing")
    footer = struct.unpack_from("<4s4H2IH", tail, eocd)
    directory_size, directory_offset = footer[5:7]
    directory = fetch(directory_offset, directory_offset + directory_size - 1)
    cursor = 0
    entries = []
    while cursor < len(directory):
        fields = struct.unpack_from("<4s6H3I5H2I", directory, cursor)
        if fields[0] != b"PK\x01\x02":
            raise RuntimeError("Invalid ZIP directory entry")
        name_length, extra_length, comment_length = fields[10:13]
        name = directory[cursor + 46:cursor + 46 + name_length].decode()
        if name in ("templates/android_debug.apk", "templates/android_release.apk"):
            entries.append((name, fields[4], fields[7], fields[8], fields[9], fields[16]))
        cursor += 46 + name_length + extra_length + comment_length
    if len(entries) != 2:
        raise RuntimeError("Required Android templates missing")
    report = {"version": "4.7.2.stable", "source": URL, "verification": "ZIP entry CRC32", "files": []}
    for name, compression, crc, compressed_size, size, offset in entries:
        print(f"Downloading {name}: {compressed_size / 1048576:.1f} MiB", flush=True)
        header = fetch(offset, offset + 29)
        local = struct.unpack("<4s5H3I2H", header)
        data_offset = offset + 30 + local[-2] + local[-1]
        compressed = fetch(data_offset, data_offset + compressed_size - 1)
        content = zlib.decompress(compressed, -15) if compression == 8 else compressed
        if len(content) != size or zlib.crc32(content) != crc:
            raise RuntimeError(f"Corrupt ZIP entry: {name}")
        path = destination / pathlib.PurePosixPath(name).name
        path.write_bytes(content)
        report["files"].append({"name": path.name, "bytes": size, "crc32": f"{crc:08x}"})
        print(f"Verified {path.name}", flush=True)
    (destination / "download-manifest.json").write_text(json.dumps(report, indent=2), encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("destination", type=pathlib.Path)
    main(parser.parse_args().destination)
