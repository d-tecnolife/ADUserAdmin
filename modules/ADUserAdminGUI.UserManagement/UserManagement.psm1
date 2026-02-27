Import-Module "$PSScriptRoot\..\ADUserAdminGUI.AppState\AppState.psm1"
Import-Module "$PSScriptRoot\..\ADUserAdminGUI.PasswordUtil\PasswordUtil.psm1"
Import-Module "$PSScriptRoot\..\ADUserAdminGUI.Logging\Logging.psm1"
$script:appInfo = Get-AppInfo

<#
.SYNOPSIS
    Searches for AD users based on search criteria
.PARAMETER SearchText
    The string to perform the query with
#>
function Search-ADUserAccounts {
    [CmdletBinding()]
    param(
        [string]$SearchText
    )
    
    try {
        $appInfo = Get-AppInfo
        $domain = Get-CurrentDomain
        $dgUserList = Get-AppControl 'dgUserList'
        $txtUserCount = Get-AppControl 'txtUserCount'

        $properties = @(
            'DisplayName', 'EmailAddress', 'SamAccountName', 
            'Title', 'Department', 'EmployeeID', 
            'Enabled', 'LastLogonDate'
        )

        if ([string]::IsNullOrWhiteSpace($SearchText)) {
            $filteredUsers = @(Get-ADUser -Server $domain -Filter "*" -Properties $properties -ErrorAction Stop)
        }
        else {
            $searchTerm = "*$($SearchText.Trim())*"
            
            $filteredUsers = @(Get-ADUser -Server $domain -Properties $properties -ErrorAction Stop -Filter {
                SamAccountName -like $searchTerm -or 
                DisplayName    -like $searchTerm -or 
                EmailAddress   -like $searchTerm -or 
                Title          -like $searchTerm -or 
                Department     -like $searchTerm -or 
                EmployeeID     -like $searchTerm
            })
        }
        
        # Update UI
        $dgUserList.ItemsSource = $filteredUsers
        $dgUserList.Items.Refresh()
        $txtUserCount.Text = "$($filteredUsers.Count) users found"
        
        Write-Verbose "Found $($filteredUsers.Count) users"
    }
    catch {
        Write-Error "Failed to search AD users: $($_.Exception.Message)"
        [void][System.Windows.MessageBox]::Show(
            "Failed to search AD users: $($_.Exception.Message)",
            $appInfo.Name,
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
}

<#
.SYNOPSIS
    Creates a new Active Directory user
#>
function New-ADUserAccount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$DataFiles
    )
    
    $domain = Get-CurrentDomain
    $appInfo = Get-AppInfo
    $adConfig = Get-ADConfig
    $loggingConfig = Get-LoggingConfig
    
    $controls = @{
        GivenName = Get-AppControl 'txtCreateUserGivenName'
        Surname = Get-AppControl 'txtCreateUserSurname'
        DisplayName = Get-AppControl 'txtCreateUserDisplayName'
        Email = Get-AppControl 'txtCreateUserEmail'
        SamAccountName = Get-AppControl 'txtCreateUserSamAccountName'
        Password = Get-AppControl 'txtCreateUserPassword'
        Title = Get-AppControl 'txtCreateUserTitle'
        Phone = Get-AppControl 'txtCreateUserPhone'
        Department = Get-AppControl 'cbCreateUserDepartment'
        Location = Get-AppControl 'cbCreateUserLocation'
        Manager = Get-AppControl 'txtManagerSamName'
        BudgetCode = Get-AppControl 'txtBudgetCode'
        EmployeeID = Get-AppControl 'txtEmployeeID'
        ADPID = Get-AppControl 'txtADPID'
    }
    
    try {
        # Validate password
        if ((-not ([string]::IsNullOrWhiteSpace($controls.Password.Text)))) {
            $result = Test-PasswordComplexity -Password $controls.Password.Text
            if($result.Count -gt 0){
            $failedList = $result -join "`n• "
            [void][System.Windows.MessageBox]::Show(
                "Password does not meet complexity requirements:`n`n•$failedList",
                $appInfo.Name,
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            )
            return
            } else {
                # If password field is populated and passes Test-PasswordComplexity, password is valid
                $passwordResult = New-SecurePassword -Password $controls.Password.Text
            }
        } else {
            # If password field is not populated, generate a new secure password
            $passwordResult = New-SecurePassword
        }
        
        # Build user parameters
        $sAMAccountName = "$($controls.GivenName.Text).$($controls.Surname.Text)".ToLower()

        $selectedLocation = if ([string]::IsNullOrWhiteSpace($controls.Location.SelectedItem)) { 
            $adConfig.UserProperties.Office.Default
        } else { 
            "$($controls.Location.SelectedItem)".Trim()
        }

        $userLocation = $DataFiles.Locations | Where-Object Location -eq $selectedLocation

        $domainAsDN = Get-DomainDN
        $ouPath = "OU=$($controls.Department.SelectedItem),$($adConfig.DefaultOUs.Sync),$domainAsDN"

        # Validate user input
        $valid = @{
            GivenName         = $controls.GivenName.Text
            Surname           = $controls.Surname.Text
            DisplayName       = if ($controls.DisplayName.Text) { $controls.DisplayName.Text } else { "$($controls.GivenName.Text) $($controls.Surname.Text)" }
            EmailAddress      = if ($controls.Email.Text) { $controls.Email.Text } else { "$sAMAccountName@$domain" }
            SamAccountName    = if ($controls.SamAccountName.Text) { $controls.SamAccountName.Text } else { $sAMAccountName }
            Office            = $selectedLocation
            Title             = $controls.Title.Text
            Department        = $controls.Department.SelectedItem
			OfficePhone       = if ($controls.Phone.Text) { $controls.Phone.Text } else { $userLocation.OfficePhone }
            EmployeeID        = $controls.EmployeeID.Text
            Manager           = $controls.Manager.Text
            OtherAttributes   = @{
                'AdpAssociateId' = $controls.ADPID.Text
                'BudgetCode'     = $controls.BudgetCode.Text
            }
        }
        if(-not (Test-UserParams -UserParams $valid -OtherAttributes "OtherAttributes"))
        {
            return
        }
        # Get manager DN
        $managerDN = $null
        if(-not [string]::IsNullOrWhiteSpace($valid.Manager)){
            $managerDN = Get-ManagerDN -SamAccountName $valid.Manager
            if ($null -eq $managerDN) {
                return
                }
        }
                
        $userParams = @{
            Server            = $domain
            Name              = "$($controls.GivenName.Text) $($controls.Surname.Text)"
            GivenName         = $controls.GivenName.Text
            Surname           = $controls.Surname.Text
            DisplayName       = $valid.DisplayName
            EmailAddress      = $valid.EmailAddress
            SamAccountName    = $valid.SamAccountName
            UserPrincipalName = if ($controls.SamAccountName.Text) { "$($controls.SamAccountName.Text)@$domain" } else { "$sAMAccountName@$domain" }
            AccountPassword   = $passwordResult.Secure
            Company           = $adConfig.UserProperties.Company.Default
            Office            = $valid.Office
            StreetAddress     = $userLocation.StreetAddress
			City              = $userLocation.City
			State             = $userLocation.State
			Country           = $userLocation.Country
			PostalCode        = $userLocation.PostalCode
            Title             = $valid.Title
            Department        = $valid.Department
			OfficePhone       = $valid.OfficePhone
            EmployeeID        = $valid.EmployeeID
            Manager           = $managerDN
            Enabled           = $true
            PasswordNeverExpires = $true
            Path              = $ouPath
            OtherAttributes   = @{
                'AdpAssociateId' = $controls.ADPID.Text
                'BudgetCode'     = $controls.BudgetCode.Text
            }
        }

        # --- CHECK EXISTING USER START ---
        # Check for existing user using key property
        $keyProp = $adConfig.KeyProperty
        $keyValue = $userParams.$keyProp
        $existingFilter = "$keyProp -eq '$keyValue'"
        $existingUser = Get-ADUser -Server $domain -Filter $existingFilter -ErrorAction SilentlyContinue
        $readablePath = Get-ReadablePath -Path $ouPath

        # If existingUser is not null, it means user was found
        if ($null -ne $existingUser) {
            [void][System.Windows.MessageBox]::Show(
                "AD User with $($keyProp): $($keyValue) already exists in $domain under $(Get-ReadablePath -Path $existingUser.DistinguishedName)",
                $appInfo.Name,
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            )
            return
        }
        
        # Check for existing user using sAMAccountName (Must be unique)
        try{
            $existingSam = Get-ADUser -Server $domain -Identity $userParams.SamAccountName -ErrorAction Stop
        }
        catch{
            $existingSam = $null
        }

        # If existingSam is not null, it means user was found
        if ($null -ne $existingSam) {
            [void][System.Windows.MessageBox]::Show(
                "AD User with sAMAccountName: $($userParams.SamAccountName) already exists in $domain under $(Get-ReadablePath -Path $existingSam.DistinguishedName)",
                $appInfo.Name,
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            )
            return
        }
        # --- CHECK EXISTING USER END ---

        Write-Host "Creating AD user: $($userParams.SamAccountName)" -ForegroundColor Cyan
        New-ADUser @userParams -ErrorAction Stop
        
        # Set clipboard to set password
        Set-Clipboard -Value $passwordResult.Plain

        # --- LOGGING START ---
        # Create a copy of params to log, display manager sAMAccountName instead of DN, hide password
        $logParams = $userParams.Clone()
        #$logParams.AccountPassword = $setPassword
        $logParams.Remove('AccountPassword')
        $logParams.Manager = $valid.Manager
        
        # Convert hashtable to string, and sort it for readable logging
        $paramString = ($logParams.Keys | Sort-Object | ForEach-Object { 
            "`n    [PROPERTY] $_`: '$($logParams[$_])'" 
        }) -join ""

        $logMessage = "`r`nCreated User: $($userParams.SamAccountName)" + $paramString
        Write-Log -Caller "New-ADUserAccount" -Level "Info" -Message $logMessage

        Write-Host "User created!`nDetails written to log at $($loggingConfig.LogPath)"
        Write-Host
        [System.Windows.MessageBox]::Show(
            "User $($userParams.DisplayName) successfully created in:`n`nDomain: $domain`n$readablePath`n`
            Temporary Password: $($passwordResult.Plain)`nPassword has been copied to your clipboard.",
            $appInfo.Name,
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information
        )
    }
    catch {
        Write-Error "Failed to create AD user: $($_.Exception.Message)"
        [void][System.Windows.MessageBox]::Show(
            "Failed to create user: $($_.Exception.Message)",
            $appInfo.Name,
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
        return $false
    }
}

<#
.SYNOPSIS
    Updates an existing Active Directory user
#>
function Update-ADUserAccount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$DataFiles,
        [Parameter()]
        [bool]$Validate = $true
    )
    
    # Use AppState getters for consistency
    $domain = Get-CurrentDomain
    $adConfig = Get-ADConfig
    $appInfo = Get-AppInfo
    $loggingConfig = Get-LoggingConfig
    
    # Get the selected user from the DataGrid
    $dgUserList = Get-AppControl 'dgUserList'
    $selectedUser = $dgUserList.SelectedItem
    
    if ($null -eq $selectedUser) {
        [void][System.Windows.MessageBox]::Show(
            "No user selected. Please select a user from the list first.",
            $appInfo.Name,
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        )
        return $false
    }
    
    try {
        # Establish domain context for OU paths
        $domainAsDN = Get-DomainDN
        
        # Determine current and target OU
        $currentOu = ($selectedUser.DistinguishedName -Split ',', 2)[1]
        $targetDept = (Get-AppControl 'cbEditUserDepartment').SelectedItem
        if (-not $targetDept){
            $targetDept = $selectedUser.Department
        }
        # Set base OU path based on Sync status
        if ($currentOu -like "*sync*") {
            $baseOU = $adConfig.DefaultOUs.Sync
        } else {
            $baseOU = $adConfig.DefaultOUs.NonSync
        }
        $ouPath = "OU=$targetDept,$baseOU,$domainAsDN"

        # Location info lookup
        $selectedLocName = (Get-AppControl 'cbEditUserLocation').SelectedItem
        $userLocation = $DataFiles.Locations | Where-Object Location -eq $selectedLocName

        # Validation hashtable
        $valid = @{
            GivenName         = (Get-AppControl 'txtEditGivenName').Text
            Surname           = (Get-AppControl 'txtEditSurname').Text
            DisplayName       = (Get-AppControl 'txtEditDisplayName').Text
            EmailAddress      = (Get-AppControl 'txtEditEmail').Text
            UserPrincipalName = (Get-AppControl 'txtEditEmail').Text
            SamAccountName    = (Get-AppControl 'txtEditSamAccountName').Text
            Office            = $selectedLocName
            StreetAddress     = $userLocation.StreetAddress
            City              = $userLocation.City
            State             = $userLocation.State
            Country           = $userLocation.Country
            PostalCode        = $userLocation.PostalCode
            Title             = (Get-AppControl 'txtEditTitle').Text
            Department        = $targetDept
            OfficePhone       = (Get-AppControl 'txtEditPhone').Text
            Manager           = (Get-AppControl 'txtEditManagerSamName').Text
            Replace           = @{
                'AdpAssociateId' = (Get-AppControl 'txtEditADPID').Text
                'BudgetCode'     = (Get-AppControl 'txtEditBudgetCode').Text
            }
            Enabled           = (Get-AppControl 'chkEditEnabled').IsChecked
        }

        # Validate parameters
        if ($Validate -and (-not (Test-UserParams -UserParams $valid -OtherAttributes "Replace"))) {
            return
        }

        # Handle manager DN resolution
        $managerDN = $null
        if (-not [string]::IsNullOrWhiteSpace($valid.Manager)) {
            $managerDN = Get-ManagerDN -SamAccountName $valid.Manager
            if ($null -eq $managerDN) { return }
        }

        # Check for existing user using sAMAccountName ONLY if it changed
        if ($valid.SamAccountName -ne $selectedUser.SamAccountName) {
            try{
                $existingSam = Get-ADUser -Server $domain -Identity $valid.SamAccountName -ErrorAction Stop
            }
            catch{
                $existingSam = $null
            }
            
            # If existingSam is not null, it means another user already has this SAMAccountName
            if ($null -ne $existingSam) {
                [void][System.Windows.MessageBox]::Show(
                    "AD User with sAMAccountName: $($valid.SamAccountName) already exists in $domain under $(Get-ReadablePath -Path $existingSam.DistinguishedName)",
                    $appInfo.Name,
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
                return
            }
        }

        # Build final parameter set for Set-ADUser
        $userParams = @{
            Server            = $domain
            GivenName         = $valid.GivenName
            Surname           = $valid.Surname
            DisplayName       = $valid.DisplayName
            EmailAddress      = $valid.EmailAddress
            UserPrincipalName = $valid.UserPrincipalName
            SamAccountName    = $valid.SamAccountName
            Office            = $valid.Office
            PostalCode        = $valid.PostalCode
            Title             = $valid.Title
            Department        = $valid.Department
            OfficePhone       = $valid.OfficePhone
            Manager           = $managerDN
            Replace           = $valid.Replace
            Enabled           = $valid.Enabled
        }

        Write-Host "Updating AD user: $($selectedUser.SamAccountName)" -ForegroundColor Cyan
        
        # Use KeyProperty from config to identify the user uniquely
        $keyProp = $adConfig.KeyProperty
        $keyValue = $selectedUser.$keyProp
        $user = Get-SelectedADUser -KeyValue $keyValue

        $user | Set-ADUser @userParams -ErrorAction Stop
        
        # Handle password update
        $inputPassword = (Get-AppControl 'txtEditUserPassword').Text
        if (-not [string]::IsNullOrWhiteSpace($inputPassword)) {
            $newPassword = New-SecurePassword -Password $inputPassword
            Set-ADAccountPassword -Server $domain -Identity $user.DistinguishedName -Reset -NewPassword $newPassword.Secure -ErrorAction Stop
            Set-Clipboard $newPassword.Plain
        }

        # Compare previous OU to new OU path, only move if they are different (Requires distinguishedName)
        if ($currentOu -ne $ouPath) {
            Move-ADObject -Server $domain -Identity $user.DistinguishedName -TargetPath $ouPath -ErrorAction Stop
            # Refresh object reference after move
            $user = Get-SelectedADUser -KeyValue $user.$keyProp
        }

        # Handle object CN rename
        if ($user.CN -ne $valid.DisplayName) {
            Rename-ADObject -Server $domain -Identity $user.DistinguishedName -NewName $valid.DisplayName -ErrorAction Stop
        }

        # --- LOGGING START ---
        $changeLog = New-Object System.Collections.Generic.List[string]

        # Map selectedUser key to the used key name in function
        $propertyMap = @{
            'Office'      = 'PhysicalDeliveryOfficeName'
            'OfficePhone' = 'TelephoneNumber'
        }
        
        # Compare $valid (new values) to $script:selectedUser (old values)
        foreach ($key in $valid.Keys) {
            
            # OtherAttributes
            if ($key -eq 'Replace') {
                foreach ($attrKey in $valid.Replace.Keys) {
                    $oldVal = "$($user.$attrKey)"
                    $newVal = "$($valid.Replace.$attrKey)"
                    
                    if ($oldVal -ne $newVal) {
                        $changeLog.Add("    [MODIFIED] $($attrKey): '$oldVal' -> '$newVal'")
                    }
                }
                continue
            }
            
            # Manager
            if ($key -eq 'Manager') {
                $currentManagerSam = ""
                if ($script:selectedUser.Manager) {
                    try {
                        $currentManagerUser = Get-ADUser -Server $domain -Identity $user.Manager -Properties SamAccountName -ErrorAction Stop
                        $currentManagerSam = $currentManagerUser.SamAccountName
                    } catch { $currentManagerSam = "Unknown/Error" }
                }
                
                if ($currentManagerSam -ne $valid.Manager) {
                    $changeLog.Add("    [MODIFIED] Manager: '$currentManagerSam' -> '$($valid.Manager)'")
                }
                continue
            }
        
            # Use AD key name for selectedUser
            $adPropertyName = if ($propertyMap.ContainsKey($key)) { $propertyMap[$key] } else { $key }
            
            $oldValue = "$($user.$adPropertyName)"
            $newValue = "$($valid.$key)"
        
            if ($newValue -ne $oldValue) {
                $changeLog.Add("    [MODIFIED] $($key): '$oldValue' -> '$newValue'")
            }
        }

        # Format the log message, then write it
        if ($changeLog.Count -gt 0) {
            $changeString = "`n" + ($changeLog -join "`n")
            $logMessage = "`r`nUser: $($script:selectedUser.SamAccountName)" + $changeString
            Write-Log -Caller "Update-ADUserAccount" -Level "Info" -Message $logMessage
        }
        # --- LOGGING END ---
         
        Write-Host "User updated!`nDetails written to log at $($loggingConfig.LogPath)"
        Write-Host
        [System.Windows.MessageBox]::Show(
            "User updated!`nIf password was set, the value has been copied into your clipboard.",
            $appInfo.Name,
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information
        )
    }
    catch {
        Write-Log -Caller "Update-ADUserAccount" -Level "Error" -Message "Failed to update AD user.`nException: $($_.Exception.Message)"
        [void][System.Windows.MessageBox]::Show(
            "Failed to update AD user: $($_.Exception.Message)",
            $appInfo.Name,
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
}

<#
.SYNOPSIS
    Validates user input against config rules and returns cause of invalid input.
.PARAMETER FieldName
    Name of the field to validate
.PARAMETER Value
    Value to validate
.EXAMPLE
    Test-UserField -FieldName EmployeeID -Value YUF676767
#>
function Test-UserField {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FieldName,
        
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )
    
    $errors = @()
    $adConfig = Get-ADConfig
    $rule = $adConfig.UserProperties.$FieldName
    
    if (-not $rule) {
        Write-Verbose "No validation rule found for: $FieldName"
        return @{
            IsValid = $true
            Errors = $errors
        }
    }

    # Check if required and empty
    if ([string]::IsNullOrWhiteSpace($Value) -and $rule.Required -eq $true) {
        $errors += "Please fill in the required field: $FieldName"
        return @{
            IsValid = $false
            Errors = $errors
        }
    }

    # Skip validation if empty and not required
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @{
            IsValid = $true
            Errors = $errors
        }
    }

    # Validate format (only if value exists and format is specified)
    if ($rule.Format -and $Value -notmatch $rule.Format) {
        $errorMessage = if ($rule.ContainsKey('Description') -and $rule.Description) {
            "Validation failed for $($FieldName): $($rule.Description)"
        } else {
            "Validation failed for $($FieldName): Invalid format"
        }
        $errors += $errorMessage
    }
    
    # Validate max length
    if ($rule.ContainsKey('MaxLength') -and $rule.MaxLength -gt 0 -and $Value.Length -gt $rule.MaxLength) {
        $errors += "Value exceeds maximum length of $($rule.MaxLength) for $FieldName"
    }
    
    return @{
        IsValid = ($errors.Count -eq 0)
        Errors  = $errors
    }
}

<#
.SYNOPSIS
    Validates user parameters using Test-UserField
.PARAMETER UserParams
    Hashtable of user parameters
.PARAMETER OtherAttributes
    String that determines the name of the OtherAttributes key holding custom attributes on the AD user
.EXAMPLE
    Test-UserParams -UserParams $userParams -OtherAttributes $otherAttributes
#>
function Test-UserParams {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$UserParams,

        [Parameter(Mandatory = $true)]
        [String]$OtherAttributes
    )
    
    $errors = @()
    $appInfo = Get-AppInfo

    foreach ($key in $UserParams.Keys) {
        
        # Check if key is a container for other attributes e.g. "Replace" or "OtherAttributes"
        if ($key -eq $OtherAttributes) {
            $nestedHash = $UserParams[$key]
            
            # Iterate through the nested hashtable
            if ($nestedHash -is [System.Collections.IDictionary]) {
                foreach ($nestedKey in $nestedHash.Keys) {
                    $value = if ($null -ne $nestedHash[$nestedKey]) { $nestedHash[$nestedKey].ToString() } else { '' }
                    # Validate
                    $result = Test-UserField -FieldName $nestedKey -Value $value
                    if (-not $result.IsValid) {
                        $errors += $result.Errors
                    }
                }
            }
        } 
        else {
            # Skipping fields that shouldn't be text-validated (like boolean)
            if ($key -ne 'Enabled') {
                # Convert value to string for validation
                $value = if ($null -ne $UserParams[$key]) { $UserParams[$key].ToString() } else { '' }

                $result = Test-UserField -FieldName $key -Value $value
                if (-not $result.IsValid) {
                    $errors += $result.Errors
                }
            }
        }
    }

    # Reporting
    if ($errors.Count -gt 0) {
        $errorText = "• " + ($errors -join "`n• ")
        [void][System.Windows.MessageBox]::Show(
            $errorText,
            $appInfo.Name,
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        )
        return $false
    }
    
    return $true
}


