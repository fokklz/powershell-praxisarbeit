<#
.SYNOPSIS
    A script to clean up a shared drive by extracting and reorganizing projects.

.DESCRIPTION
    This script is designed to clean up a shared drive. It extracts projects and reorganizes them in a new root directory. 
    It identifies projects based on the presence of certain files (like "package.json", "requirements.txt", "*.sln", "*.pyproj", "README.md").
    The script also provides options to force overwrite of existing files, enable modification date detection by file content, 
    only map projects without moving them, enable manual primary project selection, and keep all projects in root when moving.

.PARAMETER
    -Path: The directory to clean up.
    -Out: The output directory for the cleaned up structure.
    -Force: A switch to force overwrite of existing files in the output path.
    -UseContent: A switch to enable modification date detection by file content.
    -MapOnly: A switch to only map projects without moving them.
    -Interactive: A switch to enable manual primary project selection.
    -Flat: A switch to keep all projects in root when moving.

.EXAMPLE
    .\praxisarbeit.ps1 -Path "C:\SharedDrive" -Out "C:\CleanDrive" -Force -Flat

.NOTES
    The script creates a log file and a JSON file with the project details in the output directory.

.AUTHOR
    Fokko Vos

.LASTEDIT
    23.05.2023

.VERSION
    1.0.0
#>


param(
    # directory to cleanup
    [Parameter(Position = 0, HelpMessage = 'Path to cleanup')]
    [string]$Path = "",

    # ouput for cleaned up structure
    [Parameter(Position = 1, HelpMessage = 'Path to store cleaned up Data')]
    [string]$Out = "$pwd/out",

    [switch]$Force, # force overwrite of existing files (out-path)
    [switch]$UseContent, # enable modification date detection by file content
    [switch]$MapOnly, # only map projects, do not move them
    [switch]$Interactive, # enable manual primary project selection
    [switch]$Flat, # keep all projects in root when moving
    [switch]$MakeLonger # make the script take longer
)

$ErrorActionPreference = "Stop"

# =====================================================================
# Variables
# =====================================================================

# original working directory
$OG_PWD = $PWD
# temporary log array, to reduce file access
$LOG_TEMP = New-Object -TypeName System.Collections.ArrayList
# ignored folders
$BLACKLIST = "\\.git\\|\\.vscode\\|\\.venv\\|\\node_modules\\|\\.gradle\\|\\.github\\|\\.idea\\|\\__pycache__\\|\\BuildTools\\|\\.husky\\"
# project index
$INDEX = New-Object -TypeName System.Collections.Hashtable
# files making a folder a project folder
$PROJECT_FILES = @(
    # NPM Project
    "package.json",
    # Python Projects
    "requirements.txt",
    # Visual Studio
    "*.sln", 
    "*.pyproj",
    # Global fallback
    "README.md" 
)

$STARTED = Get-Date

$COUNT_PROJECT_VERSIONS = 0
$COUNT_PROJECTS_MOVED = 0

# test if path is absolute & exists
# regex: https://regex101.com/r/OVptX3/3
$RGX_ABSOLUTE_PATH = '^(?:(?:[A-Za-z]:)?(?:\.)?[\\/]){1,}?.*'

# match colored log types
$RGX_COLORED_LOG_TYPES = 'SYSTEM|WARN|ERROR'

# match for copyright years
# regex: https://regex101.com/r/auV2UP/1
$RGX_COPYRIGHT = '[Cc]opyright.*(\d{4})'

# =====================================================================
# Functions
# =====================================================================

function Get-RunTime {
    <#
    .SYNOPSIS
    Returns the runtime of the script.

    .DESCRIPTION
    Returns the runtime of the script.

    .NOTES
    The script should only be ended with this function. in case of an error.
    #>
    $runTime = ((Get-Date) - $STARTED)
    return "00:{0:00}:{1:00}" -f $runTime.Minutes, $runTime.Seconds
}

function Exit-Error {
    <#
    .SYNOPSIS
    Finishes the script with an error.

    .DESCRIPTION
    Finishes the script with an error. Resets the working directory and writes the error to the log file.

    .NOTES
    The script should only be ended with this function. in case of an error.
    #>
    Set-Location $OG_PWD
    Write-Out -Type "ERROR" $args.Exception -ForceWriteLog -LogOnly
    exit 1
}   

