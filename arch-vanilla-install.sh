#!/bin/bash

# Exit on any error
set -e
trap 'error "An error occurred at line $LINENO. Exiting..."' ERR

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Install required packages for logging
pacman -Sy --noconfirm curl netcat

# Default values
HOSTNAME="archlinux"
TIMEZONE="Asia/Ho_Chi_Minh"
INSTALL_MODE="clean" # New default value for installation mode

# Function to display log messages
log() {
    echo -e "${GREEN}$1${NC}"
}

# Function to upload logs to termbin
upload_log() {
    local log_content="$1"
    local upload_url="https://termbin.com"
    
    # Try to upload to termbin
    local url=$(echo "$log_content" | nc termbin.com 9999)
    if [[ $url =~ ^https?:// ]]; then
        echo "Log uploaded to: $url"
        return 0
    fi
    
    # Fallback to ix.io if termbin fails
    url=$(echo "$log_content" | curl -F 'f:1=<-' ix.io)
    if [[ $url =~ ^https?:// ]]; then
        echo "Log uploaded to: $url"
        return 0
    fi
    
    return 1
}

# Enhanced error handling with log upload
error() {
    local error_msg="$1"
    local line_no="$LINENO"
    local script_name=$(basename "$0")
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "${RED}Error: $error_msg${NC}" >&2
    
    # Only try to upload if curl and netcat are available
    if command -v curl >/dev/null 2>&1 && command -v nc >/dev/null 2>&1; then
        # Get disk information
        local disk_info=$(fdisk -l "$DISK" 2>/dev/null || echo "Could not get disk info")
        local parted_info=$(parted "$DISK" print 2>/dev/null || echo "Could not get parted info")
        local lsblk_info=$(lsblk -f "$DISK" 2>/dev/null || echo "Could not get lsblk info")
        
        local log_content="
=== Error Report ===
Timestamp: $timestamp
Script: $script_name
Error at line: $line_no
Message: $error_msg

=== System Information ===
Kernel: $(uname -r)
Architecture: $(uname -m)
Boot Mode: $BOOT_MODE
Installation Mode: $INSTALL_MODE
Target Disk: $DISK

=== Disk Information ===
--- fdisk output ---
$disk_info

--- parted output ---
$parted_info

--- lsblk output ---
$lsblk_info

=== Last 50 lines of script execution ===
$(tail -n 50 /var/log/arch-install.log 2>/dev/null || echo "No log file found")
"
        local url=$(upload_log "$log_content")
        if [ $? -eq 0 ]; then
            echo -e "${RED}Error details have been uploaded to: $url${NC}" >&2
        fi
    fi
    
    exit 1
}

# Start logging
exec 1> >(tee -a /var/log/arch-install.log)
exec 2> >(tee -a /var/log/arch-install.log >&2)

# Function to display usage
usage() {
    cat << EOF
Usage: $0 -u USERNAME -w WM_CHOICE -p PASSWORD [-h HOSTNAME] [-t TIMEZONE] [-m MODE] [-d DISK]

Required arguments:
    -u USERNAME      Username for the new system
    -w WM_CHOICE     Window manager choice (dwm or i3)
    -p PASSWORD      Password for both root and user

Optional arguments:
    -h HOSTNAME      Hostname for the new system (default: archlinux)
    -t TIMEZONE      Timezone (default: Asia/Ho_Chi_Minh)
    -m MODE          Installation mode (clean or dual) (default: clean)
    -d DISK          Target disk (default: /dev/nvme0n1)
    -? or --help     Display this help message

Example:
    $0 -u kayd -w dwm -p mypassword -h myarch -t Asia/Tokyo -m dual -d /dev/sda
EOF
    exit 1
}

# Function to install AUR helper and packages
install_aur_packages() {
    local aur_helper=""
    if ! command -v paru &>/dev/null; then
        sudo -u $USERNAME git clone https://aur.archlinux.org/paru.git
        (cd paru && sudo -u $USERNAME makepkg -s --noconfirm --needed && pacman -U --noconfirm *.pkg.tar.zst)
        if ! command -v paru &>/dev/null; then
            log "Paru installation failed. Falling back to yay."
            sudo -u $USERNAME git clone https://aur.archlinux.org/yay.git
            (cd yay && sudo -u $USERNAME makepkg -s --noconfirm --needed && pacman -U --noconfirm *.pkg.tar.zst)
            aur_helper="yay"
        else
            aur_helper="paru"
        fi
    else
        aur_helper="paru"
    fi

    local common_aur_packages=(
        microsoft-edge-stable-bin
        ibus-bamboo
        linux-wifi-hotspot
        nm-vpngate-git
        lf
        ripgrep
    )

    local i3_aur_packages=(i3-gaps)

    if [ "$WM_CHOICE" = "dwm" ]; then
        aur_packages=("${common_aur_packages[@]}")
    else
        aur_packages=("${common_aur_packages[@]}" "${i3_aur_packages[@]}")
    fi

    sudo -u $USERNAME $aur_helper -S --noconfirm --needed "${aur_packages[@]}"
}

# Function to install gaming-related packages
install_gaming_packages() {
    local gaming_packages=(
        nvidia-dkms nvidia-utils lib32-nvidia-utils nvidia-settings
        vulkan-icd-loader lib32-vulkan-icd-loader
        lib32-mesa vulkan-radeon lib32-vulkan-radeon
        wine-staging giflib lib32-giflib libpng lib32-libpng
        libldap lib32-libldap gnutls lib32-gnutls
        libpulse lib32-libpulse alsa-plugins lib32-alsa-plugins
        lutris steam mpg123 lib32-mpg123 openal lib32-openal
    )
    pacman -S --noconfirm --needed "${gaming_packages[@]}"
}

# Function to install suckless software
install_suckless_software() {
    local softwares=("dwm" "st" "slstatus-git")
    for sw in "${softwares[@]}"; do
        if [[ ! -d $sw ]]; then
            sudo -u $USERNAME paru -G "${sw}"
        fi
        cp "${sw}-config.h" "${sw}/config.h"
        insert_sed_command_before_make "${sw}"
        cd "${sw}"
        sudo -u $USERNAME makepkg -si --noconfirm
        cd ..
    done
}

insert_sed_command_before_make() {
    local sw="$1"
    local build_line_number=$(grep -n '^build() {' "${sw}/PKGBUILD" | cut -d: -f1)
    if [[ -z "$build_line_number" ]]; then
        return 1
    fi
    local make_line_number=$(tail -n +"$((build_line_number+1))" "${sw}/PKGBUILD" | grep -n '^ *make' | head -n 1 | cut -d: -f1)
    if [[ -z "$make_line_number" ]]; then
        return 1
    fi
    local insert_line_number=$(( make_line_number + build_line_number ))
    sed_command=""
    if [[ $sw == "dwm" ]]; then
        sed_command="sed -E -i 's#^CFLAGS\\s*=#CFLAGS = -O3 -march=native#' \$(find . -name config.mk)"
    elif [[ $sw == "st" ]]; then
        sed_command="sed -E -i 's#^STCFLAGS\\s*=#STCFLAGS = -O3 -march=native#' \$(find . -name config.mk)"
    elif [[ $sw == "slstatus-git" ]]; then
        sed_command="sed -E -i 's#^CFLAGS\\s*=#CFLAGS = -O3 -march=native#' \$(find . -name config.mk)"
    fi
    sed_command="${sed_command} && sed -E -i 's#-Os##g' \$(find . -name config.mk)"
    sed -i "${insert_line_number}i\  ${sed_command}" "${sw}/PKGBUILD"
}

# Function to setup touchpad
setup_touchpad() {
    cat > /etc/X11/xorg.conf.d/30-touchpad.conf << EOF
Section "InputClass"
    Identifier "touchpad"
    Driver "libinput"
    MatchIsTouchpad "on"
    Option "Tapping" "on"
    Option "TappingButtonMap" "lrm"
    Option "NaturalScrolling" "true"
    Option "ScrollMethod" "twofinger"
EndSection
EOF
}

# Function to configure git
setup_git() {
    sudo -u $USERNAME git config --global user.email "nhkduy201@gmail.com"
    sudo -u $USERNAME git config --global user.name "nhkduy201"
    sudo -u $USERNAME git config --global core.editor "nvim"
}

# Function to download softwares
download_softwares() {
    local PROTONUP_VERSION="2.9.1"
    sudo -u $USERNAME bash -c "
        mkdir -p ~/Downloads
        cd ~/Downloads
        wget -q https://github.com/DavidoTek/ProtonUp-Qt/releases/download/v${PROTONUP_VERSION}/ProtonUp-Qt-${PROTONUP_VERSION}-x86_64.AppImage
        curl -OJLs https://downloader.cursor.sh/linux/appImage/x64
        wget --content-disposition -O discord.tar.gz \"https://discord.com/api/download?platform=linux&format=tar.gz\"
        tar xzf discord.tar.gz
        mkdir -p ~/.local/bin
        chmod u+x cursor-*x86_64.AppImage ProtonUp-Qt-${PROTONUP_VERSION}-x86_64.AppImage
        ln -sf ~/Downloads/Discord/Discord ~/.local/bin/discord
        ln -sf ~/Downloads/ProtonUp-Qt-${PROTONUP_VERSION}-x86_64.AppImage ~/.local/bin/protonup-qt
    "
    ln -sf /home/$USERNAME/Downloads/cursor-*x86_64.AppImage /usr/local/bin/cursor
}

# Add after download_softwares function
keyboard_backlight() {
    arch-chroot /mnt bash -c "
        cd /home/$USERNAME
        sudo -u $USERNAME git clone https://github.com/imShara/l5p-kbl
        cd l5p-kbl
        sed -i 's/PRODUCT = 0xC965/PRODUCT = 0xC975/' l5p_kbl.py
    "
}

# Parse command line arguments
while getopts ":u:w:p:h:t:m:d:?" opt; do
    case $opt in
        u)
            USERNAME="$OPTARG"
            ;;
        w)
            WM_CHOICE="$OPTARG"
            if [[ "$WM_CHOICE" != "dwm" && "$WM_CHOICE" != "i3" ]]; then
                error "Window manager must be either 'dwm' or 'i3'"
            fi
            ;;
        p)
            PASSWORD="$OPTARG"
            ;;
        h)
            HOSTNAME="$OPTARG"
            ;;
        t)
            TIMEZONE="$OPTARG"
            ;;
        m)
            INSTALL_MODE="$OPTARG"
            if [[ "$INSTALL_MODE" != "clean" && "$INSTALL_MODE" != "dual" ]]; then
                error "Installation mode must be either 'clean' or 'dual'"
            fi
            ;;
        d)
            DISK="$OPTARG"
            ;;
        \?|*)
            usage
            ;;
    esac
