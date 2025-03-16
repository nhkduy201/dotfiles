#!/bin/bash
bash <<EOF1
#cd ~
#paru -Gq st
#cd st
#sed -i "s#^source=(.*#&\\n        st-clipboard-20180309-c5ba9c0.diff#" PKGBUILD
#sed -i "s#^sha256sums=(.*#&\\n            '4989c03de5165234303d3929e3b60d662828972203561651aa6dc6b8f67feeb8'#" PKGBUILD
#wget -q https://st.suckless.org/patches/clipboard/st-clipboard-20180309-c5ba9c0.diff
#sed -i '/^prepare() {/a\
#\ \ patch -d "\\\$_sourcedir" -p1 < st-clipboard-20180309-c5ba9c0.diff\n\
#  sed -i "s/\\\\(STCFLAGS =\\\\)\\\\(.*\\\\)/\\\\1 -O3 -march=native\\\\2/" "\\\$_sourcedir/config.mk"\n\
#  sed -i "s/\\\\(static char \\\\*font = \\\\"\\\\)[^:]\\\\+:[^:]\\\\+/\\\\1Source Code Pro:pixelsize=16/" "\\\$_sourcedir/config.def.h"' PKGBUILD
#makepkg -si --noconfirm --skipinteg
##makepkg --nobuild

yes | sudo cp /etc/i3/config /home/kayd/.config/i3/config
sed -i '1i set \\\$mod Mod4
1i workspace_layout tabbed
s/Mod1/\\\$mod/g
s/\\\$mod+h/\\\$mod+Mod1+h/;s/\\\$mod+v/\\\$mod+Mod1+v/
s/exec i3-sensible-terminal/exec st/
s/^\\(font\\s\\+[^0-9]\\+\\)[0-9]\\+/\\110/g' ~/.config/i3/config
sed -i 's/set \\\$up l/set \\\$up k/; s/set \\\$down k/set \\\$down j/; s/set \\\$left j/set \\\$left h/; s/set \\\$right semicolon/set \\\$right l/' ~/.config/i3/config
echo 'bindsym Mod1+Shift+l exec --no-startup-id slock
bindsym \\\$mod+Shift+s exec --no-startup-id "scrot -s - | xclip -sel clip -t image/png"
bindsym \\\$mod+q kill
bindsym XF86MonBrightnessUp exec --no-startup-id brightnessctl set +5%
bindsym XF86MonBrightnessDown exec --no-startup-id brightnessctl set 5%-' >> ~/.config/i3/config
EOF1