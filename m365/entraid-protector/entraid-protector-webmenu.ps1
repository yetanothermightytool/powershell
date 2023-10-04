<# 
.NAME
    Entra ID Protector - Webmenu
.DESCRIPTION
    This Powershell script provides a website over the specified port (default 8080) so that the functions of the entraid-protector.ps1 
    script can be executed. More details on the ReadMe page.
.NOTES  
    File Name  : entraid-protector-webmenu.ps1
    Author     : Stephan "Steve" Herzig, (stephan.herzig@veeam.com)
    Requires   : PowerShell 5.1+, Powershell Modules EntraExporter & Microsoft Graph (tested with version 2.5.0)
.VERSION
    1.2
#>
param (
    [int]$Port             = 8080,
    [int]$RefreshInterval  = 300,
    [String] $LogFilePath  = "C:\Temp\entra-id-protector-log.txt"
)
# Variables
$refreshInMs               = "{0}000" -f $RefreshInterval
$scriptPath                = "C:\Temp"
$exportRootFolder          = "C:\Temp"
$exportFolder              = "$exportRootFolder\entraid-export"
$exportFolders             = Get-ChildItem -Path $exportRootFolder -Directory -Recurse -Filter 'entraid-export-*'
$numberOfExportFolders     = $exportFolders.Count + 1
$auditExportFolder         = "$exportRootFolder\entraid-export\AuditLogs"
$lastExportDate            = (Get-Item $exportFolder).CreationTime.ToString("dd-MM-yyyy HH:mm:ss")
$lineBreaks                = '<br>' * 8
$host.ui.RawUI.WindowTitle = "Entra ID Protector Web Menu"

# General functions
function suspiciousEventCount {
    param (
        [string]$auditExportFolder,
        [string]$originCountry
    )
    # Just to see what get's checked - can be disabled
    Write-Host "Filtering anomalies for originCountry: $originCountry"

    if (-not (Test-Path -Path $auditExportFolder -PathType Container)) {
        Write-Host "Error: The specified folder '$auditExportFolder' does not exist."
        return 0
    }

    $jsonFiles = Get-ChildItem -Path $auditExportFolder -Filter 'SignInAuditLogs_*.json' -File
    $anomalies = @()

    foreach ($jsonFile in $jsonFiles) {
        try {
            $jsonContent = Get-Content -Path $jsonFile.FullName | ConvertFrom-Json

            # Check if the CountryOrRegion is not equal to originCountry
            if ($jsonContent.Location.CountryOrRegion -ne $originCountry) {
                $ExpectedCountry = $originCountry
                $CountryOrRegion = $jsonContent.Location.CountryOrRegion
                $CreatedDateTime = $jsonContent.CreatedDateTime
                $UserDisplayName = $jsonContent.UserDisplayName
                $UserPrincipalName = $jsonContent.UserPrincipalName

                for ($i = 0; $i -lt $CountryOrRegion.Count; $i++) {
                    # Check if the current CountryOrRegion is not equal to originCountry
                    if ($CountryOrRegion[$i] -ne $originCountry) {
                        $anomalies += [PSCustomObject]@{
                            "CountryOrRegion" = $CountryOrRegion[$i]
                            "ExpectedCountry" = $ExpectedCountry
                            "CreatedDateTime" = $CreatedDateTime[$i]
                            "UserDisplayName" = $UserDisplayName[$i]
                            "UserPrincipalName" = $UserPrincipalName
                        }
                    }
                }
            }
        } catch {
            Write-Host "Error processing file $($jsonFile.FullName): $_"
        }
    }

    return $anomalies.Count
}