done

# Set default disk if not specified
DISK=${DISK:-"/dev/nvme0n1"}

# Check required arguments
if [ -z "$USERNAME" ] || [ -z "$WM_CHOICE" ] || [ -z "$PASSWORD" ]; then
    error "Missing required arguments"
    usage
fi

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
fi

# Verify boot mode
if [ -d "/sys/firmware/efi/efivars" ]; then
    BOOT_MODE="UEFI"
else
    BOOT_MODE="BIOS"
fi

log "Starting Arch Linux installation in $BOOT_MODE mode..."
log "Installation parameters:"
log "  Username: $USERNAME"
log "  Hostname: $HOSTNAME"
log "  Window Manager: $WM_CHOICE"
log "  Timezone: $TIMEZONE"
log "  Installation Mode: $INSTALL_MODE"
log "  Target Disk: $DISK"

# Update system clock
timedatectl set-ntp true

# Function to detect existing OS installations
detect_existing_os() {
    local disk=$1
    local efi_part=""
    
    # Look for EFI partition
    efi_part=$(fdisk -l "$disk" | grep "EFI System" | awk '{print $1}')
    
    if [ -z "$efi_part" ]; then
        error "No EFI partition found. Existing OS must be installed in UEFI mode."
    fi
    
    # Mount EFI partition temporarily to check its contents
    local tmp_mount="/tmp/efi_check"
    mkdir -p "$tmp_mount"
    if mount "$efi_part" "$tmp_mount"; then
        # Check for Windows boot manager
        if [ -d "$tmp_mount/EFI/Microsoft" ]; then
            log "Detected Windows installation"
        fi
        umount "$tmp_mount"
    fi
    rm -r "$tmp_mount"
    
    # Return only the partition path
    echo "$efi_part"
}

