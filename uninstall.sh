#!/bin/zsh
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/local.boardbar.plist 2>/dev/null || true
rm -f ~/Library/LaunchAgents/local.boardbar.plist
pkill -x BoardBar 2>/dev/null || true
rm -rf ~/Applications/BoardBar.app
defaults delete local.boardbar 2>/dev/null || true
echo "BoardBar removed"
