#!/usr/bin/env python3
import sys
import re

def extract_video_id(url):
    regex = r"(?:v=|\/)([0-9A-Za-z_-]{11}).*"
    match = re.search(regex, url)
    if match:
        return match.group(1)
    else:
        print("Invalid YouTube URL", file=sys.stderr)
        sys.exit(1)

def get_transcript(video_id):
    try:
        from youtube_transcript_api import YouTubeTranscriptApi
        yt_api = YouTubeTranscriptApi()

        # Get a list of all available transcripts for the video
        transcript_list = yt_api.list(video_id)

        # Find a transcript in English
        transcript = transcript_list.find_transcript(['en'])

        # Fetch the transcript data
        fetched_transcript = transcript.fetch()

        # Join the text
        transcript_text = "\n".join(snippet.text for snippet in fetched_transcript)
        return transcript_text

    except Exception as e:
        print(f"Error retrieving transcript: {e}", file=sys.stderr)
        sys.exit(1)

def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <YouTube URL>", file=sys.stderr)
        sys.exit(1)
    
    url = sys.argv[1]
    video_id = extract_video_id(url)
    transcript = get_transcript(video_id)
    
    # Just print the transcript - user can copy from VS Code terminal
    print(transcript)

if __name__ == "__main__":
    main()