function Exit-Success {
    <#
    .SYNOPSIS
    Finishes the script successfully.
    
    .DESCRIPTION
    Finishes the script successfully. Resets the working directory and writes a final info message to the log file.
    
    .NOTES
    The script should only be ended with this function in case of success.
    #>
    Set-Location $OG_PWD
    Write-Out -Type "INFO" "Skript wurde erfolgreich durchgeführt, Vorgang hat %s gedauert" (Get-RunTime) -ForceWriteLog
    exit 0
}

function Write-Out {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,
        [string]$Type = "INFO",
        [switch]$LogOnly,
        [switch]$ForceWriteLog,
        [switch]$AddNewLine,
        [Parameter(ValueFromRemainingArguments = $true)]
        $highlighted # replacements for %s
    )

    $fullMessage = $Message
    $printed = $false
    if ($Message -match '.*%s.*') {
        $fullMessage = ""
        $splittedMessage = $Message -split '%s'
        # print directly if not colored log type and not log only
        for ($i = 0; $i -lt $splittedMessage.Length; $i++) {
            if ($Type -notmatch $RGX_COLORED_LOG_TYPES -and -not $LogOnly) {
                Write-Host $splittedMessage[$i] -NoNewline
            }
            $fullMessage += $splittedMessage[$i]
            if ($i -lt $highlighted.Count) {
                if ($Type -notmatch $RGX_COLORED_LOG_TYPES -and -not $LogOnly) {
                    Write-Host $highlighted[$i] -ForegroundColor Cyan -NoNewline
                }
                $fullMessage += $highlighted[$i]
            }
        }

        # new line because of -NoNewline
        if ($Type -notmatch $RGX_COLORED_LOG_TYPES -and -not $LogOnly) {
            Write-Host "`r"
            $printed = $true
        }
    }

    # print colored if colored log type and not log only
    if (-not $LogOnly) {
        switch ($Type) {
            'SYSTEM' {
                Write-Host $fullMessage -ForegroundColor Green
            }
            'WARN' {
                Write-Host $fullMessage -ForegroundColor Yellow
            }
            'ERROR' {
                Write-Host $fullMessage -ForegroundColor Red
            }
            default {
                if (-not $printed) {
                    Write-Host $fullMessage
                }
            }
        }

        if ($AddNewLine) {
            Write-Host ""
        }
    }

    $LOG_TEMP.Add("$(Get-Date -Format "dd-MM-yyyy HH:mm:ss") [$Type] $fullMessage") | Out-Null

    if ($LOG_TEMP.Count -gt 30 -or $ForceWriteLog) {
        try {
            $LOG_TEMP | Out-File -FilePath $LOG_FILE -Append -Encoding utf8
        } catch {
            Write-Host "Fehler beim Schreiben in die Log-Datei" -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
        } finally {
            $LOG_TEMP.Clear()
        }
    }
}

function Get-LastModificationDate {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path
    )

    # state & value
    $year = 0

    if ($UseContent) {
        # possible files containing years
        $fileNames = @("LICENSE", "License.md", "license.md", "index.html")
        # end on first year match
        foreach ($fileName in $fileNames) {
            # construct full path
            $fullPath = Join-Path -Path $Path -ChildPath $fileName

            if (Test-Path -Path $fullPath) {
                (Get-Content -Path $fullPath).ForEach({
                        if ($_ -match $RGX_COPYRIGHT) {
                            $year = $Matches[1]
                        }
                    })
            }

            if ($syear -gt 0) {
                break
            }
        }
    }

    if ($year -eq 0) {
        # extract oldest file inside folder
        $oldest = Get-ChildItem -Path $Path -Recurse -File | Where-Object {
            # continue if not contained
            $_.DirectoryName -notmatch $BLACKLIST
        } | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1

        # cleanup date
        return Get-Date -Year $oldest.LastWriteTime.Year -Day $oldest.LastWriteTime.Day -Month $oldest.LastWriteTime.Month -Hour 0 -Minute 0 -Second 0
    }

    # generate date from year
    return Get-Date -Year $year -Day 1 -Month 1 -Hour 0 -Minute 0 -Second 0
}

