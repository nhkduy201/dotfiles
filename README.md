# Dotfiles and System Configuration

This repository contains my personal dotfiles and system configuration files for Arch Linux, along with various installation and setup scripts.

## 📁 Repository Structure

- **Installation Scripts**
  - `arch-install.sh` - Full Arch Linux installation script
  - `min-arch-install.sh` - Minimal Arch Linux installation script
  - `kvm-arch-install.sh` - KVM-specific Arch Linux installation script
  - `post_install` - Post-installation configuration script

- **Window Manager Configurations**
  - `dwm-config.h` - DWM window manager configuration
  - `st-config.h` - Simple Terminal (st) configuration
  - `slstatus-git-config.h` - Status bar configuration for DWM
  - `picom.conf` - Compositor configuration

- **Input Device Configuration**
  - `01-libinput.conf` - Libinput configuration for touchpad
  - `01-touchpad.rules` - Udev rules for touchpad
  - `touchpad-toggle` - Script to toggle touchpad

- **System Services**
  - `ibus-daemon.service` - IBus input method system service

- **Browser Related**
  - `changefont.tampermonkey` - Tampermonkey script for font customization
  - `copy_innerText_to_clipboard.js` - JavaScript utility for clipboard operations
  - `microsoft-edge.desktop` - Microsoft Edge desktop entry

- **Utility Scripts**
  - `get_transcript.{sh,py,ps1}` - Transcript retrieval scripts
  - `download_arch_iso.{sh,ps1}` - Arch ISO download scripts
  - `arch_pkg_src_xplr.sh` - Package source explorer script
  - `w32tm-resync.vbs` - Windows time resync script
  - `windows_google_dns.ps1` - Windows DNS configuration script

- **Virtual Machine Tools**
  - `virtualbox-mobaxterm.bat` - VirtualBox MobaXterm integration
  - Save directory contains various reference files and notes

## 🚀 Key Features

- Automated Arch Linux installation with different profiles (full, minimal, KVM)
- DWM window manager setup with custom configurations
- Input device optimization for laptops
- Browser customization scripts
- Cross-platform utility scripts
- Virtual machine integration tools

## 📋 Prerequisites

- Arch Linux or compatible distribution
- Basic understanding of Linux system administration
- Git for cloning the repository

## 🔧 Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/dotfiles.git
   ```

2. Run the installation script:
   ```bash
   ./install
   ```

3. For a new Arch Linux installation:
   ```bash
   # For full installation
   ./arch-install.sh
   
   # For minimal installation
   ./min-arch-install.sh
   ```

## ⚙️ Configuration

### Window Manager (DWM)
- Custom keybindings and layouts
- Status bar with system information
- Terminal emulator (st) with custom patches

### Input Devices
- Optimized touchpad configuration
- Toggle script for easy enable/disable

### System Services
- Automated IBus setup for input methods
- Systemd service configurations

## 📝 Notes

- Check the `save/` directory for additional documentation and notes
- Refer to individual script headers for specific usage instructions
- Configuration files contain inline documentation

## 🌟 Tips

1. Use `post_install` for setting up additional software
2. Check `gaming_note.txt` for gaming-related optimizations
3. See `kvm.txt` for virtual machine setup guidance
4. Review `hotspot.txt` for network sharing setup

## 📄 License

This project is under the MIT License - see the LICENSE file for details.

## 🤝 Contributing

Feel free to submit issues and pull requests for improvements.