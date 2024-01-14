# Veeam Backup & Replication - Inline Scan Log Analysis

## Description
~~~~
Version : 1.0 (January 11th 2024)
Requires: Veeam Backup & Replication v12.1
Author  : Stephan "Steve" Herzig
~~~~

## Purpose 
One of the malware detection methos Veeam Backup & Replication supports is the File Entropy Analysis or Inline Scan. If enabled Veeam Backup & Replication detects the following malware activity during a backup job:

- Encrypted files
- Onion links
- Ransom notes

If something is found the restore point will be marked as suspicous. [`More details can be found in the Helpcenter`](https://helpcenter.veeam.com/docs/backup/vsphere/malware_detection_data_blocks.html).

2 scripts are available for a quick analysis. One script reads the Svc.VeeamDataAnalyzer.log file containing entries related to the inline scan. The script displays which metrics were identified during the analysis in a tabular format.
The other script retrieves and formats specific Windows event log entries (Event-ID 41600) from the past 30 days. It extracts information such as the date, VM name and the associated rule.

## Version History
- 1.0
  - Initial version

## Disclaimer
This script is not officially supported by Veeam Software. Use it at your own risk.
