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
    [switch]$NoVersions, # do not create version folders
    [switch]$CopyOnly # only copy files, do not move them
)

# exit on error, handled with try-catch
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

# capture start time
$STARTED = Get-Date

# all projects
$COUNT_PROJECT_VERSIONS = 0

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
    This function calculates and returns the runtime of the script.
    
    .DESCRIPTION
    The Get-RunTime function calculates the difference between the current time (Get-Date)
    and the time when the script started ($STARTED). It then formats this difference into 
    a string representing hours, minutes and seconds.
    
    .EXAMPLE
    $STARTED = Get-Date
    START-SLEEP -Seconds 5
    Get-RunTime

    Will return "00:00:05".

    .OUTPUTS
    String. The runtime of the script in the format "HH:MM:SS".
    #>
    $runTime = ((Get-Date) - $STARTED)
    return "{0:00}:{1:00}:{2:00}" -f $runTime.Hours, $runTime.Minutes, $runTime.Seconds
}

function Exit-Error {
    <#
    .SYNOPSIS
    This function handles script termination in case of an error.

    .DESCRIPTION
    The Exit-Error function is designed to be called when an error occurs in the script. 
    It changes the current location back to the original working directory ($OG_PWD), 
    then logs the runtime of the script and the error message, 
    and finally exits the script with a status of 1

    .EXAMPLE
    try {
        # do something
    } catch {
        Exit-Error $_
    }

    Will log the runtime of the script and the error message, and then exit the script with a status of 1.

    .NOTES
    The script should only be ended with this function. in case of an error.
    #>
    Set-Location $OG_PWD
    Write-Out "Der Vorgang hat %s gedauert" (Get-RunTime) -ForceWriteLog -LogOnly
    if ($args.Exception) {
        if ($args.Exception.InvocationInfo.ScriptLineNumber) {
            Write-Out -Type "ERROR" "An error occurred on line $($args.Exception.InvocationInfo.ScriptLineNumber):" -LogOnly
        }
        Write-Out -Type "ERROR" $args.Exception -ForceWriteLog -LogOnly
    }
    exit 1
}   

function Exit-Success {
    <#
    .SYNOPSIS
    This function handles script termination in case of successful execution.

    .DESCRIPTION
    The Exit-Success function is designed to be called when the script has successfully completed its execution. 
    It first changes the current location to the original working directory ($OG_PWD), 
    then prints and logs the runtime of the script and a success message, 
    and finally exits the script with a status of 0

    .EXAMPLE
    Exit-Success

    Will print & log the runtime of the script and a success message, and then exit the script with a status of 0.

    .NOTES
    The script should only be ended with this function in case of success.
    #>
    Set-Location $OG_PWD
    Write-Out "Skript wurde erfolgreich durchgeführt! Vorgang hat %s gedauert." (Get-RunTime) -ForceWriteLog
    exit 0
}