# Function to find largest free space on disk
find_free_space() {
    local disk=$1
    local start_sector=0
    local size_sectors=0
    local largest_start=0
    local largest_size=0
    
    while read -r line; do
        if [[ $line =~ "Free Space" ]]; then
            local curr_start=$(echo "$line" | awk '{print $1}' | tr -d 's')
            local curr_size=$(echo "$line" | awk '{print $3}' | tr -d 's')
            if [ "$curr_size" -gt "$largest_size" ]; then
                largest_start=$curr_start
                largest_size=$curr_size
            fi
        fi
    done < <(parted "$disk" unit s print free)
    
    echo "$largest_start $largest_size"
}

# Function to setup dual-boot
setup_dual_boot() {
    local disk=$1
    
    if [ "$BOOT_MODE" = "UEFI" ]; then
        # Detect existing OS and EFI partition
        EFI_PART=$(detect_existing_os "$disk" | tail -n1)  # Get last line only
        log "Using existing EFI partition: $EFI_PART"
        
        # Check for existing Linux partition
        ROOT_PART=$(fdisk -l "$disk" | grep "Linux filesystem" | tail -n 1 | awk '{print $1}')
        
        if [ -n "$ROOT_PART" ]; then
            log "Using existing Linux partition: $ROOT_PART"
            # Verify partition size
            local size_bytes=$(blockdev --getsize64 "$ROOT_PART")
            local size_gb=$((size_bytes / 1024 / 1024 / 1024))
            
            if [ "$size_gb" -lt 10 ]; then
                error "Linux partition too small (minimum 10GB required)"
            fi
        else
            error "No Linux partition found"
        fi
        
        # Debug output
        log "Debug: EFI_PART=$EFI_PART"
        log "Debug: ROOT_PART=$ROOT_PART"
        
        # Verify both partitions exist and are accessible
        if [ ! -e "$EFI_PART" ] || [ ! -b "$EFI_PART" ]; then
            error "EFI partition not found or not accessible: $EFI_PART"
        fi
        
        if [ ! -e "$ROOT_PART" ] || [ ! -b "$ROOT_PART" ]; then
            error "Root partition not found or not accessible: $ROOT_PART"
        fi
        
        # Verify EFI partition is properly formatted
        if ! blkid "$EFI_PART" | grep -q "vfat"; then
            error "EFI partition is not formatted as vfat: $EFI_PART"
        fi
        
        log "Verified partitions:"
        log "  EFI: $EFI_PART"
        log "  Root: $ROOT_PART"
    else
        error "Legacy BIOS dual-boot is not supported. Please install in UEFI mode."
    fi
}

