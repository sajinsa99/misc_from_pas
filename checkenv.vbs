''''''''''''''
' Parameters '
''''''''''''''

'Setting PATH env variable
PATH = "C:\Program Files (x86)\Windows Resource Kits\Tools\;C:\WINDOWS\system32;C:\WINDOWS;C:\WINDOWS\System32\Wbem;C:\Perl\bin;C:\cygwin\bin;C:\jdk16\bin;C:\Program Files (x86)\Microsoft SQL Server\90\Tools\binn\;C:\WINDOWS\Microsoft.NET\Framework64\v2.0.50727;C:\Program Files\Perforce;C:\apache-maven\bin"
Set objFSO = CreateObject("Scripting.FileSystemObject")
If objFSO.FolderExists("C:\WINDOWS\system32\WindowsPowerShell\v1.0") = True Then
    PATH = PATH & ";C:\WINDOWS\system32\WindowsPowerShell\v1.0"
End If
VS2003INSTALLDIR = "C:\Program Files (x86)\Microsoft Visual Studio .NET 2003"
VS2005INSTALLDIR = "C:\Program Files (x86)\Microsoft Visual Studio 8"
VS2008INSTALLDIR = "C:\Program Files (x86)\Microsoft Visual Studio 9.0"
MAVEN_OPTS       = "-Xms256m -Xmx512m"
JRE_DIR          = "C:\jdk16"

'Initializing a HashMap called StoppedServices
Set StoppedServices = CreateObject("Scripting.Dictionary")
For Each Service in Array("Network Associates McShield", "Network Associates Task Manager", "FTP Publishing Service", "IIS Admin Service", "Indexing Service", "NetOpt Helper", "Print Spooler", "Windows Firewal", "Wireless Configuration", "World Wide Web Publishing Service", "Symantec AntiVirus Definition Watcher", "Symantec AntiVirus")
    StoppedServices.add Service, 0
Next

'Initiatializing 4 regular expression containers used for grabbing arguments later
Set reHelpArgument = new regexp
reHelpArgument.Pattern = "^-he?l?p?"
Set reRepairArgument = new regexp
reRepairArgument.Pattern = "^-r$"
Set reDevArgument = new regexp
reDevArgument.Pattern = "^-d$"
Set reQuietArgument = new regexp
reQuietArgument.Pattern = "^-q$"

Set colArguments = Wscript.arguments 'returns the collection of arguments supplied when invoking the current script

'still getting arguments
For Each Argument In colArguments
    Set colMatches = reHelpArgument.execute(Argument)
    If colMatches.count > 0 Then Usage() End If
    Set colMatches = reRepairArgument.execute(Argument)
    If colMatches.count > 0 Then
        Repair = true
    End If
    Set colMatches = reDevArgument.execute(Argument)
    If colMatches.count > 0 Then
        Dev = true
    End If
    Set colMatches = reQuietArgument.execute(Argument)
    If colMatches.count > 0 Then
        Quiet = true
    End If
Next

'still at info gathering
Set objNetwork = CreateObject("WScript.Network") 
ComputerName = objNetwork.ComputerName
Set objWMI = GetObject( "winmgmts:\\" & ComputerName & "\root\cimv2" )
Set objRegistries = GetObject("winmgmts:{impersonationLevel=impersonate}!\\" & ComputerName & "\root\default:StdRegProv")
Set objProcess = GetObject("winmgmts:\\" & ComputerName & "\root\cimv2:Win32_Process")
Set WshShell = WScript.CreateObject("WScript.Shell")
Set colEnvironment = objWMI.ExecQuery("Select * from Win32_Environment")
Set SysEnv = WshShell.Environment("SYSTEM") 'Displaying Computer-specific PATH Environment Variables 
Set objApplication = CreateObject("Shell.Application")
Const HKEY_LOCAL_MACHINE = &H80000002
LoginName = objNetWork.UserName
LoginDomain = objNetwork.UserDomain

'if you need to repair, you need to grab some friles from wdf\buildtools, this code map wdf\buildtools to a drive letter
If Repair = True Then
    ' MAP Install Path
	' find an empty drive location and map it to wdf dropzone\BuildTools
    Set oDrives = objNetwork.EnumNetworkDrives 'all mapped network drives name
    Set MappedDrives = CreateObject("Scripting.Dictionary")
    For i = 0 to oDrives.Count - 1 Step 2
	    MappedDrives.add oDrives.Item(i), 0
    Next
    aDrives= Array("A:","B:","C:","D:","E:","F:","G:","H:","I:","J:","K","L:","M:","N:","O:","P:","Q:","R:","S:","T:","U:","V:","W:","X:","Y:","Z:")
    For Each Drive in aDrives 
        If MappedDrives.Exists(Drive) = False Then
            InstallDrive = Drive
	End If
    Next
    If IsEmpty(InstallDrive) = True Then
        Wscript.Echo("ERROR: free drive not found")
        Wscript.Quit()
    End If
    objNetwork.MapNetworkDrive InstallDrive, "\\build-drops-wdf\BuildTools"
End If

''''''''
' Main '
''''''''

'just printing out computer's domain and workgroup as info, nothing much
Wscript.Echo("############")
Wscript.Echo("# Computer #")
Wscript.Echo("############")
Wscript.Echo()
Wscript.Echo("Name: " & ComputerName)
Set colItems = objWMI.ExecQuery("Select * from Win32_ComputerSystem", , 48)
For Each objItem in colItems
    ComputerDomain = objItem.Domain
    If objItem.PartOfDomain Then
        WScript.Echo("Domain: " & ComputerDomain)
    Else
        WScript.Echo("Workgroup: " & ComputerDomain)
    End If
Next

