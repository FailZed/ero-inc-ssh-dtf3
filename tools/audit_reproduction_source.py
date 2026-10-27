"""Read only mechanical reference candidates; never copies donor code or dialogue."""
import argparse
import hashlib
import json
import re
from pathlib import Path

FEATURES = {
    "protection": r"condom_scene|condom_inventory|condom_in_scene",
    "pregnancy": r"pregnancy|pregnance",
    "pregnancy_decision": r"player_pregnancy_respond|pregnance_delete|pregnancy_event",
    "contraception": r"contracep|birth_control|emergency_contracep",
    "cycle": r"menstru|ovulat|menstrual_cycle",
    "infertility": r"infertil|steril|vasect|tubal",
    "child_support": r"alimony|child_support|алименты",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    root = args.source.resolve()
    found = {key: [] for key in FEATURES}
    for path in sorted(root.rglob("*.rpy")):
        relative = path.relative_to(root).as_posix()
        if relative.startswith("tl/") or path.name == "new.rpy":
            continue
        raw = path.read_bytes()
        matches = {key: [] for key in FEATURES}
        for number, line in enumerate(raw.decode("utf-8-sig").splitlines(), 1):
            stripped = line.strip()
            if len(stripped) > 400 or not re.match(r"(?:\$|if |elif |def |label |return |jump |call )", stripped):
                continue
            for feature, pattern in FEATURES.items():
                if re.search(pattern, stripped, re.I):
                    matches[feature].append(number)
        for feature, numbers in matches.items():
            if numbers:
                found[feature].append({"path": relative, "sha256": hashlib.sha256(raw).hexdigest(), "lines": numbers})
    report = {
        "donor": "School 0.981", "date": "2026-10-27", "method": "static candidate references only; no donor execution or content transfer",
        "limitation": "Keyword hits are leads, not proof of complete behavior or numeric parity; missing hits do not prove absence.",
        "features": found,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: len(items) for key, items in found.items()}))


if __name__ == "__main__":
    main()