function suspiciousDirectoryRoleActivityCount {
    param (
        [string]$auditExportFolder
    )

    if (-not (Test-Path -Path $auditExportFolder -PathType Container)) {
        Write-Host "Error: The specified folder '$auditExportFolder' does not exist."
        return
    }

    $jsonFiles            = Get-ChildItem -Path $auditExportFolder -Filter 'DirectoryAuditLogs*.json' -File
    $suspiciousDirectoryActivityCount = 0

    foreach ($jsonFile in $jsonFiles) {
        try {
            $jsonContent = Get-Content -Path $jsonFile.FullName -Raw | ConvertFrom-Json

            foreach ($entry in $jsonContent) {
                if ($entry.Result -eq "success" -and (
                        $entry.ActivityDisplayName -eq "Add member to role" -or
                        $entry.ActivityDisplayName -eq "Remove member from role" -or
                        $entry.ActivityDisplayName -eq "Add app role assignment grant to user"
                    )) {
                    $initiatedBy = $entry.InitiatedBy.User -match "UserPrincipalName:\s*(.+)"
                    if ($initiatedBy) {
                        $userPrincipalName = $matches[1].Trim()
                    } else {
                        $userPrincipalName = "N/A"
                    }

                    $targetResourceNames = @()
                    $targetResourceIds   = @()

                    $roleEntry = $entry.TargetResources | Where-Object { $_ -match "Type: Role" }
                    $userEntry = $entry.TargetResources | Where-Object { $_ -match "Type: User" }

                    if ($userEntry -match "UserPrincipalName:\s*(.+)") {
                        $upn = $matches[1].Trim()
                        $targetResourceNames += $upn
                    }

                    if ($roleEntry -match "Id:\s+([a-fA-F0-9-]+)") {
                        $id = $matches[1].Trim()
                        $targetResourceIds += $id
                    }

                    $suspiciousDirectoryActivityCount++
                }
            }
        } catch {
            Write-Host "Error processing file $($jsonFile.FullName): $_"
        }
    }

    $suspiciousDirectoryActivityCount
}

# Function for the different button actions
function Process-MenuChoice {
    param (
        [string]$choice,
        [string]$param1,
        [string]$param2,
        [string]$param3,
        [string]$param4,
        [string]$param5,
        [string]$param6,
        [string]$param7
        )
    switch ($choice) {
        # Display Users
        1 {
        $scriptPath = "$scriptPath\entraid-protector.ps1"
        if ($param1 -gt 0) {
            $arguments = "-Users -ExportNo", $param1
                } else {
            $arguments = "-Users"
            }
            Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $arguments" -Wait
          }
        # User Recycle Bin
        2 {
            $scriptPath = "$scriptPath\entraid-protector.ps1"
            $arguments  = "-GetRecycleBin"
            Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $arguments" -Wait
          }
        # Compare User Count
        3 {
            $scriptPath = "$scriptPath\entraid-protector.ps1"
            $arguments  = "-CompareUserCount"
            Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $arguments" -Wait
          }
        # Compare specific User
        4 {
            $scriptPath = "$scriptPath\entraid-protector.ps1"
            $arguments = "-CompareSpecificUser" , $param2 , "-ExportNo", $param3
            Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $arguments" -Wait
          }
        # Display Groups
        5 {
        $scriptPath = "$scriptPath\entraid-protector.ps1"
        if ($param4 -gt 0) {
            $arguments = "-Groups -ExportNo", $param4
                } else {
            $arguments = "-Groups"
            }
            Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $arguments" -Wait
          }
        # Display Security Groups
        6 {
        $scriptPath = "$scriptPath\entraid-protector.ps1"
        if ($param5 -gt 0) {
            $arguments = "-SecurityGroups -ExportNo", $param4
                } else {
            $arguments = "-SecurityGroups"
            }
            Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $arguments" -Wait
          }
        # Display Roles
        7 {
        $scriptPath = "$scriptPath\entraid-protector.ps1"
        if ($param6 -gt 0) {
            $arguments = "-Roles -ExportNo", $param6
                } else {
            $arguments = "-Roles"
            }
            Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $arguments" -Wait
          }
        # Display Applications
        8 {
        $scriptPath = "$scriptPath\entraid-protector.ps1"
        if ($param7 -gt 0) {
            $arguments = "-Applications -ExportNo", $param7
                } else {
            $arguments = "-Applications"
            }
            Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $arguments" -Wait
          }
        # Run Export
        9 {
        $scriptPath = "$scriptPath\entraid-protector.ps1"
        $arguments = "-Export -AuditExport"
            
            Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $arguments" -Wait
          }

           default { return "Invalid choice." }
          }
 }

