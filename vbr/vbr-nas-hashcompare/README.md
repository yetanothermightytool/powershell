# NAS Share Hash Value Comparer

## Description
~~~~
Version : 1.0 (December 23 2022)
Requires: Veeam Backup & Replication v11 and later
Author  : Stephan "Steve" Herzig
GitHub  : https://www.github.com/yetanothermightytool
~~~~

## Prerequisites

A file share backup job protecting an SMB share needs to be configured and sucessfully executed.
The SHA-256 hash value of the file that will be compared with the file stored in the backup.

## Purpose

This script launches an Instant File Share Recovery for a specified file share backup job and compares the hash value using the given parameters.

The share access permissions can be adjusted in line 32.
The recovery reason can be adjusted in line 35.

## Parameters
  
  `JobName`
_(mandatory)_ Name of the File Share Backup Job

  `SourceHash`
_(mandatory)_ SHA-256 value of the source file

  `FileToCompare`
_(mandatory)_ the path and filename to be compared

## Example: 
`PS>.\vbr-nas-hashcompare.ps1  -JobName "Demo NAS to Local" -$SourceHash "0AEIOU" -$FileToCompare "\Folder1\Documents\textdoc01.txt
  
## Notes

This script has been tested with the following versions of Veeam Backup & Replication
- v11 latest
- v12 beta3

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History

* 1.0
    * Initial Release
