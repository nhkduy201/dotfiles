#!/bin/bash

# Exit on any error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
HOSTNAME="archlinux"
TIMEZONE="Asia/Ho_Chi_Minh"

# Function to display usage
usage() {
    cat << EOF
Usage: $0 -u USERNAME -w WM_CHOICE -p PASSWORD [-h HOSTNAME] [-t TIMEZONE]

Required arguments:
    -u USERNAME      Username for the new system
    -w WM_CHOICE     Window manager choice (dwm or i3)
    -p PASSWORD      Password for both root and user

Optional arguments:
    -h HOSTNAME      Hostname for the new system (default: archlinux)
    -t TIMEZONE      Timezone (default: Asia/Ho_Chi_Minh)
    -? or --help     Display this help message

Example:
    $0 -u kayd -w dwm -p mypassword -h myarch -t Asia/Tokyo
EOF
    exit 1
}

# Function to log messages
log() {
    echo -e "${GREEN}$1${NC}"
}

# Function to handle errors
error() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# Parse command line arguments
while getopts ":u:w:p:h:t:?" opt; do
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
        \?|*)
            usage
            ;;
    esac
done

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

# Update system clock
timedatectl set-ntp true

# Disk partitioning for NVME drive
DISK="/dev/nvme0n1"
log "Partitioning disk $DISK..."

# Clear all partition tables
wipefs -a $DISK

if [ "$BOOT_MODE" = "UEFI" ]; then
    # Create GPT partition table
    parted -s $DISK mklabel gpt
    
    # Create EFI partition (512MB)
    parted -s $DISK mkpart primary fat32 1MiB 513MiB
    parted -s $DISK set 1 esp on
    
    # Create root partition (rest of disk)
    parted -s $DISK mkpart primary ext4 513MiB 100%
else
    # Create MBR partition table
    parted -s $DISK mklabel msdos
    
    # Create boot partition (512MB)
    parted -s $DISK mkpart primary ext4 1MiB 513MiB
    parted -s $DISK set 1 boot on
    
    # Create root partition (rest of disk)
    parted -s $DISK mkpart primary ext4 513MiB 100%
fi

# Format partitions
if [ "$BOOT_MODE" = "UEFI" ]; then
    mkfs.fat -F32 "${DISK}p1"
else
    mkfs.ext4 "${DISK}p1"
fi
mkfs.ext4 "${DISK}p2"

# Mount partitions
mount "${DISK}p2" /mnt
mkdir -p /mnt/boot
mount "${DISK}p1" /mnt/boot

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

# Install base system
log "Installing base system..."
pacstrap /mnt base base-devel linux linux-firmware git neovim

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Create configuration script
log "Creating configuration script..."
cat > /mnt/setup.sh << 'EOF'
#!/bin/bash
set -e

# Import variables from parent script
USERNAME="$1"
HOSTNAME="$2"
TIMEZONE="$3"
WM_CHOICE="$4"
PASSWORD="$5"

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
    pacman -S --noconfirm grub efibootmgr
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
    pacman -S --noconfirm grub
    grub-install --target=i386-pc /dev/nvme0n1
fi
grub-mkconfig -o /boot/grub/grub.cfg

# Install common packages
pacman -S --noconfirm \
    networkmanager network-manager-applet wireless_tools wpa_supplicant dialog \
    xorg xorg-xinit xorg-xinput \
    pipewire pipewire-alsa pipewire-pulse \
    firefox tmux dmenu xclip pavucontrol python-pip \
    ttf-font-awesome ttf-cascadia-code noto-fonts-emoji \
    slock dconf wget libx11 libxinerama libxft freetype2 \
    fuse openssh dnsmasq zip unrar torbrowser-launcher

# Install window manager specific packages
if [ "$WM_CHOICE" = "i3" ]; then
    pacman -S --noconfirm i3-wm i3status i3blocks i3lock
else
    # Install build dependencies for dwm
    pacman -S --noconfirm base-devel libx11 libxinerama libxft freetype2
fi

# Enable services
systemctl enable NetworkManager
systemctl enable systemd-resolved

# Configure initial window manager
if [ "$WM_CHOICE" = "i3" ]; then
    mkdir -p /home/$USERNAME/.config/i3
    echo "exec i3" > /home/$USERNAME/.xinitrc
else
    echo "exec dwm" > /home/$USERNAME/.xinitrc
fi

# Set correct ownership
chown -R $USERNAME:$USERNAME /home/$USERNAME

# Configure systemd-resolved
cat > /etc/systemd/resolved.conf << EODNS
[Resolve]
DNS=8.8.8.8 8.8.4.4 2001:4860:4860::8888 2001:4860:4860::8844
FallbackDNS=1.1.1.1 1.0.0.1 2606:4700:4700::1111 2606:4700:4700::1001
DNSOverTLS=yes
EODNS

EOF

# Make setup script executable
chmod +x /mnt/setup.sh

# Chroot and run setup
log "Running system configuration..."
arch-chroot /mnt ./setup.sh "$USERNAME" "$HOSTNAME" "$TIMEZONE" "$WM_CHOICE" "$PASSWORD"

# Clean up
rm /mnt/setup.sh

# Unmount
log "Unmounting filesystems..."
umount -R /mnt

log "Installation complete! You can now reboot."
log "After reboot:"
log "1. Log in as $USERNAME"
log "2. Run 'startx' to start the graphical environment"
if [ "$WM_CHOICE" = "dwm" ]; then
    log "3. You'll need to build and install dwm, st, and slstatus from source"
fi
