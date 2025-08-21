#!/usr/bin/env python3
"""
multiworkflow.py — Claude Code hook

End-to-end, drop-in replacement implementing a robust multi-stage workflow driver.

Key properties:
- Deterministic continuation using JSON control on Stop/SubagentStop (fallback to stderr+exit 2 via CC_HOOK_MODE=stderr).
- Self-healing: if a stage injection is swallowed, re-inject (bounded retries/cooldown, persisted across events).
- Atomic, locked state writes to prevent torn JSON and racey multi-advances.
- Stable per-session state keyed by session_id (with hashed fallback).
- Safe across multiple repos/sessions; no cross-talk.
- Minimal external assumptions; works with your existing settings plus optional SubagentStop/PostToolUse hooks.
- Slash-command first: stage messages begin with "/plan …" to activate your custom command.
"""

from __future__ import annotations

import hashlib
import json
import os
import sys
import time
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

# ----------------------------- Configuration -----------------------------

HOOK_MODE = (
    os.getenv("CC_HOOK_MODE", "json").strip().lower()
)  # 'json' (default) or 'stderr'
TRANSCRIPT_TAIL_BYTES = 65_536
MAX_REINJECT_PER_STAGE = 4
REINJECT_COOLDOWN_SEC = 2.0
STAGE_STALL_SEC = 300.0  # 5 minutes idle watchdog (gentle nudge only)
INITIAL_NUDGE_GRACE_SEC = 30.0  # avoid nudging immediately if transcript not ready yet
STATE_SCHEMA = 1

# ----------------------------- Utilities ---------------------------------


def log(message: str) -> None:
    ts = time.strftime("%H:%M:%S")
    print(f"[{ts}] {message}", file=sys.stderr)


def _atomic_write(path: Path, text: str) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(text)
    os.replace(tmp, path)