# Start http listener
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Clear-Host
Write-Host "Starting Entra ID Protector Web Server..."
Write-Host "Web Server started. Listening for incoming requests on port $Port. Refresh interval $RefreshInterval"

# The HTML Website is defined down below
$menuHtml = @"
<!DOCTYPE html>
<html>
    <head>
        <title>Entra ID Protector</title>
        <style>
            body {
                font-family: Arial, Helvetica, sans-serif;
                background-color: #F1F1F1;
                margin: 0;
                padding: 0;
            }
            .header {
                background-color: #65AF45;
                color: white;
                text-align: center;
                padding: 20px;
                margin: 0;
                width: 100%; 
                position: relative;
                display: flex;
                align-items: center;
            }
            .header h1 {
               color: white;
               text-align: left; 
            }
            .suspicious-login-container {
               position: absolute;
               width: 220px; 
               height: 75px;
               bottom: 50px;
               left: 20px;
               background-color: #E1E1E3;
               color: #5132EE;
               padding: 8px 16px;
               border-radius: 15px;
               font-size: 16px;
               font-weight: bold;
               display: flex;
               flex-direction: column;
               align-items: center; 
               justify-content: space-between;
            }
            .suspicious-event-count {
                font-size: 24px;
                font-weight: bold;
                color: #5132EE;
            }
            .suspicious-directory-container {
               position: absolute;
               width: 220px; 
               height: 75px;
               bottom: 50px;
               left: 280px;
               background-color: #E1E1E3;
               color: #5132EE;
               padding: 8px 16px;
               border-radius: 15px;
               font-size: 16px;
               font-weight: bold;
               display: flex;
               flex-direction: column;
               align-items: center; 
               justify-content: space-between;
            }
            .suspicous-directory-count {
                font-size: 24px;
                font-weight: bold;
                color: #5132EE;
            }
            .help-button {
                width: 36px;
                height: 36px;
                background-color: #fff;
                color: #4CAF50;
                border-radius: 50%;
                font-size: 28px;
                text-align: center;
                z-index: 1;
                cursor: pointer;
                margin-left: auto; 
                margin-right: 75px; 
            }
            .help-tooltip {
                display: none;
                position: absolute;
                top: calc(100% + 5px);
                right: +80px;
                padding: 10px;
                background-color: rgba(0, 0, 0, 0.7);
                color: #fff;
                border-radius: 5px;
                font-size: 16px;
                z-index: 1;
                text-align: left;
            }
            .header:hover .help-tooltip {
                display: block; 
            }
            .button-container {
                display: flex;
                justify-content: flex-start;
                margin-top: 20px;
            }
            .button {
                background-color: #283A5F;
                color: white;
                padding: 14px 20px;
                margin: 10px;
                border: none;
                border-radius: 10px;
                cursor: pointer;
                font-size: 16px;
            }
            .button:hover {
                background-color: #1d689b;
            }
            .button:focus {
                outline: none;
            }
            .button:active {
                background-color: #3e8e41;
            }
            .execute-button {
                background-color: #800080;
                color: white;
                padding: 10px 20px;
                border-radius: 10px;
                cursor: pointer;
                font-size: 16px;
                margin-left: auto;
                max-width: 200px; 
                margin: 10px; 
                text-align: center;
            }
            .execute-button:hover {
                background-color: #4B0082;
            }
            .execute-button:focus {
                outline: none;
            }
            .execute-button:active {
                background-color: #1d689b;
            }
            .container {
                display: flex;
                flex-direction: column;
                align-items: flex-start;
                justify-content: flex-start; 
                height: 100vh;
            }
            .menu {
                display: flex;
                flex-wrap: wrap;
                justify-content: flex-start; 
                align-items: flex-start; 
                flex-direction: column; 
                margin-top: 20px;
            }
            .parameter-dialog {
                display: none;
                position: fixed;
                top: 0;
                left: 0;
                width: 100%;
                height: 100%;
                background-color: #00000080;
            }
            .parameter-dialog-content {
                background-color: #FFFFFF;
                width: 400px;
                margin: 50px auto;
                padding: 20px;
                border-radius: 10px;
            }
            .parameter-input {
                display: block;
                margin-bottom: 10px;
                border: 1px solid #ccc;
                border-radius: 5px;
                padding: 8px;
                width: 100%;
                box-sizing: border-box;
            }
            .parameter-submit {
                background-color: #283A5F;
                color: white;
                padding: 10px 20px;
                border: none;
                border-radius: 5px;
                cursor: pointer;
                font-size: 16px;
            }
            .parameter-submit:hover {
                background-color: #1d689b;
            }
            .parameter-submit:focus {
                outline: none;
            }
            .parameter-submit:active {
                background-color: #73A8D2;
            }
            .timestamp {
                position: fixed;
                bottom: 0;
                left: 0;
                margin: 5px;
                color: gray;
                font-size: 12px;
            }
        </style>
    </head>
    <body>
        <div class="header">
            <img src="http://localhost:$Port/protector.png" alt="Entra ID Protector" style="height: 80px; margin-right: 10px;">
            <h1>Entra ID Protector</h1>
        <div class="help-button">?</div>
        <div class="help-tooltip">
            <p>Doppelbock is a strong beer style with a typical alcohol content beyond 7% ABV. The style originated in the Bavarian capital city of Munich, Germany and was for a fairly long time synonymous with the Salvator beer brewed by Paulaner.</p>
            <p>In the late 19th-century breweries that had copied the name “Salvator” were forced by a lawsuit to introduce their own brands of doppelbock beers and today almost 200 breweries indicate the style by amending “-ator” to their beer’s name. Famous doppelbocks are “Animator”, “Celebrator”, “Maximator”, and “Triumphator”.</p>
            <p>And here you are: Entra ID ProtecTOR. (Just -TOR it's not a beer but many beers were consumed while everything was put together)</p>
            <p>Click on a button to perform an action.</p>
        </div>
        </div>
        </div>
        <div class="execute-button" id="executeButton">Run Export</div> 
        <h2>  User related actions</h2>
        <div class="button-container">
            <button class="button" onclick="showParameterDialog(1)">Display Users</button>
            <button class="button" onclick="showParameterDialog(2)">Recycle Bin</button>
            <button class="button" onclick="showParameterDialog(3)">Compare User Count</button>
            <button class="button" onclick="showParameterDialog(4)">Compare Specific User</button>
        </div>
        <h2>  Group & other actions</h2>
        <div class="button-container">
            <button class="button" onclick="showParameterDialog(5)">Display Groups</button>
            <button class="button" onclick="showParameterDialog(6)">Display Security Groups</button>
            <button class="button" onclick="showParameterDialog(7)">Display Roles</button>
            <button class="button" onclick="showParameterDialog(8)">Display Applications</button>
        </div>
        
        <h2>  Suspicious entries in Audit Logs - Last 24 h</h2>
        <div class="suspicious-login-container">
            <span>Login Activities</span>
            <span class="suspicious-event-count" id="suspiciousEventCount">Loading...</span>
        </div>
        <div class="suspicious-directory-container">
            <span>Role Activities</span>
            <span class="suspicous-directory-count" id="suspiciousDirectoryCount">Loading...</span>
        </div>
        <div class="timestamp">
            V1.1 - Last refresh: $((Get-Date).ToString("dd-MM-yyyy HH:mm:ss")) - Last Export date: $lastExportDate - Number of Exports: $numberOfExportFolders
        </div>
     
<!-- Dialog for displaying users in export (Hidden by default) -->
<div id="parameterDialog1" class="parameter-dialog">
    <div class="parameter-dialog-content">
        <p style="font-weight: bold;">Display Users</p>
        <p>Displays exported user data (such as UserPrincipalName, DisplayName) from the latest or selected export (Export ID)</p>
        <label for="param1-1">Export ID:</label>
        <input type="text" id="param1-1" class="parameter-input">
        <!-- Submit and cancel buttons -->
        <button class="parameter-submit" onclick="sendChoice(1)">Submit</button>
        <button class="parameter-submit" onclick="closeParameterDialog()">Cancel</button>
    </div>
</div>
<!-- Dialog for displaying the users in Recycle Bin) -->
<div id="parameterDialog2" class="parameter-dialog">
    <div class="parameter-dialog-content">
        <p style="font-weight: bold;">Display Users in Recycle Bin</p>
        <p>The deleted users in the Recycle Bin get displayed. The script asks if a specific user should be restored</p>
        <!-- Submit and cancel buttons -->
        <button class="parameter-submit" onclick="sendChoice(2)">Run</button>
        <button class="parameter-submit" onclick="closeParameterDialog()">Cancel</button>
    </div>
