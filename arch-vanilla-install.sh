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
INSTALL_MODE="clean" # New default value for installation mode

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

# Function to handle dual-boot partitioning
setup_dual_boot() {
    local disk=$1
    
    # Check if Windows is installed in UEFI mode
    if [ "$BOOT_MODE" = "UEFI" ]; then
        # Check for existing EFI partition
        local efi_part=$(fdisk -l "$disk" | grep "EFI System" | awk '{print $1}')
        if [ -z "$efi_part" ]; then
            error "No EFI partition found. Make sure Windows is installed in UEFI mode."
        fi
        
        log "Using existing EFI partition: $efi_part"
        
        # Create root partition in the free space
        log "Creating root partition in available space..."
        (
            echo n  # new partition
            echo    # default partition number
            echo    # default first sector
            echo    # default last sector (rest of disk)
            echo    # no need to remove signature
            echo w  # write changes
        ) | fdisk "$disk"
        
        # Get the number of the newly created root partition
        ROOT_PART=$(fdisk -l "$disk" | tail -n 1 | awk '{print $1}')
        EFI_PART="$efi_part"
    else
        error "Legacy BIOS dual-boot is not supported. Please install in UEFI mode."
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

# Mount partitions
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
if [ "$INSTALL_MODE" = "dual" ]; then
    mount --mkdir "$EFI_PART" /mnt/boot/efi
else
    mount "$EFI_PART" /mnt/boot
fi

# Rest of the installation script remains the same until bootloader configuration
# [Previous mirror configuration and base system installation code remains unchanged]

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

# [Previous system configuration code remains unchanged until bootloader installation]

# Install and configure bootloader
if [ -d /sys/firmware/efi/efivars ]; then
    pacman -S --noconfirm grub efibootmgr os-prober
    if [ "$INSTALL_MODE" = "dual" ]; then
        # Configure for dual boot
        mkdir -p /boot/efi
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
        # Enable os-prober
        echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
    else
        grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
    fi
else
    pacman -S --noconfirm grub
    grub-install --target=i386-pc /dev/nvme0n1
fi
grub-mkconfig -o /boot/grub/grub.cfg

# [Rest of the setup script remains unchanged]
EOF

# Make setup script executable
chmod +x /mnt/setup.sh

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
if [ "$WM_CHOICE" = "dwm" ]; then
    log "3. You'll need to build and install dwm, st, and slstatus from source"
fi
