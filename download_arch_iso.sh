#!/bin/bash
# Arch Linux ISO Downloader with Singapore/Vietnam Priority

VERSION_PAGE="https://archlinux.org/download/"
CHECKSUM_FILE="sha256sums.txt"
LOG_FILE="archlinux_download.log"
PRIORITY_DOMAINS=(
    "0x.sg" "aktkn.sg" "download.nus.edu.sg" "sg.gs"  # Singapore
    "huongnguyen.dev" "nguyenhoang.cloud"             # Vietnam
)
MAX_RETRIES=3
CURL_OPTS=(--user-agent "ArchLinux-Downloader/1.0" -Lf)

# Logging setup
exec > >(tee -a "$LOG_FILE") 2>&1

# Extract latest version
LATEST_VERSION=$(curl -s "$VERSION_PAGE" | grep -oP 'Current Release:</strong>\s*\K\d{4}\.\d{2}\.\d{2}')
if [ -z "$LATEST_VERSION" ]; then
    echo "Failed to detect version. Exiting." >&2
    exit 1
fi

# Process mirrors with priority
process_mirrors() {
    curl -s "$VERSION_PAGE" | awk '
    /<h5>/{country=substr($0, index($0,">")+1); gsub(/<\/h5>|^ */, "", country)}
    /<li>/{if (country) print country "|" $0}
    ' | while IFS='|' read -r country line; do
        echo "$line" | grep -oP 'https?://[^"]+/archlinux/iso/\d+\.\d+\.\d+/' | while read -r url; do
            domain=$(echo "$url" | awk -F/ '{print $3}')
            for i in "${!PRIORITY_DOMAINS[@]}"; do
                if [[ "$domain" == *"${PRIORITY_DOMAINS[$i]}"* ]]; then
                    echo "$i $url"
                    break
                fi
            done
        done
    done | sort -n | cut -d' ' -f2- | uniq
}

MIRRORS=$(process_mirrors)
if [ -z "$MIRRORS" ]; then
    echo "No mirrors found. Exiting." >&2
    exit 1
fi

# Disk space check (2GB)
REQUIRED_SPACE=2000000000
AVAILABLE_SPACE=$(df -B1 . | awk 'NR==2 {print $4}')
if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
    echo "Insufficient space. Need 2GB." >&2
    exit 1
fi

download_and_verify() {
    local mirror=$1
    local iso_name="archlinux-${LATEST_VERSION}-x86_64.iso"
    
    ISO_URL="${mirror}${iso_name}"
    CHECKSUM_URL="${mirror}${CHECKSUM_FILE}"
    
    # Check ISO availability
    if ! curl -m 10 -sIf "$ISO_URL" &>/dev/null; then
        return 1
    fi
    
    echo "Downloading: $ISO_URL"
    if curl "${CURL_OPTS[@]}" -# -o "$iso_name" "$ISO_URL" && \
       curl "${CURL_OPTS[@]}" -s -o "$CHECKSUM_FILE" "$CHECKSUM_URL" && \
       sha256sum --check "$CHECKSUM_FILE" --ignore-missing &>/dev/null; then
        rm -f "$CHECKSUM_FILE"
        echo "Success! ISO saved as $iso_name"
        exit 0
    else
        rm -f "$iso_name" "$CHECKSUM_FILE"
        return 1
    fi
}

# Attempt downloads with retries
for mirror in $MIRRORS; do
    retry=0
    while [ $retry -lt $MAX_RETRIES ]; do
        if download_and_verify "$mirror"; then
            exit 0
        fi
        retry=$((retry + 1))
        echo "Retry $retry/$MAX_RETRIES for $mirror"
    done
done

echo "All mirrors failed. Exiting." >&2
exit 1