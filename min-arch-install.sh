#!/bin/bash -x
set -eo pipefail
trap 'error_log "Error on line $LINENO"' ERR
pacman -Sy --noconfirm curl netcat
error_log() {
    local error_msg="$1"
    local log_content="
Error: $error_msg
Time: $(date)
Disk info:
$(fdisk -l $DISK)
$(lsblk -f $DISK)
Last commands:
$(tail -n 20 /var/log/min-arch.log)"
    echo "$log_content" | nc termbin.com 9999
}
exec 1> >(tee -a /var/log/min-arch.log)
exec 2> >(tee -a /var/log/min-arch.log >&2)
HOSTNAME="archlinux"
USERNAME="kayd"
TIMEZONE="Asia/Ho_Chi_Minh"
INSTALL_MODE="clean"
BROWSER="librewolf"
UEFI_MODE=0
[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }
[[ -d /sys/firmware/efi/efivars ]] && UEFI_MODE=1
# Hardcode NVMe detection
DISK=$(lsblk -dno NAME | grep -E '^nvme' | head -1)
DISK="/dev/$DISK"
[[ -b $DISK ]] || { echo "NVMe disk not found"; exit 1; }
while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--mode) INSTALL_MODE="$2"; shift 2 ;;
        -d|--disk) DISK="$2"; shift 2 ;;
        -p|--password) PASSWORD="$2"; shift 2 ;;
        -b|--browser) BROWSER="$2"; shift 2 ;;
        *) echo "Usage: $0 [-d disk] [-m clean|dual] [-b edge|librewolf] -p password"; exit 1 ;;
    esac
done
[[ -n $PASSWORD ]] || { echo "Password required"; exit 1; }
[[ $INSTALL_MODE =~ ^(clean|dual)$ ]] || { echo "Invalid mode: $INSTALL_MODE"; exit 1; }
[[ $BROWSER =~ ^(edge|librewolf)$ ]] || { echo "Invalid browser: $BROWSER"; exit 1; }
if [[ $INSTALL_MODE == "clean" ]]; then
    # Clean install - always create new ESP
    parted -s "$DISK" mklabel gpt
    parted -s "$DISK" mkpart primary fat32 1MiB 513MiB set 1 esp on
    parted -s "$DISK" mkpart primary ext4 513MiB 100%
    BOOT_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
    mkfs.fat -F32 "$BOOT_PART"
else
    # Dual install - create ESP if missing
    if [[ $UEFI_MODE -eq 1 ]]; then
        BOOT_PART=$(fdisk -l "$DISK" | awk '/EFI System/ {print $1}' | head -1)
        if [[ -z "$BOOT_PART" ]]; then
            echo "Creating new ESP partition"
            parted -s "$DISK" mkpart primary fat32 1MiB 513MiB
            parted -s "$DISK" set 1 esp on
            BOOT_PART="${DISK}p1"
            mkfs.fat -F32 "$BOOT_PART"
        fi
        [[ $(blkid -s TYPE -o value "$BOOT_PART") == "vfat" ]] || { echo "Invalid ESP filesystem"; exit 1; }
    else
        BOOT_PART=$(fdisk -l "$DISK" | awk '/Linux/ {print $1}' | head -1)
        [[ -n $BOOT_PART && -b $BOOT_PART && $(blkid -s TYPE -o value "$BOOT_PART") == "ext4" ]] || { echo "No valid boot partition"; exit 1; }
    fi
    # Find last partition
    LAST_PART_END=$(parted -s "$DISK" unit MiB print | awk '/^ [0-9]+ /{last=$3}END{gsub("MiB", "", last); print last}')
    START_POINT=$(awk "BEGIN {print int($LAST_PART_END + 1)}")
    DISK_SIZE=$(parted -s "$DISK" unit MiB print | awk '/^Disk/{gsub("MiB", "", $3); print $3}')
    AVAILABLE_SPACE=$(awk "BEGIN {print $DISK_SIZE - $START_POINT}")
    (( AVAILABLE_SPACE >= 10240 )) || { echo "Need 10GB+ free space"; exit 1; }
    parted -s "$DISK" mkpart primary ext4 "${START_POINT}MiB" 100%
    ROOT_PART="${DISK}p$(parted -s "$DISK" print | awk '/^ [0-9]+ / {print $1}' | tail -1)"
