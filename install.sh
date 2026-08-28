#!/bin/bash

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'


echo -e "${BLUE}=> Starting installation script...${NC}"

errorHandling(){
  local returnCode=$1
  local mode=$2
  case $returnCode in
    1) echo -e "${RED}[ERROR] Network Is Unreachable${NC}" ;;
    2) echo -e "${RED}[ERROR] Unkown Error${NC}" ;;
    3) echo -e "${RED}[ERROR] Cannot enable services${NC}" ;;
    4) echo -e "${RED}[ERROR] Package installation failed${NC}" ;;
  esac
  [ "$mode" = "noexit" ] && return
  exit $returnCode
}

# Enables only the services in the given list whose unit file actually
# exists, warning and skipping the rest (e.g. pipewire-pulse isn't always
# installed/shipped as its own unit).
checkAndEnableServices(){
  local toEnable=()
  for svc in "$@"; do
    if systemctl --user list-unit-files "${svc}.service" 2>/dev/null | grep -q "^${svc}\.service"; then
      toEnable+=("$svc")
    else
      echo -e "${YELLOW}[WARN] Service ${svc}.service not found, skipping.${NC}"
    fi
  done
  if [ ${#toEnable[@]} -eq 0 ]; then
    echo -e "${YELLOW}[WARN] No services to enable.${NC}"
    return 0
  fi
  systemctl --user enable --now "${toEnable[@]}"
}

systemUpgrade(){
  echo -e "${BLUE}==> Full system upgrade...${NC}"
  sudo pacman -Suy
  if [ $? -ne 0 ]; then
    errorHandling 2
  fi
}

installPkgs() {
  echo -e "${BLUE}==> Installing dependencies...${NC}"
  sudo pacman -S --needed --noconfirm $(cat install/pkgs.txt)  
  sudo pacman -S --needed --noconfirm $(cat install/tui-pkgs.txt)  
  sudo pacman -S --needed --noconfirm $(cat install/gui-pkgs.txt)  
  if [ $? -ne 0 ]; then
    errorHandling 1
  fi
}

# Adding quickshell-lockscreen dependencies
#sudo pacman -S --needed --noconfirm sddm qt6-declarative qt6-5compat qt6-svg \
    #qt6-multimedia qt6-multimedia-ffmpeg gst-plugins-base gst-plugins-good \
    #gst-plugins-bad gst-plugins-ugly


setupStow(){
  echo -e "${BLUE}==> Setting up stow for system dotfiles...${NC}"
  rm -rf ~/.config/hypr/
  rm -rf ~/.config/waybar
  rm -rf ~/.config/quickshell/
  rm ~/.zshrc && ~/.oh-my-zsh/
  stow --target=$HOME hyprland-config || echo -e "${YELLOW}[WARN] Stow: hyprland-config failed, moving on.${NC}"
  stow --target=$HOME quickshell-bar || echo -e "${YELLOW}[WARN] Stow: waybar-config failed, moving on.${NC}"
  stow --target=$HOME ghostty-config || echo -e "${YELLOW}[WARN] Stow: ghostty-config failed, moving on.${NC}"
  stow --target=$HOME zsh-config || echo -e "${YELLOW}[WARN] Stow: zsh-config failed, moving on.${NC}"
}

installFlatpaks(){
  echo -e "${BLUE}==> Installing flatpaks${NC}"
  flatpak install -y $(cat install/flatpakslist.txt)
}

enableServices(){
  echo -e "${BLUE}==> Enabling services needed for screen sharing and audio...${NC}"
  checkAndEnableServices pipewire wireplumber xdg-desktop-portal-hyprland waybar
  if [ $? -ne 0 ]; then
    errorHandling 3 noexit
  fi
}

setupNetworkManager(){
  echo -e "${BLUE}==> Switching network management from iwd to NetworkManager...${NC}"
  # This is done at the very end so internet doesn't drop during downloads
  sudo systemctl stop iwd
  sudo systemctl disable iwd
  echo -e "${BLUE}==> Uninstalling iwd...${NC}"
  sudo pacman -R --noconfirm iwd || echo "iwd already removed."
  sudo systemctl enable --now NetworkManager
  sudo systemctl restart NetworkManager
}

enableAudio(){
  echo -e "${BLUE}==> Enabling services needed for screen sharing and audio...${NC}"
  checkAndEnableServices pipewire pipewire-pulse wireplumber xdg-desktop-portal-hyprland
  if [ $? -ne 0 ]; then
    errorHandling 3
  fi
  # Set a sane default volume so it's not muted on first boot
  sleep 2  # give pipewire a moment to settle
  wpctl set-volume @DEFAULT_SINK@ 50%
  wpctl set-mute @DEFAULT_SINK@ 0
}

setupWallpaper(){
  read -p "Do you want to download the default wallpapers set (y/n)? " answer

  if [[ "$answer" =~ ^[Yy]$ ]]; then
      echo "Downloading wallpapers..."
      (cd ~/Documents && git clone https://github.com/HoneyChasey/minimal-hypr-wallappers && stow --target=$HOME --ignore='.github' pictures)
      echo "You will find the wallpapers in ~/pictures/wallpapers folder"
      sleep 0.5
  else
      echo "Skipping wallpapers. As you want :("
  fi
}

main(){
  if ping -c 1 -W 2 1.1.1.1 &> /dev/null; then
      :
  else
      echo -e "${RED}[ERROR] Network Is Unreachable, you need to be connected to internet to run this installation script${NC}"
      exit 1
  fi

  systemUpgrade
  installPkgs
  installFlatpaks
  setupStow
  enableServices
  enableAudio
  setupNetworkManager
  echo -e "${GREEN}==> Done! System will reboot in 5 seconds.${NC}"
  echo -e "${YELLOW}Note: When you open your terminal after rebooting, Powerlevel10k will prompt you to configure it.${NC}"
  sleep 5
  sudo reboot
}

main
