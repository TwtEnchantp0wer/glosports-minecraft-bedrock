#!/bin/sh
# Run the bundled LÖVE 11.5 armhf runtime against the local lib/ directory.
# Invoked as: sh run-love.sh <game-dir> [args...]
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LD_LIBRARY_PATH="$DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH
exec "$DIR/love" "$@"
