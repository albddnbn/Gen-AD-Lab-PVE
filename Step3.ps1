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
$host.ui.RawUI.WindowTitle = "Step 3"
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
Get-ScheduledTask -TaskName 'step3_genadlab' -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false

## Ensure necessary files/scripts can be accessed:
$user_creation_script = Get-ChildItem -Path './config' -Filter "$user_creation_ps1_file" -File -ErrorAction Stop
$fileshare_creation_script = Get-ChildItem -Path './config' -Filter "$fileshares_ps1_file" -File -ErrorAction Stop
## MDT Setup: https://github.com/Digressive/MDT-Setup - this script takes care of the heavy-lifting for MDT/Deployment.
$mdt_setup_script = Get-ChildItem -Path "MDT-Setup" -Include "MDT-Setup.ps1" -File -Recurse -ErrorAction Stop
## https://github.com/damienvanrobaeys/Manage_MDT_Application_Bundle - provides functions for MDT App Bundles
## Format XML document function: https://devblogs.microsoft.com/powershell/format-xml/
@("Manage_Application_Bundle.ps1", "format-xml.ps1") | % {
    $file = Get-ChildItem -Path "MDT-Setup" -Filter "$_" -File -ErrorAction Stop
    . "$($file.fullname)"

}

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

## All users, computers, etc. created by this script series are put into this OU.
$BASE_OU = $USER_AND_GROUP_CONFIG.base_ou

## MDT Server Deployment share name, share will be C:\<sharename>, \\<sharename>$
$DEPLOY_SHARE = $MDT_SERVER_CONFIG.DEPLOY_SHARE
$DEPLOY_SHARE_LOCAL_PATH = "C:\$DEPLOY_SHARE"

## Install and configure DHCP Server with single scope
Install-WindowsFeature -Name DHCP -IncludeManagementTools
Restart-service dhcpserver

Add-DHCPServerInDC -DnsName "$DC_HOSTNAME" -IPAddress $DHCP_IP_ADDR

Add-DHCPServerv4Scope -Name "$DHCP_SCOPE_NAME" -StartRange "$DHCP_START_RANGE" `
    -EndRange "$DHCP_END_RANGE" -SubnetMask $DHCP_SUBNET_PREFIX `
    -State Active

Set-DHCPServerv4OptionValue -ComputerName "$DC_HOSTNAME" `
    -DnsServer $DHCP_DNS_SERVERS -DnsDomain "$DOMAIN_NAME" `
    -Router $DHCP_GATEWAY -Force


Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Base OU is: " -nonewline
Write-Host "$BASE_OU" -foregroundcolor yellow
Write-Host "All users, groups, ous, etc. will be created inside this OU."
try {
    New-ADOrganizationalUnit -Name "$BASE_OU" -Path "$DOMAIN_PATH" -ProtectedFromAccidentalDeletion $false
    Write-Host "Created $BASE_OU OU."

    ## OUs/Groups created inside Base OU
    $base_ou_path = (Get-ADOrganizationalUnit -Filter "Name -eq '$base_ou'").DistinguishedName
}
catch {
    Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: " -NoNewLine
    Write-Host "Something went wrong with creating $BASE_OU OU." -Foregroundcolor Red
    Write-Host "You can change the base OU in the config.ps1 file (user_and_group_config variable)."
    Read-Host "Press enter to try to continue."
}

