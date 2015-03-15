function Invoke-WmiCommand {
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
    
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [ScriptBlock]
    $ScriptBlock,

    [Parameter(Position = 0, ParameterSetName = 'FilePath' )]
    [ValidateNotNullOrEmpty()]
    [String]
    $Path

) # End Param

    if ($PSBoundParameters['Path']) {
        $null = Get-ChildItem $Path -ErrorAction Stop
        $ScriptBytes = [IO.File]::ReadAllBytes((Resolve-Path $Path))
    }
    else {
        $ScriptBytes = ([Text.Encoding]::ASCII).GetBytes($ScriptBlock)
    }

    $CompressedStream = New-Object IO.MemoryStream
    $DeflateStream = New-Object IO.Compression.DeflateStream ($CompressedStream, [IO.Compression.CompressionMode]::Compress)
    $DeflateStream.Write($ScriptBytes, 0, $ScriptBytes.Length)
    $DeflateStream.Dispose()
    $CompressedScriptBytes = $CompressedStream.ToArray()
    $CompressedStream.Dispose()
    $EncodedCompressedScript = [Convert]::ToBase64String($CompressedScriptBytes)

    $WmiEncoded = $EncodedCompressedScript -replace '\+',[char]0x00F3 -replace '/','_' -replace '=',''
    $NumberOfPieces = [Math]::Floor($WmiEncoded.Length / 5500)

    if ($WmiEncoded.Length -gt 5500) {
        $LastPiece = $WmiEncoded.Substring($WmiEncoded.Length - ($WmiEncoded.Length % 5500), ($WmiEncoded.Length % 5500))
        $WmiEncoded = $WmiEncoded.Remove($WmiEncoded.Length - ($WmiEncoded.Length % 5500), ($WmiEncoded.Length % 5500))
        
        for($i = 1; $i -le $NumberOfPieces; $i++) { 
	        $piece = $WmiEncoded.Substring(0,5500)
		    $WmiEncoded = $WmiEncoded.Substring(5500,($WmiEncoded.Length - 5500))
		    Upload-Piece -ComputerName $ComputerName -UserName $UserName -Namespace $Namespace -Tag $Tag -Piece $piece -Count $i
        }
        $WmiEncoded = $LastPiece
    }
	Upload-Piece -ComputerName $ComputerName -UserName $UserName -Namespace $Namespace -Tag $Tag -Piece $WmiEncoded -Count ($NumberOfPieces + 1)
    $null = Set-WmiInstance -EnableAllPrivileges -ComputerName $ComputerName -UserName $UserName -Namespace $Namespace -Path __Namespace -PutType CreateOnly -Arguments @{Name='SCRIPT_UPLOADED'}

    $RemoteScript = @"
    do{`$ScriptUploaded = Get-WmiObject -Namespace $Namespace -Query "SELECT Name FROM __Namespace WHERE Name LIKE 'SCRIPT_UPLOADED'"}
    until(`$ScriptUploaded)
    Get-WmiObject -Namespace $Namespace -Query "SELECT * FROM __Namespace WHERE Name LIKE 'SCRIPT_UPLOADED'" | Remove-WmiObject

    Set-Alias a New-Object
    `$ReconstructedScriptBlock = a System.Text.StringBuilder

    `$GetScriptBlock = Get-WmiObject -Namespace $Namespace -Query "SELECT Name FROM __Namespace WHERE Name like '$Tag%'" | % {`$_.Name} | Sort-Object
    foreach (`$line in `$GetScriptBlock) {
	    `$WmiToBase64 = `$line.Remove(0,14) -replace [char]0x00F3,[char]0x002B -replace '_','/'
        `$WmiToBase64 = `$WmiToBase64.Remove(`$WmiToBase64.Length - 14, 14)
	    `$null = `$ReconstructedScriptBlock.Append(`$WmiToBase64)
    }
    if (`$ReconstructedScriptBlock.ToString().Length % 4 -ne 0) { `$null = `$ReconstructedScriptBlock.Append(("===").Substring(0, 4 - (`$ReconstructedScriptBlock.ToString().Length % 4))) }
    `$ScriptBlock = (a IO.StreamReader((a IO.Compression.DeflateStream([IO.MemoryStream][Convert]::FromBase64String("`$ReconstructedScriptBlock"),[IO.Compression.CompressionMode]::Decompress)),[Text.Encoding]::ASCII)).ReadToEnd()

    Invoke-Command  -ScriptBlock {`$ScriptBlock}  
"@
    $scriptBlock = [scriptblock]::Create($RemoteScript)
    $encPosh = Out-EncodedCommand -NumberOfPiecesrofile -NonInteractive -ScriptBlock $scriptBlock
    $null = Invoke-WmiMethod -ComputerName $ComputerName -Credential $UserName -Class win32_process -Name create -ArgumentList $encPosh
                    
    # Wait for script to finish writing output to WMI namespaces
    $outputReady = ""
    do{$outputReady = Get-WmiObject -ComputerName $ComputerName -Credential $UserName -Namespace $Namespace -Query "SELECT Name FROM __Namespace WHERE Name like 'OUTPUT_READY'"}
    until($outputReady)
    $null = Get-WmiObject -Credential $UserName -ComputerName $ComputerName -Namespace $Namespace -Query "SELECT * FROM __Namespace WHERE Name LIKE 'OUTPUT_READY'" | Remove-WmiObject
                    
    # Retrieve cmd output written to WMI namespaces 
    Get-WmiShellOutput -UserName $UserName -ComputerName $ComputerName
}


    