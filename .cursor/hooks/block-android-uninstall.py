#!/usr/bin/env python3
"""Block Android uninstall / flutter install unless explicitly authorized.

Cursor beforeShellExecution hook. Fail closed on parse errors for safety.
"""
from __future__ import annotations

import json
import re
import sys

DENY_PATTERNS = [
    r"\badb(\s+|-)uninstall\b",
    r"\bpm\s+uninstall\b",
    r"\bcmd\s+package\s+uninstall\b",
    r"\bpackage\s+uninstall\b",
    r"\bflutter\s+install\b",
    r"\buninstall\s+com\.triflash\b",
]


def is_denied(command: str) -> bool:
    lowered = command.lower()
    return any(re.search(pattern, lowered) for pattern in DENY_PATTERNS)


def main() -> int:
    try:
        raw = sys.stdin.read()
        data = json.loads(raw) if raw.strip() else {}
    except Exception as exc:
        print(
            json.dumps(
                {
                    "permission": "deny",
                    "user_message": "Android install safety hook failed to parse input; blocked shell command.",
                    "agent_message": f"beforeShellExecution hook parse failure ({exc}). Do not retry with uninstall.",
                }
            )
        )
        return 0

    command = data.get("command") or ""
    if not isinstance(command, str):
        command = str(command)

    if is_denied(command):
        print(
            json.dumps(
                {
                    "permission": "deny",
                    "user_message": (
                        "Blocked: this command would uninstall or replace-via-uninstall an Android app. "
                        "Only in-place updates are allowed (adb install -r). "
                        "Uninstall requires an explicit user request in the same message."
                    ),
                    "agent_message": (
                        "HARD DENY: do not uninstall Android apps and do not run `flutter install` "
                        "(it uninstalls first). Build an APK, then: adb -s <serial> install -r <apk>. "
                        "On signature mismatch, stop and ask — never uninstall."
                    ),
                }
            )
        )
        return 0

    print(json.dumps({"permission": "allow"}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
