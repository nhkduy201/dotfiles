#!/bin/bash
## Install required packages
#sudo pacman -S --needed --noconfirm qemu virt-manager virt-viewer libvirt ebtables dnsmasq bridge-utils
## Enable and start libvirt service
#sudo systemctl enable --now libvirtd
## Add current user to libvirt group
#sudo usermod -aG libvirt $(whoami)
## Configure default network
#sudo virsh net-autostart default
#sudo virsh net-start default
## Copy ISO to libvirt images directory
#sudo cp /mnt/archlinux-2025.02.01-x86_64.iso /var/lib/libvirt/images/
## Cleanup existing VM if it exists
sudo virsh destroy archlinux
sudo virsh undefine archlinux --remove-all-storage
## Create and start new VM
sudo virt-install \
    --name archlinux \
    --memory 2048 \
    --vcpus 2 \
    --disk size=20 \
    --cdrom /var/lib/libvirt/images/archlinux-2025.02.01-x86_64.iso \
    --os-variant generic \
    --network network=default \
    --boot menu=on,useserial=on \
    --graphics vnc \
    --machine q35 \
    --console pty,target_type=serial
## Wait for VM to be accessible and run installation script
while ! sshpass -p 1 ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    root@$(sudo virsh domifaddr archlinux | grep -Po '(\d+\.){3}\d+') \
    'yes | bash <(curl -sL https://raw.githubusercontent.com/nhkduy201/dotfiles/main/min-arch-install.sh) -m clean -p 1'
do
    sleep 1
done