function Write-Out {
    <#
    .SYNOPSIS
        A custom logging function that writes messages to the console and a log file.

    .DESCRIPTION
        The Write-Out function is a custom logging function that writes messages to the console and a log file. 
        It supports different types of messages (INFO, SYSTEM, WARN, ERROR) and allows for message highlighting.

    .PARAMETER Message
        The message to be logged. This is a mandatory parameter. You can use '%s' as placeholders for the highlighted parameters.

    .PARAMETER Type
        The type of the message. Default is "INFO". Other options are "SYSTEM", "WARN", and "ERROR". 
        The message type determines the color of the message in the console.

    .PARAMETER LogOnly
        If this switch is set, the function will only write the message to the log file and not to the console.

    .PARAMETER ForceWriteLog
        If this switch is set, the function will immediately write all messages in the log buffer to the log file, 
        regardless of the current number of messages in the buffer.

    .PARAMETER AddNewLine
        If this switch is set, the function will add a new line after the message in the console.

    .PARAMETER highlighted
        An array of strings that will replace the '%s' placeholders in the Message parameter. 
        These strings will be highlighted in the console.

    .EXAMPLE
        Write-Out -Type "SYSTEM" "System started at %s" (Get-Date)

        Will print the message "System started at <current date>" in green color to the console and write it to the log file.

    .NOTES
        The function maintains a log buffer ($LOG_TEMP) and a log file ($LOG_FILE). 
        If the number of messages in the log buffer exceeds 30 or if the ForceWriteLog switch is set, 
        the function writes all messages in the buffer to the log file and then clears the buffer.
    #>

    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message, # message to be logged
        [string]$Type = "INFO", # type of the message
        [switch]$LogOnly, # only log to file
        [switch]$ForceWriteLog, # write log buffer to file
        [switch]$AddNewLine, # add new line after message
        [Parameter(ValueFromRemainingArguments = $true)]
        $highlighted # replacements for %s
    )

    $fullMessage = $Message
    $printed = $false
    if ($Message -match '.*%s.*') {
        $fullMessage = ""
        $splittedMessage = $Message -split '%s'
        # print highlighted when not colored log type
        # fullMessage will always be built
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
            Write-Host ""
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

    # append to log buffer
    $LOG_TEMP.Add("$(Get-Date -Format "dd-MM-yyyy HH:mm:ss") [$Type] $fullMessage") | Out-Null

    if ($LOG_TEMP.Count -gt 30 -or $ForceWriteLog) {
        try {
            $LOG_TEMP | Out-File -FilePath $LOG_FILE -Append -Encoding utf8
            # clear log buffer
            $LOG_TEMP.Clear()
        } catch {
            # ignore errrors
        }
    }
}

