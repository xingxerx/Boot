#!/bin/bash

# Arch Linux Dual-Boot Installation Script (Interactive)
# Tailored for ASUS ROG Strix Scar 15 (2021) with AMD Ryzen 9 5900HX & NVIDIA RTX 3080
# This script automates steps but requires significant user interaction and confirmation.
# ALWAYS BACK UP YOUR DATA BEFORE PROCEEDING!

echo "======================================================="
echo "  Arch Linux Dual-Boot Installation Script (Interactive)"
echo "======================================================="
echo "This script will guide you through installing Arch Linux alongside Windows 10."
echo "It requires manual intervention for critical steps like partitioning and editing."
echo ""
echo "!!! WARNING: This process can lead to DATA LOSS if not followed carefully. !!!"
echo "!!!          BACK UP ALL YOUR IMPORTANT DATA NOW!                           !!!"
echo ""
echo "Ensure you have already:"
echo "  - Disabled Fast Startup and Hibernation in Windows 10."
echo "  - Disabled Secure Boot in your BIOS/UEFI settings."
echo "  - Created unallocated free space on your SSD for Arch Linux."
echo "  - Created a bootable Arch Linux USB drive."
echo ""
read -p "Press Enter to begin, or Ctrl+C to exit."

# --- 1. Pre-Installation Configuration ---
echo "--- 1. Pre-Installation Configuration ---"

echo "Verifying Boot Mode (should show directory listing for UEFI)..."
ls /sys/firmware/efi/efivars || { echo "ERROR: Not in UEFI mode. Please reconfigure BIOS/UEFI."; exit 1; }
echo "UEFI mode verified."
read -p "Press Enter to continue..."

echo "Connecting to the Internet..."
read -p "Are you using Wired (Ethernet) or Wireless (Wi-Fi)? (wired/wireless): " NETWORK_TYPE

if [[ "$NETWORK_TYPE" == "wireless" ]]; then
    echo "Starting iwctl for Wi-Fi configuration..."
    echo "Please use 'device list', 'station <device> scan', 'station <device> get-networks', 'station <device> connect <SSID>'."
    echo "Type 'exit' when done."
    iwctl
    read -p "Enter your Wi-Fi device name (e.g., wlan0, wlp3s0): " WIFI_DEVICE_NAME
    read -p "Enter your Wi-Fi SSID (network name): " WIFI_SSID
    echo "Attempting to connect to Wi-Fi. You will be prompted for password if needed."
    iwctl station "$WIFI_DEVICE_NAME" connect "$WIFI_SSID" || { echo "ERROR: Wi-Fi connection failed. Please check manually."; exit 1; }
else
    echo "Assuming wired connection. Testing..."
fi

echo "Testing internet connection..."
ping -c 3 google.com || { echo "ERROR: Internet connection failed. Please troubleshoot manually."; exit 1; }
echo "Internet connection verified."
read -p "Press Enter to continue..."

echo "Updating system clock..."
timedatectl set-ntp true
echo "System clock synchronized."
read -p "Press Enter to continue..."

# --- 2. Partition the Disk ---
echo "--- 2. Partition the Disk ---"
echo "Identifying your disk. Look for your main NVMe drive (e.g., /dev/nvme0n1)."
lsblk
read -p "Enter your main disk name (e.g., nvme0n1, sda): " DISK_NAME
DISK_PATH="/dev/$DISK_NAME"

echo "Starting cfdisk to partition the disk."
echo "You MUST manually create partitions in the unallocated space:"
echo "  - EFI System Partition (ESP): Either share existing Windows ESP (recommended) or create new 512MB."
echo "  - Swap Partition: 16G or 32G (for hibernation)."
echo "  - Root Partition (/): Significant portion of remaining space (50G-100G+)."
echo "  - Home Partition (Optional): Rest of the space."
echo "Remember to 'Write' changes and 'Quit' when done."
read -p "Press Enter to launch cfdisk. After partitioning, press Enter again to continue this script."
cfdisk "$DISK_PATH"
read -p "cfdisk completed. Press Enter to continue..."

