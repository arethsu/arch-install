#!/usr/bin/env bash

###
# Arch Linux Installation
###
# * Installing and configuring ZFS? LTS?
# * How to configure a static address with systemd?
# * `/etc/hosts` is empty due to a bug in Arch
# * Perl throws a locale error during installation
# * `timedatectl set-ntp true` doesn't work inside `arch-chroot`, while `systemctl enable systemd-timesyncd` does, why?
# * Are there additional updates after `pacstrap /mnt base base-devel`? Is `pacman -Syu` recommended before install?
# * How to install and configure themes? `arc-gtk-theme` for example
# * Does the open source video driver have config options?
###

# ls /usr/share/kbd/keymaps/**/*.map.gz | grep sv
loadkeys sv-latin1

# This is done to set the hardware clock before installation
# NOTE: This will not enable the NTP service for the installed system, you'll have to do that later
timedatectl set-ntp true && hwclock --systohc

# Find block devices and partition them
fdisk -l && fdisk /dev/sda

# 1. 1M BIOS boot (GRUB init)
# 2. 2G Linux swap (should always be less than 2xRAM)
#   * <1G RAM -> RAM or greater
#   * >1G RAM (with hibernation) -> RAM or greater
#   * >1G RAM (without hibernation) -> round(sqrt(RAM)) or greater
# 3. [∞]G Linux filesystem at `/`

# fdisk has no flags to disable interactive mode, but we can use this simple hack
echo "g\nn\n\n\n+1M\nt\n4\nn\n\n\n+2G\nt\n\n19\nn\n\n\n\np\nw\n" | fdisk /dev/sda

# Make new filesystems, assign labels, and mount them all
# TODO: Make a script to `mkfs` block devices in bulk. All in one command. Example:
#       `mkfs.ext4 -L a1 /dev/sda1 -L a2 /dev/sda2 [...]`
mkswap -L p_swap /dev/sda2 && mkfs.ext4 -L p_root /dev/sda3
swapon -L p_swap && mount -L p_root /mnt

# Download a `/etc/pacman.d/mirrorlist`, backup, and replace the old one
# TODO: Make a script to backup and replace/modify a file (`.old`). Example:
#       `echo "LANG=en_US.UTF-8" | bar /etc/locale.conf`
#       `genfstab -L /mnt | bar -a /mnt/etc/fstab`
cp /etc/pacman.d/mirrorlist{,.old} && cat <<EOF > /etc/pacman.d/mirrorlist
## Sweden
Server = https://ftp.lysator.liu.se/pub/archlinux/$repo/os/$arch
Server = https://ftp.acc.umu.se/mirror/archlinux/$repo/os/$arch
Server = https://ftp.myrveln.se/pub/linux/archlinux/$repo/os/$arch

# Denmark
Server = https://mirrors.dotsrc.org/archlinux/$repo/os/$arch

## United States
Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch
EOF

# Install the system
# TODO: Install more base stuff here? `intel-ucode`? Video drivers?
pacstrap /mnt base base-devel

# Generate a file systems table based on mounted devices (`-L`ables or `-U`UIDs)
genfstab -L /mnt >> /mnt/etc/fstab

# Change root to new system and continue install
arch-chroot /mnt

bootctl install

# Install GRUB to disk and generate GRUB config
# Install `os-prober` for multiple OS
pacman -S grub && grub-install /dev/sda && grub-mkconfig -o /boot/grub/grub.cfg

# Configure system locale and console keymap
# TODO: Does `LANG` work, or do I still get warnings?
cp /etc/locale.gen{,.old} && echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen && locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf && echo 'KEYMAP=sv-latin1' > /etc/vconsole.conf

# Configure the system-wide timezone
ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime

# Enable NTP
systemctl enable systemd-timesyncd

# Make sure DHCP works on next boot
# NOTE: Don't start with `--now`, DHCP is running from USB at the moment
systemctl enable dhcpcd

cat <<EOF > /etc/systemd/resolved.conf
[Resolve]
DNS=192.168.1.1
FallbackDNS=1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4
EOF

systemctl enable systemd-resolved

cat <<EOF > /etc/systemd/network/50-wired.network
[Match]
MACAddress=XXX

[Network]
Address=192.168.1.10/24
Gateway=192.168.1.1
EOF

systemctl enable systemd-networkd

# Set hostname, configure hosts, and DNS resolver
echo 'sakura' > /etc/hostname
echo '127.0.1.1	sakura.localdomain	sakura' >> /etc/hosts

# TODO: Does the system generate a default conf from DHCP?
nano /etc/resolv.conf
cat <<EOF >> /etc/resolv.conf
nameserver sensei.localdomain
nameserver 8.8.8.8
EOF

# Uncomment `%wheel ALL=(ALL) ALL` to allow wheel users to `su root` and run commands with sudo
# Uncomment `%sudo ALL=(ALL) ALL` to allow sudo users to run commands with sudo
# `visudo` ensures there are no errors
EDITOR=nano visudo

