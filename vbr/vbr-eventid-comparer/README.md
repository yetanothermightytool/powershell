# VBR Event ID Comparer

## Version Information
~~~~
Version: 1.0 (April 8 2025)
Author: Stephan "Steve" Herzig
~~~~
## Purpose
The Veeam Backup & Replication Event Reference now contains the [Event Changelog](https://helpcenter.veeam.com/docs/backup/events/event_changelog.html). The page lists Veeam Backup & Replication events for all product versions starting from version 12.1.1. The data is stored in the JSON format. This helps to identify newly introduced or updated events. This PowerShell script compares two event definition files and shows what is added, removed, modified, or newly introduced (like new data fields such as VbrHostName). Before running the script, store the content of the changelog pages locally in separate JSON files.

## Parameters
The script uses the following parameters:

- `File1`    : Path to the first event definition JSON file.
- `File2`    : Path to the first event definition JSON file.

## Note
**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History
*  1.0
    * Initial Release	
