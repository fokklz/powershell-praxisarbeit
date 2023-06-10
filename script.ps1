# =====================================================================
# Programm: praxisarbeit.ps1
# Aufruf: praxisarbeit.ps1 [-Root] <string> [-UseContent] [-Manual]
# Beschreibung: Aufräumen eines Shared drives. Projekte extrahieren & im root neu anordnen
# Autor: Fokko Vo
# Version: 1.0.0
# Datum: 23.05.2023
# =====================================================================

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
    [switch]$Flat # keep all projects in root when moving
)

# =====================================================================
# Variables
# =====================================================================

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

# may not start with highlighted part
# same %s as additional parameter

function Exit-Error {
    # reset working directory
    Set-Location $OG_PWD
    Write-Out -Type "ERROR" $args.Exception -ForceWriteLog -LogOnly
    exit 1
}   

function Write-Out {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,
        [string]$Type = "INFO",
        [switch]$LogOnly,
        [switch]$ForceWriteLog,
        [Parameter(ValueFromRemainingArguments = $true)]
        $highlighted
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
    }

    $LOG_TEMP.Add("$(Get-Date -Format "dd-MM-yyyy HH:mm:ss") [$Type] $fullMessage") | Out-Null

    if ($LOG_TEMP.Count -gt 30 -or $ForceWriteLog) {
        $LOG_TEMP | Out-File -FilePath $LOG_FILE -Append
        $LOG_TEMP.Clear()
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

    # read trough folder, call self on all subfolders
    Get-ChildItem -Path $Path -Directory | Where-Object {
        $_.FullName -notmatch $BLACKLIST
    } | Select-Object FullName | ForEach-Object {
        if (-not (Test-Project -Path $_.FullName)) {
            # to much?, Write-Out "Verzeichnis %s wird gelesen..." (Resolve-Path -Path $_.FullName -Relative)
            Find-Projects -Path $_.FullName
        } else {
            $hash = Get-Hash $_.FullName

            # create project index, if not existing
            if (-not $INDEX.ContainsKey($hash)) {
                $INDEX.Add($hash, (New-Object -TypeName System.Collections.ArrayList))
            }

            $data = [PSCustomObject]@{
                path    = $_.FullName
                date    = (Get-LastModificationDate $_.FullName)
                primary = $false
            }

            # add date and path
            [void]$INDEX[$hash].Add($data)
            
            Write-Out "Projekt %s gefunden" $hash
            Write-Out "  - %s`n" (Resolve-Path -Path $_.FullName -Relative)
        }
        
    }
}


function Test-Project {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path
    )

    foreach ($projectFile in $PROJECT_FILES) {
        if (Test-Path -Path (Join-Path -Path $Path -ChildPath $projectFile)) {
            return $true
        }
    }

    return $false
}

function Write-ProjectsJSON {
    $storableProjects = New-Object -TypeName System.Collections.Hashtable
    foreach ($key in $INDEX.Keys) {
        $values = $INDEX[$key] | ForEach-Object { $_ }
        for ($i = 0; $i -lt $values.Count; $i++) {
            $values[$i].date = $values[$i].date.ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
        $storableProjects.Add($key, $values)
    }
    $storableProjects | ConvertTo-Json -Depth 2 | Out-File -FilePath $PROJECTS_FILE -Encoding UTF8
}

# =====================================================================
# Validation
# =====================================================================

# ensure parameters are not null or empty
if ([string]::IsNullOrEmpty($Path)) {
    Write-Out -Type "ERROR" "Der Parmaeter '-Path' darf nicht leer sein"
    Exit-Error
}
if ([string]::IsNullOrEmpty($Path)) {
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
    New-Item -Path $Out -ItemType Directory -Force -ErrorAction Stop | Out-Null
    if ((Get-ChildItem -Path $Out).Length -gt 0) {
        # help user to not overwrite existing files if not desired
        if ($Force) {
            Write-Out -Type "WARN" "Der angegebene Out-Pfad %s existiert bereits und wird überschrieben" $Out
            Remove-Item -Path "$Out/*" -Recurse -Force
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

$LOG_FILE = Join-Path -Path $Out -ChildPath "cleanup.log"
$PROJECTS_FILE = Join-Path -Path $Out -ChildPath "projects.json"

# =====================================================================
# Script
# =====================================================================

Write-Out -Type "SYSTEM" "Starte Ausführung von Cleanup-Skript" -LogOnly
Write-Out "Aufräumen von %s nach %s" $Path $Out -ForceWriteLog

try {
    Find-Projects -Path $Path

    # clone keys
    $keys = $INDEX.Keys | ForEach-Object { $_ }
    $totalProjectCount = 0
    # set primary projects
    foreach ($key in $keys) {
        $sorted = $INDEX[$key] | Sort-Object -Property date -Descending
        $primaryIndex = $null
        # calculate total count
        $totalProjectCount += $sorted.Count
        
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

                if ($input -eq "" -or $input -eq $null) {
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
        # write findings summary
        Write-Out "`n`n%s Versionen, %s Projekte gefunden" $totalProjectCount $INDEX.Count
        if ($MapOnly) {
            Write-ProjectsJSON
            Write-Out "Die Projekte wurden als JSON in %s gespeichert`n" $PROJECTS_FILE -ForceWriteLog
            exit 0
        } else {
            
        }
    }
        
    Write-Out -Type "WARN" "Keine Projekte gefunden`n" -ForceWriteLog
    exit 0
} catch {
    Write-Out -Type "ERROR" "Fehler beim Aufräumen von %s" $Path
    Write-Out -Type "ERROR" $_.Exception.Message
    Exit-Error $_
}