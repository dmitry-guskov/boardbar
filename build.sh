#!/bin/zsh
set -e
cd "${0:A:h}"
app=BoardBar.app
rm -rf $app
mkdir -p $app/Contents/MacOS $app/Contents/Resources
swiftc -O -parse-as-library BoardBar.swift -o $app/Contents/MacOS/BoardBar -framework SwiftUI -framework WebKit
cp board.html $app/Contents/Resources/
cat > $app/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>BoardBar</string>
<key>CFBundleIdentifier</key><string>local.boardbar</string>
<key>CFBundleExecutable</key><string>BoardBar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
EOF
codesign --force -s - $app
echo "Built $PWD/$app"
