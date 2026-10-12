#!/bin/bash
cd "$(dirname "$0")"

# Point to the Godot binary in the current folder
GODOT_EXE="./Godot_v4.7.2-stable_linux.x86_64"

if [ ! -f "$GODOT_EXE" ]; then
    echo "Godot binary not found in the game folder."
    read -p "Press Enter to exit..."
    exit 1
fi

# Launch the game
"$GODOT_EXE" --path . &
