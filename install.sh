#!/bin/sh
set -eu

repo=$(cd "$(dirname "$0")" && pwd)
config_dir=${XDG_CONFIG_HOME:-$HOME/.config}/rex
init="$config_dir/init.lua"
data="$HOME/.local/share/rex-resurrect"
label=com.rex-resurrect.autosave
plist="$HOME/Library/LaunchAgents/$label.plist"
rex=$(command -v rex) || { echo "rex isn't on your PATH" >&2; exit 1; }

mkdir -p "$config_dir" "$data" "$HOME/Library/LaunchAgents"

if ! grep -q 'require("resurrect")' "$init" 2>/dev/null; then
  cat >> "$init" <<EOF

package.path = "$repo/?.lua;" .. package.path
require("resurrect").setup()
EOF
fi
"$rex" config reload >/dev/null

[ "${1:-}" = "--no-autosave" ] && { echo "Installed actions resurrect_save and resurrect_restore."; exit 0; }

cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$rex</string>
    <string>do</string>
    <string>$repo/autosave.lua</string>
    <string>--all</string>
    <string>--autostart=false</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>15</integer>
  <key>StandardOutPath</key><string>$data/autosave.log</string>
  <key>StandardErrorPath</key><string>$data/autosave.log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$plist"
echo "Installed actions resurrect_save and resurrect_restore, and autosave."
