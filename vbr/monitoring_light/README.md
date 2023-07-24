# VBR - Monitoring Light - PowerShell Web Server

This PowerShell script sets up a simple HTTP server that listens on a specified port and provides a web page with various statistics related to Veeam Backup & Replication.

## Version Information
~~~~
Version: 1.0 (July 24th 2023)
Requires: Veeam Backup & Replication v12 / Scanning Tools downloaded (see Prerequisites)
Author: Stephan "Steve" Herzig
GitHub: [https://www.github.com/yetanothermightytool](https://www.github.com/yetanothermightytool)
~~~~

## Prerequisites

Before running the `monitoring_light.ps1` script, make sure to download the [job-stats.ps1](https://github.com/yetanothermightytool/powershell/blob/master/vbr/monitoring_light/job-stats.ps1) and [rts-extractor.ps1](https://github.com/yetanothermightytool/powershell/blob/master/vbr/monitoring_light/rts-extractor.ps1) and save them in the same directory where the `monitoring_light.ps1` script is located.

## Usage

```powershell
.\VBR-Quick-Analyzer.ps1 -Port 80 -RefreshInterval 30
```

Open a web browser and Access the URL http://localhost:<port> in the web browser, where <port> is the port number specified when running the script (e.g., http://localhost:80).

## Parameters

- `-Port`: The port number on which the web server will listen for incoming requests. The default value is `80`.
- `-RefreshInterval`: The time interval (in seconds) at which the web page will be automatically refreshed. The default value is `30` seconds.

## Description

The information displayed on the webpage includes:

- Veeam Backup Server Version and Patch Information.
- Backup Job Statistics for the last 24 hours, including processed data size, change rate, and transferred data size.
- Running Activities of Veeam Proxies, such as the maximum and current concurrent jobs.
- Running Activities of Veeam Repositories, including maximum and current concurrent jobs, current concurrent tasks, free space, and immutability status.
- RTS.ResourcesUsage.log Entries for the last 24 hours, showing resource usage at different time intervals.

The page will refresh automatically based on the specified `$RefreshInterval` value.

## Note

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History

* 1.0
    * Initial Release
