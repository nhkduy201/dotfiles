#!/bin/bash -x
set -e
SCRIPT_NAME=$(basename "$0")
DIR_NAME="arch-sources"
CONTAINER_NAME="arch-source-container"
SSH_PORT="12345"
SSH_PASSWORD="archpkgsrcxplr"
install_docker() {
    if ! command -v docker &> /dev/null; then
        sudo pacman -Sy --noconfirm docker
        sudo systemctl enable docker
        sudo systemctl start docker
        sudo usermod -aG docker "$USER"
        echo "Docker installed. Log out and back in for group changes to take effect."
        echo "Then run this script again."
        exit 1
    fi
}
search_package() {
    local search_term="$1"
    local package_list
    if command -v paru &> /dev/null; then
        package_list=$(paru -Ss "$search_term" | grep -E "^[a-zA-Z0-9]" | awk '{print $1}' | sed 's|^[^/]*/||')
    else
        package_list=$(pacman -Ss "$search_term" | grep -E "^[a-zA-Z0-9]" | awk '{print $1}' | sed 's|^[^/]*/||')
    fi
    if command -v dmenu &> /dev/null; then
        echo "$package_list" | dmenu -i -p "Select package:"
    else
        echo "$package_list" | fzf --prompt "Select package: "
    fi
}
download_source_only() {
    local pkg="$1"
    local dir="${HOME}/${DIR_NAME}"
    mkdir -p "$dir"
    cd "$dir"
    if command -v paru &> /dev/null; then
        paru -G "$pkg"
        cd "$(ls -td -- */ | tail -1)"
        makepkg --verifysource --skippgpcheck
    #elif pacman -Si "$pkg" &> /dev/null; then
    #    sudo pacman -S --noconfirm devtools
    #    pacman -Si asp &> /dev/null || paru -S --noconfirm --needed asp # paru not found before, can't use here
    #    asp checkout "$pkg"
    #    cd "$(ls -td -- */ | tail -1)/trunk"
    #    makepkg --verifysource --skippgpcheck
    else
        git clone "https://aur.archlinux.org/$pkg.git"
        cd "$(ls -td -- */ | tail -1)"
        makepkg --verifysource --skippgpcheck
    fi
    echo "Source downloaded to: $(pwd)/src"
}
setup_container() {
    local pkg="$1"
    docker rm -f "$CONTAINER_NAME" &>/dev/null || true
    docker run -d --name "$CONTAINER_NAME" \
        -v "${HOME}/${DIR_NAME}:/work" \
        -p ${SSH_PORT}:22 \
        archlinux:latest \
        sleep infinity
    docker exec "$CONTAINER_NAME" pacman -Syu --noconfirm
    docker exec "$CONTAINER_NAME" pacman -S --noconfirm base-devel git openssh sudo
    docker exec "$CONTAINER_NAME" bash -c "echo \"root:${SSH_PASSWORD}\" | chpasswd"
    docker exec "$CONTAINER_NAME" bash -c 'mkdir -p /root/.ssh && chmod 700 /root/.ssh'
    docker exec "$CONTAINER_NAME" bash -c 'sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin yes/" /etc/ssh/sshd_config'
    docker exec "$CONTAINER_NAME" bash -c 'ssh-keygen -A && systemctl start sshd'
    echo "Container running with SSH on port ${SSH_PORT}"
    echo "Connect with: ssh root@localhost -p ${SSH_PORT} (password: ${SSH_PASSWORD})"
    echo "VSCode SSH config: ssh -p ${SSH_PORT} root@localhost"
}
build_in_container() {
    local pkg="$1"
    setup_container "$pkg"
    if pacman -Si "$pkg" &> /dev/null; then
        docker exec "$CONTAINER_NAME" bash -c "pacman -S --noconfirm devtools && cd /work && asp checkout $pkg"
    elif command -v paru &> /dev/null; then
        docker exec "$CONTAINER_NAME" bash -c "cd /work && curl -s 'https://aur.archlinux.org/cgit/aur.git/snapshot/$pkg.tar.gz' -o '$pkg.tar.gz' && tar xzf '$pkg.tar.gz'"
    else
        docker exec "$CONTAINER_NAME" bash -c "cd /work && git clone https://aur.archlinux.org/$pkg.git"
    fi
    echo "Package source downloaded in container. Connect via SSH to build."
}
print_usage() {
    echo "Usage: $SCRIPT_NAME [options] [package]"
    echo "Options:"
    echo "  -s, --source-only    Download source code only (no building)"
    echo "  -b, --build          Setup Docker container for building"
    echo "  -h, --help           Show this help message"
}
setup_alias() {
    if ! grep -q "alias arch-src" ~/.bashrc; then
        echo "alias arch-src='$PWD/$SCRIPT_NAME'" >> ~/.bashrc
        echo "Alias 'arch-src' added to ~/.bashrc"
        source ~/.bashrc
    fi
}
main() {
    local mode="source-only"
    local package=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--source-only)
                mode="source-only"
                shift
                ;;
            -b|--build)
                mode="build"
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                package="$1"
                shift
                ;;
        esac
    done
    local cleaned_package=""
    if [[ -n "$package" ]]; then
        cleaned_package=$(echo "$package" | sed 's|^[^/]*/||')
        if ! pacman -Si "$cleaned_package" &>/dev/null && ! paru -Si "$cleaned_package" &>/dev/null 2>&1; then
            cleaned_package=$(search_package "$package")
        fi
    else
        read -p "Enter package name or search term: " search_term
        cleaned_package=$(search_package "$search_term")
    fi
    if [[ -z "$cleaned_package" ]]; then
        echo "No package selected."
        exit 1
    fi
    echo "Selected package: $cleaned_package"
    if [[ "$mode" == "source-only" ]]; then
        download_source_only "$cleaned_package"
    else
        install_docker
        build_in_container "$cleaned_package"
    fi
}
setup_alias
main "$@"