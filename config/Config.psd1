@{
    Application     = @{
        Name        = 'Active Directory User Administration Tool'
        Version     = '1.0.2'
        Publisher   = 'Contoso'
        Description = 'GUI tool for ADUserAdmin'
    }

    Authentication = @{
        ClientId = ''
        Secret = ''
        TenantId = ''
    }

    ActiveDirectory = @{
        Domains        = @(
            'contoso.com'
            'contoso2.com'
        )
        SyncServers = @(
            'sync.contoso.com'
        )
        DefaultOUs      = @{
            Sync = 'OU=Sync,OU=Departments'
            NonSync = "OU=Departments"
        }
        KeyProperty = 'EmployeeID'
        UserProperties = @{
            AdpAssociateId               = @{
                Required = $true
                Format = '^[a-zA-Z0-9]+$'
                MaxLength = 10
                Description = 'Alphanumeric, no spaces or special characters'
            }
            BudgetCode                   = @{
                Required = $true
                Format = '^[a-zA-Z0-9\-]+$'
                MaxLength = 20
                Description = 'Alphanumeric with hyphens allowed'
            }
            Company                      = @{
                Required = $false
                Default = 'Contoso'
                Format = '^.+$'
                MaxLength = 64
                Description = 'Any non-empty string'
            }
            Department                   = @{
                Required = $true
            }
            DisplayName                  = @{
                Required = $false
                Format = '^[a-zA-Z0-9 \-]+$'
                MaxLength = 64
                Description = 'Alphanumeric with spaces and hyphens allowed'
            }
            EmailAddress                 = @{
                Required = $false
                Format = '^[^@]+@[^@]+\.[^@]+$'
                MaxLength = 64
                Description = 'Format of user@domain'
            }
            EmployeeID                   = @{
                Required = $true
                Format = '^[a-zA-Z0-9\-]+$'
                MaxLength = 10
                Description = 'Alphanumeric with hyphens allowed'
            }
            GivenName                    = @{
                Required = $true
                Format = '^[a-zA-Z\-]+$'
                MaxLength = 32
                Description = 'Letters and hyphens only, no spaces'
            }
            Manager                      = @{
                Required = $true
            }
            Office                       = @{
                Required = $false
                Default = 'New York' 
            }
            OfficePhone                  = @{
                Required = $false
                Default = '123-456-7890'
                Format = '^\d{3}-\d{3}-\d{4}$'
                MaxLength = 12   
                Description = 'Format of XXX-XXX-XXXX'
            }
            SamAccountName               = @{
                Required = $false
                Format = '^[a-zA-Z0-9._\-]+$'
                MaxLength = 20
                Description = 'Alphanumeric, dots, hyphens, underscores only'
            }
            Surname                      = @{
                Required = $true
                Format = '^[a-zA-Z\-]+$'
                MaxLength = 32
                Description = 'Letters and hyphens only, no spaces'
            }
            Title                        = @{
                Required = $true
                Format = '^[a-zA-Z0-9 \-]+$'
                MaxLength = 64
                Description = 'Alphanumeric with spaces and hyphens allowed'
            }
        }
        PasswordPolicy  = @{
            MinimumLength       = 8
            MaximumLength       = 128
            DefaultLength       = 8
            RequireUppercase    = $true
            RequireLowercase    = $true
            RequireNumbers      = $true
            RequireSpecialChars = $true
            AllowedSpecialChars = '!@#$%^&*()=+-_'
        }
    }

    UI              = @{
        WindowTitle = 'Active Directory User Administration Tool'
        NavIcon     = 'media\logo.png'
        XamlFile    = 'resources\MainWindow.xaml'
    }

    DataSources     = @{
        Departments = @{
            Path   = 'data\departments'
            Key = 'Name'
            Code = 'Code'
        }
        Locations   = @{
            Path   = 'data\locations'
            Key = 'physicalDeliveryOfficeName'
            Code = 'Code'
            StreetAddress = 'streetAddress'
            City = 'l'
            State = 'state'
            Country = 'country'
            PostalCode = 'postalCode'
            OfficePhone = 'officephone'
        }
    }
    
    Logging = @{
        LogPath = "\\contososhared.com\shared\IT Department\Software\ADUserAdminGUI\Logs"
    }
}