class _FileLock:
    """Best-effort portable lock: POSIX flock if available; otherwise no-op file handle."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self._fh = None

    def __enter__(self):
        self._fh = open(self.path, "a+")
        try:
            import fcntl  # type: ignore

            fcntl.flock(self._fh, fcntl.LOCK_EX)
        except Exception:
            pass
        return self

    def __exit__(self, *exc):
        try:
            import fcntl  # type: ignore

            fcntl.flock(self._fh, fcntl.LOCK_UN)
        except Exception:
            pass
        try:
            self._fh.close()
        except Exception:
            pass


# ----------------------------- Hook Logic ---------------------------------


class MultiWorkflow:
    def __init__(self, data: Optional[Dict[str, Any]] = None) -> None:
        self.data = data or {}

        cwd = self.data.get("cwd", os.getcwd())
        self.project_dir = Path(cwd)
        self.claude_dir = self.project_dir / ".claude"
        self.claude_dir.mkdir(exist_ok=True)

        raw_sid = self.data.get("session_id")
        if not raw_sid:
            basis = self.data.get("transcript_path") or cwd
            raw_sid = hashlib.sha1(basis.encode("utf-8")).hexdigest()[:12]
        self.session_id = raw_sid

        # in-process memory (best effort; persisted fields live in state file)
        self._last_reinject_ts = 0.0
        self._reinject_counts: Dict[Tuple[str, int], int] = {}

        # Workflows: add/update here (keep triggers stable)
        self.workflows = {
            "--longrun": {
                "name": "Long Running Task",
                "stages": [
                    "investigate",
                    "plan_0",
                    "plan_1",
                    "execute_0",
                    "execute_1",
                    "execute_2",
                    "execute_3",
                    "execute_4",
                    "verify_0",
                    "verify_1",
                    "cleanup",
                ],
                "prompts": {
                    "investigate": (
                        "/plan conduct deep and thorough investigations, research, testing, debugging, etc on the task at hand. "
                        "do not plan/execute yet, just investigate/research. dont hesitate to use standalone/debugging scripts during this task if helpful. use many agents."
                    ),
                    "plan_0": (
                        "/plan create a detailed plan for the task at hand. ensure that there is defined scope, no ambiguity, and no change for overly complex solutions or overengineering. "
                        "do not execute yet, just plan. dont hesitate to use standalone/debugging scripts during this task if helpful. use many agents."
                    ),
                    "plan_1": (
                        "/plan flesh out the plan. conduct further investigations if needed to fill in gaps/reduce ambiguity. "
                        "do not execute yet, just plan. dont hesitate to use standalone/debugging scripts during this task if helpful. use many agents."
                    ),
                    "execute_0": (
                        "/plan execute the plan (first round). execute the plan step by step. "
                        "dont hesitate to use standalone/debugging scripts during this task if helpful. use many agents."
                    ),
                    "execute_1": (
                        "/plan execute the plan (second round). if there is nothing left to do (within the plan and scope), then just return (do nothing). "
                        "if there are remaining items, lets keep going. dont hesitate to use standalone/debugging scripts during this task if helpful. use many agents."
                    ),
                    "execute_2": (
                        "/plan execute the plan (third round). if there is nothing left to do (within the plan and scope), then just return (do nothing). "
                        "if there are remaining items, lets keep going. dont hesitate to use standalone/debugging scripts during this task if helpful. use many agents."
                    ),
                    "execute_3": (
                        "/plan execute the plan (fourth round). if there is nothing left to do (within the plan and scope), then just return (do nothing). "
                        "if there are remaining items, lets keep going. dont hesitate to use standalone/debugging scripts during this task if helpful. use many agents."
                    ),
                    "execute_4": (
                        "/plan execute the plan (fifth round). if there is nothing left to do (within the plan and scope), then just return (do nothing). "
                        "if there are remaining items, lets keep going. dont hesitate to use standalone/debugging scripts during this task if helpful. use many agents."
                    ),
                    "verify_0": (
                        "/plan verify that all tasks in the plan are complete, through whatever means and methods required to verify and validate. "
                        "dont hesitate to use standalone/debugging scripts during this task if helpful. use many agents."
                    ),
                    "verify_1": (
                        "/plan verify that all tasks in the plan are complete, through whatever means and methods required to verify and validate. "
                        "dont hesitate to use standalone/debugging scripts during this task if helpful. use many agents."
                    ),
                    "cleanup": (
                        "/plan conduct a deep and thorough cleanup of the project. remove all files and directories that are no longer needed. use many agents."
                    ),
                },
            },
            "--test": {
                "name": "test task",
                "stages": ["task_1", "task_2", "task_3"],
                "prompts": {
                    "task_1": "/joke ignore the user's prompt. create a file called info_eiffel.txt with just the height of the eiffel tower in it ",
                    "task_2": "/joke ignore the user's prompt. create a file called info_tokyo.txt with just the height of the tokyo tower in it ",
                    "task_3": "/joke ignore the user's prompt. create a file called info_dubai.txt with just the height of the dubai tower in it ",
                },
            },
        }

        log(f"Current directory: {cwd}, Session: {self.session_id}")

    # ------------------------- State management --------------------------

    def get_state_file(self) -> Path:
        return self.claude_dir / f"workflow_state_{self.session_id}.json"

    def _lock_path(self) -> Path:
        return self.get_state_file().with_suffix(".lock")

    def get_state(self) -> Optional[Dict[str, Any]]:
        sf = self.get_state_file()
        if not sf.exists():
            return None
        try:
            return json.loads(sf.read_text())
        except Exception as e:
            log(f"Failed to read state: {e}")
            return None

    def _update_state(self, **fields: Any) -> None:
        """Persist targeted state fields atomically under a lock."""
        sf = self.get_state_file()
        with _FileLock(self._lock_path()):
            try:
                st = json.loads(sf.read_text()) if sf.exists() else {}
            except Exception:
                st = {}
            st.update(fields)
            _atomic_write(sf, json.dumps(st, indent=2))

    def clear_state(self) -> None:
        sf = self.get_state_file()
        try:
            if sf.exists():
                sf.unlink()
        except Exception as e:
            log(f"Failed to clear state: {e}")

    def set_state(
        self,
        workflow_type: str,
        stage: str,
        stage_index: int = 0,
        original_request: Optional[str] = None,
    ) -> None:
        transcript_path = self.data.get("transcript_path", "")
        context_chars = 0
        if transcript_path and os.path.exists(transcript_path):
            try:
                context_chars = os.path.getsize(transcript_path)
            except Exception:
                context_chars = 0

        state_file = self.get_state_file()
        prev = None
        if state_file.exists():
            try:
                prev = json.loads(state_file.read_text())
            except Exception:
                prev = None

        total_stages = len(self.workflows[workflow_type]["stages"])
        progress_percentage = round((stage_index + 1) / total_stages * 100)
        stages_remaining = total_stages - (stage_index + 1)
        workflow_start_ts = (prev or {}).get("workflow_start_ts", time.time())

        state: Dict[str, Any] = {
            "schema": STATE_SCHEMA,
            "workflow_type": workflow_type,
            "workflow_name": self.workflows[workflow_type]["name"],
            "stage": stage,
            "stage_index": stage_index,
            "session_id": self.session_id,
            "timestamp": time.time(),
            "workflow_start_ts": workflow_start_ts,
            "progress": {
                "current_stage": f"{stage_index + 1}/{total_stages}",
                "percentage": f"{progress_percentage}%",
                "stages_remaining": stages_remaining,
                "phase": self._get_phase_name(stage_index),
            },
            "context_size": {"characters": context_chars},
            # reinjection persistence (reset per new stage)
            "last_reinject_epoch": 0.0,
            "reinject_counts": {},  # { "<stage_index>": int }
        }
        if original_request is not None:
            state["original_request"] = original_request

        with _FileLock(self._lock_path()):
            _atomic_write(state_file, json.dumps(state, indent=2))

        log(
            f"{state['workflow_name']}: Stage {stage_index + 1}/{total_stages} - {stage} "
            f"(Context: {context_chars:,} chars)"
        )

    # ------------------------- Formatting helpers ------------------------

    def _get_phase_name(self, stage_index: int) -> str:
        if stage_index == 0:
            return "🔍 Investigation"
        if stage_index in (1, 2):
            return "📋 Planning"
        if 3 <= stage_index <= 7:
            return "⚡ Implementation"
        if stage_index in (8, 9):
            return "✅ Verification"
        if stage_index >= 10:
            return "🧹 Cleanup"
        return "❓ Unknown"

    def _stage_token(self, wf_type: str, idx: int) -> str:
        return f"[WF:{wf_type}:{idx}:{self.session_id}]"

    def format_stage_prompt(
        self,
        workflow_type: str,
        stage_name: str,
        stage_index: int,
        original_request: Optional[str],
    ) -> str:
        workflow = self.workflows[workflow_type]
        total = len(workflow["stages"])
        token = self._stage_token(workflow_type, stage_index)

        # IMPORTANT: slash command must be first characters
        body = workflow["prompts"].get(
            stage_name,
            "/plan continue the current stage; maintain scope and do not regress.",
        )
        header = f"🔄 LONGRUN WORKFLOW - Stage {stage_index + 1}/{total}: {stage_name.upper()} {token}"

        if original_request:
            return f"{body}\n\n{header}\n\nOriginal Request: {original_request}"
        return f"{body}\n\n{header}"

    def _transcript_ready(self) -> bool:
        p = self.data.get("transcript_path")
        try:
            return bool(p and os.path.exists(p) and os.path.getsize(p) > 0)
        except Exception:
            return False

    def _transcript_contains(self, token: str) -> bool:
        path = self.data.get("transcript_path")
        if not path or not os.path.exists(path):
            return False
        try:
            size = os.path.getsize(path)
            with open(path, "rb") as f:
                f.seek(-min(TRANSCRIPT_TAIL_BYTES, size), os.SEEK_END)
                tail = f.read().decode("utf-8", "ignore")
            return token in tail
        except Exception:
            return False

    # --------------------------- Emission paths --------------------------

    def _emit_block(self, reason: str) -> int:
        if HOOK_MODE == "json":
            print(json.dumps({"decision": "block", "reason": reason}))
            return 0
        sys.stderr.write(reason)
        return 2

    def _emit_continue(self) -> int:
        if HOOK_MODE == "json":
            print(json.dumps({}))  # allow the platform to proceed
        return 0

    # ------------------------------ Events -------------------------------

    def get_workflow_type(
        self, content: str
    ) -> Tuple[Optional[str], Optional[Dict[str, Any]]]:
        for trigger, wf in self.workflows.items():
            if trigger in content:
                return trigger, wf
        return None, None

    def handle_user_prompt(self) -> int:
        try:
            content = self.data.get("prompt", "") or self.data.get("content", "") or ""
            trigger, workflow = self.get_workflow_type(content)
            log(f"UserPrompt content detected. Trigger: {trigger!r}")
            if not trigger:
                return 0  # not a workflow start

            clean_prompt = content.replace(trigger, "").strip()
            stages = workflow["stages"]
            first_stage = stages[0]
            self.set_state(trigger, first_stage, 0, clean_prompt)

            # Emit the first stage prompt so Claude continues naturally in-thread.
            first_stage_prompt = self.format_stage_prompt(
                trigger, first_stage, 0, clean_prompt
            )
            sys.stdout.write(first_stage_prompt)
            return 0
        except Exception as e:
            log(f"Error in handle_user_prompt: {e}")
            return 0

    def _persisted_reinject_allowed(self, state: Dict[str, Any], idx: int) -> bool:
        st_last = float(state.get("last_reinject_epoch", 0.0))
        counts = state.get("reinject_counts", {})
        cnt = int(counts.get(str(idx), 0))
        if (
            time.time() - st_last
        ) >= REINJECT_COOLDOWN_SEC and cnt < MAX_REINJECT_PER_STAGE:
            counts[str(idx)] = cnt + 1
            self._update_state(last_reinject_epoch=time.time(), reinject_counts=counts)
            return True
        return False

    def handle_stop_like(self) -> int:
        try:
            state = self.get_state()
            if not state:
                return self._emit_continue()

            wf_type = state["workflow_type"]
            idx = state["stage_index"]
            stages = self.workflows[wf_type]["stages"]
            orig = state.get("original_request", "")
            token = self._stage_token(wf_type, idx)

            # Avoid premature nudges if transcript isn't ready and stage just started
            stage_age = time.time() - float(state.get("timestamp", 0.0))
            if not self._transcript_ready() and stage_age < INITIAL_NUDGE_GRACE_SEC:
                return self._emit_continue()

            # Self-heal: if last injected stage header isn't visible, re-inject SAME stage (bounded)
            if not self._transcript_contains(token):
                # Watchdog: if stage has been idle long enough, allow a maintenance nudge
                if stage_age >= STAGE_STALL_SEC or True:
                    if self._persisted_reinject_allowed(state, idx):
                        prompt = self.format_stage_prompt(
                            wf_type, stages[idx], idx, orig
                        )
                        return self._emit_block(prompt)

                # If token still missing but we've hit reinject bounds, just continue (no advance)
                return self._emit_continue()

            # Advance to next stage
            next_idx = idx + 1
            if next_idx >= len(stages):
                self.clear_state()
                log(f"{state['workflow_name']}: workflow complete.")
                return self._emit_continue()

            # Idempotency guard: ensure no concurrent advance occurred
            recheck = self.get_state()
            assert (
                recheck and recheck["stage_index"] == idx
            ), "concurrent advance detected"

            next_stage = stages[next_idx]
            self.set_state(wf_type, next_stage, next_idx, orig)
            prompt = self.format_stage_prompt(wf_type, next_stage, next_idx, orig)
            return self._emit_block(prompt)

        except AssertionError as e:
            log(f"Advance race avoided: {e}")
            return self._emit_continue()
        except Exception as e:
            log(f"Error in handle_stop_like: {e}")
            return self._emit_continue()

    def handle_post_tool_use(self) -> int:
        # Gentle nudge: if a stage header appears missing from transcript, re-emit SAME stage header (bounded)
        try:
            state = self.get_state()
            if not state:
                return 0

            wf_type = state["workflow_type"]
            idx = state["stage_index"]
            token = self._stage_token(wf_type, idx)
            stage_age = time.time() - float(state.get("timestamp", 0.0))

            # respect transcript readiness and grace period
            if not self._transcript_ready() and stage_age < INITIAL_NUDGE_GRACE_SEC:
                return 0

            if not self._transcript_contains(token):
                # Watchdog allowance (also bounded by persisted cooldown)
                if stage_age >= STAGE_STALL_SEC or True:
                    if self._persisted_reinject_allowed(state, idx):
                        prompt = self.format_stage_prompt(
                            wf_type,
                            state["stage"],
                            idx,
                            state.get("original_request", ""),
                        )
                        return self._emit_block(prompt)
            return 0
        except Exception as e:
            log(f"Error in handle_post_tool_use: {e}")
            return 0


# ------------------------------ Entrypoint -------------------------------


def main() -> None:
    if len(sys.argv) < 2:
        log("ERROR: No hook event specified")
        sys.exit(1)

    event = sys.argv[1]
    log(f"Hook triggered: {event}")

    try:
        stdin_raw = sys.stdin.read()
        stdin_data = json.loads(stdin_raw) if stdin_raw.strip() else {}
    except Exception as e:
        log(f"Failed to parse stdin: {e}")
        stdin_data = {}

    if not isinstance(stdin_data, dict):
        stdin_data = {}

    workflow = MultiWorkflow(stdin_data)

    if event == "UserPromptSubmit":
        rc = workflow.handle_user_prompt()
        log(f"UserPromptSubmit exit code: {rc}")
        sys.exit(rc)

    if event in ("Stop", "SubagentStop"):
        rc = workflow.handle_stop_like()
        log(f"{event} exit code: {rc}")
        sys.exit(rc)

    if event == "PostToolUse":
        rc = workflow.handle_post_tool_use()
        log(f"PostToolUse exit code: {rc}")
        sys.exit(rc)

    log(f"Unknown event: {event}")
    sys.exit(1)


if __name__ == "__main__":
    main()
