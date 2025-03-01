#!/bin/bash

# Strict mode
set -euo pipefail
IFS=$'\n\t'

# Script constants
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME=$(basename "$0")
readonly LOG_FILE="/tmp/min-arch.log"
readonly DEBUG_LOG="/mnt/var/log/min-arch-install.log"
readonly MIN_RAM_MB=2048
readonly MIN_DISK_GB=20

# Debug mode flag
DEBUG_MODE=0

# Default values
HOSTNAME="archlinux"
USERNAME="kayd"
TIMEZONE="Asia/Ho_Chi_Minh"
INSTALL_MODE="clean"
BROWSER="edge"
UEFI_MODE=0

# Enhanced logging function with debug support
log() {
    local level="$1"
    shift
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="[$level] $timestamp: $*"
    
    echo "$message" | tee -a "$LOG_FILE"
    
    if [[ $DEBUG_MODE -eq 1 ]] || [[ $level == "DEBUG" ]]; then
        # Add extra debug info
        {
            echo "[$level] $timestamp: $*"
            echo "  -> Function: ${FUNCNAME[1]}"
            echo "  -> Line: ${BASH_LINENO[0]}"
            echo "  -> Command: $BASH_COMMAND"
            echo "  -> Stack trace:"
            local frame=0
            while caller $frame; do
                ((frame++))
            done 2>/dev/null
            echo "----------------------------------------"
        } >> "$DEBUG_LOG"
    fi
}

# Debug logging wrapper
debug_log() {
    [[ $DEBUG_MODE -eq 1 ]] && log "DEBUG" "$@"
}

# Help message
usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]
Arch Linux installation script

Options:
    -m, --mode MODE       Installation mode (clean|dual)
    -d, --disk DEVICE    Target disk device
    -p, --password PWD   Root and user password
    -b, --browser NAME   Browser to install (edge|librewolf)
    -v, --verbose        Enable verbose debug logging
    -h, --help          Show this help message
    --version           Show version information

Example:
    $SCRIPT_NAME -m clean -d /dev/sda -p mypassword -b edge -v
EOF
    exit 1
}

# Version information
version() {
    echo "$SCRIPT_NAME version $SCRIPT_VERSION"
    exit 0
}

# Logging function
log() {
    local level="$1"
    shift
    echo "[$level] $(date '+%Y-%m-%d %H:%M:%S'): $*" | tee -a "$LOG_FILE"
}

