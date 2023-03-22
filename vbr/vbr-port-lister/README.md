# VBR Port Lister

## Description
~~~~
Version : 1.0 (March 20th 2023)
Requires: Powershell
Author  : Stephan "Steve" Herzig
GitHub  : https://www.github.com/yetanothermightytool
~~~~


## Purpose

This script helps to quickly visualize the required ports that need to be opened for communication between Veeam components.

## Parameters
  
  `ServicesFile`
_(mandatory)_ Name of the File Share Backup Job

  `Source`
_(mandatory)_ Name of the File Share Backup Job

  `Destination`
_(optional)_ Name of the File Share Backup Job

Valid Source or Destination Roles are:

"VBR Server"
"VBR Console"
"Windows Proxy"
"Windows Repository"
"Linux Proxy"
"Linux Repository"
"Gateway Server"

More can be found in the specific .txt file

## Example: 

List all ports needed for the VBR Console.

`PS>.\vbr-port-lister.ps1 -ServicesFile .\services.txt -Source "VBR Console"
  
## Notes

Download the .txt files. They contain the firewall information. Currently the following files are available:

services.txt  - Veeam Backup & Replication 
agent.txt	  - Veeam Agents
explorers.txt - Veeam Explorers

Please provide feedback, if this separation makes sense.

**Please note this script is unofficial and is not created nor supported by Veeam Software.**

## Version History

* 1.0
    * Initial Release
	
