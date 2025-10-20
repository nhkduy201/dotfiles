#!/bin/bash

# Check if Python 3 is available
if ! command -v python3 &>/dev/null; then
    echo "Error: Python 3 is not installed" >&2
    exit 1
fi

# Setup virtual environment
VENV_DIR="$HOME/.local/share/get_transcript_venv"
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR" >/dev/null 2>&1 || { echo "Failed to create virtual environment." >&2; exit 1; }
fi

# Install/update packages silently
"$VENV_DIR/bin/pip" install --upgrade pip >/dev/null 2>&1
"$VENV_DIR/bin/pip" install --force-reinstall youtube-transcript-api >/dev/null 2>&1 || { echo "Failed to install YouTube transcript API." >&2; exit 1; }

# Run the Python script
"$VENV_DIR/bin/python" get_transcript.py "$@"