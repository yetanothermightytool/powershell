
# Veeam DB Publish

PowerShell script for publishing databases from Veeam backups using Veeam Explorer.  
Supports **Microsoft SQL Server**, **PostgreSQL** and **MongoDB**.

## Description
~~~~
Version : 1.0 (March 10th 2026)
Requires: Veeam Backup & Replication v13
Author  : Stephan "Steve" Herzig
~~~~
## Purpose 

Veeam DB Publish (vbr-db-publish.ps1) is a PowerShell script that automates publishing databases from Veeam backups for verification and security analysis. It supports Microsoft SQL Server, PostgreSQL, and MongoDB.

The script connects to a Veeam Backup & Replication server, retrieves the latest restore point for a given VM, and publishes the database to a destination server. After publishing it runs a connectivity test to confirm the instance is reachable. Optionally, it executes a set of configurable security queries against the published instance (for example, to detect privileged accounts). Once the configured timeout expires, the publish is cleanly torn down, and the restore session is stopped.

The intended use case is automated backup verification combined with lightweight security scanning, without any permanent changes to the source or destination environment.

---

## Prerequisites

- Veeam Backup & Replication with Veeam Explorer for the relevant DB engine
- PowerShell v7
- Script must run on the VBR server or a machine with the Veeam Console installed
- **PostgreSQL:** `psql.exe` must be available in `PATH`
- **MongoDB:** `mongosh.exe` must be available in `PATH` (falls back to TCP port check if not found)
- The destination server must have the configured port open in the firewall to allow inbound connections to the published database instance.

---

## Parameters

| Parameter | Mandatory | Default | Description |
|---|---|---|---|
| `-VBRServer` | No | `localhost` | Veeam Backup & Replication server to connect to |
| `-VMName` | Yes | — | Name of the VM / backup job in Veeam |
| `-DBName` | Yes | — | Name of the source database or instance |
| `-DestSrv` | Yes | — | Destination server where the DB will be published |
| `-DBType` | No | `MSSQL` | Database engine: `MSSQL`, `PostgreSQL`, `MongoDB` |
| `-DBUser` | No | `postgreadmin` | DB username for connectivity test (PostgreSQL) and security queries (MongoDB) |
| `-DBPassword` | No | — | Password for `-DBUser` |
| `-LinuxUser` | No | `administrator` | Linux OS username for SSH access (PostgreSQL / MongoDB) |
| `-LinuxPassword` | No | — | Password for `-LinuxUser` |
| `-TimeoutMinutes` | No | `30` | Minutes the published DB stays available before auto-cleanup |
| `-DBPort` | No | `5433` | Port for the published instance (e. g. `5433` for PostgreSQL, `27018` for MongoDB) |
| `-ReplicaSet` | No | `rs0` | MongoDB Replica Set name — used to find the correct restore point |
| `-QueryFile` | No | — | Path to a JSON file containing security queries to run after publish |

### Notes on credentials

- **MSSQL:** Uses Windows Authentication — `-DBUser` and `-DBPassword` are not used for the connectivity test
- **PostgreSQL:** `-DBUser` and `-DBPassword` are used for the `psql` connectivity test and security queries
- **MongoDB:** `-DBUser` and `-DBPassword` are **required** when `-QueryFile` is specified (authenticated queries). Not required for the basic connectivity test (ping does not require auth)
- **Linux credentials** (`-LinuxUser` / `-LinuxPassword`): used by Veeam Explorer to mount and publish the instance on the target server — required for PostgreSQL and MongoDB

---

## Security Query File (`-QueryFile`)

An optional JSON file containing queries to run against the published instance after the connectivity test passes. Queries are organised per DB engine.

```json
{
  "MSSQL":      [ { "name": "...", "description": "...", "query": "..." } ],
  "PostgreSQL": [ { "name": "...", "description": "...", "query": "..." } ],
  "MongoDB":    [ { "name": "...", "description": "...", "query": "..." } ]
}
```

A ready-to-use example file is provided: **`Veeam-DBQueries.json`**

### Query safety filter

Before any query is executed, the script checks for dangerous keywords:

`DROP` `DELETE` `INSERT` `UPDATE` `CREATE` `TRUNCATE` `EXEC` `EXECUTE` `ALTER` `GRANT` `REVOKE` `SHUTDOWN` `KILL` `MERGE` `REPLACE`

Queries containing any of these keywords are blocked and logged as `[ERROR]`. The script continues with the next query.

---

## Examples

### Microsoft SQL Server
```powershell
.\vbr-db-publish.ps1 `
    -VMName  "SQLSRV01" `
    -DBName  "ProdDB" `
    -DestSrv "SQLSRV-TEST" `
    -DBType  MSSQL
```

### PostgreSQL
```powershell
.\vbr-db-publish.ps1 `
    -VMName        "PGSRV01" `
    -DBName        "mydb" `
    -DestSrv       "PGSRV-TEST" `
    -DBType        PostgreSQL ``
    -DBPort        5433
```

### MongoDB
```powershell
.\vbr-db-Publish.ps1 `
    -VMName        "MONGOSRV01" `
    -DBName        "mydb" `
    -DestSrv       "MONGOSRV-TEST" `
    -DBType        MongoDB `
    -DBPort        27018 `
    -ReplicaSet    "rs0"
```
---

## Credential Files

Instead of passing passwords on the command line, credentials can be stored in encrypted XML files in the same directory as the script. The script automatically loads them if no password parameter is supplied. Parameters always take precedence over stored credentials.

Encryption uses Windows DPAPI (the files can only be decrypted by the same user on the same machine).

### Setup (once per machine/user)

Run the following commands once. A password dialog will open for each:

```powershell
# Linux OS credentials (PostgreSQL + MongoDB)
Get-Credential -UserName "linuxuser" | Export-Clixml cred-linux.xml

# PostgreSQL DB credentials
Get-Credential -UserName "postgreadmin" | Export-Clixml cred-postgresql.xml

# MongoDB DB credentials (only needed when -QueryFile is used)
Get-Credential -UserName "mongodbadmin" | Export-Clixml cred-mongodb.xml

# MSSQL SQL Authentication (optional/if omitted, Windows Authentication is used)
Get-Credential -UserName "veeam_scan" | Export-Clixml cred-mssql.xml
```

### MSSQL Authentication

MSSQL supports two authentication modes:

**Windows Authentication (default)** -- used automatically when `cred-mssql.xml` is not present. The Windows account running the script must have access to the SQL Server. No credential file needed.

**SQL Authentication (optional)** -- used when `cred-mssql.xml` is present. Requires a dedicated SQL Server Login (not a Windows account). The SQL Login must exist on the server and have access to the published database.

Important: `cred-mssql.xml` is only used for the connectivity test and security queries. The Veeam publish step always uses Windows Authentication regardless.

### Precedence

If `-DBPassword` or `-LinuxPassword` is passed as a parameter, the credential file is not consulted. This allows overriding stored credentials for individual runs.

---

## Version History
- 1.0
  - Initial version

## Disclaimer

This script is not officially supported by Veeam Software. Use it at your own risk.

