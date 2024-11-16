# Veeam Data Platform Content Pack for Graylog

This Graylog content package extracts and visualizes Veeam Data Platform syslog data.

## Version Information
~~~~
Version: 1.0 (November 16th 2024)
Author: Stephan "Steve" Herzig
~~~~

## Description

This content pack lets you monitor various security-related activities in your Veeam Backup infrastructure. The Veeam Security Dashboard visualizes security-relevant Syslog messages from Veeam Backup & Replication. The content pack contains:

- The Veeam Security Dashboard
- Graylog TCP Sslog Input with configured extractors
- A Pipeline with assigned Pipeline Rules for assigning the criticality to the ingested data
- A dedicated Stream with the Pipeline assigned

The Input type is Syslog TCP, and the TCP port can be configured during the installation of this content pack. The following parameters are extracted from the Syslog data by the input extractor:

- `-vbr_instanceId`: The ID of the event
- `-vbr_VbrHostName`: The hostname of the Veeam Backup & Replication Server
- `-vbr_VbrVersion`: The installed Veeam Backup & Replication version
- `-vbr_JobResult`: The Job Result ID (Success/Warning/Failed)
- `-vbr_JobType`: The Job Type
- `-vbr_Description`: Data in the Syslog Description field

This allows further data to be evaluated. The configured Stream Rule lets all syslog data that matches the application_name Veeam_MP set to go through. The specified Index Set for the Veeam Stream is configured to the Default index set. This might be adjusted.


## Notes
This content pack has been tested with the following product versions:

**Please note that this Graylog content pack is community driven and is not created nor supported by Veeam Software.**

## Version History

* 1.0
    * Initial Release
