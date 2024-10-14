## AD Home/Test Lab Setup Scripts - Step 3
## Step 3 Installs and configures DHCP server/settings. Then, creates OU structure and users.
## Author: Alex B.
## https://github.com/albddnbn/powershellnexusone
param(
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [Parameter(Mandatory = $false)]
    $config_ps1_filename = "config.ps1",
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [Parameter(Mandatory = $false)]
    [string]$user_creation_ps1_file = "create_user_population.ps1",
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [Parameter(Mandatory = $false)]
    [string]$fileshares_ps1_file = "create_fileshares.ps1"
)
#
$BaseDirectory = $PSScriptRoot


## Set Window Title to Step
$host.ui.RawUI.WindowTitle = "Step 3"

## Make sure user creation script can be accessed:
$user_creation_script = Get-ChildItem -Path './config' -Filter "$user_creation_ps1_file" -File -ErrorAction Stop
$fileshare_creation_script = Get-ChildItem -Path './config' -Filter "$fileshares_ps1_file" -File -ErrorAction Stop
# $run_mdt_setup = Get-ChildItem -Path '.' -Filter "mdtsetup.ps1" -File -ErrorAction SilentlyContinue

## Dot source configuration variables:
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

Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Creating variables from $configjson JSON file."

## Variables from json file: 
$DOMAIN_NAME = (Get-ADDomain).DNSRoot
$DOMAIN_PATH = (Get-ADDomain).DistinguishedName

$DC_HOSTNAME = (Get-ADDomainController).HostName

## DHCP server variables:
$DHCP_IP_ADDR = $DHCP_SERVER_CONFIG.IP_Addr
$DHCP_SCOPE_NAME = $DHCP_SERVER_CONFIG.Scope.Name
$DHCP_START_RANGE = $DHCP_SERVER_CONFIG.Scope.Start
$DHCP_END_RANGE = $DHCP_SERVER_CONFIG.Scope.End
$DHCP_SUBNET_PREFIX = $DHCP_SERVER_CONFIG.Scope.subnet_prefix
$DHCP_GATEWAY = $DHCP_SERVER_CONFIG.Scope.gateway
$DHCP_DNS_SERVERS = $DHCP_SERVER_CONFIG.Scope.dns_servers


$BASE_OU = $USER_AND_GROUP_CONFIG.base_ou
## confirm base OU
Write-Host "Base OU is: " -nonewline
Write-Host "$BASE_OU" -foregroundcolor yellow
Write-Host "All users, groups, ous, etc. will be created inside this OU."
# $reply = Read-Host "Proceed? [y/n]"
# if ($reply.tolower() -eq 'y') {
#     $null
# }
# else {
#     Write-Host "Script execution terminating now due to incorrect base OU: $Base_OU."
#     Write-Host "You can change the base OU in the config.ps1 file (user_and_group_config variable)." -Foregroundcolor yellow
#     Read-Host "Press enter to end."
#     return 1
# }

##
## DHCP setup / configuration of single scope
##
Get-ScheduledTask -TaskName 'step3_genadlab' -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false


Install-WindowsFeature -Name DHCP -IncludeManagementTools

Restart-service dhcpserver

Add-DHCPServerInDC -DnsName "$DC_HOSTNAME" -IPAddress $DHCP_IP_ADDR

# DHCP Scope
Add-DHCPServerv4Scope -Name "$DHCP_SCOPE_NAME" -StartRange "$DHCP_START_RANGE" `
    -EndRange "$DHCP_END_RANGE" -SubnetMask $DHCP_SUBNET_PREFIX `
    -State Active

# Force specifies that the DNS server validation is skipped - since the current bash script has SNAT turned off for vnet.
Set-DHCPServerv4OptionValue -ComputerName "$DC_HOSTNAME" `
    -DnsServer $DHCP_DNS_SERVERS -DnsDomain "$DOMAIN_NAME" `
    -Router $DHCP_GATEWAY -Force

##
## OU and Group Creation
##

## Create BASE OU using value from config.ps1 (all new users / groups / ous will be created inside this OU for easy removal)
try {
    New-ADOrganizationalUnit -Name "$BASE_OU" -Path "$DOMAIN_PATH" -ProtectedFromAccidentalDeletion $false
    Write-Host "Created $BASE_OU OU."

    ## OUs/Groups created inside Base OU
    $base_ou_path = (Get-ADOrganizationalUnit -Filter "Name -eq '$base_ou'").DistinguishedName
}
catch {
    Write-Host "Something went wrong with creating $BASE_OU OU." -Foregroundcolor Red
    Write-Host "You can change the base OU in the config.ps1 file (user_and_group_config variable)." -Foregroundcolor yellow
    Read-Host "Press enter to end."
    return 1
}

