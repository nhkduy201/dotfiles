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
set -e
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Log collection setup
exec > >(tee -a /var/log/arch-install.log)
exec 2> >(tee -a /var/log/arch-install.log >&2)

error() {
    local error_msg="$1"
    local line_no="$LINENO"
    local script_name=$(basename "$0")
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "${RED}Error: $error_msg${NC}" >&2
    
    # Enhanced log collection
    local log_content="
=== Error Report ===
Timestamp: $timestamp
Script: $script_name
Error at line: $line_no
Last command: $(history | tail -n1 | sed 's/^[ ]*[0-9]\+[ ]*//')
Exit code: $?
Message: $error_msg

=== System Information ===
Kernel: $(uname -r)
Architecture: $(uname -m)
Boot Mode: $([ -d "/sys/firmware/efi/efivars" ] && echo "UEFI" || echo "BIOS")
Installation Mode: $INSTALL_MODE
Target Disk: $DISK
Mounted FS: $(mount | grep '/mnt' || echo "None")

=== Disk Information ===
--- lsblk output ---
$(lsblk -f "$DISK" 2>/dev/null || echo "Could not get lsblk info")

--- parted output ---
$(parted "$DISK" print 2>/dev/null || echo "Could not get parted info")

=== Network Status ===
$(ip a 2>/dev/null || echo "No network info")

=== Kernel Messages ===
$(dmesg | tail -n30 2>/dev/null || echo "No dmesg output")

=== Last 100 lines of script execution ---
$(tail -n100 /var/log/arch-install.log 2>/dev/null || echo "No log file found")
"

    # Try multiple paste services with fallback
    local url=""
    for service in dpaste.org termbin.com ix.io; do
        url=$(upload_log "$log_content" "$service")
        if [[ $url =~ ^https?:// ]]; then
            echo -e "${RED}Error log: $url${NC}" >&2
            echo -e "${RED}Please share this URL for support${NC}" >&2
            break
        fi
    done
    
    exit 1
}

upload_log() {
    local log_content="$1"
    local service="$2"
    local url=""
    local max_size=524288  # 512KB

    # Truncate if needed (keep beginning and end)
    if [ ${#log_content} -gt $max_size ]; then
        log_content="${log_content:0:$((max_size/2))}\n[...TRUNCATED...]\n${log_content: -$((max_size/2))}"
    fi

    case $service in
        dpaste.org)
            url=$(curl -s -F "content=<-" -F "hold=86400" https://dpaste.org/api/ <<< "$log_content" | awk '/^https:/ {print $1}')
            ;;
        termbin.com)
            url=$(nc termbin.com 9999 <<< "$log_content" | tr -d '\0')
            ;;
        ix.io)
            url=$(curl -s -F 'f:1=<-' ix.io <<< "$log_content")
            ;;
    esac

    # Validate URL format
    [[ "$url" =~ ^https?:// ]] && echo "$url" || echo ""
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
[ "$(id -u)" -eq 0 ] || error "This script must be run as root"

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
            error "Invalid option: $1"
            ;;
    esac
done

# Validate parameters
[[ "$INSTALL_MODE" =~ ^(clean|dual)$ ]] || error "Invalid mode: $INSTALL_MODE"
[[ -b "$DISK" ]] || error "Disk $DISK not found"
[[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]] || error "Invalid username: $USERNAME"
[[ -n "$PASSWORD" ]] || error "Password cannot be empty"

# UEFI verification
check_uefi() {
    [ -d "/sys/firmware/efi/efivars" ] || error "UEFI mode required"
}

# Partitioning functions
clean_partition() {
    echo -e "${GREEN}Creating clean partition scheme...${NC}"
    if ! parted -s "$DISK" mklabel gpt \
        mkpart primary fat32 1MiB $BOOT_SIZE \
        set 1 esp on \
        mkpart primary ext4 $BOOT_SIZE 100%; then
        error "Partitioning failed"
    fi
    BOOT_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
}

dual_partition() {
    echo -e "${GREEN}Detecting existing partitions...${NC}"
    existing_efi=$(fdisk -l "$DISK" | awk '/EFI System/ {print $1}' | head -1)
    [ -b "$existing_efi" ] || error "No existing EFI partition found"
    
    free_space=$(parted "$DISK" unit MiB print free | grep "Free Space" | tail -1)
    [ -z "$free_space" ] && error "No free space available"

    start=$(echo "$free_space" | awk '{print $1}' | tr -d 'MiB')
    end=$(echo "$free_space" | awk '{print $3}' | tr -d 'MiB')
    [ $((end - start)) -ge 10240 ] || error "Minimum 10GB free space required"

    if ! parted -s "$DISK" mkpart primary ext4 "${start}MiB" "${end}MiB"; then
        error "Failed to create root partition"
    fi
    
    ROOT_PART="${DISK}p$(parted -s "$DISK" print | awk '/ext4/ {print $1}' | tail -1)"
    BOOT_PART="$existing_efi"
}

# Secure Boot setup
setup_secure_boot() {
    arch-chroot /mnt bash <<EOF
    pacman -Sy --noconfirm sbctl || exit 1
    sbctl create-keys || exit 1
    sbctl enroll-keys --microsoft || exit 1
    sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI || exit 1
    sbctl sign -s /boot/EFI/arch/vmlinuz-linux || exit 1
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
mkfs.ext4 -F "$ROOT_PART" || error "Formatting failed"

# Mounting
echo -e "${GREEN}Mounting filesystems...${NC}"
mount "$ROOT_PART" /mnt || error "Failed to mount root"
mkdir -p /mnt/boot/efi
mount "$BOOT_PART" /mnt/boot/efi || error "Failed to mount EFI"

# Base system
echo -e "${GREEN}Installing base system...${NC}"
pacstrap /mnt base linux linux-firmware networkmanager sudo efibootmgr || error "Package install failed"

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab || error "fstab generation failed"

# Chroot setup
arch-chroot /mnt /bin/bash <<EOF || error "Chroot operations failed"
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
bootctl install || exit 1
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
echo -e "${GREEN}Installation successful!${NC}"
echo -e "Next steps:"
echo "1. Reboot: systemctl reboot"
echo "2. Remove installation media"
echo "3. Login with: $USERNAME / $PASSWORD"
echo "4. Change password using 'passwd'"
echo "5. Check Secure Boot status in BIOS if needed"
