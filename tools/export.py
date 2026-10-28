"""Build self-contained macOS and Windows debug distributions with the pinned engine."""
import argparse
import shutil
import subprocess
import sys
import zipfile
from runtime import ROOT, command, install_templates


def run(name, arguments):
    logs = ROOT / '.artifacts/export'
    logs.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(command(arguments), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace')
    (logs / (name + '.log')).write_text(result.stdout, encoding='utf-8')
    if result.returncode or 'SCRIPT ERROR:' in result.stdout or 'Export failed' in result.stdout:
        print(result.stdout[-12000:])
        raise RuntimeError(f'{name} failed; see {logs}')
    print(name, 'OK', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=['macos', 'windows', 'all'], default='all')
    args = parser.parse_args()
    install_templates()
    run('import', ['--headless', '--editor', '--import', '--quit'])
    targets = ['macos', 'windows'] if args.platform == 'all' else [args.platform]
    for target in targets:
        directory = ROOT / 'dist' / target
        directory.mkdir(parents=True, exist_ok=True)
        if target == 'macos':
            preset, name = 'macOS', 'EroInc.zip'
            libraries = ['libgd_cubism.macos.universal.dylib']
        else:
            preset, name = 'Windows Desktop', 'EroInc.exe'
            libraries = ['sdk5/libgd_cubism.windows.x86_64.dll', 'sdk5/Live2DCubismCore.dll']
        for library in libraries:
            if not (ROOT / 'addons/gd_cubism/bin' / library).is_file():
                raise RuntimeError(f'Missing {library}; rebuild with tools/build_cubism_runtime.py')
        run(target, ['--headless', '--export-debug', preset, str(directory / name)])
        if not (directory / name).is_file():
            raise RuntimeError(f'Export did not create {directory / name}')
        shutil.copytree(ROOT / 'addons/gd_cubism', directory / 'licenses/live2d',
                        ignore=shutil.ignore_patterns('bin', 'res', '*.gdextension', '*.import'), dirs_exist_ok=True)
        if target == 'macos':
            # Keep legal notices beside the signed app inside the transport archive.
            with zipfile.ZipFile(directory / name, 'a', zipfile.ZIP_DEFLATED) as archive:
                for notice in (directory / 'licenses').rglob('*'):
                    if notice.is_file():
                        archive.write(notice, notice.relative_to(directory).as_posix())
        else:
            shutil.make_archive(str(ROOT / 'dist/EroInc-Windows'), 'zip', directory)
        print('Distribution:', directory)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
