# Veeam Recovery Orchestrator HTML Report Generator

## Description

This PowerShell script retrieves data from the Veeam Recovery Orchestrator API and generates an HTML report. The report includes information about each entry in the API response, such as name, plan type, state, last test time, last test result, last check time, and last check result.

## Usage

```powershell
.\vro-get-planstatus.ps1 -ReportFilePath <path>\<reportname>.html
```

- `ReportFilePath`: Specifies the file path where the generated HTML report will be saved. (Mandatory)

## Customization

You need to customize the API endpoint. Additionally, you can adjust the Username (Lines 69 and 70 in the code)

```powershell
$vroAPI = "https://<yourip>:9898"
$cred = Get-Credential -UserName <youruser@yourdomain.tld> -Message "Please enter your VRO credentials"
```

You can also customize the script by modifying the HTML template to include additional columns or styling options for the report. 