fi
mkfs.ext4 -F "$ROOT_PART"
sync
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot/efi
mount "$BOOT_PART" /mnt/boot/efi || { echo "EFI mount failed"; umount /mnt; exit 1; }
sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf
pacman-key --init
pacman-key --populate archlinux
pacman -Sy --noconfirm archlinux-keyring
pacman -Syy
pacstrap /mnt base linux linux-firmware networkmanager sudo grub efibootmgr intel-ucode amd-ucode git base-devel fuse2 os-prober
genfstab -U /mnt >> /mnt/etc/fstab
arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname
echo "127.0.0.1 localhost
::1       localhost
127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" > /etc/hosts
echo "root:$PASSWORD" | chpasswd
useradd -m -G wheel "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile none swap defaults 0 0" >> /etc/fstab
systemctl enable systemd-resolved NetworkManager
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
echo "DNS=8.8.8.8 8.8.4.4
FallbackDNS=1.1.1.1 1.0.0.1
DNSOverTLS=yes
DNSSEC=yes" > /etc/systemd/resolved.conf
mkinitcpio -P
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
sudo -u $USERNAME bash <<USERCMD
cd /tmp && git clone https://aur.archlinux.org/paru-bin.git
cd paru-bin && makepkg -si --noconfirm
paru -S --noconfirm i3-wm i3status i3blocks dmenu xorg-server xorg-xinit xorg-xrandr alacritty picom feh ibus
paru -S --noconfirm ibus-bamboo
if [[ "$BROWSER" == "edge" ]]; then
    paru -S --noconfirm microsoft-edge-stable-bin
else
    paru -S --noconfirm librewolf-bin
fi
cd ~
git clone https://github.com/imShara/l5p-kbl
sed -i 's/PRODUCT = 0xC965/PRODUCT = 0xC975/' l5p-kbl/l5p_kbl.py
echo "export GTK_IM_MODULE=ibus
export XMODIFIERS=@im=ibus
export QT_IM_MODULE=ibus
ibus-daemon -drx &" >> ~/.xinitrc
echo "sudo python \$HOME/l5p-kbl/l5p_kbl.py static a020f0" >> ~/.xinitrc
echo "exec i3" >> ~/.xinitrc
chmod +x ~/.xinitrc
mkdir -p ~/.config/i3
cp /etc/i3/config ~/.config/i3/config
sed -i '1i set $mod Mod4' ~/.config/i3/config
sed -i '1a workspace_layout tabbed' ~/.config/i3/config
sed -i 's/\$mod+h/\$mod+Shift+h/
s/\$mod+l/\$mod+Shift+l/' ~/.config/i3/config
sed -i '/bindsym .*focus/d' ~/.config/i3/config
echo "bindsym \$mod+h focus left
bindsym \$mod+j focus down
bindsym \$mod+k focus up
bindsym \$mod+l focus right" >> ~/.config/i3/config
echo "startx" >> ~/.bashrc
rm -rf /tmp/paru-bin
USERCMD
mkdir -p /etc/sudoers.d
echo "$USERNAME ALL=(ALL:ALL) NOPASSWD: /usr/bin/python /home/$USERNAME/l5p-kbl/l5p_kbl.py" > /etc/sudoers.d/l5p-kbl
chmod 440 /etc/sudoers.d/l5p-kbl
mkdir -p /etc/X11/xorg.conf.d
echo 'Section "InputClass"
    Identifier "libinput touchpad catchall"
    MatchIsTouchpad "on"
    Driver "libinput"
    Option "Tapping" "on"
    Option "NaturalScrolling" "true"
EndSection' > /etc/X11/xorg.conf.d/30-touchpad.conf
chown -R $USERNAME:$USERNAME /home/$USERNAME/
EOF
sync
fuser -km /mnt
umount -R /mnt
echo "Installation complete. Run 'startx' after reboot to start i3."
