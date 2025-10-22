# void-btrfs-script
A script that installs VoidLinux with BTrFS, as the default installer drops all files in the main volume without respecting BTrFS features.  
This script moves data for you to newly created subvolumes, it creates @ and @home by default, edits fstab, reinstalls grub to respect new filesystem.  
Currently it is made only for efi systems.
