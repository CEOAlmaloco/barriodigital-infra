#!/usr/bin/env python3
"""Valida samples de eventos contra schemas versionados (EP3.5-04)."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent / "events"


def validate(instance: dict, schema: dict) -> list[str]:
    errors: list[str] = []
    req = schema.get("required", [])
    for key in req:
        if key not in instance:
            errors.append(f"falta {key}")
    if schema.get("additionalProperties") is False:
        allowed = set(schema.get("properties", {}))
        for key in instance:
            if key not in allowed:
                errors.append(f"propiedad extra {key}")
    props = schema.get("properties", {})
    for key, rules in props.items():
        if key not in instance:
            continue
        val = instance[key]
        if "const" in rules and val != rules["const"]:
            errors.append(f"{key} debe ser {rules['const']!r}, llegó {val!r}")
        t = rules.get("type")
        if t == "string" and not isinstance(val, str):
            errors.append(f"{key} no es string")
        if t == "integer" and not isinstance(val, int):
            errors.append(f"{key} no es integer")
        if t == "object" and not isinstance(val, dict):
            errors.append(f"{key} no es object")
        if isinstance(val, int) and "minimum" in rules and val < rules["minimum"]:
            errors.append(f"{key} < minimum")
    return errors


def main() -> int:
    envelope = json.loads((ROOT / "envelope.schema.json").read_text(encoding="utf-8"))
    catalog = json.loads((ROOT / "catalog.json").read_text(encoding="utf-8"))
    failed = 0
    for et, meta in catalog["eventTypes"].items():
        schema = json.loads((ROOT / meta["file"]).read_text(encoding="utf-8"))
        # merge envelope constraints for local validator
        merged = {
            "required": envelope["required"],
            "additionalProperties": False,
            "properties": {**envelope["properties"], **schema.get("properties", {})},
        }
        sample_path = ROOT / "samples" / meta["file"].replace(".schema.json", ".json")
        sample = json.loads(sample_path.read_text(encoding="utf-8"))
        errs = validate(sample, merged)
        # incompatible change guard: schemaVersion in catalog must match sample
        if sample.get("schemaVersion") != meta["schemaVersion"]:
            errs.append("schemaVersion incompatible con catalog.json")
        if errs:
            failed += 1
            print(f"FAIL {et}: {errs}")
        else:
            print(f"OK {et}")
    # guard: quitar un eventType del catalog sin sample rompe
    if not catalog["eventTypes"]:
        print("FAIL catalog vacío")
        return 1
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
