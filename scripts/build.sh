#!/bin/bash

dir=$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")
out="$dir/output"
bin="$out/bin"

echo "Building OCPlist from $dir..."

cd gui
echo "Building GUI for web..."
flutter build web

echo "Copying web files..."
cp -r "web" "$dir/public"

echo "Building CLI tool..."
cd $dir
mkdir -p "$bin"

dart compile exe bin/ocplist.dart -o $bin/ocplist
dart compile exe bin/oclog.dart -o $bin/oclog

echo "App built!"