# Add default user with, home, groups, shell, and username
# Default shell is `/bin/bash` if `-s` is omitted (`useradd -D` to see defaults)
# NOTE: `-g` was not included. The system will create a default initial group with the same name as the user
# NOTE: `-s`was not included. Bash will be added as default
useradd -m -G wheel arethsu && passwd arethsu

# Disable root login (SSH still accepted, disable in SSH config)
# TODO: Change root password before disable?
passwd -l root

exit
umount -R /mnt && reboot

# Uncomment `[multilib]` and `Include` for 32-bit support (ex. Steam or Wine)
nano /etc/pacman.conf
pacman -Sy

# AUR helpers
# Read more: https://wiki.archlinux.org/index.php/AUR_helpers
# Trizen: https://aur.archlinux.org/packages/trizen/
# TODO: How to update a package though `trizen`?
# TODO: How to update `trizen` itself?
# TODO: Remove `trizen` folder after install?
# TODO: Alternative to Trizen? (see Arch Wiki)
git clone https://aur.archlinux.org/trizen.git && cd trizen && makepkg -sic

trizen -S zfs-linux zfs-linux-headers

# Intel microcode updates
# NOTE: AMD gets updates as part of `linux-firmware` which is installed with the system
pacman -S intel-ucode

# Video drivers (for NVIDIA)
# Read more: https://wiki.archlinux.org/index.php/xorg#Driver_installation
# * Open-source (mesa is OpenGL): xf86-video-nouveau mesa lib32-mesa
# * Proprietary: nvidia nvidia-utils lib32-nvidia-utils
#   * Beta drivers (AUR): nvidia-beta nvidia-utils-beta lib32-nvidia-utils-beta
# * Fallback X video driver: xf86-video-vesa
# * For VirtualBox: virtualbox-guest-utils virtualbox-guest-modules-arch
# TODO: Difference between open source video driver and proprietary?
pacman -S xf86-video-nouveau mesa lib32-mesa
pacman -S nvidia nvidia-utils lib32-nvidia-utils
pacman -S xf86-video-vesa

# X server and extras
pacman -S xorg-server xorg-xinit xorg-apps

# Fonts
# TODO: Read about font rendering
# TODO: Check font smoothing for terminal
# TODO: How to configure default fonts?
pacman -S ttf-ubuntu-font-family noto-fonts

# TODO: Check `plasma-meta` for things you want
# TODO: Compare different image viewers
pacman -S plasma-desktop plasma-pa konsole dolphin ark eom

# Audio and video
# * https://wiki.archlinux.org/index.php/PulseAudio
# * https://wiki.archlinux.org/index.php/Advanced_Linux_Sound_Architecture
# * https://wiki.archlinux.org/index.php/Mpv
pacman -S pulseaudio pulseaudio-alsa alsa-utils mpd ncmpcpp flac ffmpeg mpv youtube-dl

# `mpd` clients
# * https://github.com/abarisain/dmix
pacman -S gmpc ario sonata

# Base install with GUI applications, like editors
# TODO: How to configure `nftables`?
# TODO: How to enable `syncthing` with `systemctl`?
pacman -S zsh tmux openssh nftables git syncthing sshfs htop

# Start systemd SSH service? How?
# https://wiki.archlinux.org/index.php/Secure_Shell#Daemon_management
systemctl enable --now sshd

# Generate a new SSH key
# TODO: Other newer safer key types?
ssh-keygen -t rsa -b 4096

# Adds your public key to the remote user's `authorized_keys` file
ssh-copy-id username@hostname

# Configure SSH to disallow root login
# Uncomment `# PermitRootLogin yes` and change to `no`
# NOTE: SSH daemon will not auto start unless you tell it to. This is for future security, if you enable it
nano /etc/ssh/sshd_config || echo 'PermitRootLogin no' >> /etc/ssh/sshd_config
# TODO: Restart SSH agent

# Text editors
# * https://www.sublimetext.com/docs/3/linux_repositories.html

# Web and entertainment
# * https://www.mozilla.org/en-US/firefox/nightly/all/
# * https://www.chromium.org/getting-involved/dev-channel
# * https://www.teamspeak.com/en/downloads.html#client
# * https://desktop.telegram.org/changelog#alpha-version
pacman -S weechat

# Configure keyboard and mouse
# NOTE: Wiki article is outdated, `xf86-input-libinput` is the new driver. Read `xorg.conf(5)` and `libinput(4)`
# NOTE: Arch places its X config in `/usr/share/X11/xorg.conf.d` for some reason. `/etc/X11/xorg.conf.d` elsewhere
# NOTE: It seems `Option "AccelProfile" "flat"` is all that's needed. Feels like it at least
# NOTE: There is no auto scroll, and changing scroll speed is not possible...
# TODO: `MatchIsKeyboard "on"` vs. `MatchIsPointer "yes"`?
# * https://wiki.archlinux.org/index.php/Mouse_acceleration#Mouse_speed_with_libinput
cp /usr/share/X11/xorg.conf.d/40-libinput.conf{,.old} && cat <<EOF > /usr/share/X11/xorg.conf.d/40-libinput.conf
Section "InputClass"
        Identifier "libinput keyboard catchall"
        MatchIsKeyboard "on"
        MatchDevicePath "/dev/input/event*"
        Driver "libinput"
        Option "XkbLayout" "se"
