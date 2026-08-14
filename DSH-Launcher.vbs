' DeepSeek Harness desktop launcher entry: runs DSH-Launcher.ps1 without any console window.
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\DSH-Launcher.ps1""", 0, False
