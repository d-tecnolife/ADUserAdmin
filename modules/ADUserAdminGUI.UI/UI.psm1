Import-Module "$PSScriptRoot\..\ADUserAdminGUI.AppState\AppState.psm1"
$script:window = $null
$script:pages = $null
$script:navButtons = $null
$script:btnPageMap = $null

<#
.SYNOPSIS
    Initializes the WPF UI by loading XAML and creating control references.
#>
function Initialize-UI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$XAMLPath
    )
    
    $uiConfig = Get-UIConfig
        
    Write-Verbose "Loading XAML from: $XAMLPath..."
    $inputXAML = Get-Content -Path $XAMLPath -Raw
    $inputXAML = $inputXAML -replace 'mc:Ignorable="d"', '' `
        -replace 'x:Name=', 'Name=' `
        -replace 'x:Class=".*?"', '' `
        -replace '^<Win.*', '<Window'
    [XML]$XAML = $inputXAML
        
    $reader = New-Object System.Xml.XmlNodeReader $XAML
    $script:window = [Windows.Markup.XAMLReader]::Load($reader)
        
    # Set window title from config
    $script:window.Title = $uiConfig.WindowTitle
        
    Write-Verbose "Creating control references..."
    $controls = @{}
    $XAML.SelectNodes("//*[@Name]") | ForEach-Object {
        $control = $script:window.FindName($_.Name)
        if ($control) {
            $controls[$_.Name] = $control
            Write-Verbose "  Set control: $($_.Name)"
        }
    }

    Initialize-PageMappings -Controls $controls        
    Write-Verbose "UI initialization complete. Found $($controls.Count) controls."
    return $controls
}

<#
.SYNOPSIS
    Populates comboboxes, initial field values, and other UI elements with data
#>
function Initialize-Data {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Departments,
        
        [Parameter(Mandatory = $true)]
        [array]$Locations,

        [Parameter(Mandatory = $true)]
        [string]$IconPath
    )
        
    Write-Verbose "Configuring UI elements..."
    (Get-AppControl 'cbCreateUserDepartment').ItemsSource = $Departments.Department
    (Get-AppControl 'cbCreateUserLocation').ItemsSource = $Locations.Location
    (Get-AppControl 'cbEditUserDepartment').ItemsSource = $Departments.Department
    (Get-AppControl 'cbEditUserLocation').ItemsSource = $Locations.Location

    $adConfig = Get-ADConfig
    (Get-AppControl 'cbDomain').ItemsSource = $adConfig.Domains
    (Get-AppControl 'mdLogo').source = $IconPath
    
    Initialize-UtilList

    Write-Verbose "Field population complete."
}

<#
.SYNOPSIS
    Initializes page and navigation mappings
.DESCRIPTION
    Maps XAML variables for usage in the module
#>
function Initialize-PageMappings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Controls
    )
    
    $script:pages = @(
        $Controls.dashboardPage,
        $Controls.usersPage,
        $Controls.syncPage,
        $Controls.adminPage,
        $Controls.utilPage,
        $Controls.createUserPage,
        $Controls.editUserPage
    )
    
    $script:navButtons = @(
        $Controls.btnUsers,
        $Controls.btnDashboard,
        $Controls.btnSync,
        $Controls.btnAdmin,
        $Controls.btnUtilities
    )
    
    $script:btnPageMap = @{
        ($Controls.btnUsers)            = $Controls.usersPage
        ($Controls.btnDashboard)        = $Controls.dashboardPage
        ($Controls.btnSync)             = $Controls.syncPage
        ($Controls.btnAdmin)            = $Controls.adminPage
        ($Controls.btnUtilities)        = $Controls.utilPage
        ($Controls.btnCreateUser)       = $Controls.createUserPage
        ($Controls.btnEditUser)         = $Controls.editUserPage
        ($Controls.btnCreateToUserList) = $Controls.usersPage
        ($Controls.btnEditToUserList)   = $Controls.usersPage
    }
}

<#
.SYNOPSIS
    Initializes the utilities page
.DESCRIPTION
    Loads all available utilities into the utilities list and sets up selection handling
#>
function Initialize-UtilList {
    [CmdletBinding()]
    param()

    $lsUtilList = Get-AppControl 'lsUtilList'
    
    $utilities = @(
        @{Name="Field Normalisation (WIP)"; Icon="Broom"},
        @{Name="GUID Converter (WIP)"; Icon="Hexadecimal"}
    )

    foreach ($util in $utilities) {
        $listItem = New-Object System.Windows.Controls.ListBoxItem

        $stackPanel = New-Object System.Windows.Controls.StackPanel
        $stackPanel.Orientation = "Horizontal"
        $stackPanel.Margin = "8,12"
        
        # Icon
        $icon = New-Object MaterialDesignThemes.Wpf.PackIcon
        $icon.Kind = $util.Icon
        $icon.Width = 24
        $icon.Height = 24
        $icon.VerticalAlignment = "Center"
        $icon.Margin = "0,0,16,0"
        
        # Text
        $textBlock = New-Object System.Windows.Controls.TextBlock
        $textBlock.Text = $util.Name
        $textBlock.VerticalAlignment = "Center"
        $textBlock.FontSize = 14
        
        # Add to StackPanel
        $stackPanel.Children.Add($icon) | Out-Null
        $stackPanel.Children.Add($textBlock) | Out-Null
 
        $listItem.Content = $stackPanel
        $listItem.Tag = $util.Name 
        
        $lsUtilList.Items.Add($listItem) | Out-Null
    }

    Hide-UtilContent
    
    # Handle selection change
    $lsUtilList.Add_SelectionChanged({
        if ($this.SelectedItem) {
            $selectedName = $this.SelectedItem.Tag
            try {
                (Get-AppControl 'utilPageSelectedItem').Text = $selectedName
                
                # Load content based on selection
                switch ($selectedName) {
                    "Field Normalisation (WIP)" {
                        Show-FieldNormalisationContent
                    }
                    "GUID Converter (WIP)" {
                        Show-GUIDConverterContent
                    }
                }
            }
            catch {
                Write-Warning "Error switching utility page: $_"
            }
        }
    })
}

<#
.SYNOPSIS
    Shows the content for the Field Normalisation utility
.DESCRIPTION
    Displays the UI elements and logic for the Field Normalisation utility
#>
function Show-FieldNormalisationContent {
    [CmdletBinding()]
    param()
    
    Hide-UtilContent
    (Get-AppControl 'utilPageSelectedItem').Text = "Field Normalisation"
    (Get-AppControl 'utilPageSubtitle').Text = "Tool to standardize and clean user data fields."
    (Get-AppControl 'utilPageFieldNormalisation').Visibility = "Visible"
}

<#
.SYNOPSIS
    Shows the content for the GUID Converter utility
.DESCRIPTION
    Displays the UI elements and logic for the GUID Converter utility
#>
function Show-GUIDConverterContent {
    [CmdletBinding()]
    param()
    
    Hide-UtilContent
    (Get-AppControl 'utilPageSelectedItem').Text = "GUID Converter"
    (Get-AppControl 'utilPageSubtitle').Text = "Tool to convert user identifiers between formats."
    (Get-AppControl 'utilPageGUIDConverter').Visibility = "Visible"
}

<#
.SYNOPSIS
    Hides all utility content panels
#>
function Hide-UtilContent {
    [CmdletBinding()]
    param()
    
    (Get-AppControl 'utilPageGUIDConverter').Visibility = "Collapsed"
    (Get-AppControl 'utilPageFieldNormalisation').Visibility = "Collapsed"
    (Get-AppControl 'utilPageSelectedItem').Text = "Select a utility"
    (Get-AppControl 'utilPageSubtitle').Text = "Choose an option from the left panel"
}

<#
.SYNOPSIS
    Initialize data sources according to selected domain
.PARAMETER DataFiles
    A hashtable of datafiles (from the config) that will be loaded
#>
function Update-DataSources {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$DataFiles
    )

    try {
        (Get-AppControl 'cbCreateUserLocation').ItemsSource = $DataFiles.Locations.Location
        (Get-AppControl 'cbCreateUserDepartment').ItemsSource = $DataFiles.Departments.Department
    }
    catch {
        Write-Error "Failed to initialize data sources: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Switches the active page in the UI
.PARAMETER ActiveButton
    The button that was clicked to trigger the page switch
#>
function Switch-UIPage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $ActiveButton
    )
    
    try {
        $pages = Get-UIPages
        $navButtons = Get-UINavButtons
        $btnPageMap = Get-UIPageMap
        
        # Hide all pages
        foreach ($page in $pages) {
            if ($null -ne $page) {
                $page.Visibility = "Collapsed"
            }
        }
        
        # Show active page
        $targetPage = $btnPageMap[$ActiveButton]
        if ($null -ne $targetPage) {
            $targetPage.Visibility = "Visible"
            Write-Verbose "Switched to page for button: $($ActiveButton.Name)"
        }
        
        # Update navigation button highlights
        if ($navButtons -contains $ActiveButton) {
            foreach ($btn in $navButtons) {
                if ($null -ne $btn) {
                    $btn.Background = [System.Windows.Media.Brushes]::Transparent
                }
            }
            
            $ActiveButton.Background = New-Object System.Windows.Media.SolidColorBrush(
                [System.Windows.Media.Color]::FromRgb(59, 66, 82)
            )
        }
    }
    catch {
        Write-Error "Failed to switch page: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Gets the main window object
#>
function Get-UIWindow {
    [CmdletBinding()]
    param()
    return $script:window
}

<#
.SYNOPSIS
    Gets all page controls
#>
function Get-UIPages {
    [CmdletBinding()]
    param()
    return $script:pages
}

<#
.SYNOPSIS
    Gets all navigation button controls
#>
function Get-UINavButtons {
    [CmdletBinding()]
    param()
    return $script:navButtons
}

<#
.SYNOPSIS
    Gets the button-to-page mapping hashtable
#>
function Get-UIPageMap {
    [CmdletBinding()]
    param()
    return $script:btnPageMap
}

<#
.SYNOPSIS
    Shows the main window as a dialog
#>
function Show-UIWindow {
    [CmdletBinding()]
    param()
    
    if ($null -eq $script:window) {
        throw "UI window has not been initialized. Call Initialize-UI first."
    }
    
    $script:window.ShowDialog() | Out-Null
}