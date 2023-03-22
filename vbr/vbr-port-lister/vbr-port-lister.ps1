<# 
.NAME
    Veeam Backup & Replication Port Lister
.DESCRIPTION
    Powershell script to quickly visualize the required ports that need to be opened for communication between Veeam components.
.NOTES  
    File Name  : vbr-port-lister.ps1
    Author     : Stephan Herzig, Veeam Software (stephan.herzig@veeam.com)
    Requires   : A running Windows PC with Powershell
.USAGE
	The following two parameter must be given: 
		-ServicesFile		- Number of days back you want to 
		-Source             - Name of the Source Service
		-Destination        - Optional / Name of the Destination Service
  Example   
  `PS>.\vbr-port-lister.ps1 -ServicesFile .\services.txt -Source "Windows Proxy" -Destination "Linux Repository"
.VERSION
    1.0
#>
Param(
    [Parameter(Mandatory=$true)]
    [string]$ServicesFile,
    [Parameter(Mandatory=$true)]
    [string]$Source,
    [Parameter(Mandatory=$false)]
    [string]$Destination
)

# Read the .txt file
$services          = Get-Content $ServicesFile

# Split up the information from the Services File
$relationships     = foreach ($serviceline in $services) {
       $sourceName = $serviceline.Split(":")[0]
       $destName   = $serviceline.Split(":")[1]
       $destPorts  = $serviceline.Split(":")[2] -split ","
       $descPorts  = $serviceline.Split(":")[3] 
       
       [PSCustomObject]@{
       "Source Service"      = $sourceName
       "Destination Service" = $destName
       "Destination Port(s)" = $destPorts -join ","
       "Description"         = $descPorts
            }
        }

# Filter Result      
if ($Filter -eq "all") {
    $relationships | Format-Table
} else {
    #$relationships | Where-Object { $_."Source Service" -match $Source} | Format-Table -AutoSize
    #$relationships | Where-Object { $_."Source Service" -match $Source -or $_."Destination Service" -match $Destination } | Format-Table
    $relationships | Where-Object { $_."Source Service" -match $Source -and $_."Destination Service" -match $Destination } | Format-Table -Wrap -AutoSize

}