## This will create an AD Group and OU for each listing in the user_and_group_config variable, except for the base_ou listing.
## By default - a group for regular users, IT admins, and computers is included.
ForEach ($listing in $($USER_AND_GROUP_CONFIG.GetEnumerator() | ? { $_.Name -ne 'base_ou' })) {
    ## Used for OU and Group Name
    $item_name = $listing.value.name
    ## Group Description
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

## USER CREATION - using names/etc. from config/users.csv
Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Beginning user creation."

Powershell.exe -ExecutionPolicy Bypass "$($user_creation_script.fullname)"

## FILESHARE CREATION
Powershell.exe -ExecutionPolicy Bypass "$($fileshare_creation_script.fullname)"

## Install applications from the deploy folder on DC:
$foldernames = Get-ChildItem -path 'deploy' -Directory -ErrorAction SilentlyContinue | Select -Exp FullName
$foldernames | % {
    ## May not be necessary to have this try/catch
    try {
        ## Set Location to folder
        Set-Location "$_"
        $appname = $_ | Split-Path -Leaf
        $scriptfile = "deploy-$appname.ps1"

        Powershell.exe -ExecutionPolicy Bypass "./$scriptfile" -Deploymenttype 'Install' -Deploymode 'Silent'
    }
    catch {
        Write-Host "Something went wrong with installing applications from $_." -Foregroundcolor Red
    }
}

Set-Location $PSScriptRoot

## MDT installation/configuration script requires internet - check by pinging google.com
$ping_google = Test-Connection google.com -Count 1 -Quiet
if ($ping_google) {
    if ($mdt_setup_script) {
        ## Get Domain prefix by splitting dc hostname
        $domain_prefix = ($DC_HOSTNAME -Split '-')[0]
        $domain_prefix = "$($domain_prefix)-pc-"
        Powershell.exe -ExecutionPolicy Bypass "&$($mdt_setup_script.fullname) -DomainPrefix $domain_prefix -DomainControllerHostname $DC_HOSTNAME -DeploymentShareName $DEPLOY_SHARE -BaseOU $BASE_OU" 
    }
    else {
        Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: " -NoNewLine
        Write-Host "MDT-Setup script not found. Exiting..." -ForegroundColor Red
        exit 1
    }

    ## MDT Powershell module is used to import drivers/update deployment share/etc.
    $mdt_module = Get-ChildItem -Path "C:\Program Files\Microsoft Deployment Toolkit\bin" -Filter "MicrosoftDeploymentToolkit.psd1" -File -ErrorAction SilentlyContinue
    if (-not $mdt_module) {
        Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: " -NoNewLine
        Write-Host "MDT module file not found, exiting." -Foregroundcolor Red
        exit 1
    }
    Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Found $($mdt_module.fullname), importing..."
    Import-Module $($mdt_module.fullname)

    New-PSDrive -Name "DS002" -PSProvider MDTProvider -Root $DEPLOY_SHARE_LOCAL_PATH -Description "MDT Deployment Share" -Verbose

    ## Enable MDT Monitor Service (or try to!)
    Enable-MDTMonitorService -EventPort 9800 -DataPort 9801 -Verbose
    Set-ItemProperty -path DS002: -name MonitorHost -value $env:COMPUTERNAME
    Set-ItemProperty -path DS002: -name MonitorEventPort -value 9800
    Set-ItemProperty -path DS002: -name MonitorDataPort -value 9801
    New-Service -Name "MDT_Monitor" -Description "Microsoft Deployment Toolkit Monitor Service" -BinaryPathName "C:\Program Files\Microsoft Deployment Toolkit\Monitor\Microsoft.BDD.MonitorService.exe" -DisplayName "Microsoft Deployment Toolkit Monitor Service" -StartupType Automatic


    $computer_config_script = Get-ChildItem -Path MDT-Setup -Filter "computer_config.ps1" -File -ErrorAction SilentlyContinue
    if ($computer_config_script) {
        Get-Content "$($computer_config_script.fullname)" | Set-Content -Path "$DEPLOY_SHARE_LOCAL_PATH\Scripts\computer_config.ps1"
    }

    ## ALERT: This is the part that is specific to Proxmox VE - script will search drives to try to find the VirtIO
    ## iso, and install VirtIO drivers necessary for certain PVE VMs.
    $drives = Get-PSDrive -PSProvider FileSystem
    foreach ($drive in $drives) {
        $file = Get-ChildItem -Path $drive.Root -Filter "virtio-win-gt-x64.msi" -File -ErrorAction SilentlyContinue
        # If/once virtio msi is found - attempt to install silently and discontinue the searching of drives.
        if ($file) {

            ## VirtIO Win10 storage drivers path:
            $w10_folder = Get-Item -Path "$($drive.root)amd64\w10" -ErrorAction Continue
            ########################################################################################################
            ## MDT Deployment/DRIVER SETUP:
            ########################################################################################################
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
            break
        }
    }

    ####################################################################################################################
    ## MDT Deployment/APPLICATION SETUP: using apps from 'deploy' folder - PS App Deployment Toolkits
    ####################################################################################################################
    $deploy_path = "deploy"
    @('7zip', 'chrome', 'VSCode') | % {
        $folder = "$deploy_path\$_\Files"
        if (-not (Test-Path $folder -PathType Container -ErrorAction SilentlyContinue)) {
            New-Item -Path $folder -ItemType Directory | Out-null
        }

        ## Download chrome installer since the MSI is too big for Github repo.
        ## https://stackoverflow.com/questions/28682642/powershell-why-is-using-invoke-webrequest-much-slower-than-a-browser-download
        if ($_ -eq 'chrome') {
            $google_out_path = Join-Path $folder "googlechromestandaloneenterprise64.msi"
            $wc = new-object net.webclient
            $wc.downloadfile("https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi", "$google_out_path")
        }

        $app_source = "$deploy_path\$_"
        Import-MDTApplication -Path "DS002:\Applications" -enable $true -reboot $false -hide $false -Name "$_" -ShortName "$_" `
            -CommandLine "Powershell.exe -executionPolicy bypass ./Deploy-$_.ps1 -DeploymentType Install -DeployMode Silent" `
            -WorkingDirectory ".\Applications\$_" -ApplicationSourcePath "$app_source" -DestinationFolder "$_" `
            -Comments "$_ PSADT" -Verbose 

    }

    ####################################################################################################################
    ## MDT Deployment/APPLICATION BUNDLE SETUP:
    ####################################################################################################################
    $main_app_bundle_name = "MainApps"
    Import-MDTApplication -Path "DS002:\Applications" -enable $true -reboot $false -hide $false -Name "$main_app_bundle_name" -ShortName "BasicApps" `
        -Bundle -Comments "Basic Application Bundle"

    Update-MDTDeploymentShare -Path "DS002:" -Verbose
    ## Add applications to bundle:
    @('7zip', 'chrome', 'vscode') | % {
        Add-Dependency -DeploymentShare "$DEPLOY_SHARE_LOCAL_PATH" -App_Name $_ -Bundle_Name "$main_app_bundle_name"
    }

    ## Get Application Bundle GUID from Applications.xml
    $apps_xml = [xml]$(Get-Content "$DEPLOY_SHARE_LOCAL_PATH\Control\Applications.xml")
    $mainApps_bundle_guid = $apps_xml.applications.application | ? { $_.name -eq "$main_app_bundle_name" } | select -exp guid

    ## Edit Task Sequence XML to add in the bundle GUID.
    ## Resource: https://www.sharepointdiary.com/2020/11/xml-manipulation-in-powershell-comprehensive-guide.html#h-changing-xml-values-with-powershell
    $task_sequence_xml = [System.Xml.XmlDocument]::new()
    $task_sequence_xml.Load("$DEPLOY_SHARE_LOCAL_PATH\Control\W10-22H2\ts.xml")
    $installapps = $task_sequence_xml.sequence.group.step | ? { $_.name -eq 'install applications' }
    $installapps.defaultvarlist.variable | % {
        if ($_.name -eq 'applicationguid') {
            $_.InnerText = $mainApps_bundle_guid
        }
    }

    $task_sequence_xml.Save("$DEPLOY_SHARE_LOCAL_PATH\Control\W10-22H2\ts.xml")

    Update-MDTDeploymentShare -Path "DS002:" -Verbose

    format-xml ([xml](cat "$DEPLOY_SHARE_LOCAL_PATH\Control\W10-22H2\ts.xml")) | set-content "$DEPLOY_SHARE_LOCAL_PATH\Control\W10-22H2\ts.xml"
}
else {
    Write-Host "No internet connection detected." -Foregroundcolor Red
    Write-Host "Unfortunately, an internet connection is required to run MDT-Setup because it downloads Windows ADK/WinPE Add-on, Windows Media Creation Tool, and other installer files."
    Read-Host "Press enter to exit."
}
