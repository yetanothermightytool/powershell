<# 
.NAME
    Veeam Backup for Microsoft Office 365 Health-Checker
.SYNOPSIS
    Script to do a quick check of a VBO setup 
.DESCRIPTION
    This script checks some VBO components and reports possible issues/misconfigurations
    - Backup Job Status per Job 
	- Print license expiration date
	- Check logs if throtthling 
    - Check logs for sync time entries > 200 - Possible slow backup due to slow backup repo
    - Proxy stuff (min. recommended CPU and Memory)
	Created for Veeam Backup for Microsoft Office 365 v5


.NOTES  
    File Name  : vbo-health-checker.ps1  
    Author     : Stephan Herzig, Veeam Software  (stephan.herzig@veeam.com)
    Requires   : PowerShell 

.Version history
    1.1 - Bugfixes (see details on github)
        - % Free Capacity of each local VBO repository
    1.0 - Initial version
#>
param(
    [Parameter(Mandatory = $false)]
    [String] $Logfile = "C:\Scripts\Veeam\vbo\vbo_healthcheck_$env:computername.log"
    )
clear
# Import the Veeam Backup for Microsoft Office 365 Module
Import-Module "C:\Program Files\Veeam\Backup365\Veeam.Archiver.PowerShell\Veeam.Archiver.PowerShell.psd1"

# Set the variables
$orga =$exch = $exar = $od = $sites =$teams =$nok = 0
$vbo_org         = Get-VBOOrganization #-Name $organizationname
$vbo_license     = Get-VBOLicensedUser
$vbo_exp         = Get-VBOLicense
$vbo_proxy       = Get-VBOProxy
$vbo_repository  = Get-VBORepository
$vbo_repofree    = 0
$special_date    = (Get-Date).tostring("yyyy_MM")
$year            = (Get-Date).tostring("yyyy")
$month           = [cultureinfo]::InvariantCulture.DateTimeFormat.GetAbbreviatedMonthName((Get-Date).Month) 
$evt_date        = (Get-Date).AddDays(-2)
$m365_throttling = Select-String -Path C:\ProgramData\Veeam\Backup365\Logs\Veeam.Archiver.Proxy_$special_date*.log -Pattern "throttled [^0]" | Select Line| Format-Table -AutoSize
$vbo_sync        = Select-String -Path C:\ProgramData\Veeam\Backup365\Logs\Veeam.Archiver.Proxy_$special_date*.log -Pattern "Sync time: (6\.(?!0[^\d]|00)\d{1,2}|(((4[1-9](?!\d)|[5-9][0-9])(?![\d])|\d*[1-9]\d{2,})(\.\d{1,2})?))" | Select Line| Format-Table -AutoSize
$mem_events      = 0
#$logfile=$args[0]
if (!$logfile) {
$logfile = "C:\Scripts\Veeam\vbo\vbo_healthcheck_$env:computername.log"
}
#WriteLog Function
function WriteLog
{
Param ([string]$entry1,$entry2)
$timestamp = (Get-Date).toString("dd/MM/yyyy HH:mm:ss")
$logmessage = "$timestamp $entry1 $entry2"
Add-content $logfile -value $logmessage
}

WriteLog "*** Start VBO Health Check ***"
# Start the script
Write-Host "*******************************************************" -ForegroundColor Cyan
Write-Host "*                 VBO HEALTH-CHECKER                  *"
Write-Host "**************************************************v1.0*" -ForegroundColor Cyan

# Get Backup Job Configuration
Write-Host "Backup Jobs" -ForegroundColor Cyan
$jobs = (Get-VBOJob | Select-Object $_.Name)
Write-Host "Number of Backup Jobs      " -NoNewline
Write-Host $jobs.Count -ForegroundColor Green
Write-Host ""
ForEach ($j in $jobs) {
  $job_items = (Get-VBOJob -Name $j.Name)
  Write-Host "Job Name                   " -NoNewline
  Write-Host $j -ForegroundColor Cyan

# Get what got selected within the backup jobs
  If ($job_items.SelectedItems.Organization.Count -ge 1) {
  "Number of Organizations    "+$job_items.SelectedItems.Organization.Count
  $orga=$orga+$vbo_license.Count}
  If($job_items.SelectedItems.User.Count -ge 1 -And $job_items.SelectedItems.Mailbox -eq "True") {
  "Number of Exchange Users   "+$job_items.SelectedItems.User.Count
  $exch=$exch+$job_items.SelectedItems.User.Count}
  ElseIf($job_items.SelectedItems.User.Count -ge 1 -And $job_items.SelectedItems.ArchiveMailbox -eq "True") {
  "Number of Exchange Archive "+$job_items.SelectedItems.Mailbox.Count
  $exar+=$job_items.SelectedItems.Mailbox.Count}        
  ElseIf($job_items.SelectedItems.User.Count -ge 1 -And $job_items.SelectedItems.OneDrive -eq "True") {
  "Number of OneDrive         "+$job_items.SelectedItems.User.Count
  $od=$od+$job_items.SelectedItems.User.Count}
  ElseIf($job_items.SelectedItems.Site.Count -ge 1) {
  "Number of Sharepoint Sites "+$job_items.SelectedItems.Site.Count
  $sites=$sites+$job_items.SelectedItems.Site.Count}
  ElseIf($job_items.SelectedItems.Team.Count -ge 1) {
  "Number of MS Teams Sites   "+$job_items.SelectedItems.Team.Count
  $teams=$teams+$job_items.SelectedItems.Team.Count}
  Write-Host "Last Backup Status         " -NoNewline 
  Write-Host $job_items.LastStatus -ForegroundColor Green
  If($job_items.LastStatus -ne "Success") {$nok++}
  Write-Host " "
  sleep 3
    }

