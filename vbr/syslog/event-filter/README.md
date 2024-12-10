# VBR Generate Syslog Event Filter 

## Version Information
~~~~
Version: 1.0 (December 10th 2024)
Author: Stephan "Steve" Herzig
~~~~
## Purpose
This script creates an XML file based on the specified filter parameters, including event IDs, categories, and filter types.

The input CSV file event list is based on the Veeam Backup & Replication [Event Reference.](https://helpcenter.veeam.com/docs/backup/events/overview.html) The CSV file can be downloaded here
[here.](https://github.com/yetanothermightytool/powershell/blob/master/vbr/syslog/event-filter/event-id-list-dec24.csv) The created XML file can be imported as documented in the [Veeam Backup & Replication Help Center.](https://helpcenter.veeam.com/docs/backup/vsphere/syslog_servers_filtering_events.html#importing-event-ids).


## Parameters

The script uses the following parameters:

- `Category`   (Optional)  : Specify one or more categories (e.g., "Tape", "Backup"), or use "All" to include all events.
- `EventId`    (Optional)  : Specify one or more Event IDs to filter.
- `Filter`     (Mandatory) : Specify the filter Severity ("Info", "Warning", "Error") to apply.
- `InputCsv`   (Mandatory) : Path to the input CSV file.
- `OutputFile` (Mandatory) : Path to the output XML file.

> **Note:** You must specify at least `Category` or `EventId`. The categories can be adjusted within the CSV file.

## Examples

### Example 1: Filter by Categories
Filter events by "Backup" and "Restore" categories for "Info" messages:
```powershell
.\vbr-generate-syslog-event-filter.ps1 -Category "Backup","Restore" -Filter "Info" -InputCsv "events.csv" -OutputFile "output.xml"
```

### Example 2: Filter All Categories
Include all events from the CSV file and filter by "Info":
```powershell
.\vbr-generate-syslog-event-filter.ps1 -Category "All" -Filter "Info" -InputCsv "events.csv" -OutputFile "output.xml"
```

### Example 3: Filter by Event IDs
Filter events with Event IDs 110 and 310 for "Info" type:

```powershell
.\vbr-generate-syslog-event-filter.ps1 -EventId 110,310 -Filter "Info" -InputCsv "events.csv" -OutputFile "output.xml"
```

## Notes
This script has been tested with the following versions of Veeam Backup & Replication
- Veeam Backup & Replication v12.3

The categories in the CSV file are entered to the best of my knowledge and belief and might be adjusted in the future.

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History
*  1.0
    * Initial Release	
