<# 
.NAME
    Veeam Backup for Microsoft Office 365 Health-Checker
.SYNOPSIS
    Script to do a quick check of a VBO setup 
.DESCRIPTION
    This script checks some VBO components and reports possible issues/misconfigurations
    & more - See Readme on github
.NOTES  
    File Name  : vbo-health-checker.ps1  
    Author     : Stephan Herzig, Veeam Software  (stephan.herzig@veeam.com)
    Requires   : PowerShell 
.VERSION
    1.6
#>
param(
    [Parameter(mandatory=$true)]
    [String] $Organization,
    [Parameter(Mandatory = $false)]
    [String] $Logfile = "C:\temp\vbo_healthcheck_$env:computername.log",
    [Switch] $Webcheck,
    [Switch] $Clean,
    [String] $Days,
    [Switch] $Count)
Clear-Host

# Set the variables
$orga = $exch = $exar = $od = $sites = $teams = $nok = 0
$vbo_version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo("C:\Program Files\Veeam\Backup365\Veeam.Archiver.Proxy.exe").FileVersion
if($Webcheck){
$WebReq                    = Invoke-WebRequest -Uri https://www.veeam.com/kb4106
$InnerText                 = $WebReq.AllElements | Where-Object {$_.tagName -eq "TD" -and $_.innerText -ne $null} | Select -ExpandProperty innerText
$vbo_latestversion         = $InnerText[14]
$vbo_latestdisplayversion  = $InnerText[16]
$vbo_latestversionkb       = $InnerText[18]
                   }
