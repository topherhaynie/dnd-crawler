#!/usr/bin/env bash
#
# setup_ffmpeg_dev.sh — Download a static ffmpeg/ffprobe with libtheora support
# for local development.  The Godot editor will find these binaries automatically.
#
# Why?  Homebrew's ffmpeg 8.x dropped the libtheora encoder, which The Vault
# needs to convert video → OGV (Theora/Vorbis) for Godot's VideoStreamTheora.
# The evermeet.cx static builds include libtheora.
#
# Usage:
#   ./setup_ffmpeg_dev.sh          # macOS only (for now)
#

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

case "$(uname -s)" in
    Darwin)
        CACHE_DIR="$PROJECT_DIR/.cache/ffmpeg-macos"
        FFMPEG_URL="https://evermeet.cx/ffmpeg/ffmpeg-7.1.1.zip"
        FFPROBE_URL="https://evermeet.cx/ffmpeg/ffprobe-7.1.1.zip"

        if [[ -x "$CACHE_DIR/ffmpeg" ]] && [[ -x "$CACHE_DIR/ffprobe" ]]; then
            echo "Static ffmpeg and ffprobe already present at $CACHE_DIR"
            "$CACHE_DIR/ffmpeg" -version | head -1
            exit 0
        fi

        echo "Downloading static ffmpeg and ffprobe (with libtheora) …"
        mkdir -p "$CACHE_DIR"
        curl -# -L -o "$CACHE_DIR/ffmpeg.zip" "$FFMPEG_URL"
        unzip -o -q "$CACHE_DIR/ffmpeg.zip" -d "$CACHE_DIR"
        curl -# -L -o "$CACHE_DIR/ffprobe.zip" "$FFPROBE_URL"
        unzip -o -q "$CACHE_DIR/ffprobe.zip" -d "$CACHE_DIR"
        chmod +x "$CACHE_DIR/ffmpeg" "$CACHE_DIR/ffprobe"
        rm -f "$CACHE_DIR/ffmpeg.zip" "$CACHE_DIR/ffprobe.zip"

        echo ""
        echo "Done! Static ffmpeg installed at: $CACHE_DIR/ffmpeg"
        "$CACHE_DIR/ffmpeg" -version | head -1
        echo ""
        echo "The Vault will use this binary automatically when running from the Godot editor."
        ;;
    *)
        echo "This script currently supports macOS only."
        echo "On Windows, the build_windows.sh script handles ffmpeg bundling."
        exit 1
        ;;
esac
