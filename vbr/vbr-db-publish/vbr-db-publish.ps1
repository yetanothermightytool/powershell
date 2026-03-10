 <#
.SYNOPSIS
    Veeam Database Disk Publish Script
    Supports Microsoft SQL Server, PostgreSQL and MongoDB.

.DESCRIPTION
    The script retrieves the latest restore point for a specified VM,
    starts a database restore session using the correct Veeam Explorer
    cmdlets for the selected engine, publishes the target database to a
    destination server, runs a connectivity test, waits for a configurable
    timeout, and then cleanly stops the publish and restore session.

.PARAMETER VMName
    Name of the VM from which the restore point is retrieved.

.PARAMETER DBName
    Name of the source database or instance to be published.

.PARAMETER DestSrv
    Destination server where the database will be published.

.PARAMETER DBType
    Database engine type. Accepted values: MSSQL, PostgreSQL, MongoDB
    Default: MSSQL

.PARAMETER DBUser
    Database username for the connectivity test and security queries.
    MSSQL      : optional / only used when cred-mssql.xml is present (SQL Server Login, not a Windows account). Falls back to Windows Authentication if omitted.
    PostgreSQL : PostgreSQL user
    MongoDB    : required when -QueryFile is specified (authenticated queries)

.PARAMETER DBPassword
    Password for DBUser.

.PARAMETER LinuxUser
    Linux OS username for SSH access to the target server.
    Used by Veeam to mount and publish the instance on the target.
    Required for PostgreSQL and MongoDB.

.PARAMETER LinuxPassword
    Password for LinuxUser.

.PARAMETER TimeoutMinutes
    Minutes the published database stays available before auto-cleanup.
    Default: 30

.PARAMETER DBPort
    Port for the published database instance on the destination server.
    PostgreSQL default: 5433 (avoids conflict with production on 5432).
    MongoDB    default: 27017

.NOTES
    Prerequisites:
    - Must be run on the Veeam Backup Server or a server with Veeam Console installed
    - PostgreSQL connectivity test requires psql.exe in PATH
    - MongoDB connectivity test uses mongosh.exe if available, falls back to TCP port check
    - Appropriate permissions on Veeam and the target server

    SECURITY NOTE:
    Storing credentials in the script is not recommended for production.

    DISCLAIMER:
    This script is not officially supported by Veeam Software. Use it at your own risk.
#>

# ============================================================
# PARAMETERS
# ============================================================
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false, HelpMessage = "Veeam Backup & Replication server to connect to. Default: localhost")]
    [string]$VBRServer = "localhost",

    [Parameter(Mandatory = $true,  HelpMessage = "Name of the VM in Veeam Backup")]
    [string]$VMName,

    [Parameter(Mandatory = $true,  HelpMessage = "Name of the database / instance to be published")]
    [string]$DBName,

    [Parameter(Mandatory = $true,  HelpMessage = "Destination server name for the published database")]
    [string]$DestSrv,

    [Parameter(Mandatory = $false, HelpMessage = "Database engine: MSSQL, PostgreSQL, MongoDB")]
    [ValidateSet("MSSQL", "PostgreSQL", "MongoDB")]
    [string]$DBType = "MSSQL",

    # -------------------------------------------------------
    # SECURITY NOTE: Storing credentials here is not secure.
    # -------------------------------------------------------
    [Parameter(Mandatory = $false, HelpMessage = "Database username for connectivity test (PostgreSQL: e.g. postgreadmin)")]
    [string]$DBUser = "postgredbuser",

    [Parameter(Mandatory = $false, HelpMessage = "Password for DBUser")]
    [string]$DBPassword = "PASS",

    [Parameter(Mandatory = $false, HelpMessage = "Linux OS username for SSH access to the target server (PostgreSQL / MongoDB)")]
    [string]$LinuxUser = "linuxusr",

    [Parameter(Mandatory = $false, HelpMessage = "Linux OS password for SSH access to the target server (PostgreSQL / MongoDB)")]
    [string]$LinuxPassword = "PASS",

    [Parameter(Mandatory = $false, HelpMessage = "Minutes the published DB stays available before auto-cleanup")]
    [int]$TimeoutMinutes = 30,

    [Parameter(Mandatory = $false, HelpMessage = "Port for the published instance on the destination server (PostgreSQL default: 5433. Assign another port for MongoDB).")]
    [int]$DBPort = 5433,

    [Parameter(Mandatory = $false, HelpMessage = "MongoDB Replica Set name (e.g. rs0).")]
    [string]$ReplicaSet = "rs0",

    [Parameter(Mandatory = $false, HelpMessage = "Path to JSON file containing security queries per DB type. Optional.")]
    [string]$QueryFile = ""
)