# Enhanced mount function
mount_partitions() {
    log "Mounting root partition: $ROOT_PART"
    if ! mount "$ROOT_PART" /mnt; then
        error "Failed to mount root partition"
    fi

    if [ "$INSTALL_MODE" = "dual" ]; then
        log "Mounting EFI partition: $EFI_PART"
        mkdir -p /mnt/boot/efi
        if ! mount "$EFI_PART" /mnt/boot/efi; then
            umount /mnt
            error "Failed to mount EFI partition"
        fi
    else
        log "Mounting boot partition: $EFI_PART"
        mkdir -p /mnt/boot
        if ! mount "$EFI_PART" /mnt/boot; then
            umount /mnt
            error "Failed to mount boot partition"
        fi
    fi
}

# Function to handle clean installation partitioning
setup_clean_install() {
    local disk=$1
    
    # Clear all partition tables
    wipefs -a "$disk"
    
    if [ "$BOOT_MODE" = "UEFI" ]; then
        # Create GPT partition table and partitions
        (
            echo g    # create GPT partition table
            echo n    # new partition
            echo 1    # partition number
            echo     # default first sector
            echo +512M # 512MB for EFI
            echo t    # change partition type
            echo 1    # EFI System
            echo n    # new partition
            echo 2    # partition number
            echo     # default first sector
            echo     # default last sector (rest of disk)
            echo w    # write changes
        ) | fdisk "$disk"
        
        # Set partition variables based on disk type
        if [[ "$disk" == *"nvme"* ]]; then
            EFI_PART="${disk}p1"
            ROOT_PART="${disk}p2"
        else
            EFI_PART="${disk}1"
            ROOT_PART="${disk}2"
        fi
    else
        # Create MBR partition table and partitions
        (
            echo o    # create MBR partition table
            echo n    # new partition
            echo p    # primary partition
            echo 1    # partition number
            echo     # default first sector
            echo +512M # 512MB for boot
            echo a    # make bootable
            echo n    # new partition
            echo p    # primary partition
            echo 2    # partition number
            echo     # default first sector
            echo     # default last sector
            echo w    # write changes
        ) | fdisk "$disk"
        
        if [[ "$disk" == *"nvme"* ]]; then
            EFI_PART="${disk}p1"
            ROOT_PART="${disk}p2"
        else
            EFI_PART="${disk}1"
            ROOT_PART="${disk}2"
        fi
    fi
}

