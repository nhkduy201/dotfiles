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
set -eo pipefail
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
shopt -s extdebug

# Install required tools early (suppress errors)
{ pacman -Sy --noconfirm curl openbsd-netcat &>/dev/null; } || true

# Log collection setup
LOGFILE="/var/log/arch-install-$(date +%s).log"
exec > >(tee -a "$LOGFILE")
exec 2> >(tee -a "$LOGFILE" >&2)

error_handler() {
    local exit_code=$?
    local line_no="${BASH_LINENO[1]}"
    local script_name=$(basename "${BASH_SOURCE[0]}")
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local last_command="${BASH_COMMAND:-unknown}"

    # Ensure safe variable access
    local disk_info="Disk: ${DISK:-unset}"
    local install_mode="Mode: ${INSTALL_MODE:-unset}"
    local mount_status=$(mount | grep '/mnt' || echo "No mounts")

    # Build error report with failsafes
    local log_content=$(cat <<EOF
=== ERROR REPORT ===
Timestamp: $timestamp
Script: $script_name
Line: ${line_no:-unknown}
Last Command: $last_command
Exit Code: $exit_code

=== SYSTEM INFO ===
Kernel: $(uname -r 2>/dev/null || echo "unknown")
Architecture: $(uname -m 2>/dev/null || echo "unknown")
Boot Mode: $([ -d "/sys/firmware/efi/efivars" ] && echo "UEFI" || echo "BIOS")
$install_mode
$disk_info

=== DISK STATUS ===
$(lsblk -f "${DISK:-/dev/null}" 2>/dev/null || echo "No disk information")
$(parted -s "${DISK:-/dev/null}" print 2>/dev/null || echo "No partition information")

=== MOUNT STATUS ===
$mount_status

=== NETWORK STATUS ===
$(ip -brief address 2>/dev/null || echo "No network info")

=== KERNEL LOGS ===
$(dmesg | tail -n20 2>/dev/null || echo "No dmesg output")

=== INSTALLATION LOGS ===
$(tail -n200 "$LOGFILE" 2>/dev/null || echo "No log file found")
EOF
)

    # Attempt uploads in new priority order
    local upload_results=()
    for service in termbin.com dpaste.org ix.io; do
        result=$(upload_log "$log_content" "$service" 2>&1 || true)
        if [[ "$result" == http* ]]; then
            upload_results+=("$service: $result")
            break  # Stop after first successful upload
        else
            upload_results+=("$service: $result")
        fi
    done

    # Display error context
    echo -e "\n${RED}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                 INSTALLATION FAILED               ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════╝${NC}"
    echo -e "${RED}ERROR: Line $line_no - ${last_command}${NC}"
    echo -e "${RED}Exit Code: $exit_code${NC}"
    
    # Show upload results
    echo -e "\n${RED}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                  UPLOAD ATTEMPTS                  ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════╝${NC}"
    for result in "${upload_results[@]}"; do
        if [[ "$result" == https://* ]]; then
            echo -e "${GREEN}✓ ${result%%:*}: ${result#*:}${NC}"
        else
            echo -e "${RED}✗ ${result}${NC}"
        fi
    done
    
    # Preserve local log
    echo -e "\n${RED}Local log preserved at: $LOGFILE${NC}"
    exit $exit_code
}

trap 'error_handler' ERR

upload_log() {
    local content="$1"
    local service="$2"
    local max_size=50000  # 50KB
    local timeout=10
    local url=""
    
    # Trim content to last 50KB without base64
    content=$(echo "$content" | tail -c $max_size)

    case $service in
    dpaste.org)
        { url=$(timeout $timeout curl -v -s -F "content=<-" \
            -F "format=url" \
            -F "lexer=text" \
            "https://dpaste.org/api/" <<< "$content" | tr -d '"'); } 2>&1
        ;;
    termbin.com)
        { url=$(timeout $timeout nc termbin.com 9999 <<< "$content" | tr -d '\0'); } 2>&1
        ;;
    ix.io)
        { url=$(timeout $timeout curl -v -s -F 'f:1=<-' ix.io <<< "$content"); } 2>&1
        ;;
    esac

    # Validate URL format
    if [[ "$url" =~ ^https?:// ]]; then
        echo "$url"
    else
        # Return full error output
        echo "FAILED: ${url:-No response}"
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
    
    # Get existing EFI partition
    existing_efi=$(blkid -t PARTLABEL="EFI system partition" -o device | head -1)
    [ -b "$existing_efi" ] || error_handler "No existing EFI partition found"
    BOOT_PART="$existing_efi"

    # Calculate free space using parted
    free_space=$(parted -s "$DISK" unit MiB print free | awk '/Free Space/ {print $1,$3}' | tail -1)
    [ -z "$free_space" ] && error_handler "No free space available"
    
    start=$(echo "$free_space" | cut -d' ' -f1 | tr -d 'MiB')
    end=$(echo "$free_space" | cut -d' ' -f2 | tr -d 'MiB')
    [ $((end - start)) -ge 10240 ] || error_handler "Minimum 10GB free space required"

    # Create partition
    if ! parted -s "$DISK" mkpart primary ext4 "${start}MiB" "${end}MiB"; then
        error_handler "Failed to create root partition"
    fi
    
    # Get new partition
    ROOT_PART=$(parted -s "$DISK" print | awk '/ext4/ {print $1}' | tail -1)
    ROOT_PART="${DISK}p${ROOT_PART}"
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
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           INSTALLATION SUCCESSFUL!              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo -e "Next steps:"
echo "1. Reboot: systemctl reboot"
echo "2. Remove installation media"
echo "3. Login with: $USERNAME / $PASSWORD"
echo "4. Change password using 'passwd'"
echo "5. Check Secure Boot status in BIOS if needed"
echo -e "Local installation log preserved at: $LOGFILE"
