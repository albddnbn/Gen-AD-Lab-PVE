<#
.SYNOPSIS
    This script performs the installation or uninstallation of Microsoft Visual Studio Code.
    # LICENSE #
    PowerShell App Deployment Toolkit - Provides a set of functions to perform common application deployment tasks on Windows.
    Copyright (C) 2017 - Sean Lillis, Dan Cunningham, Muhammad Mashwani, Aman Motazedian.
    This program is free software: you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the Free Software Foundation, either version 3 of the License, or any later version. This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
    You should have received a copy of the GNU Lesser General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.
.DESCRIPTION
    The script is provided as a template to perform an install or uninstall of an application(s).
    The script either performs an "Install" deployment type or an "Uninstall" deployment type.
    The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.
    The script dot-sources the AppDeployToolkitMain.ps1 script which contains the logic and functions required to install or uninstall an application.
.PARAMETER DeploymentType
    The type of deployment to perform. Default is: Install.
.PARAMETER DeployMode
    Specifies whether the installation should be run in Interactive, Silent, or NonInteractive mode. Default is: Interactive. Options: Interactive = Shows dialogs, Silent = No dialogs, NonInteractive = Very silent, i.e. no blocking apps. NonInteractive mode is automatically set if it is detected that the process is not user interactive.
.PARAMETER AllowRebootPassThru
    Allows the 3010 return code (requires restart) to be passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.
.PARAMETER TerminalServerMode
    Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Destkop Session Hosts/Citrix servers.
.PARAMETER DisableLogging
    Disables logging to file for the script. Default is: $false.
.EXAMPLE
    PowerShell.exe .\Deploy-VSCode.ps1 -DeploymentType "Install" -DeployMode "NonInteractive"
.EXAMPLE
    PowerShell.exe .\Deploy-VSCode.ps1 -DeploymentType "Install" -DeployMode "Silent"
.EXAMPLE
    PowerShell.exe .\Deploy-VSCode.ps1 -DeploymentType "Install" -DeployMode "Interactive"
.EXAMPLE
    PowerShell.exe .\Deploy-VSCode.ps1 -DeploymentType "Uninstall" -DeployMode "NonInteractive"
.EXAMPLE
    PowerShell.exe .\Deploy-VSCode.ps1 -DeploymentType "Uninstall" -DeployMode "Silent"
.EXAMPLE
    PowerShell.exe .\Deploy-VSCode.ps1 -DeploymentType "Uninstall" -DeployMode "Interactive"
.NOTES
    Toolkit Exit Code Ranges:
    60000 - 68999: Reserved for built-in exit codes in Deploy-Application.ps1, Deploy-Application.exe, and AppDeployToolkitMain.ps1
    69000 - 69999: Recommended for user customized exit codes in Deploy-Application.ps1
    70000 - 79999: Recommended for user customized exit codes in AppDeployToolkitExtensions.ps1
.LINK
    http://psappdeploytoolkit.com
#>
[CmdletBinding()]
Param (
    [Parameter(Mandatory = $false)]
    [ValidateSet('Install', 'Uninstall', 'Repair')]
    [string]$DeploymentType = 'Install',
    [Parameter(Mandatory = $false)]
    [ValidateSet('Interactive', 'Silent', 'NonInteractive')]
    [string]$DeployMode = 'Interactive',
    [Parameter(Mandatory = $false)]
    [switch]$AllowRebootPassThru = $false,
    [Parameter(Mandatory = $false)]
    [switch]$TerminalServerMode = $false,
    [Parameter(Mandatory = $false)]
    [switch]$DisableLogging = $false
)

