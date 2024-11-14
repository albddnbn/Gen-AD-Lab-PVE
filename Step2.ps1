## AD Home/Test Lab Setup Scripts - Step 2
## Step 2 installs AD-Domain-Services feature.
## Author: Alex B.
## https://github.com/albddnbn/powershellnexusone
param(
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [Parameter(Mandatory = $false)]
    $config_ps1_filename = "config.ps1"
)
$host.ui.RawUI.WindowTitle = "Step 2"
## Dot source configuration variables from config.ps1:
try {
    $config_ps1 = Get-ChildItem -Path './config' -Filter "$config_ps1_filename" -File -ErrorAction Stop
    Write-Host "Found $($config_ps1.fullname), dot-sourcing configuration variables.."
    . "$($config_ps1.fullname)"

}
catch {
    Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Error reading searching for / dot sourcing config ps1, exiting script." -ForegroundColor Red
    Read-Host "Press enter to exit.."
    Return 1
}
## Scheduled Task Creation/Deletion:
$step3_filepath = (get-item ./step3.ps1).fullname
. ./config/create_scheduled_task.ps1 -task_name 'step3_genadlab' -task_file_path "$step3_filepath"

Get-ScheduledTask | ? { $_.TasKName -like "step2*adlab" } | Unregister-ScheduledTask -Confirm:$false

## Variables from json file:
$DOMAIN_NAME = $DOMAIN_CONFIG.Name
$DC_PASSWORD = ConvertTo-SecureString $DOMAIN_CONFIG.Password -AsPlainText -Force

## List the variables created above with get0-date timestampe
# Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Variables created from $($config_json):"
Write-Host "DOMAIN_NAME:        $DOMAIN_NAME"
Write-Host "DC_PASSWORD:        ...."

Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Installing AD DS.."

## Install AD DS
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Creating new AD DS Forest.."
Install-ADDSForest -DomainName $DOMAIN_NAME -DomainMode WinThreshold -ForestMode WinThreshold `
    -InstallDns -SafeModeAdministratorPassword $DC_PASSWORD -Force -Confirm:$false

Write-Host "If system hasn't already rebooted, please press enter to reboot now." -Foregroundcolor Yellow
read-host "Press enter to reboot.."
Restart-Computer