$vbo_org         = Get-VBOOrganization -Name $Organization
$vbo_bkpapp      = Get-VBOBackupApplication -Organization $vbo_org
$vbo_logpath     = "C:\ProgramData\Veeam\Backup365\Logs\" + $vbo_org
$vbo_license     = Get-VBOLicensedUser
$vbo_exp         = Get-VBOLicense
$vbo_proxy       = Get-VBOProxy
$vbo_repository  = Get-VBORepository
$vbo_repofree    = 0
$vbo_enc         = Get-VBOEncryptionKey
$special_date    = (Get-Date).tostring("yyyy_MM")
$year            = (Get-Date).tostring("yyyy")
$today           = Get-Date
$month           = [cultureinfo]::InvariantCulture.DateTimeFormat.GetAbbreviatedMonthName((Get-Date).Month) 
$evt_date        = (Get-Date).AddDays(-2)
$m365_throttling = Select-String -Path C:\ProgramData\Veeam\Backup365\Logs\Veeam.Archiver.Proxy_$special_date*.log -Pattern "throttled [^0]" | Select Line| Format-Table -AutoSize
$vbo_sync        = Select-String -Path C:\ProgramData\Veeam\Backup365\Logs\Veeam.Archiver.Proxy_$special_date*.log -Pattern "Sync time: (6\.(?!0[^\d]|00)\d{1,2}|(((4[1-9](?!\d)|[5-9][0-9])(?![\d])|\d*[1-9]\d{2,})(\.\d{1,2})?))" | Select Line| Format-Table -AutoSize
$reposcan        = Select-String -Path C:\ProgramData\Veeam\Backup365\Logs\Veeam.Archiver.Shell_*$special_date*.log -CaseSensitive -Pattern '(Editing repository:)|(New configuration saved:)|(Repository:)|(Path:)|(Retention \()' | Select Line| Format-Table -AutoSize
$mem_events      = 0
$vbo_restore     = Get-VBORestoreSession | Where-Object {($_.StartTime.Hour -lt 7 -or $_.StartTime.Hour -ge 17)}
$vbo_disabledjob = Get-VBOJob -Organization $vbo_org | Where-Object -Property IsEnabled -NE True
if (!$logfile) {
$logfile         = "C:\Users\stephan.herzig\Documents\Script\vbo\vbo_healthcheck_$env:computername.log"
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
Write-Host "**************************************************v1.6*" -ForegroundColor Cyan

# Get Backup Job Configuration
Write-Host "Health Backup Jobs" -ForegroundColor Cyan
$jobs = (Get-VBOJob -Organization $vbo_org| Select-Object $_.Name)
Write-Host "Number of Backup Jobs        " -NoNewline
Write-Host $jobs.Count -ForegroundColor Green
Write-Host ""
ForEach ($j in $jobs) {
  $job_items = (Get-VBOJob -Name $j.Name)
  Write-Host "Job Name                     " -NoNewline
  Write-Host $j.Name -ForegroundColor Cyan
  Write-Host "Last Backup Status           " -NoNewline 
  Write-Host $job_items.LastStatus -ForegroundColor Green
  Write-Host "Last Run                     " -NoNewline 
  Write-Host $job_items.LastRun

# Bottleneck from Job log - v6 and later
  if ($vbo_version -gt 10) {
  Write-Host "Bottleneck                   " -NoNewline 
  $job_name = $j.Name
  $FullFileName = Get-ChildItem -Path $vbo_logpath\$job_name -Filter *.log | Where-Object {!$_.PSIsContainer} | Sort-Object {$_.LastWriteTime} -Descending | Select-Object -First 1
  ForEach ($File in $FullFileName)
        {
        $FilePath = $File.DirectoryName
        $FileName = $File.Name
        $bottleneck = Select-String -Path $FilePath"\"$FileName -Pattern "Bottleneck:" | Select Line 
        Write-Host $bottleneck.Line
        }
        # End bottleneck detection

#Onedrive Scan for virus messages - V6+ only

  If($job_items.SelectedItems.User.Count -ge 1 -And $job_items.SelectedItems.OneDrive -eq "True") {
  Write-Host "One Drive Job Scan           " -NoNewline
  $FullFileName = Get-ChildItem -Path $vbo_logpath\$job_name -Filter *.log | Where-Object {!$_.PSIsContainer} | Sort-Object {$_.LastWriteTime} -Descending | Select-Object -First 1
  ForEach ($File in $FullFileName)
        {
        $FilePath = $File.DirectoryName
        $FileName = $File.Name
        $avmsg    = Select-String -Path $FilePath"\"$FileName -Pattern "virus reported" | Select Line 
        Write-Host $avmsg[1] -ForegroundColor Yellow
        }
  }
  }
  
  If($job_items.LastStatus -ne "Success") {$nok++}
  Write-Host " "
  sleep 3
    }

# Calculate the total objects (not used)
#$total_objects=$orga+$exch+$exar+$od+$sites+$teams

# Now some checks
Write-Host "*******************************************************" -ForegroundColor Cyan
Write-Host "*              VB365 Environment Check                *"
Write-Host "*******************************************************" -ForegroundColor Cyan
Write-Host "Backup Environment" -ForegroundColor Cyan
Write-Host "Installed version            " -NoNewline
Write-Host $vbo_version -ForegroundColor Green
WriteLog   "Installed Version" $vbo_version
Write-Host "Number of Backup Apps        " -NoNewline
Write-Host $vbo_bkpapp.Count -ForegroundColor Green
WriteLog   "Number of Backup Apps " $vbo_bkpapp.Count
If ($vbo_bkpapp.Count -ge 1) {Write-Host "More than 1 Backup Application configured. Please remove!" -ForegroundColor Yellow} 
Else {""}
Write-Host ""
if ($Webcheck -eq "Yes") {
Write-Host "Latest available version     " -NoNewline
Write-Host $vbo_latestdisplayversion -ForegroundColor Green
Write-Host "Please see this KB Article   " -NoNewline
Write-Host $vbo_latestversionkb -ForegroundColor Green
Write-Host ""            }
Write-Host "               Proxy Server Setup                      "
Write-Host "*******************************************************" -ForegroundColor Cyan
Write-Host "Number of Proxies            " -NoNewline
Write-Host $vbo_proxy.Count -ForegroundColor Green
WriteLog   "Number of Proxies" $vbo_proxy.Count
ForEach ($proxy in $vbo_proxy) {
Write-Host "Proxy Name                   " -NoNewline
Write-Host $proxy.Hostname
$proxy_cpu = (Get-WmiObject -Class Win32_Processor -ComputerName $proxy.Hostname)
Write-Host "Number of CPUs               " -NoNewline
Write-Host $proxy_cpu.Count -ForegroundColor Green -NoNewline
If ($proxy_cpu.Count -lt 4) {"More CPUs may be needed"} 
Else {""}
$proxy_mem = (Get-WMIObject -class win32_ComputerSystem -ComputerName $proxy.Hostname | % {$_.TotalPhysicalMemory})
$proxy_memory = [math]::Round($proxy_mem/1024/1024/1024) 
Write-Host "Amount of RAM (GB)           " -NoNewline
Write-Host $proxy_memory -ForegroundColor Green -NoNewline
If ($proxy_memory -lt 16) {"    More RAM may be needed"} 
Else {""}
Write-Host "Number of configured threads " -NoNewline
Write-Host $proxy.ThreadsNumber -ForegroundColor Green -NoNewline
If ($proxy_memory -lt 16) {"    More RAM may be needed"} 
Else {""}
Write-Host
   }

# Number of Repositories - No more checks
Write-Host "                Repository Server Setup                "
Write-Host "*******************************************************" -ForegroundColor Cyan
Write-Host "Number of Repositories       " -NoNewline
Write-Host $vbo_repository.Count -ForegroundColor Green
WriteLog "Number of Repositories" $vbo_repository.Count
Write-Host
ForEach ($repo in $vbo_repository) {
If (!$repo.ObjectStorageRepository){
Write-Host "Local Repository Usage"
Write-Host "Repository Name:             " -NoNewline
Write-Host $repo.Name
WriteLog "Repository Name" $repo.name
$vbo_repofree = [math]::Round(($repo.FreeSpace*100/$repo.Capacity)) 
Write-Host "% Free Capacity:             " -NoNewline
Write-Host $vbo_repofree -ForegroundColor Green
WriteLog "% Free Capacity" $vbo_repofree
}
}
Write-Host

Write-Host "                   General Checks                      "
Write-Host "*******************************************************" -ForegroundColor Cyan

# Check logs if throttling during backup occured - All logs from current month get checked
Write-Host "Did any throttling during backup occur in" $month $year "?         " -NoNewline
If ($m365_throttling.Count -eq 0) {"No"}
$m365_throttling
WriteLog "Did any throttling occur during $month $year ?" $m365_throttling.Count
Write-Host

# Check logs if throttling during SP restore occured - All logs from current month get checked
if (Test-Path -Path C:\ProgramData\Veeam\Backup\SharePointExplorer\Logs\) {
$sp_restore_429  = Select-String -Path C:\ProgramData\Veeam\Backup\SharePointExplorer\Logs\Veeam.SharePoint.*_$special_date*.log -Pattern "429 TOO MANY REQUESTS" | Select Line| Format-Table -AutoSize
Write-Host "Any throttling during a SP restore Session in" $month $year "?     " -NoNewline
If ($sp_restore_429.Count -eq 0) {"No"}
$sp_restore_429
}
else {
    "Any throttling during a SP restore Session in $month $year ?     No"
}
$sp_restore_429
WriteLog "Did any throttling occur during $month $year ?" $sp_restore_429.Count
Write-Host

# Check logs if Sync Time larger 200 - All logs from current month get checked
Write-Host "Long sync times during" $month $year "?                            " -NoNewline
If ($vbo_sync.Count -eq 0) {"No"}
$vbo_sync
WriteLog "Long sync times during $month $year ?" $vbo_sync.Count
Write-Host

# Check Windows System Log - Looking for Memory Exhausted Event-Id 2004
ForEach ($server in $vbo_proxy) {
Write-Host "Any low memory conditions on" $server.Hostname "the last 48 h?           " -NoNewline
$mem_events = Get-WinEvent -ComputerName $server.Hostname -FilterHashtable @{ LogName='System'; StartTime=$evt_date; Id='2004' } -ErrorAction SilentlyContinue
If ($mem_events.Count -eq 0) 
{
Write-Host "No"
WriteLog "No low memory conditions on" $server.Hostname
}else{
Write-Host $mem_events.Count
WriteLog "Low memory conditions on"$server.Hostname $mem_events.Count
}
}
Write-Host

# Print if a backup job is not in "Success" state
Write-Host "Jobs not successfully run    " -NoNewline
Write-Host $nok -ForegroundColor Yellow
If ($jobs.Count -le 1 -and $orga -gt 1) {"                           Only one Backup Job configured"} 
Else {""}
WriteLog "Jobs not successfully run        " $jobs.Count

# Licensed user & expiration date
Write-Host "Licensed users               " -NoNewline
Write-Host $vbo_license.Count -ForegroundColor Green
Write-Host "License expiration           " -NoNewline
Write-Host $vbo_exp.SupportExpirationDate -ForegroundColor Green
WriteLog "License expiration" $vbo_exp.SupportExpirationDate
Write-Host

# Check if anybody changed the repo retention settings
Write-Host "Possible Repository retention setting changes in " $month $year "? " -NoNewline
If ($reposcan.Count -eq 0) {"No"}
$reposcan
WriteLog "Possible Repository retention change activities"
Write-Host

# Check if any disabled Backup Job is present
Write-Host "Is there a disabled backup job?                              " -NoNewline
If ($vbo_disabledjob.Count -eq 0) {"No"}
Else {
$vbo_disabledjob.Count 
WriteLog "Disabled backup jobs present" 
}
Write-Host ""
# Check for Restore Sessions outside of business hours (7 to 17)
Write-Host "Restore activites outside of business hours                  " -NoNewline
If ($vbo_restore.Count -eq 0) {"No"}
ForEach ($outside in $vbo_restore) {
Write-Host "Restore activity detected " -ForegroundColor Yellow
Write-Host ""
Write-Host "Start Time         " -NoNewline
$outside.StartTime
Write-Host "Restore Point      " -NoNewline
$outside.Name
Write-Host "Initiated by       " -NoNewline
$outside.InitiatedBy
Write-Host "Processed Object   " -NoNewline
$outside.ProcessedObjects
Write-Host ""

}
Write-Host ""
# Display age of encryption keys
Write-Host "Age of the configured encryption key(s)" -NoNewline
Write-Host
$keyReport = @()
foreach ($enckey in $vbo_enc)
{
   $passwordAge    = [DateTime]$enckey.LastModified
   $reportPassword = [PSCustomObject]@{
        Password = $enckey.Description
        AgeInDays = ($today - $passwordAge).Days
                                      }
   $keyReport += $reportPassword
}
$keyReport

# That's all folks
WriteLog "*** End VBO Health Check ***"

# Special Section
if($Count){
$usage = New-Object -TypeName System.Collections.Generic.List[PSCustomObject]
function validate {
    param (
          $variable
    )
    if ($variable) {
        return $variable.count
    }
    else {
        return 0
    }
}
foreach ($repo in $vbo_repository) {
        $users           = Get-VBOEntityData -Repository $repo -Type User
        $exc             = Get-VBOEntityData -Repository $repo -Type Mailbox
        $od              = Get-VBOEntityData -Repository $repo -Type OneDrive
        $groups          = Get-VBOEntityData -Repository $repo -Type Group
        $sites           = Get-VBOEntityData -Repository $repo -Type Site
        $teams           = Get-VBOEntityData -Repository $repo -Type Team
        $orgs            = Get-VBOEntityData -Repository $repo -Type Organization

$usage.Add([PSCustomObject]@{
           RepName       = $repo.Name;
           UserCount     = validate $users;
           MailboxCount  = validate $exc
           OneDriveCount = validate $od;
           GroupCount    = validate $groups;
           SiteCount     = validate $sites;
           TeamCount     = validate $teams;
           OrgCount      = validate $orgs
    })
}
$total           = [PSCustomObject]@{
          RepoCount      = $usage.count;
          UserCount      = ($usage | Measure-Object -Property UserCount -Sum).Sum;
          MailboxCount   = ($usage | Measure-Object -Property MailboxCount -Sum).Sum;
          OneDriveCount  = ($usage | Measure-Object -Property OneDriveCount -Sum).Sum;
          GroupCount     = ($usage | Measure-Object -Property GroupCount -Sum).Sum;
          SiteCount      = ($usage | Measure-Object -Property SiteCount -Sum).Sum;
          TeamCount      = ($usage | Measure-Object -Property TeamCount -Sum).Sum;
          OrgCount       = ($usage | Measure-Object -Property OrgCount -Sum).Sum
}
return $total
}
# Log Cleaner
if($Clean){
$culture         = [System.Globalization.CultureInfo]::InvariantCulture
$format          = 'dd/MM/yyyy HH:mm:ss'
Write-Host ""
Write-Host "                       Cleaner                         "
Write-Host "*******************************************************" -ForegroundColor Cyan
Write-Host "Cleaning up log file - Delete entries older than $Days days  "
(get-content $Logfile )| Where-Object {$_} |  Where-Object { ([datetime]::ParseExact(([string]$_).Substring(0,19), $format, $culture) -ge (Get-Date).AddDays(-$Days)) } | Set-Content $Logfile
}
