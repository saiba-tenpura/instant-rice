#!/usr/bin/env bash

# Print usage info
usage() {
    cat <<-EOF
	Usage: $(basename "${0}") [options] -d <dev>

	Options:
	-h, --help      Show this help message.
	-c              Perform system configuration.         
	EOF

    exit 1
}

# Check Requirements
check_requirements() {
    # Usage: check_requirements
    local p progs
    progs="arch-chroot curl genfstab grep pacman pacstrap"
    [ $(id -u) = 0 ] || error "Script must be run as root!"
    [ -b "${device}" ] || error "${dev} isn't a block device!"

    # Check required programs
    for p in $progs; do
        type -p "${p}" >/dev/null || error "Missing required executable: ${p}"
    done
}

# Print error & exit
error() {
    # Usage error message
    printf "\e[91mERROR\e[m: ${1}\n" >&2
    exit 2
}

# Print error
info() {
    # Usage info message
    printf "\e[96mINFO\e[m: ${1}\n" >&2
}

# Cleanup
cleanup() {
    rm /mnt/root/{config,install}.sh 2>/dev/null
}

# Configure env
setup_chroot() {
    # Usage: setup_chroot
    local mirrorlist pac_conf

    # Enable 32-Bit support
    pac_conf=$(<"/etc/pacman.conf")
    printf "${pac_conf/\#\[multilib]$'\n'\#Include/[multilib]$'\n'Include}" > /etc/pacman.conf

    # Setup mirrorlist
    mirrorlist=$(curl -s "https://www.archlinux.org/mirrorlist/?country=${country}&protocol=https&use_mirro_status=on")
    printf "${mirrorlist//\#Server/Server}" > /etc/pacman.d/mirrorlist
    pacman -Sy >/dev/null 2>&1

    # Install base environment
    pacstrap /mnt base base-devel linux linux-firmware $pkgs > /dev/null 2>&1

    # Generate fstab
    genfstab -U /mnt >> /mnt/etc/fstab
}

# Configure timesync & timezone
cfg_time() {
    # Usage: cfg_time timezone
    ln -sf "/usr/share/zoneinfo/${1}" /etc/localtime
    hwclock --systohc
    timedatectl set-ntp true
}

# Configure system language
cfg_locale() {
    # Usage: cfg_locale
    local tmp_locale

    tmp_locale=$(<"/etc/locale.gen")
    printf "${tmp_locals//\#en_US.UTF-8/en_US.UTF-8}\n" > /etc/locale.gen
    locale-gen > /dev/null

    printf "LANG=en_US.UTF-8\n" > /etc/locale.conf
}

# Configure keyboard for vconsole & X
cfg_kbd() {
    # Usage: cfg_kbd
    printf "KEYMAP=de-latin1-nodeadkeys\n" > /etc/vconsole.conf

    mkdir -p /etc/X11/xorg.conf.d/
    cat <<-EOF > /etc/X11/xorg.conf.d/20-keyboard.conf
	Section "InputClass"
	    Identifier "keyboard"
	    MatchIsKeyboard "yes"
	    Option "XkbLayout" "de"
	    Option "XkbVariant" "nodeadkeys"
	EndSection
	EOF
}
# Configure hostname, hosts, networkmanager
cfg_network() {
    # Usage: cfg_network hostname
    printf "${1}\n" > /etc/hostname
    printf "%-12s localhost\n" "127.0.0.1" "::1" > /etc/hosts
    systemctl enable NetworkManager.service > /dev/null
}

# Add user & autologin
cfg_user() {
    # Usage: cfg_user user
    useradd -m -s /bin/bash "${1}"

    # Autologin
    mkdir -p /etc/systemd/system/getty@tty1.service.d
    cat <<-EOF > /etc/systemd/system/getty@tty1.service.d/override.conf
	[Service]
	ExecStart=
	ExecStart=-/usr/bin/agetty -a ${1} --noclear %I \$TERM
	EOF
}

# Allow sudo & specific commands
cfg_sudo() {
    # Usage: cfg_sudo user
    local sudo_file

    sudo_file="/etc/sudoers.d/10-${1}"
    printf "${1} ALL=(ALL) ALL\n${1} ALL=(ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/mount,/usr/bin/umount\n" > "${sudo_file}"
    chmod 440 "${sudo_file}"
}

