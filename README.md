# Gen-AD-Lab-PVE

![Powershell](https://img.shields.io/badge/language-Powershell-0078D4) ![Bash](https://img.shields.io/badge/Bash-05c100)

A series of Powershell scripts that can be used to generate an Active Directory Lab environment.
This series was created to be used with **Proxmox Virtual Environment**, but my goal is for the scripts to work in other environments as well.

_For example: Step 1 checks for a drive containing the VirtIO iso to install necessary drivers for Proxmox VMs, and Step 3 creates a folder in the MDT Deployment Share specific to %Make% of Proxmox VMs ('QEMU')._

## Table of Contents

- [Introduction](#introduction)
- [Features](#features)
- [Usage](#usage)
- [Scripts](#scripts)
- [Resources](#resources)
- [Issues](#issues)
- [License](#license)

## Introduction

If you are using Proxmox Virtual Environment, [new_dc_vm.sh](https://github.com/albddnbn/proxmox-ve-utility-scripts/blob/main/new_dc_vm.sh) can help create a new VM to run these scripts on, as Domain Controller.

Step 1 is used to configure network settings and install drivers.
Step 2 is used to install Active Directory Domain Services and configure the Domain Controller.
Step 3 is used to install DHCP Server, create OUs, Groups, Users, configure fileshares, and MDT.

This project is a collection of bash and PowerShell scripts that can be used to generate an Active Directory lab in Proxmox.
The new_vm.sh bash script can be used first to generate a Domain Controller VM and corresponding virtual network elements.
The Step1.ps1 Powershell script is used afterwards, to configure basic elements of an Active Directory Domain Controller. Step1.ps1 creates a scheduled task for Step2.ps1 which is run after reboot/login. Step2.ps1 creates the same type of scheduled task to execute Step3.ps1.

**MDT Deployment/Driver situation**: Step3 will search for a mounted virtio iso to import VirtIO drivers, and attempt to download VMWare tools iso for VMWare Storage/SCSI Driver so that the deployment should work with several different types of 'hardware' available through Proxmox. Intel/Virtio NICs, and VMWare/Virtio SCSI controllers.

## Features

- Create a Domain Controller VM in Proxmox
- Create a virtual network in Proxmox
- Configure DNS, DHCP, AD DS, and file shares on the Domain Controller VM
- Generate Active Directory OU/Group/User objects using values from ./config directory

## Usage

### Generating a Basic AD Lab Environment

In this example, a domain/network will be generated using the default settings from both **config.ps1**, and **new_dc_vm.sh**.

### 1. Run **new_dc_vm.sh**, specify VM settings, select isos:

<table>
    <tr>
        <td>
        <img src="img\1-new-dc-vm.png">
        </td>
        <td>
        <img src="img\2-vm-settings.png">
        </td>
    </tr>
</table>

### 2. Optionally create virtual network and firewall aliases:

<table>
    <tr>
        <td>
        <img src="img\3-zone-settings.png">
        </td>
        <td>
        <img src="img\4-firewall-aliases.png">
        </td>
    </tr>
</table>

> [!NOTE]
> VMs created using this script prompt for many values, but some settings are explicitly hard-coded based on recommendations from various articles, like this one: [https://davejansen.com/recommended-settings-windows-10-2016-2018-2019-vm-proxmox/](https://davejansen.com/recommended-settings-windows-10-2016-2018-2019-vm-proxmox/)

_Use VirtIO storage drivers during Windows Server installation._

<img src="img\011-load-virtio-drivers-for-server-install.png" style="max-width: 750px;">

### 3. After installing Windows Server OS, run **Step1.ps1** on the DC VM to start the process.

Network-related values in the configuration file should **correspond to any network values set during VM creation**.

In this example, the top of config.ps1 would look something like this:

```powershell
## Domain configuration:
$DOMAIN_CONFIG = [PSCustomObject]@{
    Name          = 'lab.edu'
    Netbios       = 'lab'
    DC_Hostname   = 'test-dc-vm-1'
    DC_IP         = '10.0.1.2'
    DNS_Servers   = @('10.0.1.2', '8.8.8.8')
    Gateway       = '10.0.1.1'
    Subnet_Prefix = '24'
    Password      = 'Somepass1'
}
## DHCP server and scope configuration:
$DHCP_SERVER_CONFIG = [PSCustomObject]@{
    IP_Addr = $DOMAIN_CONFIG.DC_IP
    Scope   = [PSCustomObject]@{
        Name          = 'A Domain DHCP Scope'
        Start         = '10.0.1.10'
        End           = '10.0.1.240'
        Gateway       = $DOMAIN_CONFIG.Gateway
        Subnet_Prefix = '255.255.255.0'
        DNS_Servers   = $DOMAIN_CONFIG.DNS_Servers
    }
}
```

Steps 2 and 3 will run automatically as **scheduled tasks** after reboot/logins.

**It may be good idea to copy the script folder to the base of your C:\ to ensure enough disk space for MDT-related downloads.**

_**\*Some interaction required for MDT Setup in Step 3.**_

## Scripts

#### Step 1 / Step1.ps1:

- Sets hostname, static IP address / related network settings
- Searches available drives to find attached VirtIO iso and install drivers from: [https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/?C=M;O=D](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/?C=M;O=D)

#### Step 2 / Step2.ps1:

- Installs AD DS with DNS server
- Configures AD DS Forest / Domain Controller

#### Step 3 / Step3.ps1:

- Installs and configures DHCP Server with single DHCP scope
- Creates AD DS OUs, Groups, Users
- Creates file shares that can be used for roaming profiles/folder redirection and configures permissions
- Installs/configures MDT Server and dependencies
- Adds steps to W10-22H2 x64 Task Sequence to install applications and configure settings
- Imports VirtIO/VMWare drivers into Deployment Share

## Resources

### MDT-Setup

[https://gal.vin/utils/mdt-setup](https://gal.vin/utils/mdt-setup)

### Format-XML

[https://devblogs.microsoft.com/powershell/format-xml/](https://devblogs.microsoft.com/powershell/format-xml/)

### Manage_Application_Bundle

[https://github.com/damienvanrobaeys/Manage_MDT_Application_Bundle](https://github.com/damienvanrobaeys/Manage_MDT_Application_Bundle)

## Issues

1. Current work-around for MDT Monitoring is to **disable, then re-enable through GUI**.

2. If you run into an error during Step 3 when script tries to run Windows Media Creation Tool, **re-run Step3.ps1**.

## License

This project is licensed under the GNU General Public License v2.0. You may obtain a copy of the License at

[https://www.gnu.org/licenses/gpl-2.0.en.html](https://www.gnu.org/licenses/gpl-2.0.en.html)

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
