Set ws = CreateObject("WScript.Shell")
ws.Run "net start w32time", 0, True
ws.Run "tzutil /s ""SE Asia Standard Time""", 0, True
ws.Run "w32tm /resync", 0, True

If GetObject("winmgmts:").ExecQuery("Select * from Win32_Process Where Name='msedge.exe'").Count = 0 Then 
    ws.Run "msedge", 0, False
End If