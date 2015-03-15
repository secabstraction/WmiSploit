function New-WmiSession {
Param (	
    [Parameter(Position = 0, Mandatory = $True)]
    [string]
    $ComputerName,
    
    [Parameter(Position = 1)]
    [ValidateNotNull()]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $UserName = [System.Management.Automation.PSCredential]::Empty,

    [Parameter(Position = 2, ParameterSetName = 'Default')]
    [string]
    $Namespace = "root\default",

    [Parameter(Position = 3)]
    [string]
    $Tag = ([System.IO.Path]::GetRandomFileName()).Remove(8,4),
    
    [Parameter(Position = 4, ParameterSetName = 'Random')]
    [switch]
    $RandomNamespace
) # End Param

    if ( $PSBoundParameters['RandomNamespace'] ) 
    { $Namespace = ([System.IO.Path]::GetRandomFileName()).Remove(8,4) }
    if ( $PSBoundParameters['UserName'] ) 
    { $UserName = Get-Credential -Credential $UserName }

    #Check for existence of WMI Namespace specified by user
    $CheckNamespace = [bool](Get-WmiObject -ComputerName $ComputerName -Credential $UserName -Namespace root -Class __Namespace -ErrorAction SilentlyContinue | `
                             ? {$_.Name -eq $Namespace})
    if ( !$CheckNamespace ) 
    { $null = Set-WmiInstance -EnableAll -ComputerName $ComputerName -Credential $UserName -Namespace root -Class __Namespace -Arguments @{Name=$Namespace} }
    $Namespace = "root\" + $Namespace

    $props = @{
        'ComputerName' = $ComputerName
        'UserName' = $UserName
        'Namespace' = $Namespace
        'Tag' = $Tag
    }
    New-Object -TypeName PSObject -Property $props
}