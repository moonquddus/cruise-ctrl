#!/usr/bin/env expect

# Claude Code asks "Do you want to proceed?", "Do you want to create <file>?"
# and several more variants. Option 1 is always "Yes".
# The full-screen display does not write the spaces between words. It moves the
# cursor instead, so each space can arrive as an escape sequence.
set question {Do[^\r\n]{1,24}you[^\r\n]{1,24}want[^\r\n]{1,24}to[^?\r\n]{0,200}\?}
# The sandbox network dialog puts its question in a box. A narrow window wraps
# the question, so the title arms the wrapper as well.
set title {Network[^\r\n]{1,24}request[^\r\n]{1,24}outside[^\r\n]{1,24}of[^\r\n]{1,24}sandbox}
# The workflow dialog "Run a dynamic workflow?" offers "1. Yes, run it". It
# starts many agents, so the user answers it.
set yes {Yes(?![^\r\n]{0,40}run[^\r\n]{0,12}it)}
# Claude Code draws ANSI attributes between "1." and "Yes".
set option {1\.[^\r\n]{0,60}}
append option $yes
# Claude Code draws only the characters that change. A dialog drawn over the
# last one can lose letters of its question, but it always draws the selector.
set selected {\u276f(?:\u001b\[[0-9;]*[mG]| )*1(?:\.|\u001b\[[0-9;]*[mG]| )*}
append selected $yes
# These show that no permission dialog is open: the empty input box, and the
# footer of a question that Claude asks the user.
set closed {\u276f\u00a0|Enter[^\r\n]{1,24}to[^\r\n]{1,24}select}
# A question that Claude asks the user has a header chip such as "☐ Next step"
# above it, and its first option is often "Yes". A permission dialog has no chip.
set ask {\u2610}
# Claude Code refuses input that arrives less than 150 ms after a dialog
# appears, so that a stray keypress cannot approve it. Wait past that window.
set settle 400

# CRUISE_CTRL_TRACE records every byte Claude Code writes, to build a pattern
# for a dialog that the wrapper does not answer.
if {[info exists env(CRUISE_CTRL_TRACE)]} {
    log_file -a $env(CRUISE_CTRL_TRACE)
}

spawn -noecho claude {*}$argv

# interact overwrites both of these, so keep a copy.
set claude $spawn_id
set claude_tty $spawn_out(slave,name)

set armed 0
set stale 0
set waiting 0
set pending ""

proc resize {} {
    global claude_tty
    if {[catch {stty rows} rows]} return
    if {[catch {stty columns} cols]} return
    # stty reports 0 rather than failing when stdin is not a terminal.
    if {$rows > 0 && $cols > 0} {
        catch {stty rows $rows columns $cols < $claude_tty}
    }
}

proc arm {} {
    global armed stale waiting
    if {!$stale && !$waiting} { set armed 1 }
}

proc approve {} {
    global armed waiting settle pending
    if {!$armed} return
    # A stale latch must not approve a later "1. Yes" that is only prose.
    set armed 0
    # A sleep would stop interact from reading. Claude Code would then block
    # on the full pty, and its redraws would arrive only after the "1".
    set waiting 1
    set pending [after $settle send_yes]
}

proc cancel {} {
    global waiting pending
    # The dialog closed during the wait, so a "1" would go into the input box.
    if {$waiting} {
        after cancel $pending
        set waiting 0
    }
}

proc send_yes {} {
    global claude stale waiting env
    send -i $claude -- "1\r"
    set waiting 0
    # Claude Code wrote the output that is waiting now before it read the "1",
    # so it can only be a redraw of this dialog. A redraw can use other escape
    # sequences, and a second "1" would go into the prompt box. The event loop
    # becomes idle only after interact has read all of that output.
    set stale 1
    after idle { set stale 0 }
    if {[info exists env(CRUISE_CTRL_LOG)]} {
        set log [open $env(CRUISE_CTRL_LOG) a]
        puts $log "[clock format [clock seconds]] approved"
        close $log
    }
}

proc ignore_ask {} {
    global armed stale
    set armed 0
    # The question and its options arrive in the same output as the chip.
    set stale 1
    after idle { set stale 0 }
}

resize
trap resize WINCH

# A wrapped question arms on the title, which Claude Code draws first.
interact -o \
    -nobuffer -re $ask { ignore_ask } \
    -nobuffer -re $question { arm } \
    -nobuffer -re $title { arm } \
    -nobuffer -re $selected { arm; approve } \
    -nobuffer -re $option { approve } \
    -nobuffer -re $closed { cancel }

catch wait result
exit [lindex $result 3]