'just printing out user's loginname and logindomain, it does a check and only allow certain users to use this script, and it would quit if the user is not one of them
Wscript.Echo()
Wscript.Echo("########")
Wscript.Echo("# User #")
Wscript.Echo("########")
Wscript.Echo()
Wscript.Echo("Name: " & LoginName)
Wscript.Echo("Domain: " & LoginDomain)
If Dev = False Then
    Set objGroup = GetObject("WinNT://" & ComputerName & "/Administrators,Group")
    If (LoginName <> "Builder" And LoginName <> "builder" And LoginName <> "psbuild" And LoginName <> "pblack" And LoginName <> "PBLACK"  And LoginName <> "porange") Or (LoginDomain <> "PGDEV" And LoginDomain <> "SAP_ALL" And LoginDomain <> "GLOBAL") Or (objGroup.IsMember("WinNT://PGDEV/Builder")=False And objGroup.IsMember("WinNT://SAP_ALL/Builder")=False And objGroup.IsMember("WinNT://SAP_ALL/psbuild")=False And objGroup.IsMember("WinNT://SAP_ALL/pblack")=False And objGroup.IsMember("WinNT://SAP_ALL/porange")=False And objGroup.IsMember("WinNT://GLOBAL/porange")=False And objGroup.IsMember("WinNT://GLOBAL/pblack")=False And objGroup.IsMember("WinNT://GLOBAL/PBLACK")=False And objGroup.IsMember("WinNT://GLOBAL/psbuild")=False) Then
        Wscript.Echo("ERROR: User must be SAP_ALL\pblack, PGDEV\Builder, SAP_ALL\Builder, GLOBAL\porange, GLOBAL\pblack, GLOBAL\PBLACK, SAP_ALL\porange, GLOBAL\psbuild or SAP_ALL\psbuild in the Administrators group")
        Wscript.Quit 0	
    End If
End If

'prints out windows' info, check if windows' version is right.
Wscript.Echo()
Wscript.Echo("####################")
Wscript.Echo("# Operating System #")
Wscript.Echo("####################")
Wscript.Echo()
Set colOS = objWMI.ExecQuery("SELECT * FROM Win32_OperatingSystem")
For Each objOS in colOS
    Wscript.Echo("Caption: " & objOS.Caption)
    Wscript.Echo("Service Pack: " & objOS.ServicePackMajorVersion & "." & objOS.ServicePackMinorVersion)
    Wscript.Echo("Version: " & objOS.Version)
    If objOS.Caption <> "Microsoft(R) Windows(R) Server 2003 Enterprise x64 Edition" Or (objOS.ServicePackMajorVersion <> 1 And objOS.ServicePackMajorVersion <> 2)  Or objOS.ServicePackMinorVersion <> 0 Then
        Wscript.Echo("ERROR: the OS must be 'Microsoft(R) Windows(R) Server 2003 R2, Enterprise x64 Edition SP2' in " & ComputerName)
    End If
Next

'this section only prints, no checking performed.
Wscript.Echo()
Wscript.Echo("############")
Wscript.Echo("# Hardware #")
Wscript.Echo("############")
Wscript.Echo()
Set colProcessors = objWMI.ExecQuery("SELECT * FROM Win32_Processor")
For Each objProcessor In colProcessors
    Wscript.Echo("Processor: " & objProcessor.Name)
Next
Set colComputerSystems = objWMI.ExecQuery("SELECT * FROM Win32_ComputerSystem")
For Each objComputerSystem In colComputerSystems 
    Wscript.Echo("Total Physical Memory: " & Int(objComputerSystem.TotalPhysicalMemory/1073741824*100)/100 & " GB")
Next
Set colDisks = objWMI.ExecQuery("SELECT * FROM Win32_LogicalDisk WHERE DriveType = 3")
For Each objDisk in colDisks
    Wscript.Echo("Hard Disk " &  objDisk.Name & " (" & Int(objDisk.Size/1073741824*100)/100 & " GB)")
Next

'stop the services in the StoppedService List
Wscript.Echo()
Wscript.Echo("############")
Wscript.Echo("# Services #")
Wscript.Echo("############")
Wscript.Echo()
Set colService = objWMI.ExecQuery("SELECT * FROM Win32_Service")
For Each objService In colService
    Wscript.Echo(objService.Caption & " is " & objService.State)
    If objService.State <>  "Stopped" And StoppedServices.exists(objService.Caption) Then
        Wscript.Echo("ERROR: " & objService.Caption & " is " & objService.State & " in " & ComputerName)
        If Repair = True Then
            If MsgBox("Do you want stop this service?", vbYesNoCancel, "Service '"  & objService.Caption & "'") = vbYes Then
                objService.StopService()
                objService.ChangeStartMode("Manual")
            End If
	    End If
    End If
Next

'it checks network configuration, and fixes it
Wscript.Echo()
Wscript.Echo("#####################")
Wscript.Echo("# DNS Domain Suffix #")
Wscript.Echo("#####################")
Wscript.Echo()
Set colNetwork = objWMI.ExecQuery("SELECT * FROM Win32_NetworkAdapterConfiguration WHERE IPEnabled = True")
For Each objNet In colNetwork
    Wscript.Echo(objNet.Caption)
    Set DNSDomainSuffixes = CreateObject("Scripting.Dictionary")
    If IsArray(objNet.DNSDomainSuffixSearchOrder) Then
        For i=0 To UBound(objNet.DNSDomainSuffixSearchOrder)
            Wscript.Echo(vbTab & objNet.DNSDomainSuffixSearchOrder(i))
            If DNSDomainSuffixes.Exists(objNet.DNSDomainSuffixSearchOrder(i)) = False Then
                DNSDomainSuffixes.Add objNet.DNSDomainSuffixSearchOrder(i), 0
            End If
        Next
    End If
    If DNSDomainSuffixes.Exists("crystald.net") = False Then
        Wscript.Echo("ERROR: DNS Domain Suffix 'crystald.net' is  not found in " & ComputerName)                                                                
        If Repair = True Then
    	    If MsgBox("Do you want add 'crystald.net' in this network", vbYesNoCancel, "Network '" & objNet.Caption & "'") = vbYes Then
                DNSDomainSuffixes.Add "crystald.net", 0
                Set objNetworkSettings = objWMI.Get("Win32_NetworkAdapterConfiguration")
                objNetworkSettings.SetDNSSuffixSearchOrder(DNSDomainSuffixes.Keys)
	        End If
        End If
    End If
Next

'it checks if env variables (TMP, TEMP, SITE) are all set, but you still have to input manually when it complains, 
Wscript.Echo()
WScript.Echo("#########################")
WScript.Echo("# Environment Variables #")
WScript.Echo("#########################")
Wscript.Echo()
If objFSO.FolderExists("C:\TEMP") = False Then
    WScript.Echo("ERROR 'C:\TEMP' not found")
    If Repair = True Then
    	If MsgBox("Do you want create 'C:\Temp' folder?", vbYesNoCancel, "Folder 'C:\Temp'") = vbYes Then
	    objFSO.CreateFolder("C:\TEMP")
	End If
    End If
End If
Set Environments = CreateObject("Scripting.Dictionary")
For Each objEnvironment In colEnvironment
    Wscript.Echo(objEnvironment.Name & "=" & objEnvironment.VariableValue)
    If Left(objEnvironment.VariableValue, 1)<>"%" And Environments.Exists(objEnvironment.Name)=False Then
        Environments.Add objEnvironment.Name, objEnvironment.VariableValue
    End If
