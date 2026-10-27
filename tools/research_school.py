"""Read-only School RPA inventory. Never imports or executes donor scripts.

Raw sources stay outside the Godot project. The committed manifest contains only
paths, hashes, line counts and declaration names, not donor implementations.
Uses the RPA-3 layout documented by the donor's renpy/loader.py.
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import io
import json
import pickle
import re
import zlib
from pathlib import Path, PurePosixPath


class IndexReader(pickle.Unpickler):
    def find_class(self, module, name):
        raise ValueError(f"Executable pickle entry rejected: {module}.{name}")


def read_entry(stream, chunks, key):
    content = bytearray()
    for chunk in chunks:
        offset, length = chunk[0] ^ key, chunk[1] ^ key
        prefix = chunk[2] if len(chunk) > 2 else b""
        if isinstance(prefix, str):
            prefix = prefix.encode("latin-1")
        stream.seek(offset)
        content.extend(prefix)
        content.extend(stream.read(length))
    return content


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("donor", type=Path)
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--extract-compiled", action="store_true", help="Extract only compiled modules lacking an original .rpy, outside the project")
    parser.add_argument("--decompiled-workspace", type=Path, help="Index independently decompiled files; never executes them")
    parser.add_argument("--decompiler-revision", help="Provenance revision for the separate decompiler tool")
    args = parser.parse_args()
    donor = args.donor.resolve()
    workspace = args.workspace.resolve()
    project = Path(__file__).resolve().parents[1]
    if workspace.is_relative_to(project) or workspace.is_relative_to(donor):
        parser.error("Raw research workspace must be outside both projects")
    archive = donor / "game/archive.rpa"
    files = []
    with archive.open("rb") as stream:
        header = stream.readline().split()
        if header[0] != b"RPA-3.0":
            raise ValueError("Only RPA-3.0 is supported")
        stream.seek(int(header[1], 16))
        index = IndexReader(io.BytesIO(zlib.decompress(stream.read()))).load()
        key = int(header[2], 16)
        for raw_name, chunks in sorted(index.items()):
            name = raw_name.decode("utf-8") if isinstance(raw_name, bytes) else raw_name
            relative = PurePosixPath(name)
            if relative.is_absolute() or ".." in relative.parts or ":" in name or "\\" in name:
                raise ValueError(f"Unsafe archive path: {name}")
            if args.extract_compiled and name.endswith(".rpyc") and not name.startswith("tl/") and name[:-1] not in index:
                compiled_path = workspace / "compiled" / name
                compiled_path.parent.mkdir(parents=True, exist_ok=True)
                compiled_path.write_bytes(read_entry(stream, chunks, key))
            if not name.endswith(".rpy") or name.startswith("tl/"):
                continue
            content = read_entry(stream, chunks, key)
            text = content.decode("utf-8-sig")
            output = workspace / "source" / name
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(text, encoding="utf-8", newline="")
            declarations = []
            for number, line in enumerate(text.splitlines(), 1):
                match = re.match(r"\s*(def|class|label|screen|default|define)\s+([\w.]+)", line)
                if match:
                    declarations.append({"kind": match[1], "name": match[2], "line": number})
            files.append({"path": name, "sha256": hashlib.sha256(content).hexdigest(),
                          "bytes": len(content), "lines": len(text.splitlines()),
                          "declarations": declarations})
    for loose in sorted((donor / "files_for_").glob("*.rpy")):
        text = loose.read_text(encoding="utf-8-sig")
        output = workspace / "source/files_for_" / loose.name
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(text, encoding="utf-8", newline="")
        files.append({"path": "files_for_/" + loose.name,
                      "sha256": hashlib.sha256(loose.read_bytes()).hexdigest(),
                      "bytes": loose.stat().st_size, "lines": len(text.splitlines()),
                      "declarations": [{"kind": m[1], "name": m[2], "line": i}
                                       for i, line in enumerate(text.splitlines(), 1)
                                       if (m := re.match(r"\s*(def|class|label|screen)\s+([\w.]+)", line))]})
    missing = sorted(str(name) for name in index if str(name).endswith(".rpyc")
                     and not str(name).startswith("tl/") and str(name)[:-1] not in index)
    report = {"donor": donor.name, "format": "RPA-3.0", "method": "static text inspection; no donor execution",
              "archive_bytes": archive.stat().st_size, "archive_entries": len(index),
              "file_count": len(files), "line_count": sum(f["lines"] for f in files),
              "compiled_without_source": missing, "files": files}
    with archive.open("rb") as fingerprint_stream:
        report["archive_sha256"] = hashlib.file_digest(fingerprint_stream, "sha256").hexdigest()
    if args.decompiled_workspace:
        decompiled_root = args.decompiled_workspace.resolve()
        if decompiled_root.is_relative_to(project) or decompiled_root.is_relative_to(donor):
            parser.error("Decompiled research must stay outside both projects")
        recovered = []
        for name in missing:
            decompiled = decompiled_root / name[:-1]
            if not decompiled.is_file():
                continue
            text = decompiled.read_text(encoding="utf-8-sig")
            recovered.append({"archive_path": name, "reconstructed_path": name[:-1],
                              "sha256": hashlib.sha256(decompiled.read_bytes()).hexdigest(),
                              "lines": len(text.splitlines()),
                              "declarations": [{"kind": m[1], "name": m[2], "line": i}
                                               for i, line in enumerate(text.splitlines(), 1)
                                               if (m := re.match(r"\s*(def|class|label|screen)\s+([\w.]+)", line))]})
        report["recovered_compiled"] = recovered
        report["unrecovered_compiled"] = [name for name in missing if name not in {entry["archive_path"] for entry in recovered}]
        report["decompiler"] = {"name": "unrpyc", "url": "https://github.com/CensoredUsername/unrpyc", "revision": args.decompiler_revision}
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    args.manifest.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k not in {"files", "recovered_compiled"}}, ensure_ascii=False, indent=2))
    if "recovered_compiled" in report:
        print("Recovered compiled modules:", len(report["recovered_compiled"]))
    print("Largest files:")
    for entry in sorted(files, key=lambda f: f["lines"], reverse=True)[:25]:
        print(f"{entry['lines']:7} {entry['path']}")


if __name__ == "__main__":
    main()
