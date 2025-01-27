#!/bin/bash
set -eo pipefail
DISK="/dev/nvme0n1"
HOSTNAME="archlinux"
USERNAME="kayd"
TIMEZONE="Asia/Ho_Chi_Minh"
INSTALL_MODE="clean"
[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }
[[ -d /sys/firmware/efi/efivars ]] || { echo "Requires UEFI"; exit 1; }
[[ -b $DISK ]] || { echo "Disk not found: $DISK"; exit 1; }
while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--mode) INSTALL_MODE="$2"; shift 2 ;;
        -d|--disk) DISK="$2"; shift 2 ;;
        -p|--password) PASSWORD="$2"; shift 2 ;;
        *) echo "Usage: $0 [-d disk] [-m clean|dual] -p password"; exit 1 ;;
    esac
done
[[ -n $PASSWORD ]] || { echo "Password required"; exit 1; }
[[ $INSTALL_MODE =~ ^(clean|dual)$ ]] || { echo "Invalid mode: $INSTALL_MODE"; exit 1; }
if [[ $INSTALL_MODE == "clean" ]]; then
    parted -s "$DISK" mklabel gpt mkpart primary fat32 1MiB 512MiB set 1 esp on mkpart primary ext4 512MiB 100%
    BOOT_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
    mkfs.fat -F32 "$BOOT_PART"
else
    BOOT_PART=$(fdisk -l "$DISK" | awk '/EFI System/{print $1}' | head -1)
    [[ -n $BOOT_PART && -b $BOOT_PART && $(blkid -s TYPE -o value "$BOOT_PART") == "vfat" ]] || { echo "No valid EFI partition found"; exit 1; }
    FREE_SPACE=$(parted -s "$DISK" unit MiB print free | awk '/Free Space/ && $4>10240{print $1}' | tail -1)
    [[ -n $FREE_SPACE ]] || { echo "Need 10GB+ free space"; exit 1; }
    parted -s "$DISK" mkpart primary ext4 "${FREE_SPACE}MiB" 100%
    ROOT_PART=$(fdisk -l "$DISK" | awk '/Linux filesystem$/{print $1}' | tail -1)
fi
mkfs.ext4 -F "$ROOT_PART"
mount
mkdir -p /mnt/boot/efi
mount "$BOOT_PART" /mnt/boot/efi || { echo "Failed mounting EFI"; umount /mnt; exit 1; }
pacstrap /mnt base linux linux-firmware networkmanager sudo efibootmgr firefox
genfstab -U /mnt >> /mnt/etc/fstab
arch-chroot /mnt /bin/bash <<'EOF'
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname
echo "root:$PASSWORD" | chpasswd
useradd -m -G wheel "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
systemctl enable NetworkManager
if [[ $INSTALL_MODE == "dual" ]]; then
    pacman -S --noconfirm sbsigntools
    mkdir -p /boot/EFI/keys
    cd /boot/EFI/keys
    for type in db KEK PK; do
        openssl req -new -x509 -newkey rsa:2048 -keyout ${type}.key -out ${type}.crt -nodes -days 3650 -subj "/CN=Arch ${type}/"
        openssl x509 -outform DER -in ${type}.crt -out ${type}.der
        efi-updatevar
    done
    sbsign --key db.key --cert db.crt /boot/vmlinuz-linux --output /boot/vmlinuz-linux.signed
fi
bootctl install
mkdir -p /boot/loader/entries
cat > /boot/loader/entries/arch.conf <<LOADER
title Arch Linux
linux /vmlinuz-linux$([ "$INSTALL_MODE" == "dual" ] && echo ".signed")
initrd /initramfs-linux.img
options root=$(blkid -s UUID -o value "$ROOT_PART") rw
LOADER
EOF
umount -R /mnt
echo "Installation complete. Reboot to start."
