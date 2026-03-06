#region Configuration
$script:LocalLowPath = "$env:USERPROFILE\AppData\LocalLow"
$script:TargetFileName = "HGWebview.log"
$script:UrlRegexPattern = 'https://[^\s"]+?\.gryphline\.com/[^\s"]+?token=[^\s"]+?server=[^\s"]+'
$script:LogFileAgeCutoffHours = -24
$script:SearchDirectories = @("Gryphline", "Hypergryph")
$script:CheckedPaths = @()
#endregion

#region Functions
function Get-PrimaryLogFilePath {
    <#
        .SYNOPSIS
        Gets the primary log file path.
    #>
    $primaryPath = Join-Path $script:LocalLowPath "Gryphline\Endfield\sdklogs\$script:TargetFileName"
    
    if (Test-Path $primaryPath) {
        return $primaryPath
    }
    
    return $null
}

function Search-LogFileInDirectories {
    <#
        .SYNOPSIS
        Searches for the log file in fallback directories.
        
        .PARAMETER CutoffTime
        The minimum last write time for the log file.
    #>
    param(
        [DateTime]$CutoffTime
    )
    
    foreach ($directory in $script:SearchDirectories) {
        $searchPath = Join-Path $script:LocalLowPath $directory
        
        if (-not (Test-Path $searchPath)) {
            continue
        }
        
        $logFile = Get-ChildItem `
            -Path $searchPath `
            -Filter $script:TargetFileName `
            -Recurse `
            -ErrorAction SilentlyContinue |
            Where-Object { 
                $_.LastWriteTime -ge $CutoffTime -and 
                $_.FullName -notin $script:CheckedPaths 
            } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        
        if ($logFile) {
            return $logFile.FullName
        }
    }
    
    return $null
}

function Find-UrlInLogFile {
    <#
        .SYNOPSIS
        Extracts the last matching URL from the log file.
        
        .PARAMETER FilePath
        The path to the log file.
    #>
    param(
        [string]$FilePath
    )
    
    if (-not (Test-Path $FilePath)) {
        return $null
    }
    
    $lines = Get-Content $FilePath -ErrorAction SilentlyContinue
    
    if ($null -eq $lines) {
        Write-Error "Log file is empty."
        return $null
    }
    
    $lastMatch = $null
    
    foreach ($line in $lines) {
        if ($line -match $script:UrlRegexPattern) {
            $lastMatch = $matches[0]
        }
    }
    
    return $lastMatch
}