## This will create an AD Group and OU for each listing in the user_and_group_config variable, except for the base_ou listing.
## By default - a group for regular users, IT admins, and computers is included.
ForEach ($listing in $($USER_AND_GROUP_CONFIG.GetEnumerator() | ? { $_.Name -ne 'base_ou' })) {
    ## Used for OU and Group Name
    $item_name = $listing.value.name
    ## Used for Group Description
    $item_description = $listing.value.description
    ## The group created is added to groups in memberof property
    $item_memberof = $listing.value.memberof
    try {
        New-ADOrganizationalUnit -Name $item_name -Path "$base_ou_path" -ProtectedFromAccidentalDeletion $false
        Write-Host "Created $item_name OU."

        $ou_path = (Get-ADOrganizationalUnit -Filter "Name -like '$item_name'").DistinguishedName

        New-ADGroup -Name $item_name -GroupCategory Security -GroupScope Global -Path "$ou_path" -Description "$item_description"

        Write-Host "Created group: $item_name."

        ForEach ($single_group in $item_memberof) {
            Add-ADGroupMember -Identity $single_group -Members $item_name
            Write-Host "Added $item_name to $single_group."
        }
    }
    catch {
        Write-Host "Something went wrong with creating $item_name OU/Groups." -Foregroundcolor Red
    }
}

##
## AD User / Admin user creation
## All users in the IT department receive an _admin account.


## Create users using users.csv\
Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Beginning user creation."

Powershell.exe -ExecutionPolicy Bypass "$($user_creation_script.fullname)"


## Create file shares
Powershell.exe -ExecutionPolicy Bypass "$($fileshare_creation_script.fullname)"

## Install applications from the deploy folder on DC:
$foldernames = Get-ChildItem -path 'deploy' -Directory -ErrorAction SilentlyContinue | Select -Exp Fullname
$foldernames | % {
    try {
        ## Set Location to folder
        Set-Location "$_"

        Powershell.exe -ExecutionPolicy Bypass "./Deploy-$_.ps1" -Deploymenttype 'Install' -Deploymode 'Silent'
    }
    catch {
        Write-Host "Something went wrong with installing applications from $_." -Foregroundcolor Red
    }
}

Set-Location $BaseDirectory


## MDT Setup:
## Thank you, Digressive/MDT-Setup for this awesome MDT setup script!
## Source: https://github.com/Digressive/MDT-Setup
$mdt_setup_script = Get-ChildItem -Path "MDT-Setup" -Include "MDT-Setup.ps1" -File -Recurse -ErrorAction Stop

## MDT Application Bundle Management Script - Thank you!
## Source: https://github.com/damienvanrobaeys/Manage_MDT_Application_Bundle
$manage_mdt_app_bundles = Get-ChildItem -Path "MDT-Setup" -Filter "Manage_Application_Bundle.ps1" -File -ErrorAction Stop
. "$($manage_mdt_app_bundles.fullname)"

