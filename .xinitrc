feh --bg-fill Downloads/wallpaperflare.com_wallpaper.jpg
picom &>/dev/null &
slstatus &>/dev/null &
export GTK_IM_MODULE=ibus
export XMODIFIERS=@im=ibus
export QT_IM_MODULE=ibus
ibus-daemon -drx &
gsettings set org.freedesktop.ibus.general preload-engines "['xkb:us::eng', 'Bamboo']"
gsettings set org.freedesktop.ibus.general.hotkey triggers "['<Control><Shift>space']"
sudo python $(find ~ -name l5p_kbl.py) static a020f0
exec dwm
