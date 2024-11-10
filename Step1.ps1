## AD Home/Test Lab Setup Scripts - Step 1
## Step 1 configures basic settings on the computer including: Hostname, static IP address, gateway, DNS servers, and 
## enabling network discovery and file/printer sharing firewall rules.
## Before trying to set network adapter settings - the script does a quick check for a virtio driver installer and attempts
## to install it if found. This enables the computer to 'see' the VirtIO network adapters.
## Author: Alex B.
param(
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [Parameter(Mandatory = $false)]
    $config_ps1_filename = "config.ps1"
)
$host.ui.RawUI.WindowTitle = "Step 1"

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

## Create scheduled task for next step and remove any previous step's scheduled task:
$step2_filepath = (get-item ./step2.ps1).fullname
. ./config/create_scheduled_task.ps1 -task_name 'step2_genadlab' -task_file_path "$step2_filepath"

## Variables from json file:
## Domain Controller (static IP settings, hostname..)
$STATIC_IP_ADDR = $DOMAIN_CONFIG.DC_IP
$DC_DNS_SETTINGS = $DOMAIN_CONFIG.DNS_Servers
$GATEWAY_IP_ADDR = $DOMAIN_CONFIG.Gateway
$SUBNET_PREFIX = $DOMAIN_CONFIG.subnet_prefix
$DC_HOSTNAME = $DOMAIN_CONFIG.DC_hostname

Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Variables created from $($config_json):"
Write-Host "DC_HOSTNAME:     $DC_HOSTNAME"
Write-Host "STATIC_IP_ADDR:  $STATIC_IP_ADDR"
Write-Host "DC_DNS_SETTINGS: $DC_DNS_SETTINGS"
Write-Host "GATEWAY_IP_ADDR: $GATEWAY_IP_ADDR"
Write-Host "SUBNET_PREFIX:   $SUBNET_PREFIX`n"

# Renaming the computer
Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Renaming computer to $DC_HOSTNAME.."
Rename-Computer -NewName $DC_HOSTNAME -Force

## Check for virtio 64-bit Windows driver installer MSI file by cycling through base of connected drives.
$drives = Get-PSDrive -PSProvider FileSystem
foreach ($drive in $drives) {
    $file = Get-ChildItem -Path $drive.Root -Filter "virtio-win-gt-x64.msi" -File -ErrorAction SilentlyContinue

    ## VirtIO Driver MSI Installation:
    if ($file) {
        Write-Output "Found file: $($file.FullName), running installation."
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/i $($file.FullName) /qn /norestart" -Wait
    }

    ## QEMU Guest Agent Installation using VirtIO MSI
    $qemu_installer = Get-ChildItem -Path $(Join-path $drive.Root 'guest-agent') -Filter "qemu-ga-x86_64.msi" -File -ErrorAction SilentlyContinue
    # If/once virtio msi is found - attempt to install silently and discontinue the searching of drives.
    if ($qemu_installer) {
        Write-Output "Found file: $($qemu_installer.FullName), running installation."
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/i $($qemu_installer.FullName) /qn /norestart" -Wait
        break
    }

    ## Code shouldn't inside here - if virtio iso is there, both files should be there.
    if ($file) { break; }
}

## Ensure Network Adapter is in 'Up' status after VirtIO driver installation.
$active_net_adapter = Get-NetAdapter | ? { $_.Status -Eq 'Up' }
if (-not $active_net_adapter) {
    Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: " -NoNewline
    Write-Host "No active network adapter found, exiting script." -ForegroundColor Red
    Read-Host "Press enter to exit.."
    Return 1
}

Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Network adapter found: $($active_net_adapter.Name)."
Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Setting static IP address, gateway, and DNS servers.."
Write-Host "IP Address:    $STATIC_IP_ADDR"
Write-Host "Gateway:       $GATEWAY_IP_ADDR"
Write-Host "DNS Servers:   $DC_DNS_SETTINGS"
Write-Host "Subnet Prefix: $SUBNET_PREFIX`n"
New-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $active_net_adapter.ifIndex `
    -IPAddress $STATIC_IP_ADDR -PrefixLength $SUBNET_PREFIX `
    -DefaultGateway $GATEWAY_IP_ADDR

Set-DNSClientServerAddress -InterfaceIndex $active_net_adapter.ifIndex `
    -ServerAddresses $DC_DNS_SETTINGS

## Enable network discovery and file/printer sharing (firewall rules):
Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Enabling Network Discovery and File/Printer Sharing.."
ForEach ($rulegroup in @("Network Discovery", "File and Printer Sharing")) {
    Enable-NetFirewallRule -DisplayGroup $rulegroup | Out-Null
}

Start-Sleep -Seconds 5

## Until the kinks are worked out of the scheduled task method, or better method found:
Write-Host "`r`nAfter the machine reboots, log back in to start Step2.ps1 as a scheduled task." -Foregroundcolor Yellow
Read-Host "Press enter to reboot and apply changes." 
Restart-Computer
