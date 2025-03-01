# Original bash script:
# #!/bin/bash
# xclip -sel clip -o | sed -E 's/^[0-9]{2}:[0-9]{2}:[0-9]{2}[[:space:]]+//' | tr '\n' ' ' | xclip -sel clip -i
# Alternative version using awk (not used):
# xclip -sel clip -o | awk '{sub(/^[0-9]{2}:[0-9]{2}:[0-9]{2}[[:space:]]+/, ""); printf "%s ", $0} END {print ""}' | xclip -sel clip -i

#!/usr/bin/env python3
import sys
import re
import subprocess
import platform

def install_package(package):
    try:
        __import__(package)
    except ImportError:
        subprocess.check_call([sys.executable, "-m", "pip", "install", package])

# Install required Python packages
install_package("youtube_transcript_api")
install_package("pyperclip")

from youtube_transcript_api import YouTubeTranscriptApi
import pyperclip

def install_linux_dependencies():
    try:
        subprocess.run(["xclip", "-version"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        print("xclip not found. Attempting to install xclip...")
        try:
            subprocess.check_call(["sudo", "pacman", "-S", "--noconfirm", "xclip"])
        except Exception as e:
            print("Failed to install xclip. Please install it manually.")
            sys.exit(1)

def extract_video_id(url):
    regex = r"(?:v=|\/)([0-9A-Za-z_-]{11}).*"
    match = re.search(regex, url)
    if match:
        return match.group(1)
    else:
        print("Invalid YouTube URL")
        sys.exit(1)

def get_transcript(video_id):
    try:
        transcript_list = YouTubeTranscriptApi.get_transcript(video_id)
        transcript_text = "\n".join(entry["text"] for entry in transcript_list)
        return transcript_text
    except Exception as e:
        print("Error retrieving transcript:", e)
        sys.exit(1)

def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <YouTube URL>")
        sys.exit(1)
    
    url = sys.argv[1]
    video_id = extract_video_id(url)
    
    os_name = platform.system()
    if os_name == "Linux":
        install_linux_dependencies()
    elif os_name == "Windows":
        pass
    else:
        print("Unsupported OS. This script supports Linux (Arch) and Windows.")
        sys.exit(1)
    
    transcript = get_transcript(video_id)
    pyperclip.copy(transcript)
    print("Transcript copied to clipboard.")

if __name__ == "__main__":
    main()
