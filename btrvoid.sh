#!/bin/bash

# Check if script is ran as root or not.
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script as root."
    exit 1
fi

# List block devices.
cd /
lsblk

# Ask user for prompt.
read -rp "Enter the disk name (WARNING: ALL DATA ON THAT DISK WILL GET DELETED) (e.g. sda, nvme0n1): " disk

# Safety check
if [ ! -b "/dev/$disk" ]; then
    echo "Error: /dev/$disk not found."
    exit 1
fi

# Setting new partition table and partitioning the disk.
fdisk "/dev/$disk" <<EOF
g
n
1

+256M
t
1
n
2

+1G
n
3


w
EOF

echo "Partitioning is done successfully."


# Formatting new partitions.
if [[ $disk =~ [0-9]$ ]]; then
    p="p"
else
    p=""
fi

mkfs.vfat -F32 "/dev/${disk}${p}1"
mkfs.ext4 "/dev/${disk}${p}2"
mkfs.btrfs "/dev/${disk}${p}3"

echo "Formatting is done successfully."
sleep 3
clear
echo "Proceed in the installer and choose the disks for /, /boot, /boot/efi without formatting and don't reboot after, but exit the installer."
sleep 15
void-installer


# Mount the new root.
cd /
umount -R /mnt/*
umount -R /mnt
rm -rf /mnt/*
mount /dev/vda3 /mnt

# Move its content to a subvolume.
btrfs subvolume create /mnt/@
mv /mnt/* /mnt/@

# Create another home subvolume.
btrfs subvolume create /mnt/@home
mv /mnt/@/home/* /mnt/@home
echo "Data moved to subvolumes successfully."
sleep 2


# Setup /etc/fstab.
uuid_efi=$(blkid -s UUID -o value /dev/${disk}${p}1)
uuid_boot=$(blkid -s UUID -o value /dev/${disk}${p}2)
uuid_root=$(blkid -s UUID -o value /dev/${disk}${p}3)

rm /mnt/@/etc/fstab

cat > /mnt/@/etc/fstab <<EOF
UUID=${uuid_root}   /          btrfs  subvol=@               0 0
UUID=${uuid_root}   /home      btrfs  subvol=@home           0 0
UUID=${uuid_boot}   /boot      ext4   defaults               0 2
UUID=${uuid_efi}    /boot/efi  vfat   defaults               0 2
tmpfs               /tmp       tmpfs  defaults,nosuid,nodev  0 0
EOF


# Remount partitions in the correct way.
umount -R /mnt

mount "/dev/${disk}${p}3" /mnt -o subvol=@
mount "/dev/${disk}${p}3" /mnt/home -o subvol=@home
mount "/dev/${disk}${p}2" /mnt/boot
mount "/dev/${disk}${p}1" /mnt/boot/efi

mount --bind /dev /mnt/dev
mount --bind /sys /mnt/sys
mount --bind /proc /mnt/proc
mount -t efivarfs efivarfs /mnt/sys/firmware/efi/efivars


# Chroot and install grub.
rm -rf /mnt/boot/efi/*
chroot /mnt /bin/bash <<'EOF'
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Void
grub-mkconfig -o /boot/grub/grub.cfg
exit
EOF

echo "You can reboot now!"


# Reboot prompt
while true; do
    read -rp "Reboot? [Y/n]: " ans
    case "$ans" in
        [Yy]|"")
            if ! reboot; then
                echo "Failed to reboot, please reboot manually."
                exit 1
            fi
            break
            ;;
        [Nn])
            echo "Aborted."
            exit 1
            ;;
        *)
            echo "Please answer with y or n."
            ;;
    esac
done
