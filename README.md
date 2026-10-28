# rex-resurrect

Save and restore Rex sessions, like tmux-resurrect and tmux-continuum.

It saves every session's tabs, splits and their sizes, floating panes, the zoomed and focused pane, each pane's working directory and scrollback, and the program running in it. Restore rebuilds all of it. Autosave keeps a snapshot every five minutes and restores the last one when the Rex server starts.

## Install

```sh
git clone https://github.com/hanzpo/rex-ressurect.git
cd rex-ressurect
./install.sh
```

This adds two lines to `~/.config/rex/init.lua` and starts a launchd agent for autosave. Run `./install.sh --no-autosave` to skip the agent. `./uninstall.sh` removes both.

## Use

```sh
rex do resurrect_save
rex do resurrect_restore
rex do resurrect_restore path=/path/to/snapshot.json
```

Restore skips any session whose name is already open, so running it twice is safe.

## Settings

Put them in `~/.config/rex/resurrect.lua`:

```lua
return {
  keys = { save = "ctrl+shift+s", restore = "ctrl+shift+r" },
  prompt_lines = 2,
  interval = 300,
  keep = 20,
  auto_restore = true,
  scrollback = true,
  scrollback_lines = 5000,
  programs = {
    ssh = false,
    yazi = true,
  },
}
```

| Setting | Default | What it does |
| --- | --- | --- |
| `keys` | none | Key bindings for save and restore |
| `prompt_lines` | 1 | Lines your shell prompt takes up, dropped from saved scrollback so it isn't shown twice |
| `interval` | 300 | Seconds between autosaves |
| `keep` | 20 | Snapshots to keep |
| `auto_restore` | true | Restore when the server starts |
| `scrollback` | true | Save each pane's scrollback |
| `scrollback_lines` | 5000 | Lines of scrollback to keep per pane |
| `programs` | see below | Programs to start again on restore |
| `dir` | `~/.local/share/rex-resurrect` | Where snapshots go |

Run `rex config reload` after changing settings, and `launchctl kickstart -k gui/$(id -u)/com.rex-resurrect.autosave` to restart autosave.

## Programs

Rex reports the program running in each pane but not its arguments, since they can hold secrets. A program comes back only if it's listed in `programs`:

- `true` runs it by name: `vi`, `vim`, `nvim`, `emacs`, `nano`, `htop`, `btop`, `top`, `lazygit`
- a string runs that command instead: `claude` runs `claude --continue`, `codex` runs `codex resume --last`
- `false` turns off a default

The command is typed into a fresh shell, so the shell is still there when the program exits.

## Limits

- Rex doesn't yet run event handlers from `init.lua`, so autosave runs as `rex do autosave.lua --all` under launchd. It waits for the server rather than starting it.
- Scrollback is saved as plain text, so colors are lost. Panes showing a full-screen program, like vim, have no scrollback saved.
- Panes that aren't terminals are skipped.

## Files

- `resurrect.lua` saves and restores, and registers the actions
- `autosave.lua` restores once per server start, then saves on a timer
- Snapshots are `snapshots/<time>.json` with scrollback in `snapshots/<time>/`. `last` holds the newest one's path.
