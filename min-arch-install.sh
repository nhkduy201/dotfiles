#!/bin/bash -x
set -eo pipefail
trap 'error_log "Error on line $LINENO"' ERR
error_log() { local error_msg="$1"; echo "Error: $error_msg Time: $(date) Disk info: $(fdisk -l "$DISK") $(lsblk -f "$DISK") Last commands: $(tail -n 20 /var/log/min-arch.log)" | nc termbin.com 9999; }
exec 1> >(tee -a /var/log/min-arch.log)
exec 2> >(tee -a /var/log/min-arch.log >&2)
HOSTNAME="archlinux"
USERNAME="kayd"
TIMEZONE="Asia/Ho_Chi_Minh"
INSTALL_MODE="clean"
BROWSER="edge"
UEFI_MODE=0
[[ -d /sys/firmware/efi/efivars ]] && UEFI_MODE=1
detect_install_disk() {
    local is_vm=0
    local vm_hint=""
    if grep -qi "vmware" /sys/class/dmi/id/sys_vendor 2>/dev/null || grep -qi "virtualbox" /sys/class/dmi/id/sys_vendor 2>/dev/null || grep -qi "qemu" /sys/class/dmi/id/sys_vendor 2>/dev/null; then
        is_vm=1
        vm_hint=$(grep -i "vmware\|virtualbox\|qemu" /sys/class/dmi/id/sys_vendor 2>/dev/null)
    fi
    if ((is_vm)); then
        echo "Detected virtual environment: $vm_hint" >&2
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
        echo "Detected Ventoy installation at $ventoy_disk - avoiding this disk" >&2
        local ventoy_parent=$(lsblk -no PKNAME "$ventoy_disk" | head -1)
        [[ -n "$ventoy_parent" ]] && ventoy_parent="/dev/$ventoy_parent"
    fi
    local available_disks=($(lsblk -dno NAME,TYPE,RM | awk '$2=="disk" && $3=="0" {print $1}'))
    for disk in "${available_disks[@]}"; do
        disk="/dev/$disk"
        [[ "$disk" == "$ventoy_parent" ]] && continue
        if [[ "$disk" =~ ^/dev/nvme ]]; then
            echo "$disk"
            return 0
        fi
    done
    for disk in "${available_disks[@]}"; do
        disk="/dev/$disk"
        [[ "$disk" == "$ventoy_parent" ]] && continue
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

clean_existing_install() {
    local disk="$1"
    if ((UEFI_MODE)) && mount | grep -q "/mnt/boot/efi"; then
        echo "Cleaning up existing GRUB EFI installation..."
        if [[ -d /mnt/boot/efi/EFI/GRUB ]]; then
            rm -rf /mnt/boot/efi/EFI/GRUB
        fi
    fi
    if [[ $INSTALL_MODE == "clean" ]]; then
        return 0
    fi
    local linux_parts=($(lsblk -no NAME,FSTYPE "$disk" | grep "ext4" | cut -d' ' -f1))
    for part in "${linux_parts[@]}"; do
        part="/dev/$part"
        [[ "$part" == "$BOOT_PART" ]] && continue
        mkdir -p /tmp/arch_check
        if mount "$part" /tmp/arch_check 2>/dev/null; then
            if [[ -f /tmp/arch_check/etc/arch-release ]]; then
                echo "Found existing Arch Linux installation on $part"
                umount /tmp/arch_check
                
                read -rp $"Remove existing Arch Linux on $part? (y/n) " a
                if [[ "$a" =~ ^[Yy]$ ]]; then
                    echo "Removing existing Arch Linux partition $part"
                    umount "$part" 2>/dev/null || true
                    mkfs.ext4 -F "$part"
                    ROOT_PART="$part"
                    return 0
                fi
            fi
            umount /tmp/arch_check
        fi
    done
    rmdir /tmp/arch_check 2>/dev/null || true
    return 1
}
DISK=$(detect_install_disk)
[[ -b "$DISK" ]] || { echo "No suitable disk found"; lsblk; exit 1; }
[[ $INSTALL_MODE == "dual" ]] && clean_existing_install "$DISK"

while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--mode) INSTALL_MODE="$2"; shift 2 ;;
        -d|--disk) DISK="$2"; shift 2 ;;
        -p|--password) PASSWORD="$2"; shift 2 ;;
        -b|--browser) BROWSER="$2"; shift 2 ;;
        *) echo "Usage: $0 [-d disk] [-m clean|dual] [-b edge|librewolf] -p password"; exit 1 ;;
    esac