# Partition the disk based on installation mode
log "Partitioning disk $DISK..."
if [ "$INSTALL_MODE" = "dual" ]; then
    setup_dual_boot "$DISK"
else
    setup_clean_install "$DISK"
fi

# Format partitions
if [ "$BOOT_MODE" = "UEFI" ]; then
    if [ "$INSTALL_MODE" = "clean" ]; then
        mkfs.fat -F32 "$EFI_PART"
    fi
else
    mkfs.ext4 "$EFI_PART"
fi
mkfs.ext4 "$ROOT_PART"

# Use the enhanced mount function
mount_partitions

# Setup mirrorlist for Asian countries
log "Configuring mirrors..."
cat > /etc/pacman.d/mirrorlist << EOF
## Singapore
Server = https://mirror.jingk.ai/archlinux/\$repo/os/\$arch
Server = https://mirror.aktkn.sg/archlinux/\$repo/os/\$arch

## Japan
Server = https://mirrors.cat.net/archlinux/\$repo/os/\$arch
Server = https://ftp.jaist.ac.jp/pub/Linux/ArchLinux/\$repo/os/\$arch

## South Korea
Server = https://mirror.funami.tech/arch/\$repo/os/\$arch
Server = https://ftp.lanet.kr/pub/archlinux/\$repo/os/\$arch

## Hong Kong
Server = https://mirror.xtom.com.hk/archlinux/\$repo/os/\$arch
EOF

# Enable parallel downloads
sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 5/' /etc/pacman.conf

# Enable multilib repository
sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf

# Update package database
pacman -Sy

# After mounting partitions and before pacstrap, add these lines:
log "Configuring network and DNS..."
# Configure systemd-resolved with Google DNS
cat > /etc/systemd/resolved.conf << EOF
[Resolve]
DNS=8.8.8.8 8.8.4.4
FallbackDNS=1.1.1.1 1.0.0.1
DNSOverTLS=yes
DNSSEC=yes
EOF

# Restart systemd-resolved and update DNS configuration
systemctl restart systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# Initialize and update keyring
log "Updating keyring..."
pacman-key --init
pacman-key --populate archlinux
pacman -Sy --noconfirm archlinux-keyring

# Update package database
log "Updating package database..."
pacman -Syy

# After DNS configuration and before pacstrap, add these lines:
log "Updating mirrorlist..."
# Backup original mirrorlist
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup

# Install pacman-contrib for rankmirrors
pacman -Sy --noconfirm pacman-contrib || error "Failed to install pacman-contrib"

