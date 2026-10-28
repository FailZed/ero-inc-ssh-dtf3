"""Run EroInc checks in disposable projects with separate save directories."""
from pathlib import Path
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from runtime import ROOT, command, host

ARTIFACTS = ROOT / '.artifacts/tests'
FIXTURE = ROOT / '.cache/tests/main'
SUITES = {
    'save-compatibility': ('tests/gameplay/save_compatibility.gd', 'SAVE_COMPATIBILITY_RESULT'),
    'startup': ('tests/gameplay/startup.gd', 'STARTUP_RESULT'),
    'companion': ('tests/gameplay/companion.gd', 'COMPANION_RESULT'),
    'gameplay': ('tests/gameplay/run.gd', 'GAMEPLAY_RESULT'),
    'ui': ('tests/gameplay/run_ui.gd', 'GAME_UI_RESULT'),
    'mechanics': ('tests/mechanics/run.gd', 'MECHANICS_RESULT'),
    'characters': ('tests/characters/run.gd', 'CHARACTERS_RESULT'),
    'character-menu': ('tests/characters/integration.gd', 'CHARACTERS_INTEGRATION_RESULT'),
    'sandbox': ('tests/gameplay/run_sandbox.gd', 'SANDBOX_RESULT'),
    'work': ('tests/gameplay/work_expansion.gd', 'WORK_EXPANSION_RESULT'),
    'livelihood': ('tests/gameplay/livelihood.gd', 'LIVELIHOOD_RESULT'),
    'growth': ('tests/gameplay/growth.gd', 'GROWTH_RESULT'),
}


def copy_directory(relative, destination):
    shutil.copytree(ROOT / relative, destination / relative, dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('__pycache__', '.DS_Store', '.godot', '.git'))


def prepare(kind):
    target = FIXTURE if kind == 'main' else FIXTURE.parent / kind
    target.mkdir(parents=True, exist_ok=True)
    if kind == 'main':
        for name in ['scripts', 'scenes', 'data', 'addons', 'assets', 'Characters', 'TimeLine', 'locations', 'quests', 'styles', 'translation', 'tests']:
            copy_directory(name, target)
        settings = (ROOT / 'project.godot').read_text(encoding='utf-8')
        settings = settings.replace('[application]', '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="EroIncAutomatedTests"')
        settings = re.sub(r'config/name="[^"]+"', 'config/name="EroInc Automated Tests"', settings)
        (target / 'project.godot').write_text(settings, encoding='utf-8')
        shutil.copy2(ROOT / 'icon.svg', target / 'icon.svg')
    else:
        paths = ['scripts/mechanics', 'data/mechanics', 'tests/mechanics', 'assets/textures/portraits/protagonist_layers'] if kind == 'mechanics' else ['scripts/characters', 'scripts/ui/characters', 'data/characters', 'tests/characters', 'scenes/characters', 'assets/characters/mdrg_study', 'addons/gd_cubism']
        for name in paths:
            copy_directory(name, target)
        if kind == 'characters':
            for name in ['scripts/ui/gameplay/ui_factory.gd', 'assets/textures/ui/windows-v2/window_surface.png']:
                output = target / name
                output.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / name, output)
        (target / 'project.godot').write_text(f'''config_version=5
[application]
config/name="EroInc {kind} Tests"
config/use_custom_user_dir=true
config/custom_user_dir_name="EroIncTests-{kind}"
[display]
window/size/viewport_width=1440
window/size/viewport_height=900
[rendering]
renderer/rendering_method="gl_compatibility"
''', encoding='utf-8')
    return target