echo "Please list your partitions again to note down the new partition names and Windows EFI partition."
lsblk
read -p "Enter the full path to your ROOT partition (e.g., /dev/nvme0n1p3): " ROOT_PARTITION
read -p "Enter the full path to your SWAP partition (e.g., /dev/nvme0n1p4): " SWAP_PARTITION
read -p "Enter the full path to your EFI System Partition (e.g., /dev/nvme0n1p1 if sharing Windows, or /dev/nvme0n1p2 if new): " EFI_PARTITION
read -p "Do you have a separate HOME partition? (yes/no): " HAS_HOME
if [[ "$HAS_HOME" == "yes" ]]; then
    read -p "Enter the full path to your HOME partition (e.g., /dev/nvme0n1p5): " HOME_PARTITION
fi

# --- 3. Format the Partitions ---
echo "--- 3. Format the Partitions ---"
echo "Formatting partitions..."
mkfs.ext4 "$ROOT_PARTITION" || { echo "ERROR: Failed to format root partition."; exit 1; }
mkswap "$SWAP_PARTITION" || { echo "ERROR: Failed to format swap partition."; exit 1; }
swapon "$SWAP_PARTITION" || { echo "ERROR: Failed to enable swap."; exit 1; }
mkfs.fat -F32 "$EFI_PARTITION" || { echo "ERROR: Failed to format EFI partition."; exit 1; } # This will reformat even if shared, which is generally safe but user should be aware.
if [[ "$HAS_HOME" == "yes" ]]; then
    mkfs.ext4 "$HOME_PARTITION" || { echo "ERROR: Failed to format home partition."; exit 1; }
fi
echo "Partitions formatted."
read -p "Press Enter to continue..."

# --- 4. Mount the Partitions ---
echo "--- 4. Mount the Partitions ---"
echo "Mounting partitions..."
mount "$ROOT_PARTITION" /mnt || { echo "ERROR: Failed to mount root partition."; exit 1; }
mkdir -p /mnt/boot/efi || { echo "ERROR: Failed to create /mnt/boot/efi."; exit 1; }
mount "$EFI_PARTITION" /mnt/boot/efi || { echo "ERROR: Failed to mount EFI partition."; exit 1; }
if [[ "$HAS_HOME" == "yes" ]]; then
    mkdir -p /mnt/home || { echo "ERROR: Failed to create /mnt/home."; exit 1; }
    mount "$HOME_PARTITION" /mnt/home || { echo "ERROR: Failed to mount home partition."; exit 1; }
fi
echo "Partitions mounted."
read -p "Press Enter to continue..."

# --- 5. Install Arch Linux Base System ---
echo "--- 5. Install Arch Linux Base System ---"
echo "Installing base system, Linux kernel, firmware, and microcode for your Ryzen CPU..."
pacstrap /mnt base linux linux-firmware amd-ucode nano vim || { echo "ERROR: pacstrap failed."; exit 1; }
echo "Base system installed."
read -p "Press Enter to continue..."

echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab || { echo "ERROR: genfstab failed."; exit 1; }
echo "Verifying fstab content. Please review carefully:"
cat /mnt/etc/fstab
read -p "Press Enter to continue after reviewing fstab..."

# --- 6. Configure the New System (chroot) ---
echo "--- 6. Configure the New System (chroot) ---"
echo "Entering chroot environment..."
arch-chroot /mnt /bin/bash <<EOF_CHROOT_SCRIPT

echo "Setting timezone..."
read -p "Enter your Region/City for timezone (e.g., America/New_York): " TIMEZONE_REGION_CITY
ln -sf /usr/share/zoneinfo/"$TIMEZONE_REGION_CITY" /etc/localtime || { echo "ERROR: Failed to set timezone."; exit 1; }
hwclock --systohc || { echo "ERROR: Failed to synchronize hardware clock."; exit 1; }
echo "Timezone set."

echo "Configuring localization (locale)..."
echo "Uncomment 'en_US.UTF-8 UTF-8' in /etc/locale.gen using nano. Save and exit."
read -p "Press Enter to open nano. After editing, press Enter again to continue."
nano /etc/locale.gen
locale-gen || { echo "ERROR: Failed to generate locales."; exit 1; }
echo "LANG=en_US.UTF-8" > /etc/locale.conf || { echo "ERROR: Failed to create locale.conf."; exit 1; }
echo "Localization configured."