<#
.SYNOPSIS
    Initializes the edit page with selected user data
#>
function Initialize-EditPage {
    [CmdletBinding()]
    param()

    # Helper function to handle setting textboxes
    function Set-ControlText {
        param(
            [string]$ControlName,
            [string]$Value
        )
        $control = Get-AppControl $ControlName
        if ($null -ne $control) {
            $control.Text = if ($Value) { $Value } else { "" }
        } else {
            Write-Warning "Control '$ControlName' not found - skipping"
        }
    }
    
    # Helper for dropdowns
    function Set-ControlSelectedItem {
        param(
            [string]$ControlName,
            $Value
        )
        $control = Get-AppControl $ControlName
        if ($null -ne $control) {
            $control.SelectedItem = $Value
        } else {
            Write-Warning "Control '$ControlName' not found - skipping"
        }
    }
    
    # Helper for checkbox
    function Set-ControlChecked {
        param(
            [string]$ControlName,
            [bool]$Value
        )
        $control = Get-AppControl $ControlName
        if ($null -ne $control) {
            $control.IsChecked = $Value
        } else {
            Write-Warning "Control '$ControlName' not found - skipping"
        }

    }
    $dgUserList = Get-AppControl 'dgUserList'
    $selectedUser = $dgUserList.SelectedItem
    $appInfo = Get-AppInfo
    $adConfig = Get-ADConfig
    $keyProp = $adConfig.KeyProperty

    if ($null -eq $selectedUser) {
        return
    }
    
    try {
        $fullUser = Get-SelectedADUser -KeyValue $selectedUser.$keyProp

        $managerSamName = ""
        if ($fullUser.Manager) {
            try {
                $domain = Get-CurrentDomain
                $managerUser = Get-ADUser -Server $domain -Identity $fullUser.Manager -Properties SamAccountName -ErrorAction Stop
                $managerSamName = $managerUser.SamAccountName
            }
            catch {
                Write-Warning "Could not retrieve manager SAMAccountName: $($_.Exception.Message)"
                $managerSamName = ""
            }
        }

        Set-ControlText 'txtEditHeaderDisplayName' $fullUser.DisplayName
        Set-ControlText 'txtEditGivenName' $fullUser.GivenName
        Set-ControlText 'txtEditSurname' $fullUser.Surname
        Set-ControlText 'txtEditDisplayName' $fullUser.DisplayName
        Set-ControlText 'txtEditSamAccountName' $fullUser.SamAccountName
        Set-ControlText 'txtEditEmail' $fullUser.EmailAddress
        Set-ControlText 'txtEditTitle' $fullUser.Title
        Set-ControlSelectedItem 'cbEditUserDepartment' $fullUser.Department
        Set-ControlSelectedItem 'cbEditUserLocation' $fullUser.PhysicalDeliveryOfficeName
        Set-ControlText 'txtEditPhone' $fullUser.TelephoneNumber
        Set-ControlText 'txtEditEmployeeID' $fullUser.EmployeeID
        Set-ControlText 'txtEditHeaderKey' $fullUser.EmployeeID
        Set-ControlText 'txtEditManagerSamName' $managerSamName
        Set-ControlText 'txtEditADPID' $fullUser.AdpAssociateId
        Set-ControlText 'txtEditBudgetCode' $fullUser.BudgetCode
        Set-ControlChecked 'chkEditEnabled' $fullUser.Enabled
        Set-ControlText 'txtEditLastLogon' $(if ($fullUser.LastLogonDate) { $fullUser.LastLogonDate.ToString() } else { "Never" })
        
        Write-Verbose "Initialized edit page for user: $($fullUser.SamAccountName)"
    }
    catch {
        Write-Log -Caller "Initialize-EditPage" -Level "Error" -Message "Failed to load user details for edit page.`nException: $($_.Exception.Message)"
        [void][System.Windows.MessageBox]::Show(
            "Failed to load user details: $($_.Exception.Message)",
            $appInfo.Name,
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
}

# Helper Functions

<#
.SYNOPSIS
    Fetches all properties required for editing and logging a specific user.
#>
function Get-SelectedADUser {
    param(
        [Parameter(Mandatory = $true)]
        [string]$KeyValue
    )
    $adConfig = Get-ADConfig
    $keyProp = $adConfig.KeyProperty
    $domain = Get-CurrentDomain
    $filter = "$keyProp -eq '$KeyValue'"
    $properties = @(
        'StreetAddress', 'City', 'State', 'PostalCode', 'Country',
        'Company', 'EmployeeID', 'Manager', 'Description', 
        'GivenName', 'Surname', 'DisplayName', 'EmailAddress',
        'SamAccountName','Title','Department','TelephoneNumber',
        'PhysicalDeliveryOfficeName','BudgetCode', 'AdpAssociateId','Enabled',
        'LastLogonDate', 'DistinguishedName', 'CN'
    )
    $user = Get-ADUser -Server $domain -Filter $filter -Properties $properties -ErrorAction SilentlyContinue

    return $user
}

<#
.SYNOPSIS
    Returns a manager's distinguished name
.PARAMETER Domain
    The domain to perform the query for the manager on
#>
function Get-ManagerDN {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SamAccountName
    )
    $appInfo = Get-AppInfo
    $domain = Get-CurrentDomain

    try {
        $managerUser = Get-ADUser -Server $domain -Identity $SamAccountName -ErrorAction Stop
        return $managerUser.DistinguishedName
    }
    catch {
        [void][System.Windows.MessageBox]::Show(
            "Manager with SAMAccountName '$SamAccountName' not found.",
            $appInfo.Name,
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        )
        return $null
    }
}

<#
.SYNOPSIS
    Converts a DN path into a readable, directory style format
.PARAMETER Path
    The path to convert
#>
function Get-ReadablePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $Parts = @($Path -split ',' | Where-Object { $_ -like 'OU=*' } | ForEach-Object { $_ -replace '^OU=', '' })
    [array]::Reverse($Parts)
    $readablePath = $Parts -join '\'

    return $readablePath
}

<#
.SYNOPSIS
    Gets the domain string at the end of a DN
.PARAMETER Domain
    The domain to convert into a DN format
#>
function Get-DomainDN {
    [CmdletBinding()]
    param()
    $domain = Get-CurrentDomain
    $domainDN = (Get-ADDomain -Server $domain -ErrorAction Stop).DistinguishedName
    return "OU=$($domainDN -replace 'DC=', '' -replace ',', '-'),$domainDN"
}