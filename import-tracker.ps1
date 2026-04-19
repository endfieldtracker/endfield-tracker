#region Configuration
$script:CacheFilePath = "$env:LOCALAPPDATA\PlatformProcess\Cache\data_1"
$script:UrlChars = '[A-Za-z0-9._~\-/?&=%+]'
$script:UrlRegexPattern = "https://[A-Za-z0-9.\-]+\.gryphline\.com/$script:UrlChars*?token=$script:UrlChars*?server=$script:UrlChars+"
#endregion

#region Functions
function Copy-CacheToTemp {
    <#
        .SYNOPSIS
        Copies the locked cache file to a temp location so it can be read.
    #>
    if (-not (Test-Path $script:CacheFilePath)) {
        Write-Error "Could not find cache file: $script:CacheFilePath"
        return $null
    }

    $tempFile = Join-Path $env:TEMP "tracker_cache_$([Guid]::NewGuid().ToString('N')).tmp"

    try {
        $sourceStream = [System.IO.File]::Open(
            $script:CacheFilePath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )
        $destStream = [System.IO.File]::Create($tempFile)
        $sourceStream.CopyTo($destStream)
        $sourceStream.Close()
        $destStream.Close()
        return $tempFile
    }
    catch {
        Write-Error "Could not copy file cache: $_"
        return $null
    }
}

function Find-UrlInCacheFile {
    <#
        .SYNOPSIS
        Extracts the last matching URL from the cache file.

        .PARAMETER FilePath
        The path to the (temp) cache file.
    #>
    param(
        [string]$FilePath
    )

    if (-not (Test-Path $FilePath)) {
        return $null
    }

    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    # Latin1 keeps bytes 1:1 (binary byte >= 128 becomes non-ASCII character, not replaced by '?')
    $content = [System.Text.Encoding]::GetEncoding("ISO-8859-1").GetString($bytes)

    $urlMatches = [regex]::Matches($content, $script:UrlRegexPattern)

    if ($urlMatches.Count -eq 0) {
        return $null
    }

    return $urlMatches[$urlMatches.Count - 1].Value
}

function Remove-TempFile {
    param([string]$Path)

    if ($Path -and (Test-Path $Path)) {
        Remove-Item $Path -Force -ErrorAction SilentlyContinue
    }
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
#endregion

#region Main Execution
function Main {
    Write-Host "Reading cache file..." -ForegroundColor Yellow

    $tempFile = Copy-CacheToTemp
    if (-not $tempFile) {
        exit 1
    }

    try {
        $foundUrl = Find-UrlInCacheFile -FilePath $tempFile

        if (-not $foundUrl) {
            Write-Error "Could not find matching URL in cache file. Please make sure you have opened the game and accessed the tracker page."
            exit 1
        }

        Set-Clipboard -Value $foundUrl
        Write-SuccessMessage -Url $foundUrl
    }
    finally {
        Remove-TempFile -Path $tempFile
    }
}

Main
#endregion
