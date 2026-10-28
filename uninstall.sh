#!/bin/sh
set -eu

init=${XDG_CONFIG_HOME:-$HOME/.config}/rex/init.lua
label=com.rex-resurrect.autosave

launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$label.plist"

if [ -f "$init" ]; then
  grep -v -e '/?.lua;" .. package.path' -e 'require("resurrect")' "$init" > "$init.tmp" || true
  mv "$init.tmp" "$init"
fi
rex config reload >/dev/null 2>&1 || true
echo "Removed. Snapshots are still in ~/.local/share/rex-resurrect."
