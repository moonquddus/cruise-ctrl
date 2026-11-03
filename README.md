# cruise-ctrl

Cruise control for Claude Code. It starts Claude Code and answers the permission
prompts with `1. Yes`.

## Why

Claude Code has a bypass-permissions mode. That mode can still fall back to a
permission prompt and stop work until you answer it. `cruise-ctrl`
watches for those prompts and answers them, so a long task does not wait for
you.

You keep full control of the session. The wrapper passes your keyboard through
to Claude Code, so you can type, interrupt and quit as usual.

## Requirements

- `expect`. On macOS, install it with `brew install expect`. On Debian or
  Ubuntu, use `sudo apt install expect`.
- `claude` on your `PATH`.

## Install

Copy the script to a directory on your `PATH` and make it executable. Make the
directory first, because `install` does not create it:

```sh
mkdir -p ~/.local/bin
install -m 755 cruise-ctrl.sh ~/.local/bin/cruise-ctrl
```

If `cruise-ctrl` is not found after this, add the directory to your `PATH`.

## Use

Use `cruise-ctrl` in place of `claude`. It passes on every argument:

```sh
cruise-ctrl
cruise-ctrl --resume
cruise-ctrl "fix the failing tests"
cruise-ctrl --dangerously-skip-permissions
```

## Herdr plugin

If you run Claude Code in herdr, use the plugin in place
of the wrapper. The plugin monitors all Claude Code panes, so you start
`claude` as usual. It needs Python 3.11 or later.

```sh
herdr plugin link ~/workspace/cruise-ctrl
```

Herdr marks a pane as `blocked` when Claude Code shows a dialog. The plugin
then reads the screen of that pane. If the screen shows a permission dialog
with `❯ 1. Yes` selected, the plugin waits 400 ms and sends `1` and Enter. It
then reads the screen again, because Claude Code shows queued dialogs one at a
time.

The plugin uses the same checks as the wrapper. It does not answer questions
that Claude asks you, or `Run a dynamic workflow?`. If a dialog does not close
after the answer, the plugin does not send a second answer.

To stop the plugin, use `herdr plugin disable cruise-ctrl`.

### Settings

Open the command palette and run `Cruise Ctrl: Settings`. This opens
`settings.toml` in `$EDITOR`. The file is in the directory that
`herdr plugin config-dir cruise-ctrl` shows.

| Setting     | Default | Effect                                            |
| ----------- | ------- | ------------------------------------------------- |
| `log`       | `true`  | Record each answer in `approvals.log`.            |
| `trace`     | `false` | Record each screen that the plugin reads in `trace.log`. |
| `settle_ms` | `400`   | Time to wait after a dialog appears.              |

The plugin reads the file again for each dialog, so a change has an effect
immediately. The logs are in `~/.local/state/herdr/plugins/cruise-ctrl`.
Run `Cruise Ctrl: Show Log` to see the answers live.

## How it works

The script starts Claude Code on a pseudo-terminal and connects your keyboard
to it. At the same time it reads the output of Claude Code and looks for two
things in order:

1. A question that starts with `Do you want to` and ends with `?`, or the
   title `Network request outside of sandbox`.
2. The first option, `1. Yes`.

The sandbox dialog draws its question in a box. A narrow window wraps the
question across two lines, and then only the title identifies the dialog.

Claude Code does not always write the spaces between the words. In full-screen
mode it moves the cursor to the start of the next word instead. The wrapper
accepts a space or an escape sequence at each of these positions.

Claude Code also draws only the characters that change. When a dialog replaces
the last one, its question can arrive with letters missing, for example
`Do you wa t to proceed?`. The wrapper then finds the dialog by its selected
first option, `❯ 1. Yes`. That line can also lose its dot.

When it finds both, it waits 400 ms and then sends `1` and a carriage return.
This is the same input as a manual selection of `1. Yes`.

The wait is necessary. Claude Code refuses input that arrives less than 150 ms
after a dialog appears, so that a stray keypress cannot approve it. An
immediate `1` is discarded, and the wrapper gets no second chance.

Five checks keep the wrapper quiet:

- It answers only when the option list comes after the question, or when it
  sees the selected option `❯ 1. Yes`. If Claude Code writes
  `Do you want to proceed?` in ordinary text, the wrapper does nothing.
- It answers a given prompt once. Claude Code can draw an open dialog again
  during the wait, with other escape sequences. The wrapper continues to read
  during the wait and ignores those redraws. After it sends `1`, the wrapper
  ignores all output that is already waiting. That output came before Claude
  Code read the `1`, so it can only be a redraw. Each dialog after that is a
  new one, also when it has the same text as the last, for example a second
  edit to the same file.
- It does not answer the questions that Claude asks you. Such a question has a
  header chip, for example `☐ Next step`, and its first option is often `Yes`.
  When the wrapper sees the chip, it ignores the question and its options.
  Such a question also has the footer `Enter to select`. If the wrapper sees
  that footer during the wait, it sends nothing.
- It does not send `1` to a dialog that closed during the wait. A queued dialog
  can close by itself, for example after an earlier `allow reading during this
  session`. Claude Code then draws the empty input box, and the wrapper sends
  nothing. Without this check, Claude would get `1` as a message.
- It does not answer `Run a dynamic workflow?`. A workflow starts many agents,
  so you answer it yourself. The wrapper ignores a first option of
  `Yes, run it`.

The script also copies the size of your terminal to Claude Code, and does it
again when you change the size of the window.

## Trace

Set `CRUISE_CTRL_TRACE` to a file to record every byte that Claude Code writes.
Use this to build a pattern for a dialog that the wrapper does not answer.

```sh
CRUISE_CTRL_TRACE=/tmp/cruise-ctrl.trace cruise-ctrl
```

## Log

Set `CRUISE_CTRL_LOG` to record each automatic answer:

```sh
CRUISE_CTRL_LOG=~/cruise-ctrl.log cruise-ctrl
```

The wrapper does not write to the screen, because that damages the Claude Code
display.

## Keep your Mac awake

A Mac that goes to sleep stops a long task. On macOS, use the built-in
`caffeinate` command to prevent idle sleep while the wrapper runs:

```sh
caffeinate -i cruise-ctrl
```

To do this each time, add an alias to your `~/.zshrc`:

```sh
alias cruise='caffeinate -i cruise-ctrl'
```

`caffeinate` stops when the wrapper exits. The `-i` flag lets the display
turn off. Use `-di` to keep the display on too. A Mac with a closed lid
still goes to sleep, unless it has power and an external display.

## Tests

```sh
./test/run.sh
```

The tests replace `claude` with a stub program and drive the wrapper through a
pseudo-terminal. They need no network and no credentials.

## Limits

- The wrapper answers `Yes` to every permission prompt that it finds. It
  removes that safety check. Use it only for work that you accept in advance.
- In sandbox mode, this includes `Network request outside of sandbox`. The
  wrapper allows the connection to each host that Claude Code asks about.
- The wrapper finds a prompt by its text. A change to the text in a new version
  of Claude Code can stop it. If this occurs, the wrapper sends nothing and you
  answer the prompt yourself.
- Use the wrapper for interactive sessions. For a piped or scripted run, use
  `claude` directly.

## License

MIT. See [LICENSE](LICENSE).
