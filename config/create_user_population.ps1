param(
    $num_users = 50,
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [Parameter(Mandatory = $false)]
    $config_ps1_file = "config.ps1",
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    $user_data_file = "random_user_data.csv",
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    $department_data_file = "departments.csv"
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
$DC_PASSWORD = ConvertTo-SecureString $DOMAIN_CONFIG.Password -AsPlainText -Force
$DOMAIN_NAME = (Get-ADDomain).DNSRoot
$DC_HOSTNAME = (Get-ADDomainController).HostName


# try {
$user_data_file = Get-ChildItem -Path '.' -Filter "$user_data_file" -File -Recurse -ErrorAction Stop | SElect -exp fullname
$USER_DATA = Import-CSV "$user_data_file"
# }
# catch {
#     Write-Host "Something went wrong importing the user data file at: $user_data_file." -ForegroundColor Yellow
# }

# try {
$department_data_file = Get-ChildItem -Path '.' -Filter "$department_data_file" -File -Recurse -ErrorAction Stop | Select -exp fullname
$DEPT_DATA = Import-CSV $department_data_file
# }
# catch {
#     Write-Host "Something went wrong importing the department name data file at: $department_data_file." -ForegroundColor Yellow
# }

## Get the user's OU info from config variable:
$users_ou_info = ($USER_AND_GROUP_CONFIG.GetEnumerator() | ? { $_.Name -eq 'users' }).value

## Get the path, where users and department groups will be created
$department_ou_path = (Get-ADOrganizationalUnit -Filter "Name -like '$($users_ou_info.name)'").DistinguishedName

## Users in IT department will also have an _admin account created for them.
## Get Admin group info from config, and OU path
$admin_ou_info = ($USER_AND_GROUP_CONFIG.GetEnumerator() | ? { $_.Name -eq 'admins' }).value
$admin_ou_name = $admin_ou_info.name
$admin_ou_path = (Get-ADOrganizationalUnit -Filter "Name -eq '$admin_ou_name'").DistinguishedName

## Create an AD Group for each department listed in DEPT_DATA
$DEPT_DATA | % {
    $department_name = $_.department_name
    $department_description = $_.description

    try {
        New-ADGroup -Name $department_name -GroupCategory Security -GroupScope Global -Path "$department_ou_path" -Description "$department_description"
        Write-Host "Created departmental group: $department_name."
    }
    catch {
        Write-Host "Something went wrong with creating departmental group: $department_name." -Foregroundcolor Yellow
    }
}

## Shuffle user data for randomization
$user_info = $USER_DATA | Get-Random -Count $num_users

## Assign departments to users with a round-robin approach
## Hopefully using modulus here will take into account leftover users.
$deptIndex = 0
foreach ($user in $user_info) {
    $user | add-member -membertype noteproperty -name department -value $null
    $user.department = $DEPT_DATA[$deptIndex % $DEPT_DATA.Count].department_name
    $deptIndex++
}

## Now that $user_info holds all necessary info - AD User accounts can be created.
ForEach ($user_account in $user_info) {
    $firstname = $user_account.first_name
    $lastname = $user_account.last_name
    $deptname = $user_account.department
    
    ## This forms initial username, if it already exists, another will be created.
    if ($lastname.length -ge 8) {
        $username = $lastname.Substring(0, 8)
    }
    else {
        $username = $lastname
    }

    $username = "$($firstname[0])$username"

    $number_at_end_of_username = 1
    ## Make sure username is unique
    while (Get-ADUser -Filter "SamAccountName -eq '$username'") {
        Write-Host "Existing AD User account for: " -NoNewline
        write-host "$username" -Foregroundcolor Yellow

        $number_length = $number_at_end_of_username.ToString().Length
        ## Chop off last number_length characters in username and attach number
        $username = $username.Substring(0, $username.Length - $number_length) + [string]$number_at_end_of_username

        Write-Host "Attempting AD usename: " -NoNewline
        write-host "$username" -Foregroundcolor Yellow

    }

    $splat = @{
        SamAccountName    = $username
        UserPrincipalName = "$username@$DOMAIN_NAME"
        DisplayName       = "$firstname $lastname"
        Name              = $username
        GivenName         = $firstname
        Surname           = $lastname
        Department        = $deptname
        AccountPassword   = $DC_PASSWORD
        Enabled           = $true
        HomeDrive         = 'Z'
        HomeDirectory     = "\\$DC_HOSTNAME\users\$username"
        ProfilePath       = "\\$DC_HOSTNAME\profiles$\$username"
        Path              = "$department_ou_path"
        # Force = $true
    }

    Write-Host "`nCreating user account for $firstname $lastname." -ForegroundColor Yellow
    # Write-Host "Username: $username"
    # Write-Host "Department: $deptname"
    try {
        New-ADUser @splat
        Write-Host "Created user: $($splat.userprincipalname)."
    }
    catch {
        Write-Host "Something went wrong creating user; $($splat.userprincipalname)." -foregroundcolor yellow
    }
    ## Add user to their dept group, and the main users group from config.ps1
    Add-ADGroupMember -Identity $deptname -Members $username

    Add-ADGroupMember -Identity $($users_ou_info.name) -Members $username

    
    ## if they're an IT user - make them an admin, is already guaranteed not to be duplicate (I hope)
    if ($deptname -eq "IT") {

        $admin_username = "$($username)_admin"

        $admin_splat = @{
            SamAccountName    = $admin_username
            UserPrincipalName = "$admin_username@$DOMAIN_NAME"
            DisplayName       = "$firstname $lastname (admin)"
            Name              = $admin_username
            # GivenName         = $firstname
            # Surname           = $lastname
            Department        = $deptname
            AccountPassword   = $DC_PASSWORD
            Enabled           = $true
            Path              = "$admin_ou_path" ## explicit listing of the users group
        
        }
    
        Write-Host "`nCreating admin account for $firstname $lastname." -ForegroundColor Yellow
        Write-Host "Username: $admin_username"
        Write-Host "Department: $deptname"

        try {
            New-ADUser @admin_splat
            Write-Host "Created _admin user for: $($admin_splat.userprincipalname)."
        }
        catch {
            Write-Host "Something went wrong with creating user: $($admin_splat.userprincipalname)." -Foregroundcolor Yellow
        }
        ## Add user to their dept group
        Add-ADGroupMember -Identity $($admin_ou_info.name) -Members "$admin_username"

    }
}