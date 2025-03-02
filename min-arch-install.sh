#!/bin/bash -x
set -euo pipefail
IFS=$'\n\t'

# Configuration ---------------------------------------------------------------
readonly SCRIPT_NAME=$(basename "$0")
readonly LOG_FILE="/var/log/min-arch.log"
readonly DEFAULT_HOSTNAME="archlinux"
readonly DEFAULT_USER="kayd"
readonly DEFAULT_TZ="Asia/Ho_Chi_Minh"
readonly SWAP_RATIO=0.5
declare -A BROWSER_PACKAGES=(
    [edge]="microsoft-edge-stable-bin"
    [librewolf]="librewolf-bin"
)

# Initialize Variables
HOSTNAME="$DEFAULT_HOSTNAME"
USERNAME="$DEFAULT_USER"
TIMEZONE="$DEFAULT_TZ"
INSTALL_MODE="clean"
BROWSER="edge"
UEFI_MODE=0
DISK=""
PASSWORD=""

# Security Settings
declare -A SECURITY_PROFILES=(
    [relaxed]="NOPASSWD:ALL"
    [strict]="PASSWD:ALL"
)

# Package Lists
BASE_PACKAGES=(
    base linux linux-firmware networkmanager sudo grub efibootmgr 
    amd-ucode intel-ucode git base-devel fuse2 pipewire{,-pulse,-alsa,-jack} 
    wireplumber alsa-utils xorg{,-xinit} i3{-wm,status,blocks} dmenu picom feh 
    ibus gvim xclip mpv scrot slock python-pyusb brightnessctl jq wget openssh 
    xdg-utils tmux
)

# Functions --------------------------------------------------------------------
error_log() {
    local error_msg="$1"
    echo "Error: $error_msg Time: $(date) Disk info: $(fdisk -l "$DISK") $(lsblk -f "$DISK")" \
        "Last commands: $(tail -n 20 "$LOG_FILE")" | nc termbin.com 9999
}

log() {
    echo "[$(date '+%Y-%m-%d %T')] $*" | tee -a "$LOG_FILE"
}

trap_error() {
    error_log "Error on line $1"
    exit 1
}

trap 'trap_error $LINENO' ERR

detect_install_disk() {
    local is_vm=0 vm_hint="" ventoy_disk="" ventoy_parent=""
    
    # Detect virtual environment
    if grep -qi "vmware\|virtualbox\|qemu" /sys/class/dmi/id/sys_vendor 2>/dev/null; then
        is_vm=1
        vm_hint=$(grep -i "vmware\|virtualbox\|qemu" /sys/class/dmi/id/sys_vendor 2>/dev/null)
        log "Detected virtual environment: $vm_hint"
        
        for dev in /dev/sda /dev/vda; do
            [[ -b "$dev" ]] && { echo "$dev"; return 0; }
        done
    fi

    # Improved Ventoy detection with more robust output handling
    ventoy_disk=$(blkid -o device -t LABEL_FATBOOT=Ventoy 2>/dev/null || true)
    if [[ -n "${ventoy_disk}" ]]; then
        ventoy_parent=$(lsblk --nodeps -n -o pkname "${ventoy_disk}" 2>/dev/null)
        [[ -n "$ventoy_parent" ]] && ventoy_parent="/dev/${ventoy_parent}"
        log "Detected Ventoy at ${ventoy_disk}, parent: ${ventoy_parent:-none}"
    fi

    # Find suitable disks
    local available_disks=($(lsblk -dno NAME,TYPE,RM | awk '$2=="disk" && $3=="0" {print "/dev/"$1}'))
    for disk in "${available_disks[@]}"; do
        [[ "$disk" == "$ventoy_parent" ]] && continue
        if [[ "$disk" =~ ^/dev/nvme ]]; then
            echo "$disk"
            return 0
        fi
    done

    [[ -n "${available_disks[0]}" ]] && echo "${available_disks[0]}" || return 1
}

clean_existing_install() {
    local disk="$1"
    log "Checking for existing installations on $disk"
    
    if ((UEFI_MODE)) && mount | grep -q "/mnt/boot/efi"; then
        log "Cleaning existing EFI installation"
        [[ -d /mnt/boot/efi/EFI/GRUB ]] && rm -rf /mnt/boot/efi/EFI/GRUB
    fi

    [[ "$INSTALL_MODE" == "clean" ]] && return

    local linux_parts=($(lsblk -no NAME,FSTYPE "$disk" | awk '/ext4/ {print $1}'))
    for part in "${linux_parts[@]}"; do
        part="/dev/${part}"
        [[ "${part}" == "${BOOT_PART}" ]] && continue

        mkdir -p /tmp/arch_check
        if mount "$part" /tmp/arch_check 2>/dev/null; then
            if [[ -f /tmp/arch_check/etc/arch-release ]]; then
                log "Found Arch Linux on $part"
                read -rp "Remove existing installation on $part? (y/N) " a
                if [[ "$a" =~ [Yy] ]]; then
                    log "Formatting $part"
                    if ! umount "${part}" 2>/dev/null; then
                        error_log "Failed to unmount ${part}"
                    fi
                    mkfs.ext4 -F "$part"
                    ROOT_PART="$part"
                    return 0
                fi
            fi
            umount /tmp/arch_check
        fi
    done
    rmdir /tmp/arch_check 2>/dev/null || true
}

