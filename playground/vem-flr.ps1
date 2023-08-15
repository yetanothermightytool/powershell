Clear-Host

# Variables
$host.ui.RawUI.WindowTitle = "Single File Restore"
$server                    = "https://localhost:9398/api/"
$username                  = "Administrator"

# Trust all certificates
Add-Type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

# Getting the API
$r_api              = Invoke-WebRequest -Method Get -Uri $server -UseBasicParsing
$r_api_xml          = [xml]$r_api.Content
$r_api_links        = @($r_api_xml.EnterpriseManager.SupportedVersions.SupportedVersion | Where-Object { $_.Name -eq "v1_7" })[0].Links

# Start login
$r_login            = Invoke-WebRequest -method Post -Uri $r_api_links.Link.Href -UseBasicParsing -Credential (Get-Credential -Message "Basic Auth" -UserName "$username")
$sessionheadername  = "X-RestSvcSessionId"
$sessionid          = $r_login.Headers[$sessionheadername]
$r_login_xml        = [xml]$r_login.Content
$r_login_links      = $r_login_xml.LogonSession.Links.Link
$r_login_links_base = $r_login_links | Where-Object {$_.Type -eq 'EnterpriseManager'}

# Get the restore points
$r_jobs_query       = $r_login_links_base.Href + 'vmRestorePoints'
$r_jobs             = Invoke-WebRequest -Method Get -Headers @{$sessionheadername = $sessionid} -Uri $r_jobs_query -UseBasicParsing
$r_jobs_xml         = [xml]$r_jobs.Content
$r_jobs_list        = $r_jobs_xml.EntityReferences.Ref

# Start prompting
Write-Host "******************************************************" -ForegroundColor Cyan
Write-Host "*   File Recovery using Enterprise Manager RestAPI   *" -ForegroundColor Cyan
Write-Host "******************************************************" -ForegroundColor Cyan
Write-Host
Write-Host "This PowerShell script connects to the Veeam Enterprise Manager RestAPI, retrieves available restore points for a specific Windows virtual machine and allows the user to search for a specific file(s) to perform a file-level restore from the selected restore point." -ForegroundColor White
Write-Host

# Prompt the user to enter the hostname to search for
$searchHostname     = Read-Host "Enter the hostname to search a restore point for"

# Search for the hostname in the sorted entries
$filteredEntries    = $r_jobs_list | Where-Object { $_.Name -like "*$searchHostname@*" }

