#!/usr/bin/env python3
"""Cross-check docs/STATUS.yml against docs/plan.md and docs/decisions/log.md.

Status rots when it lives in more than one file. This keeps the single status
file honest by proving that every milestone it names is defined, that every
blocker it names exists, and that no pass is claimed without evidence.

Exits non-zero on the first failure it can report, after listing all of them.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parent.parent
STATUS = REPO / "docs" / "STATUS.yml"
PLAN = REPO / "docs" / "plan.md"
LOG = REPO / "docs" / "decisions" / "log.md"

MAX_NEXT_ACTIONS = 3
VALID_STATUS = {"not-started", "blocked", "in-progress", "complete"}
# "superseded" means the run passed, and then the path it exercised was
# replaced. Deleting the record would erase a real event; calling it
# "never-run" would be false.
VALID_REBUILD = {"never-run", "passed", "failed", "superseded"}

MILESTONE_HEADING = re.compile(r"^### (M\d+) ", re.MULTILINE)
DECISION_HEADING = re.compile(r"^## (D-\d+) ", re.MULTILINE)

errors: list[str] = []


def fail(message: str) -> None:
    errors.append(message)


def load_status() -> dict:
    try:
        data = yaml.safe_load(STATUS.read_text(encoding="utf-8"))
    except FileNotFoundError:
        sys.exit(f"missing {STATUS.relative_to(REPO)}")
    except yaml.YAMLError as exc:
        sys.exit(f"{STATUS.relative_to(REPO)} is not valid YAML: {exc}")
    if not isinstance(data, dict):
        sys.exit(f"{STATUS.relative_to(REPO)} must be a mapping")
    return data


def read_ids(path: Path, pattern: re.Pattern[str]) -> list[str]:
    try:
        return pattern.findall(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        sys.exit(f"missing {path.relative_to(REPO)}")


def check_milestones(status: dict, planned: list[str]) -> None:
    tracked = status.get("milestones")
    if not isinstance(tracked, dict):
        fail("milestones must be a mapping of milestone ID to state")
        return

    duplicates = {m for m in planned if planned.count(m) > 1}
    if duplicates:
        fail(f"plan.md defines these milestones more than once: {sorted(duplicates)}")

    missing = [m for m in planned if m not in tracked]
    if missing:
        fail(f"plan.md defines milestones that STATUS.yml does not track: {missing}")

    unknown = [m for m in tracked if m not in planned]
    if unknown:
        fail(f"STATUS.yml tracks milestones that plan.md does not define: {unknown}")

    for milestone, state in tracked.items():
        if not isinstance(state, dict):
            fail(f"{milestone} must be a mapping")
            continue
        value = state.get("status")
        if value not in VALID_STATUS:
            fail(f"{milestone} has status {value!r}, expected one of {sorted(VALID_STATUS)}")
        if value == "blocked" and not state.get("blocked_by"):
            fail(f"{milestone} is blocked but names no blocking decision")
        if value != "blocked" and state.get("blocked_by"):
            fail(f"{milestone} is not blocked but lists blocked_by")
        check_evidence(milestone, state)


def check_evidence(milestone: str, state: dict) -> None:
    """A milestone marked complete must carry a commit SHA and a date.

    CLAUDE.md applies this rule to rebuild claims. It applies just as much to
    a milestone: complete with nothing behind it is the claim this repository
    exists to make impossible.
    """
    evidence = state.get("evidence")
    if state.get("status") != "complete":
        if evidence:
            fail(f"{milestone} is not complete but carries evidence")
        return
    if not isinstance(evidence, dict):
        fail(f"{milestone} is complete but records no evidence. Without a SHA it did not happen.")
        return
    if not evidence.get("commit"):
        fail(f"{milestone} is complete but records no commit SHA")
    if not evidence.get("date"):
        fail(f"{milestone} is complete but records no date")


def check_blockers(status: dict, decisions: list[str]) -> None:
    known = set(decisions)
    for milestone, state in (status.get("milestones") or {}).items():
        if not isinstance(state, dict):
            continue
        for decision in state.get("blocked_by") or []:
            if decision not in known:
                fail(f"{milestone} is blocked by {decision}, which decisions/log.md does not define")


def check_phase(status: dict, planned: list[str]) -> None:
    phase = status.get("phase")
    if phase not in planned:
        fail(f"phase {phase!r} is not a milestone defined in plan.md")


def check_next_actions(status: dict) -> None:
    actions = status.get("next_actions")
    if actions is None:
        return
    if not isinstance(actions, list):
        fail("next_actions must be a list")
        return
    if len(actions) > MAX_NEXT_ACTIONS:
        fail(f"next_actions has {len(actions)} entries, the limit is {MAX_NEXT_ACTIONS}")


def check_rebuild(status: dict) -> None:
    rebuild = status.get("last_rebuild")
    if not isinstance(rebuild, dict):
        fail("last_rebuild must be a mapping")
        return
    state = rebuild.get("status")
    if state not in VALID_REBUILD:
        fail(f"last_rebuild.status is {state!r}, expected one of {sorted(VALID_REBUILD)}")
        return
    if state == "never-run":
        return
    # A superseded record still has to say which run it was.
    if not rebuild.get("commit"):
        fail(f"last_rebuild claims {state!r} but records no commit SHA. Without a SHA it did not happen.")
    if not rebuild.get("date"):
        fail(f"last_rebuild claims {state!r} but records no date")


def main() -> int:
    status = load_status()
    planned = read_ids(PLAN, MILESTONE_HEADING)
    decisions = read_ids(LOG, DECISION_HEADING)

    if not planned:
        fail("plan.md defines no milestones")
    if not decisions:
        fail("decisions/log.md defines no decisions")

    check_milestones(status, planned)
    check_blockers(status, decisions)
    check_phase(status, planned)
    check_next_actions(status)
    check_rebuild(status)

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        print(f"\n{len(errors)} problem(s) found.", file=sys.stderr)
        return 1

    print(f"ok: {len(planned)} milestones, {len(decisions)} decisions, cross-check clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
