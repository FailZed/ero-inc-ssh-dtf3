"""Import an explicitly selected temporary portrait asset set, never donor scripts.

The owner requested these images for prototyping on 2026-10-18. The output
manifest records their origin so the entire pack can be replaced later.
"""
from __future__ import annotations
import argparse, hashlib, io, json, struct, zlib
from pathlib import Path, PurePosixPath
from research_school import IndexReader, read_entry

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("selection", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    destination = args.destination.resolve()
    names = json.loads(args.selection.read_text(encoding="utf-8-sig"))
    records = []
    with args.archive.open("rb") as stream:
        header = stream.readline().split()
        if header[0] != b"RPA-3.0": raise ValueError("Unsupported archive")
        stream.seek(int(header[1],16))
        index = IndexReader(io.BytesIO(zlib.decompress(stream.read()))).load()
        key = int(header[2],16)
        for name in names:
            relative = PurePosixPath(name)
            if relative.is_absolute() or ".." in relative.parts or ":" in name or "\\" in name:
                raise ValueError("Unsafe selected path")
            if not name.startswith("images/character/") or not name.endswith(".png"):
                raise ValueError("Only selected character PNGs may be imported")
            content = bytes(read_entry(stream,index[name],key))
            if not content.startswith(b"\x89PNG\r\n\x1a\n"): raise ValueError("Expected PNG: "+name)
            path = destination.joinpath(*relative.parts[2:])
            if not path.resolve().is_relative_to(destination): raise ValueError("Path escaped destination")
            if path.exists() and path.read_bytes() != content: raise ValueError("Refusing to overwrite changed image: "+str(path))
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_bytes(content)
            width,height=struct.unpack(">II",content[16:24])
            records.append({"source":name,"target":path.relative_to(destination).as_posix(),"sha256":hashlib.sha256(content).hexdigest(),"bytes":len(content),"size":[width,height]})
    args.manifest.parent.mkdir(parents=True,exist_ok=True)
    args.manifest.write_text(json.dumps({"temporary":True,"source":"School-0.981-win/game/archive.rpa","authorization":"Owner requested temporary image reuse on 2026-10-18","destination":str(destination),"donor_scripts_imported":False,"files":records},ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"images":len(records),"bytes":sum(x["bytes"] for x in records)}))

if __name__ == "__main__": main()
