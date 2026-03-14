#!/bin/bash
#
# YouTube Transcript Fetcher - Linux/macOS
# Manages venv automatically, installs dependencies on first run
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$HOME/.local/share/get_transcript_venv"
PYTHON_SCRIPT="$SCRIPT_DIR/get_transcript.py"

# Check if Python 3 is available
if ! command -v python3 &>/dev/null; then
    echo "Error: Python 3 is not installed" >&2
    echo "Install with: sudo apt install python3 python3-venv (Debian/Ubuntu)" >&2
    echo "              sudo dnf install python3 python3-venv (Fedora/RHEL)" >&2
    echo "              brew install python (macOS)" >&2
    exit 1
fi

# Create virtual environment if not exists
if [ ! -d "$VENV_DIR" ]; then
    echo "Setting up virtual environment..." >&2
    python3 -m venv "$VENV_DIR" || {
        echo "Failed to create virtual environment" >&2
        exit 1
    }
fi

# Activate venv and install/update packages
VENV_PIP="$VENV_DIR/bin/pip"
VENV_PYTHON="$VENV_DIR/bin/python"

"$VENV_PIP" install --upgrade pip --quiet 2>/dev/null
# Use specific version known to work, or latest if not specified
"$VENV_PIP" install "youtube-transcript-api>=0.6.0" --quiet 2>/dev/null || {
    echo "Failed to install youtube-transcript-api" >&2
    exit 1
}

# Check Python script exists
if [ ! -f "$PYTHON_SCRIPT" ]; then
    echo "Error: get_transcript.py not found in $SCRIPT_DIR" >&2
    exit 1
fi

# Run the Python script with all arguments
exec "$VENV_PYTHON" "$PYTHON_SCRIPT" "$@"
