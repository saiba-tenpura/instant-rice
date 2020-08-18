# Instant-Rice (WIP)

The following configurations are made:
* **Time**:
  * The timezone will be set as defined by `$T_ZONE` for example 'Europe/Berlin'.
  * The **/etc/adjtime** is generated via `hwclock --systohc`.
  * Activates the time synchronisation via ntp.
* **Locale**:
  * Uncomments **en_US.UTF-8** in `/etc/locale.gen`.
  * Generates the locales & sets it in the `/etc/locale.conf`.
* **Keyboard Layout** (Only if country is 'DE'):
  * Creates the `/etc/vconsole.conf` & `/etc/X11/xorg.conf.d/20-keyboard.conf` to use a german keyboard layout.
* **Network**:
  * Sets hostname as defined by `$HOST`.
  * Create basic `/etc/hosts` file.
  * Enable the **NetworkManager.service**.
* **User**:
  * Add user with name as defined by `$USER` and give him sudo privileges.
  * Configure & clone dotfiles for the newly created user.
* **Packaging**:
  * Install AUR Helper (yay) & download packages defined by `$AUR_LIST`.
* **Bootloader**
  * Install refind-efi or grub as bootloader as defined by `$BOOT_LDR`.