</div>
<!-- Dialog for comparing the user count) -->
<div id="parameterDialog3" class="parameter-dialog">
    <div class="parameter-dialog-content">
        <p style="font-weight: bold;">Compare the exported user count</p>
        <p>Compares user count between latest export and older export folders. Displays missing users in latest export related to the existing exports.</p>
        <!-- Submit and cancel buttons -->
        <button class="parameter-submit" onclick="sendChoice(3)">Run</button>
        <button class="parameter-submit" onclick="closeParameterDialog()">Cancel</button>
    </div>
</div>
<!-- Dialog for comparing a specific user -->
<div id="parameterDialog4" class="parameter-dialog">
    <div class="parameter-dialog-content">
        <p style="font-weight: bold;">Compare a specific user</p>
        <p>Searches for a user by User Principal Name, compares the data between the last and the specified export</p>
        <label for="param2-1">User Principal Name:</label>
        <input type="text" id="param2-1" class="parameter-input" placeholder="pesche.mueller@domain.tld">
        <label for="param2-1">Export ID:</label>
        <input type="text" id="param3-1" class="parameter-input">
        <!-- Submit and cancel buttons -->
        <button class="parameter-submit" onclick="sendChoice(4)">Submit</button>
        <button class="parameter-submit" onclick="closeParameterDialog()">Cancel</button>
    </div>
