#!/bin/bash -x

# Enable error handling
set -eo pipefail

# Error handling function
trap 'error_log "Error on line $LINENO"' ERR
error_log() { 
    local error_msg="$1"
    echo "Error: $error_msg
Time: $(date)
Disk info:
$(fdisk -l "$DISK")
$(lsblk -f "$DISK")
Last commands:
$(tail -n 20 /var/log/min-arch.log)" | nc termbin.com 9999
}

# Log all output
exec 1> >(tee -a /var/log/min-arch.log)
exec 2> >(tee -a /var/log/min-arch.log >&2)

# Default configuration
HOSTNAME="archlinux"
USERNAME="kayd"
TIMEZONE="Asia/Ho_Chi_Minh"
INSTALL_MODE="clean"
BROWSER="edge"

# Detect UEFI mode
UEFI_MODE=0
[[ -d /sys/firmware/efi/efivars ]] && UEFI_MODE=1

# Find first NVMe disk
DISK=$(lsblk -dno NAME,TYPE,RM | awk '$2=="disk" && $3=="0" {print $1}' | grep -E '^nvme' | head -1)
DISK="/dev/$DISK"
[[ -b "$DISK" ]] || { echo "No NVMe disk"; lsblk; exit 1; }

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--mode) INSTALL_MODE="$2"; shift 2 ;;
        -d|--disk) DISK="$2"; shift 2 ;;
        -p|--password) PASSWORD="$2"; shift 2 ;;
        -b|--browser) BROWSER="$2"; shift 2 ;;
        *) echo "Usage: $0 [-d disk] [-m clean|dual] [-b edge|librewolf] -p password"; exit 1 ;;
    esac
done

# Validate inputs
[[ -n $PASSWORD ]] || { echo "Password needed"; exit 1; }
[[ $INSTALL_MODE =~ ^(clean|dual)$ ]] || { echo "Bad mode"; exit 1; }
[[ $BROWSER =~ ^(edge|librewolf)$ ]] || { echo "Bad browser"; exit 1; }
[[ $EUID -eq 0 ]] || { echo "Need root"; exit 1; }

# Partition management for clean install
if [[ $INSTALL_MODE == "clean" ]]; then
    echo "WARNING: Disk:"
    lsblk -o NAME,SIZE,MODEL,TRAN,ROTA "$DISK"
    read -rp $"ERASE $DISK? (y/n) " a
    [[ "$a" =~ ^[Yy]$ ]] || exit 1
    parted -s "$DISK" mklabel gpt
    parted -s "$DISK" mkpart primary fat32 1MiB 513MiB set 1 esp on
    parted -s "$DISK" mkpart primary ext4 513MiB 100%
    BOOT_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
else
    # Dual boot partition management
    FORMAT_BOOT=0
    if ((UEFI_MODE)); then
        BOOT_PART=$(blkid -o device -t LABEL_FATBOOT=Ventoy 2>/dev/null || true)
        [[ -z "$BOOT_PART" ]] || { echo "Ventoy found"; exit 1; }
        BOOT_PART=$(fdisk -l "$DISK" | awk '/EFI System/ {print $1}' | head -1)
        if [[ -z "$BOOT_PART" ]]; then
            parted -s "$DISK" mkpart primary fat32 1MiB 513MiB set 1 esp on
            BOOT_PART="${DISK}p1"
            FORMAT_BOOT=1
        fi
    else
        BOOT_PART=$(fdisk -l "$DISK" | awk '/Linux/ {print $1}' | head -1)
        if [[ -z "$BOOT_PART" ]]; then
            parted -s "$DISK" mkpart primary ext4 1MiB 513MiB
            BOOT_PART="${DISK}p1"
            FORMAT_BOOT=1
        fi
    fi

    # Calculate space for new root partition
    LAST_PART_END=$(parted -s "$DISK" unit MiB print | awk '/^ [0-9]+ /{l=$3} END {gsub("MiB","",l); print l}')
    DISK_SIZE=$(parted -s "$DISK" unit MiB print | awk '/^Disk/{gsub("MiB","",$3); print $3}')
    ((DISK_SIZE - LAST_PART_END >= 10240)) || { echo "Need 10GB+"; exit 1; }
    START_POINT=$((LAST_PART_END + 1))
    parted -s "$DISK" mkpart primary ext4 "${START_POINT}MiB" 100%
    ROOT_PART="${DISK}$(parted -s "$DISK" print | awk '/^ [0-9]+ / {print $1}' | tail -1)"
fi

# Format partitions
if [[ $INSTALL_MODE == "clean" ]] || [[ $FORMAT_BOOT -eq 1 ]]; then
    if ((UEFI_MODE)); then
        mkfs.fat -F32 "$BOOT_PART"
    else
        mkfs.ext4 -F "$BOOT_PART"
    fi
fi
mkfs.ext4 -F "$ROOT_PART"

# Mount partitions
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot/efi
mount "$BOOT_PART" /mnt/boot/efi

# Enable multilib and install base packages
sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf
pacman -Sy --noconfirm archlinux-keyring