done
[[ -n $PASSWORD ]] || { echo "Password needed"; exit 1; }
[[ $INSTALL_MODE =~ ^(clean|dual)$ ]] || { echo "Bad mode"; exit 1; }
[[ $BROWSER =~ ^(edge|librewolf)$ ]] || { echo "Bad browser"; exit 1; }
[[ $EUID -eq 0 ]] || { echo "Need root"; exit 1; }
if [[ $INSTALL_MODE == "clean" ]]; then
    echo "WARNING: Disk:"
    lsblk -o NAME,SIZE,MODEL,TRAN,ROTA "$DISK"
    read -rp $"ERASE $DISK? (y/n) " a
    [[ "$a" =~ ^[Yy]$ ]] || exit 1
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
        [[ -z "$BOOT_PART" ]] || { echo "Ventoy found"; exit 1; }
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
            parted -s "$DISK" set 1 boot on  # Add boot flag for BIOS boot partition
            BOOT_PART=$(get_partition_device "$DISK" "1")
            FORMAT_BOOT=1
        fi
    fi
    FREE_SPACE=$(parted -s "$DISK" unit MiB print free | awk '
        /Free Space/ {
            gsub("MiB","",$3)
            if (int($3) > max) max = int($3)
        } 
        END {print max}
    ')
    [[ -z "$FREE_SPACE" ]] && FREE_SPACE=0
    [[ $FREE_SPACE -ge 10240 ]] || { echo "Need 10GB+ of free space (only found ${FREE_SPACE}MiB)"; exit 1; }
    LAST_PART_END=$(parted -s "$DISK" unit MiB print | awk '
        /^ [0-9]+ / {
            gsub("MiB","",$3)
            if (int($3) > end) end = int($3)
        } 
        END {print end}
    ')
    START_POINT=$((LAST_PART_END + 1))
    parted -s "$DISK" mkpart primary ext4 "${START_POINT}MiB" 100%
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
if ((UEFI_MODE)); then
    mkdir -p /mnt/boot/efi
    mount "$BOOT_PART" /mnt/boot/efi
else
    mkdir -p /mnt/boot
    mount "$BOOT_PART" /mnt/boot
fi
sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf
pacman-key --init
pacman-key --populate archlinux
pacman -Sy --noconfirm archlinux-keyring
base_pkgs=(base linux linux-firmware networkmanager sudo grub efibootmgr amd-ucode intel-ucode git base-devel fuse2 pipewire{,-pulse,-alsa,-jack} wireplumber alsa-utils xorg{,-xinit} i3{-wm,status,blocks} dmenu picom feh ibus gvim xclip mpv scrot slock python-pyusb brightnessctl jq wget openssh xdg-utils tmux)
((UEFI_MODE)) && base_pkgs+=(efibootmgr)
[[ "$INSTALL_MODE" == "dual" ]] && base_pkgs+=(os-prober)
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
mount -t efivarfs efivarfs /sys/firmware/efi/efivars 2>/dev/null || true
UEFI_CHROOT=0
[[ -d /sys/firmware/efi/efivars ]] && UEFI_CHROOT=1
if ((UEFI_CHROOT)); then
    rm -rf /boot/efi/EFI/GRUB || true
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
paru -Gq st
cd st
sed -i "s#^source=(.*#&\\n        st-clipboard-20180309-c5ba9c0.diff#" PKGBUILD
sed -i "s#^sha256sums=(.*#&\\n            '4989c03de5165234303d3929e3b60d662828972203561651aa6dc6b8f67feeb8'#" PKGBUILD
wget -q https://st.suckless.org/patches/clipboard/st-clipboard-20180309-c5ba9c0.diff
sed -i '/^prepare() {/a\
\ \ patch -d "\\\$_sourcedir" -p1 < st-clipboard-20180309-c5ba9c0.diff\n\
  sed -i "s/\\\\\\\\(STCFLAGS =\\\\\\\\)\\\\\\\\(.*\\\\\\\\)/\\\\\\\\1 -O3 -march=native\\\\\\\\2/" "\\\$_sourcedir/config.mk"\n\
  sed -i "s/\\\\\\\\(static char \\\\\\\\*font = \\\\\\\"\\\\\\\\)[^:]\\\\\\\\+:[^:]\\\\\\\\+/\\\\\\\\1Source Code Pro:pixelsize=16/" "\\\$_sourcedir/config.def.h"' PKGBUILD
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
s/exec i3-sensible-terminal/exec st/
s/^\\(font\\s\\+[^0-9]\\+\\)[0-9]\\+/\\112/g' ~/.config/i3/config
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
cat > ~/.vimrc <<'VIM_EOF'
set hls tabstop=2 shiftwidth=2 expandtab autoindent smartindent cindent clipboard=unnamedplus mouse=
let mapleader = ","
syntax on
VIM_EOF
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
[[ \\\$TERM_PROGRAM = "vscode" ]] && [[ -z \\\$TMUX ]] && { tmux attach || tmux; }
BASHRC_EOF
systemctl --user enable --now pipewire{,-pulse} wireplumber
USER_EOF
rm -rf /tmp/paru-bin
CHROOT_EOF
umount -l -R /mnt
reboot
