"""Check main-game mechanics in a small isolated project without UI or user saves."""
from pathlib import Path
import json
import re
import shutil
import subprocess

from runtime import ROOT, command

OUTPUT = ROOT / '.artifacts/depth-check'
RUNTIME = OUTPUT / 'runtime'
SCRIPT = 'tests/gameplay/mechanics_depth.gd'


def prepare():
    RUNTIME.mkdir(parents=True, exist_ok=True)
    for relative in ['scripts/mechanics', 'data/mechanics', 'data/world']:
        shutil.copytree(ROOT / relative, RUNTIME / relative, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns('.DS_Store', '__pycache__'))
    pending = [SCRIPT]
    copied = set()
    while pending:
        relative = pending.pop()
        if relative in copied:
            continue
        copied.add(relative)
        source = ROOT / relative
        target = RUNTIME / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        if source.suffix == '.gd':
            pending.extend(re.findall(r'(?:preload|load)\("res://([^"\n]+)"\)', source.read_text(encoding='utf-8')))
    (RUNTIME / 'project.godot').write_text('''config_version=5
[application]
config/name="EroInc Depth Checks"
config/use_custom_user_dir=true
config/custom_user_dir_name="EroIncDepthChecks"
[rendering]
renderer/rendering_method="gl_compatibility"
''', encoding='utf-8')


def main():
    prepare()
    result = subprocess.run(command(['--headless', '--path', str(RUNTIME), '--script', 'res://' + SCRIPT]),
                            cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, encoding='utf-8', errors='replace', timeout=180)
    (OUTPUT / 'main-depth.log').write_text(result.stdout, encoding='utf-8')
    match = re.search(r'MECHANICS_DEPTH_RESULT (\{[^\n]+\})', result.stdout)
    report = json.loads(match.group(1)) if match else {'failed': 1, 'failures': ['Missing test result']}
    failed = result.returncode != 0 or report.get('failed', 1) != 0 or re.search(r'SCRIPT ERROR:|ERROR:|FAIL:', result.stdout)
    (OUTPUT / 'main-depth-result.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(result.stdout if failed else json.dumps(report, ensure_ascii=False))
    return 1 if failed else 0


if __name__ == '__main__':
    raise SystemExit(main())
