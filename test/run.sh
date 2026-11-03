#!/usr/bin/env bash
# Runs claude-auto.sh against a stub claude. No network, no credentials.
set -u

cd "$(dirname "$0")/.." || exit 1
root=$(pwd)
fixtures="$root/test/fixtures"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
ln -s "$root/test/stub-claude" "$tmp/bin/claude"
export PATH="$tmp/bin:$PATH"
export STUB_RECORD="$tmp/record"

pass=0
fail=0

run() {
    : > "$STUB_RECORD"
    expect -f test/driver.exp ./claude-auto.sh "$@" > "$tmp/output" 2>&1
    code=$?
}

field() { sed -n "s/^$1://p" "$STUB_RECORD" | head -1; }

check() {
    local name=$1 want=$2 got=$3
    if [ "$want" = "$got" ]; then
        printf 'ok   %s\n' "$name"
        pass=$((pass + 1))
    else
        printf 'FAIL %s\n       want: %s\n       got:  %s\n' "$name" "$want" "$got"
        fail=$((fail + 1))
    fi
}

approves() {
    local name=$1 fixture=$2
    STUB_FRAME="$fixtures/$fixture" run
    check "$name" "1<LF>" "$(field input)"
}

ignores() {
    local name=$1 fixture=$2
    STUB_FRAME="$fixtures/$fixture" run
    check "$name" "" "$(field input)"
}

approves "approves a bash prompt"          proceed.txt
approves "approves a file edit prompt"     edit.txt
approves "approves through ANSI attributes" ansi.txt
approves "approves a full-screen frame"     fullscreen.txt
approves "approves a sandbox network prompt" sandbox.txt
approves "approves a full-screen sandbox frame" sandbox-fullscreen.txt
approves "approves a sandbox frame with a wrapped question" sandbox-wrapped.txt

approves "approves a fetch prompt"          fetch.txt

# Recorded from Claude Code 2.1.312: a dialog drawn over the last one, with only
# the changed characters.
approves "approves a dialog with a partly drawn question" partial-question.txt
approves "approves a dialog with a partly drawn option" partial-option.txt

ignores "ignores the question in prose"    prose.txt
ignores "ignores an option list alone"     option-only.txt
ignores "ignores a question from Claude"    ask.txt
ignores "ignores a full-screen question from Claude" ask-fullscreen.txt
ignores "ignores a question from Claude after prose" ask-after-prose.txt
ignores "ignores a question from Claude without a chip" ask-no-chip.txt
ignores "ignores a dynamic workflow dialog" workflow.txt

# Claude Code shows queued dialogs one at a time. The next one is drawn as soon
# as the last is answered, and can repeat its text exactly.
queued() {
    local name=$1 first=$2 second=$3 gap=${4:-0.3}
    STUB_FRAME="$fixtures/$first" STUB_FRAME2="$fixtures/$second" \
        STUB_GAP=$gap STUB_WAIT=6 run
    check "$name" "1<LF>" "$(field input2)"
}

queued "approves a dialog queued behind another" proceed.txt fetch.txt
queued "approves a queued dialog that repeats the question" sandbox.txt sandbox-other.txt
queued "approves a queued full-screen dialog" fullscreen.txt sandbox-fullscreen.txt
queued "approves a queued dialog identical to the last" proceed.txt proceed.txt
queued "approves a queued full-screen dialog identical to the last" fullscreen.txt fullscreen.txt
queued "approves an identical dialog queued 20 ms after the answer" proceed.txt proceed.txt 0.02

# Claude Code ignores input sent less than 150 ms after a dialog appears.
STUB_FRAME="$fixtures/sandbox.txt" STUB_WAIT=4 run
waited=$(field delay)
check "waits out the input refusal window" "yes" \
    "$(python3 -c "print('yes' if $waited >= 0.3 else 'no ($waited s)')")"

STUB_FRAME="$fixtures/proceed.txt" STUB_REPEAT=5 STUB_WAIT=4 run
check "approves a redrawn frame once" "1<LF>" "$(field input)"

STUB_FRAME="$fixtures/fullscreen.txt" STUB_REDRAW="$fixtures/fullscreen-spaced.txt" STUB_WAIT=4 run
check "approves a frame redrawn with other escapes once" "1<LF>" "$(field input)"

STUB_FRAME="$fixtures/fullscreen.txt" STUB_REDRAW="$fixtures/fullscreen-spaced.txt" \
    STUB_REDRAW_DELAY=0.2 STUB_WAIT=4 run
check "approves a frame redrawn during the wait once" "1<LF>" "$(field input)"

STUB_FRAME="$fixtures/ask.txt" STUB_REDRAW="$fixtures/proceed.txt" \
    STUB_REDRAW_DELAY=0.5 STUB_WAIT=4 run
check "approves a dialog after a question from Claude" "1<LF>" "$(field input)"

STUB_FRAME="$fixtures/fullscreen.txt" STUB_REDRAW="$fixtures/fullscreen-spaced.txt" \
    STUB_REDRAW_PIECES=6 STUB_WAIT=4 run
check "approves a frame redrawn in pieces once" "1<LF>" "$(field input)"

# Recorded from Claude Code 2.1.312: a queued dialog closed by itself during the
# wait, and Claude Code drew the empty input box.
STUB_FRAME="$fixtures/proceed.txt" STUB_REDRAW="$fixtures/input-box.txt" \
    STUB_REDRAW_DELAY=0.2 STUB_WAIT=4 run
check "sends nothing when the dialog closes during the wait" "" "$(field input)"

STUB_FRAME="$fixtures/input-box.txt" STUB_REDRAW="$fixtures/proceed.txt" \
    STUB_REDRAW_DELAY=0.2 STUB_WAIT=4 run
check "approves a dialog drawn after the input box" "1<LF>" "$(field input)"

# Recorded from Claude Code 2.1.286, text masked: a dialog drawn twice before an answer.
STUB_FRAME="$fixtures/skill-redrawn.txt" STUB_WAIT=4 run
check "approves a recorded double-drawn dialog once" "1<LF>" "$(field input)"

CLAUDE_AUTO_TRACE="$tmp/trace" STUB_FRAME="$fixtures/sandbox.txt" run
check "records a trace" "yes" "$(grep -qc 'outside of sandbox' "$tmp/trace" 2>/dev/null && echo yes)"

STUB_FRAME= run --resume "fix the failing tests"
check "forwards arguments" "--resume fix the failing tests" "$(field args)"

STUB_FRAME= STUB_EXIT=42 run
check "propagates the exit code" "42" "$code"

STUB_FRAME= STUB_WAIT=3 DRIVER_TYPE="hello" run
check "forwards keystrokes" "hello" "$(field input)"

STUB_FRAME= STUB_WAIT=4 DRIVER_SIZE="40 100" run
check "follows a terminal resize" "40 100" "$(field size)"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