## MDT installation/configuration script requires internet - check by pingining google.com
$ping_google = Test-Connection google.com -Count 1 -Quiet
if ($ping_google) {
    if ($mdt_setup_script) {
        ## Get Domain prefix by splitting dc hostname
        $domain_prefix = ($DC_HOSTNAME -Split '-')[0]
        $domain_prefix = "$domain_prefix-pc-"

        Write-Host "MDT-Setup script found. Running the script..."
        Powershell.exe -ExecutionPolicy Bypass "&$($mdt_setup_script.fullname) -DomainPrefix $domain_prefix"
    }
    else {
        Write-Host "MDT-Setup script not found. Exiting..."
        exit 1
    }

    ## NOTE: I have tested this successfully on Windows Server 2022 running in a Proxmox VM (currently adding changes into this script)

    ## Configurations made:
    ## 1. Monitoring service enabled.
    ## 2. VirtIO storage drivers for win10 added to WinPE drivers folder in deployment share.
    ## TODO:
    ## 3. VirtIO Windows drivers installation via application/msi?

    ## Import mdt module:
    $mdt_module = Get-ChildItem -Path "C:\Program Files\Microsoft Deployment Toolkit\bin" -Filter "MicrosoftDeploymentToolkit.psd1" -File -ErrorAction SilentlyContinue
    if (-not $mdt_module) {
        Write-Host "MDT module file not found, exiting."
        exit 1
    }

    Write-Host "Found $($mdt_module.fullname), importing..."
    ipmo $($mdt_module.fullname)


    # default deployment share name
    $deployshare = "C:\deployshare"
    New-PSDrive -Name "DS002" -PSProvider MDTProvider -Root $deployshare -Description "MDT Deployment Share" -Verbose

    ## Enable MDT Monitor Service
    Enable-MDTMonitorService -EventPort 9800 -DataPort 9801 -Verbose
    Set-ItemProperty -path DS002: -name MonitorHost -value $env:COMPUTERNAME
    ## Unsure if this is necessary:
    # Set-ItemProperty -path DS002: -name MonitorEventPort -value 9800
    # Set-ItemProperty -path DS002: -name MonitorDataPort -value 9801
    
    ## find virtio drivers disk by targeting virtio msi
    ## Check for virtio 64-bit Windows driver installer MSI file by cycling through base of connected drives.
    $drives = Get-PSDrive -PSProvider FileSystem
    foreach ($drive in $drives) {
        $file = Get-ChildItem -Path $drive.Root -Filter "virtio-win-gt-x64.msi" -File -ErrorAction SilentlyContinue
        # If/once virtio msi is found - attempt to install silently and discontinue the searching of drives.
        if ($file) {

            ## VirtIO Win10 storage drivers path:
            $w10_folder = Get-Item -Path "$($drive.root)amd64\w10" -ErrorAction SilentlyContinue
            if (-not $w10_folder) {
                Write-Host "amd64/w10 folder not found in $($drive.root)" -Foregroundcolor yellow
                Read-Host "Press enter to continue"
            }
            else {

                ## get model name for folder:
                $modelname = Get-Ciminstance -class win32_computersystem | select -exp model
                $makename = Get-Ciminstance -class win32_computersystem | select -exp manufacturer

                Write-Host "Creating VirtIO driver folder in Out-of-box drivers\WinPE folder."
                ## create virtio driver folder:
                New-Item -Path "DS002:\Out-of-box drivers\$makename" -ItemType Directory
                New-Item -Path "DS002:\Out-of-box drivers\$makename\$modelname" -ItemType Directory

                Write-Host "Importing VirtIO drivers to deployment share.."
                ## Import virtio drivers to MDT:
                Import-MDTDriver -Path "DS002:\Out-of-box drivers\$makename\$modelname" -SourcePath $w10_folder.FullName -Verbose

                New-Item -Path "DS002:\Out-of-box drivers\WinPE\VirtIO" -ItemType Directory


                ## Get ALL w10 amd64 drivers from virtio iso and import into make/model folder for injection
                Import-MDTDriver -Path "DS002:\Out-of-box drivers\WinPE\VirtIO" -SourcePath $w10_folder.FullName -Verbose

                $folders = Get-ChildItem -Path $drive.root -Include 'amd64' -Directory -Recurse | ? { $_.Parent.name -eq 'w10' }

                $folders | % {
                    Import-MDTDriver -Path "DS002:\Out-of-box drivers\$makename\$modelname" -SourcePath $_.fullname -verbose
                }


            }
            break
        }
    }

    ## populate the 7zip, chrome, and vscode ps app deployments with installer files:
    ## These downloads may take a while depending on network capabilities.
    ##
    $deploy_path = "deploy"
    @('7zip', 'chrome', 'VSCode') | % {
        $folder = "$deploy_path\$_\Files"
        if (-not (Test-Path $folder -PathType Container -ErrorAction SilentlyContinue)) {
            New-Item -Path $folder -ItemType Directory | Out-null
        }
    }
    # iwr "https://www.7-zip.org/a/7z2408-x64.msi" -outfile "$deploy_path\7zip\Files\7z2408-x64.msi"
    # iwr "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi" -outfile "$(Join-Path $BaseDirectory "$deploy_path\Chrome\Files\googlechromestandaloneenterprise64.msi")"    
    # iwr "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64" -outfile "$deploy_path\VSCode\Files\VSCodeSetup-x64.exe"

    ## Add few second pause before importing applications to ensure files are downloaded.
    # Start-Sleep -Seconds 5

    ## Import apps individually for now, may  be able to use a loop later?
    @('7zip', 'Chrome', 'VSCode') | % {
        $app_source = "$deploy_path\$_"
        Import-MDTApplication -Path "DS002:\Applications" -enable $true -reboot $false -hide $false -Name "$_" -ShortName "$_" `
            -CommandLine "Powershell.exe -executionPolicy bypass ./Deploy-$_.ps1 -DeploymentType Install -DeployMode Silent" `
            -WorkingDirectory ".\Applications\$_" -ApplicationSourcePath "$app_source" -DestinationFolder "$_" `
            -Comments "$_ PSADT" -Verbose
    }
    ## 7zip
    # $7zip_source = "$deploy_path\7zip"
    # Import-MDTApplication -Path "DS002:\Applications" -enable $true -reboot $false -hide $false -Name '7zip' -ShortName '7zip' `
    #     -CommandLine "Powershell.exe -executionPolicy bypass ./Deploy-7zip.ps1 -DeploymentType Install -DeployMode Silent" `
    #     -WorkingDirectory ".\Applications\7zip\" -ApplicationSourcePath "$7zip_source" -DestinationFolder "7zip" `
    #     -Comments "7zip PSADT" -Verbose
    # ## Chrome
    # $chrome_source = "$deploy_path\chrome"
    # Import-MDTApplication -Path "DS002:\Applications" -enable $true -reboot $false -hide $false -Name 'chrome' -ShortName 'chrome' `
    #     -CommandLine "Powershell.exe -executionpolicy bypass ./Deploy-Chrome.ps1 -Deploymenttype Install -Deploymode Silent" `
    #     -WorkingDirectory ".\Applications\chrome\" -ApplicationSourcePath "$chrome_source" -DestinationFolder "chrome" `
    #     -Comments "Chrome PSADT" -Verbose
    # ## VSCode
    # $vscode_source = "$deploy_path\VSCode"
    # Import-MDTApplication -path "DS002:\Applications" -enable $true -reboot $false -hide $false -Name 'VSCode' -ShortName 'VSCode' `
    #     -CommandLine "Powershell.exe -ExecutionPolicy Bypass ./Deploy-VSCode.ps1 -DeploymentType Install -DeployMode Silent" `
    #     -WorkingDirectory ".\Applications\VSCode" -ApplicationSourcePath "$vscode_source" -DestinationFolder "VSCode" `
    #     -Comments 'VS Code PSADT' -Verbose




    ## This would create an Application Bundle containing the three apps. I'm going to try a different method to force them to be installed during deployment first.    
    $main_app_bundle_name = "MainApps"
    Import-MDTApplication -Path "DS002:\Applications" -enable $true -reboot $false -hide $false -Name "$main_app_bundle_name" -ShortName "BasicApps" `
        -Bundle -Comments "Basic Application Bundle"

    ## update the deployment share:
    Update-MDTDeploymentShare -Path "DS002:" -Verbose

    ## Add applications to bundle:
    @('7zip', 'chrome', 'vscode') | % {
        Add-Dependency -DeploymentShare "$deployshare" -App_Name $_ -Bundle_Name "$main_app_bundle_name"
    }

    ## Get Application Bundle GUID from Applications.xml
    $apps_xml = [xml]$(Get-Content "$deployshare\Control\Applications.xml")

    $mainApps_bundle_guid = $apps_xml.applications.application | ? { $_.name -eq "$main_app_bundle_name" } | select -exp guid

    ## Edit Task Sequence XML to add in the bundle GUID.
    ## Resource: https://www.sharepointdiary.com/2020/11/xml-manipulation-in-powershell-comprehensive-guide.html#h-changing-xml-values-with-powershell
    $task_sequence_xml = [System.Xml.XmlDocument]::new()
    $task_sequence_xml.Load("$deployshare\Control\W10-22H2\ts.xml")
    $installapps = $task_sequence_xml.sequence.group.step | ? { $_.name -eq 'install applications' }
    $installapps.defaultvarlist.variable | % {
        if ($_.name -eq 'applicationguid') {
            $_.InnerText = $mainApps_bundle_guid
        }
    }

    ## Save xml docs:
    $task_sequence_xml.Save("$deployshare\Control\W10-22H2\ts.xml")

    ## update the deployment share:
    Update-MDTDeploymentShare -Path "DS002:" -Verbose
}
else {
    Write-Host "No internet connection detected." -Foregroundcolor Red
    Write-Host "Unfortunately, an internet connection is required to run MDT-Setup because it downloads Windows ADK/WinPE Add-on, Windows Media Creation Tool, and other installer files."
    Read-Host "Press enter to exit."
}
