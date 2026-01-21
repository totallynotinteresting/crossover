#!/bin/bash

# btw if ur gonna steal this shit at least give me credit holy

set -e

read -p "Where is CrossOver.app? [/Applications/CrossOver.app]: " USER_PATH < /dev/tty
APP_PATH="${USER_PATH:-/Applications/CrossOver.app}"
CONTENTS_PATH="$APP_PATH/Contents"
MACOS_PATH="$CONTENTS_PATH/MacOS"
SHARED_SUPPORT="$CONTENTS_PATH/SharedSupport/CrossOver"
REPO_URL="https://github.com/totallynotinteresting/crossover.git"
RAW_URL="https://raw.githubusercontent.com/totallynotinteresting/crossover/main"
RELEASE_URL="https://github.com/totallynotinteresting/crossover/releases/latest/download/hook.dylib"

if [ ! -d "$APP_PATH" ]; then
    echo "CrossOver.app was not found at $APP_PATH"
    echo "please make sure that CrossOver.app is in /Applications/"
    exit 1
fi

cd "$MACOS_PATH" || exit 1

if git clone "$REPO_URL" crossover_patch; then
    cd crossover_patch || exit 1
    # try to build (because who doesnt trust open source right?)
    echo "building hook.dylib because this contains the logic"
    if clang -dynamiclib -arch arm64 -arch x86_64 -framework Foundation -framework AppKit -o hook.dylib hook.m; then
        echo "Build successful."
    else
        echo "either somethings gone wrong or you dont have clang installed, so we're gonna download it from the gh directly"
        curl -L -o hook.dylib "$RELEASE_URL"
    fi
else
    echo "bruh u dont have git installed, so we gon do some manual downlaoding instead"
    mkdir -p crossover_patch
    cd crossover_patch || exit 1
    
    echo "this is the thing that kinda makes it work"
    curl -L -o pco.sh "$RAW_URL/pco.sh"
    
    echo "this is the thing that actually does the hooking"
    curl -L -o hook.dylib "$RELEASE_URL"
fi

# ok well if it doesnt exist, you've clearly done something wrong
if [ ! -f hook.dylib ]; then
    echo "how the hell is hook.dylib not there?"
    cd ..
    rm -rf crossover_patch
    exit 1
fi

echo "signing it because macos is specal like that"
codesign -f -s - hook.dylib

echo "blah blah moving it to where it belongs"
mv hook.dylib ..
mv ../CrossOver ../CrossOver.o
echo "gotta resign crossover as well because something about macos doing hardened runtime"
codesign -f -s - ../CrossOver.o
mv pco.sh ../CrossOver
chmod +x ../CrossOver

echo "i lowk forgot that codeweavers also licensed the wine exec itself, so we doin ts too"
LOADER_PATH="$SHARED_SUPPORT/bin/wineloader"
if [ -f "$LOADER_PATH" ]; then
    codesign -f -s - "$LOADER_PATH"
else
    echo "wineloader not found at $LOADER_PATH"
fi

WINE_SCRIPT="$SHARED_SUPPORT/bin/wine"

if ! grep -q "DYLD_INSERT_LIBRARIES" "$WINE_SCRIPT"; then
    sed -i '' '/exec $cmd, @wine_args, @args/i\
if ($cmd =~ /wineloader/) {\
    $ENV{'\''DYLD_INSERT_LIBRARIES'\''} = '\''/tmp/hook.dylib'\'';\
}\
' "$WINE_SCRIPT"
    echo "bin/wine patched."
else
    echo "bin/wine already patched."
fi

cd ..
rm -rf crossover_patch

echo "uh sure try it out"
