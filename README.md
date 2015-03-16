# WmiSploit

WmiSploit is a small set of PowerShell scripts that leverage the WMI service, for post-exploitation use. While the WmiSploit scripts do not have built-in pass-the-hash functionality, Invoke-TokenManipulation from the PowerSploit framework should provide a similar effect. WmiSploit scripts don't write any new files to disk, but their activities can be recovered by a defender who knows where to look.

###Invoke-WmiShadowCopy

Invoke-WmiShadowCopy creates a Volume Shadow Copy, links the Shadow Copy's Device Object to a directory in %TEMP%, then has the ability to get a file handle to locked files and copy them. The files being copied are exfiltrated through WMI by Base64 encoding the files, writing the Base64 strings to WMI namespaces, then querying those WMI namespaces from our attacker machine. After the file is exfiltrated, the shadow copy and its device object link are removed.

###Invoke-WmiCommand
###Enter-WmiShell

##TODO
---------
###Invoke-WmiRestorePoint
