Set objShell = CreateObject("Wscript.Shell")
strPath = Wscript.ScriptFullName
Set objFSO = CreateObject("Scripting.FileSystemObject")
Set objFile = objFSO.GetFile(strPath)
strFolder = objFSO.GetParentFolderName(objFile) 

Set wshShell = CreateObject( "WScript.Shell" )
Username=wshShell.ExpandEnvironmentStrings( "%USERNAME%" )
Domain=wshShell.ExpandEnvironmentStrings( "%USERDOMAIN%" )

'Wscript.Echo "Name: " & Username & " Domain: " & Domain

strComputer = "."

Set objWMIService = GetObject("winmgmts:\\" & strComputer & "\root\cimv2")
Set objVariable = objWMIService.Get("Win32_Environment").SpawnInstance_

objVariable.Name = "BUILD_HOME"
objVariable.UserName = Domain & "\" & Username
objVariable.VariableValue = strFolder
objVariable.Put_

objVariable.Name = "ANT_HOME"
objVariable.UserName = Domain & "\" & Username
objVariable.VariableValue = strFolder & "\tools\ant\apache-ant-1.9.0"
objVariable.Put_

objVariable.Name = "PERL_HOME"
objVariable.UserName = Domain & "\" & Username
objVariable.VariableValue = strFolder & "\tools\perl"
objVariable.Put_

objVariable.Name = "PATH"
objVariable.UserName = Domain & "\" & Username
objVariable.VariableValue = "%PATH%;C:\WINDOWS\Microsoft.NET\Framework\v4.0.30319;%ANT_HOME%\bin;%PERL_HOME%"
objVariable.Put_