Next
If Environments.Exists("SITE") = False Then
    WScript.Echo("ERROR: Environment variable 'SITE' not found in " & ComputerName)                                                                
    If Repair = True Then
    	If MsgBox("Do you want create 'SITE' environment variable?", vbYesNoCancel, "Environment variable 'SITE'") = vbYes Then
    	    sSite = InputBox("Options are 'Walldorf' or 'Levallois' or 'Vancouver'" & vbCrLf & "Enter a new value", "Creating SITE environment variable") 
	        SysEnv("SITE") = sSite
            Environments.Add "SITE", sSite
	    End If
    End If
Else
    If Environments.Item("SITE")<>"Walldorf" And Environments.Item("SITE")<>"Levallois" And Environments.Item("SITE")<>"Vancouver" Then
        WScript.Echo("ERROR: Environment variable 'SITE' value is wrong in " & ComputerName)                                                                
        If Repair = True Then
    	    If MsgBox("Do you want change 'SITE' environment variable value?", vbYesNoCancel, "Environment variable 'SITE'") = vbYes Then
    	        sSite = InputBox("Options are 'Walldorf' or 'Levallois' or 'Vancouver'" & vbCrLf & "Enter a new value", "Creating SITE environment variable") 
	            SysEnv("SITE") = sSite
                Environments.Item("SITE") = sSite
	        End If
        End If
    End If
End If
If Environments.Exists("TEMP") = False Then
    WScript.Echo("ERROR: Environment variable 'TEMP' not found in " & ComputerName)                                                                
    If Repair = True Then
    	If MsgBox("Do you want create 'TEMP' environment variable?", vbYesNoCancel, "Environment variable 'TEMP'") = vbYes Then
	        SysEnv("TEMP") = "C:\Temp"
	    End If
    End If
Else
    If Environments.Item("TEMP")<>"C:\Temp" And Environments.Item("TEMP")<>"D:\Temp" Then
        WScript.Echo("ERROR: Environment variable 'TEMP' value is wrong in " & ComputerName)                                                                
        If Repair = True Then
    	    If MsgBox("Do you want change 'TEMP' environment variable value?", vbYesNoCancel, "Environment variable 'TEMP'") = vbYes Then
	            SysEnv("TEMP") = "C:\Temp"
	        End If
        End If
    End If
End If
If Environments.Exists("TMP") = False Then
    WScript.Echo("ERROR: Environment variable 'TMP' not found in " & ComputerName)                                                                
    If Repair = True Then
    	If MsgBox("Do you want create 'TMP' environment variable?", vbYesNoCancel, "Environment variable 'TMP'") = vbYes Then
	        SysEnv("TMP") = "C:\Temp"
	    End If
    End If
Else
    If Environments.Item("TMP")<>"C:\Temp" And Environments.Item("TMP")<>"D:\Temp" Then
        WScript.Echo("ERROR: Environment variable 'TMP' value is wrong in " & ComputerName)                                                                
        If Repair = True Then
    	    If MsgBox("Do you want change 'TMP' environment variable value?", vbYesNoCancel, "Environment variable 'TMP'") = vbYes Then
	            SysEnv("TMP") = "C:\Temp"
	        End If
        End If
    End If
End If

'check if .net framwork 2.0 is installed, and prompt to see if you want to install it if it isn;t already installed.
Wscript.Echo()
WScript.Echo("##########################")
WScript.Echo("# .NET Framework 2.0 SP1 #")
WScript.Echo("##########################")
Wscript.Echo()
objRegistries.GetDWORDValue HKEY_LOCAL_MACHINE, "SOFTWARE\Microsoft\NET Framework Setup\NDP\v2.0.50727", "Install", iValue
If IsNull(iValue) Or iValue <> 1  Then
    Wscript.Echo("ERROR: .NET Framework 2.0.50727 not found")
    If Repair = True Then
        If MsgBox("Do you want install .NET Framework 2.0 SP1 2.0.50727", vbYesNoCancel, ".NET Framework 2.0 SP1") = vbYes Then
            WshShell.Run "cmd /c " & InstallDrive & "\win32_x86\Microsoft\NetFx20SP1_x86.exe", 0, True
        End If
    End If
Else
    Wscript.Echo(".NET Framework 2.0 SP1 version 2.0.50727")
End If

'check if terminal service settings is correct, and prompt to fix it
Wscript.Echo()
WScript.Echo("####################")
WScript.Echo("# Terminal Service #")
WScript.Echo("####################")
Wscript.Echo()
Set colTS = objWMI.ExecQuery("Select * from Win32_TerminalServiceSetting")
For Each objTS in colTS
    Wscript.Echo("Use temporary folders per session: " & objTS.UseTempFolders) 
    If objTS.UseTempFolders = 1 Then
        Wscript.Echo("ERROR: Use tempory folders per session must be 'No' in " & ComputerName)
        If Repair = true Then
            If MsgBox("Do you want disable 'use tempory folders per session' policy?", vbYesNoCancel, "Terminal Service Configuration") = vbYes Then
                objTS.SetPolicyPropertyName "UseTempFolders", 0
            End If
        End If
    End If
Next

'install perl if version is wrong
Wscript.Echo()
WScript.Echo("########")
WScript.Echo("# Perl #")
WScript.Echo("########")
PerlHeader = vbCrLf & "This is perl, v5.8.7 built for MSWin32-x86-multi-thread" & vbCrLf & "(with 7 registered patches, see perl -V for more detail)" & vbCrLf & vbCrLf & "Copyright 1987-2005, Larry Wall" & vbCrLf & vbCrLf & "Binary build 813 [148120] provided by ActiveState http://www.ActiveState.com" & vbCrLf & "ActiveState is a division of Sophos." & vbCrLf & "Built Jun  6 2005 13:36:37" & vbCrLf & vbCrLf & "Perl may be copied only under the terms of either the Artistic License or the" & vbCrLf & "GNU General Public License, which may be found in the Perl 5 source kit." & vbCrLf & vbCrLf & "Complete documentation for Perl, including FAQ lists, should be found on" & vbCrLf & "this system using `man perl' or `perldoc perl'.  If you have access to the" & vbCrLf & "Internet, point your browser at http://www.perl.org/, the Perl Home Page." & vbCrLf & vbCrLf
objProcess.Create("cmd /c perl -v >C:\Temp\Perl.txt 2>&1")
WScript.Sleep(5 * 1000)
Set objFile = objFSO.OpenTextFile("C:\Temp\Perl.txt", 1)
CurrentHeader = objFile.ReadAll
WScript.Echo(CurrentHeader)
If CurrentHeader =  "'perl' is not recognized as an internal or external command," & vbCrLf & "operable program or batch file." & vbCrLf Then
    Wscript.Echo("ERROR: Perl not found")