# Use curl to fetch the latest mirrorlist, prioritizing Asian mirrors
if ! curl -s "https://archlinux.org/mirrorlist/?country=VN&country=SG&country=JP&country=KR&country=TW&country=HK&protocol=https&use_mirror_status=on" | \
    sed -e 's/^#Server/Server/' -e '/^#/d' | \
    rankmirrors -n 5 - > /etc/pacman.d/mirrorlist; then
    error "Failed to update mirrorlist"
fi

# Initialize keyring and update package database
log "Updating keyring..."
pacman-key --init || error "Failed to initialize pacman-key"
pacman-key --populate archlinux || error "Failed to populate keyring"
pacman -Sy --noconfirm archlinux-keyring || error "Failed to update archlinux-keyring"

# Update package database
log "Updating package database..."
pacman -Syy || error "Failed to update package database"

# Define ultra-minimal base packages
MINIMAL_PACKAGES="base linux linux-firmware \
    networkmanager \
    grub efibootmgr"  # efibootmgr only needed for UEFI

# Define base-devel and additional packages for full installation
FULL_PACKAGES="base-devel git gvim \
    network-manager-applet wireless_tools dialog \
    xorg xorg-xinit xorg-xinput \
    pipewire pipewire-alsa pipewire-pulse \
    firefox tmux dmenu xclip pavucontrol python-pip \
    ttf-font-awesome ttf-cascadia-code noto-fonts-emoji \
    slock dconf wget libx11 libxinerama libxft freetype2 \
    fuse openssh dnsmasq zip unrar torbrowser-launcher \
    mpv yt-dlp gdb scrot sqlite sbctl os-prober"

# Modify the pacstrap section
log "Installing base system..."
max_retries=3
retry_count=0
success=false

while [ $retry_count -lt $max_retries ]; do
    if [ "$INSTALL_TYPE" = "minimal" ]; then
        # Ultra-minimal installation
        if pacstrap /mnt $MINIMAL_PACKAGES; then
            success=true
            break
        fi
    else
        # Full installation
        if pacstrap /mnt $MINIMAL_PACKAGES $FULL_PACKAGES \
            $([ "$WM_CHOICE" = "i3" ] && echo "i3-wm i3status i3blocks i3lock"); then
            success=true
            break
        fi
    fi
    
    retry_count=$((retry_count + 1))
    log "Package installation failed. Retry $retry_count of $max_retries..."
    sleep 5
    pacman -Syy || log "Warning: Failed to refresh package databases before retry"
done

if [ "$success" != "true" ]; then
    error "Failed to install packages after $max_retries attempts"
fi

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Configure secure boot if in UEFI mode (move this section after chroot setup)
if [ "$BOOT_MODE" = "UEFI" ]; then
    if [ -d /sys/firmware/efi/efivars ]; then
        # Install and configure secure boot inside chroot
        arch-chroot /mnt bash -c "
            # Install sbctl
            pacman -Sy --noconfirm sbctl || exit 1
            
            # Configure secure boot
            sbctl create-keys
            sbctl enroll-keys -m
            
            # Sign all required files
            sbctl sign -s /boot/vmlinuz-linux
            sbctl sign -s /boot/efi/EFI/GRUB/grubx64.efi
            sbctl verify
        "
    fi
fi

# Create configuration script
log "Creating configuration script..."

# Modify the bootloader installation in setup.sh
cat > /mnt/setup.sh << 'EOF'
#!/bin/bash
set -e

# Import variables from parent script
USERNAME="$1"
HOSTNAME="$2"
TIMEZONE="$3"
WM_CHOICE="$4"
PASSWORD="$5"
INSTALL_MODE="$6"

# Basic system configuration
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf
echo "$HOSTNAME" > /etc/hostname

# Configure hosts
cat > /etc/hosts << EOHOST
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOHOST

# Set root password
echo "root:$PASSWORD" | chpasswd

# Create user
useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd

# Configure sudo
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

