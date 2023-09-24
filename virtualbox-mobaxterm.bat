"C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" startvm <vm-name> --type headless
timeout /t 30 /nobreak > NUL
cd "C:\Program Files (x86)\Mobatek\MobaXterm\"
start /B "" "MobaXterm.exe" -bookmark <session-name>
