#!/usr/bin/env bash

# Target device
device="/dev/nvme1n1"
device_root="/dev/nvme1n1p3"

# Packages to install
pkgs="$(<"pkgs.txt")"

# AUR packages to install
aurs="$(<"aurs.txt")"

# Country for mirrorlist retrieval
country="DE"

# Sudo user of the system
user="yagiza"

# Hostname of the system
hostname="artheus"

# Time Zone
timezone="Europe/Berlin"

# Dotfile Repo to use
dotfiles="https://github.com/aynsoph/dotfiles"
