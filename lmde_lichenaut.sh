#!/bin/bash

# Exit on fail
set -e

# GitHub Release downloading
install_latest_deb() {
    REPO=$1
    FILE_PATTERN=$2
    LATEST_URL=$(wget -qO- "https://api.github.com/repos/$REPO/releases/latest" | jq -r ".assets[] | select(.name | test(\"$FILE_PATTERN\")) | .browser_download_url" | head -n 1)
    if [[ -z "$LATEST_URL" ]]; then
        echo "Could not find the latest .deb package URL for $REPO."
        exit 1
    fi
    wget "$LATEST_URL" -O /tmp/latest.deb
    sudo gdebi /tmp/latest.deb -n
    rm /tmp/latest.deb
}

# Web App Creating
APP_DIR="$HOME/.local/share/applications"
mkdir -p "$APP_DIR"
create_webapp() {
  local app_name=$1
  local app_url=$2
  local app_icon=$3
  local app_file="$APP_DIR/$app_name.desktop"
  cat <<EOF > "$app_file"
[Desktop Entry]
Version=1.0
Name=$app_name
Comment=Web app for $app_name
Exec=xdg-open $app_url
Icon=$app_icon
Terminal=false
Type=Application
Categories=Internet;WebBrowser;
EOF
  chmod +x "$app_file"
}