Try {
    ## Set the script execution policy for this process
    Try { Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'Stop' } Catch {}

    ##*===============================================
    ##* VARIABLE DECLARATION
    ##*===============================================
    ## Variables: Application
    [string]$appVendor = 'Microsoft Corporation'
    [string]$appName = 'Visual Studio Code'
    [string]$appVersion = ''
    [string]$appArch = ''
    [string]$appLang = ''
    [string]$appRevision = ''
    [string]$appScriptVersion = '1.0.0'
    [string]$appScriptDate = 'XX/XX/20XX'
    [string]$appScriptAuthor = 'Jason Bergner'
    ##*===============================================
    ## Variables: Install Titles (Only set here to override defaults set by the toolkit)
    [string]$installName = ''
    [string]$installTitle = 'Microsoft Visual Studio Code'

    ##* Do not modify section below
    #region DoNotModify

    ## Variables: Exit Code
    [int32]$mainExitCode = 0

    ## Variables: Script
    [string]$deployAppScriptFriendlyName = 'Deploy Application'
    [version]$deployAppScriptVersion = [version]'3.8.4'
    [string]$deployAppScriptDate = '26/01/2021'
    [hashtable]$deployAppScriptParameters = $psBoundParameters

    ## Variables: Environment
    If (Test-Path -LiteralPath 'variable:HostInvocation') { $InvocationInfo = $HostInvocation } Else { $InvocationInfo = $MyInvocation }
    [string]$scriptDirectory = Split-Path -Path $InvocationInfo.MyCommand.Definition -Parent

    ## Dot source the required App Deploy Toolkit Functions
    Try {
        [string]$moduleAppDeployToolkitMain = "$scriptDirectory\AppDeployToolkit\AppDeployToolkitMain.ps1"
        If (-not (Test-Path -LiteralPath $moduleAppDeployToolkitMain -PathType 'Leaf')) { Throw "Module does not exist at the specified location [$moduleAppDeployToolkitMain]." }
        If ($DisableLogging) { . $moduleAppDeployToolkitMain -DisableLogging } Else { . $moduleAppDeployToolkitMain }
    }
    Catch {
        If ($mainExitCode -eq 0) { [int32]$mainExitCode = 60008 }
        Write-Error -Message "Module [$moduleAppDeployToolkitMain] failed to load: `n$($_.Exception.Message)`n `n$($_.InvocationInfo.PositionMessage)" -ErrorAction 'Continue'
        ## Exit the script, returning the exit code to SCCM
        If (Test-Path -LiteralPath 'variable:HostInvocation') { $script:ExitCode = $mainExitCode; Exit } Else { Exit $mainExitCode }
    }

    #endregion
    ##* Do not modify section above
    ##*===============================================
    ##* END VARIABLE DECLARATION
    ##*===============================================

    ## Download VS Code installer to dirfiles:

    If ($deploymentType -ine 'Uninstall' -and $deploymentType -ine 'Repair') {
        ##*===============================================
        ##* PRE-INSTALLATION
        ##*===============================================
        [string]$installPhase = 'Pre-Installation'

        ## Microsoft Intune Win32 App Workaround - Check If Running 32-bit Powershell on 64-bit OS, Restart as 64-bit Process
        If (!([Environment]::Is64BitProcess)) {
            If ([Environment]::Is64BitOperatingSystem) {

                Write-Log -Message "Running 32-bit Powershell on 64-bit OS, Restarting as 64-bit Process..." -Severity 2
                $Arguments = "-NoProfile -ExecutionPolicy ByPass -WindowStyle Hidden -File `"" + $myinvocation.mycommand.definition + "`""
                $Path = (Join-Path $Env:SystemRoot -ChildPath "\sysnative\WindowsPowerShell\v1.0\powershell.exe")

                Start-Process $Path -ArgumentList $Arguments -Wait
                Write-Log -Message "Finished Running x64 version of PowerShell"
                Exit

            }
            Else {
                Write-Log -Message "Running 32-bit Powershell on 32-bit OS"
            }
        }

        ## Show Welcome Message, Close Visual Studio Code With a 60 Second Countdown Before Automatically Closing
        Show-InstallationWelcome -CloseApps 'Code' -CloseAppsCountdown 60

        ## Show Progress Message (With a Message to Indicate the Application is Being Uninstalled)
        Show-InstallationProgress -StatusMessage "Removing Any Existing Versions of Microsoft Visual Studio Code. Please Wait..."

        ## Remove Microsoft Visual Studio Code (User Installer)
        $Users = Get-ChildItem C:\Users
        ForEach ($user in $Users) {

            $VSCodeLocal = "$($user.fullname)\AppData\Local\Programs\Microsoft VS Code"
            If (Test-Path $VSCodeLocal) {

                $UninstPath = Get-ChildItem -Path "$VSCodeLocal\*" -Include unins000.exe -Recurse -ErrorAction SilentlyContinue
                If ($UninstPath.Exists) {
                    Write-Log -Message "Found $($UninstPath.FullName), now attempting to uninstall the $installTitle."
                    Execute-ProcessAsUser -Path "$UninstPath" -Parameters "/VERYSILENT /NORESTART /LOG=""$configToolkitLogDir\VSCodeUser-Uninstall.log""" -Wait
                    Start-Sleep -Seconds 5

                    ## Cleanup User Profile Registry
                    [scriptblock]$HKCURegistrySettings = {
                        Remove-RegistryKey -Key 'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\{D628A17A-9713-46BF-8D57-E671B46A741E}_is1' -SID $UserProfile.SID
                        Remove-RegistryKey -Key 'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\{771FD6B0-FA20-440A-A002-3B3BAC16DC50}_is1' -SID $UserProfile.SID
                    }
                    Invoke-HKCURegistrySettingsForAllUsers -RegistrySettings $HKCURegistrySettings -ErrorAction SilentlyContinue

                    ## Cleanup Microsoft Visual Studio Code (Local User Profile) Directory
                    If (Test-Path $VSCodeLocal) {
                        Write-Log -Message "Cleanup ($VSCodeLocal) Directory."
                        Remove-Item -Path "$VSCodeLocal" -Force -Recurse -ErrorAction SilentlyContinue 
                    }
                }
            }
        }
        $Users = Get-ChildItem C:\Users
        ForEach ($user in $Users) {

            ## Cleanup Microsoft Visual Studio Code (Roaming User Profile) Directory
            $VSCodeRoaming = "$($user.fullname)\AppData\Roaming\Code"
            If (Test-Path $VSCodeRoaming) {
                Write-Log -Message "Cleanup ($VSCodeRoaming) Directory."
                Remove-Item -Path "$VSCodeRoaming" -Force -Recurse -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 5
            }
            ## Remove Microsoft Visual Studio Code Start Menu Shortcut From User Profiles (If Present)
            $StartMenuSC = "$($user.fullname)\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Visual Studio Code"
            If (Test-Path $StartMenuSC) {
                Write-Log -Message "Removing Microsoft Visual Studio Code Start Menu Shortcut From User Profile."
                Remove-Item $StartMenuSC -Recurse -Force -ErrorAction SilentlyContinue
            }
            ## Remove Microsoft Visual Studio Code Desktop Shortcut From User Profiles (If Present)
            $DesktopSC = "$($user.fullname)\Desktop\Visual Studio Code.lnk"
            If (Test-Path $DesktopSC) {
                Write-Log -Message "Removing Microsoft Visual Studio Code Desktop Shortcut From User Profile."
                Remove-Item $DesktopSC -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        ## Remove Microsoft Visual Studio Code (System Installer)
        $AppList = Get-InstalledApplication -Name 'Microsoft Visual Studio Code'        
        ForEach ($App in $AppList) {
            If ($App.UninstallString) {
                $UninstPath = $($App.UninstallString).Replace('"', '')       
                If (Test-Path -Path $UninstPath) {
                    Write-Log -Message "Found $($App.DisplayName) $($App.DisplayVersion) and a valid uninstall string, now attempting to uninstall."
                    Execute-Process -Path $UninstPath -Parameters "/VERYSILENT /NORESTART /LOG=""$configToolkitLogDir\VSCode-Uninstall.log"""
                    Start-Sleep -Seconds 5
                }
            }
        }
   
        ##*===============================================
        ##* INSTALLATION
        ##*===============================================
        [string]$installPhase = 'Installation'

        Write-Log -Message "Detected 64-bit OS Architecture" -Severity 1 -Source $deployAppScriptFriendlyName

        ## Install Microsoft Visual Studio Code (64-bit Systems)
        $ExePath64 = Get-ChildItem -Path "$dirFiles" -Include VSCodeSetup-x64*.exe -File -Recurse -ErrorAction SilentlyContinue
        If ($ExePath64.Exists) {
            Write-Log -Message "Found $($ExePath64.FullName), now attempting to install $installTitle."
            Show-InstallationProgress "Installing Microsoft Visual Studio Code (64-bit Systems). This may take some time. Please wait..."
            Execute-Process -Path "$ExePath64" -Parameters "/VERYSILENT /NORESTART /MERGETASKS=!runcode /LOG=""$configToolkitLogDir\VSCode64-Install.log""" -WindowStyle Hidden
            Start-Sleep -Seconds 5

            ## Disable Visual Studio Code Auto Updates
            $JSON = Get-ChildItem -Path "$dirFiles" -Include settings.json -File -Recurse -ErrorAction SilentlyContinue
            If ($JSON.Exists) {
                Write-Log -Message "Copying settings.json To User Profile (Disable Visual Studio Code Auto Updates)"
                $UserProfiles = Get-WmiObject Win32_UserProfile | Where { (!$_.Special) -and $_.LocalPath -notlike 'C:\Windows\ServiceProfiles*' } | Select-Object -ExpandProperty LocalPath
                ForEach ($Profile in $UserProfiles) {

                    New-Item "$Profile\AppData\Roaming\Code\User\" -ItemType Directory -Force
                    Copy-Item $JSON -Destination "$Profile\AppData\Roaming\Code\User\" -ErrorAction SilentlyContinue
                }
            }
        }
        
       
        ##*===============================================
        ##* POST-INSTALLATION
        ##*===============================================
        [string]$installPhase = 'Post-Installation'

        ## TODO: Import Dracula at night theme jsons

    }
    ElseIf ($deploymentType -ieq 'Uninstall') {
        ##*===============================================
        ##* PRE-UNINSTALLATION
        ##*===============================================
        [string]$installPhase = 'Pre-Uninstallation'

        ## Show Welcome Message, Close Visual Studio Code With a 60 Second Countdown Before Automatically Closing
        Show-InstallationWelcome -CloseApps 'Code' -CloseAppsCountdown 60

        ## Show Progress Message (With a Message to Indicate the Application is Being Uninstalled)
        Show-InstallationProgress -StatusMessage "Uninstalling the $installTitle Application. Please Wait..."

        ##*===============================================
        ##* UNINSTALLATION
        ##*===============================================
        [string]$installPhase = 'Uninstallation'

        ## Uninstall Microsoft Visual Studio Code (User Installer)
        $Users = Get-ChildItem C:\Users
        ForEach ($user in $Users) {

            $VSCodeLocal = "$($user.fullname)\AppData\Local\Programs\Microsoft VS Code"
            If (Test-Path $VSCodeLocal) {

                $UninstPath = Get-ChildItem -Path "$VSCodeLocal\*" -Include unins000.exe -Recurse -ErrorAction SilentlyContinue
                If ($UninstPath.Exists) {
                    Write-Log -Message "Found $($UninstPath.FullName), now attempting to uninstall the $installTitle."
                    Execute-ProcessAsUser -Path "$UninstPath" -Parameters "/VERYSILENT /NORESTART /LOG=""$configToolkitLogDir\VSCodeUser-Uninstall.log""" -Wait
                    Start-Sleep -Seconds 5

                    ## Cleanup User Profile Registry
                    [scriptblock]$HKCURegistrySettings = {
                        Remove-RegistryKey -Key 'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\{D628A17A-9713-46BF-8D57-E671B46A741E}_is1' -SID $UserProfile.SID
                        Remove-RegistryKey -Key 'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\{771FD6B0-FA20-440A-A002-3B3BAC16DC50}_is1' -SID $UserProfile.SID
                    }
                    Invoke-HKCURegistrySettingsForAllUsers -RegistrySettings $HKCURegistrySettings -ErrorAction SilentlyContinue

                    ## Cleanup Microsoft Visual Studio Code (Local User Profile) Directory
                    If (Test-Path $VSCodeLocal) {
                        Write-Log -Message "Cleanup ($VSCodeLocal) Directory."
                        Remove-Item -Path "$VSCodeLocal" -Force -Recurse -ErrorAction SilentlyContinue 
                    }
                }
            }
        }
        $Users = Get-ChildItem C:\Users
        ForEach ($user in $Users) {

            ## Cleanup Microsoft Visual Studio Code (Roaming User Profile) Directory
            $VSCodeRoaming = "$($user.fullname)\AppData\Roaming\Code"
            If (Test-Path $VSCodeRoaming) {
                Write-Log -Message "Cleanup ($VSCodeRoaming) Directory."
                Remove-Item -Path "$VSCodeRoaming" -Force -Recurse -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 5
            }
            ## Remove Microsoft Visual Studio Code Start Menu Shortcut From User Profiles (If Present)
            $StartMenuSC = "$($user.fullname)\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Visual Studio Code"
            If (Test-Path $StartMenuSC) {
                Write-Log -Message "Removing Microsoft Visual Studio Code Start Menu Shortcut From User Profile."
                Remove-Item $StartMenuSC -Recurse -Force -ErrorAction SilentlyContinue
            }
            ## Remove Microsoft Visual Studio Code Desktop Shortcut From User Profiles (If Present)
            $DesktopSC = "$($user.fullname)\Desktop\Visual Studio Code.lnk"
            If (Test-Path $DesktopSC) {
                Write-Log -Message "Removing Microsoft Visual Studio Code Desktop Shortcut From User Profile."
                Remove-Item $DesktopSC -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        ## Uninstall Microsoft Visual Studio Code (System Installer)
        $AppList = Get-InstalledApplication -Name 'Microsoft Visual Studio Code'        
        ForEach ($App in $AppList) {
            If ($App.UninstallString) {
                $UninstPath = $($App.UninstallString).Replace('"', '')       
                If (Test-Path -Path $UninstPath) {
                    Write-Log -Message "Found $($App.DisplayName) $($App.DisplayVersion) and a valid uninstall string, now attempting to uninstall."
                    Execute-Process -Path $UninstPath -Parameters "/VERYSILENT /NORESTART /LOG=""$configToolkitLogDir\VSCode-Uninstall.log"""
                    Start-Sleep -Seconds 5
                }
            }
        }

        ##*===============================================
        ##* POST-UNINSTALLATION
        ##*===============================================
        [string]$installPhase = 'Post-Uninstallation'


    }
    ElseIf ($deploymentType -ieq 'Repair') {
        ##*===============================================
        ##* PRE-REPAIR
        ##*===============================================
        [string]$installPhase = 'Pre-Repair'


        ##*===============================================
        ##* REPAIR
        ##*===============================================
        [string]$installPhase = 'Repair'


        ##*===============================================
        ##* POST-REPAIR
        ##*===============================================
        [string]$installPhase = 'Post-Repair'


    }
    ##*===============================================
    ##* END SCRIPT BODY
    ##*===============================================

    ## Call the Exit-Script function to perform final cleanup operations
    Exit-Script -ExitCode $mainExitCode
}
Catch {
    [int32]$mainExitCode = 60001
    [string]$mainErrorMessage = "$(Resolve-Error)"
    Write-Log -Message $mainErrorMessage -Severity 3 -Source $deployAppScriptFriendlyName
    Show-DialogBox -Text $mainErrorMessage -Icon 'Stop'
    Exit-Script -ExitCode $mainExitCode
}