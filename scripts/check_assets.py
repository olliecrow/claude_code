#!/usr/bin/env python3
"""Validate the reusable Claude Code assets and their durable policy contracts."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
AGENT_MODELS = {"opus", "sonnet"}
FORBIDDEN_TEXT = (
    "spawn them liberally",
    "use many agents",
    "never work alone",
    "no detail is too small",
    "all independent agents must be launched together",
)
DATED_MODEL_PATTERN = re.compile(r"claude-(?:haiku|opus|sonnet)-[^ \n]*\d{8}")


def read_frontmatter(path: Path) -> tuple[dict[str, str], str]:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()

    if not lines or lines[0] != "---":
        raise ValueError("frontmatter must start on the first line")

    try:
        closing_index = lines.index("---", 1)
    except ValueError as error:
        raise ValueError("frontmatter has no closing delimiter") from error

    frontmatter: dict[str, str] = {}
    for line in lines[1:closing_index]:
        if not line.strip():
            continue
        if ":" not in line:
            raise ValueError(f"invalid frontmatter line: {line!r}")
        key, value = line.split(":", 1)
        frontmatter[key.strip()] = value.strip()

    return frontmatter, text


def validate_agent(path: Path) -> list[str]:
    errors: list[str] = []
    try:
        frontmatter, text = read_frontmatter(path)
    except ValueError as error:
        return [f"{path.relative_to(ROOT)}: {error}"]

    if frontmatter.get("name") != path.stem:
        errors.append(f"{path.relative_to(ROOT)}: name must match the filename")
    if not frontmatter.get("description"):
        errors.append(f"{path.relative_to(ROOT)}: description is required")
    if frontmatter.get("model") not in AGENT_MODELS:
        errors.append(
            f"{path.relative_to(ROOT)}: model must be one of {sorted(AGENT_MODELS)}"
        )

    lowered = text.lower()
    for forbidden_text in FORBIDDEN_TEXT:
        if forbidden_text in lowered:
            errors.append(
                f"{path.relative_to(ROOT)}: forbidden policy text {forbidden_text!r}"
            )
    return errors


def validate_command(path: Path) -> list[str]:
    try:
        frontmatter, text = read_frontmatter(path)
    except ValueError as error:
        return [f"{path.relative_to(ROOT)}: {error}"]

    errors: list[str] = []
    if not frontmatter.get("description"):
        errors.append(f"{path.relative_to(ROOT)}: description is required")

    lowered = text.lower()
    for forbidden_text in FORBIDDEN_TEXT:
        if forbidden_text in lowered:
            errors.append(
                f"{path.relative_to(ROOT)}: forbidden policy text {forbidden_text!r}"
            )
    return errors


def validate_repository_text() -> list[str]:
    errors: list[str] = []
    text_files = [
        *ROOT.glob("*.md"),
        *ROOT.glob("agents/*.md"),
        *ROOT.glob("commands/*.md"),
        *ROOT.glob("container/*"),
        *ROOT.glob("docs/*.md"),
        *ROOT.glob("scripts/**/*"),
    ]

    for path in text_files:
        if not path.is_file() or path.name == "uv.lock":
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        if DATED_MODEL_PATTERN.search(text):
            errors.append(
                f"{path.relative_to(ROOT)}: use a current model alias, not a dated model ID"
            )
    return errors


def main() -> int:
    errors: list[str] = []

    for path in sorted((ROOT / "agents").glob("*.md")):
        if path.name != "README.md":
            errors.extend(validate_agent(path))

    for path in sorted((ROOT / "commands").glob("*.md")):
        if path.name != "README.md":
            errors.extend(validate_command(path))

    errors.extend(validate_repository_text())

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    print("Claude Code assets are valid.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