def run_process(name, arguments, marker=None, timeout=600):
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    log = ARTIFACTS / (name + '.log')
    try:
        result = subprocess.run(command(arguments), cwd=ROOT, env={**os.environ, "EROINC_ARTIFACTS": str(ARTIFACTS)}, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace', timeout=timeout)
    except subprocess.TimeoutExpired as error:
        output = error.stdout or b''
        log.write_text(output.decode(errors='replace') if isinstance(output, bytes) else output, encoding='utf-8')
        raise RuntimeError(f'Timed out: {name}; see {log}') from error
    log.write_text(result.stdout, encoding='utf-8')
    failed = result.returncode != 0 or re.search(r'SCRIPT ERROR:|Parse Error:|FAIL:', result.stdout)
    data = None
    if marker:
        match = re.search(re.escape(marker) + r' (\{[^\n]+\})', result.stdout)
        if match:
            data = json.loads(match.group(1))
        failed = failed or data is None or data.get('failed', 0) != 0 or data.get('ok', True) is False
    if failed:
        print(result.stdout[-16000:])
        raise RuntimeError(f'Check failed: {name}; see {log}')
    print(name, json.dumps(data, ensure_ascii=False) if data else 'OK', flush=True)
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('suite', choices=[*SUITES, 'all', 'snapshots', 'story'])
    parser.add_argument('--isolated', action='store_true')
    parser.add_argument('--pack', action='store_true')
    parser.add_argument('--visible', action='store_true')
    parser.add_argument('--native', action='store_true')
    args = parser.parse_args()
    if args.pack and (args.suite not in ['mechanics', 'characters'] or not args.isolated):
        parser.error('--pack requires --isolated and suite mechanics or characters')
    kind = args.suite if args.isolated and args.suite in ['mechanics', 'characters'] else 'main'
    target = prepare(kind)
    run_process('import-' + kind, ['--path', str(target), '--headless', '--editor', '--import', '--quit'], timeout=1200)
    render = ['--rendering-method', 'gl_compatibility', '--resolution', '1440x900'] if args.visible else ['--headless']
    base = ['--path', str(target), *render]
    if args.pack:
        preset = 'Windows Desktop' if host() == 'windows' else 'macOS'
        (target / 'export_presets.cfg').write_text(f'''[preset.0]
name="Test Pack"
platform="{preset}"
runnable=true
export_filter="all_resources"
include_filter="*.json,*.moc3"
[preset.0.options]
custom_template/debug=""
custom_template/release=""
''', encoding='utf-8')
        pack = ARTIFACTS / (kind + '.pck')
        run_process('export-' + kind, ['--path', str(target), '--headless', '--export-pack', 'Test Pack', str(pack)])
        packed = FIXTURE.parent / (kind + '-packed')
        packed.mkdir(exist_ok=True)
        if kind == 'characters':
            shutil.copytree(ROOT / 'addons/gd_cubism/bin', packed / 'addons/gd_cubism/bin', dirs_exist_ok=True)
        base = ['--path', str(packed), *render, '--main-pack', str(pack)]
    suites = ['startup', 'save-compatibility', 'mechanics', 'gameplay', 'ui', 'characters', 'character-menu', 'companion', 'sandbox', 'work', 'livelihood', 'growth'] if args.suite == 'all' else [args.suite]
    results = {}
    for suite in suites:
        if suite in ['snapshots', 'story']:
            continue
        script, marker = SUITES[suite]
        extra = ['--', '--unit-only'] if kind == 'mechanics' else []
        results[suite] = run_process(suite + ('-pack' if args.pack else ''), [*base, '--script', 'res://' + script, *extra], marker)
    if args.suite in ['all', 'snapshots']:
        for snapshot in ['snapshot_process', 'sandbox_snapshot', 'work_expansion_snapshot', 'growth_snapshot', 'livelihood_snapshot', 'remaining_snapshot', 'companion_snapshot']:
            script = target / 'tests/gameplay' / (snapshot + '.gd')
            marker = re.search(r'print\("([A-Z_]+RESULT) ', script.read_text(encoding='utf-8')).group(1)
            path = ARTIFACTS / (snapshot + '.json')
            for mode in ['write', 'read']:
                results[snapshot + '-' + mode] = run_process(snapshot + '-' + mode, [*base, '--script', 'res://tests/gameplay/' + script.name, '--', f'--{mode}={path}'], marker)
        for snapshot in ['reproduction_snapshot', 'npc_reproduction_snapshot']:
            script = target / 'tests/mechanics' / (snapshot + '.gd')
            marker = re.search(r'print\("([A-Z_]+RESULT) ', script.read_text(encoding='utf-8')).group(1)
            path = ARTIFACTS / (snapshot + '.json')
            for mode in ['write', 'read']:
                results[snapshot + '-' + mode] = run_process(snapshot + '-' + mode, [*base, '--script', 'res://tests/mechanics/' + script.name, '--', f'--mode={mode}', f'--file={path}'], marker)
    if args.suite in ['all', 'story']:
        for branch in range(5):
            extra = [f'--branch={2 if branch == 4 else branch}', '--difficulty=' + ['easy','normal','hard','custom','custom'][branch]]
            if branch == 3: extra += ['--flee','--points=10']
            if branch == 4: extra += ['--teacher-right','--points=60']
            results['story-' + str(branch)] = run_process('story-' + str(branch), [*base, '--script', 'res://tests/gameplay/flow.gd', '--', *extra], 'FLOW_RESULT')
    if args.native:
        captures = {'companion': ('companion','COMPANION_NATIVE_RESULT'), 'work': ('work_expansion','WORK_EXPANSION_NATIVE_RESULT'), 'livelihood': ('livelihood','LIVELIHOOD_NATIVE_RESULT'), 'growth': ('growth','GROWTH_NATIVE_RESULT'), 'sandbox': ('sandbox','SANDBOX_CAPTURE_RESULT')}
        if args.suite not in captures:
            parser.error('--native is supported for companion, work, livelihood, growth and sandbox')
        capture, marker = captures[args.suite]
        results['native'] = run_process('native-' + capture, ['--path',str(target),'--rendering-method','gl_compatibility','--resolution','1366x768','--script','res://tests/gameplay/capture_' + capture + '.gd'], marker)
    (ARTIFACTS / f'results-{args.suite}.json').write_text(json.dumps(results, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, OSError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
