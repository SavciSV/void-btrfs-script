# void-btrfs-script
A script to install void-linux with btrfs, as the default installer drops all files in the main volume without respecting btrfs features, this script moves data for you to newly created subvolumes, it creates @ and @home by default, edits fstab, reinstalls grub to respect new filesystem, made only for efi systems, needs a whole disk currently.