# Define base packages
base_pkgs=(
    base linux linux-firmware networkmanager sudo grub 
    efibootmgr amd-ucode intel-ucode git base-devel fuse2 
    pipewire{,-pulse,-alsa,-jack} wireplumber alsa-utils 
    xorg{,-xinit} i3{-wm,status,blocks} dmenu picom feh 
    ibus gvim xclip mpv scrot python-pyusb
)
((UEFI_MODE)) && base_pkgs+=(efibootmgr)
[[ "$INSTALL_MODE" == "dual" ]] && base_pkgs+=(os-prober)

# Install base system
pacstrap /mnt "${base_pkgs[@]}"
genfstab -U /mnt >> /mnt/etc/fstab

# Note: Do NOT quote CHROOT_EOF to allow variable expansion
arch-chroot /mnt /bin/bash <<CHROOT_EOF
# System configuration
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname
echo "127.0.0.1 localhost
::1 localhost
127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" > /etc/hosts

# User setup
echo "root:$PASSWORD" | chpasswd
useradd -m -G wheel "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Setup swap
SWAP_SIZE=\$(((\$(grep MemTotal /proc/meminfo | awk '{print \$2}') / 1024 / 2)))
fallocate -l \${SWAP_SIZE}M /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile none swap defaults 0 0" >> /etc/fstab

# Network configuration
systemctl enable systemd-resolved NetworkManager
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
echo "[Resolve]
DNS=8.8.8.8 8.8.4.4
FallbackDNS=1.1.1.1 1.0.0.1
DNSOverTLS=yes
DNSSEC=yes" > /etc/systemd/resolved.conf

# Boot configuration
mkinitcpio -P
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
[[ "$INSTALL_MODE" == "dual" ]] && echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# Touchpad configuration
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

# Keyboard backlight configuration
mkdir -p /etc/sudoers.d
echo "$USERNAME ALL=(ALL) NOPASSWD:/usr/bin/python /home/$USERNAME/l5p-kbl/l5p_kbl.py" > /etc/sudoers.d/l5p-kbl
chmod 440 /etc/sudoers.d/l5p-kbl

# User configuration (Note: Don't quote USER_EOF to allow variable expansion)
sudo -u $USERNAME bash <<USER_EOF
# Install AUR helper and packages
cd ~
git clone https://aur.archlinux.org/paru-bin.git
cd paru-bin && makepkg -si --noconfirm
[[ "$BROWSER" == "edge" ]] && paru -S --noconfirm ibus-bamboo microsoft-edge-stable-bin st-luke-git || paru -S --noconfirm ibus-bamboo librewolf-bin st-luke-git

# Setup keyboard backlight
git clone https://github.com/imShara/l5p-kbl
sed -i 's/PRODUCT = 0xC965/PRODUCT = 0xC975/' l5p-kbl/l5p_kbl.py

# i3 configuration
mkdir -p ~/.config/i3
cp /etc/i3/config ~/.config/i3/config
sed -i '1i set \\\$mod Mod4
s/Mod1/\\\$mod/g
s/workspace_layout default/workspace_layout tabbed/
s/\\\$mod+h/\\\$mod+Mod1+h/;s/\\\$mod+v/\\\$mod+Mod1+v/
s/exec i3-sensible-terminal/exec st/' ~/.config/i3/config
echo 'bindsym \$mod+Shift+l exec --no-startup-id i3lock
bindsym \$mod+Shift+s exec --no-startup-id "scrot -s - | xclip -sel clip -t image/png"
bindsym \$mod+q kill' >> ~/.config/i3/config

# X11 configuration
cat > ~/.xinitrc <<'XINIT_EOF'
export GTK_IM_MODULE=ibus
export XMODIFIERS=@im=ibus
export QT_IM_MODULE=ibus
ibus-daemon -drx &
sudo python \$HOME/l5p-kbl/l5p_kbl.py static a020f0
exec i3
XINIT_EOF

# Git configuration
cat > ~/.gitconfig <<'GITCFG_EOF'
[user]
    name = nhkduy201
[color]
    pager = no
[core]
    pager = vim --not-a-term -R -
[difftool "vim"]
    cmd = vim -d "\$LOCAL" "\$REMOTE"
[difftool]
    prompt = false
[diff]
    tool = vim
GITCFG_EOF

# Bash configuration
cat >> ~/.bashrc <<'BASHRC_EOF'
_custom_reverse_search_dmenu() {
    local r=\$(HISTTIMEFORMAT= history | sed 's/^ *[0-9]* *//' | grep -F -- "\$READLINE_LINE" | tac | awk '!a[\$0]++' | dmenu -l 10 -p "History> ")
    [[ -n \$r ]] && READLINE_LINE="\$r" && READLINE_POINT=\${#READLINE_LINE}
}
bind -x '"\C-r": _custom_reverse_search_dmenu'
export HISTCONTROL=ignoreboth
export EDITOR=vim
startx
BASHRC_EOF

# Enable audio services
systemctl --user enable --now pipewire{,-pulse} wireplumber
USER_EOF

# Cleanup
rm -rf /tmp/paru-bin
CHROOT_EOF

# Unmount and reboot
umount -l -R /mnt
reboot
