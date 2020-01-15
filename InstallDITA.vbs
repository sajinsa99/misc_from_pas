''''''''''''''
' Parameters '
''''''''''''''

DROP_DIR = "\\build-drops-wdf.wdf.sap.corp\dropzone"
PROJECT = "documentation"
STREAM  = "dita_output_prod"
PLATFORM = "win64_x64"
MODE = "release"
DST = "C:\DITA"
SRC = DROP_DIR & "\" & PROJECT & "\" & STREAM

Set objRE  = New RegExp
Set objShell = WScript.CreateObject("WScript.Shell")
Set objFSO = CreateObject("Scripting.FileSystemObject")
 
''''''''
' Main '
''''''''
' First parameter contains the destination and is optional (default is c:\Dita as destination dir) 

If WScript.Arguments.Count = 1 then
  DST= WScript.Arguments.Item(0) 
end If

Set objFile = objFSO.OpenTextFile(SRC & "\greatest.xml", 1)
Context = objFile.ReadAll
objRE.Pattern = "<version.+>\d+\.\d+\.\d+\.(\d+)</version>"
objRE.IgnoreCase = True
objRE.MultiLine = True
Set Version = objRE.Execute(Context)
BuildNumber = Version(0).submatches(0) 
objShell.Run "XCOPY /ECIQHRYD " & SRC & "\" & BuildNumber & "\" & PLATFORM & "\" & MODE & "\bin\* " & DST