# Configure user dotfiles
cfg_dotfiles() {
    # Usage: cfg_dotfiles user dotfiles
    su - "${1}" <<-EOF
	curl -sO "${2/github/raw.githubusercontent}/master/install.sh"
	chmod 744 install.sh
	./install.sh ${2}
	EOF
}

# AMD gaming configurations
cfg_amd_gaming() {
    # Install Drivers
    pacman -S lib32-mesa vulkan-radeon lib32-vulkan-radeon vulkan-icd-loader lib32-vulkan-icd-loader -y

    # Enable ACO
    printf "RADV_PERFTEST=aco" > /etc/environment
}

# Install AUR & AUR packages
install_aur() {
    # Usage: install_aur user aur_pkgs
    local sudo_file

    sudo_file="/etc/sudoers.d/10-${1}"
    printf "${1} ALL=(ALL) NOPASSWD: ALL" > "${sudo_file}"

    su - "${1}" <<-EOF
    git clone https://aur.archlinux.org/yay.git ~/yay
    (cd ~/yay; makepkg --noconfirm -si > /dev/null 2>&1; rm -rf ~/yay)
    yay --noconfirm -S ${2} > /dev/null 2>&1
	EOF
}

# Install rEFInd as bootloader
install_refind() {
    # Usage: install_refind device
    local uuid

    refind-install
    uuid=$(lsblk -no UUID "${1}3")

    cat <<-EOF > /boot/EFI/refind/refind.conf
	extra_kernel_version_strings linux

	menuentry "Arch Linux" {
	    icon /EFI/refind/icons/os_arch.png
	    loader /vmlinuz-linux
	    initrd /initramfs-linux.img
	    options "root=PARTUUID=${uuid} rw add_efi_memmap initrd=amd-ucode.img"
	    submentry "Boot using fallback initramfs" {
	        initrd /initramfs-linux-fallback.img
	    }
	    submenuentry "Boot to terminal" {
	        add_options "systemd.unit=multi-user.target"
	    }
	}
	EOF

    cat <<-EOF > /boot/refind_linux.conf
	"Boot using default options"    "root=PARTUUID=${uuid} rw add_efi_memmap initrd=amd-ucode.img initrd=/initramfs-%v.img"
	"Boot using fallback initramfs" "root=PARTUUID=${uuid} rw add_efi_memmap initrd=/initramfs-%v-fallback.img"
	"Boot to terminal               "root=PARTUUID=${uuid} rw add_efi_memmap initrd=/initramfs-%v.img systemd.unit=multi-user.target"
	EOF
}

# Install grub as bootloader
install_grub() {
    # Usage: install_grub device
    if [ -d /sys/firmware/efi ]; then
        pacman --noconfirm -S efibootmgr > /dev/null 2>&1
        grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
    else
        grub-install --target=i386-pc "${1}"
    fi

    grub-mkconfig -o /boot/grub/grub.cfg
}

# Configure inside of chroot via library
configure() {
    cfg_time "${time_zone}"
    cfg_locale
    cfg_kbd
    cfg_network "${hostname}"
    cfg_user "${user}"
    cfg_dotfiles "${user}" "${dotfiles}"
    install_aur "${user}" "${aurs}"
    cfg_sudo "${user}"
    cfg_amd_gaming
    install_refind "${device_root}"
    #install_grub "${device}"

    exit 0
}

# Perform full installation
main() {
    # Cleanup on exit
    trap cleanup EXIT INT

    # Check for prerequisits
    info "\nChecking requirements:(1/3)"
    check_requirements

    # Set path to script
    work_dir="$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)"

    info "Setting up mirrors & installing packages:(2/3)"
    setup_chroot

    info "Performing system configuration:(2/3)"
    cp "${work_dir}/{config,install}.sh" /mnt/root/
    arch-chroot /mnt /root/install.sh -c
    rm /mnt/root/{config,install}.sh

    printf "\e[92mInstallation process is done:\e[m Please set passwords for root & ${user}.\n" >&2

    exit 0
}

source config.sh
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            ;;

        -c)
            configure
            ;;
        *)
            error "Unkown option $1 was given."
            shift
            ;;
   esac
done

main "$@"