# Calculate the total objects (not used)
$total_objects=$orga+$exch+$exar+$od+$sites+$teams

# Now some checking
Write-Host "*******************************************************" -ForegroundColor Cyan
Write-Host "*              VBO Environment Check                  *"
Write-Host "*******************************************************" -ForegroundColor Cyan
Write-Host "Number of Proxies          " -NoNewline
Write-Host $vbo_proxy.Count -ForegroundColor Green
WriteLog   "Number of Proxies" $vbo_proxy.Count

ForEach ($proxy in $vbo_proxy) {
Write-Host "Proxy Name                 " -NoNewline
Write-Host $proxy.Hostname
$proxy_cpu = (Get-WmiObject -Class Win32_Processor -ComputerName $proxy.Hostname)
Write-Host "Number of CPUs             " -NoNewline
Write-Host $proxy_cpu.Count -ForegroundColor Green -NoNewline
If ($proxy_cpu.Count -lt 4) {"     More CPUs might be added"} 
Else {""}
$proxy_mem = (Get-WMIObject -class win32_ComputerSystem -ComputerName $proxy.Hostname | % {$_.TotalPhysicalMemory})
$proxy_memory = [math]::Round($proxy_mem/1024/1024/1024) 
Write-Host "Amount of RAM (GB)         " -NoNewline
Write-Host $proxy_memory -ForegroundColor Green -NoNewline
If ($proxy_memory -lt 16) {"    More RAM might be added"} 
Else {""}
Write-Host
   }
# Check logs if throttling occured - All logs from current month get checked
Write-Host "Did any throtthling occur during" $month $year "?                  " -NoNewline
If ($m365_throttling.Count -eq 0) {"No"}
$m365_throttling
WriteLog "Did any throttling occur during $month $year ?" $m365_throttling.Count
Write-Host

# Check logs if Sync Time larger 200 - All logs from current month get checked
Write-Host "Long sync times during" $month $year "?                            " -NoNewline
If ($vbo_sync.Count -eq 0) {"No"}
$vbo_sync
WriteLog "Long sync times during $month $year ?" $vbo_sync.Count
Write-Host

# Check Windows System Log - Looking for Memory Exhausted Event-Id 2004
ForEach ($server in $vbo_proxy) {
Write-Host "Any low memory conditions on" $server.Hostname "the last 48 h?  " -NoNewline
$mem_events = Get-WinEvent -ComputerName $server.Hostname -FilterHashtable @{ LogName='System'; StartTime=$evt_date; Id='2004' } -ErrorAction SilentlyContinue
If ($mem_events.Count -eq 0) {"No"}
else{$mem_events.Count}
WriteLog "Low memory conditions on"$server.Hostname $mem_events.Count
Write-Host
}

# Number of Repositories - No more checks
Write-Host "Number of Repositories     " -NoNewline
Write-Host $vbo_repository.Count -ForegroundColor Green
WriteLog "Number of Repositories" $vbo_repository.Count
Write-Host
ForEach ($repo in $vbo_repository) {
If (!$repo.ObjectStorageRepository){
Write-Host "Repository Name:           " -NoNewline
Write-Host $repo.Name
WriteLog "Repository Name" $repo.name
$vbo_repofree = [math]::Round(($repo.FreeSpace*100/$repo.Capacity)) 
Write-Host "% Free Capacity:           " -NoNewline
Write-Host $vbo_repofree -ForegroundColor Green
WriteLog "% Free Capacity" $vbo_repofree
}
}
Write-Host

# Licensed user & expiration date
Write-Host "Licensed user              " -NoNewline
Write-Host $vbo_license.Count -ForegroundColor Green
Write-Host "License expiration         " -NoNewline
Write-Host $vbo_exp.SupportExpirationDate -ForegroundColor Green
WriteLog "License expiration" $vbo_exp.SupportExpirationDate
Write-Host

# Print if any job is not in "Success" state
Write-Host "Jobs not successfully run  " -NoNewline
Write-Host $nok -ForegroundColor Yellow
If ($jobs.Count -le 1 -and $orga -gt 1) {"                           Only one Backup Job configured"} 
Else {""}
WriteLog "Jobs not successfully run" $jobs.Count
Write-Host ""
WriteLog "*** End VBO Health Check ***"
