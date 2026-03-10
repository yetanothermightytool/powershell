<#
.SYNOPSIS
    Veeam SQL Disk Publish Script
    Performs a disk publish of a SQL database from a Veeam Backup.

.DESCRIPTION
    The script retrieves the latest restore point for a specified VM,
    starts a SQL restore session, publishes the target database to a
    destination server, runs a connectivity test, waits for a configurable
    timeout, and then cleanly stops the publish and restore session.

.PARAMETER VMName
    Name of the VM / backup job from which the restore point is retrieved.

.PARAMETER DBName
    Name of the source database to be published.

.PARAMETER DestSrv
    Destination server where the database will be published.

.PARAMETER SQLUser
    SQL username for authentication on the destination server.

.PARAMETER SQLPassword
    SQL password for authentication on the destination server.

.PARAMETER TimeoutMinutes
    How many minutes the published database stays available before the
    session is automatically stopped. Default: 30 minutes.

.EXAMPLE
    .\mssql-check.ps1 -VMName "SQLSERVER01" -DBName "ProductionData" -DestSrv "SQLSRV-TEST"

.EXAMPLE
    .\mssql-check.ps1 -VMName "SQLSERVER01" -DBName "ProductionData" -DestSrv "SQLSRV-TEST" -TimeoutMinutes 120

.NOTES
    Prerequisites:
    - Veeam Backup & Replication PowerShell Snapin must be available
    - Must be run on the Veeam Backup Server or a server with Veeam Console installed
    - Appropriate permissions on Veeam and the target SQL server

    SECURITY NOTE:
    Storing credentials directly in the script is not recommended for production.
    Preferred alternatives: Windows Authentication or a secrets vault.
#>

# PARAMETERS
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false, HelpMessage = "Veeam Backup & Replication server to connect to. Default: localhost")]
    [string]$VBRServer = "localhost",

    [Parameter(Mandatory = $true,  HelpMessage = "Name of the VM in Veeam Backup")]
    [string]$VMName,

    [Parameter(Mandatory = $true,  HelpMessage = "Name of the SQL database to be published")]
    [string]$DBName,

    [Parameter(Mandatory = $true,  HelpMessage = "Destination server name for the published database")]
    [string]$DestSrv,

    # -------------------------------------------------------
    # SECURITY NOTE: Storing credentials here is not secure.
    # -------------------------------------------------------
    [Parameter(Mandatory = $false, HelpMessage = "SQL username")]
    [string]$SQLUser = "Administrator",

    [Parameter(Mandatory = $false, HelpMessage = "SQL password")]
    [string]$SQLPassword = "",

    [Parameter(Mandatory = $false, HelpMessage = "Minutes the published DB stays available before auto-cleanup")]
    [int]$TimeoutMinutes = 30
)

### FUNCTIONS

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR","SUCCESS")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "INFO"    { "Cyan"   }
        "WARN"    { "Yellow" }
        "ERROR"   { "Red"    }
        "SUCCESS" { "Green"  }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Get-LatestRestorePoint {
    param([string]$Name)

    Write-Log "Searching restore points for VM: '$Name'..."
    try {
        $restorePoints = Get-VBRApplicationRestorePoint -Name $Name -SQL -ErrorAction Stop
        if (-not $restorePoints) {
            Write-Log "No restore points found for: '$Name'" -Level "ERROR"
            exit 1
        }

        # Sort by CreationTime descending and pick the most recent entry
        $latest = $restorePoints |
                  Sort-Object -Property CreationTime -Descending |
                  Select-Object -First 1

        Write-Log "Latest restore point found:" -Level "SUCCESS"
        Write-Log "  CreationTime : $($latest.CreationTime)"
        Write-Log "  Name         : $($latest.Name)"

        return $latest
    }
    catch {
        Write-Log "Error retrieving restore points: $_" -Level "ERROR"
        exit 1
    }
}

