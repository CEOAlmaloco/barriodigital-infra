# -*- coding: utf-8 -*-
"""Check internal relative markdown links under docs/."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LINK_RE = re.compile(r"\[([^\]]*)\]\(([^)]+)\)")


def main() -> int:
    broken = []
    checked = 0
    for md in ROOT.rglob("*.md"):
        if "estudio" in md.parts:
            continue
        if md.name.upper().startswith("GUIA"):
            continue
        text = md.read_text(encoding="utf-8")
        for m in LINK_RE.finditer(text):
            target = m.group(2).strip()
            if target.startswith(("http://", "https://", "mailto:", "#")):
                continue
            # strip anchor
            path_part = target.split("#", 1)[0]
            if not path_part:
                continue
            resolved = (md.parent / path_part).resolve()
            checked += 1
            if not resolved.exists():
                broken.append(f"{md.relative_to(ROOT)} -> {target}")
    print(f"checked={checked} broken={len(broken)}")
    if checked == 0:
        print("FAIL: no se revisó ningún enlace")
        return 1
    for b in broken:
        print("BROKEN", b)
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
