#!/usr/bin/env python3
"""
YouTube Transcript Fetcher with Language Fallback
Strategy: preferred_lang → vi/vn → any translatable (translated to preferred)
"""
import sys
import re

def extract_video_id(url):
    """Extract YouTube video ID from various URL formats."""
    regex = r"(?:v=|\/)([0-9A-Za-z_-]{11}).*"
    match = re.search(regex, url)
    if match:
        return match.group(1)
    print("Invalid YouTube URL", file=sys.stderr)
    sys.exit(1)

def get_transcript(video_id, preferred_languages=None):
    """
    Fetch transcript with 3-tier language fallback:
    1. Preferred languages (default: ['en'])
    2. Vietnamese fallback ['vi', 'vn']
    3. Any available transcript translated to preferred language

    Returns: (transcript_text, language_code, was_translated)
    """
    try:
        from youtube_transcript_api import YouTubeTranscriptApi

        if preferred_languages is None:
            preferred_languages = ['en']

        yt_api = YouTubeTranscriptApi()
        transcript_list = yt_api.list(video_id)

        # Tier 1: Try preferred languages (native transcripts)
        try:
            transcript = transcript_list.find_transcript(preferred_languages)
            fetched = transcript.fetch()
            text = "\n".join(snippet.text for snippet in fetched)
            return text, transcript.language_code, False
        except Exception:
            pass

        # Tier 2: Try Vietnamese fallback
        try:
            transcript = transcript_list.find_transcript(['vi', 'vn'])
            fetched = transcript.fetch()
            text = "\n".join(snippet.text for snippet in fetched)
            return text, transcript.language_code, False
        except Exception:
            pass

        # Tier 3: Find ANY translatable transcript and translate
        for transcript in transcript_list:
            if transcript.is_translatable:
                target_lang = preferred_languages[0]
                translated = transcript.translate(target_lang)
                fetched = translated.fetch()
                text = "\n".join(snippet.text for snippet in fetched)
                return text, target_lang, True

        raise Exception(f"No transcripts available for video {video_id}")

    except Exception as e:
        print(f"Error retrieving transcript: {e}", file=sys.stderr)
        sys.exit(1)

def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <YouTube URL> [language_codes...]", file=sys.stderr)
        print(f"  Default: en → vi → any (translated)", file=sys.stderr)
        print(f"  Example: {sys.argv[0]} https://youtu.be/VIDEO_ID en de", file=sys.stderr)
        sys.exit(1)

    url = sys.argv[1]
    video_id = extract_video_id(url)
    preferred_languages = sys.argv[2:] if len(sys.argv) > 2 else None

    transcript, lang_code, was_translated = get_transcript(video_id, preferred_languages)

    # Metadata to stderr (doesn't interfere with stdout capture)
    status = "translated" if was_translated else "native"
    print(f"# Transcript: {lang_code} ({status})", file=sys.stderr)

    # Transcript to stdout (clean for piping/capture)
    print(transcript)

if __name__ == "__main__":
    main()
