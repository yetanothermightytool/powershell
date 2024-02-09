# Automating Tape Verification in Veeam Backup & Replication

## Version Information
~~~~
Version: 1.0 (February 9th 2024)
Requires: Veeam Backup & Replication v12 or later
Author: Stephan "Steve" Herzig
~~~~

## Overview

This script automates the process of verifying tape backups in Veeam Backup & Replication. It checks the verification status of tapes at specified intervals and initiates verification for tapes that haven't been verified within the defined timeframe.

## Parameters

- **MediaPool**: Specifies the media pool from which tapes will be selected for verification. (Mandatory)
- **NumberofTapes**: Determines the number of tapes to verify in each execution. (Optional) - Default 1
- **CheckInterval**: Sets the interval, in days, for verifying tapes. (Optional) - Default 270

## Example

```powershell
.\vbr-tape-verification.ps1 -MediaPool "Standard Media Pool 01" -NumberofTapes 2
```

## Notes
Tested with Veeam Backup & Replication v12.1. 

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History

*  1.0
    * Initial Release
