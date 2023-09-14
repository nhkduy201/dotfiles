#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

[[ -f ~/.welcome_screen ]] && . ~/.welcome_screen

_set_liveuser_PS1() {
    PS1='[\u@\h \W]\$ '
    if [ "$(whoami)" = "liveuser" ] ; then
        local iso_version="$(grep ^VERSION= /usr/lib/endeavouros-release 2>/dev/null | cut -d '=' -f 2)"
        if [ -n "$iso_version" ] ; then
            local prefix="eos-"
            local iso_info="$prefix$iso_version"
            PS1="[\u@$iso_info \W]\$ "
        fi
    fi
}
_set_liveuser_PS1
unset -f _set_liveuser_PS1

ShowInstallerIsoInfo() {
    local file=/usr/lib/endeavouros-release
    if [ -r $file ] ; then
        cat $file
    else
        echo "Sorry, installer ISO info is not available." >&2
    fi
}


alias ls='ls --color=auto'
alias ll='ls -lav --ignore=..'   # show long listing of all except ".."
alias l='ls -lav --ignore=.?*'   # show long listing but no hidden dotfiles except "."

[[ "$(whoami)" = "root" ]] && return

[[ -z "$FUNCNEST" ]] && export FUNCNEST=100          # limits recursive functions, see 'man bash'

## Use the up and down arrow keys for finding a command in history
## (you can write some initial letters of the command first).
bind '"\e[A":history-search-backward'
bind '"\e[B":history-search-forward'

################################################################################
## Some generally useful functions.
## Consider uncommenting aliases below to start using these functions.
##
## October 2021: removed many obsolete functions. If you still need them, please look at
## https://github.com/EndeavourOS-archive/EndeavourOS-archiso/raw/master/airootfs/etc/skel/.bashrc

_open_files_for_editing() {
    # Open any given document file(s) for editing (or just viewing).
    # Note1:
    #    - Do not use for executable files!
    # Note2:
    #    - Uses 'mime' bindings, so you may need to use
    #      e.g. a file manager to make proper file bindings.

    if [ -x /usr/bin/exo-open ] ; then
        echo "exo-open $@" >&2
        setsid exo-open "$@" >& /dev/null
        return
    fi
    if [ -x /usr/bin/xdg-open ] ; then
        for file in "$@" ; do
            echo "xdg-open $file" >&2
            setsid xdg-open "$file" >& /dev/null
        done
        return
    fi

    echo "$FUNCNAME: package 'xdg-utils' or 'exo' is required." >&2
}

#------------------------------------------------------------

## Aliases for the functions above.
## Uncomment an alias if you want to use it.
##

# alias ef='_open_files_for_editing'     # 'ef' opens given file(s) for editing
# alias pacdiff=eos-pacdiff
################################################################################


[ -f ~/.fzf.bash ] && source ~/.fzf.bash
#======== FUNCTION ============#
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

#======== ALIAS ============#
alias tmat='tmux attach || tmux'
alias vi='vim'
alias pn='eval "$(/home/kayd/cp/utils/mcf pn vim)"'

#sleep 0.1
#wmctrl -i -r $(wmctrl -lx | grep xfce4-terminal | cut -d' ' -f1) -b add,fullscreen
#wmctrl -r lxterminal -b add,fullscreen
#wmctrl -r qterminal -b add,fullscreen
#wmctrl -i -r $(wmctrl -lx | grep gnome-terminal | cut -d' ' -f1) -b add,fullscreen

# open tmux
[[ $TERM_PROGRAM != "vscode" && -z $TMUX ]] && (tmat)

startx 2>/dev/null

# Created by `pipx` on 2023-09-09 09:34:12
export PATH="$PATH:/home/kayd/.local/bin"