# ============================================================
# SHARED FUNCTIONS
# ============================================================

function Write-Log {
    <#
    .SYNOPSIS Outputs a formatted log message with timestamp and colour.
    #>
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

# ------------------------------------------------------------

function Get-CredentialFromManager {
    <#
    .SYNOPSIS Loads a PSCredential from an encrypted XML file in the script directory.
    Files are created once with: Get-Credential | Export-Clixml "$PSScriptRoot\cred-linux.xml"
    Encrypted with DPAPI -- only readable by the same user on the same machine.
    #>
    param([string]$Target)

    $xmlFile = Join-Path $PSScriptRoot "cred-$Target.xml"

    if (-not (Test-Path $xmlFile)) {
        Write-Log "Credential file not found: '$xmlFile'" -Level "WARN"
        Write-Log "Create it with: Get-Credential | Export-Clixml '$xmlFile'" -Level "WARN"
        return $null
    }

    try {
        $cred = Import-Clixml -Path $xmlFile -ErrorAction Stop
        Write-Log "Loaded credentials from '$xmlFile' (User: $($cred.UserName))" -Level "SUCCESS"
        return $cred
    }
    catch {
        Write-Log "Failed to load credential file '$xmlFile': $_" -Level "WARN"
        return $null
    }
}

# ------------------------------------------------------------

function Test-QuerySafe {
    <#
    .SYNOPSIS Checks a query for dangerous keywords before execution.
    Returns $true if safe, $false if a blocked keyword is found.
    Uses word boundaries so partial matches (e.g. a column named 'executor') are not blocked.
    #>
    param([string]$Query)

    $blocked = @(
        'DROP', 'DELETE', 'INSERT', 'UPDATE', 'CREATE',
        'TRUNCATE', 'EXEC', 'EXECUTE', 'ALTER', 'GRANT',
        'REVOKE', 'SHUTDOWN', 'KILL', 'MERGE', 'REPLACE'
    )

    foreach ($keyword in $blocked) {
        if ($Query -match "(?i)\b$keyword\b") {
            return $false, $keyword
        }
    }
    return $true, $null
}

# ------------------------------------------------------------

function Invoke-SecurityQueries {
    <#
    .SYNOPSIS Loads a JSON query file and runs all queries for the given DB type.
    Results are always logged regardless of content.
    If -QueryFile is not specified or the file does not exist, this step is skipped.
    
    JSON format:
    {
      "MSSQL":      [ { "name": "...", "description": "...", "query": "..." } ],
      "PostgreSQL": [ { "name": "...", "description": "...", "query": "..." } ],
      "MongoDB":    [ { "name": "...", "description": "...", "query": "..." } ]
    }
    #>
    param(
        [string]$QueryFilePath,
        [string]$Type,
        [string]$Server,
        [string]$Database,
        [string]$DBUser,
        [string]$DBPassword,
        [int]$Port
    )

    if (-not $QueryFilePath -or -not (Test-Path $QueryFilePath)) {
        if ($QueryFilePath) {
            Write-Log "Query file not found: '$QueryFilePath' -- skipping security queries." -Level "WARN"
        }
        return
    }

    Write-Log "======================================================="
    Write-Log " Security Query Checks -- $Type"
    Write-Log "======================================================="

    try {
        $config  = Get-Content $QueryFilePath -Raw | ConvertFrom-Json
        $queries = $config.$Type

        if (-not $queries) {
            Write-Log "No queries defined for '$Type' in query file." -Level "WARN"
            return
        }

        foreach ($q in $queries) {
            Write-Log "Running: $($q.name)"
            Write-Log "  Description : $($q.description)"

            # Safety check -- block any query containing destructive keywords
            $isSafe, $blockedKeyword = Test-QuerySafe -Query $q.query
            if (-not $isSafe) {
                Write-Log "  BLOCKED: Query contains forbidden keyword '$blockedKeyword' -- skipping." -Level "ERROR"
                continue
            }

            try {
                switch ($Type) {

                    "MSSQL" {
                        # SQL Auth if DBUser/DBPassword provided, otherwise Windows Authentication
                        if ($DBUser -and $DBPassword) {
                            $connStr = "Server=$Server;Database=$Database;User Id=$DBUser;Password=$DBPassword;Connect Timeout=10;"
                        } else {
                            $connStr = "Server=$Server;Database=$Database;Integrated Security=True;Connect Timeout=10;"
                        }
                        $conn    = New-Object System.Data.SqlClient.SqlConnection($connStr)
                        $conn.Open()
                        $cmd             = $conn.CreateCommand()
                        $cmd.CommandText = $q.query
                        $reader          = $cmd.ExecuteReader()
                        $results         = @()
                        while ($reader.Read()) {
                            $row = @{}
                            for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                                $row[$reader.GetName($i)] = $reader.GetValue($i)
                            }
                            $results += [PSCustomObject]$row
                        }
                        $reader.Close()
                        $conn.Close()

                        if ($results.Count -eq 0) {
                            Write-Log "  Result      : (no rows returned)" -Level "INFO"
                        } else {
                            foreach ($row in $results) {
                                Write-Log "  Result      : $($row | ConvertTo-Json -Compress)" -Level "WARN"
                            }
                        }
                    }

                    "PostgreSQL" {
                        $env:PGPASSWORD = $DBPassword
                        $queryText = $q.query
                        $output = & psql `
                            --host=$Server `
                            --port=$Port `
                            --username=$DBUser `
                            --dbname=$Database `
                            --command="$queryText" `
                            --tuples-only 2>&1
                        $env:PGPASSWORD = $null

                        $lines = ($output | ForEach-Object { "$_" } | Where-Object { $_.Trim() -ne "" })
                        if (-not $lines) {
                            Write-Log "  Result      : (no rows returned)" -Level "INFO"
                        } else {
                            foreach ($line in $lines) {
                                Write-Log "  Result      : $line" -Level "WARN"
                            }
                        }
                    }

                    "MongoDB" {
                        $mongosh = Get-Command mongosh.exe -ErrorAction SilentlyContinue
                        if ($mongosh) {
                            $queryText = $q.query
                            # Use DBUser/DBPassword for authenticated queries
                            $output = & mongosh.exe --host $Server --port $Port --username $DBUser --password $DBPassword --authenticationDatabase admin --eval "$queryText" 2>&1
                            $lines = ($output | ForEach-Object { "$_" } | Where-Object { $_.Trim() -ne "" -and $_ -notmatch "^Current Mongosh" -and $_ -notmatch "^Using MongoDB" -and $_ -notmatch "^Connecting to" })
                            if (-not $lines) {
                                Write-Log "  Result      : (no output)" -Level "INFO"
                            } else {
                                foreach ($line in $lines) {
                                    Write-Log "  Result      : $line" -Level "WARN"
                                }
                            }
                        } else {
                            Write-Log "  Result      : mongosh.exe not found -- cannot run MongoDB query." -Level "WARN"
                        }
                    }
                }
            }
            catch {
                Write-Log "  Error running query '$($q.name)': $_" -Level "ERROR"
            }
        }
    }
    catch {
        Write-Log "Failed to load or parse query file '$QueryFilePath': $_" -Level "ERROR"
    }

    Write-Log "======================================================="
}