Else
    If CurrentHeader <> PerlHeader Then
        Wscript.Echo("ERROR: Perl version is wrong")
    End If
End If
If CurrentHeader <> PerlHeader And Repair = True Then
    If MsgBox("Do you want install ActivePerl 5.8.7.813", vbYesNoCancel, "Perl Installation") = vbYes Then
        WshShell.Run "cmd /c " & InstallDrive & "\win32_x86\ActiveState\ActivePerl-5.8.7.813-MSWin32-x86-148120.msi", 0, True
        SysEnv("PATH") = SysEnv("PATH") & ";C:\Perl\bin"
        objFSO.CopyFile InstallDrive & "\win32_x86\ActiveState\Packages\install.pl", "C:\Temp\install.pl", True
        WshShell.Run "cmd /c set SITE=" & Environments.Item("SITE") & "& set PATH=" & Environments.Item("Path") & "& perl C:\Temp\install.pl", 1, True
        WshShell.Run "cmd /c set PATH=" & SysEnv("PATH") & " & " & InstallDrive & "\win32_x86\Perforce\p4perl58-setup.exe", 0, True
    End If
End If

Wscript.Echo("##########")
Wscript.Echo("# Cygwin #")
Wscript.Echo("##########")
WScript.Echo()
CygwinHeader = "GNU bash, version 3.00.16(11)-release (i686-pc-cygwin)" & vbLf & "Copyright (C) 2004 Free Software Foundation, Inc." & vbLf
objProcess.Create("cmd /c bash --version > C:\Temp\Cygwin.txt 2>&1")
WScript.Sleep(5 * 1000)
Set objFile = objFSO.OpenTextFile("C:\Temp\Cygwin.txt", 1)
CurrentCygwinHeader = objFile.ReadAll
Wscript.Echo(CurrentCygwinHeader)
If CurrentCygwinHeader =  "'bash' is not recognized as an internal or external command," & vbCrLf & "operable program or batch file." & vbCrLf Then
    Wscript.Echo("ERROR: Cygwin not found")
Else
    If CurrentCygwinHeader <> CygwinHeader Then
        Wscript.Echo("ERROR: cygwin version is wrong")
    End If
End If

If CurrentCygwinHeader <> CygwinHeader And Repair = True Then
    If MsgBox("Do you want install Cygwin 1.5.18-1", vbYesNoCancel, "Cygwin Installation") = vbYes Then
        WshShell.Run "cmd /c " & InstallDrive & "\win32_x86\CygWin\1.5.18-1\setup.exe", 0, True
        SysEnv("PATH") = SysEnv("PATH") & ";C:\cygwin\bin"
        WshShell.Run "cmd /c " & InstallDrive & "\win32_x86\Projects\Build_Machine_SoftwareUpdate\cygwin_vs7.reg", 0, True
        WshShell.Run "cmd /c " & InstallDrive & "\win32_x86\CygWin\1.5.18-1\snapshots\20050811.zip & pause", 1, True
        If objFSO.FileExists("C:\cygwin\bin\perl.exe")=True Then objFSO.MoveFile "C:\cygwin\bin\perl.exe" , "C:\cygwin\bin\perl.exe.orig" End If
        If objFSO.FileExists("C:\cygwin\bin\msvcp71.dll")=True Then objFSO.MoveFile "C:\cygwin\bin\msvcp71.dll" , "C:\cygwin\bin\msvcp71.dll.orig" End If
        If objFSO.FileExists("C:\cygwin\bin\msvcr71.dll")=True Then objFSO.MoveFile "C:\cygwin\bin\msvcr71.dll" , "C:\cygwin\bin\msvcr71.dll.orig" End If
        If objFSO.FileExists("C:\cygwin\bin\link.exe")=True Then objFSO.MoveFile "C:\cygwin\bin\link.exe" , "C:\cygwin\bin\link.exe.orig" End If
        If objFSO.FileExists("C:\cygwin\bin\mt.exe")=True Then objFSO.MoveFile "C:\cygwin\bin\mt.exe" , "C:\cygwin\bin\mt.exe.orig" End If
        If objFSO.FileExists("C:\cygwin\bin\mc.exe")=True Then objFSO.MoveFile "C:\cygwin\bin\mc.exe" , "C:\cygwin\bin\mc.exe.orig" End If
	    objRegistries.GetDWORDValue HKEY_LOCAL_MACHINE, "SOFTWARE\Cygnus Solutions\Cygwin", "heap_chunk_in_mb", iValue
        Wscript.Echo("HKEY_LOCAL_MACHINE\SOFTWARE\Cygnus Solutions\Cygwin\heap_chunk_in_mb=" & iValue)
        If IsNull(iValue) Or iValue <> 1024 Then
            Wscript.Echo("ERROR: the 'HKEY_LOCAL_MACHINE\SOFTWARE\Cygnus Solutions\Cygwin\heap_chunk_in_mb' registry value is wrong in " & ComputerName)
            If Repair = true Then
                If MsgBox("Do you want set '1024' value in this registry?", vbYesNoCancel, "Registry 'HKEY_LOCAL_MACHINE\SOFTWARE\Cygnus Solutions\Cygwin\heap_chunk_in_mb'") = vbYes Then
                    Return = objRegistries.SetDWORDValue(HKEY_LOCAL_MACHINE, "SOFTWARE\Cygnus Solutions\Cygwin", "heap_chunk_in_mb", 1024)
                    If (Return <> 0) Or (Err.Number <> 0) Then   
                        Wscript.Echo("SetDWORDValue failed. Error = " & Err.Number)'
                        Wscript.Quit 0
                    End If
                End If
            End If
        End If
        Set objFile = objFSO.OpenTextFile("C:\boot.ini" , 1)
        boot = objFile.ReadAll
        objFile.Close
        Set reNoExecute = new regexp
        reNoExecute.Pattern = "/noexecute=\w+"
        reNoExecute.IgnoreCase = True
        boot = reNoExecute.Replace(boot, "/noexecute=AlwaysOff")
        Set rePAE = new regexp
        rePAE.Pattern = "/PAE"
        rePAE.IgnoreCase = True
        boot = rePAE.Replace(boot, "")
        WshShell.Run "attrib -s -r -h c:\boot.ini", 0, True
        Set objFile = objFSO.OpenTextFile("c:\boot.ini", 2)
        objFile.Write boot
        objFile.Close
        WshShell.Run "attrib +s +r +h c:\boot.ini", 0, True
        CygwinUser = "Builder"
        If LoginUser <> "builder" or LoginUser <> "Builder" Then CygwinUser = LoginUser End If
        CygwinPath = "C:\cygwin\home\" & CygwinUser       
        SysEnv("HOME") = CygwinPath
        If objFSO.FolderExists(CygwinPath) = False Then
            If objFSO.FolderExists("C:\cygwin\home") = False Then objFSO.CreateFolder("C:\cygwin\home") End If
            objFSO.CreateFolder(CygwinPath)                    
        End If
        objFSO.CopyFolder InstallDrive & "\solaris_sparc\home" , CygwinPath, True
        WshShell.Run "C:\cygwin\bin\chmod 600  C:\cygwin\home\" & CygwinUser & "\.passwds", 0, True
        Set objFile = objFSO.OpenTextFile("C:\cygwin\etc\passwd" , 1)
        passwd = objFile.ReadAll
        objFile.Close
        Set rePasswd = new regexp
        rePasswd.Pattern = ":/cygdrive/c/Documents and Settings/" & CygwinUser & ":"
        passwd = rePasswd.Replace(passwd, ":/home/" & CygwinUser & ":")
        Set objFile = objFSO.OpenTextFile("C:\cygwin\etc\passwd", 2)
        objFile.Write passwd
        objFile.Close
    End If