# Browser GPU preferencing
update_pref_js() {
    local base_dir=$1
    for profile_dir in $base_dir; do
        if [[ -d "$profile_dir" ]]; then
            echo "user_pref(\"layers.acceleration.force-enabled\", true);
user_pref(\"gfx.webrender.all\", true);" > "$profile_dir/user.js"
        fi
    done
}

# Autostart creating
create_autostart_entry() {
    local app_name="$1"
    local exec_command="$2"
    local icon="$3"
    local file_name="$4"
    local autostart_dir="$HOME/.config/autostart"
    local desktop_file="$autostart_dir/$file_name.desktop"
    mkdir -p "$autostart_dir"
    if [[ ! -f "$desktop_file" ]]; then
        echo "[Desktop Entry]
Name=$app_name
GenericName=$app_name
Comment=Autostart entry for $app_name
Exec=$exec_command
Icon=$icon
Terminal=false
Type=Application
Categories=Utility;
X-GNOME-Autostart-enabled=true
NoDisplay=false
Hidden=false
X-GNOME-Autostart-Delay=0" > "$desktop_file"
    fi
}

# Cinnamon configurating
update_cinnamon_config() {
    local CONFIG_DIR="$1"
    local JQ_FILTER="$2"
    if [[ ! -d "$CONFIG_DIR" ]]; then
        echo "$CONFIG_DIR not found!"
        return 1
    fi
    for FILE in "$CONFIG_DIR"/*.json; do
        [[ -f "$FILE" ]] || continue
        jq "$JQ_FILTER" "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE" || {
            echo "Failed to update $FILE"
            return 1
        }
    done
}

# Disclaimer
echo "This script assumes the user has connected to the internet and completed the installation and welcome GUIs for LMDE. Press Enter to continue..."
read continue

# Quad9
DNS_SERVERS_IPV4="9.9.9.9 149.112.112.112"
DNS_SERVERS_IPV6="2620:fe::fe 2620:fe::9"
CONNECTION_NAME=$(nmcli -t -f NAME,DEVICE connection show --active | grep -E -v "lo|docker0" | awk -F: '{print $1}' | head -n 1)
if [[ -z "$CONNECTION_NAME" ]]; then
    echo "No active network connection found."
    exit 1
fi
sudo nmcli connection modify "$CONNECTION_NAME" ipv4.dns "$DNS_SERVERS_IPV4"
sudo nmcli connection modify "$CONNECTION_NAME" ipv4.ignore-auto-dns yes
sudo nmcli connection modify "$CONNECTION_NAME" ipv6.dns "$DNS_SERVERS_IPV6"
sudo nmcli connection modify "$CONNECTION_NAME" ipv6.ignore-auto-dns yes
sudo nmcli connection up "$CONNECTION_NAME"

# OpenRazer
echo 'deb http://download.opensuse.org/repositories/hardware:/razer/Debian_12/ /' | sudo tee /etc/apt/sources.list.d/hardware:razer.list
curl -fsSL https://download.opensuse.org/repositories/hardware:razer/Debian_12/Release.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/hardware_razer.gpg > /dev/null

# APT
sudo apt update -y && sudo apt install -y python3-pip nodejs vlc webcord vim sqlitebrowser openrazer-meta razergenie cups hplip htop codium krita keepassxc kdenlive guake git podman jq nvidia-driver preload tlp tlp-rdw
sudo systemctl enable --now cups

# Flathub
flatpak install -y app/io.gitlab.librewolf-community/x86_64/stable app/org.telegram.desktop/x86_64/stable app/com.valvesoftware.Steam/x86_64/stable com.jetbrains.IntelliJ-IDEA-Community com.usebottles.bottles us.zoom.Zoom app/com.obsproject.Studio/x86_64/stable

# Qemu
sudo apt install -y qemu-kvm libvirt-daemon-system virt-manager bridge-utils
sudo systemctl enable --now libvirtd

# GitHub
install_latest_deb "ThaUnknown/miru" "linux-Miru.*deb"
install_latest_deb "VSCodium/vscodium" ".*amd64.deb"
install_latest_deb "KRTirtho/spotube" ".*x86_64.deb"

# Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
. "$HOME/.cargo/env"

# Postman
DEST_DIR="$HOME/Documents"
ARCHIVE="$DEST_DIR/postman.tar.gz"
mkdir -p "$DEST_DIR"
wget -O "$ARCHIVE" "https://dl.pstmn.io/download/latest/linux_64"
tar -xzf "$ARCHIVE" -C "$DEST_DIR"
rm "$ARCHIVE"

# ADB and fastboot
curl -o /tmp/platform-tools.zip "https://dl.google.com/android/repository/platform-tools-latest-linux.zip"
unzip -o /tmp/platform-tools.zip -d "$HOME/adb-fastboot"
PROFILE_FILE="$HOME/.profile"
if ! grep -q 'platform-tools' "$PROFILE_FILE"; then
    echo -e '\n# Add ADB & Fastboot to PATH' >> "$PROFILE_FILE"
    echo 'if [ -d "$HOME/adb-fastboot/platform-tools" ] ; then' >> "$PROFILE_FILE"
    echo '    export PATH="$HOME/adb-fastboot/platform-tools:$PATH"' >> "$PROFILE_FILE"
    echo 'fi' >> "$PROFILE_FILE"
fi
rm /tmp/platform-tools.zip

# Web Apps
create_webapp "Microsoft Teams" "https://teams.microsoft.com/v2/" "web-microsoft"
create_webapp "Twitter" "https://twitter.com" "twitter"
create_webapp "GitHub" "https://github.com" "github"

# Debloat
sudo apt purge -y baobab celluloid drawing gnome-calendar gnome-logs gnome-power-manager gnote hexchat hypnotix nano onboard pix rhythmbox seahorse simple-scan thunderbird transmission-gtk warpinator xreader

# Browser
update_pref_js "$HOME/.mozilla/firefox/*.default-release"
update_pref_js "$HOME/.var/app/io.gitlab.librewolf-community/.librewolf/*.default-default"

# GRUB
sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' "/etc/default/grub"
sudo sed -i 's/^#GRUB_GFXMODE=.*/GRUB_GFXMODE=1920x1080/' "/etc/default/grub"
sudo update-grub

# Startup Applications
create_autostart_entry "Redshift" "redshift-gtk" "redshift" "redshift-gtk"
create_autostart_entry "Guake Terminal" "guake" "guake" "guake"
create_autostart_entry "Update Manager" "mintupdate-launcher" "mintupdate" "mintupdate"
sudo sed -i 's/^X-GNOME-Autostart-enabled=.*/X-GNOME-Autostart-enabled=false/' "$HOME/.config/autostart/mintupdate.desktop"

# Default Applications
echo "[Default Applications]
application/octet-stream=org.keepassxc.KeePassXC.desktop
x-scheme-handler/http=io.gitlab.librewolf-community.desktop
x-scheme-handler/https=io.gitlab.librewolf-community.desktop
x-scheme-handler/postman=Postman.desktop
audio/*=vlc.desktop
video/*=vlc.desktop
application/pdf=io.gitlab.librewolf-community.desktop
application/javascript=codium.desktop
application/x-httpd-php3=codium.desktop
application/x-httpd-php4=codium.desktop
application/x-httpd-php5=codium.desktop
application/x-m4=codium.desktop
application/x-php=codium.desktop
application/x-ruby=codium.desktop
application/x-shellscript=codium.desktop
application/xml=codium.desktop
text/*=codium.desktop
text/css=codium.desktop
text/turtle=codium.desktop
text/x-c++hdr=codium.desktop
text/x-c++src=codium.desktop
text/x-chdr=codium.desktop
text/x-csharp=codium.desktop
text/x-csrc=codium.desktop
text/x-diff=codium.desktop
text/x-dsrc=codium.desktop
text/x-fortran=codium.desktop
text/x-java=codium.desktop
text/x-makefile=codium.desktop
text/x-pascal=codium.desktop
text/x-perl=codium.desktop
text/x-python=codium.desktop
text/x-sql=codium.desktop
text/x-vb=codium.desktop
text/yaml=codium.desktop

[Added Associations]
application/octet-stream=org.keepassxc.KeePassXC.desktop
x-scheme-handler/http=io.gitlab.librewolf-community.desktop;firefox.desktop
audio/*=vlc.desktop
application/pdf=io.gitlab.librewolf-community.desktop;libreoffice-draw.desktop
video/*=vlc.desktop" > ~/.config/mimeapps.list

# Cinnamon tweaks
update_cinnamon_config "$HOME/.config/cinnamon/spices/calendar@cinnamon.org" \
    '.["show-week-numbers"].value = true |
    .["use-custom-format"].value = true |
    .["custom-format"].value = "%A %B %e, %H:%M" |
    .["custom-tooltip-format"].value = "%A %B %e, %H:%M"'
update_cinnamon_config "$HOME/.config/cinnamon/spices/grouped-window-list@cinnamon.org" \
    '.["pinned-apps"].value = [
            "nemo.desktop",
            "io.gitlab.librewolf-community.desktop:flatpak",
            "codium.desktop",
            "webcord.desktop",
            "spotube.desktop"
        ] |
        .["pinned-apps"].default = [
            "nemo.desktop",
            "io.gitlab.librewolf-community.desktop:flatpak",
            "codium.desktop",
            "webcord.desktop",
            "spotube.desktop"
        ]'
gsettings set org.cinnamon.desktop.interface enable-animations false
gsettings set org.cinnamon desktop-effects-workspace false
gsettings set org.cinnamon enabled-applets "['panel1:right:7:calendar@cinnamon.org:29', 'panel1:left:1:grouped-window-list@cinnamon.org:34', 'panel1:left:0:menu@cinnamon.org:37', 'panel1:right:4:network@cinnamon.org:38', 'panel1:right:3:printers@cinnamon.org:39', 'panel1:right:0:removable-drives@cinnamon.org:40', 'panel1:right:1:systray@cinnamon.org:41', 'panel1:right:0:xapp-status@cinnamon.org:42']"
gsettings set org.cinnamon.desktop.sound event-sounds false
gsettings set org.cinnamon.desktop.sound theme-name "none"
dconf write /org/cinnamon/panels-enabled "['1:0:top']"

# Housekeeping
sudo apt upgrade -y && sudo apt autoremove -y && sudo apt clean -y
source ~/.bashrc
source ~/.profile
cinnamon --replace > /dev/null 2>&1 &

# Flavor
neofetch

# Reboot?
read -p "Reboot now? (y/N): " REBOOT_CHOICE
case "$REBOOT_CHOICE" in
  y|Y ) echo "Rebooting..."; sudo reboot;;
  * ) echo "Reboot canceled.";;
esac

# web apps: (auto-download icons?)
# teams
# outlook
# tuta
# protonm
# venice

# fl studio in bottles