</div>
<!-- Dialog for displaying groups in export (Hidden by default) -->
<div id="parameterDialog5" class="parameter-dialog">
    <div class="parameter-dialog-content">
        <p style="font-weight: bold;">Display Groups</p>
        <p>Displays group data, and if a specific group is selected, it also displays its members.</p>
        <label for="param4-1">Export ID:</label>
        <input type="text" id="param4-1" class="parameter-input">
        <!-- Submit and cancel buttons -->
        <button class="parameter-submit" onclick="sendChoice(5)">Submit</button>
        <button class="parameter-submit" onclick="closeParameterDialog()">Cancel</button>
    </div>
</div>
<!-- Dialog for Display Security Groups) -->
<div id="parameterDialog6" class="parameter-dialog">
    <div class="parameter-dialog-content">
        <p style="font-weight: bold;">Display Security Groups</p>
        <p>Display the exported Security Groups and offers to restore the group back to the directory</p>
        <label for="param5-1">Export ID:</label>
        <input type="text" id="param5-1" class="parameter-input">
        <!-- Submit and cancel buttons -->
        <button class="parameter-submit" onclick="sendChoice(6)">Run</button>
        <button class="parameter-submit" onclick="closeParameterDialog()">Cancel</button>
    </div>
</div>
<!-- Parameter Dialog for displaying the roles (Hidden by default) -->
<div id="parameterDialog7" class="parameter-dialog">
    <div class="parameter-dialog-content">
        <p style="font-weight: bold;">Display Roles</p>
        <p>Displays role data from the latest or selected export (Export ID). The members of the roles can be displayed as well.</p>
        <label for="param6-1">Export ID:</label>
        <input type="text" id="param6-1" class="parameter-input">
        <!-- Submit and cancel buttons -->
        <button class="parameter-submit" onclick="sendChoice(7)">Submit</button>
        <button class="parameter-submit" onclick="closeParameterDialog()">Cancel</button>
    </div>
</div>
<!-- Dialog for displaying the applications (Hidden by default) -->
<div id="parameterDialog8" class="parameter-dialog">
    <div class="parameter-dialog-content">
        <p style="font-weight: bold;">Display Applications</p>
        <p>Displays exported application information from the latest or selected export (Export ID)</p>
        <label for="param7-1">Export ID:</label>
        <input type="text" id="param7-1" class="parameter-input">
        <!-- Submit and cancel buttons -->
        <button class="parameter-submit" onclick="sendChoice(8)">Submit</button>
        <button class="parameter-submit" onclick="closeParameterDialog()">Cancel</button>
    </div>