End If

Wscript.Echo("########")
Wscript.Echo("# Java #")
Wscript.Echo("########")
Wscript.Echo()

Java32Header = "java version " & Chr(34) & "1.6.0_16" & Chr(34) & vbCrLf & "Java(TM) SE Runtime Environment (build 1.6.0_16-b01)" & vbCrLf & "Java HotSpot(TM) Client VM (build 14.2-b01, mixed mode, sharing)" & vbCrLf
Java64Header = "java version " & Chr(34) & "1.6.0_29" & Chr(34) & vbCrLf & "Java(TM) SE Runtime Environment (build 1.6.0_29-b11)" & vbCrLf & "Java HotSpot(TM) 64-Bit Server VM (build 20.4-b02, mixed mode)" & vbCrLf
objProcess.Create("cmd /c java -version > C:\Temp\java.txt 2>&1")
WScript.Sleep(5 * 1000)
Set objFile = objFSO.OpenTextFile("C:\Temp\java.txt", 1)
CurrentJavaHeader = objFile.ReadAll
Wscript.Echo(CurrentJavaHeader)
If CurrentCygwinHeader =  "'java' is not recognized as an internal or external command," & vbCrLf & "operable program or batch file." & vbCrLf Then
    Wscript.Echo("ERROR: java not found")
Else
    If CurrentJavaHeader <> Java32Header And CurrentJavaHeader <> Java64Header Then
        Wscript.Echo("WARNING: java version is wrong")
    End If
End If

If CurrentJavaHeader <> Java32Header Or CurrentJavaHeader <> Java64Header Then
    If Environments.Exists("JAVA_HOME") = True Then
        If SysEnv("JAVA_HOME") <> JRE_DIR Then
            Wscript.Echo("ERROR: JAVA_HOME environment variable value is wrong")
        End If
    Else
        Wscript.Echo("ERROR: JAVA_HOME is not set")
    End If
End If

If (CurrentJavaHeader = Java32Header Or CurrentJavaHeader = Java64Header) And SysEnv("JAVA_HOME") <> JRE_DIR And Repair Then
    If MsgBox("Do you want set JAVA_HOME variable with '"& JRE_DIR & "'?", vbYesNoCancel, "JAVA_HOME setting") = vbYes Then
        SysEnv("JAVA_HOME") = JRE_DIR    
    End If
End If

If CurrentJavaHeader <> Java64Header And Repair = True Then
    If Repair = True Then
        If MsgBox("Do you want install Java JDK 64 bits ?", vbYesNoCancel, "Java 1.6 JDK 64-Bit Installation") = vbYes Then
            WshShell.Run "cmd /c " & InstallDrive & "\win64_x64\Sun\Sun\jre-6u29-windows-x64.exe", 0, True
	        SysEnv("JAVA_HOME") = JRE_DIR
	        SysEnv("PATH") = SysEnv("PATH") & ";" & JRE_DIR
 	    End If
    End If
End If

If CurrentJavaHeader <> Java32Header And Repair = True Then
    If Repair = True Then
        If MsgBox("Do you want install Java 2 SDK?", vbYesNoCancel, "Java 1.6.0 SDK Installation") = vbYes Then
            WshShell.Run "cmd /c " & InstallDrive & "\win32_x86\Sun\j2sdk\jdk-6u16-windows-i586.exe", 0, True
	        SysEnv("JAVA_HOME") = JRE_DIR
	        SysEnv("PATH") = SysEnv("PATH") & ";" & JRE_DIR
 	    End If
    End If
End If


Wscript.Echo("#########################")
Wscript.Echo("# VisualStudio.Net 2003 #")
Wscript.Echo("#########################")
WScript.Echo()
VisualStudioNet2003Header = "Setting environment for using Microsoft Visual Studio .NET 2003 tools." & vbCrLf & "(If you have another version of Visual Studio or Visual C++ installed and wish" & vbCrLf & "to use its tools from the command line, run vcvars32.bat for that version.)" & vbCrLf
If Environments.Exists("VS2003INSTALLDIR") = True Then
    objProcess.Create("cmd /c """ & Environments.Item("VS2003INSTALLDIR") & "\Common7\Tools\vsvars32.bat"" > C:\Temp\VisualStudioNet2003.txt 2>&1")
    WScript.Sleep(5 * 1000)
    Set objFile = objFSO.OpenTextFile("C:\Temp\VisualStudioNet2003.txt" , 1)
    CurrentVisualStudioNet2003Header = objFile.ReadAll
    Wscript.Echo(CurrentVisualStudioNet2003Header)
    If CurrentVisualStudioNetHeader =  "'" & Environments.Item("VS2003INSTALLDIR") & "\Common7\Tools\vsvars32.bat' is not recognized as an internal or external command," & vbCrLf & "operable program or batch file." & vbCrLf Then
         Wscript.Echo("ERROR: VisualStudio.Net 2003 not found")
    Else
        If CurrentVisualStudioNet2003Header <> VisualStudioNet2003Header Then
            Wscript.Echo("ERROR: VisualStudio.Net 2003 version is wrong")
        End If
    End If
