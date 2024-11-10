## This will remove the base OU, along with fileshares created.

## DHCP, DNS, AD DS, will remain.
param(
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [Parameter(Mandatory = $false)]
    $config_ps1 = "config.ps1"
    )
## Dot source configuration variables:
try {
    $config_ps1 = Get-ChildItem -Path '.' -Filter "$config_ps1" -File -ErrorAction Stop
    Write-Host "Found $($config_ps1.fullname), dot-sourcing configuration variables.."

    . ".\$($config_ps1.name)"
}
catch {

    Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Error reading searching for / dot sourcing config ps1, exiting script." -ForegroundColor Red
    Read-Host "Press enter to exit.."
    Return 1
}

## Remove base OU
$BASE_OU = $USER_AND_GROUP_CONFIG.base_ou
try {
    Get-ADOrganizationalUnit -Filter "Name -eq '$BASE_OU'" | Remove-ADOrganizationalUnit -Confirm:$false
    Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Removing base OU: $BASE_OU.."

} catch {
    Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Something went wrong removing base ou: $BASE_OU." -Foregroundcolor Yellow
    Read-Host "Press enter to continue"
}

## Remove fileshares
$FILESHARE_CONFIG | ForEach-Object {
    $SHARE_NAME = $_.Name
    try {
        Get-SmbShare -Name $SHARE_NAME | Remove-SmbShare -Confirm:$false

        Remove-Item -Path $_.Path -Recurse -Force

        Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Removed smb share and folder: $SHARE_NAME."

    } catch {
        Write-Host "[$(Get-Date -Format 'mm-dd-yyyy HH:mm:ss')] :: Something went wrong removing fileshare: $SHARE_NAME." -Foregroundcolor Yellow
        Read-Host "Press enter to continue"
    }
}