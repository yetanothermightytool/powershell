# Restore Latest VMDK Files from VM

## Overview

This PowerShell script connects to a Veeam Backup & Replication server and restores the latest `.vmdk` files from a specified virtual machine to a chosen destination server and path.

## Parameters

**hostname**  
Name of the VM to search for.

**destinationserver**  
Name of the destination server for restore. This server needs to be registered within Veeam Backup & Replication.

**destinationpath**  
Path on the destination server where files will be restored.  
The destination path must have enough free space available and should not be located on the C: drive.


## Usage Example

```powershell
.\vbr-restore-vm-files.ps1 -hostname "MyVM" -destinationserver "TargetServer" -destinationpath "D:\RestoredVMDKs"
```

## Notes

- The script runs the restore operation in the background (`-RunAsync`).

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version Information
~~~~
Version: 1.0 (August 31 2025 🎃)
Author: Stephan "Steve" Herzig
~~~~


## Version History
*  1.0
    * Initial Release
 
