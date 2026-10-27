"""Build the pinned Windows Cubism renderer using the local portable toolchain.

The framework and build cache stay on E:. No game or save file is modified.
Run with the research Python environment (scons and pefile are required).
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import pefile

PROJECT = Path(__file__).resolve().parents[1]
RUNTIME = Path('E:/Ai/ComfyUI-EroInc/runtime/cubism')
SOURCE = RUNTIME/'gd_cubism-0.9.1'


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--core-dll', type=Path, default=Path('E:/factorial-omega-win-64/My Dystopian Robot Girlfriend_Data/Plugins/x86_64/Live2DCubismCore.dll'))
    p.add_argument('--jobs', type=int, default=6)
    args = p.parse_args()
    compiler = RUNTIME/'llvm-mingw-20261020-ucrt-x86_64/bin'
    if not compiler.is_dir():
        raise SystemExit('Portable llvm-mingw compiler is missing from '+str(compiler))
    archive = RUNTIME/'llvm-mingw-20261020-ucrt-x86_64.zip'
    if archive.exists() and hashlib.sha256(archive.read_bytes()).hexdigest() != 'fd5462b7f5d93b2ff981fcd3f9c7e427e47f3203c64ea91c27bcc444eebd74cd':
        raise SystemExit('Portable compiler archive checksum mismatch')
    native_file = SOURCE/'src/gd_cubism_user_model.cpp'
    native_text = native_file.read_text(encoding='utf-8')
    if 'D_METHOD("is_initialized")' not in native_text:
        native_text = native_text.replace('// ModelData', '// ModelData\n    ClassDB::bind_method(D_METHOD("is_initialized"), &GDCubismUserModel::is_initialized);', 1)
        native_file.write_text(native_text, encoding='utf-8')
    sdk = SOURCE/'thirdparty/CubismSdkForNative-5-r.1'
    lib = sdk/'Core/lib/windows/x86_64/mingw'
    lib.mkdir(parents=True, exist_ok=True)
    pe = pefile.PE(str(args.core_dll))
    exports = [e.name.decode('ascii') for e in pe.DIRECTORY_ENTRY_EXPORT.symbols if e.name]
    definition = lib/'Live2DCubismCore.def'
    definition.write_text('LIBRARY Live2DCubismCore.dll\nEXPORTS\n'+'\n'.join(exports)+'\n', encoding='utf-8')
    subprocess.run([str(compiler/'llvm-dlltool.exe'), '-m', 'i386:x86-64', '-d', str(definition),
        '-l', str(lib/'libLive2DCubismCore.a')], check=True)
    build_file = SOURCE/'SConstruct'
    text = build_file.read_text(encoding='utf-8')
    if '# EroInc portable dynamic Core' not in text:
        start = text.index('if env["platform"] == "windows":')
        end = text.index('elif env["platform"] == "macos":', start)
        text = text[:start]+'''# EroInc portable dynamic Core: use the installed x64 Core DLL through an import library.
if env["platform"] == "windows":
    env.Append(LIBPATH=[os.path.join(CUBISM_NATIVE_CORE_DIR, "lib/windows/x86_64/mingw")])
    env.Append(LIBS=["Live2DCubismCore"])
    env.Append(LINKFLAGS=["-static-libgcc", "-static-libstdc++"])
'''+text[end:]
        build_file.write_text(text, encoding='utf-8')
    spec = importlib.util.spec_from_file_location('cubism_bindings', SOURCE/'godot-cpp/binding_generator.py')
    binding = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(binding)
    headers = set()
    for path in (SOURCE/'src').rglob('*'):
        if path.suffix in ('.cpp', '.hpp'):
            headers.update(re.findall(r'godot_cpp/classes/(\w+)\.hpp', path.read_text(encoding='utf-8')))
    api = json.loads((SOURCE/'godot-cpp/gdextension/extension_api.json').read_text(encoding='utf-8'))
    classes = [c['name'] for c in api['classes'] if binding.camel_to_snake(c['name']) in headers]
    profile = SOURCE/'ero_profile.json'
    profile.write_text(json.dumps({'enabled_classes':classes}, indent=2), encoding='utf-8')
    env = os.environ.copy()
    env['PATH'] = str(compiler)+os.pathsep+env['PATH']
    subprocess.run([sys.executable, '-m', 'SCons', 'platform=windows', 'use_mingw=yes',
        'arch=x86_64', 'target=template_debug', 'debug_symbols=no', 'optimize=speed',
        'build_profile=ero_profile.json', '-j'+str(args.jobs)], cwd=SOURCE, env=env, check=True)
    target = PROJECT/'addons/gd_cubism'
    target.mkdir(parents=True, exist_ok=True)
    for name in ('res', 'bin'):
        shutil.copytree(SOURCE/'demo/addons/gd_cubism'/name, target/name, dirs_exist_ok=True)
    shutil.copy2(args.core_dll, target/'bin/Live2DCubismCore.dll')
    (target/'gd_cubism.gdextension').write_text('''[configuration]
entry_symbol = "gd_cubism_library_init"
compatibility_minimum = "4.3"

[libraries]
windows.x86_64 = "bin/libgd_cubism.windows.debug.x86_64.dll"

[dependencies]
windows.x86_64 = {"bin/Live2DCubismCore.dll": ""}
''', encoding='utf-8')
    for name in ('LICENSE.adoc','LICENSE.en.adoc'):
        shutil.copy2(SOURCE/name, target/name)
    for name in ('LICENSE.md','NOTICE.md'):
        shutil.copy2(sdk/name, target/('CUBISM_SDK_'+name))
    shutil.copy2(sdk/'Core/LICENSE.md', target/'CUBISM_CORE_LICENSE.md')
    shutil.copy2(sdk/'Framework/LICENSE.md', target/'CUBISM_FRAMEWORK_LICENSE.md')
    provenance = {'renderer':'MizunagiKB/gd_cubism v0.9.1',
        'source':'https://github.com/MizunagiKB/gd_cubism/tree/v0.9.1',
        'godot_cpp_revision':'fbbf9ec4efd8f1055d00edb8d926eef8ba4c2cce',
        'sdk_headers':'Live2D Cubism SDK for Native 5-r.1',
        'core_source':str(args.core_dll), 'core_sha256':hashlib.sha256(args.core_dll.read_bytes()).hexdigest(),
        'local_changes':['Windows MinGW import library for the supplied Core DLL','Expose is_initialized() to GDScript'],
        'platform':'Windows x86_64', 'build_profile':classes}
    (target/'provenance.json').write_text(json.dumps(provenance,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('CUBISM_RUNTIME_READY',target,flush=True)


if __name__ == '__main__':
    main()
