xinput set-prop $(xinput | grep -i touchpad | grep -oP 'id=\K\d+') "libinput Natural Scrolling Enabled" 1
feh --bg-fill Downloads/wallpaperflare.com_wallpaper.jpg
picom &>/dev/null &
slstatus &>/dev/null &
exec dwm
#stalonetray &
