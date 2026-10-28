"""Build the pinned Live2D extension on macOS (universal) or Windows (x64).

Uses the official Native SDK, never a DLL from another game's installation.
SDK terms: https://www.live2d.com/en/sdk/download/native/
Build dependencies: Xcode Command Line Tools, or Visual Studio C++ Build Tools.
"""
from pathlib import Path
import argparse
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import venv
from runtime import ROOT, CACHE, download, extract, host, digest

REVISION = '60e9c61ed20d08ec19b2cb80fb492ce6344927c6'
CPP_REVISION = 'fbbf9ec4efd8f1055d00edb8d926eef8ba4c2cce'
SDK_NAME = 'CubismSdkForNative-5-r.1'
SDK_SHA256 = '073f623fc3fb06c192e68bb5287fdb9dab1952164c2a956dec6d4b45fd342ffb'
SOURCE = CACHE / 'gd_cubism'


def checked(*args, **kwargs):
    subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def prepare_source():
    if not (SOURCE / '.git').is_dir():
        checked('git', 'clone', '--branch', 'v0.9.1', '--depth', '1', 'https://github.com/MizunagiKB/gd_cubism.git', SOURCE)
    actual = subprocess.check_output(['git', '-C', str(SOURCE), 'rev-parse', 'HEAD'], text=True).strip()
    if actual != REVISION:
        raise RuntimeError('Unexpected gd_cubism source revision; use a fresh build cache')
    checked('git', '-C', SOURCE, 'submodule', 'update', '--init', '--depth', '1')
    actual = subprocess.check_output(['git', '-C', str(SOURCE / 'godot-cpp'), 'rev-parse', 'HEAD'], text=True).strip()
    if actual != CPP_REVISION:
        raise RuntimeError('Unexpected godot-cpp source revision')
    native_file = SOURCE / 'src/gd_cubism_user_model.cpp'
    native_text = native_file.read_text(encoding='utf-8')
    if 'D_METHOD("is_initialized")' not in native_text:
        native_text = native_text.replace('// ModelData', '// ModelData\n    ClassDB::bind_method(D_METHOD("is_initialized"), &GDCubismUserModel::is_initialized);', 1)
        native_file.write_text(native_text, encoding='utf-8')
    build_file = SOURCE / 'SConstruct'
    build_text = build_file.read_text(encoding='utf-8')
    if '# EroInc cross-build' not in build_text:
        build_text = build_text.replace('if env["platform"] == "windows":', '''# EroInc cross-build: use the official Core import library with MinGW.
if env["platform"] == "windows" and env.get("use_mingw", False):
    env.Append(LIBPATH=[os.path.join(CUBISM_NATIVE_CORE_DIR, "dll/windows/x86_64")])
    env.Append(LIBS=["Live2DCubismCore"])
    env.Append(LINKFLAGS=["-static-libgcc", "-static-libstdc++"])
elif env["platform"] == "windows":''', 1)
        build_file.write_text(build_text, encoding='utf-8')
    spec = importlib.util.spec_from_file_location('cubism_bindings', SOURCE / 'godot-cpp/binding_generator.py')
    binding = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(binding)
    headers = set()
    for path in (SOURCE / 'src').rglob('*'):
        if path.suffix in ('.cpp', '.hpp'):
            headers.update(re.findall(r'godot_cpp/classes/(\w+)\.hpp', path.read_text(encoding='utf-8')))
    api = json.loads((SOURCE / 'godot-cpp/gdextension/extension_api.json').read_text(encoding='utf-8'))
    classes = [item['name'] for item in api['classes'] if binding.camel_to_snake(item['name']) in headers]
    (SOURCE / 'ero_profile.json').write_text(json.dumps({'enabled_classes': classes}, indent=2), encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk', type=Path, help='An extracted official CubismSdkForNative-5-r.1 directory')
    parser.add_argument('--platform', choices=['macos','windows'], default=host())
    parser.add_argument('--jobs', type=int, default=min(os.cpu_count() or 2, 8))
    args = parser.parse_args()
    target_platform = args.platform
    prepare_source()
    sdk = SOURCE / 'thirdparty' / SDK_NAME
    if args.sdk:
        if not (args.sdk / 'Core/include/Live2DCubismCore.h').is_file():
            raise RuntimeError('--sdk must point to the extracted Native SDK')
        if args.sdk.resolve() != sdk.resolve():
            shutil.copytree(args.sdk, sdk, dirs_exist_ok=True)
    elif not (sdk / 'Core/include/Live2DCubismCore.h').is_file():
        archive = download(f'https://cubism.live2d.com/sdk-native/bin/{SDK_NAME}.zip', CACHE / f'{SDK_NAME}.zip', SDK_SHA256)
        extract(archive, SOURCE / 'thirdparty')
    build_env = CACHE / 'build-venv'
    python = build_env / ('Scripts/python.exe' if os.name == 'nt' else 'bin/python')
    if not python.is_file():
        venv.EnvBuilder(with_pip=True).create(build_env)
    checked(python, '-m', 'pip', 'install', '--disable-pip-version-check', 'scons==4.7.0')
    if target_platform == 'macos':
        core = sdk / 'Core/lib/macos'
        (core / 'universal').mkdir(exist_ok=True)
        checked('lipo', '-create', core / 'arm64/libLive2DCubismCore.a', core / 'x86_64/libLive2DCubismCore.a', '-output', core / 'universal/libLive2DCubismCore.a')
    extra = []
    if target_platform == 'windows' and (host() != 'windows' or shutil.which('x86_64-w64-mingw32-g++')):
        if not shutil.which('x86_64-w64-mingw32-g++'):
            raise RuntimeError('Cross-building Windows requires mingw-w64')
        extra = ['use_mingw=yes']
    checked(python, '-m', 'SCons', *extra, f'platform={target_platform}', 'arch=universal' if target_platform == 'macos' else 'arch=x86_64', 'target=template_debug', 'debug_symbols=no', 'optimize=speed', 'build_profile=ero_profile.json', '-j' + str(max(1, args.jobs)), cwd=SOURCE)
    addon = ROOT / 'addons/gd_cubism'
    binary_root = addon / 'bin'
    binary_dir = binary_root / 'sdk5' if target_platform == 'windows' else binary_root
    binary_dir.mkdir(parents=True, exist_ok=True)
    if target_platform == 'macos':
        source = SOURCE / 'demo/addons/gd_cubism/bin/libgd_cubism.macos.debug.framework/libgd_cubism.macos.debug'
        target = binary_dir / 'libgd_cubism.macos.universal.dylib'
        shutil.copy2(source, target)
        checked('install_name_tool', '-id', '@rpath/' + target.name, target)
        checked('codesign', '--force', '--sign', '-', target)
    else:
        source = SOURCE / 'demo/addons/gd_cubism/bin/libgd_cubism.windows.debug.x86_64.dll'
        target = binary_dir / 'libgd_cubism.windows.x86_64.dll'
        shutil.copy2(source, target)
        shutil.copy2(sdk / 'Core/dll/windows/x86_64/Live2DCubismCore.dll', binary_dir / 'Live2DCubismCore.dll')
    shutil.copytree(SOURCE / 'demo/addons/gd_cubism/res', addon / 'res', dirs_exist_ok=True)
    for source_path, name in [(sdk / 'LICENSE.md', 'CUBISM_SDK_LICENSE.md'), (sdk / 'NOTICE.md', 'CUBISM_SDK_NOTICE.md'), (sdk / 'Core/LICENSE.md', 'CUBISM_CORE_LICENSE.md'), (sdk / 'Framework/LICENSE.md', 'CUBISM_FRAMEWORK_LICENSE.md')]:
        shutil.copy2(source_path, addon / name)
    (binary_root / f'build-{target_platform}.json').write_text(json.dumps({'renderer_revision': REVISION, 'godot_cpp_revision': CPP_REVISION, 'sdk': SDK_NAME, 'platform': target_platform, 'binary': target.relative_to(binary_root).as_posix(), 'sha256': digest(target), 'core_linkage': 'dynamic' if extra else 'static'}, indent=2) + '\n', encoding='utf-8')
    print('CUBISM_RUNTIME_READY', target, flush=True)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        print(f'Live2D build failed: {error}', file=sys.stderr)
        sys.exit(1)