</div>
<script>
        const executeButton = document.getElementById('executeButton');
        executeButton.addEventListener('click', function() {
        sendChoice(9); 
        });

        function updateTextColor(element) {
                    if (parseInt(element.innerText) > 0) {
                        element.style.color = 'orange';
                    } else {
                        element.style.color = 'darkblue';
                    }
       }

        // Hovering fetch
        const container = document.querySelector(".suspicious-login-container");
   
        
        function fetchSuspiciousEventCount() {
            fetch("http://localhost:8080/suspiciousEventCount")
                .then(response => response.text())
                .then(suspiciousEventCount => {
                    console.log("Fetched data:", suspiciousEventCount);
                    var suspiciousEventCountElement = document.getElementById("suspiciousEventCount");
                    suspiciousEventCountElement.textContent = suspiciousEventCount;
                    updateTextColor(suspiciousEventCountElement);
                })
                .catch(error => {
                    alert("Failed to fetch data. Please try again later.");
                    console.error(error);
                });
        }

        // Fetch the suspicious event count when the page is loaded
        window.addEventListener("load", function () {
            fetchSuspiciousEventCount();
        });

        function fetchSuspiciousDirectoryCount() {
            fetch("http://localhost:8080/suspiciousDirectoryCount")
                .then(response => response.text())
                .then(suspiciousDirectoryCount => {
                    console.log("Fetched data:", suspiciousDirectoryCount);
                    var suspiciousDirectoryCountElement = document.getElementById("suspiciousDirectoryCount");
                    suspiciousDirectoryCountElement.textContent = suspiciousDirectoryCount;
                    updateTextColor(suspiciousDirectoryCountElement);
                })
                .catch(error => {
                    alert("Failed to fetch data. Please try again later.");
                    console.error(error);
                });
        }

        // Fetch the suspicious directory event count when the page is loaded
        window.addEventListener("load", function () {
            fetchSuspiciousDirectoryCount();
        });


        

        function showParameterDialog(choice) {
            var dialog1 = document.getElementById('parameterDialog1');
            var dialog2 = document.getElementById('parameterDialog2');
            var dialog3 = document.getElementById('parameterDialog3');
            var dialog4 = document.getElementById('parameterDialog4');
            var dialog5 = document.getElementById('parameterDialog5');
            var dialog6 = document.getElementById('parameterDialog6');
            var dialog7 = document.getElementById('parameterDialog7');
            var dialog8 = document.getElementById('parameterDialog8');
        if (choice === 1) {
            dialog1.style.display = 'block';
            dialog2.style.display = 'none';
            dialog3.style.display = 'none';
            dialog4.style.display = 'none';
            dialog5.style.display = 'none';
            dialog6.style.display = 'none';
            dialog7.style.display = 'none';
            dialog8.style.display = 'none';
        // Reset the input fields 
            document.getElementById('param1-1').value = '';
        } else if (choice === 2) {
            dialog1.style.display = 'none';
            dialog2.style.display = 'block';
            dialog3.style.display = 'none';
            dialog4.style.display = 'none';
            dialog5.style.display = 'none';
            dialog6.style.display = 'none';
            dialog7.style.display = 'none';
            dialog8.style.display = 'none';
        } else if (choice === 3) {
            dialog1.style.display = 'none';
            dialog2.style.display = 'none';
            dialog3.style.display = 'block';
            dialog4.style.display = 'none';
            dialog5.style.display = 'none';
            dialog6.style.display = 'none';
            dialog7.style.display = 'none';
            dialog8.style.display = 'none';
        } else if (choice === 4) {
            dialog1.style.display = 'none';
            dialog2.style.display = 'none';
            dialog3.style.display = 'none';
            dialog4.style.display = 'block';
            dialog5.style.display = 'none';
            dialog6.style.display = 'none';
            dialog7.style.display = 'none';
            dialog8.style.display = 'none';
        // Reset the input fields 
            document.getElementById('param2-1').value = '';
            document.getElementById('param3-1').value = '';
        }  else if (choice === 5) {
            dialog1.style.display = 'none';
            dialog2.style.display = 'none';
            dialog3.style.display = 'none';
            dialog4.style.display = 'none';
            dialog5.style.display = 'block';
            dialog6.style.display = 'none';
            dialog7.style.display = 'none';
            dialog8.style.display = 'none';
        // Reset the input field
            document.getElementById('param4-1').value = '';
        }  else if (choice === 6) {
            dialog1.style.display = 'none';
            dialog2.style.display = 'none';
            dialog3.style.display = 'none';
            dialog4.style.display = 'none';
            dialog5.style.display = 'none';
            dialog6.style.display = 'block';
            dialog7.style.display = 'none';
            dialog8.style.display = 'none';
        // Reset the input field
            document.getElementById('param5-1').value = '';
        }  else if (choice === 7) {
            dialog1.style.display = 'none';
            dialog2.style.display = 'none';
            dialog3.style.display = 'none';
            dialog4.style.display = 'none';
            dialog5.style.display = 'none';
            dialog6.style.display = 'none';
            dialog7.style.display = 'block';
            dialog8.style.display = 'none';
        }  else if (choice === 8) {
            dialog1.style.display = 'none';
            dialog2.style.display = 'none';
            dialog3.style.display = 'none';
            dialog4.style.display = 'none';
            dialog5.style.display = 'none';
            dialog6.style.display = 'none';
            dialog7.style.display = 'none';
            dialog8.style.display = 'block';
        }

}
        function closeParameterDialog() {
            var dialog1 = document.getElementById('parameterDialog1');
            var dialog2 = document.getElementById('parameterDialog2');
            var dialog3 = document.getElementById('parameterDialog3');
            var dialog4 = document.getElementById('parameterDialog4');
            var dialog5 = document.getElementById('parameterDialog5');
            var dialog6 = document.getElementById('parameterDialog6');
            var dialog7 = document.getElementById('parameterDialog7');
            var dialog8 = document.getElementById('parameterDialog8');
    
            dialog1.style.display = 'none';
            dialog2.style.display = 'none';
            dialog3.style.display = 'none';
            dialog4.style.display = 'none';
            dialog5.style.display = 'none';
            dialog6.style.display = 'none';
            dialog7.style.display = 'none';
            dialog8.style.display = 'none';
        }

    function sendChoice(choice) {
        var param1, param2, param3, param4, param5, param6, param7;
        var xhr = new XMLHttpRequest();

        if (choice === 1) {
            param1 = document.getElementById('param1-1').value;
 
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        console.log(xhr.responseText); 
                        closeParameterDialog();
                    } else {
                        alert("Failed to execute the script. Please try again later.");
                        console.error(xhr.responseText); 
                    }
                }
            };
        } else if (choice === 2) {

            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        console.log(xhr.responseText);
                        closeParameterDialog();
                    } else {
                        alert("Failed to execute the script. Please try again later.");
                        console.error(xhr.responseText);
                    }
                }
            };
        } else if (choice === 3) {

            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        console.log(xhr.responseText);
                        closeParameterDialog();
                    } else {
                        alert("Failed to execute the script. Please try again later.");
                        console.error(xhr.responseText);
                    }
                }
            };
        
        }  else if (choice === 4) {
            param2 = document.getElementById('param2-1').value;
            param3 = document.getElementById('param3-1').value;

            if (!param2 || !param3) {
                alert("Please fill in all parameters.");
                return;
            }

            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        console.log(xhr.responseText); // Log the response from the server - just for truuubleshuuting
                        closeParameterDialog();
                    } else {
                        alert("Failed to execute the script. Please try again later.");
                        console.error(xhr.responseText); // Log any error response from the server - just for truuubleshuuting
                    }
                }
            };
        } else if (choice === 5) {
            param4 = document.getElementById('param4-1').value;

            
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        console.log(xhr.responseText);
                        closeParameterDialog();
                    } else {
                        alert("Failed to execute the script. Please try again later.");
                        console.error(xhr.responseText);
                    }
                }
            };
         } else if (choice === 6) {
            param5 = document.getElementById('param5-1').value;
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        console.log(xhr.responseText);
                        closeParameterDialog();
                    } else {
                        alert("Failed to execute the script. Please try again later.");
                        console.error(xhr.responseText);
                    }
                }
            };
         } else if (choice === 7) {
            param6 = document.getElementById('param6-1').value;
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        console.log(xhr.responseText);
                        closeParameterDialog();
                    } else {
                        alert("Failed to execute the script. Please try again later.");
                        console.error(xhr.responseText);
                    }
                }
            };
        } else if (choice === 8) {
            param4 = document.getElementById('param7-1').value;

            
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        console.log(xhr.responseText);
                        closeParameterDialog();
                    } else {
                        alert("Failed to execute the script. Please try again later.");
                        console.error(xhr.responseText);
                    }
                }
            };
        } else if (choice === 9) {
            console.log("Sending run export to the server server")
    
            xhr.onreadystatechange = function () {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        console.log("Server response:", xhr.responseText)
                        closeParameterDialog();
                    } else {
                        alert("Failed to execute the script. Please try again later.");
                        console.error("Server error:", xhr.responseText);
                    }
                }
            };
            
        }   xhr.open("POST", "http://localhost:8080/processChoice", true);
            xhr.setRequestHeader("Content-Type", "application/json");
        var data = {
            choice: choice,
            param1: param1,
            param2: param2,
            param3: param3,
            param4: param4,
            param5: param5,
            param6: param6,
            param7: param7
        };
        xhr.send(JSON.stringify(data));
    }
    </script>
  </body>
