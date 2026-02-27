Import-Module "$PSScriptRoot\..\ADUserAdminGUI.AppState\AppState.psm1"
<#
.SYNOPSIS
    Writes a formatted entry to a log file
.PARAMETER Message
    The main text to log
.PARAMETER Level
    Info, Warning, or Error
.PARAMETER Caller
    (Optional) Name of the function calling the log
.EXAMPLE
    Write-Log -Message "Warning message" -Level Warning
    Output: [13:21:27] [domain\namedadmin] [Warning] [CallingScript]
    Warning message
#>
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [ValidateSet("Info", "Warning", "Error")]
        [string]$Level = "Info",

        [Parameter()]
        [string]$Caller = $($MyInvocation.ScriptName)
    )
    $loggingConfig = Get-LoggingConfig
    $admin = Get-Admin

    if ($null -eq $loggingConfig) {
         return 
        }
    
    $timestamp = Get-Date
    $folderName = $timestamp.ToString("yyyy-MM")
    $fileName = $timestamp.ToString("yyyy-MM-dd") + ".log"
    $appInfo = Get-AppInfo
    $version = $appInfo.Version
    
    $logPath = Join-Path $loggingConfig.LogPath $folderName
    $logFile = Join-Path $logPath $fileName

    try {
        # Create directory if it doesn't exist
        if (-not (Test-Path $logPath)) {
            New-Item -Path $logPath -ItemType Directory -Force | Out-Null
        }

        # Format: [Timestamp] [User] [Level] [Function] - Message
        $logEntry = "[{0}] [v{1}] [{2}] [{3}] [{4}] `n {5}" -f `
            $timestamp.ToString("HH:mm:ss"), `
            $version, `
            $admin, `
            $Level, `
            $Caller, `
            $Message

        # Append to file with separator between actions
        Add-Content -Path $logFile -Value $logEntry
        Add-Content -Path $logFile -Value ("-" * 100)
    }
    catch {
        Write-Warning "Failed to write to log file: $($_.Exception.Message)"
    }
}