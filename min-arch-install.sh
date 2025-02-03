#!/bin/bash -x
set -eo pipefail
trap 'error_log "Error on line $LINENO"' ERR

error_log() {
    local error_msg="$1"
    echo "
Error: $error_msg
Time: $(date)
Disk info:
$(fdisk -l $DISK)
$(lsblk -f $DISK)
Last commands:
$(tail -n 20 /var/log/min-arch.log)" | nc termbin.com 9999
}

exec 1> >(tee -a /var/log/min-arch.log)
exec 2> >(tee -a /var/log/min-arch.log >&2)

HOSTNAME="archlinux"
USERNAME="kayd"
TIMEZONE="Asia/Ho_Chi_Minh"
INSTALL_MODE="clean"
BROWSER="edge"
UEFI_MODE=0

[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }
[[ -d /sys/firmware/efi/efivars ]] && UEFI_MODE=1
DISK=$(lsblk -dno NAME,TYPE,RM | awk '$2=="disk" && $3=="0" {print $1}' | grep -E '^nvme' | head -1)
DISK="/dev/$DISK"
[[ -b "$DISK" ]] || { echo "No suitable NVMe disk found"; lsblk -dno NAME,TYPE,RM,SIZE,MODEL; exit 1; }

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
    echo "WARNING: Selected disk for installation:"
    lsblk -o NAME,SIZE,MODEL,TRAN,ROTA "$DISK"
    echo -n "THIS WILL ERASE ALL DATA ON $DISK! Confirm (y/n)? "
    read -r answer
    [[ "$answer" =~ ^[Yy]$ ]] || exit 1
    parted -s "$DISK" mklabel gpt
    parted -s "$DISK" mkpart primary fat32 1MiB 513MiB set 1 esp on
    parted -s "$DISK" mkpart primary ext4 513MiB 100%
    BOOT_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
else
    if [[ $UEFI_MODE -eq 1 ]]; then
        BOOT_PART=$(blkid -o device -t LABEL_FATBOOT=Ventoy 2>/dev/null || true)
        [[ -z "$BOOT_PART" ]] || { echo "Ventoy partition detected - aborting"; exit 1; }
        BOOT_PART=$(fdisk -l "$DISK" | awk '/EFI System/ {print $1}' | head -1)
        if [[ -z "$BOOT_PART" ]]; then
            parted -s "$DISK" mkpart primary fat32 1MiB 513MiB
            parted -s "$DISK" set 1 esp on
            BOOT_PART="${DISK}p1"
        fi
        [[ $(blkid -s TYPE -o value "$BOOT_PART") == "vfat" ]] || { echo "Invalid ESP filesystem"; exit 1; }
    else
        BOOT_PART=$(fdisk -l "$DISK" | awk '/Linux/ {print $1}' | head -1)
        [[ -n $BOOT_PART && -b $BOOT_PART && $(blkid -s TYPE -o value "$BOOT_PART") == "ext4" ]] || { echo "No valid boot partition"; exit 1; }
    fi
    LAST_PART_END=$(parted -s "$DISK" unit MiB print | awk '/^ [0-9]+ /{last=$3}END{gsub("MiB", "", last); print last}')
    START_POINT=$(awk "BEGIN {print int($LAST_PART_END + 1)}")
    DISK_SIZE=$(parted -s "$DISK" unit MiB print | awk '/^Disk/{gsub("MiB", "", $3); print $3}')
    AVAILABLE_SPACE=$(awk "BEGIN {print $DISK_SIZE - $START_POINT}")
    (( AVAILABLE_SPACE >= 10240 )) || { echo "Need 10GB+ free space"; exit 1; }
    parted -s "$DISK" mkpart primary ext4 "${START_POINT}MiB" 100%
    ROOT_PART="${DISK}p$(parted -s "$DISK" print | awk '/^ [0-9]+ / {print $1}' | tail -1)"
fi

if [[ $UEFI_MODE -eq 1 ]]; then
    mkfs.fat -F32 "$BOOT_PART"
else
    mkfs.ext4 "$BOOT_PART"
fi

mkfs.ext4 -F "$ROOT_PART"
sync
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot/efi
mount "$BOOT_PART" /mnt/boot/efi || { echo "EFI mount failed"; umount /mnt; exit 1; }

sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf
pacman-key --init
pacman-key --populate archlinux
pacman -Sy --noconfirm archlinux-keyring netcat git
pacstrap /mnt base linux linux-firmware networkmanager sudo grub efibootmgr intel-ucode amd-ucode git base-devel fuse2 os-prober pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber alsa-utils xorg-server xorg-xinit i3-wm i3status i3blocks dmenu picom feh ibus gvim xclip mpv

genfstab -U /mnt >> /mnt/etc/fstab

SWAP_SIZE=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 2)) # Half of RAM size
arch-chroot /mnt /bin/bash <<'CHROOT_EOF'
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname
echo "127.0.0.1 localhost
::1	localhost
127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" > /etc/hosts
echo "root:$PASSWORD" | chpasswd
useradd -m -G wheel "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
fallocate -l ${SWAP_SIZE}M /swapfile
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
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
[[ "$INSTALL_MODE" == "dual" ]] && echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
systemctl --user --now enable pipewire pipewire-pulse wireplumber
cd /tmp && git clone https://aur.archlinux.org/paru-bin.git
cd paru-bin && makepkg -si --noconfirm
if [[ "$BROWSER" == "edge" ]]; then
    paru -S --noconfirm ibus-bamboo microsoft-edge-stable-bin
else
    paru -S --noconfirm ibus-bamboo librewolf-bin
fi
mkdir -p /etc/sudoers.d
echo "$USERNAME ALL=(ALL:ALL) NOPASSWD: /usr/bin/python /home/$USERNAME/l5p-kbl/l5p_kbl.py" > /etc/sudoers.d/l5p-kbl
chmod 440 /etc/sudoers.d/l5p-kbl
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/30-touchpad.conf <<'XORG_EOF'
Section "InputClass"
    Identifier "libinput touchpad catchall"
    MatchIsTouchpad "on"
    Driver "libinput"
    Option "Tapping" "on"
    Option "NaturalScrolling" "true"
EndSection
XORG_EOF
chown -R $USERNAME:$USERNAME /home/$USERNAME/
sudo -u $USERNAME bash <<'USERCMD'
cd ~
git clone https://github.com/imShara/l5p-kbl
sed -i 's/PRODUCT = 0xC965/PRODUCT = 0xC975/' l5p-kbl/l5p_kbl.py
cat > ~/.xinitrc <<'XINIT_EOF'
export GTK_IM_MODULE=ibus
export XMODIFIERS=@im=ibus
export QT_IM_MODULE=ibus
ibus-daemon -drx &
sudo python $HOME/l5p-kbl/l5p_kbl.py static a020f0
exec i3
XINIT_EOF
chmod +x ~/.xinitrc
cat > ~/.gitconfig <<'GITCONFIG_EOF'
[user]
    name = nhkduy201
[color]
    pager = no
[core]
    pager = vim -R -
[difftool "vim"]
    cmd = vim -d "$LOCAL" "$REMOTE"
[difftool]
    prompt = false
[diff]
    tool = vim
GITCONFIG_EOF
USERCMD
rm -rf /tmp/paru-bin
CHROOT_EOF

sync
if mountpoint -q /mnt; then
  for attempt in {1..3}; do
    fuser -km /mnt || true
    sleep 2
    umount -R /mnt && break || {
      [[ $attempt -eq 3 ]] && { echo "Failed to unmount"; exit 1; }
      sleep 5
    }
  done
fi
reboot
