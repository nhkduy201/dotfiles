#!/bin/bash
# # Install required packages
echo -e '1\ny\n' | sudo pacman -S --needed qemu virt-manager virt-viewer libvirt ebtables dnsmasq bridge-utils
# Enable and start libvirt service
sudo systemctl enable --now libvirtd
# Add current user to libvirt group
sudo usermod -aG libvirt $(whoami)
# Configure default network
sudo virsh net-autostart default
sudo virsh net-start default
# Download Arch Linux ISO
if [ -f archlinux-*-x86_64.iso ]; then
    echo "Arch Linux ISO already exists. Skipping download."
else
    ./download_arch_iso.sh
    if [ ! -f archlinux-*-x86_64.iso ]; then
        echo "Failed to download Arch Linux ISO. Exiting." >&2
        exit 1
    fi
fi
# Copy ISO to libvirt images directory
sudo cp archlinux-*-x86_64.iso /var/lib/libvirt/images/
# Cleanup existing VM if it exists
sudo virsh destroy archlinux
sudo virsh undefine archlinux --remove-all-storage
## Create and start new VM
sudo virt-install \
    --name archlinux \
    --memory 2048 \
    --vcpus 2 \
    --disk size=20 \
    --cdrom /var/lib/libvirt/images/archlinux-*-x86_64.iso \
    --os-variant generic \
    --network network=default \
    --boot menu=on,useserial=on \
    --graphics vnc \
    --machine q35 \
    --console pty,target_type=serial &> ./virt-install.log &
## Install sshpass if not installed
sudo pacman -S --needed --noconfirm sshpass
## Wait for VM to be accessible and run installation script
while ! (sshpass -p 1 scp \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    ./min-arch-install.sh \
    root@$(sudo virsh domifaddr archlinux | grep -Po '(\d+\.){3}\d+'):/tmp/)
do
    sleep 1
done

sshpass -p 1 ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    root@$(sudo virsh domifaddr archlinux | grep -Po '(\d+\.){3}\d+') \
    'yes | bash /tmp/min-arch-install.sh -m clean -p 1'