function Get-Hash {
    <#
    .SYNOPSIS
    Get hash of file or project-folder
    
    .DESCRIPTION
    Get hash of file or for a project-folder. If a project-folder is given, 
    the name of the project is used as identifyer. If no project name is given,
    the hash of the project file is used as identifyer.
    
    .PARAMETER Path
    Existing project path
    #>
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path
    )

    if (Test-Path -Path $Path -PathType Container) {
        # exit on first match
        foreach ($projectFile in $PROJECT_FILES) {
            if (Test-Path -Path (Join-Path -Path $Path -ChildPath $projectFile)) {
                if ($projectFile -eq "package.json") {
                    # parse package.json
                    $package = Get-Content -Path (Join-Path -Path $Path -ChildPath $projectFile) -Raw | ConvertFrom-Json
                    # if name is set, use it
                    if ($package.name) {
                        return $package.name 
                    }
                }
                return (Get-FileHash -Path (Join-Path -Path $Path -ChildPath $projectFile) -Algorithm SHA256).Hash
            }
        }

        Write-Out -Type "ERROR" "Keine Projektdatei gefunden für %s" $Path
    }

    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash
}

function Find-Projects {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path
    )

    # read trough folder
    # exit on error
    Get-ChildItem -Path $Path -Directory | Where-Object {
        $_.FullName -notmatch $BLACKLIST
    } | Select-Object FullName | ForEach-Object {
        if (-not (Test-Project -Path $_.FullName)) {
            # call self on subfolder
            Find-Projects -Path $_.FullName
        } else {
            # get project identifyer (name or hash)
            $hash = Get-Hash $_.FullName

            # create project index, if not existing
            if (-not $INDEX.ContainsKey($hash)) {
                $INDEX.Add($hash, (New-Object -TypeName System.Collections.ArrayList))
            }

            $data = [PSCustomObject]@{
                path    = $_.FullName
                date    = (Get-LastModificationDate $_.FullName)
                primary = $false
                newPath = $null
            }

            # store data
            [void]$INDEX[$hash].Add($data)
            
            Write-Out "Projekt %s gefunden" $hash
            Write-Out "  - %s" (Resolve-Path -Path $_.FullName -Relative) -AddNewLine
        }
        
    }
}


function Test-Project {
    <#
    .SYNOPSIS
    Test if is a project-folder
    
    .DESCRIPTION
    Test if a project file exists in the given path
    based on the PROJECT_FILES array defined
    
    .PARAMETER Path
    Existing folder path (possible project folder)
    
    .EXAMPLE
    Test-Project -Path $Path
    #>
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path
    )

    # test for each project file
    foreach ($projectFile in $PROJECT_FILES) {
        if (Test-Path -Path (Join-Path -Path $Path -ChildPath $projectFile)) {
            return $true
        }
    }

    return $false
}

function Write-ProjectsJSON {
    <#
    .SYNOPSIS
    Write projects to json file
    
    .DESCRIPTION
    convert the data for the Projects to a valid json format
    and write the file to the disk
    
    .PARAMETER HashTable
    Hashtable containing the projects
    
    .EXAMPLE
    Write-ProjectsJSON -HashTable $INDEX
    
    .NOTES
    The date is converted to a universal time format
    #>

    # formatted data for json
    $storableProjects = New-Object -TypeName System.Collections.Hashtable

    foreach ($key in $INDEX.Keys) {
        # clone to avoid mutation errors
        $values = $INDEX[$key] | ForEach-Object { $_ }
        for ($i = 0; $i -lt $values.Count; $i++) {
            $values[$i].date = $values[$i].date.ToString("yyyy-MM-ddTHH:mm:ssZ")
            if ($MapOnly) {
                # remove new path when only mapping
                $newData = [PSCustomObject]@{
                    path    = $values[$i].path
                    date    = $values[$i].date
                    primary = $values[$i].primary
                }
                $values[$i] = $newData
            }
        }
        $storableProjects.Add($key, $values)
    }

    # write to file
    $storableProjects | ConvertTo-Json -Depth 2 | Out-File -FilePath $PROJECTS_FILE -Encoding UTF8
    Write-Out "Projetinformationen als JSON in %s geschpeichert" $PROJECTS_FILE
}

function Update-Progress {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$name
    )

    if ($COUNT_PROJECTS_MOVED -gt 0) {
        $complete = ($COUNT_PROJECTS_MOVED / $COUNT_PROJECT_VERSIONS) * 100
        if ($COUNT_PROJECTS_MOVED -eq $COUNT_PROJECT_VERSIONS -or $complete -ge 100) {
            Write-Progress -Id 1 -Activity "Projekte werden verschoben" -Status "Vollendet" -PercentComplete 100 -Completed
            return
        }
        Write-Progress -Id 1 -Activity "Projekte werden verschoben" -Status "$name wird verschoben..." -PercentComplete $complete
    }
}