Else
    WScript.Echo("ERROR: VisualStudio.Net 2003 not found")
End If
If CurrentVisualStudioNet2003Header <> VisualStudioNet2003Header And Repair = True Then
    If MsgBox("Do you want install VisualStudio.Net 2003?", vbYesNoCancel, "Installation VisualStudio.Net 2003") = vbYes Then
        WshShell.Run "cmd /c " & InstallDrive & "\win32_x86\Microsoft\VS_2003_Ent\setup.exe & pause", 1, True
        objFSO.CopyFile InstallDrive & "\win32_x86\Microsoft\VS_2003_Ent\vcbuild.exe", "C:\Program Files\Microsoft Visual Studio .NET 2003\Vc7\vcpackages\vcbuild.exe", True
        WshShell.Run "cmd /c """ & InstallDrive & "\win32_x86\Microsoft\VS_2003_Ent\Patchs\WSE_20_SP3\Microsoft WSE 2.0 SP3.msi""", 0, True
        WshShell.Run "cmd /c " & InstallDrive & "\win32_x86\Microsoft\VS_2003_Ent\Patchs\237054_intl_i386\VS7.1-KB900410-X86-Enu.exe", 0, True
    End If
End If

Wscript.Echo("##################")
Wscript.Echo("# VisualStudio 8 #")
Wscript.Echo("##################")
WScript.Echo()
VisualStudio8Header = "Setting environment for using Microsoft Visual Studio 2005 x86 tools." & vbCrLf
If Environments.Exists("VS2005INSTALLDIR") = True Then
    objProcess.Create("cmd /c """ & Environments.Item("VS2005INSTALLDIR") & "\Common7\Tools\vsvars32.bat"" > C:\Temp\VisualStudio8.txt 2>&1")
    WScript.Sleep(5 * 1000)
    Set objFile = objFSO.OpenTextFile("C:\Temp\VisualStudio8.txt" , 1)
    CurrentVisualStudio8Header = objFile.ReadAll
    Wscript.Echo(CurrentVisualStudio8Header)
    If CurrentVisualStudio8Header =  "'" & Environments.Item("VS2005INSTALLDIR") & "\Common7\Tools\vsvars32.bat' is not recognized as an internal or external command," & vbCrLf & "operable program or batch file." & vbCrLf Then
         Wscript.Echo("ERROR: VisualStudio 8 not found")
    Else
        If CurrentVisualStudio8Header <> VisualStudio8Header Then
            Wscript.Echo("ERROR: VisualStudio 8 version is wrong")
        End If
    End If
Else
    WScript.Echo("ERROR: VisualStudio 8 not found")
End If
If CurrentVisualStudio8Header <> VisualStudio8Header And Repair = True Then
    If MsgBox("Do you want install VisualStudio 8?", vbYesNoCancel, "Installation VisualStudio 8") = vbYes Then
        WshShell.Run "cmd /c " & InstallDrive & "\win32_x86\Microsoft\VS_STD_2005\vs\setup.exe & pause", 1, True
        WshShell.Run "cmd /c " & InstallDrive & "\win32_x86\Microsoft\VS_STD_2005\SP1\WindowsServer2003-KB925336-x86-ENU.exe", 0, True
        WshShell.Run "cmd /c " & InstallDrive & "\win32_x86\Microsoft\VS_STD_2005\SP1\VS80sp1-KB926601-X86-ENU.exe", 0, True
    End If
End If

Wscript.Echo("##################")
Wscript.Echo("# XML Parser SDK #")
Wscript.Echo("##################")
WScript.Echo()
If objFSO.FolderExists("C:\Program Files (x86)\MSXML 4.0") = True Then
    WScript.Echo("Microsoft MSXML 4.0 Parser SDK")
Else
    WScript.Echo("ERROR: Microsoft XML 4.0 Parser SDK not found")
    If Repair = True Then
        If MsgBox("Do you want install Microsoft XML 4.0 Parser SDK?", vbYesNoCancel, "Installation 'Microsoft XML 4.0 Parser SDK'") = vbYes Then
            WshShell.Run "cmd /c " & InstallDrive & "\win32_x86\Microsoft\XML\4.0\msxml4.msi", 0, True
        End If
    End If
End If

WScript.Echo()
Wscript.Echo("#############")
Wscript.Echo("# UltraEdit #")
Wscript.Echo("#############")
WScript.Echo()
If objFSO.FolderExists("C:\Program Files\UltraEdit") = True Then
    WScript.Echo("UltraEdit-32 - v10.00")
Else
    If objFSO.FolderExists("C:\Program Files (x86)\UltraEdit-32") = True Then
        WScript.Echo("UltraEdit-32 - v11.10")
    Else
    	If objFSO.FolderExists("C:\Program Files (x86)\IDM Computer Solutions\UltraEdit-32") = True Then
  	        WScript.Echo("UltraEdit-32 - v12.20")
	    Else
            WScript.Echo("ERROR: UltraEdit not found")
            If Repair = True Then
                If MsgBox("Do you want install UltraEdit?", vbYesNoCancel, "Installation 'UltraEdit'") = vbYes Then
                    WshShell.Run "cmd /c """ & InstallDrive & "\win32_x86\IDM Computer Solutions\UltraEdit\10\Anglais\uesetup.exe""", 0, True
                End If
            End If
        End If
    End If
End If

'install perforce, problem is it sets P4USER=builder; it also prompt for p4 password
'it doesnt set P4PORT
WScript.Echo()
Wscript.Echo("############")
Wscript.Echo("# Perforce #")
Wscript.Echo("############")
WScript.Echo()
PerforceHeader1 = "Perforce - The Fast Software Configuration Management System." & vbCrLf & "Copyright 1995-2008 Perforce Software.  All rights reserved." & vbCrLf & "Rev. P4/NTX86/2008.1/168182 (2008/10/10)." & vbCrLf
PerforceHeader2 = "Perforce - The Fast Software Configuration Management System." & vbCrLf & "Copyright 1995-2008 Perforce Software.  All rights reserved." & vbCrLf & "Rev. P4/NTX64/2008.2/179173 (2008/12/05)." & vbCrLf
PerforceHeader3 = "Perforce - The Fast Software Configuration Management System." & vbCrLf & "Copyright 1995-2011 Perforce Software.  All rights reserved." & vbCrLf & "Rev. P4/NTX64/2010.2/295040 (2011/03/25)." & vbCrLf
objProcess.Create("cmd /c p4 -V > C:\Temp\Perforce.txt 2>&1")
WScript.Sleep(5 * 1000)
Set objFile = objFSO.OpenTextFile("C:\Temp\Perforce.txt" , 1)
CurrentPerforceHeader = objFile.ReadAll
Wscript.Echo(CurrentPerforceHeader)
If CurrentPerforceHeader =  "'p4' is not recognized as an internal or external command," & vbCrLf & "operable program or batch file." & vbCrLf Then
    Wscript.Echo("ERROR: Perforce not found")