function Format-UrlWithPath {
    <#
        .SYNOPSIS
        Appends the relative path to the URL if using fallback location.
        
        .PARAMETER Url
        The base URL to format.
        
        .PARAMETER FilePath
        The full path to the log file.
        
        .PARAMETER IsFallback
        Whether the file was found in a fallback location.
    #>
    param(
        [string]$Url,
        [string]$FilePath,
        [bool]$IsFallback
    )
    
    if (-not $IsFallback) {
        return $Url
    }
    
    $relativePath = $FilePath.Replace("$script:LocalLowPath\", "")
    return "$Url&path=$relativePath"
}

function Write-SuccessMessage {
    <#
        .SYNOPSIS
        Displays success message with the URL.
        
        .PARAMETER Url
        The URL to display.
    #>
    param(
        [string]$Url
    )
    
    Write-Host "Success! URL has been copied to clipboard:" -ForegroundColor Green
    Write-Host $Url
}

function Search-AllDrivesForLogFile {
    <#
        .SYNOPSIS
        Searches for log file across all available drives.
        
        .PARAMETER CutoffTime
        The minimum last write time for the log file.
    #>
    param(
        [DateTime]$CutoffTime
    )
    
    Write-Host "Scanning all drives (A-Z) to find log file..." -ForegroundColor Yellow
    
    $availableDrives = Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Name
    Write-Host "Available drives: $($availableDrives -join ', ')" -ForegroundColor Yellow
    
    foreach ($driveLetter in $availableDrives) {
        $drive = "$driveLetter`:"
        
        Write-Host "Scanning drive $drive..."
        
        # Search in user profiles on this drive
        $usersPath = Join-Path $drive "Users"
        
        if (Test-Path $usersPath) {
            $userDirs = Get-ChildItem -Path $usersPath -Directory -ErrorAction SilentlyContinue
            
            foreach ($userDir in $userDirs) {
                foreach ($directory in $script:SearchDirectories) {
                    $localLowPath = Join-Path $userDir.FullName "AppData\LocalLow\$directory"
                    
                    if (-not (Test-Path $localLowPath)) {
                        continue
                    }
                    
                    $logFile = Get-ChildItem `
                        -Path $localLowPath `
                        -Filter $script:TargetFileName `
                        -Recurse `
                        -ErrorAction SilentlyContinue |
                        Where-Object { 
                            $_.LastWriteTime -ge $CutoffTime -and 
                            $_.FullName -notin $script:CheckedPaths 
                        } |
                        Sort-Object LastWriteTime -Descending |
                        Select-Object -First 1
                    
                    if ($logFile) {
                        $fullPath = $logFile.FullName
                        $script:CheckedPaths += $fullPath
                        Write-Host "Found log file: $fullPath" -ForegroundColor Green
                        return $fullPath
                    }
                }
            }
        }
        
        # Search in LocalLow directory directly on the drive (if exists)
        foreach ($directory in $script:SearchDirectories) {
            $searchPath = Join-Path $drive "LocalLow\$directory"
            
            if (-not (Test-Path $searchPath)) {
                continue
            }
            
            $logFile = Get-ChildItem `
                -Path $searchPath `
                -Filter $script:TargetFileName `
                -Recurse `
                -ErrorAction SilentlyContinue |
                Where-Object { 
                    $_.LastWriteTime -ge $CutoffTime -and 
                    $_.FullName -notin $script:CheckedPaths 
                } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            
            if ($logFile) {
                $fullPath = $logFile.FullName
                $script:CheckedPaths += $fullPath
                Write-Host "Found log file: $fullPath" -ForegroundColor Green
                return $fullPath
            }
        }
    }
    
    return $null
}

function Request-ManualPath {
    <#
        .SYNOPSIS
        Prompts user to manually enter the log file path or directory.
        
        .PARAMETER CutoffTime
        The minimum last write time for the log file.
    #>
    param(
        [DateTime]$CutoffTime
    )
    
    Write-Host "`nLog file not found automatically." -ForegroundColor Red
    Write-Host "You can manually enter the path to the log file or directory containing logs." -ForegroundColor Yellow
    Write-Host "`nCommon path examples:" -ForegroundColor Yellow
    Write-Host "  $env:USERPROFILE\AppData\LocalLow\Gryphline\Endfield\sdklogs\HGWebview.log" -ForegroundColor Cyan
    Write-Host "  $env:USERPROFILE\AppData\LocalLow\Gryphline" -ForegroundColor Cyan
    Write-Host "  $env:USERPROFILE\AppData\LocalLow\Hypergryph" -ForegroundColor Cyan
    
    while ($true) {
        $userPath = Read-Host "`nEnter path (type 'exit' to quit)"
        
        if ([string]::IsNullOrWhiteSpace($userPath)) {
            Write-Host "Invalid path. Please try again." -ForegroundColor Red
            continue
        }
        
        if ($userPath.ToLower() -eq "exit") {
            return $null
        }
        
        # Remove quotes if present
        $userPath = $userPath.Trim('"', "'")
        
        if (-not (Test-Path $userPath)) {
            Write-Host "Path does not exist: $userPath" -ForegroundColor Red
            continue
        }
        
        $resolvedPath = Resolve-Path $userPath -ErrorAction SilentlyContinue
        
        if (-not $resolvedPath) {
            Write-Host "Cannot resolve path: $userPath" -ForegroundColor Red
            continue
        }
        
        $resolvedPath = $resolvedPath.Path
        
        # If it's a file, check directly
        if (Test-Path $resolvedPath -PathType Leaf) {
            if ($resolvedPath -like "*$script:TargetFileName") {
                Write-Host "Found log file: $resolvedPath" -ForegroundColor Green
                return $resolvedPath
            }
            else {
                Write-Host "File is not $script:TargetFileName" -ForegroundColor Red
                continue
            }
        }
        
        # If it's a directory, search for log file in it
        Write-Host "Searching for log file in directory: $resolvedPath" -ForegroundColor Yellow
        
        $logFile = Get-ChildItem `
            -Path $resolvedPath `
            -Filter $script:TargetFileName `
            -Recurse `
            -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge $CutoffTime } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        
        if ($logFile) {
            Write-Host "Found log file: $($logFile.FullName)" -ForegroundColor Green
            return $logFile.FullName
        }
        else {
            Write-Host "Log file not found in this directory." -ForegroundColor Red
            Write-Host "Please check the path again or make sure you have opened the game and accessed the tracker page." -ForegroundColor Yellow
        }
    }
}
#endregion

#region Main Execution
function Main {
    $cutoffTime = (Get-Date).AddHours($script:LogFileAgeCutoffHours)
    $targetFilePath = $null
    $isFallback = $false
    
    Write-Host "Searching for log file automatically..." -ForegroundColor Yellow
    
    # Try primary path first
    $targetFilePath = Get-PrimaryLogFilePath
    if ($targetFilePath) {
        $script:CheckedPaths += $targetFilePath
        Write-Host "Found log file at primary path: $targetFilePath" -ForegroundColor Green
    }
    
    # If not found, search in fallback directories
    if (-not $targetFilePath) {
        $targetFilePath = Search-LogFileInDirectories -CutoffTime $cutoffTime
        if ($targetFilePath) {
            $isFallback = $true
            $script:CheckedPaths += $targetFilePath
        }
    }
    
    # If still not found, search all drives
    if (-not $targetFilePath) {
        $targetFilePath = Search-AllDrivesForLogFile -CutoffTime $cutoffTime
        if ($targetFilePath) {
            $isFallback = $true
        }
    }
    
    # If still not found, request manual path
    if (-not $targetFilePath) {
        $targetFilePath = Request-ManualPath -CutoffTime $cutoffTime
        if ($targetFilePath) {
            $isFallback = $true
        }
    }
    
    # Validate file exists
    if (-not $targetFilePath) {
        Write-Error "Log file not found. Please check the path again or make sure you have opened the game."
        exit 1
    }
    
    # Extract URL from log file
    $foundUrl = Find-UrlInLogFile -FilePath $targetFilePath
    
    if (-not $foundUrl) {
        Write-Error "No matching URL found in log file. Please make sure you have opened the game and accessed the tracker page."
        exit 1
    }
    
    # Format URL with path if using fallback
    $finalUrl = Format-UrlWithPath `
        -Url $foundUrl `
        -FilePath $targetFilePath `
        -IsFallback $isFallback
    
    # Copy to clipboard and display success message
    Set-Clipboard -Value $finalUrl
    Write-SuccessMessage -Url $finalUrl
}

Main
#endregion
