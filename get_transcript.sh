#!/bin/bash
# Check if Python 3 is installed
if ! command -v python3 &>/dev/null; then
    echo "Installing Python 3..."
    sudo pacman -Sy python --noconfirm || { echo "Failed to install Python 3."; exit 1; }
fi

# Run the Python script
python3 get_transcript.py "$@"