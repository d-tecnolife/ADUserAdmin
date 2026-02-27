Import-Module "$PSScriptRoot\..\ADUserAdminGUI.AppState\AppState.psm1"
<#
.SYNOPSIS
    Generates a cryptographically secure random password, or returns a provided password as secure string
.PARAMETER Password
    (Optional) Plain text password to convert to secure string
.PARAMETER Length
    (Optional) Length of the password to generate
#>
function New-SecurePassword {
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$Length,
        [Parameter()]
        [String]$Password
    )
    $policy = Get-PasswordPolicy

    if([String]::IsNullOrWhiteSpace($Password)){
        # Use config values if length not specified
        if ($Length -eq 0) {
            $Length = $policy.DefaultLength
        }
        
        $minLength = $policy.MinimumLength
        $maxLength = $policy.MaximumLength
        
        if ($Length -lt $minLength -or $Length -gt $maxLength) {
            throw "Password length must be between $minLength and $maxLength characters."
        }
        
        # Remove problem characters I and l
        $lowercase = 'abcdefghijkmnopqrstuvwxyz'
        $uppercase = 'ABCDEFGHJKLMNOPQRSTUVWXYZ'
        $numbers = '0123456789'
        $special = $policy.AllowedSpecialChars
        $allChars = $lowercase + $uppercase + $numbers + $special
        
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        
        try {
            function Get-RandomChar {
                param([string]$CharSet)
                $bytes = [byte[]]::new(4)
                $rng.GetBytes($bytes)
                $index = [BitConverter]::ToUInt32($bytes, 0) % $CharSet.Length
                return $CharSet[$index]
            }
            
            # Build password as a list of individual characters
            $passwordChars = New-Object System.Collections.Generic.List[char]
            
            # Ensure at least one of each required character type
            $passwordChars.Add([char](Get-RandomChar $lowercase))
            $passwordChars.Add([char](Get-RandomChar $uppercase))
            $passwordChars.Add([char](Get-RandomChar $numbers))
            $passwordChars.Add([char](Get-RandomChar $special))
            
            # Fill remaining length
            for ($i = 4; $i -lt $Length; $i++) {
                $passwordChars.Add([char](Get-RandomChar $allChars))
            }
            
            # Shuffle the characters
            $shuffled = $passwordChars | Sort-Object { 
                $bytes = [byte[]]::new(4)
                $rng.GetBytes($bytes)
                [BitConverter]::ToUInt32($bytes, 0)
            }

            $passwordPlain = -join $shuffled
            $passwordSecure = (ConvertTo-SecureString -AsPlainText $passwordPlain -Force)
            return @{
                Plain = $passwordPlain
                Secure = $passwordSecure
            }
        }
        finally {
            $rng.Dispose()
        }
    } else {
        $passwordPlain = $Password
        $passwordSecure = (ConvertTo-SecureString -AsPlainText $Password -Force)
        return @{
            Plain = $passwordPlain
            Secure = $passwordSecure
        }
    }
}

<#
.SYNOPSIS
    Tests if a password meets complexity requirements from config
.PARAMETER Password
    Password to validate
#>
function Test-PasswordComplexity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Password
    )
    
    $policy = Get-PasswordPolicy
    $requirements = @()
    
    # Build requirements from config
    if ($policy.RequireLowercase) {
        $requirements += @{ 
            Name = "At least one lowercase letter"
            Test = { $Password -cmatch '[a-z]' } 
        }
    }
    
    if ($policy.RequireUppercase) {
        $requirements += @{ 
            Name = "At least one uppercase letter"
            Test = { $Password -cmatch '[A-Z]' } 
        }
    }
    
    if ($policy.RequireNumbers) {
        $requirements += @{ 
            Name = "At least one number"
            Test = { $Password -match '[0-9]' } 
        }
    }
    
    if ($policy.RequireSpecialChars) {
        $requirements += @{ 
            Name = "At least one special character"
            Test = { 
                $charArray = $policy.AllowedSpecialChars.ToCharArray()
                $Password.IndexOfAny($charArray) -ge 0
             } 
        }
    }
    
    # Check minimum length
    $requirements += @{ 
        Name = "Minimum $($policy.MinimumLength) characters"
        Test = { $Password.Length -ge $policy.MinimumLength } 
    }
    
    # Check maximum length
    $requirements += @{ 
        Name = "Maximum $($policy.MaximumLength) characters"
        Test = { $Password.Length -le $policy.MaximumLength } 
    }
    
    # Validate all requirements
    $failed = @()
    foreach ($req in $requirements) {
        if (-not (& $req.Test)) {
            $failed += $req.Name
        }
    }
    return $failed
}