echo "Configuring network..."
read -p "Enter your desired hostname (e.g., myasusrog): " HOSTNAME
echo "$HOSTNAME" > /etc/hostname || { echo "ERROR: Failed to set hostname."; exit 1; }
echo "127.0.0.1       localhost" > /etc/hosts
echo "::1             localhost" >> /etc/hosts
echo "127.0.1.1       $HOSTNAME.localdomain    $HOSTNAME" >> /etc/hosts || { echo "ERROR: Failed to update /etc/hosts."; exit 1; }
echo "Network configuration done."

echo "Setting root password..."
passwd || { echo "ERROR: Failed to set root password."; exit 1; }
echo "Root password set."

echo "Creating a new user..."
read -p "Enter your desired username: " USERNAME
useradd -m -g users -G wheel,storage,power -s /bin/bash "$USERNAME" || { echo "ERROR: Failed to create user."; exit 1; }
passwd "$USERNAME" || { echo "ERROR: Failed to set user password."; exit 1; }
echo "User '$USERNAME' created."

echo "Enabling sudo for the new user..."
echo "You MUST uncomment the line '%wheel ALL=(ALL:ALL) ALL' in /etc/sudoers using visudo. Save and exit."
read -p "Press Enter to open visudo. After editing, press Enter again to continue."
EDITOR=nano visudo || { echo "ERROR: Failed to edit sudoers."; exit 1; }
echo "Sudo enabled for wheel group."

echo "--- 7. Bootloader Installation (GRUB for Dual Boot) ---"
echo "Installing GRUB, efibootmgr, and os-prober..."
pacman -S grub efibootmgr os-prober || { echo "ERROR: Failed to install bootloader packages."; exit 1; }

echo "Installing GRUB to EFI partition..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ArchLinux --recheck || { echo "ERROR: Failed to install GRUB."; exit 1; }

echo "Enabling OS-Prober in GRUB configuration..."
sed -i 's/#GRUB_DISABLE_OS_PROBER=true/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub || { echo "ERROR: Failed to enable OS-Prober in grub config."; exit 1; }

echo "Generating GRUB configuration file..."
grub-mkconfig -o /boot/grub/grub.cfg || { echo "ERROR: Failed to generate GRUB config."; exit 1; }
echo "GRUB configuration generated. Look for 'Found Windows Boot Manager'."

echo "--- 8. Install NVIDIA & AMD Graphics Drivers (Hybrid Graphics) ---"
echo "Installing xorg-server, NVIDIA (dkms), and AMD Mesa drivers..."
pacman -S xorg-server nvidia-dkms nvidia-utils nvidia-settings mesa vulkan-radeon libva-mesa-driver mesa-vdpau linux-headers || { echo "ERROR: Failed to install graphics drivers."; exit 1; }

echo "Configuring mkinitcpio for NVIDIA and AMD modules..."
echo "You MUST edit /etc/mkinitcpio.conf to add 'amdgpu nvidia nvidia_modeset nvidia_uvm nvidia_drm' to the MODULES line."
echo "Example: MODULES=(amdgpu nvidia nvidia_modeset nvidia_uvm nvidia_drm)"
read -p "Press Enter to open nano. After editing, press Enter again to continue."
nano /etc/mkinitcpio.conf
mkinitcpio -P || { echo "ERROR: Failed to regenerate initramfs."; exit 1; }
echo "mkinitcpio configured."

echo "Re-generating GRUB configuration after graphics drivers installation..."
grub-mkconfig -o /boot/grub/grub.cfg || { echo "ERROR: Failed to re-generate GRUB config."; exit 1; }
echo "GRUB config updated."

EOF_CHROOT_SCRIPT

# --- 9. Exit Chroot and Reboot ---
echo "--- 9. Exit Chroot and Reboot ---"
echo "Exiting chroot environment..."
# The EOF_CHROOT_SCRIPT above handles the chroot exit implicitly.
# Now unmount everything from the live environment.
echo "Unmounting partitions..."
umount -R /mnt || { echo "ERROR: Failed to unmount partitions."; exit 1; }
echo "Partitions unmounted."

echo "Installation script complete. Rebooting system in 5 seconds..."
echo "Remove the USB installation media when prompted or when the screen goes black."
sleep 5
reboot
