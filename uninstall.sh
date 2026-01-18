#!/bin/bash
read -p "Where is CrossOver.app? [/Applications/CrossOver.app]: " USER_PATH
APP_PATH="${USER_PATH:-/Applications/CrossOver.app}"
CROSSOVER_MACOS_PATH="$APP_PATH/Contents/MacOS"
if [ ! -d "$CROSSOVER_MACOS_PATH" ]; then
    echo "CrossOver.app wasnt found at $APP_PATH. nthing to uninstall (or you moved it)."
    exit 1
fi

cd "$CROSSOVER_MACOS_PATH" || exit 1

if [ ! -f "CrossOver.o" ]; then
    echo "Backup 'CrossOver.o' wasnt found. Is the patch installed?"
    exit 1
fi

echo "Removing hook.dylib..."
rm -f hook.dylib

echo "Removing pco.sh..."
rm -f pco.sh

echo "Restoring original CrossOver executable..."
rm -f CrossOver # verification
mv CrossOver.o CrossOver

# just to be safe
chmod +x CrossOver

echo "Uninstall complete. CrossOver is back to normal. (boooooooo)"
