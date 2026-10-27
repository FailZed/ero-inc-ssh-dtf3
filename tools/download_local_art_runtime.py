"""Download the official AMD ComfyUI bundle and the selected DaSiWa checkpoint.

All downloads, resumable partials and metadata stay in the explicitly chosen E: root.
Only HTTPS source URLs from the recorded official metadata are used.
"""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import argparse, hashlib, json, os, sys, time, urllib.request, urllib.error

ROOT = Path('E:/Ai/ComfyUI-EroInc').resolve()
DEST = ROOT / 'downloads'

def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(8*1024*1024), b''): result.update(chunk)
    return result.hexdigest()

def download(name, url, expected_hash, expected_size):
    if not url.startswith('https://'): raise ValueError('HTTPS required')
    target = (DEST / name).resolve()
    if not target.is_relative_to(ROOT) or target.name != name: raise ValueError('Unsafe destination')
    if target.exists():
        if digest(target).lower() == expected_hash.lower():
            print(f'{name}: already verified', flush=True); return
        raise ValueError(f'Refusing to replace existing unverified file: {target}')
    partial = target.with_suffix(target.suffix+'.part')
    for attempt in range(5):
        offset = partial.stat().st_size if partial.exists() else 0
        if offset == expected_size: break
        headers = {'User-Agent':'EroInc-Art-Setup/1.0'}
        if offset: headers['Range'] = f'bytes={offset}-'
        try:
            request = urllib.request.Request(url,headers=headers)
            with urllib.request.urlopen(request,timeout=90) as response:
                append = offset > 0 and response.status == 206
                if not append: offset = 0
                print(f'{name}: downloading from {offset/1024**3:.2f} GiB',flush=True)
                last_report = time.monotonic()
                with partial.open('ab' if append else 'wb') as output:
                    while True:
                        chunk = response.read(8*1024*1024)
                        if not chunk: break
                        output.write(chunk); offset += len(chunk)
                        if time.monotonic()-last_report > 20:
                            print(f'{name}: {offset/1024**3:.2f} / {expected_size/1024**3:.2f} GiB',flush=True)
                            last_report = time.monotonic()
            if offset == expected_size: break
        except Exception as error:
            print(f'{name}: attempt {attempt+1}: {type(error).__name__}: {error}',flush=True)
            if isinstance(error, urllib.error.HTTPError) and error.code in (401, 403, 404):
                raise RuntimeError(f'{name}: source requires authorized access or is unavailable; no automatic retry') from error
            if attempt == 4: raise
            time.sleep(2)
    if not partial.exists() or partial.stat().st_size != expected_size: raise ValueError(f'Incomplete download: {name}')
    if digest(partial).lower() != expected_hash.lower(): raise ValueError(f'SHA-256 mismatch: {name}')
    partial.replace(target)
    print(f'{name}: SHA-256 verified, {expected_size} bytes',flush=True)

def main():
    sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser()
    parser.add_argument('--component', choices=('all','comfy','checkpoint','controlnet'), default='all')
    args = parser.parse_args()
    if args.component == 'controlnet':
        metadata = json.loads((DEST/'controlnet-metadata.json').read_text(encoding='utf-8-sig'))
        entry = next(a for a in metadata['siblings'] if a['rfilename']=='diffusion_pytorch_model.safetensors')
        name = 'xinsir-openpose-sdxl.safetensors'
        download(name, 'https://huggingface.co/xinsir/controlnet-openpose-sdxl-1.0/resolve/main/diffusion_pytorch_model.safetensors', entry['lfs']['sha256'], entry['size'])
        installed = ROOT/'runtime/ComfyUI_windows_portable/ComfyUI/models/controlnet'/name
        installed.parent.mkdir(parents=True, exist_ok=True)
        if not installed.exists(): os.link(DEST/name, installed)
        if digest(installed) != entry['lfs']['sha256']: raise ValueError('Installed ControlNet checksum mismatch')
        print(f'ControlNet verified and installed: {installed}', flush=True)
        return
    comfy = json.loads((DEST/'comfy-metadata.json').read_text(encoding='utf-8'))
    model = json.loads((DEST/'dasiwa-metadata.json').read_text(encoding='utf-8'))
    bundle = next(a for a in comfy['assets'] if a['name']=='ComfyUI_windows_portable_amd.7z')
    checkpoint = next(a for a in model['files'] if a['primary'] and a['type']=='Model')
    jobs = []
    if args.component in ('all','comfy'):
        jobs.append((bundle['name'],bundle['browser_download_url'],bundle['digest'].split(':',1)[1],bundle['size']))
    if args.component in ('all','checkpoint'):
        jobs.append((checkpoint['name'],checkpoint['downloadUrl'],checkpoint['hashes']['SHA256'],round(checkpoint['sizeKB']*1024)))
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(download,*job) for job in jobs]
        for future in futures: future.result()

if __name__ == '__main__': main()