function Move-WithProgress {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [PSCustomObject]$Data,
        [Parameter(Mandatory = $false, Position = 1)]
        [PSCustomObject]$Primary = $null,
        [int]$Version = 0,
        [boolean]$Flat
    )

    $COUNT_PROJECTS_MOVED++
    Move-Project -Data $Data -Primary $Primary -Version $Version -Flat $Flat
}

function Move-Project {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [PSCustomObject]$Data,
        [Parameter(Mandatory = $false, Position = 1)]
        [PSCustomObject]$Primary = $null,
        [int]$Version = 0,
        [boolean]$Flat
    )

    $year = $Data.date.Year
    $name = Split-Path $Data.path -Leaf
    $newPath = $null
    
    if ($Primary -ne $null -and $Version -gt 0) {
        $primaryName = Split-Path $Primary.path -Leaf
        $name = "$primaryName/.versions/v$($Version)_$name"
    }
    
    Update-Progress $name

    if ($Flat) {
        $newPath = Join-Path $Out $name
    } else {
        $newPath = Join-Path $Out (Join-Path $year $name)
    }

    try {
        New-Item -Path (Split-Path $newPath -Parent) -ItemType Directory -Force | Out-Null
        Move-Item -Path $Data.path -Destination $newPath -Force
        $script:COUNT_PROJECTS_MOVED += 1
        Write-Out -Type "INFO" "Das Projekt %s wurde verschoben (%s/%s)" $name $COUNT_PROJECTS_MOVED $COUNT_PROJECT_VERSIONS
        Update-Progress $name
    } catch {
        Write-Out -Type "ERROR" "Das Projekt %s konnte nicht verschoben werden" $name
        Write-Out -Type "ERROR" $_.Exception -LogOnly
    } finally {
        # allow for some delay while shoing in presentation
        if ($MakeLonger) {
            Start-Sleep -Seconds 1
        }
    }

    return $newPath
}
# =====================================================================-
# Validation
# =====================================================================

# ensure parameters are not null or empty
if ([string]::IsNullOrEmpty($Path)) {
    Write-Out -Type "ERROR" "Der Parmaeter '-Path' darf nicht leer sein"
    Exit-Error
}
if ([string]::IsNullOrEmpty($Out)) {
    Write-Out -Type "ERROR" "Der Parmaeter '-Out' darf nicht leer sein"
    Exit-Error
}

# handle path
if (Test-Path $Path) {
    # make path absolute if relative
    if ($Path -notmatch $RGX_ABSOLUTE_PATH) {
        $Path = Join-Path -Path $PWD -ChildPath $Path
    }

    # ensure directory & exists
    if (-not (Test-Path -Path $Path -PathType Container)) {
        Write-Out -Type "ERROR" "Der angegebene Pfad %s ist kein Ordner" $Path
        Exit-Error
    }
} else {
    Write-Out -Type "ERROR" "Der angegebene Pfad %s existiert nicht" $Path
    Exit-Error
}

# make out-path absolute if relative
if ($Out -notmatch $RGX_ABSOLUTE_PATH) {
    $Out = Join-Path -Path $PWD -ChildPath $Out
}
# ensure out-path is syntactically correct
try {
    New-Item -Path $Out -ItemType Directory -Force | Out-Null
    if ((Get-ChildItem -Path $Out).Length -gt 0) {
        # help user to not overwrite existing files if not desired
        if ($Force) {
            Write-Out -Type "WARN" "Der angegebene Out-Pfad %s existiert bereits und wird überschrieben" $Out
            Remove-Item -Path "$Out/*" -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Write-Out -Type "ERROR" "Der angegebene Out-Pfad %s existiert bereits" $Out
            Exit-Error
        }
    }
} catch {
    Write-Out -Type "ERROR" "Der angegebene Out-Pfad %s ist ungültig" $Out
    Exit-Error $_
}

Set-Location $Path

# =====================================================================
# Variables Dependent on Parameters
# =====================================================================

$LOG_FILE = Join-Path $Out "cleanup.log"
$PROJECTS_FILE = Join-Path $Out "projects.json"

