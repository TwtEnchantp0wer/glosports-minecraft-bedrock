#!/bin/bash
# Build script for linux users (same UX as glOSports-half-life).

set -eu

if command -v podman &> /dev/null; then
    podman build -o ./out .
elif command -v docker &> /dev/null; then
    docker buildx build --output type=local,dest=./out .
else
    echo "Error: neither podman nor docker was found in PATH." >&2
    exit 1
fi

echo
echo "Done: out/minecraft-bedrock-port.zip"
echo "Unzip it into the root of the HOME partition of your goodluckOS SD card."