Else
    If CurrentPerforceHeader<>PerforceHeader1 And CurrentPerforceHeader<>PerforceHeader2 And CurrentPerforceHeader<>PerforceHeader3 Then
        Wscript.Echo("ERROR: Perforce version is wrong")
    End If
End If
If CurrentPerforceHeader<>PerforceHeader1 And CurrentPerforceHeader<>PerforceHeader2 And CurrentPerforceHeader<>PerforceHeader3 And Repair = True Then
    If MsgBox("Do you want install Perforce 2008.1", vbYesNoCancel, "Perforce 2008.1 Installation") = vbYes Then
        WshShell.Run "cmd /c " & InstallDrive & "\win64_x64\Perforce\p4winst64_2008.1.176630.exe", 0, True
        WshShell.Run "cmd /c " & InstallDrive & "\win64_x64\Perforce\p4vinst64_2010.2.295040.exe", 0, True
        P4PASSWD = inputbox("P4PASSWD" , "Perforce Password")
        objProcess.Create("cmd /c p4 set P4USER=pblack")
        objProcess.Create("cmd /c p4 set P4PASSWD=" & P4PASSWD)
    End If
End If


Wscript.Echo("##########")
Wscript.Echo("# AppLoc #")
Wscript.Echo("##########")
WScript.Echo()
If objFSO.FileExists("C:\WINDOWS\AppPatch\AppLoc.exe") = True Then
    WScript.Echo("AppLoc")
Else
    WScript.Echo("ERROR: AppLoc not found")
    If Repair = True Then
        If MsgBox("Do you want install AppLoc?", vbYesNoCancel, "Installation 'AppLoc'") = vbYes Then
            objApplication.ControlPanelItem "intl.cpl"
            WshShell.Run "cmd /c pause", 1, True
            WshShell.Run "cmd /c " & InstallDrive & "\win32_x86\Microsoft\AppLoc\apploc.msi", 0, True
            objFSO.CopyFile InstallDrive & "\win32_x86\Microsoft\AppLoc\AppLoc.exe", "C:\WINDOWS\AppPatch\AppLoc.exe", True
        End If
    End If
End If

WScript.Echo()
Wscript.Echo("#########")
Wscript.Echo("# Maven #")
Wscript.Echo("#########")
WScript.Echo()
MavenHeader = "Apache Maven 2.2.1 (r801777; 2009-08-06"
objProcess.Create("cmd /c set MAVEN_OPTS=& mvn -v >C:\Temp\Maven.txt 2>&1")
WScript.Sleep(5 * 1000)
Set objFile = objFSO.OpenTextFile("C:\Temp\Maven.txt", 1)
CurrentHeader = objFile.ReadAll
WScript.Echo(CurrentHeader)
If CurrentHeader =  "'mvn' is not recognized as an internal or external command," & vbCrLf & "operable program or batch file." & vbCrLf Then
    Wscript.Echo("ERROR: mvn not found")
Else
    If Left(CurrentHeader, 39) <> MavenHeader Then
        Wscript.Echo("WARNING: Maven version is wrong")
    End If
End If
If Left(CurrentHeader, 39) <> MavenHeader And Repair = True Then
    If MsgBox("Do you want install Maven 2.2.1", vbYesNoCancel, "Maven Installation") = vbYes Then
        WshShell.Run "cmd /c " & InstallDrive & "\win32_x86\maven\apache-maven-2.2.1.zip & pause", 1, True
        objFSO.MoveFolder "C:\apache-maven-2.2.1" , "C:\apache-maven"
        objFSO.CopyFile InstallDrive & "\win32_x86\maven\" & SysEnv("SITE") & "\maven\settings.xml", "C:\apache-maven\conf\settings.xml", True
        SysEnv("M2_HOME") = "C:\apache-maven"
        SysEnv("M2") = "C:\apache-maven\bin"
        SysEnv("MAVEN_OPTS") = MAVEN_OPTS
        SysEnv("PATH") = SysEnv("PATH") & ";C:\apache-maven\bin"
    End If
End If
If (Environments.Exists("MAVEN_OPTS")=False Or SysEnv("MAVEN_OPTS")="") And Quiet = True Then
    WScript.Echo("ERROR: Environment variable 'MAVEN_OPTS' is empty or doesn't exist in " & ComputerName)
    SysEnv("MAVEN_OPTS") = MAVEN_OPTS
    WScript.Echo("INFO: Environment variable 'MAVEN_OPTS' is set with " & SysEnv("MAVEN_OPTS"))
End If                                                                
If Environments.Exists("MAVEN_OPTS")=False Or SysEnv("MAVEN_OPTS")="" Then
    WScript.Echo("ERROR: Environment variable 'MAVEN_OPTS' is empty or doesn't exist in " & ComputerName)
    If Repair = True Then
        If MsgBox("Do you want set 'MAVEN_OPTS' environment variable with '-Xms256m -Xmx512m'?", vbYesNoCancel, "Environment variable 'MAVEN_OPTS'") = vbYes Then
            SysEnv("MAVEN_OPTS") = MAVEN_OPTS
        End If
    End If
End If
If WshShell.ExpandEnvironmentStrings("%PATH%") <> PATH And WshShell.ExpandEnvironmentStrings("%PATH%") <> "C:\WINDOWS\Microsoft.NET\Framework\v2.0.50727;" & PATH Then
    WScript.Echo("WARNING: PATH environment variable value is wrong")
    WScript.Echo("INFO:  current PATH=" & WshShell.ExpandEnvironmentStrings("%PATH%"))
    WScript.Echo("INFO: required PATH=" & PATH)
    If Repair = True Then
        If MsgBox("Do you want set PATH variable with '"& PATH & "'?", vbYesNoCancel, "PATH setting") = vbYes Then
            SysEnv("PATH") = PATH    
        End If
    End If
