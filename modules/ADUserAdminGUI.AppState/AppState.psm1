<#
.SYNOPSIS
    Centralized application state management module for ADUserAdminGUI
.DESCRIPTION
    Provides a single source of truth for configuration, controls, domain, and other shared state.
#>

$script:config = $null
$script:controls = @{}
$script:currentDomain = $null
$script:admin = $null
$script:rootPath = $null


# Init functions
<#
.SYNOPSIS
    Initializes the application state with configuration
.PARAMETER Config
    The configuration hashtable loaded from Config.psd1
.PARAMETER RootPath
    The root path of the application module
#>
function Initialize-AppState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )
        $script:config = $Config
        $script:rootPath = $RootPath
        $script:currentDomain = ($Config.ActiveDirectory.Domains)[0]  # Set initial domain
        $script:admin = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        
        Write-Verbose "App state initialized with domain: $script:currentDomain"
}

<#
.SYNOPSIS
    Sets the UI controls hashtable
.PARAMETER Controls
    The controls hashtable from Initialize-UI
#>
function Set-AppControls {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Controls
    )
    
    $script:controls = $Controls
    
    # Set up domain change event handler
    if ($script:controls.cbDomain) {
        $script:controls.cbDomain.Add_SelectionChanged({
            $newDomain = $script:controls.cbDomain.SelectedItem
            if ($newDomain) {
                $script:currentDomain = $newDomain
                Write-Verbose "Domain changed to: $script:currentDomain"
            }
        })
    }
    
    Write-Verbose "Controls set. Found $($Controls.Count) controls."
}


# Getters
<#
.SYNOPSIS
    Gets the entire configuration hashtable
#>
function Get-AppConfig {
    [CmdletBinding()]
    param()
    return $script:config
}

<#
.SYNOPSIS
    Gets application information
#>
function Get-AppInfo {
    [CmdletBinding()]
    param()
    return $script:config.Application
}

<#
.SYNOPSIS
    Gets Active Directory configuration
#>
function Get-ADConfig {
    [CmdletBinding()]
    param()
    return $script:config.ActiveDirectory
}

<#
.SYNOPSIS
    Gets UI configuration
#>
function Get-UIConfig {
    [CmdletBinding()]
    param()
    return $script:config.UI
}

<#
.SYNOPSIS
    Gets authentication configuration
#>
function Get-AuthConfig {
    [CmdletBinding()]
    param()
    return $script:config.Authentication
}

<#
.SYNOPSIS
    Gets data sources configuration
#>
function Get-DataSourcesConfig {
    [CmdletBinding()]
    param()
    return $script:config.DataSources
}

<#
.SYNOPSIS
    Gets logging configuration
#>
function Get-LoggingConfig {
    [CmdletBinding()]
    param()
    return $script:config.Logging
}

<#
.SYNOPSIS
    Gets password policy
#>
function Get-PasswordPolicy {
    [CmdletBinding()]
    param()
    return $script:config.ActiveDirectory.PasswordPolicy
}

<#
.SYNOPSIS
    Gets a specific UI control by name
.PARAMETER Name
    The name of the control to retrieve
#>
function Get-AppControl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
    $control = $script:controls[$Name]
    if ($null -eq $control) {
        Write-Warning "Control '$Name' not found in app state"
        return $null 
    }
    return $control
}

<#
.SYNOPSIS
    Gets all UI controls
#>
function Get-AppControls {
    [CmdletBinding()]
    param()
    return $script:controls
}

<#
.SYNOPSIS
    Gets the currently selected domain
#>
function Get-CurrentDomain {
    [CmdletBinding()]
    param()
    return $script:currentDomain
}

<#
.SYNOPSIS
    Sets the current domain (also updates the UI dropdown)
.PARAMETER Domain
    The domain to set as current
#>
function Set-CurrentDomain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )
    
    $script:currentDomain = $Domain
    
    # Update UI if control exists
    if ($script:controls.cbDomain) {
        $script:controls.cbDomain.SelectedItem = $Domain
    }
    
    Write-Verbose "Domain set to: $Domain"
}

<#
.SYNOPSIS
    Gets the current admin username
#>
function Get-Admin {
    [CmdletBinding()]
    param()
    return $script:admin
}

<#
.SYNOPSIS
    Gets the application root path
#>
function Get-AppRootPath {
    [CmdletBinding()]
    param()
    return $script:rootPath
}


# Utility functions
<#
.SYNOPSIS
    Tests if AppState has been initialized
#>
function Test-AppStateInitialized {
    [CmdletBinding()]
    param()
    return ($null -ne $script:config)
}

<#
.SYNOPSIS
    Gets a config value by path (e.g., "ActiveDirectory.Domains")
.PARAMETER Path
    Dot-separated path to the config value
#>
function Get-ConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    $parts = $Path -split '\.'
    $current = $script:config
    
    foreach ($part in $parts) {
        if ($current -is [hashtable] -and $current.ContainsKey($part)) {
            $current = $current[$part]
        } else {
            return $null
        }
    }
    
    return $current
}