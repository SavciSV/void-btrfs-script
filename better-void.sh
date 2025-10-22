#!/bin/bash

# Check if script is running as root or not.
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script as root."
    exit 1
fi


# List block devices.
cd /
lsblk

# Ask user for prompt.
read -rp "Enter the disk name (e.g. sda, nvme0n1): " disk

# Safety check
if [ ! -b "/dev/$disk" ]; then
    echo "Error: /dev/$disk not found."
    exit 1
fi

# Compatibility with NVMe disks.
if [[ $disk =~ [0-9]$ ]]; then
    p="p"
else
    p=""
fi


# Function of Partitioning and Formatting if the user wants it.
partitionAndFormat()
{
    # Setting root, boot, and efi partiitons values to the known ones.
    efipar=1
    bootpar=2
    rootpar=3


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
    mkfs.vfat -F32 "/dev/${disk}${p}${efipar}"
    mkfs.ext4 "/dev/${disk}${p}${bootpar}"
    mkfs.btrfs "/dev/${disk}${p}${rootpar}"

    echo "Formatting is done successfully."
    sleep 2
    clear
    echo "The script will automatically proceed in the installer, choose the disks for /, /boot, /boot/efi without formatting and don't reboot after, but exit the installer."
    sleep 15
    void-installer
}


# If user chose to not format.
doNotFormat()
{
    clear
    echo "Make sure to have 3 partiitons for your void installer, a FAT32 recommended 256MiB for your efi, a ext4 recommended 1GiB for your boot, a btrfs one for your root."
    sleep 15
    void-installer
    clear
    lsblk -f
    read -p "What is your root partition's number (if \"sda1\" then type \"1\", if \"nvme0n1p3\" then type \"3\" and so on): " rootpar
    read -p "What is your boot partition's number: " bootpar
    read -p "What is your efi partition's number: " efipar
}


# See installation method preferred by user.
while true; do
    read -rp "Format the entire disk? [y/n] (other answers will stop the script): " answer
    case "$answer" in
        [Yy])
            partitionAndFormat
            break
            ;;
        [Nn])
            doNotFormat
            break
            ;;
        *)
            echo "Invalid input, exiting the script."
            exit 1
            ;;
    esac
done


# Mount the new root.
cd /
umount -R /mnt/* 2>/dev/null
umount -R /mnt 2>/dev/null
rm -rf /mnt/* 2>/dev/null
mount /dev/${disk}${p}${rootpar} /mnt

# Move its content to a subvolume.
btrfs subvolume create /mnt/@
mv /mnt/* /mnt/@ 2>/dev/null

# Create another home subvolume.
btrfs subvolume create /mnt/@home
mv /mnt/@/home/* /mnt/@home
echo "Data moved to subvolumes successfully."
sleep 2


# Setup /etc/fstab.
uuid_efi=$(blkid -s UUID -o value /dev/${disk}${p}${efipar})
uuid_boot=$(blkid -s UUID -o value /dev/${disk}${p}${bootpar})
uuid_root=$(blkid -s UUID -o value /dev/${disk}${p}${rootpar})

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

mount "/dev/${disk}${p}${rootpar}" /mnt -o subvol=@
mount "/dev/${disk}${p}${rootpar}" /mnt/home -o subvol=@home
mount "/dev/${disk}${p}${bootpar}" /mnt/boot
mount "/dev/${disk}${p}${efipar}" /mnt/boot/efi

mount -t proc /proc /mnt/proc
mount --rbind /dev /mnt/dev
mount --make-rslave /mnt/dev
mount --rbind /sys /mnt/sys
mount --make-rslave /mnt/sys


# Chroot and install grub.
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