# Check if any matching entries were found
if ($filteredEntries.Count -gt 0) {
    # Display the matching entries
    Write-Host
    Write-Host "Found restore point(s):" -ForegroundColor White
    for ($i = 0; $i -lt $filteredEntries.Count; $i++) {
        $entry = $filteredEntries[$i]
        $uid   = $entry.UID
        $name  = $entry.Name
        Write-Host "$($i + 1). Restore Point: $name" -ForegroundColor White
    }

    # Prompt the user to select an entry
    $selectedEntry    = Read-Host "Select an entry (enter the number)"
    $selectedIndex    = [int]$selectedEntry - 1

    # Check if the selected index is valid
    if ($selectedIndex -ge 0 -and $selectedIndex -lt $filteredEntries.Count) {
        $selectedJob  = $filteredEntries[$selectedIndex]

        # Perform the FLR using the selected job
        Write-Host
        Write-Host "Starting File Level Recovery..."
        $rpQuery      = $selectedJob.Href + "/mounts"
        $FLRsess      = Invoke-WebRequest -Method Post -Headers @{$sessionheadername = $sessionid} -Uri $rpQuery -UseBasicParsing
        
        # Wait for the FLR job to initialize
        Write-Host "Initialize..."
        Sleep 10
        Clear-Host

        # Get the FLR session information
        $getFLRsess   = Invoke-WebRequest -Method Get -Headers @{$sessionheadername = $sessionid} -Uri $rpQuery -UseBasicParsing

        # Convert the XML content to an XML object
        $xmlData      = [xml]$getFLRsess.Content

        # Access the VmRestorePointMount element
        $mountElement = $xmlData.VmRestorePointMounts.VmRestorePointMount

        # Delete entry for stopping the FLR session later on
        $deleteLink = $xmlData.VmRestorePointMounts.VmRestorePointMount.Links.Link | Where-Object { $_.Rel -eq "Delete" }
        $deleteURL  = $deleteLink.Href

        # Access the FSRoots element
        $fsRoots = $mountElement.FSRoots

        # Store the DirectoryEntry elements in an array
        $directoryEntries = $fsRoots.DirectoryEntry

        # Sort the DirectoryEntry elements by Path
        $sortedEntries = $directoryEntries | Sort-Object -Property Path

# Function to stop the FLR session
function Stop-FLRSession {
$deleteResponse = Invoke-WebRequest -Method Delete -Headers @{ $sessionheadername = $sessionid } -Uri $DeleteURL -UseBasicParsing
        if ($deleteResponse.StatusCode -eq 204) {
            Write-Host "File Level Recovery process stopped successfully." -ForegroundColor Green
        } else {
            Write-Host "File Level Recovery process stopping failed. Status code: $($deleteResponse.StatusCode)" -ForegroundColor Red
        }

        Exit
    }

# Function to restore a selected file
        function RestoreFile($selectedFileHref) {
            # Generate the restore request URL
            $restoreUrl = $selectedFileHref + "?action=restore"

            # Set up the request body
            $requestBody = @{
                ForDirectDownload = @{
                    FileName = (Split-Path $selectedFileHref -Leaf)
                }
            }

            # Convert the request body to JSON - No idea (yet) why it isn't working using XML
            $jsonBody = $requestBody | ConvertTo-Json

            # Display the restore URL for debugging purposes
            #Write-Host "Restore URL: $restoreUrl"

            try {
                # Start the restore
                Clear-Host
                Write-Host "Start restore $selectedFile..."
                $restoreResponse = Invoke-WebRequest -Method Post -Headers @{$sessionheadername = $sessionid} -Uri $restoreUrl -Body $jsonBody -ContentType "application/json" -UseBasicParsing

                ###Write-Host "Restore request sent. Response:"
                #$restoreResponse.Content

                # Check if the restore request was accepted
                if ($restoreResponse.StatusCode -eq 202) {
                    # Get the task ID from the restore response
                    $taskId = ($restoreResponse.Content | ConvertFrom-Json).TaskId

                    # Construct the URL to check the task status
                    $taskStatusUrl = "$server/tasks/$taskId"

                    # Wait for the restore task to complete
                    while ($true) {
                        try {
                            # Check the task status
                            $taskStatusResponse = Invoke-WebRequest -Method Get -Headers @{$sessionheadername = $sessionid} -Uri $taskStatusUrl -UseBasicParsing
                            $taskStatusXml      = [xml]$taskStatusResponse.Content
                            $taskState          = $taskStatusXml.Task.State

                            # If the task is in a finished state, break out of the loop
                            if ($taskState -eq "Finished") {
                                break
                            }

                            # Sleep for a few seconds before checking again
                            Start-Sleep -Seconds 5
                        } catch {
                            Write-Host "Error occurred while checking task status:"
                            Write-Host $_.Exception.Message
                            break
                        }
                    }

                    # Check if the restore task was successful
                    if ($taskState -eq "Finished") {
                        # Find the download link in the task response
                        $downloadLink = $taskStatusXml.Task.Links.Link | Where-Object { $_.Rel -eq "download" }

                        if ($downloadLink) {
                            # Get the URL to download the restored file
                            $fileDownloadUrl = $downloadLink.Href
                            $downloadFile = Invoke-WebRequest -Method Get -Headers @{$sessionheadername = $sessionid} -Uri $fileDownloadUrl -UseBasicParsing
                            Write-Host "File restore completed successfully."
                            } 
                    } else {
                        Write-Host "File restore task did not complete successfully. Task state: $taskState"
                    }
                } else {
                    Write-Host "Restore request was not accepted. Status code: $($restoreResponse.StatusCode)"
                }
            } catch {
                Write-Host "Error occurred during restore request:"
                Write-Host $_.Exception.Message
            }
        }

        # Function to list directories within a selected directory
        function ListDirectories($directoryEntryHref) {
        $listAllFS   = $directoryEntryHref + "?action=listAll&amp;pageSize=100&amp;"
        $result      = Invoke-WebRequest -Method Get -Headers @{$sessionheadername = $sessionid} -Uri $listAllFS -UseBasicParsing

        $xml         = [xml]$result.Content
        $directories = $xml.FileSystemEntries.Directories.DirectoryEntry | Select-Object -ExpandProperty Name

        # Display the list of directories
        Write-Host "Listing directories..."
        Write-Host "----------------------"
        $directories

        # Prompt the user to select a directory or list files
        $selectedOption = Read-Host "Enter 'back' to go back, the filenames to restore (separated by commas), 'exit' to exit the script, or 'files' to list files again"
        if ($selectedOption -eq "back") {
            # Find the parent directory href
            $parentDirectoryHref = $directoryEntryHref -replace "/[^/]+$"

            # Call the function recursively to list directories in the parent directory
            ListDirectories $parentDirectoryHref
        }

        elseif ($selectedOption -eq "exit") {
            # Close the session and exit the script
            Stop-FLRSession 
        }
    
        elseif ($selectedOption -eq "files") {
            $listFilesQuery = $directoryEntryHref + "?action=listFiles&amp;pageSize=100&amp;"
            $filesResult = Invoke-WebRequest -Method Get -Headers @{$sessionheadername = $sessionid} -Uri $listFilesQuery -UseBasicParsing

            $filesXml = [xml]$filesResult.Content
            $files = $filesXml.FileSystemEntries.Files.FileEntry | Select-Object -ExpandProperty Name

            # Display the list of files
            Write-Host "Listing files..."
            Write-Host "----------------"
            $files

            # Prompt the user to select a file or go back
    $selectedOption = Read-Host "Enter 'back' to go back, the filenames to restore (separated by commas), 'exit' to exit the script, or 'files' to list files again"

    if ($selectedOption -eq "back") {
        # Find the parent directory href
        $parentDirectoryHref = $directoryEntryHref -replace "/[^/]+$"

        # Call the function recursively to list directories in the parent directory
        ListDirectories $parentDirectoryHref
    }

    elseif ($selectedOption -eq "exit") {
            # Close the session and exit the script
            Stop-FLRSession
    }

    elseif ($selectedOption -eq "files") {
        # Call the function recursively to list files again
        ListFiles $directoryEntryHref
    }
    else {
        $selectedFiles = $selectedOption -split ','

        # Trim whitespace from filenames
        $selectedFiles = $selectedFiles | ForEach-Object { $_.Trim() }

        # Filter out empty filenames
        $selectedFiles = $selectedFiles | Where-Object { $_ -ne "" }

        # Restore the selected files
        $selectedFileHrefs = @()
        foreach ($selectedFile in $selectedFiles) {
            # Find the selected file and retrieve its href
            $selectedFileEntry = $filesXml.FileSystemEntries.Files.FileEntry | Where-Object { $_.Name -eq $selectedFile }
            if ($selectedFileEntry) {
                $selectedFileHrefs += $selectedFileEntry.Href
            }
            else {
                Write-Host "Invalid file '$selectedFile'. Skipping..."
            }
        }

        if ($selectedFileHrefs.Count -gt 0) {
            RestoreMultipleFiles $selectedFileHrefs
            ListFiles $directoryEntryHref
        }
        else {
            Write-Host "No valid files selected. Please try again."
            ListFiles $directoryEntryHref
        }
    }

        }
        elseif ($directories -contains $selectedOption) {
            # Find the selected directory and retrieve its href
            $selectedEntry     = $xml.FileSystemEntries.Directories.DirectoryEntry | Where-Object { $_.Name -eq $selectedOption }
            $selectedEntryHref = $selectedEntry.Href

            # Call the function recursively to list directories in the selected directory
            Clear-Host
            ListDirectories $selectedEntryHref
        }
        else {
            Write-Host
            Write-Host "Invalid directory name. Please try again."
            ListDirectories $directoryEntryHref
        }
    }

    
    # Function to restore multiple selected files
function RestoreMultipleFiles($selectedFileHrefs) {
    foreach ($selectedFileHref in $selectedFileHrefs) {
        RestoreFile $selectedFileHref
    }
}

# Function to list files within a selected directory
function ListFiles($directoryEntryHref) {
    
    # Prompt the user to select files or go back
    $selectedOption = Read-Host "Enter 'back' to go back, the filenames to restore (separated by commas), 'exit' to exit the script, or 'files' to list files again"

    if ($selectedOption -eq "back") {
        # Find the parent directory href
        $parentDirectoryHref = $directoryEntryHref -replace "/[^/]+$"
        # Call the function recursively to list directories in the parent directory
        ListDirectories $parentDirectoryHref
    }
    elseif ($selectedOption -eq "exit") {
        # Close the session and exit the script
        Stop-FLRSession
    }


    elseif ($selectedOption -eq "files") {
        # Call the function recursively to list files again
        ListFiles $directoryEntryHref
    }
    else {
        $selectedFiles = $selectedOption -split ','

        # Trim whitespace from filenames
        $selectedFiles = $selectedFiles | ForEach-Object { $_.Trim() }

        # Filter out empty filenames
        $selectedFiles = $selectedFiles | Where-Object { $_ -ne "" }

        # Restore the selected files
        $selectedFileHrefs = @()
        foreach ($selectedFile in $selectedFiles) {
            # Find the selected file and retrieve its href
            $selectedFileEntry = $filesXml.FileSystemEntries.Files.FileEntry | Where-Object { $_.Name -eq $selectedFile }
            if ($selectedFileEntry) {
                $selectedFileHrefs += $selectedFileEntry.Href
            }
            else {
                Write-Host "File '$selectedFile' not found. Skipping..."
            }
        }

        if ($selectedFileHrefs.Count -gt 0) {
            RestoreMultipleFiles $selectedFileHrefs
            ListFiles $directoryEntryHref
        }
        else {
            Write-Host "No valid files selected. Please try again."
            ListFiles $directoryEntryHref
        }
    }
}

 # Loop through each sorted DirectoryEntry and display their attributes
        for ($i = 0; $i -lt $sortedEntries.Count; $i++) {
            $directoryEntry = $sortedEntries[$i]
            $directoryEntryHref = $directoryEntry.Href
            $directoryEntryType = $directoryEntry.Type
            $directoryEntryPath = $directoryEntry.Path
            $directoryEntryName = $directoryEntry.Name

            Write-Host "Available Path $($i + 1):"
            Write-Host "  Drive: $directoryEntryPath"
        }

        # Prompt the user to select a specific entry
        $selectedEntry = Read-Host "Select an entry (enter the number)"
        $selectedIndex = [int]$selectedEntry - 1

        # Check if the selected index is valid
        if ($selectedIndex -ge 0 -and $selectedIndex -lt $sortedEntries.Count) {
            $selectedDirectoryEntry = $sortedEntries[$selectedIndex]

            # Call the function to list directories within the selected directory
            Clear-Host
            ListDirectories $selectedDirectoryEntry.Href
        } else {
            Clear-Host
            Write-Host "Invalid Path selection. Please try again."
            
        }

    } else {
        
        Write-Host "Invalid restore point selection. Please try again."
               
    }
    } else {
        Write-Host "No matching entries found for the specified hostname."
    }
