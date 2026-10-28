"""Validate the standalone event *design*, without loading Godot or game saves.

Run from any directory with Python 3.10+. No third-party modules are required.
Optional --school-root verifies the local research source hashes as well.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "data/mechanics/design/random_events.json"


def validate(data: dict, root: Path, school_root: Path | None = None) -> dict:
    errors: list[str] = []

    def need(condition: bool, message: str) -> None:
        if not condition:
            errors.append(message)

    need(data.get("schema") == "eroinc.random_events.design.v1", "Unknown design schema")
    need(data.get("status") == "design_prepared_not_loaded", "Design presented as integrated")
    need(data.get("not_runtime_catalog") is True, "Missing runtime boundary")
    need(data.get("school_full_or_numeric_parity") is False, "Unsupported parity claim")
    need(data.get("numeric_balance") == "proposed_not_playtested", "Balance status is misleading")
    events = data.get("events", [])
    need(isinstance(events, list) and bool(events), "No event cards")
    if not isinstance(events, list) or not all(isinstance(e, dict) for e in events):
        return {"ok": False, "errors": errors + ["Malformed event array"]}
    ids = [e.get("id", "") for e in events]
    need(len(ids) == len(set(ids)), "Duplicate event IDs")
    by_id = {e.get("id", ""): e for e in events}
    families = data.get("families", {})
    gates = data.get("gates", {})
    owners = data.get("owner_domain_references", {})
    evidence = data.get("school_evidence", {}).get("entries", [])
    source_ids = [s.get("id", "") for s in evidence]
    need(len(source_ids) == len(set(source_ids)), "Duplicate School evidence IDs")
    evidence_ids = set(source_ids)
    inventory = {s["path"]: s for s in json.loads(
        (root / "docs/mechanics/source_inventory.json").read_text(encoding="utf-8-sig"))["files"]}
    locations = json.loads((root / "data/world/city-graph.json").read_text(encoding="utf-8-sig"))["locations"]
    for domain, ref in owners.items():
        need((root / ref.get("path", "")).is_file(), f"Missing owner source: {domain}")
        need(ref.get("binding_status") == "reviewed_source_not_approved_command_binding",
             f"Unapproved dispatch binding: {domain}")
    for source in evidence:
        sid, path = source.get("id", ""), source.get("path", "")
        need(path in inventory, f"Uninventoried School source: {sid}")
        spec = inventory.get(path, {})
        need(source.get("sha256") == spec.get("sha256"), f"Inventory hash differs: {sid}")
        span = source.get("lines", [])
        need(len(span) == 2 and all(type(n) is int for n in span)
             and 1 <= span[0] <= span[1] <= source.get("file_lines", 0), f"Bad evidence range: {sid}")
        need(bool(source.get("observation")) and bool(source.get("inference_for_eroinc")),
             f"Missing observation/inference distinction: {sid}")
        if school_root is not None:
            file = school_root / path
            need(file.is_file(), f"Missing local donor file: {sid}")
            if file.is_file():
                raw = file.read_bytes()
                need(hashlib.sha256(raw).hexdigest() == source.get("sha256"), f"Local donor hash differs: {sid}")
                need(len(raw.decode("utf-8-sig").splitlines()) == source.get("file_lines"),
                     f"Local donor line count differs: {sid}")
    required_gates = {"sandbox_or_post_prologue", "adult_participants", "world_preferences", "real_context",
                      "actual_access", "calendar_capacity", "not_emergency", "no_active_duplicate"}
    referenced_children: Counter = Counter()
    worked = []
    for e in events:
        eid, family, stage = e.get("id", ""), e.get("family", ""), e.get("stage", "")
        need(bool(re.fullmatch(r"re_[a-z0-9_]+", eid)), f"Invalid ID: {eid}")
        need(family in families, f"Unknown family: {eid}")
        need(stage in ["root", "followup"], f"Unknown card stage: {eid}")
        need(e.get("variant_class") == ("continuation_node" if stage == "followup"
             else "independent_authored_situation"), f"Incorrect counting unit: {eid}")
        need(e.get("parameter_variants_counted") is False, f"Variant counted as situation: {eid}")
        need(e.get("status") == "design_prepared", f"Unsupported runtime status: {eid}")
        for field in ["title", "situation", "memory_key", "npc_resolution", "readiness"]:
            need(isinstance(e.get(field), str) and bool(e[field].strip()), f"Empty {field}: {eid}")
        need(e.get("actor_modes") in [["npc"], ["player", "npc"]], f"Invalid actor modes: {eid}")
        need(e.get("casting") == "bind_only_existing_context_actors_no_spawn", f"Implicit actor spawn: {eid}")
        conditions = e.get("eligibility", {}).get("all", [])
        need(required_gates <= set(conditions), f"Missing eligibility gate: {eid}")
        need(set(conditions) <= set(gates), f"Unknown eligibility gate: {eid}")
        need(len(e.get("eligibility", {}).get("detail", "")) >= 20, f"No concrete condition: {eid}")
        need(set(e.get("owner_domains", [])) <= set(owners) and bool(e.get("owner_domains")),
             f"Unknown/missing owner: {eid}")
        need(set(e.get("school_contracts", [])) <= evidence_ids, f"Unknown School reference: {eid}")
        need(bool(e.get("location_examples_prepared_graph")) and
             set(e.get("location_examples_prepared_graph", [])) <= set(locations), f"Unknown prepared place: {eid}")
        need(len(e.get("integration_dependencies", [])) >= 3, f"Missing integration blockers: {eid}")
        need(e.get("resource_policy", {}).get("reward", "").startswith("no_fixed_event"),
             f"Potential duplicate owner reward: {eid}")
        selection = e.get("selection", {})
        for field in ["cooldown_minutes_proposal", "family_cooldown_minutes_proposal", "offer_lifetime_minutes_proposal"]:
            need(type(selection.get(field)) is int and selection[field] > 0, f"Invalid {field}: {eid}")
        weight = selection.get("relative_weight_proposal")
        need(type(weight) is int and (weight == 0 if stage == "followup" else weight > 0), f"Invalid weight: {eid}")
        need(selection.get("case_key") == "event_id + owner_incident_id + ordered_actor_roles", f"Unscoped incident: {eid}")
        choices = e.get("choices", [])
        need(len(choices) == (4 if "worked_example" in e else 3), f"Incorrect choice count: {eid}")
        choice_ids = [c.get("id") for c in choices]
        need(len(choice_ids) == len(set(choice_ids)), f"Duplicate choice ID: {eid}")
        need(choice_ids == (["a", "b", "c", "leave"] if "worked_example" in e else ["a", "b", "leave"]),
             f"Missing distinct decisions or refusal: {eid}")
        need(len({c.get("text") for c in choices}) == len(choices), f"Duplicate choice text: {eid}")
        for c in choices:
            cid = f"{eid}/{c.get('id')}"
            need(type(c.get("local_minutes_proposal")) is int and 0 <= c["local_minutes_proposal"] <= 120,
                 f"Invalid local time: {cid}")
            for field in ["text", "immediate", "persistent"]:
                need(isinstance(c.get(field), str) and len(c[field].strip()) >= 8, f"Empty {field}: {cid}")
            need(c.get("effect_status") == "prose_intent_not_runtime_effects", f"Undeclared executable effect: {cid}")
            if c.get("id") == "leave":
                need(c.get("local_minutes_proposal") == 0 and c.get("service_policy") == "dismiss_offer_only",
                     f"Refusal creates obligation/cost: {cid}")
            if "followup" in c:
                target = by_id.get(c["followup"], {})
                referenced_children[c["followup"]] += 1
                need(stage == "root" and target.get("stage") == "followup", f"Broken chain edge: {cid}")
                need(target.get("parent", {}).get("event_id") == eid and
                     target.get("parent", {}).get("choice_id") == c["id"], f"Mismatched parent edge: {cid}")
        if stage == "followup":
            parent = e.get("parent", {})
            source = by_id.get(parent.get("event_id", ""), {})
            need(source.get("stage") == "root" and source.get("family") == family, f"Invalid parent: {eid}")
            need(e.get("actor_modes") == source.get("actor_modes"), f"Changed actors in followup: {eid}")
            need(parent.get("inherit_actor_tuple") is True and parent.get("required_result") ==
                 "actual_owner_confirmed_success", f"Unconfirmed parent result: {eid}")
            need(parent.get("due_source") == "existing_owner_agreed_due_or_actual_reply", f"Fabricated reply/due: {eid}")
        if "worked_example" in e:
            worked.append(e)
            example = e["worked_example"]
            need(stage == "root" and example.get("kind") == "fictional_acceptance_fixture_not_saved_game",
                 f"Synthetic example misrepresented: {eid}")
            need(example.get("free_local_window_minutes", 0) >= max(c["local_minutes_proposal"] for c in choices),
                 f"Infeasible local worked example: {eid}")
    need(all(referenced_children[eid] == 1 for eid, e in by_id.items() if e.get("stage") == "followup"),
         "An orphan or multiply referenced followup exists")
    need(len({e.get("title") for e in events}) == len(events), "Duplicate situation title")
    roots = [e for e in events if e.get("stage") == "root"]
    followups = [e for e in events if e.get("stage") == "followup"]
    need(Counter(e["family"] for e in roots) == Counter({f: 10 for f in families}), "Uneven root family coverage")
    need(Counter(e["family"] for e in followups) == Counter({f: 2 for f in families}), "Uneven continuation coverage")
    need(Counter(e["family"] for e in worked) == Counter({f: 1 for f in families}), "Missing worked family example")
    counts = {"families": len(families), "independent_root_situations": len(roots), "continuation_nodes": len(followups),
              "cards": len(events), "choices": sum(len(e["choices"]) for e in events), "worked_examples": len(worked),
              "parameter_variants_in_total": 0, "npc_only_cards": sum(e["actor_modes"] == ["npc"] for e in events),
              "player_eligible_cards": sum("player" in e["actor_modes"] for e in events)}
    need(data.get("counts") == counts, "Declared counts do not match the catalog")
    matrix_path = root / "docs/mechanics/EVENT_MATRIX.md"
    overview_path = root / "docs/mechanics/RANDOM_EVENTS.md"
    matrix = matrix_path.read_text(encoding="utf-8") if matrix_path.is_file() else ""
    overview = overview_path.read_text(encoding="utf-8") if overview_path.is_file() else ""
    for e in events:
        need(matrix.count(f"| `{e['id']}` / ") == 1, f"Matrix row missing/duplicated: {e['id']}")
    for e in worked:
        need(f"### `{e['id']}`" in overview, f"Worked example absent from overview: {e['id']}")
    need("design_prepared" in overview and "не загружается" in overview, "Overview conceals design status")
    return {"ok": not errors, "scope": "static_design_validation_not_gameplay_or_balance_test", "counts": counts,
            "school_evidence_entries": len(evidence), "donor_hashes_checked_now": school_root is not None,
            "errors": errors}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=CATALOG)
    parser.add_argument("--school-root", type=Path)
    args = parser.parse_args()
    try:
        data = json.loads(args.catalog.read_text(encoding="utf-8-sig"))
        result = validate(data, ROOT, args.school_root)
    except (OSError, ValueError, KeyError, TypeError, AttributeError, IndexError) as exc:
        result = {"ok": False, "errors": [f"Malformed design or missing dependency: {exc}"]}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
