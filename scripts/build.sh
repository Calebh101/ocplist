#!/bin/bash

dir=$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")
out="$dir/output"
bin="$out/bin"
www="$dir/public"

echo "Building OCPlist from $dir..."
rm -rf "$out"
rm -rf "$www"
mkdir -p "$bin"
mkdir -p "$www"

cd gui
echo "Building GUI for web..."
flutter build web --base-href /ocplist/
cp -r build/web/* "$www"

echo "Building CLI tool..."
cd $dir

dart compile exe bin/ocplist.dart -o $bin/ocplist
dart compile exe bin/oclog.dart -o $bin/oclog

echo "App built!"