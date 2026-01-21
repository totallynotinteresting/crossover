#!/bin/bash
set -e 

echo "removing .update-timestamp from bottles"
rm -f ~/Library/Application\ Support/CrossOver/Bottles/*/.update-timestamp

for reg in ~/Library/Application\ Support/CrossOver/Bottles/*/system.reg; do
    echo "resetting time on $reg"
    [ -f "$reg" ] && sed -i '' '/\[Software\\\\CodeWeavers\\\\CrossOver\\\\cxoffice\]/,/"Version"=/d' "$reg"
done
