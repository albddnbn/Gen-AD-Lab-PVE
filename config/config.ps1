## Domain configuration:
$DOMAIN_CONFIG = [PSCustomObject]@{
    Name          = 'lab.edu'
    Netbios       = 'lab'
    DC_Hostname   = 'a-dc-01'
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
## Fileshare(s) configuration:
$FILESHARE_CONFIG = @(
    ## SMB Share to hold roaming profile data for regular users
    [PSCustomObject]@{
        Name        = 'profiles$'
        Path        = 'C:/Shares/profiles$'
        Description = 'Profiles share'
    },
    ## SMB Share to hold user homedrive data for regular users
    [PSCustomObject]@{
        Name        = 'users'
        Path        = 'C:/Shares/users'
        Description = 'Users share'
    }
)

## User and group configuration - set names for regular user, admin, and computer groups/OUs
$USER_AND_GROUP_CONFIG = @{
    ## admins group, AD users in the IT department have _admin admin account created for them.
    ## the _admin accounts are added to this group.
    "admins"    = [PSCustomObject]@{
        Name        = "LabAdmins"
        Description = "Lab Admins"
        MemberOf    = @('Domain Admins')
    };
    ## basic computer group, not used for anything atm
    "computers" = [PSCustomObject]@{
        Name        = "LabComputers"
        Description = "Lab Computers"
        MemberOf    = @('Domain Computers')
    };
    ## basic user group - used for regular users who need folder redirection and roaming profiles
    "users"     = [PSCustomObject]@{
        Name        = "LabUsers"
        Description = "Lab Users"
        MemberOf    = @('Domain Users')
    };
    ## Base OU (all users, groups, ous, etc. are added to this OU)
    "base_ou"   = "homelab";
}

## MDT Server / Deployment configuration
$MDT_SERVER_CONFIG = [PSCustomObject]@{
    DEPLOY_SHARE = 'Deployment'
}