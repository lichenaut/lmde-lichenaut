#!/bin/bash

# Exit on fail
set -e

# .desktop file creating
create_desktop_file() {
    NAME=$1
    EXEC=$2
    ICON=$3
    CATEGORIES=$4
    LOWERCASE_FILE_NAME=$(echo "$NAME" | tr '[:upper:]' '[:lower:]')
    if [[ -z $ICON ]]; then
        ICON="application-x-executable"
    fi
    echo "[Desktop Entry]
Type=Application
Name=$NAME
Comment=Start $NAME
Icon=$ICON
Exec=$EXEC
Terminal=false
Categories=$CATEGORIES" | sudo tee "/usr/share/applications/$LOWERCASE_FILE_NAME.desktop" > /dev/null
}

# GitHub release downloading
install_latest_gh() {
    REPO=$1
    FILE_PATTERN=$2
    FILE_TYPE=$3
    FILE_NAME=$4
    LATEST_URL=$(wget -qO- "https://api.github.com/repos/$REPO/releases/latest" | jq -r ".assets[] | select(.name | test(\"$FILE_PATTERN\")) | .browser_download_url" | head -n 1)
    if [[ -z "$LATEST_URL" ]]; then
        echo "Script fatal error: could not find the latest $FILE_TYPE package URL for $REPO."
        exit 1
    fi
    DOWNLOAD_PATH="/tmp/latest.$FILE_TYPE"
    wget -O $DOWNLOAD_PATH $LATEST_URL
    if [[ "$FILE_TYPE" == "AppImage" ]]; then
        chmod +x $DOWNLOAD_PATH
        mv $DOWNLOAD_PATH $HOME/$FILE_NAME.$FILE_TYPE
        create_desktop_file $FILE_NAME $HOME/$FILE_NAME.$FILE_TYPE "" ""
        return 0
    fi
    if [[ "$FILE_TYPE" == "deb" ]]; then
        sudo gdebi $DOWNLOAD_PATH -n
    elif [[ "$FILE_TYPE" == "tar.gz" || "$FILE_TYPE" == "tgz" ]]; then
        tar -C $HOME -h -xzf $DOWNLOAD_PATH
    else
        echo "Script fatal error: unsupported file type: $FILE_TYPE"
        exit 1
    fi
    rm "$DOWNLOAD_PATH"
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
        exit 1
    fi
    for FILE in "$CONFIG_DIR"/*.json; do
        [[ -f "$FILE" ]] || continue
        jq "$JQ_FILTER" "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE" || {
            echo "Failed to update $FILE"
            exit 1
        }
    done
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

# Choose mode
MODE=$1
if [[ -z "$MODE" ]]; then
    echo "LMDE ISO download: https://www.linuxmint.com/download_lmde.php
    Script modes:

        1) Format drive from ISO
        2) Installation - Personalize computer, thorough updating
        3) Update - Streamlined updating
    "
    while true; do
        read -p "Which do you want to run (0 to abort)? [0-3]: " MODE
        if [[ "$MODE" == "0" ]]; then
            echo "Script finished: no mode chosen."
            exit 0
        fi
        case "$MODE" in
            1|2|3) break ;;
            *) continue ;;
        esac
    done
fi

# Drive formatting
if [[ "$MODE" == "1" ]]; then
    lsblk -o NAME,PATH,SIZE,TYPE,MOUNTPOINTS
    read -p "Enter the PATH for the drive you want to format (e.g. /dev/sda): " DRIVE_PATH
    read -p "Enter the path for the ISO file (e.g. ~/Downloads/lmde.iso): " ISO_PATH
    ISO_PATH=$(eval echo "$ISO_PATH")
    if [[ ! -b "$DRIVE_PATH" ]]; then
        echo "Script fatal error: $DRIVE_PATH is not a valid block device."
        exit 1
    fi
    if [[ ! -f "$ISO_PATH" ]]; then
        echo "Script fatal error: ISO file not found at $ISO_PATH."
        exit 1
    fi
    read -p "WARNING: This will erase all data on $DRIVE_PATH. Make sure the drive is unmounted and is not in use by any other service. Type 'yes' to continue: " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
        echo "Script finished: operation canceled."
        exit 0
    fi
    sudo wipefs --all "$DRIVE_PATH"
    sudo dd if=/dev/zero of="$DRIVE_PATH" bs=1M count=10 status=progress
    sudo dd if="$ISO_PATH" of="$DRIVE_PATH" bs=4M status=progress && sync
    echo "Script finished: USB formatted and bootable."
    exit 0
fi

# Pre-APT, installation mode
EMAIL=""
if [[ "$MODE" == "2" ]]; then

    # Prerequisite
    read -p "Are you connected to the internet? Additionally, have you completed the installation and welcome setup screens for LMDE? (y/N): " CONTINUE
    case "$CONTINUE" in
    y|Y ) 
        ;;
    * ) 
        echo "Script finished: please connect to the internet and complete the installation and welcome setup screens for LMDE before using this script."
        exit 0
        ;;
    esac

    # User email
    read -p "Enter your email for git: " EMAIL

    # Disable autoconnect to wireless
    nmcli -t -f NAME connection show | while read -r CONN; do
        if [[ "$CONN" != *"Wired"* ]]; then
            sudo nmcli connection modify "$CONN" connection.autoconnect no
        fi
    done

    # Quad9
    DNS_SERVERS_IPV4="9.9.9.9 149.112.112.112"
    DNS_SERVERS_IPV6="2620:fe::fe 2620:fe::9"
    CONNECTION_NAME=$(nmcli -t -f NAME,DEVICE connection show --active | grep -E -v "lo|docker0" | awk -F: '{print $1}' | head -n 1)
    if [[ -z "$CONNECTION_NAME" ]]; then
        echo "Script fatal error: no active network connection found."
        exit 1
    fi
    sudo nmcli connection modify "$CONNECTION_NAME" ipv4.dns "$DNS_SERVERS_IPV4"
    sudo nmcli connection modify "$CONNECTION_NAME" ipv4.ignore-auto-dns yes
    sudo nmcli connection modify "$CONNECTION_NAME" ipv6.dns "$DNS_SERVERS_IPV6"
    sudo nmcli connection modify "$CONNECTION_NAME" ipv6.ignore-auto-dns yes
    sudo nmcli connection up "$CONNECTION_NAME"
    sudo systemctl restart NetworkManager

    # Java
    wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/adoptium.gpg > /dev/null
    echo "deb [arch=amd64] https://packages.adoptium.net/artifactory/deb bookworm main" | sudo tee /etc/apt/sources.list.d/adoptium.list

    # Node.js
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -

    # OpenRazer
    echo 'deb http://download.opensuse.org/repositories/hardware:/razer/Debian_12/ /' | sudo tee /etc/apt/sources.list.d/hardware:razer.list
    curl -SL https://download.opensuse.org/repositories/hardware:razer/Debian_12/Release.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/hardware_razer.gpg > /dev/null

    # Spotify
    curl -S https://download.spotify.com/debian/pubkey_C85668DF69375001.gpg | sudo gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/spotify.gpg
    echo "deb http://repository.spotify.com stable non-free" | sudo tee /etc/apt/sources.list.d/spotify.list

    # Tor
    echo "deb     [signed-by=/usr/share/keyrings/deb.torproject.org-keyring.gpg] https://deb.torproject.org/torproject.org bookworm main
deb-src [signed-by=/usr/share/keyrings/deb.torproject.org-keyring.gpg] https://deb.torproject.org/torproject.org bookworm main" | sudo tee /etc/apt/sources.list.d/tor.list > /dev/null
    wget -qO- https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | gpg --dearmor | sudo tee /usr/share/keyrings/deb.torproject.org-keyring.gpg > /dev/null
fi

# APT
sudo apt update -y

# Installation Mode
if [[ "$MODE" == "2" ]]; then

    # # ADB, fastboot
    # curl -o /tmp/platform-tools.zip "https://dl.google.com/android/repository/platform-tools-latest-linux.zip"
    # unzip -o /tmp/platform-tools.zip -d "$HOME/adb-fastboot"
    # PROFILE_FILE="$HOME/.profile"
    # if ! grep -q 'platform-tools' "$PROFILE_FILE"; then
    #     echo -e '\n# Add ADB & Fastboot to PATH\nif [ -d "$HOME/adb-fastboot/platform-tools" ] ; then\n    export PATH="$HOME/adb-fastboot/platform-tools:$PATH"\nfi' >> "$PROFILE_FILE"
    # fi
    # rm /tmp/platform-tools.zip

    # APT
    sudo apt install -y apt-transport-https bleachbit cups dconf-editor deb.torproject.org-keyring git guake hplip htop temurin-21-jdk jq keepassxc krita kdenlive nodejs npm nvidia-driver podman preload python3-django python3-pip python3.11-venv razergenie openrazer-meta sqlitebrowser spotify-client tlp tlp-rdw tor torbrowser-launcher tree vim vlc
    sudo systemctl enable --now cups

    # Ble.sh
    set -o vi
    rm -rf ~/ble.sh
    git clone --recursive --depth 1 --shallow-submodules https://github.com/akinomyoga/ble.sh.git ~/ble.sh
    make -C ~/ble.sh install PREFIX=~/.local
    grep -qxF 'source ~/.local/share/blesh/ble.sh' ~/.bashrc || echo '
source ~/.local/share/blesh/ble.sh' >> ~/.bashrc

    # Flathub
    flatpak install -y app/dev.vencord.Vesktop/x86_64/stable app/io.gitlab.librewolf-community/x86_64/stable app/org.prismlauncher.PrismLauncher/x86_64/stable app/org.telegram.desktop/x86_64/stable app/com.valvesoftware.Steam/x86_64/stable com.jetbrains.IntelliJ-IDEA-Community com.usebottles.bottles us.zoom.Zoom app/com.obsproject.Studio/x86_64/stable

    # GitHub releases
    install_latest_gh "ThaUnknown/miru" "linux-Miru.*deb" "deb"
    # install_latest_gh "noisetorch/NoiseTorch" "NoiseTorch_x64.*tgz" "tgz"
    # create_desktop_file "NoiseTorch" "noisetorch" "noisetorch" "Audio;Music;Player;AudioVideo;"
    install_latest_gh "ebkr/r2modmanPlus" ".*AppImage" "AppImage" "R2ModMan"
    install_latest_gh "VSCodium/vscodium" ".*amd64.deb" "deb"
    codium --install-extension serayuzgur.crates --force
    codium --install-extension usernamehw.errorlens --force
    codium --install-extension dbaeumer.vscode-eslint --force
    codium --install-extension tamasfe.even-better-toml --force
    COPILOT_VERSION=$(curl -S "https://marketplace.visualstudio.com/items?itemName=GitHub.copilot" | grep -oP '(?<="Version":")[^"]*')
    curl -S -o "${HOME}/github.copilot-${COPILOT_VERSION}.vsix" "https://github.gallery.vsassets.io/_apis/public/gallery/publisher/github/extension/copilot/${COPILOT_VERSION}/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage"
    codium --install-extension "${HOME}/github.copilot-${COPILOT_VERSION}.vsix"  --force
    find "${HOME}" -name "github.copilot-*.vsix" -not -name "github.copilot-${COPILOT_VERSION}.vsix" -delete
    codium --install-extension ms-toolsai.jupyter --force
    codium --install-extension vadimcn.vscode-lldb --force
    codium --install-extension zhuangtongfa.material-theme --force
    codium --install-extension esbenp.prettier-vscode --force
    codium --install-extension ms-python.python --force
    codium --install-extension rust-lang.rust-analyzer --force
    codium --install-extension bradlc.vscode-tailwindcss --force
    codium --install-extension Vue.volar --force
    touch ~/.config/VSCodium/User/settings.json
    echo "{
  \"workbench.sideBar.location\": \"right\",
  \"workbench.colorTheme\": \"One Dark Pro\",
  \"editor.formatOnSave\": true,
  \"editor.defaultFormatter\": \"esbenp.prettier-vscode\",
  \"[javascript]\": {
    \"editor.defaultFormatter\": \"esbenp.prettier-vscode\"
  },
  \"workbench.startupEditor\": \"none\",
  \"security.workspace.trust.untrustedFiles\": \"open\",
  \"explorer.confirmDelete\": false,
  \"typescript.updateImportsOnFileMove.enabled\": \"always\",
  \"javascript.updateImportsOnFileMove.enabled\": \"always\",
  \"explorer.confirmDragAndDrop\": false,
  \"editor.wordWrap\": \"on\",
  \"github.copilot.enable\": {
    \"*\": true,
    \"plaintext\": true,
    \"markdown\": true,
    \"scminput\": true
  }
}" > ~/.config/VSCodium/User/settings.json

    # Libsecret
    sudo apt-get install libsecret-1-0 libsecret-1-dev
    (cd /usr/share/doc/git/contrib/credential/libsecret && sudo make)

    # # Postman
    # ARCHIVE="$HOME/postman.tar.gz"
    # mkdir -p "$HOME"
    # wget -O "$ARCHIVE" "https://dl.pstmn.io/download/latest/linux_64"
    # tar -xzf "$ARCHIVE" -C "$HOME"
    # rm "$ARCHIVE"

    # Qemu
    sudo apt install -y bridge-utils libvirt-daemon-system qemu-kvm virt-manager
    sudo systemctl enable --now libvirtd

    # Rust
    grep -qxF '. "$HOME/.cargo/env"' ~/.bashrc || echo '' >> ~/.bashrc
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    . "$HOME/.cargo/env"

    # Spotify patching
    rm -rf ~/spotify-adblock
    git clone https://github.com/abba23/spotify-adblock.git ~/spotify-adblock
    make -C ~/spotify-adblock
    sudo make -C ~/spotify-adblock install
    create_desktop_file "Spotify" "env LD_PRELOAD=/usr/local/lib/spotify-adblock.so spotify %U" "spotify-client" "Audio;Music;Player;AudioVideo;"

    # Purge
    sudo apt purge -y baobab celluloid drawing gnome-calendar gnome-logs gnome-power-manager gnote hexchat hypnotix nano onboard pix rhythmbox seahorse simple-scan thunderbird warpinator webapp-manager xreader

    # Bash functions for development
    grep -qxF 'find_project_root() {' ~/.bashrc || echo '
find_project_root() {
  original_dir=$(pwd)
  while [ ! -d ".git" ] && [ "$(pwd)" != "/" ]; do
    cd ..
  done
  if [ "$(pwd)" = "/" ]; then
    cd "$original_dir"
    echo "Could not find project root directory."
    return 1
  fi
}' >> ~/.bashrc
    grep -qxF 'dr() {' ~/.bashrc || echo '
dr() {
  find_project_root
  if [ ! -d "backend" ]; then
    echo "Could not find the 'backend' directory in project root."
    return 1
  fi
  if [ -z "$VIRTUAL_ENV" ]; then
    if [ ! -d "venv" ]; then
        echo "Could not find the 'venv' Python virtual environment directory in project root."
        return 1
    fi
    source "$(pwd)/venv/bin/activate"
  fi
  cd backend
  python3 manage.py runserver
}' >> ~/.bashrc
    grep -qxF 'fr() {' ~/.bashrc || echo '
fr() {
  find_project_root
  if [ ! -d "frontend" ]; then
    echo "Could not find the 'frontend' directory in project root."
    return 1
  fi
  cd frontend
  npm run dev
}' >> ~/.bashrc
    grep -qxF 'gpm() {' ~/.bashrc || echo '
gpm() {
  read -p "Enter commit message: " message
  find_project_root
  git add .
  git commit -m "$message"
  git push
}' >> ~/.bashrc

    # Bash function for this script
    mkdir ~/CodiumProjects
    git clone https://github.com/lichenaut/lmde-lichenaut ~/CodiumProjects/lmde-lichenaut
    chmod +x ~/CodiumProjects/lmde-lichenaut/lmde_lichenaut.sh
    grep -qxF 'lus() {' ~/.bashrc || echo '
lus() {
  ~/CodiumProjects/lmde-lichenaut/lmde_lichenaut.sh 3
}' >> ~/.bashrc

    # Cinnamon tweaks
    gsettings set org.cinnamon desktop-effects-workspace false
    gsettings set org.cinnamon enabled-applets "['panel1:right:7:calendar@cinnamon.org:29', 'panel1:left:1:grouped-window-list@cinnamon.org:34', 'panel1:left:0:menu@cinnamon.org:37', 'panel1:right:4:network@cinnamon.org:38', 'panel1:right:3:printers@cinnamon.org:39', 'panel1:right:0:removable-drives@cinnamon.org:40', 'panel1:right:1:systray@cinnamon.org:41', 'panel1:right:0:xapp-status@cinnamon.org:42']"
    gsettings set org.cinnamon panels-enabled "['1:0:top']"
    gsettings set org.cinnamon.desktop.interface enable-animations false
    gsettings set org.cinnamon.desktop.interface gtk-theme "'Mint-Y-Dark'"
    gsettings set org.cinnamon.desktop.interface icon-theme "'Mint-Y'"
    gsettings set org.cinnamon.desktop.peripherals.mouse accel-profile "'flat'"
    gsettings set org.cinnamon.desktop.sound event-sounds false
    gsettings set org.cinnamon.desktop.sound theme-name "none"
    gsettings set org.cinnamon.desktop.sound volume-sound-enabled false
    gsettings set org.cinnamon.sounds login-enabled false
    gsettings set org.cinnamon.sounds logout-enabled false
    gsettings set org.cinnamon.sounds notification-enabled false
    gsettings set org.cinnamon.sounds plug-enabled false
    gsettings set org.cinnamon.sounds switch-enabled false
    gsettings set org.cinnamon.sounds tile-enabled false
    gsettings set org.cinnamon.sounds unplug-enabled false
    gsettings set org.cinnamon.theme name "'Mint-Y-Dark'"
    gsettings set org.x.apps.portal color-scheme "'prefer-dark'"
    update_cinnamon_config "$HOME/.config/cinnamon/spices/calendar@cinnamon.org" \
        '(.["show-week-numbers"].value = true) | 
        (.["use-custom-format"].value = true) | 
        (.["custom-format"].value = "%A %B %e, %H:%M") | 
        (.["custom-tooltip-format"].value = "%A %B %e, %H:%M")'

    update_cinnamon_config "$HOME/.config/cinnamon/spices/grouped-window-list@cinnamon.org" \
        '(.["pinned-apps"].value = [
            "nemo.desktop",
            "io.gitlab.librewolf-community.desktop",
            "codium.desktop",
            "spotify.desktop",
            "dev.vencord.Vesktop.desktop"
        ]) | 
        (.["pinned-apps"].default = [
            "nemo.desktop",
            "io.gitlab.librewolf-community.desktop:flatpak",
            "codium.desktop",
            "spotify.desktop",
            "dev.vencord.Vesktop.desktop:flatpak"
        ])'

    # Default apps
    echo "[Default Applications]
application/octet-stream=org.keepassxc.KeePassXC.desktop
application/javascript=codium.desktop
application/pdf=io.gitlab.librewolf-community.desktop
application/x-httpd-php3=codium.desktop
application/x-httpd-php4=codium.desktop
application/x-httpd-php5=codium.desktop
application/x-m4=codium.desktop
application/x-php=codium.desktop
application/x-ruby=codium.desktop
application/x-shellscript=codium.desktop
application/xml=codium.desktop
audio/*=vlc.desktop
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
video/*=vlc.desktop
x-scheme-handler/http=io.gitlab.librewolf-community.desktop
x-scheme-handler/https=io.gitlab.librewolf-community.desktop
x-scheme-handler/postman=Postman.desktop

[Added Associations]
application/octet-stream=org.keepassxc.KeePassXC.desktop
application/pdf=io.gitlab.librewolf-community.desktop;libreoffice-draw.desktop
audio/*=vlc.desktop
video/*=vlc.desktop
x-scheme-handler/http=io.gitlab.librewolf-community.desktop;firefox.desktop" > ~/.config/mimeapps.list
    sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/guake 100

    # Gamemode apps
    env GAMEMODERUNEXEC="env __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only"
    sudo usermod -a -G gamemode $USER
    if [ $(grep -q "Exec=LD_PRELOAD=\"\" gamemoderun" "/usr/share/applications/r2modman.desktop"; echo $?) -ne 0 ]; then
        sudo sed -i '/^Exec=/s|^Exec=|Exec=LD_PRELOAD="" gamemoderun |' "/usr/share/applications/r2modman.desktop"
    fi
    if [ $(grep -q "Exec=LD_PRELOAD=\"\" gamemoderun" "/var/lib/flatpak/exports/share/applications/com.valvesoftware.Steam.desktop"; echo $?) -ne 0 ]; then
        sudo sed -i '/^Exec=/s|^Exec=|Exec=LD_PRELOAD="" gamemoderun |' "/var/lib/flatpak/exports/share/applications/com.valvesoftware.Steam.desktop"
    fi
    if [ $(grep -q "Exec=LD_PRELOAD=\"\" gamemoderun" "$HOME/.local/share/applications/com.valvesoftware.Steam.desktop"; echo $?) -ne 0 ]; then
        sudo sed -i '/^Exec=/s|^Exec=|Exec=LD_PRELOAD="" gamemoderun |' "$HOME/.local/share/applications/com.valvesoftware.Steam.desktop"
    fi

    # Git tweaks
    git config --global branch.sort -committerdate
    git config --global column.ui auto
    git config --global credential.helper /usr/share/doc/git/contrib/credential/libsecret/git-credential-libsecret
    git config --global diff.algorithm histogram
    git config --global diff.colorMoved plain
    git config --global diff.mnemonicPrefix true
    git config --global diff.renames true
    git config --global fetch.all true
    git config --global fetch.prune true
    git config --global fetch.pruneTags true
    git config --global help.autocorrect prompt
    git config --global init.defaultBranch main
    git config --global pull.rebase true
    git config --global push.autoSetupRemote true
    git config --global push.default simple
    git config --global push.followTags true
    git config --global rebase.autoSquash true
    git config --global rebase.autoStash true
    git config --global rebase.updateRefs true
    git config --global rerere.autoupdate true
    git config --global rerere.enabled true
    git config --global tag.sort version:refname
    git config --global user.email $EMAIL
    git config --global user.name lichenaut

    # GRUB tweaks
    sudo sed -i 's/^#GRUB_GFXMODE=.*/GRUB_GFXMODE=1920x1080/' "/etc/default/grub"
    sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' "/etc/default/grub"
    sudo update-grub

    # Guake tweaks
    gsettings set guake.keybindings.global show-hide "'F5'"
    gsettings set guake.style.font palette "'#505050505050:#FFFF2E2E3F3F:#6F6FD6D65D5D:#FFFF6F6F2323:#34347676FFFF:#98986161F8F8:#0000CDCDB3B3:#FFFFFCFCC2C2:#7C7C7C7C7C7C:#FFFF64648080:#3F3FC5C56B6B:#F9F9C8C85959:#0000B1B1FEFE:#B6B68D8DFFFF:#B3B38B8B7D7D:#FFFFFEFEE3E3:#DEDEE0E0DFDF:#262626262626'"
    gsettings set guake.style.font palette-name "'Bluloco'"

    # Miscellanenous Tweaks
    gsettings set org.nemo.preferences show-hidden-files true

    # Startup apps
    create_autostart_entry "Guake Terminal" "guake" "guake" "guake"
    # create_autostart_entry "NoiseTorch" "noisetorch" "noisetorch" "noisetorch"
    create_autostart_entry "Redshift" "redshift-gtk" "redshift" "redshift-gtk"
    create_autostart_entry "Update Manager" "mintupdate-launcher" "mintupdate" "mintupdate"
    sudo sed -i 's/^X-GNOME-Autostart-enabled=.*/X-GNOME-Autostart-enabled=false/' "$HOME/.config/autostart/mintupdate.desktop"
    sudo systemctl disable bluetooth.service

    # Reload
    source ~/.bashrc
    source ~/.profile
    gtk-update-icon-cache
    cinnamon --replace > /dev/null 2>&1 &
fi

# APT
sudo apt full-upgrade -y && sudo apt autoremove -y && sudo apt autoclean -y

# Flathub
flatpak update -y

# Rust
~/.cargo/bin/rustup update

# Browser preferencing
update_pref_js "$HOME/.mozilla/firefox/*.default-release"
update_pref_js "$HOME/.var/app/io.gitlab.librewolf-community/.librewolf/*.default-default"
update_pref_js "$HOME/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default"

# Flavor
if [[ "$MODE" == "2" ]]; then
    neofetch
fi

# Reboot question
read -t 10 -p "Reboot now? (y/N): " REBOOT_CHOICE && echo
case "$REBOOT_CHOICE" in
  y|Y ) 
    echo "Rebooting..."
    sudo reboot
    ;;
  * ) 
    echo && echo "Script finished."
    ;;
esac