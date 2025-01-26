#!/bin/bash

# Configuration defaults
DISK="/dev/nvme0n1"
HOSTNAME="archmin"
USERNAME="user"
PASSWORD="archpass123"
TIMEZONE="UTC"
INSTALL_MODE="clean"
BOOT_SIZE="512MiB"

# Error handling and colors
set -euo pipefail
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
trap 'error_handler "Script failed at line $LINENO"' ERR

# Install required tools early
pacman -Sy --noconfirm curl openbsd-netcat &>/dev/null || true

# Log collection setup
LOGFILE="/var/log/arch-install.log"
exec > >(tee -a "$LOGFILE")
exec 2> >(tee -a "$LOGFILE" >&2)

error_handler() {
    local error_msg="$1"
    local script_name=$(basename "$0")
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Initialize upload_url
    local upload_url=""
    
    # Capture error context
    local last_command=$(history 1 | sed 's/^[ ]*[0-9]\+[ ]*//')
    local exit_code=$?

    # Build comprehensive error report
    local log_content=$(cat <<EOF
=== ERROR REPORT ===
Timestamp: $timestamp
Script: $script_name
Last Command: $last_command
Exit Code: $exit_code
Message: $error_msg

=== SYSTEM INFO ===
Kernel: $(uname -r)
Architecture: $(uname -m)
Boot Mode: $([ -d "/sys/firmware/efi/efivars" ] && echo "UEFI" || echo "BIOS")
Install Mode: $INSTALL_MODE
Target Disk: $DISK

=== DISK STATUS ===
$(lsblk -f "$DISK" 2>/dev/null || echo "No disk information")
$(parted -s "$DISK" print 2>/dev/null || echo "No partition information")

=== MOUNT STATUS ===
$(mount | grep '/mnt' || echo "No mounts")

=== NETWORK STATUS ===
$(ip -brief address 2>/dev/null || echo "No network info")

=== KERNEL LOGS ===
$(dmesg | tail -n20 2>/dev/null || echo "No dmesg output")

=== INSTALLATION LOGS ===
$(tail -n200 "$LOGFILE" 2>/dev/null || echo "No log file found")
EOF
)

    # Attempt log upload with error capture
    local upload_errors=()
    local upload_url=""
    
    # Try services in order of reliability
    for service in termbin.com dpaste.org ix.io; do
        result=$(upload_log "$log_content" "$service")
        
        if [[ "$result" =~ ^https?:// ]]; then
            upload_url="$result"
            break
        elif [[ "$result" == SERVICE_FAILURE:* ]]; then
            IFS=':' read -ra parts <<< "$result"
            service_name="${parts[1]}"
            error_details="${parts[*]:2}"
            upload_errors+=("$service_name failed: $error_details")
        fi
    done

    # Display error message
    echo -e "\n${RED}ERROR: $error_msg${NC}" >&2
    if [ -n "$upload_url" ]; then
        echo -e "${GREEN}DEBUG LOG: $upload_url${NC}" >&2
    else
        echo -e "${RED}Log upload failed for all services:${NC}" >&2
        for err in "${upload_errors[@]}"; do
            echo -e "${RED} • $err${NC}" >&2
        done
        echo -e "${RED}Local log preserved at: $LOGFILE${NC}" >&2
        
        # Display last 20 lines of log for immediate debugging
        echo -e "\n${RED}Last 20 lines of log:${NC}"
        tail -n20 "$LOGFILE" | sed 's/^/  /'
    fi
    
    exit 1
}

upload_log() {
    local content="$1"
    local service="$2"
    local url=""
    local max_size=500000
    local err_file="/tmp/upload_error.log"

    # Truncate content
    content=$(echo "$content" | head -c $max_size)

    echo "Attempting upload to $service" > "$err_file"

    # Add HTTP-based fallbacks and timeouts
    case $service in
    dpaste.org)
        # Try both POST methods
        url=$(curl -v -s -F "content=<-" "https://dpaste.org/api/" <<< "$content" 2>> "$err_file" | tr -d '"')
        [ -z "$url" ] && url=$(curl -v -s --data-urlencode "content@-" "https://dpaste.org/api/" <<< "$content" 2>> "$err_file")
        ;;
    termbin.com)
        # Try both netcat and HTTP fallback
        url=$(timeout 10 nc -v -w 5 termbin.com 9999 <<< "$content" 2>> "$err_file" | tr -d '\0')
        [ -z "$url" ] && url=$(curl -v -s -F 'f:1=<-' https://termbin.com/ <<< "$content" 2>> "$err_file")
        ;;
    ix.io)
        # Alternative ix.io endpoint
        url=$(curl -v -s -F 'f:1=<-' https://ix.io/ <<< "$content" 2>> "$err_file")
        [ -z "$url" ] && url=$(curl -v -s --data-urlencode "f:1@-" https://ix.io/ <<< "$content" 2>> "$err_file")
        ;;
    esac

    # Capture service-specific error info
    local service_error=$(<"$err_file")
    rm -f "$err_file"

    # Additional validation for URL format
    if [[ "$url" =~ ^https?:// ]] && curl -s --head "$url" &>/dev/null; then
        echo "$url"
    else
        # Enhanced error reporting
        echo "SERVICE_FAILURE:$service:${service_error//$'\n'/ }"
    fi
}

show_help() {
    cat <<EOF
Usage: bash <(curl -sL https://raw.githubusercontent.com/yourusername/repo/main/arch-install.sh) [OPTIONS]

Required options:
  -m, --mode MODE      Installation mode (clean|dual)
  -u, --user USER      Username for regular account

Recommended:
  -s, --password PASS  Password for both accounts (default: $PASSWORD)

Optional:
  -d, --disk DISK      Target disk (default: $DISK)
  -n, --hostname NAME  System hostname (default: $HOSTNAME)
  -t, --timezone TZ    Timezone (default: $TIMEZONE)
  -h, --help           Show this help

Examples:
  Minimal:  bash <(curl -sL URL) -m dual -u myuser
  Full:     bash <(curl -sL URL) -m clean -d /dev/sda -n myarch -u admin -s 'S3cur3P@ss!'
EOF
    exit 0
}

# Check root
[ "$(id -u)" -eq 0 ] || error_handler "This script must be run as root"

# Parse command-line options
while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--mode)
            INSTALL_MODE="$2"
            shift 2
            ;;
        -d|--disk)
            DISK="$2"
            shift 2
            ;;
        -n|--hostname)
            HOSTNAME="$2"
            shift 2
            ;;
        -u|--user)
            USERNAME="$2"
            shift 2
            ;;
        -s|--password)
            PASSWORD="$2"
            shift 2
            ;;
        -t|--timezone)
            TIMEZONE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            error_handler "Invalid option: $1"
            ;;
    esac
