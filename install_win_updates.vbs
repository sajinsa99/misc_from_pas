
exec_auto = False
test_mode = False

If WScript.Arguments.Count > 0 Then
	For I = 0 To WScript.Arguments.Count -1 
		If WScript.Arguments.Item(I) = "y" Then
			exec_auto = True
		End If
		If WScript.Arguments.Item(I) = "t" Then
			test_mode = True
		End If
	Next	
End If

If Not exec_auto Then
	WScript.Echo "launch "
	WScript.Echo "     cscript.exe install_win_updates.vbs y "
	WScript.Echo "to automaticaly install all the updates except the visual studio one"
	WScript.Echo
End If

Set updateSession = CreateObject("Microsoft.Update.Session")
updateSession.ClientApplicationID = "MSDN Sample Script"


If updateSession.ReadOnly Then
	WScript.Echo "Session readonly"
End If	
Set updateSearcher = updateSession.CreateUpdateSearcher()

WScript.Echo "Searching for updates..." & vbCRLF

Set searchResult = _
updateSearcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")

WScript.Echo "List of applicable items on the machine:"

For I = 0 To searchResult.Updates.Count-1
    Set update = searchResult.Updates.Item(I)
    WScript.Echo I + 1 & "> " & update.Title
Next

If searchResult.Updates.Count = 0 Then
    WScript.Echo "There are no applicable updates."
    WScript.Quit
End If




WScript.Echo vbCRLF & "Creating collection of updates to download:"

Set updatesToDownload = CreateObject("Microsoft.Update.UpdateColl")

nb_to_download = 0
MAX_DOWNLOAD = 1 

For I = 0 to searchResult.Updates.Count-1
    Set update = searchResult.Updates.Item(I)
    addThisUpdate = false
    If update.InstallationBehavior.CanRequestUserInput = true Then
        WScript.Echo I + 1 & ">   skipping: " & update.Title & _
        " because it requires user input"
    Else
    	If InStr(1,update.Title,"Visual Studio",1) > 0  Then
	        WScript.Echo I + 1 & ">   skipping: " & update.Title & _
	        " because it is Visual Studio update"
    	Else	
	        If update.EulaAccepted = false Then
	            WScript.Echo I + 1 & "> note: " & update.Title & _
	            " has a license agreement that must be accepted:"
	            WScript.Echo update.EulaText
	            WScript.Echo "Do you accept this license agreement? (Y/N)"
	            strInput = WScript.StdIn.Readline
	            WScript.Echo 
	            If (strInput = "Y" or strInput = "y") Then
	            	If ( Not test_mode Or nb_to_download < MAX_DOWNLOAD ) Then
	                	update.AcceptEula()
	                	addThisUpdate = true
	                	nb_to_download = nb_to_download + 1
	                End If
	            Else
	                WScript.Echo I + 1 & "> skipping: " & update.Title & _
	                " because the license agreement was declined"
	            End If
	        Else
	            If ( Not test_mode Or nb_to_download < MAX_DOWNLOAD ) Then
	            	addThisUpdate = true
	                nb_to_download = nb_to_download + 1
	            End If
	        End If
	    End If
    End If
    If addThisUpdate = true Then
        WScript.Echo I + 1 & "> adding: " & update.Title 
        updatesToDownload.Add(update)
    End If
Next



If updatesToDownload.Count = 0 Then
    WScript.Echo "All applicable updates were skipped."
    WScript.Quit
End If
    
WScript.Echo vbCRLF & "Downloading " & updatesToDownload.Count & " updates..."

Set downloader = updateSession.CreateUpdateDownloader() 
downloader.Updates = updatesToDownload
downloader.Download()

Set updatesToInstall = CreateObject("Microsoft.Update.UpdateColl")

rebootMayBeRequired = false

WScript.Echo vbCRLF & "Successfully downloaded updates:"

nb_to_install = 0
MAX_INSTALL = 1


For I = 0 To searchResult.Updates.Count-1
    set update = searchResult.Updates.Item(I)
    If update.IsDownloaded = true Then
    	If InStr(1,update.Title,"Visual Studio",1) > 0  Then
	        WScript.Echo I + 1 & ">   skipping: " & update.Title & _
	        " because it is Visual Studio update"
	    Else
	   		If ( Not test_mode Or nb_to_install < MAX_INSTALL ) Then
				nb_to_install = nb_to_install + 1
	        	WScript.Echo I + 1 & "> " & update.Title 
	        	updatesToInstall.Add(update) 
	        	If update.InstallationBehavior.RebootBehavior > 0 Then
	            	rebootMayBeRequired = true
	        	End If
	        End If
	    End If
    End If
Next

If updatesToInstall.Count = 0 Then
    WScript.Echo "No updates were successfully downloaded."
    WScript.Quit
End If

If rebootMayBeRequired = true Then
    WScript.Echo vbCRLF & "These updates may require a reboot."
End If
    
WScript.Echo updatesToInstall.Count & " updates will be installed."

If exec_auto Then
	strInput = "y"
Else

	WScript.Echo  vbCRLF & "Would you like to install updates now? (Y/N)"
	strInput = WScript.StdIn.Readline
	WScript.Echo 
End If

If (strInput = "Y" or strInput = "y") Then
    WScript.Echo "Installing updates..."
    Set installer = updateSession.CreateUpdateInstaller()
    installer.Updates = updatesToInstall
    Set installationResult = installer.Install()
 
    'Output results of install
    WScript.Echo "Installation Result: " & _
    GetErrorMsg(installationResult.ResultCode) 
    WScript.Echo "Reboot Required: " & _ 
    installationResult.RebootRequired & vbCRLF 
    WScript.Echo "Listing of updates installed " & _
    "and individual installation results:" 
 
    For I = 0 to updatesToInstall.Count - 1
        WScript.Echo I + 1 & "> " & _
        updatesToInstall.Item(i).Title & _
        ": " & GetErrorMsg(installationResult.GetUpdateResult(i).ResultCode)   
    Next

	result=MsgBox("Do you want to reboot the computer  ",4,"Reboot machine")
	If result = 6 Then
		WScript.Echo "Reboot in progress ..."
		
		strComputer = "." ' Local Computer
	
		SET objWMIService = GETOBJECT("winmgmts:{impersonationLevel=impersonate,(Shutdown)}!\\" & _
				strComputer & "\root\cimv2")
	
		SET colOS = objWMIService.ExecQuery("Select * from Win32_OperatingSystem")
	
		FOR EACH objOS in colOS
			objOS.Reboot()
		NEXT
	End If   
        
End If





Function GetErrorMsg(Err)
	Select Case(Err) 
		Case 0: 
 			GetErrorMsg = "The operation is not started."
		Case 1: 
 			GetErrorMsg = "The operation is in progress."
		Case 2: 
 			GetErrorMsg = "The operation was completed successfully."
		Case 3: 
 			GetErrorMsg = "The operation is complete, but one or more errors occurred during the operation. The results might be incomplete."
		Case 4: 
 			GetErrorMsg = "The operation failed to complete."
		Case 5: 
 			GetErrorMsg = "The operation is canceled."
		Case Else 
 			GetErrorMsg = "Not defined"
	End Select
End Function













