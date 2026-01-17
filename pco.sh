#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"

cp "$DIR/hook.dylib" "/tmp/hook.dylib"

DYLD_INSERT_LIBRARIES="/tmp/hook.dylib" "$DIR/CrossOver.o" "$@"
