# === MYCONFIG === #
[ -f ~/.fzf.bash ] && source ~/.fzf.bash
# FUNCTION
otw() {
  file_path="/root/otwpass"
  line_threshold="$1"
  replacement_text="$2"

  if [[ $(wc -l < "$file_path") -gt "$line_threshold" ]]; then
    sed -i "$(($line_threshold + 1))s/.*/$replacement_text/" "$file_path"
  else
    echo "$replacement_text" >> "$file_path"
  fi
  sshpass -p$replacement_text ssh -p 2220 -o StrictHostKeyChecking=no bandit$line_threshold@bandit.labs.overthewire.org
}
# pnc() {
#   /root/cp/utils/w2pts -n $(tty) 'eval "$(/root/cp/utils/mcf pn code)"'
# }
# pws() {
#   /root/python/winconn cmd $1
# }
# opgx() {
#   pws "opgx $1"
# }
# code() {
#   pws "code $(realpath $1)"
# }
findroot() {
        find / -iname *$1* 2>/dev/null
}
cal_mem() {
  local unit="MB"  # Set the desired unit ("KB", "MB", or "GB")
  ps -o rss --no-header -p $(pgrep $1) | awk -v unit="$unit" '
    { sum += $1 }
    END {
        if (unit == "KB")
            printf "%d KB\n", sum
        else if (unit == "MB")
            printf "%.2f MB\n", sum / 1024
        else if (unit == "GB")
            printf "%.2f GB\n", sum / (1024 * 1024)
    }'
}
save_dotfiles() {
  [[ -f ~/config/.bashrc ]] && awk '/# === MYCONFIG === #/,0' ~/.bashrc > ~/config/.bashrc
}
copy_file_clipboard() {
  xclip -sel clip -i $1
}

# ALIAS
#alias tmat='tmux attach || tmux'
#alias pn='eval "$(/home/kayd/cp/utils/mcf pn vim)"'
#alias p='eval "$(/home/kayd/cp/utils/mcf p)"'
alias ll='ls -alF'
alias v='nvim'

#sleep 0.1
#wmctrl -i -r $(wmctrl -lx | grep xfce4-terminal | cut -d' ' -f1) -b add,fullscreen
#wmctrl -r lxterminal -b add,fullscreen
#wmctrl -r qterminal -b add,fullscreen
#wmctrl -i -r $(wmctrl -lx | grep gnome-terminal | cut -d' ' -f1) -b add,fullscreen

# Created by `pipx` on 2023-09-09 09:34:12
export PATH="$PATH:/home/kayd/.local/bin"

if ! pgrep -x "Xorg" > /dev/null; then
  startx
fi

# open tmux
if [[ $TERM_PROGRAM != "vscode" ]]; then
  if [[ -z $TMUX ]]; then
    tmux attach || tmux
  fi
fi