function Get-LastModificationDate {
    <#
    .SYNOPSIS
    This function retrieves the last modification date of a file or directory.

    .DESCRIPTION
    The Get-LastModificationDate function first checks if the specified path contains any of the predefined files (LICENSE, License.md, license.md, index.html). 
    If it does, it tries to extract a year from the file content. If a year is found, it returns a date object with that year.
    If no year is found in the file content or if the specified path does not contain any of the predefined files, 
    it finds the oldest file in the specified path and returns its last write time.

    .PARAMETER Path
    The path of the file or directory to check. This parameter is mandatory.

    .EXAMPLE
    Get-LastModificationDate -Path "C:\Users\user\Documents\GitHub\PowerShell-Scripts"

    .OUTPUTS
    Date-Time. The last modification date of the specified file or directory.
    #>
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

            # match if file exists
            if (Test-Path -Path $fullPath) {
                Get-Content -Path $fullPath | ForEach-Object {
                    if ($_ -match $RGX_COPYRIGHT) {
                        # update year from first match
                        $year = $Matches[1]
                    }
                }
            }

            if ($year -gt 0) {
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
    Get hash or name of file or project-folder
    
    .DESCRIPTION
    Get hash of file or for a project-folder. If a project-folder is given, 
    the name of the project is used as identifyer. If no project name is given,
    the hash of the project file is used as identifyer.

    .PARAMETER Path
    Existing project path

    .EXAMPLE
    Get-Hash "C:\Users\user\Documents\GitHub\PowerShell-Scripts"

    .OUTPUTS
    String. The hash or name of the specified file or project.
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

        # this functions should only be called on existing projects
        # log error and continue
        Write-Out -Type "ERROR" "Keine Projektdatei gefunden für %s" $Path
        # generate identifier from folder name and current date
        return "$(Split-Path -Path $Path -Leaf)_$(Get-Date -Format "yyyyMMddHHmmss")" 
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

            # create data object
            $data = [PSCustomObject]@{
                name    = (Split-Path $_.FullName -Leaf)
                path    = $_.FullName
                date    = (Get-LastModificationDate $_.FullName)
                primary = $false
                newPath = $null
            }

            # store data
            [void]$INDEX[$hash].Add($data)
            
            # give detailed project information
            Write-Out "Projekt %s gefunden" $data.name
            if (($INDEX[$hash].Count - 1) -gt 0) {
                Write-Out "  Version: %s" ($INDEX[$hash].Count - 1)
            }
            Write-Out "  Jahr: %s" ($data.date.Year)
            Write-Out "  Pfad: %s" (Resolve-Path -Path $_.FullName -Relative) -AddNewLine
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
    
    .EXAMPLE
    Write-ProjectsJSON

    Will output the data to the file specified in the script scope
    
    .NOTES
    The date is converted to a universal time format
    newPath will be removed if MapOnly is set
    #>

    # formatted data for json
    $storableProjects = New-Object -TypeName System.Collections.Hashtable

    foreach ($key in $INDEX.Keys) {
        # clone to avoid mutation errors
        $values = $INDEX[$key].Clone()
        for ($i = 0; $i -lt $values.Count; $i++) {
            if ($MapOnly) {
                # remove new path when only mapping
                $newData = [PSCustomObject]@{
                    path    = $values[$i].path
                    date    = $values[$i].date.ToString("yyyy-MM-ddTHH:mm:ssZ")
                    primary = $values[$i].primary
                }
                $values[$i] = $newData
            }
        }

        # add to sotorable project index
        $storableProjects.Add($key, $values)
    }

    # write to file
    $storableProjects | ConvertTo-Json -Depth 2 | Out-File -FilePath $PROJECTS_FILE -Encoding UTF8
    Write-Out "Die Projekte wurden als JSON in %s gespeichert" $PROJECTS_FILE
}

function Move-WithProgress {
    <#
    .SYNOPSIS
    Move a folder with progress bar
    
    .DESCRIPTION
    The function Move-WithProgress is used to move a folder with a progress bar. It grabs the first level of entries in the folder.
    If a subentry is a folder and the Recursion level is not reached, the function calls itself with the subentry as path.
    otherwise the subentry is moved to the destination folder.
    
    .PARAMETER Path
    The path of the folder to move
    
    .PARAMETER Destination
    The destination folder
    
    .PARAMETER Id
    The id for the progress bar
    
    .PARAMETER ParentId
    The id for the parent progress bar
    
    .PARAMETER Levels
    The recursion level for the progress bar. Be careful with this parameter as it can lead to deep recursion 
    if there are many nested directories. 

    .EXAMPLE
    Move-WriteProgress -Path $HOME/Documents/test -Destination $HOME/Projects -Id 10

    This will move all items from "$HOME/Documents/test" to "$HOME/Projects" and display a progress bar with an ID of 1. 
    If any items are directories, it will also display a nested progress bar with a recursion level of 2.

    .NOTES
    The function will automatically create the destination directory if it does not exist. 
    After all items are moved, the source directory will be removed.
    #>
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Destination,
        [int]$Id,
        [int]$ParentId = 0,
        [int]$Levels = 1
    )

    # auto increment id
    $current = $Id
    if (-not ($ParentId -eq 0)) {
        $current = $ParentId + 1
    }

    # grab contents
    $items = Get-ChildItem -Path $Path
    $toMove = $items.Count
    $moved = 0
    # name of the project, by path
    $name = Split-Path -Path $Path -Leaf


    foreach ($item in $items) {
        $completed = ($moved / $toMove) * 100

        # init & update progress bars
        if ($ParentId -eq 0) {
            # update main progress bar
            Write-Progress -Id $current -Activity "Verschieben von $name" -Status "$item wird verschoben..." -PercentComplete $completed
        } else {
            # update sub progress bar
            Write-Progress -ParentId $ParentId -Id $current -Activity "Verschieben von $name" -Status "$item wird verschoben..." -PercentComplete $completed
        }

        # call self if not reached recursion limit for progress bar
        if ($item -is [System.IO.DirectoryInfo] -and $current -lt ($Id + $Levels)) {
            Move-WithProgress -Path $item.FullName -Destination (Join-Path $Destination $item.Name) -Id $current -ParentId $current
        } else {
            # ensure destination folder exists
            New-Item -Path $Destination -ItemType Directory -Force | Out-Null
            if ($CopyOnly) {
                # copy item
                Copy-Item -Path $item.FullName -Destination $Destination -Force
            } else {
                # finally move item
                Move-Item -Path $item.FullName -Destination $Destination -Force
            }
        }

        # allow progress bar to update
        $moved++
    }

    # finish progress bars
    if ($ParentId -eq 0) {
        # update main progress bar
        Write-Progress -Id $current -Activity "Verschieben von $name" -Status "Vollendet" -PercentComplete 100 -Completed
    } else {
        # update sub progress bar
        Write-Progress -ParentId $ParentId -Id $current -Activity "Verschieben von $name" -Status "Vollendet" -PercentComplete 100 -Completed
    }

    if (-not $CopyOnly) {
        # remove empty folder
        Remove-Item -Path $Path
    }
}

