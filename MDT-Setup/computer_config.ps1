## Network Discovery / File-sharing firewall rules:
## Enable network discovery and file/printer sharing (firewall rules):
Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Enabling Network Discovery and File/Printer Sharing.."
ForEach ($rulegroup in @("Network Discovery", "File and Printer Sharing")) {
    Enable-NetFirewallRule -DisplayGroup $rulegroup | Out-Null
}

## Enable PS Remoting
Enable-PSRemoting -Force -SkipNetworkProfileCheck