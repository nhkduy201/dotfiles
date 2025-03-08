' Create a WScript.Shell object
Set WshShell = CreateObject("WScript.Shell")

' Start the Windows Time service if it's not running.
' "cmd /c" runs the command, "0" hides the window, and "True" waits for it to finish.
WshShell.Run "cmd /c net start w32time", 0, True

' Set the time zone to SE Asia Standard Time (Hanoi, Bangkok, Jakarta)
WshShell.Run "cmd /c tzutil /s ""SE Asia Standard Time""", 0, True

' Resync the system time.
WshShell.Run "cmd /c w32tm.exe /resync", 0, True

' Launch Microsoft Edge.
' If msedge.exe isn’t in your PATH, specify the full path, e.g.,
' "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
WshShell.Run "msedge", 0, False