function Start-SQLRestoreSession {
    param($RestorePoint)

    Write-Log "Starting SQL restore session..."
    try {
        $session = Start-VESQLRestoreSession -RestorePoint $RestorePoint -ErrorAction Stop
        Write-Log "SQL restore session started. Session ID: $($session.Id)" -Level "SUCCESS"
        return $session
    }
    catch {
        Write-Log "Error starting restore session: $_" -Level "ERROR"
        exit 1
    }
}

function Get-RestoreDatabase {
    param($Session, [string]$DatabaseName)

    Write-Log "Looking up database '$DatabaseName' in restore session..."
    try {
        $db = Get-VESQLDatabase -Session $Session -Name $DatabaseName -ErrorAction Stop
        if (-not $db) {
            Write-Log "Database '$DatabaseName' was not found in the session." -Level "ERROR"
            exit 1
        }
        Write-Log "Database '$DatabaseName' found." -Level "SUCCESS"
        return $db
    }
    catch {
        Write-Log "Error retrieving database: $_" -Level "ERROR"
        exit 1
    }
}

function Publish-Database {
    param(
        $Database,
        [string]$SourceDBName,
        [string]$TargetServer,
        [string]$User,
        [string]$Password
    )

    $publishedName  = "${SourceDBName}_temp"
    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $credentials    = New-Object System.Management.Automation.PSCredential($User, $securePassword)

    Write-Log "Publishing database..."
    Write-Log "  Source DB     : $SourceDBName"
    Write-Log "  Target DB     : $publishedName"
    Write-Log "  Target Server : $TargetServer"
    Write-Log "  SQL User      : $User"

    try {
        $publish = Publish-VESQLDatabase `
            -Database         $Database `
            -DatabaseName     $publishedName `
            -ServerName       $TargetServer `
            -GuestCredentials $credentials `
            -ErrorAction Stop

        Write-Log "Database published successfully!" -Level "SUCCESS"
        Write-Log "  Published as : $publishedName"
        Write-Log "  Server       : $TargetServer"
        return $publish
    }
    catch {
        Write-Log "Error publishing database: $_" -Level "ERROR"
        exit 1
    }
}

function Test-SQLConnectivity {
    <#
    .SYNOPSIS Runs a SELECT 1 connectivity test against the published database.
    Uses System.Data.SqlClient — no extra PowerShell modules required.
    Retries every 15 seconds for up to 5 minutes to give SQL Server time to come online.
    #>
    param(
        [string]$Server,
        [string]$Database,
        [string]$User,
        [string]$Password
    )

    # Windows Authentication — credentials come from the OS account running the script.
    $connectionString = "Server=$Server;Database=$Database;Integrated Security=True;Connect Timeout=10;"
    $maxAttempts      = 20    # 20 x 15s = max 5 minutes
    $attempt          = 0

    Write-Log "Starting SQL connectivity test (SELECT 1) on [$Server].[$Database]..."

    while ($attempt -lt $maxAttempts) {
        $attempt++
        try {
            $connection             = New-Object System.Data.SqlClient.SqlConnection($connectionString)
            $connection.Open()
            $command                = $connection.CreateCommand()
            $command.CommandText    = "SELECT 1"
            $result                 = $command.ExecuteScalar()
            $connection.Close()

            if ($result -eq 1) {
                Write-Log "Connectivity test passed (SELECT 1 returned $result)." -Level "SUCCESS"
                return $true
            }
        }
        catch {
            $errorMessage = $_.Exception.Message

            # Auth errors will never resolve by retrying — abort immediately
            if ($errorMessage -match "Login failed" -or $errorMessage -match "password" -or $errorMessage -match "18456") {
                Write-Log "Authentication error — check SQLUser / SQLPassword credentials: $errorMessage" -Level "ERROR"
                Write-Log "Hint: Verify that SQL Authentication is enabled on [$Server] and that the user '$User' exists." -Level "WARN"
                return $false
            }

            # All other errors (network, server not yet ready) — keep retrying
            Write-Log "Attempt $attempt/$maxAttempts — not yet reachable: $errorMessage" -Level "WARN"
        }

        if ($attempt -lt $maxAttempts) {
            Write-Log "Retrying in 15 seconds..."
            Start-Sleep -Seconds 15
        }
    }

    Write-Log "Connectivity test failed after $maxAttempts attempts." -Level "ERROR"
    return $false
}

function Wait-AndCleanup {
    param(
        $Session,
        $PublishObject,
        [int]$Minutes
    )

    if ($Minutes -gt 0) {
        $deadline = (Get-Date).AddMinutes($Minutes)
        Write-Log "Published database will be available for $Minutes minute(s)."
        Write-Log "Auto-cleanup scheduled at: $($deadline.ToString('yyyy-MM-dd HH:mm:ss'))"

        for ($remaining = $Minutes; $remaining -gt 0; $remaining--) {
            Write-Log "Time remaining before cleanup: $remaining minute(s)..."
            Start-Sleep -Seconds 60
        }
    }

    Write-Log "Starting cleanup..."

    try {
        Write-Log "Unpublishing database..."
        Unpublish-VESQLDatabase -Database $PublishObject -Force -ErrorAction Stop
        Write-Log "Database unpublished successfully." -Level "SUCCESS"
    }
    catch {
        Write-Log "Unpublish step skipped (session stop will handle cleanup): $_" -Level "WARN"
    }

    try {
        Write-Log "Stopping SQL restore session..."
        Stop-VESQLRestoreSession -Session $Session -ErrorAction Stop
        Write-Log "Restore session stopped cleanly." -Level "SUCCESS"
    }
    catch {
        Write-Log "Error stopping restore session: $_" -Level "ERROR"
    }
}

# MAIN
Write-Log "======================================================="
Write-Log " Veeam SQL Disk Publish - Start"
Write-Log "======================================================="
Write-Log "Parameters:"
Write-Log "  VM Name         : $VMName"
Write-Log "  DB Name         : $DBName"
Write-Log "  Destination Srv : $DestSrv"
Write-Log "  Timeout         : $TimeoutMinutes minute(s)"

# Connect to VBR Server
Write-Log "Connecting to VBR Server: $VBRServer..."
try {
    Connect-VBRServer -Server $VBRServer -ErrorAction Stop
    Write-Log "Connected to VBR Server: $VBRServer" -Level "SUCCESS"
}
catch {
    Write-Log "Failed to connect to VBR Server '$VBRServer': $_" -Level "ERROR"
    exit 1
}

# Retrieve the latest restore point
$restorePoint = Get-LatestRestorePoint -Name $VMName

# Start the SQL restore session
$session = Start-SQLRestoreSession -RestorePoint $restorePoint

# Retrieve the database object from the session
$restoreDb = Get-RestoreDatabase -Session $session -DatabaseName $DBName

# Publish the database to the destination server
$publish = Publish-Database `
    -Database     $restoreDb `
    -SourceDBName $DBName `
    -TargetServer $DestSrv `
    -User         $SQLUser `
    -Password     $SQLPassword

# Connectivity test — SELECT 1 against the published database
$publishedDBName = "${DBName}_temp"
$testPassed = Test-SQLConnectivity `
    -Server   $DestSrv `
    -Database $publishedDBName `
    -User     $SQLUser `
    -Password $SQLPassword

if (-not $testPassed) {
    # Connectivity failed — clean up immediately and exit with error
    Write-Log "Connectivity test failed — initiating immediate cleanup." -Level "WARN"
    Wait-AndCleanup -Session $session -PublishObject $publish -Minutes 0
    exit 1
}

# Wait for the configured timeout, then clean up
Wait-AndCleanup -Session $session -PublishObject $publish -Minutes $TimeoutMinutes

# Disconnect from VBR Server
try {
    Disconnect-VBRServer -ErrorAction Stop
    Write-Log "Disconnected from VBR Server: $VBRServer" -Level "SUCCESS"
}
catch {
    Write-Log "Failed to disconnect from VBR Server: $_" -Level "WARN"
}

Write-Log "======================================================="
Write-Log " Veeam SQL Disk Publish - Completed" -Level "SUCCESS"
Write-Log "======================================================="