# =====================================================================
# Script
# =====================================================================

Write-Out "Aufräumen von %s nach %s" $Path $Out -ForceWriteLog

try {
    Find-Projects -Path $Path

    # clone keys
    $keys = $INDEX.Keys | ForEach-Object { $_ }
    # set primary projects
    foreach ($key in $keys) {
        $sorted = $INDEX[$key] | Sort-Object -Property date -Descending
        $primaryIndex = $null
        
        if ($Interactive -and $sorted.Count -gt 1) {
            Write-Host "`n"
            Write-Out "Projekt %s hat %s Versionen" $key $sorted.Count

            $i = 1
            foreach ($value in $sorted) {
                Write-Out "[ %s ] %s - %s" $i ($value.date -f "yyyy-MM-dd HH:mm:ss") $value.path
                $i += 1
            }

            $selectedIndex = -1
            # prompt until valid
            while ($selectedIndex -lt 1 -or $selectedIndex -ge ($sorted.Count + 1)) {
                $input = Read-Host -Prompt "Bitte wähle die primäre Version aus (1)"

                if ([string]::IsNullOrEmpty($input)) {
                    # set default if no value provided
                    $selectedIndex = 1
                    break
                }

                # validate number
                try {
                    $selectedIndex = [int] $input
                } catch {
                    Write-Out -Type "ERROR" "Eingabe %s ungültig. Bitte gib eine Zahl ein." $input
                    continue
                }
            }

            $primaryIndex = $selectedIndex - 1
            Write-Out "Gewählte Primäre Version [ %s ] %s" ($primaryIndex + 1) ($sorted[$primaryIndex].path)
        } else {
            # set first to primary by default
            $primaryIndex = 0
        }

        # set primary flag
        $INDEX[$key][$primaryIndex].primary = $true
    }

    if ($INDEX.Count -gt 0) {
        $INDEX.Keys | ForEach-Object {
            $COUNT_PROJECT_VERSIONS += $INDEX[$_].Count
        }
        # write findings summary
        Write-Host "`n"
        Write-Out " %s Versionen, %s Projekte gefunden" $COUNT_PROJECT_VERSIONS $INDEX.Count
        if ($MapOnly) {
            Write-ProjectsJSON
            Write-Out "Die Projekte wurden als JSON in %s gespeichert" $PROJECTS_FILE -ForceWriteLog
            Exit-Success
        } else {
            $useFlat = $false
            if ($Interactive -and -not $Flat) {
                $inputString = $null
                while ($inputString -ne "y" -and $inputString -ne "n") {
                    $inputString = Read-Host -Prompt "Möchtest du die Projekte nach Datum sortiert abglegen? (y/n, default: y)"

                    if ([string]::IsNullOrEmpty($inputString)) {
                        break
                    }

                    if ($inputString -eq "y") {
                        break
                    } elseif ($inputString -eq "n") {
                        $useFlat = $true
                    } else {
                        Write-Out -Type "ERROR" "Eingabe %s ungültig. Bitte gib 'y' oder 'n' ein." $inputString
                    }
                }
            } elseif ($Flat) {
                $useFlat = $false
            }

            Write-Out "Die Projekte werden nach %s verschoben" $Out -ForceWriteLog -AddNewLine

            # cloned to avoid mutating while iterating
            $keys = $INDEX.Keys | ForEach-Object { $_ }
            $keys | ForEach-Object {
                $projects = $INDEX[$_] | Sort-Object -Property primary -Descending
                $primary = $projects[0]
                $movedPrimary = Move-Project $primary -Flat $useFlat
                $primary.newPath = $movedPrimary
                for ($i = 1; $i -lt $projects.Count; $i++) {
                    $movedVersion = Move-Project $projects[$i] $primary -Version $i -Flat $useFlat
                    $projects[$i].newPath = $movedVersion
                }
                $INDEX[$_] = $projects
            }
            Write-ProjectsJSON

            Write-Host "`n"
            Write-Out "Die Projekte wurden erfolgreich verschoben"
            Exit-Success
        }
    }
        
    Write-Out -Type "WARN" "Keine Projekte gefunden"
    Exit-Success
} catch {
    Write-Out -Type "ERROR" "Fehler beim Aufräumen von %s" $Path
    Write-Out -Type "ERROR" $_.Exception.Message
    Exit-Error $_
}