EndSection

Section "InputClass"
        Identifier "libinput pointer catchall"
        MatchIsPointer "on"
        MatchDevicePath "/dev/input/event*"
        Driver "libinput"
        Option "AccelProfile" "flat"
        Option "AccelSpeed" "-1"
        Option "ScrollMethod" "button"
        Option "ScrollButton" "2"
EndSection
EOF

echo 'exec startkde' > $HOME/.xinitrc && startx

# (tmux) (ufw) (git) openjdk-8-jdk-headless
# https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar
# ruby and python: autoconf bison build-essential libbz2-dev libffi-dev libgdbm-dev libncurses5-dev libreadline-dev libsqlite3-dev libssl-dev libyaml-dev llvm (xz-utils) zlib1g-dev
# npm: yarn
# mastodon: pkg-config nginx certbot libidn11-dev redis postgresql postgresql-contrib libpq-dev imagemagick ffmpeg libprotobuf-dev protobuf-compiler libicu-dev

# locale and bashrc, set git config, ruby python

sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"

# Programming languages
git clone https://github.com/rbenv/rbenv.git $HOME/.rbenv
git clone https://github.com/rbenv/ruby-build.git $RBENV_ROOT/plugins/ruby-build

git clone https://github.com/pyenv/pyenv.git $HOME/.pyenv

curl https://sh.rustup.rs -sSf | sh
cargo install exa ripgrep bat fd-find genact gifski oxipng diskus termimage

# DON'T FORGET TO CLONE YOUR DOTFILES!


# THE AREA BELOW IS A WORK IN PROGRESS

# QEMU with KVM and network bridge
# TODO: Run with multiple images, such as swap

# QEMU wiki, gentoo, and arch, all have great info

qemu-img create system.img 5G


# Boot order drives:
#   * a, b: floppy 1 and 2
#   * c: first hard disk (default)
#   * d: first cd-rom
-boot

to use virtio, the guest kernel must support it, arch comes with it, but add
MODULES="virtio virtio_net" to /etc/mkinitcpio.conf for basic load of virtio ("virtio_blk virtio_pci")

USB mouse support

-usb -device usb-tablet
-usbdevice tablet

-vga std??

mount guest image to host
mount running guest to host

# Create a VM with ethernet bridge

-cpu <CPU> - Specify a processor architecture to emulate. To see a list of supported architectures, run: qemu-system-x86_64 -cpu ?
-cpu host - (Recommended) Emulate the host processor.
-smp <NUMBER> - Specify the number of cores the guest is permitted to use. The number can be higher than the available cores on the host system.
-hda IMAGE.img - Set a virtual hard drive and use the specified image file for it.
-drive - Advanced configuration of a virtual hard drive:
    -drive file=IMAGE.img,if=virtio - Set a virtual VirtIO hard drive and use the specified image file for it.
-k LAYOUT - Set the keyboard layout, e.g. de for german keyboards. Recommend for VNC connections.

Default - without any -net option - is Pass-through.
-net user - Pass-through of the host network connection. However, the virtual machine is no member of the LAN and so can't use any local network service and can't communicate to any other virtual machine.
-netdev user,id=vmnic -device virtio-net,netdev=vmnic - (Recommended) Pass-through with VirtIO support.


qemu-img create system.img 25G
# nic ifname empty? OS provides one
# nic model is default e1000

# qemu-system-x86_64 -nic help
# qemu-system-x86_64 -nic model=help
# script=no,downscript=no provides a script file to start and stop the tap interface, but in this example, no

# "-cpu": What's the default?
# "-drive" and "-hda": "-hda" is a shortcut for "-drive file=system.img". What's the default "if" (interface)?
# "-net": Depricated/considered obsolete as of QEMU 0.12.
# "-nic" and "-netdev": What's the difference between user, bridge, and tap? What's the default "ifname" (interface name)?
qemu-system-x86_64 -enable-kvm \
    -cpu host \
    -m 2G
    -drive file=system.img,format=raw,if=virtio \

    -nic tap,[ifname=tap0],script=no,downscript=no,model=virtio-net-pci \
    -nic user,model=virtio-net-pci \

    -monitor [stdio (non graphical mode) | vc (graphical mode) ] \
    -name "Arch Linux VM"

-m 2G -cdrom iso_image -boot order=d -drive file=disk_image,format=raw [-hda system-image.img]? -net nic,model=virtio
