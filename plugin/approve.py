import fcntl
import json
import os
import re
import subprocess
import time
import tomllib
from pathlib import Path

DEFAULTS = {"log": True, "trace": False, "settle_ms": 400}

RULE = re.compile(r"^\s*─{10,}\s*$", re.M)
QUESTION = re.compile(r"Do you want to[\s\S]{0,300}?\?|Network request outside of sandbox")
# Option 1 must be selected. "Yes, run it" starts a dynamic workflow, which the user answers.
SELECTED_YES = re.compile(r"^\s*❯\s*1\.\s*Yes\b(?!.*run it)", re.M)
# A question that Claude asks the user has a header chip and an "Enter to select" footer.
ASK = re.compile(r"☐|Enter to select")


def herdr(*args):
    return subprocess.run([os.environ.get("HERDR_BIN_PATH", "herdr"), *args],
                          capture_output=True, text=True, check=True).stdout


def dialog(screen):
    region = RULE.split(screen)[-1]
    if ASK.search(region) or not SELECTED_YES.search(region):
        return None
    match = QUESTION.search(region)
    return " ".join(match.group().split()) if match else None


def settings():
    path = Path(os.environ["HERDR_PLUGIN_CONFIG_DIR"]) / "settings.toml"
    if not path.exists():
        return DEFAULTS
    return DEFAULTS | tomllib.loads(path.read_text())


def append(path, line):
    with path.open("a") as file:
        file.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {line}\n")


def wait_for_change(pane, screen, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if herdr("pane", "read", pane, "--source", "visible") != screen:
            return True
        time.sleep(0.1)
    return False


def main():
    event = json.loads(os.environ["HERDR_PLUGIN_EVENT_JSON"])["data"]
    if event.get("agent") != "claude" or event.get("agent_status") != "blocked":
        return
    pane = event["pane_id"]
    config = settings()
    state = Path(os.environ["HERDR_PLUGIN_STATE_DIR"])
    state.mkdir(parents=True, exist_ok=True)

    # Each blocked event starts a hook. One hook at a time answers a pane.
    with (state / f"{pane.replace(':', '_')}.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        # Claude Code refuses input that arrives less than 150 ms after a dialog appears.
        time.sleep(config["settle_ms"] / 1000)
        # Claude Code shows queued dialogs one at a time, without a new blocked event.
        while True:
            screen = herdr("pane", "read", pane, "--source", "visible")
            question = dialog(screen)
            if config["trace"]:
                append(state / "trace.log", f"{pane} {question or 'no dialog'}\n{screen}")
            if not question:
                return
            herdr("pane", "send-keys", pane, "1", "enter")
            if config["log"]:
                append(state / "approvals.log", f"{pane} approved: {question}")
            # A dialog that does not close after a "1" must not get a second "1".
            if not wait_for_change(pane, screen, 5):
                return
            time.sleep(config["settle_ms"] / 1000)


if __name__ == "__main__":
    main()
