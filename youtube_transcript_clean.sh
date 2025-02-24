#!/bin/bash
xclip -sel clip -o | sed -E 's/^[0-9]{2}:[0-9]{2}:[0-9]{2}[[:space:]]+//' | tr '\n' ' ' | xclip -sel clip -i
# Alternative version using awk (not used):
# xclip -sel clip -o | awk '{sub(/^[0-9]{2}:[0-9]{2}:[0-9]{2}[[:space:]]+/, ""); printf "%s ", $0} END {print ""}' | xclip -sel clip -i
