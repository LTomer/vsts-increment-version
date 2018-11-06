﻿[CmdletBinding()]
param()

function Get-VersionPattern {
    return "\d+\.\d+\.\d+\.\d+"
}

function Get-Pattern($filePath, $versionType) {

    Write-Debug "Get-Pattern: [FileName=$filePath, VersionType=$versionType]"

    $isCS = $filePath.ToLower().endswith(".cs")
    $isCSPROJ = $filePath.ToLower().endswith(".csproj")

    if($isCS -and ($versionType -ne "AssemblyVersion" -and $versionType -ne "AssemblyFileVersion")){
        Write-Error "Version Property not valid for cs file ($versionType)"
        return;
    }
    elseif ($isCSPROJ -and ($versionType -ne "AssemblyVersion" -and $versionType -ne "FileVersion" -and $versionType -ne "Version")){
        Write-Error "Version Property not valid for csproj file ($versionType)"
        return;
    }
    
    # AssemblyVersion, AssemblyFileVersion
    if($isCS)    {
        $pattern = '\[assembly\: __TYPE__\("__VersionPattern__)"\)\]'
    }
    # AssemblyVersion, FileVersion, Version
    elseif ($isCSPROJ) {
        $pattern = "<__TYPE__>(__VersionPattern__)</__TYPE__>"
    }
    else
    {
        Write-Error "File type unknow."
        return;
    }

    $versionPattern = Get-VersionPattern
    return $pattern.Replace("__VersionPattern__", $versionPattern).Replace("__TYPE__", $versionType);
}

function Get-CurrentVersion($filePath, $versionProperty) {

    Write-Debug "Get-CurrentVersion: [FileName=$filePath, VersionProperty=$versionProperty]"

    $pattern = Get-Pattern -filePath $filePath -versionType $versionProperty
    $contents = [System.IO.File]::ReadAllText($filePath)
    $tempString = [RegEx]::Match($contents, $pattern)

    Write-Debug  "---> Line Version: $tempString"

    $versionPattern = Get-VersionPattern
    $versionString = [RegEx]::Match($tempString.Value, $versionPattern)

    Write-Debug "---> Version: $versionString"

    if (-not $versionString.Value) {
        Write-Error "cs File not contain version number."
    }

    return $versionString.Value
}

function Get-IncVersion($versionType, $currentVersion, $customVersion) {
    
    Write-Debug "Get-IncVersion: [VersionType=$versionType, CurrentVersion=$currentVersion, CustomVersion=$customVersion]"

    if ($versionType -eq "Custom") {
        if(-not $customVersion)
        {
            Write-Error "Custom Type is Empty"
            return;
        }
        
        $versionType = $customVersion
    }

    if ($versionType -eq 0 -or $versionType -eq "None") {
        Write-Host ("AssemblyFileVersion without change.")
        return;
    }

    $incVersion = $currentVersion
    $version = [version]$currentVersion
    if ($versionType -eq 1 -or $versionType -ieq "Major") {
        $incVersion = "{0}.{1}.{2}.{3}" -f ($version.Major + 1), 0, 0, 0
    }
    ElseIf ($versionType -eq 2 -or $versionType -ieq "Minor") {
        $incVersion = "{0}.{1}.{2}.{3}" -f $version.Major, ($version.Minor + 1), 0, 0
    }
    ElseIf ($versionType -eq 3 -or $versionType -ieq "Build") {
        $incVersion = "{0}.{1}.{2}.{3}" -f $version.Major, $version.Minor, ($version.Build + 1), 0
    }
    ElseIf ($versionType -eq 4 -or $versionType -ieq "Revision") {
        $incVersion = "{0}.{1}.{2}.{3}" -f $version.Major, $version.Minor, $version.Build, ($version.Revision + 1)
    }
    Else {
        try {
            $a = [version]$versionType

            if ($a.Revision -eq -1) {
                Write-Error "Version type not valid, Not contain 4 digit ($versionType)"
                return
            }

            $incVersion = $versionType
        }
        Catch {
            Write-Error "Version type not valid ($versionType)"
            return
        }
    }
    return [string]$incVersion
}

function Update-Version($filePath, $versionProperty, $currentVersion, $newVersion) {

    Write-Debug "Update-Version: [FileName=$filePath, VersionProperty=$versionProperty, CurrentVersion=$currentVersion, NewVersion=$newVersion]"

    $contents = [System.IO.File]::ReadAllText($filePath)
    $pattern = Get-Pattern -filePath $filePath -versionType $versionProperty

    $currentLine = [RegEx]::Match($contents, $pattern)
    $newLine = $currentLine.Value -replace $currentVersion, $newVersion
    $contents = $contents.Replace($currentLine.Value, $newLine)

    [System.IO.File]::WriteAllText($filePath, $contents)
}


Write-Debug "---> Read VSTS Inputs"
#Read Detail from vsts inputs
$filePath = Get-VstsInput -Name filePath -Require
$versionType = Get-VstsInput -Name versionType -Require
$variableName = Get-VstsInput -Name variableName -Require
$customVersion = Get-VstsInput -Name CustomType
$versionProperty = Get-VstsInput -Name versionProperty -Require
$updateIncVersion = Get-VstsInput -Name updateIncVersion -Require

$currentVersion = Get-CurrentVersion -filePath $filePath -versionProperty $versionProperty
Write-Host ("Current Version: " + $currentVersion)

$newVersion = Get-IncVersion -versionType $versionType -currentVersion $currentVersion -customVersion $customVersion

if($variableName)
{
    Write-Debug "--> Update variable with new version"
    Write-Host ("New Version: " + $newVersion)
    Write-Host ("##vso[task.setvariable variable=$variableName]$newVersion")
}

if($updateIncVersion -and $newVersion -and $currentVersion -ne $newVersion){
    Write-Host ("Check-Out & Update file with new version")
    tf checkout $filePath

    Update-Version -filePath $filePath -versionProperty $versionProperty -currentVersion $currentVersion -newVersion $newVersion
}