# ------------------------------------------------------------

function Get-LatestRestorePoint {
    <#
    .SYNOPSIS Retrieves the most recent application restore point for a given VM.
    Uses the correct engine-specific switch (-SQL, -PostgreSQL, -MongoDB).
    #>
    param(
        [string]$Name,
        [string]$Type,
        [string]$ReplicaSet = "rs0"
    )

    $searchName = if ($Type -eq "MongoDB") { $ReplicaSet } else { $Name }
    Write-Log "Searching restore points for: '$searchName' (Type: $Type)..."
    try {
        $restorePoints = switch ($Type) {
            "MSSQL"      { Get-VBRApplicationRestorePoint -Name $searchName -SQL        -ErrorAction Stop }
            "PostgreSQL" { Get-VBRApplicationRestorePoint -Name $searchName -PostgreSQL -ErrorAction Stop }
            # MongoDB: -Name must be the Replica Set name (e.g. rs0), not the hostname
            "MongoDB"    { Get-VBRApplicationRestorePoint -Name $searchName -MongoDB    -ErrorAction Stop }
        }

        if (-not $restorePoints) {
            Write-Log "No restore points found for: '$Name'" -Level "ERROR"
            exit 1
        }

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

# ------------------------------------------------------------

function Wait-AndCleanup {
    <#
    .SYNOPSIS Countdown timer, then calls the engine-specific cleanup function.
    #>
    param(
        [string]$Type,
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

    switch ($Type) {
        "MSSQL"      { Stop-MSSQLPublish     -Session $Session -PublishObject $PublishObject }
        "PostgreSQL" { Stop-PostgreSQLPublish -Session $Session -PublishObject $PublishObject }
        "MongoDB"    { Stop-MongoDBPublish    -Session $Session -PublishObject $PublishObject }
    }
}

# ============================================================
# MSSQL FUNCTIONS
# ============================================================

function Start-MSSQLSession {
    param($RestorePoint)
    Write-Log "[MSSQL] Starting SQL restore session..."
    try {
        $session = Start-VESQLRestoreSession -RestorePoint $RestorePoint -ErrorAction Stop
        Write-Log "[MSSQL] Session started. ID: $($session.Id)" -Level "SUCCESS"
        return $session
    }
    catch {
        Write-Log "[MSSQL] Error starting session: $_" -Level "ERROR"
        exit 1
    }
}

function Get-MSSQLDatabase {
    param($Session, [string]$DatabaseName)
    Write-Log "[MSSQL] Looking up database '$DatabaseName'..."
    try {
        $db = Get-VESQLDatabase -Session $Session -Name $DatabaseName -ErrorAction Stop
        if (-not $db) {
            Write-Log "[MSSQL] Database '$DatabaseName' not found in session." -Level "ERROR"
            exit 1
        }
        Write-Log "[MSSQL] Database '$DatabaseName' found." -Level "SUCCESS"
        return $db
    }
    catch {
        Write-Log "[MSSQL] Error retrieving database: $_" -Level "ERROR"
        exit 1
    }
}

function Publish-MSSQLDatabase {
    param($Database, [string]$SourceDBName, [string]$TargetServer, [string]$User, [string]$Password)

    $publishedName = "${SourceDBName}_temp"

    Write-Log "[MSSQL] Publishing database..."
    Write-Log "  Source DB     : $SourceDBName"
    Write-Log "  Target DB     : $publishedName"
    Write-Log "  Target Server : $TargetServer"

    try {
        # Publish always uses Windows Authentication (GuestCredentials = Windows account on target).
        # SQL Server Login credentials are only used for connectivity test and security queries.
        Write-Log "  Auth          : Windows Authentication (Publish)"
        $publish = Publish-VESQLDatabase `
            -Database     $Database `
            -DatabaseName $publishedName `
            -ServerName   $TargetServer `
            -ErrorAction Stop
        Write-Log "[MSSQL] Database published as '$publishedName' on '$TargetServer'." -Level "SUCCESS"
        return $publish
    }
    catch {
        Write-Log "[MSSQL] Error publishing database: $_" -Level "ERROR"
        exit 1
    }
}

function Test-MSSQLConnectivity {
    param(
        [string]$Server,
        [string]$Database,
        [string]$User     = "",
        [string]$Password = ""
    )

    # Use SQL Authentication if credentials are provided, otherwise Windows Authentication
    if ($User -and $Password) {
        $connectionString = "Server=$Server;Database=$Database;User Id=$User;Password=$Password;Connect Timeout=10;"
        Write-Log "[MSSQL] Starting connectivity test (SQL Auth, User: $User) on [$Server].[$Database]..."
    }
    else {
        $connectionString = "Server=$Server;Database=$Database;Integrated Security=True;Connect Timeout=10;"
        Write-Log "[MSSQL] Starting connectivity test (Windows Auth) on [$Server].[$Database]..."
    }

    $maxAttempts = 20   # 20 x 15s = max 5 minutes
    $attempt     = 0

    while ($attempt -lt $maxAttempts) {
        $attempt++
        try {
            $conn            = New-Object System.Data.SqlClient.SqlConnection($connectionString)
            $conn.Open()
            $cmd             = $conn.CreateCommand()
            $cmd.CommandText = "SELECT 1"
            $result          = $cmd.ExecuteScalar()
            $conn.Close()

            if ($result -eq 1) {
                Write-Log "[MSSQL] Connectivity test passed." -Level "SUCCESS"
                return $true
            }
        }
        catch {
            $msg = $_.Exception.Message
            # Auth errors will never resolve/abort immediately
            if ($msg -match "Login failed" -or $msg -match "18456") {
                Write-Log "[MSSQL] Authentication error: $msg" -Level "ERROR"
                return $false
            }
            Write-Log "[MSSQL] Attempt $attempt/$maxAttempts -- not yet reachable: $msg" -Level "WARN"
        }

        if ($attempt -lt $maxAttempts) {
            Write-Log "Retrying in 15 seconds..."
            Start-Sleep -Seconds 15
        }
    }

    Write-Log "[MSSQL] Connectivity test failed after $maxAttempts attempts." -Level "ERROR"
    return $false
}

function Stop-MSSQLPublish {
    param($Session, $PublishObject)

    # Unpublish the database first; if the cmdlet is unavailable the session stop below will implicitly remove the publish.
    try {
        Write-Log "[MSSQL] Unpublishing database..."
        Unpublish-VESQLDatabase -Database $PublishObject -Force -ErrorAction Stop
        Write-Log "[MSSQL] Database unpublished." -Level "SUCCESS"
    }
    catch {
        Write-Log "[MSSQL] Unpublish skipped (session stop will handle cleanup): $_" -Level "WARN"
    }

    try {
        Write-Log "[MSSQL] Stopping restore session..."
        Stop-VESQLRestoreSession -Session $Session -ErrorAction Stop
        Write-Log "[MSSQL] Session stopped cleanly." -Level "SUCCESS"
    }
    catch {
        Write-Log "[MSSQL] Error stopping session: $_" -Level "ERROR"
    }
}

# ============================================================
# POSTGRESQL FUNCTIONS
# ============================================================

function Start-PostgreSQLSession {
    param($RestorePoint)
    Write-Log "[PostgreSQL] Starting restore session..."
    try {
        $session = Start-VEPSQLRestoreSession -RestorePoint $RestorePoint -ErrorAction Stop
        Write-Log "[PostgreSQL] Session started. ID: $($session.Id)" -Level "SUCCESS"
        return $session
    }
    catch {
        Write-Log "[PostgreSQL] Error starting session: $_" -Level "ERROR"
        exit 1
    }
}

function Get-PostgreSQLInstance {
    param($Session)
    Write-Log "[PostgreSQL] Retrieving backed-up instance from session..."
    try {
        $instance = Get-VEPSQLInstance -Session $Session -ErrorAction Stop |
                    Select-Object -First 1
        if (-not $instance) {
            Write-Log "[PostgreSQL] No instance found in session." -Level "ERROR"
            exit 1
        }
        Write-Log "[PostgreSQL] Instance found: $($instance.Name)" -Level "SUCCESS"
        return $instance
    }
    catch {
        Write-Log "[PostgreSQL] Error retrieving instance: $_" -Level "ERROR"
        exit 1
    }
}

function Publish-PostgreSQLInstance {
    param($Instance, [string]$TargetServer, [string]$LinuxUser, [string]$LinuxPassword, [int]$Port)

    # ElevateAccountToRoot via sudo, if account already has sudo rights, no -AddToSudoers needed.
    $secureLinuxPassword = ConvertTo-SecureString $LinuxPassword -AsPlainText -Force
    $rootPassword        = ConvertTo-SecureString $LinuxPassword -AsPlainText -Force
    $linuxCreds          = New-VEPSQLLinuxCredential `
                            -Account              $LinuxUser `
                            -Password             $secureLinuxPassword `
                            -ElevateAccountToRoot `
                            -RootPassword         $rootPassword `
                            -ErrorAction Stop

    Write-Log "[PostgreSQL] Publishing instance..."
    Write-Log "  Source Instance : $($Instance.Name)"
    Write-Log "  Target Server   : $TargetServer"
    Write-Log "  Target Port     : $Port"

    try {
        $publish = Start-VEPSQLInstancePublish `
            -Instance         $Instance `
            -ServerName       $TargetServer `
            -LinuxCredentials $linuxCreds `
            -Port             $Port `
            -ErrorAction Stop

        Write-Log "[PostgreSQL] Instance published on '$TargetServer':$Port." -Level "SUCCESS"

        # Wait for the instance to fully come online before running connectivity test
        Write-Log "[PostgreSQL] Waiting 30 seconds for instance to come online..."
        Start-Sleep -Seconds 30

        return $publish
    }
    catch {
        Write-Log "[PostgreSQL] Error publishing instance: $_" -Level "ERROR"
        exit 1
    }
}

function Test-PostgreSQLConnectivity {
    param([string]$Server, [string]$Database, [string]$User, [string]$Password, [int]$Port = 5433)

    # Uses psql.exe -- must be available in PATH on the Veeam server.
    $maxAttempts = 20   # 20 x 15s = max 5 minutes
    $attempt     = 0

    Write-Log "[PostgreSQL] Starting connectivity test (psql SELECT 1) on [$Server]:$Port [$Database]..."

    $env:PGPASSWORD = $Password

    while ($attempt -lt $maxAttempts) {
        $attempt++
        try {
            $output = & psql `
                --host=$Server `
                --port=$Port `
                --username=$User `
                --dbname=$Database `
                --command="SELECT 1" `
                --tuples-only 2>&1

            if ($LASTEXITCODE -eq 0 -and $output -match "1") {
                Write-Log "[PostgreSQL] Connectivity test passed." -Level "SUCCESS"
                $env:PGPASSWORD = $null
                return $true
            }

            # Authentication failure -- no point retrying
            if ($output -match "authentication failed" -or $output -match "password authentication") {
                Write-Log "[PostgreSQL] Authentication error: $output" -Level "ERROR"
                $env:PGPASSWORD = $null
                return $false
            }

            Write-Log "[PostgreSQL] Attempt $attempt/$maxAttempts -- not yet reachable: $output" -Level "WARN"
        }
        catch {
            Write-Log "[PostgreSQL] Attempt $attempt/$maxAttempts -- psql error: $_" -Level "WARN"
        }

        if ($attempt -lt $maxAttempts) {
            Write-Log "Retrying in 15 seconds..."
            Start-Sleep -Seconds 15
        }
    }

    $env:PGPASSWORD = $null
    Write-Log "[PostgreSQL] Connectivity test failed after $maxAttempts attempts." -Level "ERROR"
    return $false
}

function Stop-PostgreSQLPublish {
    param($Session, $PublishObject)

    # Multiple publish jobs may be running simultaneously (e.g. from previous runs).
    # We identify the correct one by matching the RestorePointId of our publish object,
    # then stop only that specific job using -Force to suppress confirmation prompts.
    try {
        Write-Log "[PostgreSQL] Looking up active publish job to stop..."
        $targetPublish = Get-VEPSQLInstancePublish |
                         Where-Object { $_.RestorePointId -eq $PublishObject.RestorePointId -and
                                        $_.InstanceName   -match ":$($PublishObject.Port)" } |
                         Select-Object -First 1

        if (-not $targetPublish) {
            # Fallback: Match only by RestorePointId if port matching fails
            Write-Log "[PostgreSQL] Port-based match failed, falling back to RestorePointId match..." -Level "WARN"
            $targetPublish = Get-VEPSQLInstancePublish |
                             Where-Object { $_.RestorePointId -eq $PublishObject.RestorePointId } |
                             Select-Object -First 1
        }

        if ($targetPublish) {
            Write-Log "[PostgreSQL] Stopping publish job for instance: $($targetPublish.InstanceName)..."
            Stop-VEPSQLInstancePublish -InstancePublish $targetPublish -Force -ErrorAction Stop
            Write-Log "[PostgreSQL] Publish job stopped." -Level "SUCCESS"
        }
        else {
            Write-Log "[PostgreSQL] No matching publish job found to stop." -Level "WARN"
        }
    }
    catch {
        Write-Log "[PostgreSQL] Error stopping publish job: $_" -Level "WARN"
    }

    try {
        Write-Log "[PostgreSQL] Stopping restore session..."
        Stop-VEPSQLRestoreSession -Session $Session -ErrorAction Stop
        Write-Log "[PostgreSQL] Session stopped cleanly." -Level "SUCCESS"
    }
    catch {
        Write-Log "[PostgreSQL] Error stopping session: $_" -Level "ERROR"
    }
}

# ============================================================
# MONGODB FUNCTIONS
# ============================================================

function Start-MongoDBSession {
    param($RestorePoint)
    Write-Log "[MongoDB] Starting restore session..."
    try {
        $session = Start-VEMDBRestoreSession -RestorePoint $RestorePoint -ErrorAction Stop
        Write-Log "[MongoDB] Session started. ID: $($session.Id)" -Level "SUCCESS"
        return $session
    }
    catch {
        Write-Log "[MongoDB] Error starting session: $_" -Level "ERROR"
        exit 1
    }
}

function Publish-MongoDBInstance {
    param($Session, [string]$TargetServer, [string]$LinuxUser, [string]$LinuxPassword, [int]$Port)

    # Linux OS credentials with sudo elevation
    $securePassword = ConvertTo-SecureString $LinuxPassword -AsPlainText -Force
    $rootPassword   = ConvertTo-SecureString $LinuxPassword -AsPlainText -Force
    $creds          = New-VEMDBLinuxCredentials `
                        -Account              $LinuxUser `
                        -Password             $securePassword `
                        -ElevateAccountToRoot `
                        -RootPassword         $rootPassword `
                        -ErrorAction Stop

    Write-Log "[MongoDB] Publishing instance..."
    Write-Log "  Target Server        : $TargetServer"
    Write-Log "  Publish Instance Port: $Port"
    Write-Log "  Restore Instance Port: $Port"

    try {
        $publish = Start-VEMDBPublishJob `
            -Session              $Session `
            -Credential           $creds `
            -PublishInstancePort  $Port `
            -RestoreInstancePort  $Port `
            -ErrorAction Stop

        Write-Log "[MongoDB] Instance published. Target port: $Port." -Level "SUCCESS"

        # Wait for the instance to fully come online before running connectivity test
        Write-Log "[MongoDB] Waiting 30 seconds for instance to come online..."
        Start-Sleep -Seconds 30

        return $publish
    }
    catch {
        Write-Log "[MongoDB] Error publishing instance: $_" -Level "ERROR"
        exit 1
    }
}

function Test-MongoDBConnectivity {
    param([string]$Server, [int]$Port)

    $maxAttempts = 20   # 20 x 15s = max 5 minutes
    $attempt     = 0

    Write-Log "[MongoDB] Starting connectivity test (mongosh ping) on [$Server]:$Port..."

    while ($attempt -lt $maxAttempts) {
        $attempt++

        $mongosh = Get-Command mongosh.exe -ErrorAction SilentlyContinue
        if ($mongosh) {
            try {
                $output = & mongosh.exe --host $Server --port $Port --eval "db.runCommand({ping:1})" 2>&1
                if ($LASTEXITCODE -eq 0 -and $output -match 'ok\s*:\s*1') {
                    Write-Log "[MongoDB] Connectivity test passed (mongosh ping ok)." -Level "SUCCESS"
                    return $true
                }
                Write-Log "[MongoDB] Attempt $attempt/$maxAttempts -- mongosh output: $output" -Level "WARN"
            }
            catch {
                Write-Log "[MongoDB] Attempt $attempt/$maxAttempts -- mongosh error: $_" -Level "WARN"
            }
        }
        else {
            # Fallback: TCP port test if mongosh is not available
            Write-Log "[MongoDB] mongosh.exe not found -- falling back to TCP port test..." -Level "WARN"
            try {
                $tcp = New-Object System.Net.Sockets.TcpClient
                $tcp.Connect($Server, $Port)
                $tcp.Close()
                Write-Log "[MongoDB] Connectivity test passed (TCP port $Port reachable)." -Level "SUCCESS"
                return $true
            }
            catch {
                Write-Log "[MongoDB] Attempt $attempt/$maxAttempts -- TCP port $Port not yet reachable: $_" -Level "WARN"
            }
        }

        if ($attempt -lt $maxAttempts) {
            Write-Log "Retrying in 15 seconds..."
            Start-Sleep -Seconds 15
        }
    }

    Write-Log "[MongoDB] Connectivity test failed after $maxAttempts attempts." -Level "ERROR"
    return $false
}

function Stop-MongoDBPublish {
    param($Session, $PublishObject)

    try {
        Write-Log "[MongoDB] Looking up active publish job to stop..."
        $targetPublish = Get-VEMDBPublishJob |
                         Where-Object { $_.JobId -eq $PublishObject.JobId } |
                         Select-Object -First 1

        if ($targetPublish) {
            Write-Log "[MongoDB] Stopping publish job. Source: $($targetPublish.SourceInstance), Port: $($targetPublish.TargetPort)..."
            Stop-VEMDBPublishJob -PublishJob $targetPublish -Force -ErrorAction Stop
            Write-Log "[MongoDB] Publish job stopped." -Level "SUCCESS"
        }
        else {
            Write-Log "[MongoDB] No matching publish job found to stop." -Level "WARN"
        }
    }
    catch {
        Write-Log "[MongoDB] Error stopping publish job: $_" -Level "WARN"
    }

    try {
        Write-Log "[MongoDB] Stopping restore session..."
        Stop-VEMDBRestoreSession -Session $Session -ErrorAction Stop
        Write-Log "[MongoDB] Session stopped cleanly." -Level "SUCCESS"
    }
    catch {
        Write-Log "[MongoDB] Error stopping session: $_" -Level "ERROR"
    }
}

# ============================================================
# MAIN / Let the magic happen / YAMT
# ============================================================

Write-Log "======================================================="
Write-Log " Veeam DB Publish - Start"
Write-Log "======================================================="
Write-Log "Parameters:"
Write-Log "  VM Name         : $VMName"
Write-Log "  DB Name         : $DBName"
Write-Log "  DB Type         : $DBType"
Write-Log "  Destination Srv : $DestSrv"
Write-Log "  Timeout         : $TimeoutMinutes minute(s)"

if ($DBType -eq "MSSQL") {
    # cred-mssql.xml is only for SQL Server Logins (not Windows accounts).
    # If present, SQL Auth is used. Otherwise Windows Auth is used automatically.
    $mssqlCred = Get-CredentialFromManager -Target "mssql"
    if ($mssqlCred) {
        $DBUser     = $mssqlCred.UserName
        $DBPassword = $mssqlCred.GetNetworkCredential().Password
        Write-Log "MSSQL: cred-mssql.xml found -- using SQL Authentication (User: $DBUser)" -Level "INFO"
    }
    else {
        # Clear DBUser/DBPassword so Windows Auth is used
        $DBUser     = ""
        $DBPassword = ""
        Write-Log "MSSQL: no cred-mssql.xml found -- using Windows Authentication." -Level "INFO"
    }
}

if ($DBType -eq "PostgreSQL" -or $DBType -eq "MongoDB") {
    if (-not $LinuxPassword -or $LinuxPassword -eq "PASS") {
        $linuxCred = Get-CredentialFromManager -Target "linux"
        if ($linuxCred) {
            $LinuxUser     = $linuxCred.UserName
            $LinuxPassword = $linuxCred.GetNetworkCredential().Password
        }
        else {
            Write-Log "LinuxPassword not supplied and not found in Credential Manager (file: 'cred-linux.xml')." -Level "ERROR"
            exit 1
        }
    }
}

if ($DBType -eq "PostgreSQL") {
    if (-not $DBPassword -or $DBPassword -eq "PASS") {
        $pgCred = Get-CredentialFromManager -Target "postgresql"
        if ($pgCred) {
            $DBUser     = $pgCred.UserName
            $DBPassword = $pgCred.GetNetworkCredential().Password
        }
        else {
            Write-Log "DBPassword not supplied and not found in Credential Manager (file: 'cred-postgresql.xml')." -Level "ERROR"
            exit 1
        }
    }
}

if ($DBType -eq "MongoDB" -and $QueryFile) {
    if (-not $DBPassword -or $DBPassword -eq "PASS") {
        $mongoCred = Get-CredentialFromManager -Target "mongodb"
        if ($mongoCred) {
            $DBUser     = $mongoCred.UserName
            $DBPassword = $mongoCred.GetNetworkCredential().Password
        }
        else {
            Write-Log "DBPassword not supplied and not found in Credential Manager (file: 'cred-mongodb.xml'). Required for MongoDB security queries." -Level "ERROR"
            exit 1
        }
    }
}

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
$restorePoint = Get-LatestRestorePoint -Name $VMName -Type $DBType -ReplicaSet $ReplicaSet

# Engine-specific: session -> publish -> connectivity test -> cleanup
switch ($DBType) {

    "MSSQL" {
        $session   = Start-MSSQLSession -RestorePoint $restorePoint
        $restoreDb = Get-MSSQLDatabase  -Session $session -DatabaseName $DBName
        $publish   = Publish-MSSQLDatabase `
                        -Database     $restoreDb `
                        -SourceDBName $DBName `
                        -TargetServer $DestSrv `
                        -User         $DBUser `
                        -Password     $DBPassword

        $testPassed = Test-MSSQLConnectivity -Server $DestSrv -Database "${DBName}_temp" -User $DBUser -Password $DBPassword
    }

    "PostgreSQL" {
        $session  = Start-PostgreSQLSession -RestorePoint $restorePoint
        $instance = Get-PostgreSQLInstance  -Session $session
        $publish  = Publish-PostgreSQLInstance `
                        -Instance      $instance `
                        -TargetServer  $DestSrv `
                        -LinuxUser     $LinuxUser `
                        -LinuxPassword $LinuxPassword `
                        -Port          $DBPort

        $testPassed = Test-PostgreSQLConnectivity `
                        -Server   $DestSrv `
                        -Database $DBName `
                        -User     $DBUser `
                        -Password $DBPassword `
                        -Port     $DBPort
    }

    "MongoDB" {
        $session  = Start-MongoDBSession -RestorePoint $restorePoint
        $publish  = Publish-MongoDBInstance `
                        -Session       $session `
                        -TargetServer  $DestSrv `
                        -LinuxUser     $LinuxUser `
                        -LinuxPassword $LinuxPassword `
                        -Port          $DBPort

        $testPassed = Test-MongoDBConnectivity -Server $DestSrv -Port $DBPort
    }
}

# Handle connectivity result
if (-not $testPassed) {
    Write-Log "Connectivity test failed -- initiating immediate cleanup." -Level "WARN"
    Wait-AndCleanup -Type $DBType -Session $session -PublishObject $publish -Minutes 0
    exit 1
}

# Run security queries if a query file was provided
Invoke-SecurityQueries `
    -QueryFilePath $QueryFile `
    -Type          $DBType `
    -Server        $DestSrv `
    -Database      $DBName `
    -DBUser        $DBUser `
    -DBPassword    $DBPassword `
    -Port          $DBPort

# Wait for configured timeout, then clean up
Wait-AndCleanup -Type $DBType -Session $session -PublishObject $publish -Minutes $TimeoutMinutes

# Disconnect from VBR Server
try {
    Disconnect-VBRServer -ErrorAction Stop
    Write-Log "Disconnected from VBR Server: $VBRServer" -Level "SUCCESS"
}
catch {
    Write-Log "Failed to disconnect from VBR Server: $_" -Level "WARN"
}

Write-Log "======================================================="
Write-Log " Veeam DB Publish - Completed" -Level "SUCCESS"
Write-Log "=======================================================" 
