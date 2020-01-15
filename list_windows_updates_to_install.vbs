Dim ActualDay
Dim MyDay
Dim MyMonth

'Déclaration des constantes
Const ForReading = 1
Const ForWritting = 2
Const ForAppending = 8

'Determine actual date
MyDay = Day(Now)
MyMonth = Month(Now)

If Len(MyDay) = 1 Then
MyDay = "0" & MyDay
End If

If Len(MyMonth) = 1 Then
MyMonth = "0" & MyMonth
End If
ActualDay = Year(Now) & "-" & MyMonth & "-" & MyDay

Set objSession = CreateObject("Microsoft.Update.Session")
Set objSearcher = objSession.CreateUpdateSearcher
intHistoryCount = objSearcher.GetTotalHistoryCount

Set colHistory = objSearcher.QueryHistory(1, intHistoryCount)

Set objSearcher = objSession.CreateupdateSearcher()
'WScript.Echo "Searching for available updates..." & vbCRLF

Set searchResult = objSearcher.Search("IsInstalled=0")
WScript.Echo ""
WScript.Echo "List of applicable items on the machine:"

For I = 0 To searchResult.Updates.Count-1
Set update = searchResult.Updates.Item(I)
WScript.Echo "" & update.Title
Next

WScript.Echo ""
WScript.Echo "End of script" & wscript.scriptfullname

Wscript.Quit 0
