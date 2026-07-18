Option Explicit

Dim shell, fso, baseDir, scriptPath, logPath, command
Dim attempt, exitCode, logFile
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
scriptPath = fso.BuildPath(baseDir, "BubuQuotaPanel.ps1")
logPath = fso.BuildPath(baseDir, "panel-launcher.log")
command = "powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & scriptPath & """"

For attempt = 1 To 3
    Set logFile = fso.OpenTextFile(logPath, 8, True)
    logFile.WriteLine Now & " launch attempt " & attempt
    logFile.Close

    exitCode = shell.Run(command, 0, True)

    Set logFile = fso.OpenTextFile(logPath, 8, True)
    logFile.WriteLine Now & " panel exited with code " & exitCode
    logFile.Close

    If exitCode = 0 Then Exit For
    WScript.Sleep 3000
Next