done

# Validate parameters
[[ "$INSTALL_MODE" =~ ^(clean|dual)$ ]] || error_handler "Invalid mode: $INSTALL_MODE"
[[ -b "$DISK" ]] || error_handler "Disk $DISK not found"
[[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]] || error_handler "Invalid username: $USERNAME"
[[ -n "$PASSWORD" ]] || error_handler "Password cannot be empty"

# UEFI verification
check_uefi() {
    [ -d "/sys/firmware/efi/efivars" ] || error_handler "UEFI mode required"
}

# Partitioning functions
clean_partition() {
    echo -e "${GREEN}Creating clean partition scheme...${NC}"
    if ! parted -s "$DISK" mklabel gpt \
        mkpart primary fat32 1MiB $BOOT_SIZE \
        set 1 esp on \
        mkpart primary ext4 $BOOT_SIZE 100%; then
        error_handler "Partitioning failed"
    fi
    BOOT_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
}

dual_partition() {
    echo -e "${GREEN}Detecting existing partitions...${NC}"
    
    # Get disk size in MiB
    disk_size_mib=$(parted -s "$DISK" unit MiB print | awk '/^Disk/ {gsub("MiB","",$3); print $3}')
    
    # Find the end of the last partition (remove decimal for integer math)
    last_part_end=$(parted -s "$DISK" unit MiB print | awk '/^ [0-9]+/ {print $3}' | tail -n1 | cut -d'.' -f1)
    
    # Calculate available space
    free_space_mib=$((disk_size_mib - last_part_end))
    
    # Verify minimum 10GB (10240MiB)
    [ "$free_space_mib" -ge 10240 ] || error_handler "Need 10GB free space after last partition (found ${free_space_mib}MiB)"
    
    echo -e "${GREEN}Creating partition using all ${free_space_mib}MiB free space...${NC}"
    
    # Create partition using 100% of remaining space
    if ! parted -s "$DISK" mkpart primary ext4 "${last_part_end}MiB" "100%"; then
        error_handler "Failed to create root partition"
    fi
    
    # Get new partition path
    ROOT_PART=$(parted -s "$DISK" print | awk '/ext4/ {print $1}' | tail -n1)
    ROOT_PART="${DISK}p${ROOT_PART}"
    BOOT_PART="$existing_efi"
}
# Secure Boot setup
setup_secure_boot() {
    arch-chroot /mnt bash <<EOF || error_handler "Secure Boot setup failed"
    pacman -Sy --noconfirm sbctl
    sbctl create-keys
    sbctl enroll-keys --microsoft
    sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI
    sbctl sign -s /boot/EFI/arch/vmlinuz-linux
EOF
}

# Main installation
check_uefi

# Partitioning
if [ "$INSTALL_MODE" = "clean" ]; then
    clean_partition
else
    dual_partition
fi

# Formatting
echo -e "${GREEN}Formatting partitions...${NC}"
[ "$INSTALL_MODE" = "clean" ] && mkfs.fat -F32 "$BOOT_PART"
mkfs.ext4 -F "$ROOT_PART" || error_handler "Formatting failed"

# Mounting
echo -e "${GREEN}Mounting filesystems...${NC}"
mount "$ROOT_PART" /mnt || error_handler "Failed to mount root"
mkdir -p /mnt/boot/efi
mount "$BOOT_PART" /mnt/boot/efi || error_handler "Failed to mount EFI"

# Base system
echo -e "${GREEN}Installing base system...${NC}"
pacstrap /mnt base linux linux-firmware networkmanager sudo efibootmgr || error_handler "Package install failed"

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab || error_handler "fstab generation failed"

# Chroot setup
arch-chroot /mnt /bin/bash <<EOF || error_handler "Chroot operations failed"
# Basic setup
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname

# Users
echo "root:$PASSWORD" | chpasswd
useradd -m -G wheel "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Bootloader
bootctl install
cat <<LOADER > /boot/loader/entries/arch.conf
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
options root="$(blkid -s UUID -o value "$ROOT_PART")" rw
LOADER

# Secure Boot for dual install
[ "$INSTALL_MODE" = "dual" ] && setup_secure_boot

# Network
systemctl enable NetworkManager
EOF

# Cleanup
umount -R /mnt

# Final message
echo -e "${GREEN}Installation completed successfully!${NC}"
echo -e "Next steps:"
echo "1. Reboot: systemctl reboot"
echo "2. Remove installation media"
echo "3. Login with: $USERNAME / $PASSWORD"
echo "4. Change password using 'passwd'"
echo "5. Check Secure Boot status in BIOS if needed"
