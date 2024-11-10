## Creating file shares base on FILESHARE_CONFIG from config.ps1
## By default, a file share is created/configured for users home drives and roaming profiles (2 file shares)
param(
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [Parameter(Mandatory = $false)]
    $config_ps1_file = "config.ps1"
)
## Dot source configuration variables:
try {
    $config_ps1 = Get-ChildItem -Path '.' -Filter "$config_ps1_file" -File -Recurse -ErrorAction Stop
    Write-Host "Found $($config_ps1.fullname), dot-sourcing configuration variables.."

    . "$($config_ps1.fullname)"
}
catch {

    Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Error reading searching for / dot sourcing config ps1, exiting script." -ForegroundColor Red
    Read-Host "Press enter to exit.."
    Return 1
}

#########
$DOMAIN_NETBIOS = (Get-ADDomain).NetBIOSName

If (-not (Test-Path C:\Shares -ErrorAction SilentlyContinue)) {
    New-Item -Path C:\Shares -ItemType Directory | Out-null
}

## Cycle through each fileshare object in $FILESHARE_CONFIG variable
ForEach ($share_listing in $FILESHARE_CONFIG) {

    ## Get Admins group name:
    $admin_group_name = ($USER_AND_GROUP_CONFIG.GetEnumerator() | ? { $_.Name -eq 'admins' }).value
    $admin_group_name = $admin_group_name.name

    ## Get Users group name:
    $users_group_name = ($USER_AND_GROUP_CONFIG.GetEnumerator() | ? { $_.Name -eq 'users' }).value
    $users_group_name = $users_group_name.name

    $ShareParameters = @{
        Name                  = $share_listing.name
        Path                  = $share_listing.path
        Description           = $share_listing.description
        FullAccess            = "$DOMAIN_NETBIOS\Domain Admins", "$DOMAIN_NETBIOS\$admin_group_name", "Administrators" # explicit admin listing.
        ReadAccess            = "$DOMAIN_NETBIOS\$users_group_name"
        FolderEnumerationMode = "AccessBased"
        # ContinuouslyAvailable = $true
        # SecurityDescriptor = ""
    }

    ## Create directory if doesn't exist
    if (-not (Test-Path "$($share_listing.path)" -ErrorAction SilentlyContinue)) {
        New-Item -Path $share_listing.path -ItemType Directory | Out-Null
    }

    New-SmbShare @ShareParameters

    ## disbale inheritance, convert to explicit permissions
    ## disbale inheritance, convert to explicit permissions
    $acl = Get-Acl -Path $share_listing.path
    ## Add access rule for homelabusers group:
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("$DOMAIN_NETBIOS\$users_group_name", "ReadandExecute,CreateDirectories,AppendData,Traverse,ExecuteFile", "Allow")))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("$DOMAIN_NETBIOS\$admin_group_name", "FullControl", "Allow")))

    $acl.SetAccessRuleProtection($true, $true)

    Set-Acl -Path $share_listing.path -AclObject $acl

    ## Allows creation of user's folder in the share upon first login, users can't see other user folders.
    ## Ok for test lab.
    Grant-SMBshareAccess -Name $share_listing.name -AccountName "Authenticated Users" -AccessRight Full -Force

}