function Remove-WithProgress {
    <#
    .SYNOPSIS
    Removes items from a specified path with a progress bar.

    .DESCRIPTION
    The Remove-WithProgress function removes items from a specified path. 
    It displays a progress bar during the operation. The progress bar can be nested to show progress 
    of individual items if they are directories.

    .PARAMETER Path
    The path of the items to be removed.

    .PARAMETER Id
    The ID for the progress bar. This is used to identify the progress bar in the console.

    .PARAMETER ParentId
    The ID for the parent progress bar. This is used when the progress bar is nested.

    .PARAMETER EmptyOnly
    A switch parameter. If this is set, the base folder will be recreated after all items are removed.

    .PARAMETER Levels
    The recursion level for the progress bar. Be careful with this parameter as it can lead to deep recursion 
    if there are many nested directories. 

    .EXAMPLE
    Remove-WithProgress -Path "$HOME/Projects" -Id 10 -EmptyOnly

    This will remove all items from "$HOME/Projects" and display a progress bar
    .NOTES
    The function will ignore any errors during the removal process.
    #>
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path, # path to remove
        [int]$Id, # progress bar id
        [int]$ParentId = 0, # parent progress bar id
        [switch]$EmptyOnly, # recreate base folder at the end
        [int]$Levels = 2 # recursion level for progress bar (be carefull)
    )

    # auto increment id
    $current = $Id
    if (-not ($ParentId -eq 0)) {
        $current = $ParentId + 1
    }

    # grab first sublevel
    $items = Get-ChildItem -Path $Path
    $toRemove = $items.Count
    $removed = 0
    # extract name from path
    $name = Split-Path -Path $Path -Leaf

    # process sublevel
    foreach ($item in $items) {
        $completed = ($removed / $toRemove) * 100
        # init & update progress bar
        if ($ParentId -eq 0) {
            Write-Progress -Id $current -Activity "Entfernen von $name" -Status "$item wird entfernt..." -PercentComplete $completed
        } else {
            Write-Progress -Id $current -Activity "Entfernen von $name" -Status "$item wird entfernt..." -PercentComplete $completed -ParentId $ParentId
        }

        # to much recursion will slow down the process strogly
        if ($item -is [System.IO.DirectoryInfo] -and $current -lt ($Id + $Levels)) {
            # call self on subfolders
            Remove-WithProgress -Path $item.FullName -ParentId $current -Id $Id
        }
        
        # finally remove item, ignore errors
        Remove-Item -Path $item.FullName -Force -Recurse -ErrorAction SilentlyContinue
        $removed++
    }

    # complete progress bar
    if ($ParentId -eq 0) {
        Write-Progress -Id $current -Activity "Entfernen von $name" -Status "Vorgang Abgeschlossen" -PercentComplete 100 -Completed
    } else {
        Write-Progress -Id $current -Activity "Entfernen von $name" -Status "Vorgang Abgeschlossen" -PercentComplete 100 -Completed -ParentId $ParentId
    }

    if ($EmptyOnly) {
        # recreate folder
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Get-Decision {
    <#
    .SYNOPSIS
    Prompts the user for a decision (y/n) based on a provided message.

    .DESCRIPTION
    The Get-Decision function prompts the user for a decision (yes/no) based on a provided message. 
    The function will keep prompting the user until a valid input ("y", "n" or empty) is provided. 
    If no input is provided, the function defaults to "yes".

    .PARAMETER Message
    The message to display to the user when prompting for a decision.

    .EXAMPLE
    Get-Decision -Message "Do you want to continue?"

    This will prompt the user with the message "Do you want to continue? (y/n, default: y)" and wait for a "y", "n" or empty response.

    .NOTES
    If the user enters anything other than "y" or "n" or empty, an error message will be displayed and the user will be prompted again.
    #>
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message
    )

    $decision = $true
    $inputString = $null
    # keep prompting until a valid input is provided
    while ($inputString -ne "j" -and $inputString -ne "n") {
        # 'Read-Host' will add a ':' to the end
        $inputString = Read-Host -Prompt "$Message (j/n, default: j)"

        if ([string]::IsNullOrEmpty($inputString)) {
            # default to yes if no input is provided
            break
        }

        if ($inputString -eq "j") {
            break
        } elseif ($inputString -eq "n") {
            $decision = $false
        } else {
            # do not log invalid input
            Write-Host "Eingabe $inputString ungültig. Bitte gib 'j' oder 'n' ein." -ForegroundColor Red
        }
    }
    return $decision
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

# only validate out-path if not map-only
if (-not $MapOnly) {
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
                Write-Out -Type "WARN" "Der angegebene Out-Pfad %s existiert bereits" $Out
                Write-Out "Leeren des Out-Ordners. Dies könnte einen Moment dauern..."
                Remove-WithProgress -Path $Out -EmptyOnly -Id 10
            } else {
                Write-Out -Type "ERROR" "Der angegebene Out-Pfad %s existiert bereits" $Out
                Exit-Error
            }
        }
    } catch {
        Write-Out -Type "ERROR" "Der angegebene Out-Pfad %s ist ungültig" $Out
        Exit-Error $_
    }
} else {
    # force it to PWD on map only
    $Out = $PWD
}

