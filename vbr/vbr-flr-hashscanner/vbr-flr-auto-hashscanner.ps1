param(
    [Parameter(Mandatory = $true)]
    [String] $JobName,
    [Parameter(Mandatory = $true)]
    [String] $FilterDaysBack,
    [Parameter(Mandatory = $true)]
    [String] $MaxBackupScans,
    [Parameter(Mandatory = $false)]
    [String] $LogFilePath = "C:\Temp\log.txt"
      )

# Variables
$Date                           = (Get-Date).AddDays(-$FilterDaysBack)
$VeeamBackupCounterFile         = "D:\Scripts\Filehashscanner\VMtable.xml"

# Connect to the VBR server
Connect-VBRServer -Server localhost

# Function to get the Untested VMs
Function selectUntestedVMs {
    param([string]$fVeeamBackupCounterFile, [int]$fNumberofVMs, $fVbrObjs)

    $fVMTable = @()
    $fTestVMs = [System.Collections.ArrayList]@()
    $fDeletedVMs = [System.Collections.ArrayList]@()

    # Import VMtable if exists from a previous iteration
    if (Test-Path $fVeeamBackupCounterFile) {
        $fVMTable = import-clixml $fVeeamBackupCounterFile
    }

    # Initialize Checked property for all VMs in VMTable
    $fVMTable | ForEach-Object {
        if (-not $_.PSObject.Properties.Match('Checked')) {
            Write-Host "Adding Checked property to VM: $($_.VMname)"
            $_ | Add-Member -MemberType NoteProperty -Name 'Checked' -Value 0
        }
    }

    # Check if all VM's were tested / if so the VMTable is cleared
    if (!($fVMTable.Checked -contains 0)) { $fVMTable = @() }

    # Add newly created VM's from backup
    Foreach ($fVbrObj in $fVbrObjs) {
        if (!(($fVMTable.VMname) -Contains ($fVbrObj.name))) {
            $fVMTable += [PSCustomObject] @{
                VMname = $fVbrObj.Name;
                JobName = $fVbrObj.JobName;
                Checked = 0;
                Deleted = 0
            }
        }
    }

    # Remove old VM's from VMTable
    $fVMTable | ForEach-Object { if ($fVbrObjs.Name -notcontains $_.VMname) { $_.Deleted = 1 } }

    # Sort VMTable by Checked and VMname
    $fVMTable = $fVMTable | Where-Object { $_.Deleted -eq 0 } | Sort-Object Checked, VMname

    # Limit the number of VMs to be tested based on the number of entries in the VMTable
    $fNumberofVMs = [Math]::Min($fNumberofVMs, $fVMTable.Count)

    # Select least tested VMs and set as Checked
    $fTestVMs = @()
    for ($i = 0; $i -lt $fNumberofVMs; $i++) {
        # Check if backup job is currently running. If so, skip VM for a later run
        if ((Get-VBRBackupSession -Name ($fVMTable[$i].JobName + "*") | Where-Object { $_.state -ne "Stopped" -and $_.EndTime.Year -eq 1900 }) -eq $null) {
            $fTestVMs += [PSCustomObject] @{
                VMName = $fVMTable[$i].VMname;
                JobName = $fVMTable[$i].JobName
            }
            $fVMTable[$i].Checked = 1
        }
    }

    # Save VMTable to file for the next iteration
    $fVMTable | Export-Clixml $fVeeamBackupCounterFile

    Return $fTestVMs
}

# Find all VM objest successfully backed sind $Date
$scanObjects  = (Get-VBRBackupSession | Where-Object  {$_.JobType -eq "Backup" -and $_.JobName -eq $JobName -and $_.EndTime -ge $Date}).GetTaskSessions() | Where-Object {$_.Status -eq "Success" -or $_.Status -eq "Warning" }
# Call function selectUntestedVMs
$testVMs      = selectUntestedVMs -fVeeamBackupCounterFile $VeeamBackupCounterFile -fNumberofVMs $MaxBackupScans -fVbrObjs $scanObjects

foreach ($testVM in $testVMs){

            $scanVMObject    =  $testVM.VMname
            $scanVMJob       =  $testVMs.Jobname
            $scriptPath      =  "vbr-flr-filehashscanner.ps1"
            $arguments       =  "-VM $scanVMObject -JobName $scanVMJob"
            Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $arguments" 
            sleep 30
}

Disconnect-VBRServer
