[CmdletBinding()]
param()

function Get-VersionPattern {
    return "\d+\.\d+\.\d+\.\d+"
}

function Get-Pattern($filePath, $VersionProperty) {

    Write-Debug "Get-Pattern: [FileName=$filePath, VersionProperty=$VersionProperty]"

    $isCS = $filePath.ToLower().endswith(".cs")
    $isCSPROJ = $filePath.ToLower().endswith(".csproj")

    if($isCS -and ($VersionProperty -ne "AssemblyVersion" -and $VersionProperty -ne "AssemblyFileVersion")){
        Write-Error "Version Property not valid for cs file ($VersionProperty)"
        return;
    }
    elseif ($isCSPROJ -and ($VersionProperty -ne "AssemblyVersion" -and $VersionProperty -ne "FileVersion" -and $VersionProperty -ne "Version")){
        Write-Error "Version Property not valid for csproj file ($VersionProperty)"
        return;
    }
    
    # AssemblyVersion, AssemblyFileVersion
    if($isCS)    {
        $pattern = '\[assembly\: __TYPE__\("__VersionPattern__"\)\]'
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
    return $pattern.Replace("__VersionPattern__", $versionPattern).Replace("__TYPE__", $VersionProperty);
}

function Get-CurrentVersion($filePath, $VersionProperty) {

    Write-Debug "Get-CurrentVersion: [FileName=$filePath, VersionProperty=$VersionProperty]"

    if($VersionProperty -eq "AllCSVersion"){
        $VersionProperty = "AssemblyVersion"
    }
    $pattern = Get-Pattern -filePath $filePath -VersionProperty $VersionProperty
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

function Update-Version($FilePath, $versionProperty, $newVersion) {

    Write-Debug "Update-Version: [FileName=$FilePath, VersionProperty=$versionProperty, NewVersion=$newVersion]"

    $pattern = Get-Pattern -filePath $FilePath -VersionProperty $versionProperty

    $contents = [System.IO.File]::ReadAllText($FilePath)

    $currentLine = [RegEx]::Match($contents, $pattern) #Get relevant line

    $versionPattern = Get-VersionPattern
    $version = [RegEx]::Match($currentLine, $versionPattern) #Get current version

    $newLine = $currentLine.Value -replace $version, $newVersion #Update new version
    $contents = $contents.Replace($currentLine.Value, $newLine) #Update contents

    [System.IO.File]::WriteAllText($FilePath, $contents) #Save contents to file
}


Write-Debug "---> Read VSTS Inputs"
#Read Detail from vsts inputs
$filePathInput = Get-VstsInput -Name filePath -Require
$versionTypeInput = Get-VstsInput -Name versionType -Require
$variableNameInput = Get-VstsInput -Name variableName -Require
$customVersionInput = Get-VstsInput -Name CustomType
$versionPropertyInput = Get-VstsInput -Name versionProperty -Require
$updateIncVersionInput = Get-VstsInput -Name updateIncVersion -Require

$currentVersion = Get-CurrentVersion -filePath $filePathInput -VersionProperty $versionPropertyInput
Write-Host ("Current Version: " + $currentVersion)

$newVersion = Get-IncVersion -versionType $versionTypeInput -currentVersion $currentVersion -customVersion $customVersionInput

if($variableNameInput)
{
    Write-Debug "--> Update variable with new version"
    Write-Host ("New Version: " + $newVersion)
    Write-Host ("##vso[task.setvariable variable=$variableNameInput]$newVersion")
}

if($updateIncVersionInput -and $newVersion -and $currentVersion -ne $newVersion){
    Write-Host ("Check-Out & Update file with new version")
    tf checkout $filePathInput

    if($versionPropertyInput -eq "AllCSVersion"){
        Update-Version -FilePath $filePathInput -VersionProperty "AssemblyVersion" -newVersion $newVersion
        Update-Version -FilePath $filePathInput -VersionProperty "AssemblyFileVersion" -newVersion $newVersion
    }
    else{
        Update-Version -FilePath $filePathInput -VersionProperty $versionPropertyInput -newVersion $newVersion
    }
}