End If
If Environments.Exists("VCINSTALLDIR") = True Then
    WScript.Echo("ERROR: Environment variable 'VCINSTALLDIR' must be removed in " & ComputerName)                                                                
    If Repair = True Then
        If MsgBox("Do you want remove 'VCINSTALLDIR' environment variable value?", vbYesNoCancel, "Environment variable 'VCINSTALLDIR'") = vbYes Then
            SysEnv.Remove("VCINSTALLDIR")
        End If
    End If
End If
If Environments.Exists("VS71COMNTOOLS") = True Then
    WScript.Echo("ERROR: Environment variable 'VS71COMNTOOLS' must be removed in " & ComputerName)                                                                
    If Repair = True Then
        If MsgBox("Do you want remove 'VS71COMNTOOLS' environment variable value?", vbYesNoCancel, "Environment variable 'VS71COMNTOOLS'") = vbYes Then
            SysEnv.Remove("VS71COMNTOOLS")
        End If
    End If
End If
If Environments.Exists("VS80COMNTOOLS") = True Then
    WScript.Echo("ERROR: Environment variable 'VS80COMNTOOLS' must be removed in " & ComputerName)                                                                
    If Repair = True Then
        If MsgBox("Do you want remove 'VS80COMNTOOLS' environment variable value?", vbYesNoCancel, "Environment variable 'VS80COMNTOOLS'") = vbYes Then
            SysEnv.Remove("VS80COMNTOOLS")
        End If
    End If
End If
If Environments.Exists("VSCOMNTOOLS") = True Then
    WScript.Echo("ERROR: Environment variable 'VSCOMNTOOLS' must be removed in " & ComputerName)                                                                
    If Repair = True Then
        If MsgBox("Do you want remove 'VSCOMNTOOLS' environment variable value?", vbYesNoCancel, "Environment variable 'VSCOMNTOOLS'") = vbYes Then
            SysEnv.Remove("VSCOMNTOOLS")
        End If
    End If
End If
If Environments.Exists("INCLUDE") = True Then
    WScript.Echo("ERROR: Environment variable 'INCLUDE' must be removed in " & ComputerName)                                                                
    If Repair = True Then
        If MsgBox("Do you want remove 'INCLUDE' environment variable value?", vbYesNoCancel, "Environment variable 'INCLUDE'") = vbYes Then
            SysEnv.Remove("INCLUDE")
        End If
    End If
End If
If Environments.Exists("LIB") = True Then
    WScript.Echo("ERROR: Environment variable 'LIB' must be removed in " & ComputerName)                                                                
    If Repair = True Then
        If MsgBox("Do you want remove 'LIB' environment variable value?", vbYesNoCancel, "Environment variable 'LIB'") = vbYes Then
            SysEnv.Remove("LIB")
        End If
    End If
End If
If SysEnv("VS2003INSTALLDIR") <> VS2003INSTALLDIR Then
    WScript.Echo("ERROR: VS2003INSTALLDIR environment variable value is wrong")
    If Repair = True Then
        If MsgBox("Do you want set VS2003INSTALLDIR variable with '"& VS2003INSTALLDIR & "'?", vbYesNoCancel, "VS2003INSTALLDIR setting") = vbYes Then
            SysEnv("VS2003INSTALLDIR") = VS2003INSTALLDIR    
        End If
    End If
End If
If SysEnv("VS2005INSTALLDIR") <> VS2005INSTALLDIR Then
    WScript.Echo("ERROR: VS2005INSTALLDIR environment variable value is wrong")
    If Repair = True Then
        If MsgBox("Do you want set VS2005INSTALLDIR variable with '"& VS2005INSTALLDIR & "'?", vbYesNoCancel, "VS2005INSTALLDIR setting") = vbYes Then
            SysEnv("VS2005INSTALLDIR") = VS2005INSTALLDIR    
        End If
    End If
End If
If SysEnv("VS2008INSTALLDIR") <> VS2008INSTALLDIR Then
    WScript.Echo("ERROR: VS2008INSTALLDIR environment variable value is wrong")
    If Repair = True Then
        If MsgBox("Do you want set VS2008INSTALLDIR variable with '"& VS2008INSTALLDIR & "'?", vbYesNoCancel, "VS2008INSTALLDIR setting") = vbYes Then
            SysEnv("VS2008INSTALLDIR") = VS2008INSTALLDIR    
        End If
    End If
End If

WScript.Echo()
Wscript.Echo("######################")
Wscript.Echo("# Installed Software #")
Wscript.Echo("######################")
WScript.Echo()
sBaseKey = "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\"
objRegistries.EnumKey HKEY_LOCAL_MACHINE, sBaseKey, aSubKeys
For Each sKey In aSubKeys
iRC = objRegistries.GetStringValue(HKEY_LOCAL_MACHINE, sBaseKey & sKey, "DisplayName", sValue)
If iRC <> 0 Then
    objRegistries.GetStringValue HKEY_LOCAL_MACHINE, sBaseKey & sKey, "QuietDisplayName", sValue
End If
If sValue <> "" Then
    iRC = objRegistries.GetStringValue(HKEY_LOCAL_MACHINE, sBaseKey & sKey, "DisplayVersion", sVersion)
    If sVersion <> "" Then
        Wscript.Echo(sValue & vbTab & "Ver:" & sVersion)
    Else
        sVersion = " "
        Wscript.Echo(sValue) 
    End If
End If
Next

If IsEmpty(InstallDrive) = False Then
    objNetwork.RemoveNetworkDrive InstallDrive
End If

'''''''''''''
' Functions '
'''''''''''''

Sub ReplaceAllByExpression(ByRef StringToExtract, ByVal MatchPattern, ByVal ReplacementText)
    Set regEx = New RegExp
    regEx.Pattern = MatchPattern
    regEx.IgnoreCase = True
    regEx.Global = True
    regEx.MultiLine = True
    StringToExtract = regEx.Replace(StringToExtract, ReplacementText)
    Set regEx = Nothing
End Sub

Sub Usage()
    Wscript.Echo("Usage   : cscript checkenv.vbs [-h] [-r] [-d]")
    Wscript.Echo("Example : cscript checkenv.vbs -h")
    Wscript.Echo("          cscript checkenv.vbs -r")
    Wscript.Echo("          cscript checkenv.vbs -d")
    Wscript.Echo()
    Wscript.Echo("  -help   argument displays helpful information about builtin commands.")
    Wscript.Echo("  -r      performs repair, default is no.")
    Wscript.Echo("  -q      repairs in quiet mode if possible, default is no.")
    Wscript.Echo("  -d      specifies it is for Developer environment, default is no.")
    Wscript.Quit 0
End Sub