# update working directory to start the script
Set-Location $Path

# =====================================================================
# Variables Dependent on Parameters
# =====================================================================

$LOG_FILE = Join-Path $Out "cleanup.log"
$PROJECTS_FILE = Join-Path $Out "projects.json"

# =====================================================================
# Script
# =====================================================================

Write-Out "Indexierung von %s" $Path -ForceWriteLog

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

            # create index starting by 1
            $i = 1
            foreach ($value in $sorted) {
                Write-Out "[ %s ] %s - %s" $i ($value.date -f "yyyy-MM-dd HH:mm:ss") (Resolve-Path $value.path -Relative)
                $i += 1
            }

            $selectedIndex = -1
            # prompt until valid
            while ($selectedIndex -lt 1 -or $selectedIndex -ge ($sorted.Count + 1)) {
                $userInput = Read-Host -Prompt "Bitte wähle die primäre Version aus (1)"

                if ([string]::IsNullOrEmpty($userInput)) {
                    # set default if no value provided
                    $selectedIndex = 1
                    break
                }

                # validate number
                try {
                    $selectedIndex = [int] $userInput
                } catch {
                    Write-Out -Type "ERROR" "Eingabe %s ungültig. Bitte gib eine Zahl ein." $userInput
                    continue
                }
            }

            # remove 1 to get index since array starts at 0
            $primaryIndex = $selectedIndex - 1
            Write-Out "Gewählte Primäre Version [ %s ] %s" ($primaryIndex + 1) (Resolve-Path $sorted[$primaryIndex].path -Relative)
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
            Exit-Success
        } else {
            $useFlat = $false
            # evalute folder structure, update on interactive or flat switch
            if ($Interactive -and -not $Flat) {
                $useFlat = Get-Decision "Möchtest du die Projekte nach Datum sortiert abglegen?"
            } elseif ($Flat) {
                $useFlat = $true
            }
            Write-Out "Das Verschieben der Projekte wird vorbereitet"

            # create list of primary and versioned projects
            $primaryProjects = New-Object -TypeName System.Collections.ArrayList
            $versionProjects = New-Object -TypeName System.Collections.ArrayList

            # cloned to avoid mutating while iterating
            $keys = $INDEX.Keys | ForEach-Object { $_ }
            $keys | ForEach-Object {
                $projects = $INDEX[$_] | Sort-Object -Property primary -Descending
                $primary = $projects[0]
                $primaryName = $primary.path | Split-Path -Leaf

                $newPrimaryPath = $null
                if ($useFlat) {
                    $newPrimaryPath = Join-Path $Out $primaryName
                } else {
                    $newPrimaryPath = Join-Path $Out (Join-Path $primary.date.Year $primaryName)
                }

                # store primary project silently
                $primaryProjects.Add([PSCustomObject]@{
                        name    = $primaryName
                        path    = $primary.path
                        newPath = $newPrimaryPath
                    }) | Out-Null

                # add each versioned project as well
                for ($i = 1; $i -lt $projects.Count; $i++) {
                    $versionName = $projects[$i].path | Split-Path -Leaf
                    # they will be located in a subfolder '.versions' of the primary project
                    # the 'primary' property is used as a base path for the versioned projects
                    $versionProjects.Add([PSCustomObject]@{
                            parent  = $primaryName
                            name    = ".versions/v$($i)_$versionName"
                            path    = $projects[$i].path
                            primary = $newPrimaryPath
                        }) | Out-Null
                }
            }

            Write-Out "Die Projekte werden nach %s verschoben" $Out -ForceWriteLog -AddNewLine

            Write-Progress  -Id 20 -Activity "Verschieben der Projekte" -Status "-" -PercentComplete 0
            $primaryMoved = 0
            $primaryProjects | ForEach-Object {
                # update progress with current project
                Write-Progress -Id 20 -Activity "Verschieben der Projekte" -Status "Verschieben von $($_.name)" -PercentComplete ($primaryMoved / $primaryProjects.Count * 100)
                Move-WithProgress -Path $_.path -Destination $_.newPath -Id 20 -ParentId 20
                $primaryMoved++
                # fallback output to ensure even with no Progress bar the user gets some feedback
                Write-Out "Projekt %s erfolreich verschoben (%s/%s)" $_.name $primaryMoved $primaryProjects.Count
            }

            Write-Out "Die Primär Projekte wurden erfolgreich verschoben" -ForceWriteLog -AddNewLine

            # allow versioned projects to be moved as well
            if ($versionProjects.Count -gt 0) {
                $includeVerions = $true
                if ($Interactive -and -not $NoVersions) {
                    $includeVerions = Get-Decision "Möchtest du die $($versionProjects.Count) übrigen Versionen der Projekte mitverschieben?"
                } elseif ($NoVersions) {
                    $includeVerions = $false
                }
    
                if ($includeVerions) {
                    Write-Progress  -Id 20 -Activity "Verschieben der Projekte" -Status "-" -PercentComplete 0
                    $versionsMoved = 0
                    $versionProjects | ForEach-Object {
                        # update progress with current project version
                        Write-Progress -Id 20 -Activity "Verschieben der Versionen für $($_.parent)" -Status "Verschieben von $($_.name)" -PercentComplete ($versionsMoved / $versionProjects.Count * 100)
                        Move-WithProgress -Path $_.path -Destination (Join-Path $_.primary $_.name) -Id 20
                        $versionsMoved++
                        # fallback output to ensure even with no Progress bar the user gets some feedback
                        Write-Out "Projekt %s erfolreich verschoben (%s/%s)" "$($_.parent)/$($_.name)" $versionsMoved $versionProjects.Count
                    }
                }    
            }

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