</html>
"@

# Respond to requests
while ($true) {
    $context  = $listener.GetContext()
    $request  = $context.Request
    $response = $context.Response

    if ($request.HttpMethod -eq "GET") {
        $url = $request.Url.LocalPath
        $query = $request.Url.Query

        if ($url -eq "/") {
            # Serving the menu page
            $response.Headers.Add("Content-Type", "text/html; charset=utf-8")
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($menuHtml)
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.Close()
         } elseif ($request.Url.LocalPath -eq '/protector.png') {
            $imagePath = "$scriptPath\protector.png"
            $imageBuffer = [System.IO.File]::ReadAllBytes($imagePath)
            $response.ContentType = "image/png"
            $response.ContentLength64 = $imageBuffer.Length
            $response.OutputStream.Write($imageBuffer, 0, $imageBuffer.Length)
        } elseif ($url -eq "/suspiciousEventCount") {
            $response.Headers.Add("Content-Type", "text/plain; charset=utf-8")
            $eventCount = suspiciousEventCount -auditExportFolder $auditExportFolder -originCountry CZ
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($eventCount.ToString())
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.Close()
        } elseif ($url -eq "/suspiciousDirectoryCount") {
            $response.Headers.Add("Content-Type", "text/plain; charset=utf-8")
            $eventCount = suspiciousDirectoryRoleActivityCount -auditExportFolder $auditExportFolder
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($eventCount.ToString())
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.Close()
        }
        else {
            # Invalid URL
            $response.StatusCode = 404
            $response.Close()
        }
    }
    elseif ($request.HttpMethod -eq "POST" -and $request.Url.LocalPath -eq "/processChoice") {
        # Handling menu choice
        $formData = $request.InputStream
        $reader = New-Object System.IO.StreamReader $formData
        $formDataStr = $reader.ReadToEnd()
        $reader.Close()
        $formDataObj = ConvertFrom-Json $formDataStr
        $choice  = $formDataObj.choice
        $param1  = $formDataObj.param1
        $param2  = $formDataObj.param2
        $param3  = $formDataObj.param3
        $param4  = $formDataObj.param4
        $param5  = $formDataObj.param5
        $param6  = $formDataObj.param6
        $param7  = $formDataObj.param7
        $menuResult = Process-MenuChoice -choice $choice -param1 $param1 -param2 $param2 -param3 $param3 -param4 $param4 -param5 $param5 -param6 $param6 -param7 $param7 
        if ([string]::IsNullOrEmpty($menuResult)) {
        $menuResult = "No data available."
        }
        $response.Headers.Add("Content-Type", "text/plain; charset=utf-8")
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($menuResult) 
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.Close()
    }
    else {
        # Invalid HTTP method or URL
        $response.StatusCode = 405
        $response.Close()
    }
}
