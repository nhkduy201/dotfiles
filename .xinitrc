xinput set-prop $(xinput | grep -i touchpad | grep -oP 'id=\K\d+') "libinput Natural Scrolling Enabled" 1
feh --bg-fill Downloads/wallpaperflare.com_wallpaper.jpg
picom &>/dev/null &
slstatus &>/dev/null &
export GTK_IM_MODULE=ibus
export XMODIFIERS=@im=ibus
export QT_IM_MODULE=ibus
ibus-daemon -drx &
sed -i 's/PRODUCT = 0xC965/PRODUCT = 0xC975/' l5p-kbl.py
exec dwm
