"""Download only Windows members of the official Godot export ZIP (stdlib)."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import struct
import urllib.request
import urllib.error
import zipfile
import zlib
import time
import http.client
from concurrent.futures import ThreadPoolExecutor

VERSION = "4.7.2"
ROOT = Path(__file__).resolve().parents[1]
OFFICIAL = f"https://downloads.godotengine.org/?flavor=stable&platform=templates&slug=export_templates.tpz&version={VERSION}"
# Official redirect destination; useful when the redirector rejects Python's TLS client.
MIRROR = f"https://godot-releases.nbg1.your-objectstorage.com/{VERSION}-stable/Godot_v{VERSION}-stable_export_templates.tpz"
NAMES = {"windows_release_x86_64.exe", "windows_debug_x86_64.exe"}

def request(url, byte_range=None):
    headers = {"User-Agent": "EmpireFront-Godot-Builder/2.0", "Accept-Encoding": "identity"}
    if byte_range:
        headers["Range"] = "bytes=" + byte_range
    for attempt in range(4):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=120)
        except urllib.error.HTTPError:
            raise
        except (urllib.error.URLError, OSError):
            if attempt == 3:
                raise
            time.sleep(attempt + 1)

def ranged(url, start, end):
    # The official mirror can throttle each connection. Independent small ranges
    # retain CRC verification while avoiding a several-minute single transfer.
    if end - start + 1 > 2 * 1024 * 1024:
        chunk = 1024 * 1024
        spans = [(position, min(end, position + chunk - 1)) for position in range(start, end + 1, chunk)]
        with ThreadPoolExecutor(max_workers=8) as workers:
            blocks = list(workers.map(lambda span: ranged(url, *span), spans))
        return b"".join(blocks)
    for attempt in range(4):
        try:
            return _range_once(url, start, end)
        except (urllib.error.URLError, OSError, http.client.HTTPException):
            if attempt == 3:
                raise
            time.sleep(attempt + 1)

def _range_once(url, start, end):
    with request(url, f"{start}-{end}") as response:
        if response.status != 206:
            raise RuntimeError("Server does not support HTTP Range")
        expected = f"bytes {start}-{end}/"
        if not response.headers.get("Content-Range", "").startswith(expected):
            raise RuntimeError("Unexpected Content-Range")
        blocks = []
        received = 0
        while block := response.read(1024 * 1024):
            blocks.append(block)
            received += len(block)
            if end - start > 8 * 1024 * 1024 and received % (8 * 1024 * 1024) == 0:
                print(f"  {received / 1024 / 1024:.0f} MiB received", flush=True)
        blob = b"".join(blocks)
    if len(blob) != end - start + 1:
        raise RuntimeError("Incomplete ranged download")
    return blob

def download(output: Path, allow_full=False):
    output.mkdir(parents=True, exist_ok=True)
    manifest_path = output / "manifest.json"
    if manifest_path.exists():
        try:
            cached = json.loads(manifest_path.read_text(encoding="utf-8"))
            files = cached.get("files", {})
            verified = cached.get("version") == VERSION and set(files) == NAMES
            for name in NAMES:
                target = output / name
                info = files.get(name, {})
                verified = verified and target.exists() and target.stat().st_size == info.get("size")
                if verified:
                    verified = zlib.crc32(target.read_bytes()) == int(info["crc32"], 16)
            if verified:
                print("Local Windows templates verified (offline)", flush=True)
                return
        except (ValueError, KeyError, OSError):
            pass
    url = OFFICIAL
    try:
        response = request(url, "-65557")
    except urllib.error.HTTPError as exc:
        if exc.code != 403:
            raise
        url = MIRROR
        response = request(url, "-65557")
    with response:
        url = response.geturl()
        if response.status != 206:
            if not allow_full:
                raise RuntimeError("Range unavailable; use --allow-full-download to download the complete official package")
            archive = output / "export_templates.tpz"
            with archive.open("wb") as file:
                while block := response.read(1024 * 1024):
                    file.write(block)
            with zipfile.ZipFile(archive) as package:
                for item in package.infolist():
                    if Path(item.filename).name in NAMES:
                        blob = package.read(item)  # ZIP library validates CRC.
                        (output / Path(item.filename).name).write_bytes(blob)
            return
        tail = response.read()
    eocd = tail.rfind(b"PK\x05\x06")
    if eocd < 0:
        raise RuntimeError("ZIP end directory missing")
    record = struct.unpack_from("<4s4H2LH", tail, eocd)
    central_size, central_offset = record[5:7]
    if central_offset == 0xFFFFFFFF or central_size == 0xFFFFFFFF:
        raise RuntimeError("ZIP64 package unsupported")
    central = ranged(url, central_offset, central_offset + central_size - 1)
    offset = 0
    manifest = {"version": VERSION, "official_url": OFFICIAL, "resolved_url": url, "files": {}}
    while offset < len(central):
        fields = struct.unpack_from("<4s6H3L5H2L", central, offset)
        if fields[0] != b"PK\x01\x02":
            raise RuntimeError("Invalid ZIP central directory")
        compression, crc, packed, unpacked = fields[4], fields[7], fields[8], fields[9]
        name_len, extra_len, comment_len = fields[10:13]
        name = central[offset + 46:offset + 46 + name_len].decode("utf-8")
        basename = Path(name).name
        local_offset = fields[16]
        offset += 46 + name_len + extra_len + comment_len
        if basename not in NAMES:
            continue
        target = output / basename
        if target.exists() and target.stat().st_size == unpacked and zlib.crc32(target.read_bytes()) == crc:
            print(f"Verified existing {basename}", flush=True)
        else:
            print(f"Downloading {basename}: {packed / 1024 / 1024:.1f} MiB", flush=True)
            local = ranged(url, local_offset, local_offset + 29)
            if local[:4] != b"PK\x03\x04":
                raise RuntimeError("Invalid ZIP local header")
            local_name, local_extra = struct.unpack_from("<2H", local, 26)
            start = local_offset + 30 + local_name + local_extra
            compressed = ranged(url, start, start + packed - 1)
            blob = zlib.decompress(compressed, -15) if compression == 8 else compressed
            if compression not in (0, 8) or len(blob) != unpacked or zlib.crc32(blob) != crc:
                raise RuntimeError(f"CRC or length mismatch: {basename}")
            temporary = target.with_suffix(".partial")
            temporary.write_bytes(blob)
            temporary.replace(target)
        manifest["files"][basename] = {"size": unpacked, "crc32": f"{crc:08x}"}
    if set(manifest["files"]) != NAMES:
        raise RuntimeError("Windows templates missing from archive")
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print("Windows templates verified", flush=True)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "tools/godot-runtime/templates")
    parser.add_argument("--allow-full-download", action="store_true")
    options = parser.parse_args()
    download(options.output, options.allow_full_download)