partition_disk() {
    local disk="$1"
    local FORMAT_BOOT=0  # Add this line
    log "Partitioning $disk in $INSTALL_MODE mode"
    
    if [[ "$INSTALL_MODE" == "clean" ]]; then
        if ((UEFI_MODE)); then
            parted -s "${disk}" mklabel gpt
            parted -s "${disk}" mkpart ESP fat32 1MiB 513MiB
            parted -s "${disk}" set 1 esp on
            parted -s "${disk}" mkpart root ext4 513MiB 100%
            BOOT_PART=$(get_partition_device "$disk" 1)
            ROOT_PART=$(get_partition_device "$disk" 2)
        else
            parted -s "${disk}" mklabel msdos
            parted -s "${disk}" mkpart primary ext4 1MiB 513MiB
            parted -s "${disk}" set 1 boot on
            parted -s "${disk}" mkpart primary ext4 513MiB 100%
            BOOT_PART=$(get_partition_device "$disk" 1)
            ROOT_PART=$(get_partition_device "$disk" 2)
        fi
    else
        if ((UEFI_MODE)); then
            BOOT_PART=$(blkid -o device -t LABEL_FATBOOT=Ventoy 2>/dev/null || true)
            [[ -n "$BOOT_PART" ]] && { log "Ventoy detected"; exit 1; }
            BOOT_PART=$(fdisk -l "$disk" | awk '/EFI System/ {print $1}' | head -1)
            
            if [[ -z "$BOOT_PART" ]]; then
                parted -s "${disk}" mkpart primary fat32 1MiB 513MiB
                parted -s "${disk}" set 1 esp on
                BOOT_PART=$(get_partition_device "$disk" 1)
                FORMAT_BOOT=1
            fi
        else
            BOOT_PART=$(fdisk -l "$disk" | awk '/Linux/ {print $1}' | head -1)
            [[ -z "$BOOT_PART" ]] && {
                parted -s "$disk" mkpart primary ext4 1MiB 513MiB
                parted -s "$disk" set 1 boot on
                BOOT_PART=$(get_partition_device "$disk" 1)
                FORMAT_BOOT=1
            }
        fi

        # Improved free space detection that handles decimal values
        FREE_SPACE=$(parted -s "$disk" unit MiB print free | awk '
            /Free Space/ {
                gsub("MiB","",$3)
                if (int($3) > max) max = int($3)
            } 
            END {print max}
        ')
        
        [[ -z "$FREE_SPACE" ]] && FREE_SPACE=0
        [[ $FREE_SPACE -ge 10240 ]] || { log "Need 10GB+ free space (only found ${FREE_SPACE}MiB)"; exit 1; }
        
        # Find last partition end point more reliably
        LAST_PART_END=$(parted -s "$disk" unit MiB print | awk '
            /^ [0-9]+ / {
                gsub("MiB","",$3)
                if (int($3) > end) end = int($3)
            } 
            END {print end}
        ')
        
        parted -s "$disk" mkpart primary ext4 "${LAST_PART_END}MiB" 100%
        local part_num=$(parted -s "$disk" print | awk '/^ [0-9]+ / {n=$1} END {print n}')
        ROOT_PART=$(get_partition_device "$disk" "$part_num")
    fi
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

configure_system() {
    # Initialize pacman keyring first
    pacman-key --init
    pacman-key --populate archlinux

    # Export DISK variable for error_log function
    arch-chroot /mnt /bin/bash <<EOF
    export DISK="$DISK"
    # Base configuration
    ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
    hwclock --systohc
    
    # Locale setup
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf
    
    # System config
    echo "$HOSTNAME" > /etc/hostname
    echo -e "127.0.0.1 localhost\\n::1 localhost\\n127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" > /etc/hosts
    
    # mkinitcpio configuration
    sed -i 's/^MODULES=(.*)/MODULES=(amdgpu)/' /etc/mkinitcpio.conf
    sed -i 's/^HOOKS=(.*)/HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)/' /etc/mkinitcpio.conf
    mkinitcpio -P
    
    # Users & Security
    echo "root:$PASSWORD" | chpasswd
    useradd -m -G wheel,video "$USERNAME"
    echo "$USERNAME:$PASSWORD" | chpasswd
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    
    # Swap
    local swap_size=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 2 ))
    fallocate -l ${swap_size}M /swapfile || { echo "Failed to create swapfile"; exit 1; }
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo "/swapfile none swap defaults 0 0" >> /etc/fstab
    
    # Bootloader
    if ((UEFI_MODE)); then
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
    else
        grub-install --target=i386-pc --boot-directory=/boot --recheck "$DISK"
        echo -e 'GRUB_TERMINAL_INPUT="console"\nGRUB_TERMINAL_OUTPUT="console"' >> /etc/default/grub
    fi
    [[ "$INSTALL_MODE" == "dual" ]] && echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
    sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=1/' /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg
    
    # Xorg configuration
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

    cat > /etc/sudoers.d/l5p-kbl <<'SUDO_EOF'
$USERNAME ALL=(ALL) NOPASSWD:/usr/bin/python /home/$USERNAME/l5p-kbl/l5p_kbl.py
SUDO_EOF
    chmod 440 /etc/sudoers.d/l5p-kbl

    # Add systemd-resolved configuration
    systemctl enable systemd-resolved NetworkManager
    ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    echo "[Resolve]
DNS=8.8.8.8 8.8.4.4
FallbackDNS=1.1.1.1 1.0.0.1
DNSOverTLS=yes
DNSSEC=yes" > /etc/systemd/resolved.conf

    # Add checksum verification for downloaded packages
    sed -i 's/^#CheckSpace/CheckSpace/;s/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf
EOF
}

setup_user_environment() {
    # Make heredoc marker usage consistent throughout the function
    arch-chroot /mnt sudo -u "$USERNAME" bash <<'SCRIPT_EOF'
    # AUR helper
    TEMP_DIR="$(mktemp -d)"
    cd "${TEMP_DIR}"
    if ! git clone https://aur.archlinux.org/paru-bin.git; then
        rm -rf "${TEMP_DIR}"
        exit 1
    fi
    cd paru-bin
    if ! makepkg -si --noconfirm --skipinteg; then
        rm -rf "${TEMP_DIR}"
        exit 1
    fi
    cd / 
    rm -rf "${TEMP_DIR}"
    
    # Git configuration
    git config --global diff.tool vim
    
    # Browser installation
    paru -S --noconfirm ibus-bamboo ${BROWSER_PACKAGES[$BROWSER]}
    
    # Custom software
    git clone https://github.com/imShara/l5p-kbl $HOME/l5p-kbl
    sed -i 's/PRODUCT = 0xC965/PRODUCT = 0xC975/' $HOME/l5p-kbl/l5p_kbl.py
    
    # Window manager config
    mkdir -p $HOME/.config/i3
    cp /etc/i3/config $HOME/.config/i3/config
    sed -i '
        1i set $mod Mod4
        1i workspace_layout tabbed
        s/Mod1/$mod/g
        s/$mod+h/$mod+Mod1+h/
        s/$mod+v/$mod+Mod1+v/
        s/exec i3-sensible-terminal/exec st/
        s/set $up l/set $up k/
        s/set $down k/set $down j/
        s/set $left j/set $left h/
        s/set $right semicolon/set $right l/' $HOME/.config/i3/config
    
    echo -e 'bindsym Mod1+Shift+l exec --no-startup-id slock
bindsym $mod+Shift+s exec --no-startup-id "scrot -s - | xclip -sel clip -t image/png"
bindsym $mod+q kill
bindsym XF86MonBrightnessUp exec --no-startup-id brightnessctl set +5%
bindsym XF86MonBrightnessDown exec --no-startup-id brightnessctl set 5%-' >> $HOME/.config/i3/config
    
    # Dotfiles with consistent heredoc markers
    cat > "$HOME/.xinitrc" <<'XINIT_EOF'
export GTK_IM_MODULE=ibus
export XMODIFIERS=@im=ibus
export QT_IM_MODULE=ibus
ibus-daemon -drx &
gsettings set org.freedesktop.ibus.general preload-engines "['xkb:us::eng', 'Bamboo']"
gsettings set org.freedesktop.ibus.general.hotkey triggers "['<Control><Shift>space']"
sudo python "$HOME/l5p-kbl/l5p_kbl.py" static a020f0
exec i3
XINIT_EOF

    cat > $HOME/.tmux.conf <<'TMUX_EOF'
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

    cat >> $HOME/.bashrc <<'BASHRC_EOF'
reverse_search_dmenu() {
    local r=$(HISTTIMEFORMAT= history | sed 's/^ *[0-9]* *//' | grep -F -- "$READLINE_LINE" | tac | awk '!a[$0]++' | dmenu -l 10 -p "History> ")
    [[ -n "$r" ]] && READLINE_LINE="$r" && READLINE_POINT=${#READLINE_LINE}
}
bind -x '"\C-r": reverse_search_dmenu'
export HISTCONTROL=ignoreboth
export EDITOR=vim
pgrep -xq "Xorg" || startx
[[ "$TERM_PROGRAM" != "vscode" ]] && [[ -z "$TMUX" ]] && { tmux attach || tmux; }
BASHRC_EOF

    # Install and configure ST terminal
    if ! paru -G st; then
        error_log "Failed to retrieve ST terminal PKGBUILD"
        exit 1
    fi
    cd st
    sed -E -i 's#^STCFLAGS[[:space:]]*=#STCFLAGS = -O3 -march=native#' config.mk
    sed -i 's/static Key key\[\]/static Key key[] = {\n\t{ ControlMask|ShiftMask, XK_c, clipcopy, {.i = 0} },\n\t{ ControlMask|ShiftMask, XK_v, clippaste, {.i = 0} },/g' config.def.h
    if ! makepkg -si --noconfirm --skipinteg; then
        error_log "Failed to install ST"
        exit 1
    fi
    cd ..
    
    # Add Git configuration
    cat > $HOME/.gitconfig <<'GITCFG_EOF'
[user]
    name = nhkduy201
[color]
    pager = no
[core]
    pager = vim --not-a-term -R -
[difftool "vim"]
    cmd = vim -d "$LOCAL" "$REMOTE"
[difftool]
    prompt = false
[diff]
    tool = vim
GITCFG_EOF

    # Enable pipewire services
    systemctl --user enable --now pipewire{,-pulse} wireplumber
    
    # Cleanup
    rm -rf /tmp/paru-bin
SCRIPT_EOF
}

# Main Execution Flow ----------------------------------------------------------
main() {
    # Initialization
    exec 1> >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)
    [[ -d /sys/firmware/efi/efivars ]] && UEFI_MODE=1
    DISK=$(detect_install_disk) || { log "No suitable disk found"; exit 1; }
    
    # Argument parsing
    while [[ $# -gt 0 ]]; do
        case $1 in
            -m|--mode) INSTALL_MODE="$2"; shift 2 ;;
            -d|--disk) DISK="$2"; shift 2 ;;
            -p|--password) PASSWORD="$2"; shift 2 ;;
            -b|--browser) BROWSER="$2"; shift 2 ;;
            *) echo "Usage: $0 [-d disk] [-m clean|dual] [-b edge|librewolf] -p password"; exit 1 ;;
        esac
    done
    
    # Validation
    [[ -n "$PASSWORD" ]] || { log "Password required"; exit 1; }
    [[ "$INSTALL_MODE" =~ ^(clean|dual)$ ]] || { log "Invalid install mode"; exit 1; }
    [[ "$BROWSER" =~ ^(edge|librewolf)$ ]] || { log "Invalid browser"; exit 1; }
    [[ "$EUID" -eq 0 ]] || { log "Must be run as root"; exit 1; }
    
    # Disk confirmation
    if [[ "$INSTALL_MODE" == "clean" ]]; then
        log "Installation disk: $(lsblk -o NAME,SIZE,MODEL,TRAN,ROTA "$DISK")"
        read -rp "ERASE $DISK? (y/N) " confirm
        [[ "$confirm" =~ [Yy] ]] || exit 1
    fi

    # Partitioning
    partition_disk "$DISK"
    clean_existing_install "$DISK"
    
    # Formatting
    if [[ "$INSTALL_MODE" == "clean" || "$FORMAT_BOOT" -eq 1 ]]; then
        if ((UEFI_MODE)); then
            mkfs.fat -F32 "$BOOT_PART"
        else
            mkfs.ext4 -F "$BOOT_PART"
        fi
    fi
    mkfs.ext4 -F "$ROOT_PART"
    
    # Mounting
    mount "$ROOT_PART" /mnt || { error_log "Failed to mount root partition"; exit 1; }
    if ((UEFI_MODE)); then
        mkdir -p /mnt/boot/efi
        mount "$BOOT_PART" /mnt/boot/efi || { error_log "Failed to mount EFI partition"; exit 1; }
    else
        mkdir -p /mnt/boot
        mount "$BOOT_PART" /mnt/boot || { error_log "Failed to mount boot partition"; exit 1; }
    fi

    # System installation
    sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf
    pacman -Sy --noconfirm archlinux-keyring
    pacstrap /mnt "${BASE_PACKAGES[@]}"
    genfstab -U /mnt >> /mnt/etc/fstab

    # Configuration
    configure_system
    setup_user_environment

    # Finalization with reboot confirmation
    if ((UEFI_MODE)); then
        umount -l /mnt/boot/efi || log "Warning: Failed to unmount EFI partition"
    fi
    umount -l -R /mnt || { log "Error: Failed to unmount /mnt"; exit 1; }
    log "Installation complete. Rebooting..."
reboot
}

# Execute
main "$@"