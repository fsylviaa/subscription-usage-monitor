#!/usr/bin/env python3
"""Extract unchanged native PNG bytes from saved Figma gallery HTML.

Example:
  python3 design/tools/extract-native-gallery.py \
    --manifest design/delivery-light.json design/delivery-dark.json \
    --html /path/to/figma-r4-gallery.html /path/to/another-gallery.html \
    --output design/review-r4/native --report design/native-images.json

Each manifest is a deliveryReadOnlyStage JSON object with a `manifest` array,
an array of {id, filename} rows, or an array of those delivery reports.
Partial batches are allowed; --require-complete requires every manifest ID.
No Figma access, network access, raster processing, or image re-encoding occurs.
"""

import argparse
import base64
import binascii
import hashlib
import json
from html.parser import HTMLParser
from pathlib import Path


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


class GalleryParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.figure_id = None
        self.images = []

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == "figure":
            if self.figure_id is not None:
                raise ValueError("Nested gallery figures are unsupported")
            self.figure_id = values.get("data-id")
        elif tag == "img" and self.figure_id:
            self.images.append((self.figure_id, values.get("src", "")))

    def handle_endtag(self, tag):
        if tag == "figure":
            self.figure_id = None


def manifest_rows(value):
    if isinstance(value, dict) and isinstance(value.get("manifest"), list):
        yield from manifest_rows(value["manifest"])
    elif isinstance(value, dict) and "id" in value and "filename" in value:
        yield value
    elif isinstance(value, list):
        for item in value:
            yield from manifest_rows(item)
    else:
        raise ValueError("Manifest must contain delivery reports or {id, filename} rows")


def read_manifest(paths):
    by_id, by_filename = {}, {}
    for path in paths:
        value = json.loads(path.read_text(encoding="utf-8"))
        for row in manifest_rows(value):
            node_id, filename = row["id"], row["filename"]
            if not isinstance(node_id, str) or not node_id.strip():
                raise ValueError(f"Invalid manifest node ID in {path}")
            if (not isinstance(filename, str) or not filename.endswith(".png")
                    or Path(filename).name != filename or "/" in filename
                    or "\\" in filename or "\x00" in filename):
                raise ValueError(f"Unsafe or non-PNG filename for {node_id}")
            if node_id in by_id and by_id[node_id]["filename"] != filename:
                raise ValueError(f"Conflicting filenames for node {node_id}")
            if filename in by_filename and by_filename[filename] != node_id:
                raise ValueError(f"Filename {filename} maps to multiple nodes")
            by_id[node_id] = row
            by_filename[filename] = node_id
    if not by_id:
        raise ValueError("Manifest has no image rows")
    return by_id


def collect_images(paths, manifest):
    images = {}
    for path in paths:
        parser = GalleryParser()
        parser.feed(path.read_text(encoding="utf-8"))
        parser.close()
        if not parser.images:
            raise ValueError(f"No figure data-id images in {path}")
        for node_id, uri in parser.images:
            if node_id not in manifest:
                raise ValueError(f"Gallery node {node_id} is absent from the manifest ({path})")
            prefix = "data:image/png;base64,"
            if not uri.startswith(prefix):
                raise ValueError(f"Node {node_id} does not contain a base64 PNG")
            try:
                data = base64.b64decode("".join(uri[len(prefix):].split()), validate=True)
            except (ValueError, binascii.Error) as error:
                raise ValueError(f"Invalid PNG base64 for node {node_id}") from error
            if not data.startswith(PNG_SIGNATURE):
                raise ValueError(f"Invalid PNG signature for node {node_id}")
            if node_id in images and images[node_id]["data"] != data:
                raise ValueError(f"Conflicting exports for node {node_id}; use one final export")
            image = images.setdefault(node_id, {"data": data, "sources": []})
            if str(path) not in image["sources"]:
                image["sources"].append(str(path))
    return images


def extract(args):
    manifest = read_manifest(args.manifest)
    images = collect_images(args.html, manifest)
    missing = [node_id for node_id in manifest if node_id not in images]
    if args.require_complete and missing:
        raise ValueError(f"Missing {len(missing)} manifest images: {', '.join(missing)}")
    # Validate every destination before writing any image. Existing identical
    # exports are retained; different bytes require a different output folder.
    for node_id, image in images.items():
        destination = args.output / manifest[node_id]["filename"]
        if destination.is_symlink():
            raise ValueError(f"Refusing symlink destination: {destination}")
        if destination.exists() and (not destination.is_file() or destination.read_bytes() != image["data"]):
            raise ValueError(f"Existing export differs: {destination}")
    if args.report and args.report.resolve() in {(args.output / row["filename"]).resolve() for row in manifest.values()}:
        raise ValueError("Report path must not overwrite an image")
    args.output.mkdir(parents=True, exist_ok=True)
    records = []
    for node_id, row in manifest.items():
        if node_id not in images:
            continue
        image = images[node_id]
        destination = args.output / row["filename"]
        if not destination.exists():
            with destination.open("xb") as handle:
                handle.write(image["data"])
        records.append({"id": node_id, "filename": row["filename"], "path": str(destination),
                        "bytes": len(image["data"]), "sha256": hashlib.sha256(image["data"]).hexdigest(),
                        "sourceHtml": image["sources"]})
    report = {"nativeBytesUnchanged": True, "reencoded": False,
              "expectedCount": len(manifest), "extractedCount": len(records),
              "complete": not missing, "missingIds": missing, "images": records}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--manifest", type=Path, nargs="+", required=True)
    parser.add_argument("--html", type=Path, nargs="+", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--require-complete", action="store_true")
    args = parser.parse_args()
    try:
        extract(args)
    except (OSError, ValueError) as error:
        parser.exit(1, f"Extraction stopped: {error}\n")


if __name__ == "__main__":
    main()