# Install and configure bootloader
if [ -d /sys/firmware/efi/efivars ]; then
    if [ "$INSTALL_MODE" = "dual" ]; then
        mkdir -p /boot/efi
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
        echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
    else
        grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
    fi
else
    pacman -S --noconfirm grub
    grub-install --target=i386-pc /dev/nvme0n1
fi
grub-mkconfig -o /boot/grub/grub.cfg

# Enable essential services
systemctl enable NetworkManager
EOF
else
    # Use existing full setup script
    # ... (keep your existing setup script for full installation)
fi

# Make setup script executable
chmod +x /mnt/setup.sh

# Setup additional configurations
log "Setting up additional configurations..."
arch-chroot /mnt bash -c "$(cat << 'CHROOT'
    # Define all functions first
    setup_touchpad() {
        mkdir -p /etc/X11/xorg.conf.d/
        cat > /etc/X11/xorg.conf.d/30-touchpad.conf << EOF
Section "InputClass"
    Identifier "touchpad"
    Driver "libinput"
    MatchIsTouchpad "on"
    Option "Tapping" "on"
    Option "TappingButtonMap" "lrm"
    Option "NaturalScrolling" "true"
    Option "ScrollMethod" "twofinger"
EndSection
EOF
    }

    setup_git() {
        pacman -S --noconfirm git
    }

    install_gaming_packages() {
        pacman -S --noconfirm steam lutris wine-staging gamemode lib32-gamemode
    }

    install_aur_packages() {
        # Install yay
        cd /tmp
        git clone https://aur.archlinux.org/yay.git
        cd yay
        makepkg -si --noconfirm
    }

    download_softwares() {
        pacman -S --noconfirm discord telegram-desktop
    }

    keyboard_backlight() {
        # Add user to video group for backlight control
        usermod -aG video $USERNAME
    }

    install_suckless_software() {
        cd /tmp
        git clone https://git.suckless.org/dwm
        git clone https://git.suckless.org/st
        git clone https://git.suckless.org/dmenu
        
        cd dwm && make clean install
        cd ../st && make clean install
        cd ../dmenu && make clean install
    }

    # Now execute the functions
    setup_touchpad
    setup_git
    install_gaming_packages
    install_aur_packages
    download_softwares
    keyboard_backlight
    if [ "$WM_CHOICE" = "dwm" ]; then
        install_suckless_software
    fi

    # Configure GRUB
    mkdir -p /boot/grub
    grub-mkconfig -o /boot/grub/grub.cfg
CHROOT
)"

# Change GRUB timeout
arch-chroot /mnt bash -c "
    sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=1/' /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg
"

# Configure systemd-resolved
arch-chroot /mnt bash -c "
    systemctl enable systemd-resolved --now
    ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    cat > /etc/systemd/resolved.conf << EOF
DNS=8.8.8.8 8.8.4.4 2001:4860:4860::8888 2001:4860:4860::8844
FallbackDNS=1.1.1.1 1.0.0.1 2606:4700:4700::1111 2606:4700:4700::1001
DNSOverTLS=yes
EOF
    systemctl restart systemd-resolved
"

# Disable telemetry
cat >> /mnt/etc/hosts << EOF
## For an-anime-game-launcher-bin
0.0.0.0 sg-public-data-api.hoyoverse.com
0.0.0.0 log-upload-os.hoyoverse.com
0.0.0.0 log-upload-os.mihoyo.com
0.0.0.0 overseauspider.yuanshen.com
0.0.0.0 public-data-api.mihoyo.com
0.0.0.0 log-upload.mihoyo.com
EOF

# Chroot and run setup
log "Running system configuration..."
arch-chroot /mnt ./setup.sh "$USERNAME" "$HOSTNAME" "$TIMEZONE" "$WM_CHOICE" "$PASSWORD" "$INSTALL_MODE"

# Clean up
rm /mnt/setup.sh

# Unmount
log "Unmounting filesystems..."
umount -R /mnt

log "Installation complete! You can now reboot."
log "After reboot:"
log "1. Log in as $USERNAME"
log "2. Run 'startx' to start the graphical environment"
