"""Pinned project-local Godot runtime for macOS and Windows (Python 3.9+)."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = (ROOT / '.godot-version').read_text(encoding='utf-8').strip()
CACHE = ROOT / '.cache/runtime'
RELEASE = f'https://github.com/godotengine/godot-builds/releases/download/{VERSION}-stable/'


def host():
    system = platform.system()
    if system == 'Darwin':
        return 'macos'
    if system == 'Windows':
        return 'windows'
    raise RuntimeError(f'Unsupported desktop platform: {system}')


def digest(path, algorithm='sha256'):
    value = hashlib.new(algorithm)
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def download(url, destination, checksum=None, algorithm='sha256'):
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_file() and checksum and digest(destination, algorithm) == checksum:
        return destination
    partial = destination.with_suffix(destination.suffix + '.part')
    print(f'Downloading {destination.name}', flush=True)
    request = urllib.request.Request(url, headers={'User-Agent': 'EroInc-Setup/1.0', 'Referer': 'https://www.live2d.com/'})
    with urllib.request.urlopen(request, timeout=60) as response, partial.open('wb') as output:
        shutil.copyfileobj(response, output)
    if checksum and digest(partial, algorithm) != checksum:
        partial.unlink()
        raise RuntimeError(f'Checksum mismatch: {destination.name}')
    partial.replace(destination)
    return destination


def extract(archive, destination):
    destination = Path(destination).resolve()
    with zipfile.ZipFile(archive) as package:
        for entry in package.infolist():
            path = (destination / entry.filename).resolve()
            if destination != path and destination not in path.parents:
                raise RuntimeError('Archive contains a path outside its destination')
        package.extractall(destination)
        if os.name != 'nt':
            for entry in package.infolist():
                mode = entry.external_attr >> 16
                if mode & 0o111:
                    (destination / entry.filename).chmod(0o755)


def local_engine():
    directory = CACHE / 'godot' / VERSION
    return directory / ('Godot.app/Contents/MacOS/Godot' if host() == 'macos' else f'Godot_v{VERSION}-stable_win64_console.exe')


def engine():
    explicit = os.environ.get('EROINC_GODOT')
    candidates = [Path(explicit)] if explicit else [local_engine()]
    if not explicit:
        if host() == 'macos':
            candidates += [Path('/Applications/Godot.app/Contents/MacOS/Godot')]
        elif os.environ.get('LOCALAPPDATA'):
            candidates += [Path(os.environ['LOCALAPPDATA']) / f'Programs/Godot/{VERSION}/Godot_v{VERSION}-stable_win64_console.exe']
        located = shutil.which('godot') or shutil.which('godot4')
        if located:
            candidates.append(Path(located))
    for candidate in candidates:
        if candidate.is_file():
            result = subprocess.run([str(candidate), '--version'], capture_output=True, text=True)
            version = result.stdout.strip()
            if result.returncode == 0 and version.startswith(VERSION + '.stable.'):
                return candidate
            if explicit:
                raise RuntimeError(f'EROINC_GODOT must be Godot {VERSION} stable; found {version}')
    raise RuntimeError(f'Godot {VERSION} not found. Run: python tools/runtime.py setup')


def official_archive(name):
    request = urllib.request.Request(RELEASE + 'SHA512-SUMS.txt', headers={'User-Agent': 'EroInc-Setup/1.0'})
    sums = urllib.request.urlopen(request, timeout=60).read().decode()
    checksum = next((line.split()[0] for line in sums.splitlines() if line.split()[-1].lstrip('*') == name), None)
    if not checksum:
        raise RuntimeError(f'Official checksum missing for {name}')
    return download(RELEASE + name, CACHE / 'downloads' / name, checksum, 'sha512')


def install_engine():
    if local_engine().is_file():
        engine()
        return
    suffix = 'macos.universal.zip' if host() == 'macos' else 'win64.exe.zip'
    extract(official_archive(f'Godot_v{VERSION}-stable_{suffix}'), CACHE / 'godot' / VERSION)
    if host() == 'macos':
        local_engine().chmod(0o755)
    engine()


def install_templates():
    if host() == 'macos':
        directory = Path.home() / 'Library/Application Support/Godot/export_templates' / f'{VERSION}.stable'
    else:
        directory = Path(os.environ['APPDATA']) / 'Godot/export_templates' / f'{VERSION}.stable'
    if (directory / 'windows_debug_x86_64.exe').is_file() and (directory / 'macos.zip').is_file():
        return
    archive = official_archive(f'Godot_v{VERSION}-stable_export_templates.tpz')
    extracted = CACHE / 'templates' / VERSION
    extract(archive, extracted)
    shutil.copytree(extracted / 'templates', directory, dirs_exist_ok=True)
    print(f'Export templates: {directory}')


def command(arguments):
    arguments = list(arguments)
    if arguments and arguments[0] == '--':
        arguments.pop(0)
    engine_args = arguments[:arguments.index('--')] if '--' in arguments else arguments
    defaults = []
    if '--path' not in engine_args:
        defaults += ['--path', str(ROOT)]
    if '--audio-driver' in engine_args:
        position = engine_args.index('--audio-driver')
        if position + 1 >= len(engine_args) or engine_args[position + 1] != 'Dummy':
            raise RuntimeError('Project launchers keep audio disabled (Dummy), as configured for this project')
    else:
        defaults += ['--audio-driver', 'Dummy']
    return [str(engine()), *defaults, *arguments]


def doctor():
    failures = []
    try:
        print('Godot:', engine())
    except RuntimeError as error:
        failures.append(str(error))
    library = ROOT / 'addons/gd_cubism/bin' / ('libgd_cubism.macos.universal.dylib' if host() == 'macos' else 'sdk5/libgd_cubism.windows.x86_64.dll')
    if library.is_file():
        print('Live2D:', library)
        manifest = ROOT / 'addons/gd_cubism/bin' / f'build-{host()}.json'
        if manifest.is_file() and digest(library) != json.loads(manifest.read_text(encoding='utf-8'))['sha256']:
            failures.append('Live2D binary does not match its build manifest')
        if host() == 'windows' and not (library.parent / 'Live2DCubismCore.dll').is_file():
            failures.append('Windows Live2DCubismCore.dll is missing')
    else:
        failures.append('Live2D missing. Run: python tools/runtime.py setup --live2d')
    for failure in failures:
        print(failure, file=sys.stderr)
    return int(bool(failures))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    setup = sub.add_parser('setup')
    setup.add_argument('--live2d', action='store_true')
    setup.add_argument('--templates', action='store_true')
    sub.add_parser('doctor')
    run = sub.add_parser('run')
    run.add_argument('arguments', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    try:
        if args.action == 'setup':
            install_engine()
            if args.templates:
                install_templates()
            if args.live2d:
                subprocess.run([sys.executable, str(ROOT / 'tools/build_cubism_runtime.py')], check=True)
            print('Runtime ready:', engine())
            return 0
        if args.action == 'doctor':
            return doctor()
        return subprocess.call(command(args.arguments or ['--editor']), cwd=ROOT)
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        print(f'Setup error: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
