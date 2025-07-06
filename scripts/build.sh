#!/bin/bash

dir=$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")
out="$dir/output"
bin="$out/bin"
kernel="$out/kernel"
www="$dir/public"
buildgui=true

for arg in "$@"; do
  if [ "$arg" == "--no-gui" ]; then
    buildgui=false
    break
  fi
done

echo "Building OCPlist from $dir..."
cd "$dir"
rm -rf "$out"
rm -rf "$www"
mkdir -p "$bin"
mkdir -p "$www"
mkdir -p "$kernel"

compile() {
    ext=""
    if [[ -n "$3" ]]; then ext=".$3"; fi;
    echo "Building CLI to $1... (output: $2/)"
    dart compile "$1" bin/ocplist.dart -o "$2/ocplist$ext"
    dart compile "$1" bin/oclog.dart -o "$2/oclog$ext"
}

compile exe "$bin"
compile kernel "$kernel" dill

if [ "$buildgui" = true ]; then
    echo "Building GUI for web..."
    cd gui
    flutter build web --base-href /ocplist/
    cp -r build/web/* "$www"
fi

cd "$dir"
echo "App built!"