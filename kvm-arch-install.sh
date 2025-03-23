#!/bin/bash -x
set -e
sudo pacman -S --needed --noconfirm qemu virt-manager libvirt dnsmasq bridge-utils openssh sshpass cdrtools libosinfo expect xdotool
sudo groupadd -f libvirt
sudo usermod -aG libvirt $(whoami)
sudo systemctl enable --now libvirtd
if ! sudo virsh net-info default 2>/dev/null | grep -q "Active:.*yes"; then sudo virsh net-autostart default; sudo virsh net-start default; fi
rm -f ~/.ssh/known_hosts
mkdir -p ~/.ssh
chmod 700 ~/.ssh
if [ ! -f /var/lib/libvirt/images/archlinux*-x86_64.iso ]; then if [ -f download_arch_iso.sh ]; then ./download_arch_iso.sh; else curl -LO https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso; fi; fi
ISO_PATH=$(realpath $(ls -1 archlinux*-x86_64.iso 2>/dev/null | head -n1))
[ -z "$ISO_PATH" ] && { echo "ERROR: No ISO found"; exit 1; }
ISO_FILE=$(basename "$ISO_PATH")
sudo cp -f "$ISO_PATH" /var/lib/libvirt/images/
ISO_PATH="/var/lib/libvirt/images/$ISO_FILE"
VM_NAME="archlinux"
sudo virsh destroy "$VM_NAME" 2>/dev/null || true
sudo virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
sudo virt-install --name "$VM_NAME" --memory 2048 --vcpus 2 --disk size=20,format=qcow2 --os-variant archlinux --graphics vnc --network network=default --cdrom "$ISO_PATH" --noautoconsole
sudo virt-viewer "$VM_NAME" &
sleep 1
WIN_ID=$(xdotool search --name "$VM_NAME")
xdotool windowactivate $WIN_ID
xdotool key Return
sleep 15
xdotool windowactivate $WIN_ID
xdotool type "echo root:1|chpasswd"
xdotool key Return
sleep 1
VM_IP=""
while [ -z "$VM_IP" ]; do VM_IP=$(sudo virsh domifaddr "$VM_NAME" | awk '/ipv4/ {print $4}' | cut -d'/' -f1); sleep 5; done
until sshpass -p 1 ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no root@$VM_IP true 2>/dev/null; do sleep 5; done
sshpass -p 1 scp -o StrictHostKeyChecking=no ./min-arch-install.sh root@$VM_IP:/tmp/
sshpass -p 1 ssh -o StrictHostKeyChecking=no root@$VM_IP 'echo y | /tmp/min-arch-install.sh -m clean -p 1'
