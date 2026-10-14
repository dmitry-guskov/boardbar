#!/bin/zsh
# Build BoardBar, copy it to ~/Applications and start it at login.
# Usage: ./install.sh [path/to/board.json]
set -e
cd "${0:A:h}"
./build.sh
board="${1:-$HOME/Documents/Obsidian Vault/07 Meta/board.json}"
mkdir -p ~/Applications
pkill -x BoardBar 2>/dev/null || true
rm -rf ~/Applications/BoardBar.app
cp -R BoardBar.app ~/Applications/
defaults write local.boardbar boardPath "$board"
plist=~/Library/LaunchAgents/local.boardbar.plist
cat > $plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>local.boardbar</string>
<key>ProgramArguments</key><array><string>$HOME/Applications/BoardBar.app/Contents/MacOS/BoardBar</string></array>
<key>RunAtLoad</key><true/>
</dict></plist>
PLIST
launchctl bootout gui/$(id -u) $plist 2>/dev/null || true
launchctl bootstrap gui/$(id -u) $plist
echo "Installed ~/Applications/BoardBar.app, reading: $board"
