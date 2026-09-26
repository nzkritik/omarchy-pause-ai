# Pause AI

An Omarchy bar button that freezes every AI agent CLI on your machine
(Claude Code, Codex, Gemini CLI, OpenCode, Cursor Agent, Crush, Aider,
Goose, Amp, Qwen Code, Copilot CLI) and resumes them exactly where they were.

- **Left click** pauses all agents until you click again.
- **Right click** opens a panel: pause for 5, 10, 15 or 30 minutes, an hour,
  or until resumed; resume now; and the agents it can see.

While paused the icon turns into a pause sign and the tooltip counts down.
Agents that start during a pause are frozen too, within a few seconds.

## How it works

Pausing sends `SIGSTOP` to each agent **and everything it started** (shells,
builds, MCP servers), so nothing it set in motion carries on without it.
Resuming sends `SIGCONT` to exactly those processes and nothing else.

- An agent started from an interactive shell has that shell frozen first and
  thawed last. Otherwise the shell would see its foreground job stop, print
  `Stopped` and take the terminal back, leaving the agent stuck in the
  background after the resume.
- Processes that were already stopped (Ctrl-Z, a debugger) are never
  recorded, so a resume cannot wake them.
- Every frozen process is recorded with its start time, so a recycled
  process id is never woken by mistake.
- The pause survives a shell restart: the state lives in
  `/run/user/<uid>/nzkritik.pause-ai/`, and a timed pause whose time ran out
  meanwhile ends as soon as the shell is back.
- Only your own processes are touched. Nothing runs with elevated
  privileges, so system services (for example the `ollama` system service)
  are out of reach by design.

A paused agent keeps its full state. A request to an AI service that was in
flight may time out if the pause is long; agents generally retry.

## Requirements

Omarchy with the Quickshell bar, and `python3` (in Omarchy's base install).

## Install

```bash
git clone https://github.com/nzkritik/omarchy-pause-ai ~/.config/omarchy/plugins/nzkritik.pause-ai
omarchy bar put nzkritik.pause-ai
```

## Remove

```bash
omarchy-shell nzkritik.pause-ai resume     # if anything is paused
omarchy bar remove nzkritik.pause-ai 2>/dev/null || true
rm -rf ~/.config/omarchy/plugins/nzkritik.pause-ai
omarchy restart shell
```

If `omarchy bar` has no `remove` on your version, delete the
`nzkritik.pause-ai` entry from `~/.config/omarchy/shell.json` instead.

## Settings

**Extra agent commands**: more command names to treat as agents,
space-separated (for example a wrapper script you run agents through).

## Scripting

```bash
omarchy-shell nzkritik.pause-ai pause 15     # minutes; 0 = until resumed
omarchy-shell nzkritik.pause-ai resume
omarchy-shell nzkritik.pause-ai status
```

`bin/pause-ai` also works on its own (`scan`, `pause [--until EPOCH]`,
`resume`, `status`), which is handy from a keybinding or a script.

## Tests

```bash
python3 -m unittest discover -s tests
```

The tests run a fake agent as the foreground job of a real interactive
shell and check the whole freeze/thaw cycle, including that the shell never
reports it stopped.

## License

MIT
