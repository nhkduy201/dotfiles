xinput set-prop $(xinput | grep -i touchpad | grep -oP 'id=\K\d+') "libinput Natural Scrolling Enabled" 1
feh --bg-fill Downloads/wallpaperflare.com_wallpaper.jpg
picom &>/dev/null &
slstatus &>/dev/null &
export GTK_IM_MODULE=ibus
export XMODIFIERS=@im=ibus
export QT_IM_MODULE=ibus
ibus-daemon -drx &
python $(find ~ -name l5p_kbl.py) static a020f0
exec dwm