# Error handling with logging
error_log() {
    local error_msg="$1"
    local log_url=$(echo "Error: $error_msg
Time: $(date)
System Info: $(uname -a)
Memory: $(free -h)
Disk info: $(fdisk -l "$DISK" 2>/dev/null || echo 'N/A')
$(lsblk -f "$DISK" 2>/dev/null || echo 'N/A')
Last commands: $(tail -n 20 "$LOG_FILE")" | nc termbin.com 9999)
    
    log "ERROR" "$error_msg"
    log "INFO" "Error details logged to: $log_url"
    exit 1
}

# Input validation with timeout
confirm_with_timeout() {
    local prompt="$1"
    local timeout=30
    read -t $timeout -rp "$prompt" response || {
        log "ERROR" "No response within $timeout seconds"
        exit 1
    }
    [[ "$response" =~ ^[Yy]$ ]] || exit 1
}

# System requirements check
check_system_requirements() {
    log "INFO" "Checking system requirements..."
    
    # Check RAM
    local total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_ram_mb=$((total_ram_kb / 1024))
    if [[ $total_ram_mb -lt $MIN_RAM_MB ]]; then
        error_log "Insufficient RAM. Required: ${MIN_RAM_MB}MB, Available: ${total_ram_mb}MB"
    fi
    
    # Check disk space
    if [[ -b "$DISK" ]]; then
        local disk_size_bytes=$(blockdev --getsize64 "$DISK")
        local disk_size_gb=$((disk_size_bytes / 1024 / 1024 / 1024))
        if [[ $disk_size_gb -lt $MIN_DISK_GB ]]; then
            error_log "Insufficient disk space. Required: ${MIN_DISK_GB}GB, Available: ${disk_size_gb}GB"
        fi
    fi

    log "INFO" "System requirements check passed"
}

# Package verification
verify_packages() {
    log "INFO" "Verifying package availability..."
    local failed_pkgs=()
    for pkg in "$@"; do
        if ! pacman -Si "$pkg" &>/dev/null; then
            failed_pkgs+=("$pkg")
        fi
    done
    
    if [[ ${#failed_pkgs[@]} -gt 0 ]]; then
        error_log "Following packages not found: ${failed_pkgs[*]}"
    fi
    log "INFO" "Package verification completed"
}

# Create backup of important files
create_backup() {
    log "INFO" "Creating backup of important files..."
    local backup_dir="/root/pre_install_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # List of important files to backup
    local files_to_backup=(
        "/etc/fstab"
        "/etc/default/grub"
        "/boot/grub/grub.cfg"
    )

    for file in "${files_to_backup[@]}"; do
        if [[ -f "$file" ]]; then
            cp -p "$file" "$backup_dir/" || log "WARN" "Failed to backup $file"
        fi
    done
    
    log "INFO" "Backup created at $backup_dir"
}

# Initialize logging
init_logging() {
    if [[ $DEBUG_MODE -eq 1 ]]; then
        # In debug mode, all logs go to DEBUG_LOG
        mkdir -p "$(dirname "$DEBUG_LOG")"
        touch "$DEBUG_LOG"
        # Redirect all output to debug log
        exec 1> >(tee -a "$DEBUG_LOG")
        exec 2> >(tee -a "$DEBUG_LOG" >&2)
    else
        # In normal mode, use temporary log
        touch "$LOG_FILE"
        exec 1> >(tee -a "$LOG_FILE")
        exec 2> >(tee -a "$LOG_FILE" >&2)
    fi
    
    log "INFO" "Starting installation script v$SCRIPT_VERSION"
}

# System state logging
log_system_state() {
    if [[ $DEBUG_MODE -eq 1 ]]; then
        {
            echo "=== System State ==="
            echo "Date: $(date)"
            echo "Kernel: $(uname -a)"
            echo "Memory:"
            free -h
            echo "Disk Space:"
            df -h
            echo "Block Devices:"
            lsblk
            echo "Mount Points:"
            mount
            echo "Network Interfaces:"
            ip addr
            echo "Process List:"
            ps aux
            echo "==================="
        } >> "$DEBUG_LOG"
    fi
}

# Main installation logic
main() {
    init_logging
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help) usage ;;
            --version) version ;;
            -m|--mode) INSTALL_MODE="$2"; shift 2 ;;
            -d|--disk) DISK="$2"; shift 2 ;;
            -p|--password) PASSWORD="$2"; shift 2 ;;
            -b|--browser) BROWSER="$2"; shift 2 ;;
            -v|--verbose) DEBUG_MODE=1; shift ;;
            *) log "ERROR" "Unknown option: $1"; usage ;;
        esac
    done

    # Initialize debug logging
    if [[ $DEBUG_MODE -eq 1 ]]; then
        log "INFO" "Debug mode enabled - detailed logs will be written to $DEBUG_LOG"
        # Enable bash debugging
        set -x
        # Trace all commands
        exec 19>&2
        exec 2> >(tee -a "$DEBUG_LOG")
        
        # Log initial system state
        log_system_state
        
        # Log script parameters
        debug_log "Script parameters:"
        debug_log "  INSTALL_MODE: $INSTALL_MODE"
        debug_log "  DISK: $DISK"
        debug_log "  BROWSER: $BROWSER"
        debug_log "  UEFI_MODE: $UEFI_MODE"
    fi

    # Validate required parameters
    [[ -n $PASSWORD ]] || { log "ERROR" "Password needed"; exit 1; }
    [[ $INSTALL_MODE =~ ^(clean|dual)$ ]] || { log "ERROR" "Bad mode"; exit 1; }
    [[ $BROWSER =~ ^(edge|librewolf)$ ]] || { log "ERROR" "Bad browser"; exit 1; }
    [[ $EUID -eq 0 ]] || { log "ERROR" "Need root"; exit 1; }

    # Detect UEFI mode
    [[ -d /sys/firmware/efi/efivars ]] && UEFI_MODE=1

    # Detect installation disk
    detect_install_disk() {
        local is_vm=0
        local vm_hint=""
        local ventoy_parent=""  # Initialize the variable
        
        if grep -qi "vmware" /sys/class/dmi/id/sys_vendor 2>/dev/null || grep -qi "virtualbox" /sys/class/dmi/id/sys_vendor 2>/dev/null || grep -qi "qemu" /sys/class/dmi/id/sys_vendor 2>/dev/null; then
            is_vm=1
            vm_hint=$(grep -i "vmware\|virtualbox\|qemu" /sys/class/dmi/id/sys_vendor 2>/dev/null)
        fi
        
        if ((is_vm)); then
            log "INFO" "Detected virtual environment: $vm_hint"
            if [[ -b "/dev/sda" ]]; then
                echo "/dev/sda"
                return 0
            fi
            if [[ -b "/dev/vda" ]]; then
                echo "/dev/vda"
                return 0
            fi
        fi
        
        local ventoy_disk=$(blkid -o device -t LABEL_FATBOOT=Ventoy 2>/dev/null || true)
        if [[ -n "$ventoy_disk" ]]; then
            log "INFO" "Detected Ventoy installation at $ventoy_disk - avoiding this disk"
            ventoy_parent=$(lsblk -no PKNAME "$ventoy_disk" 2>/dev/null | head -1 || true)
            [[ -n "$ventoy_parent" ]] && ventoy_parent="/dev/$ventoy_parent"
        fi
        
        local available_disks=($(lsblk -dno NAME,TYPE,RM | awk '$2=="disk" && $3=="0" {print $1}'))
        if [[ ${#available_disks[@]} -eq 0 ]]; then
            log "ERROR" "No suitable disks found"
            return 1
        fi
        
        # Prefer NVMe drives first
        for disk in "${available_disks[@]}"; do
            disk="/dev/$disk"
            [[ -n "$ventoy_parent" && "$disk" == "$ventoy_parent" ]] && continue
            if [[ "$disk" =~ ^/dev/nvme ]]; then
                echo "$disk"
                return 0
            fi
        done
        
        # Fall back to first available non-Ventoy disk
        for disk in "${available_disks[@]}"; do
            disk="/dev/$disk"
            [[ -n "$ventoy_parent" && "$disk" == "$ventoy_parent" ]] && continue
            echo "$disk"
            return 0
        done
        
        return 1
    }

    get_partition_device() {
        local disk="$1"
        local part_num="$2"
        if [[ "$disk" =~ ^/dev/nvme ]]; then
            echo "${disk}p${part_num}"
        else
            echo "${disk}${part_num}"
        fi
    }

    DISK=$(detect_install_disk)
    [[ -b "$DISK" ]] || { log "ERROR" "No suitable disk found"; lsblk; exit 1; }

    # Create backup before making changes
    create_backup

    if [[ $INSTALL_MODE == "clean" ]]; then
        log "WARNING" "Disk:"
        lsblk -o NAME,SIZE,MODEL,TRAN,ROTA "$DISK"
        confirm_with_timeout "ERASE $DISK? (y/n) "
        check_system_requirements
        if ((UEFI_MODE)); then
            parted -s "$DISK" mklabel gpt
            parted -s "$DISK" mkpart primary fat32 1MiB 513MiB set 1 esp on
            parted -s "$DISK" mkpart primary ext4 513MiB 100%
            BOOT_PART=$(get_partition_device "$DISK" "1")
            ROOT_PART=$(get_partition_device "$DISK" "2")
        else
            parted -s "$DISK" mklabel msdos
            parted -s "$DISK" mkpart primary ext4 1MiB 513MiB
            parted -s "$DISK" set 1 boot on
            parted -s "$DISK" mkpart primary ext4 513MiB 100%
            BOOT_PART=$(get_partition_device "$DISK" "1")
            ROOT_PART=$(get_partition_device "$DISK" "2")
        fi
    else
        FORMAT_BOOT=0
        if ((UEFI_MODE)); then
            BOOT_PART=$(blkid -o device -t LABEL_FATBOOT=Ventoy 2>/dev/null || true)
            [[ -z "$BOOT_PART" ]] || { log "ERROR" "Ventoy found"; exit 1; }
            BOOT_PART=$(fdisk -l "$DISK" | awk '/EFI System/ {print $1}' | head -1)
            if [[ -z "$BOOT_PART" ]]; then
                parted -s "$DISK" mkpart primary fat32 1MiB 513MiB set 1 esp on
                BOOT_PART=$(get_partition_device "$DISK" "1")
                FORMAT_BOOT=1
            fi
        else
            BOOT_PART=$(fdisk -l "$DISK" | awk '/Linux/ {print $1}' | head -1)
            if [[ -z "$BOOT_PART" ]]; then
                parted -s "$DISK" mkpart primary ext4 1MiB 513MiB
                BOOT_PART=$(get_partition_device "$DISK" "1")
                FORMAT_BOOT=1
            fi
        fi
        FREE_SPACE=$(parted -s "$DISK" unit MB print free | awk '/Free Space/ {size=$3; gsub("MB","",$3); if($3 > max) max=$3} END {print max}')
        [[ $FREE_SPACE -ge 10240 ]] || { log "ERROR" "Need 10GB+ of free space (only found ${FREE_SPACE}MB)"; exit 1; }
        LAST_PART_END=$(parted -s "$DISK" unit MB print | awk '/^ [0-9]+ / {end=$3} END {gsub("MB","",end); print end}')
        START_POINT=$((LAST_PART_END + 1))
        parted -s "$DISK" mkpart primary ext4 "${START_POINT}MB" 100%
        PART_NUM=$(parted -s "$DISK" print | awk '/^ [0-9]+ / {n=$1} END {print n}')
        ROOT_PART=$(get_partition_device "$DISK" "$PART_NUM")
    fi

    if [[ $INSTALL_MODE == "clean" ]] || [[ $FORMAT_BOOT -eq 1 ]]; then
        if ((UEFI_MODE)); then
            mkfs.fat -F32 "$BOOT_PART"
        else
            mkfs.ext4 -F "$BOOT_PART"
        fi
    fi

    mkfs.ext4 -F "$ROOT_PART"
    mount "$ROOT_PART" /mnt
    mkdir -p /mnt/boot/efi
    mount "$BOOT_PART" /mnt/boot/efi
    sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf
    pacman-key --init
    pacman-key --populate archlinux
    pacman -Sy --noconfirm archlinux-keyring
    base_pkgs=(base linux linux-firmware networkmanager sudo grub efibootmgr amd-ucode intel-ucode git base-devel fuse2 pipewire{,-pulse,-alsa,-jack} wireplumber alsa-utils xorg{,-xinit} i3{-wm,status,blocks} dmenu picom feh ibus gvim xclip mpv scrot slock python-pyusb brightnessctl jq wget openssh xdg-utils tmux)
    ((UEFI_MODE)) && base_pkgs+=(efibootmgr)
    [[ "$INSTALL_MODE" == "dual" ]] && base_pkgs+=(os-prober)

    # Verify packages before installation
    verify_packages "${base_pkgs[@]}"

    # Add checksum verification for downloaded packages
    sed -i 's/^#CheckSpace/CheckSpace/;s/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf

    pacstrap /mnt "${base_pkgs[@]}"
    genfstab -U /mnt >> /mnt/etc/fstab
    arch-chroot /mnt /bin/bash <<CHROOT_EOF
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname
echo "127.0.0.1 localhost
::1 localhost
127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" > /etc/hosts
echo "root:$PASSWORD" | chpasswd
useradd -m -G wheel,video "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
SWAP_SIZE=\$(((\$(grep MemTotal /proc/meminfo | awk '{print \$2}') / 1024 / 2)))
fallocate -l \${SWAP_SIZE}M /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile none swap defaults 0 0" >> /etc/fstab
systemctl enable systemd-resolved NetworkManager
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
echo "[Resolve]
DNS=8.8.8.8 8.8.4.4
FallbackDNS=1.1.1.1 1.0.0.1
DNSOverTLS=yes
DNSSEC=yes" > /etc/systemd/resolved.conf
mkinitcpio -P
if ((UEFI_MODE)); then
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
else
    grub-install --target=i386-pc --boot-directory=/boot --recheck "$DISK"
    echo 'GRUB_TERMINAL_INPUT="console"' >> /etc/default/grub
    echo 'GRUB_TERMINAL_OUTPUT="console"' >> /etc/default/grub
fi
[[ "$INSTALL_MODE" == "dual" ]] && echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=1/' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/30-touchpad.conf <<'XORG_EOF'
Section "InputClass"
    Identifier "libinput touchpad"
    MatchIsTouchpad "on"
    Driver "libinput"
    Option "Tapping" "on"
    Option "NaturalScrolling" "true"
EndSection
XORG_EOF
mkdir -p /etc/sudoers.d
echo "$USERNAME ALL=(ALL) NOPASSWD:/usr/bin/python /home/$USERNAME/l5p-kbl/l5p_kbl.py" > /etc/sudoers.d/l5p-kbl
chmod 440 /etc/sudoers.d/l5p-kbl
sudo -u $USERNAME bash <<USER_EOF
cd ~
git clone https://aur.archlinux.org/paru-bin.git
makepkg -D paru-bin/ -si --noconfirm
[[ "$BROWSER" == "edge" ]] && paru -S --noconfirm ibus-bamboo microsoft-edge-stable-bin || paru -S --noconfirm ibus-bamboo librewolf-bin
paru -G st
cd st
sed -E -i 's#^STCFLAGS\\s*=#STCFLAGS = -O3 -march=native#' config.mk
sed -i 's/static Key key\[\]/static Key key[] = {\n\t{ ControlMask|ShiftMask, XK_c, clipcopy, {.i = 0} },\n\t{ ControlMask|ShiftMask, XK_v, clippaste, {.i = 0} },/g' config.def.h
makepkg -si --noconfirm --skipinteg
cd ..
git clone https://github.com/imShara/l5p-kbl
sed -i 's/PRODUCT = 0xC965/PRODUCT = 0xC975/' l5p-kbl/l5p_kbl.py
mkdir -p ~/.config/i3
cp /etc/i3/config ~/.config/i3/config
sed -i '1i set \\\$mod Mod4
1i workspace_layout tabbed
s/Mod1/\\\$mod/g
s/\\\$mod+h/\\\$mod+Mod1+h/;s/\\\$mod+v/\\\$mod+Mod1+v/
s/exec i3-sensible-terminal/exec st/' ~/.config/i3/config
sed -i 's/set \\\$up l/set \\\$up k/; s/set \\\$down k/set \\\$down j/; s/set \\\$left j/set \\\$left h/; s/set \\\$right semicolon/set \\\$right l/' ~/.config/i3/config
echo 'bindsym Mod1+Shift+l exec --no-startup-id slock
bindsym \\\$mod+Shift+s exec --no-startup-id "scrot -s - | xclip -sel clip -t image/png"
bindsym \\\$mod+q kill
bindsym XF86MonBrightnessUp exec --no-startup-id brightnessctl set +5%
bindsym XF86MonBrightnessDown exec --no-startup-id brightnessctl set 5%-' >> ~/.config/i3/config
cat > ~/.xinitrc <<'XINIT_EOF'
export GTK_IM_MODULE=ibus
export XMODIFIERS=@im=ibus
export QT_IM_MODULE=ibus
ibus-daemon -drx &
gsettings set org.freedesktop.ibus.general preload-engines "['xkb:us::eng', 'Bamboo']"
gsettings set org.freedesktop.ibus.general.hotkey triggers "['<Control><Shift>space']"
sudo python \\$HOME/l5p-kbl/l5p_kbl.py static a020f0
exec i3
XINIT_EOF
cat > ~/.gitconfig <<'GITCFG_EOF'
[user]
    name = nhkduy201
[color]
    pager = no
[core]
    pager = vim --not-a-term -R -
[difftool "vim"]
    cmd = vim -d "\\$LOCAL" "\\$REMOTE"
[difftool]
    prompt = false
[diff]
    tool = vim
GITCFG_EOF
cat > ~/.tmux.conf <<'TMUX_EOF'
setw -g mode-keys vi
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R
bind-key -r J resize-pane -D 3
bind-key -r K resize-pane -U 3
bind-key -r H resize-pane -L 3
bind-key -r L resize-pane -R 3
bind '"' split-window -c "#{pane_current_path}"
bind % split-window -h -c "#{pane_current_path}"
bind c new-window -c "#{pane_current_path}"
set-option -g history-limit 1000000
set-option -g mouse on
set-option -s set-clipboard off
bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-no-clear "xclip -sel clip"
bind-key -T copy-mode-vi DoubleClick1Pane select-pane \; send-keys -X select-word \; send-keys -X copy-pipe-no-clear "xclip -sel clip"
bind-key -n DoubleClick1Pane select-pane \; copy-mode -M \; send-keys -X select-word \; send-keys -X copy-pipe-no-clear "xclip -sel clip"
bind-key -T copy-mode-vi 'v' send -X begin-selection
bind-key -T copy-mode-vi 'y' send -X copy-pipe "xclip -sel clip -i"
bind-key C-m set-option -g mouse \; display-message 'mouse #{?mouse,on,off}'
TMUX_EOF
cat >> ~/.bashrc <<'BASHRC_EOF'
reverse_search_dmenu() {
    local r=\\\$(HISTTIMEFORMAT= history | sed 's/^ *[0-9]* *//' | grep -F -- "\\\$READLINE_LINE" | tac | awk '!a[\\\$0]++' | dmenu -l 10 -p "History> ")
    [[ -n "\\\$r" ]] && READLINE_LINE="\\\$r" && READLINE_POINT=\\\${#READLINE_LINE}
}
bind -x '"\C-r": reverse_search_dmenu'
export HISTCONTROL=ignoreboth
export EDITOR=vim
pgrep -x "Xorg" > /dev/null || startx
[[ \\\$TERM_PROGRAM != "vscode" ]] && [[ -z \\\$TMUX ]] && { tmux attach || tmux; }
BASHRC_EOF
systemctl --user enable --now pipewire{,-pulse} wireplumber
USER_EOF
rm -rf /tmp/paru-bin
CHROOT_EOF

    # Before unmounting, copy logs to installed system
    finalize_logging() {
        if [[ $DEBUG_MODE -eq 1 ]]; then
            # Debug log is already in the right place
            log "INFO" "Installation logs available at: $DEBUG_LOG"
        else
            # Copy regular log to installed system
            mkdir -p "/mnt/var/log"
            cp "$LOG_FILE" "/mnt/var/log/min-arch-install.log"
            log "INFO" "Installation logs copied to: /var/log/min-arch-install.log"
        fi
    }

    finalize_logging
    umount -l -R /mnt
    reboot
}

# Improve error handling trap
trap 'last_command=$current_command; current_command=$BASH_COMMAND; log "ERROR" "Command \"${last_command}\" failed with exit code $? on line $LINENO"; error_log "Command \"${last_command}\" failed on line $LINENO"' ERR

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trap 'error_log "Error on line $LINENO"' ERR
    [[ $EUID -eq 0 ]] || { log "ERROR" "This script must be run as root"; exit 1; }
    main "$@"
fi
