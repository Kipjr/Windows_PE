#https://go.microsoft.com/fwlink/?linkid=2165884 #ADK
#https://go.microsoft.com/fwlink/?linkid=2166133 #ADK Add-on WinPE
#https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-mount-and-customize?view=windows-11

$json=get-content -path .\env.json -raw | convertfrom-json
$adkPATH="C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit"
$WinPEPATH="$adkPATH\Windows Preinstallation Environment"
$WinPEOCPath="$WinPEPATH\amd64\WinPE_OCs"

$dismPATH="$env:systemroot\System32\Dism.exe" 
$DeployImagingToolsENV="$adkPATH\Deployment Tools\DandISetEnv.bat" #Deployment and Imaging Tools Environment

function DismAddPackage {
    Param(
        [string]$image=".\WinPE_amd64\mount",
        [Parameter(Mandatory=$true)][string]$packageName
    )
    try {
        $packagePath = if(test-path "$WinPEPath\$packageName.cab") { $="$WinPEOCPath\$packageName.cab" } else {$null}
        $LangpackagePath = if(test-path "$WinPEPath\en-us\$packageName.cab") { "$WinPEOCPath\en-us\$packageName`_en-us.cab" } else {$null}
    }
    catch {
        write-host "Issue with $packageName.cab"| write-host -foregroundcolor red
        exit 1
    }
    
    $command1="$dismPATH /Mount-Image /ImageFile`:$image /PackagePath:$packagePath"
    $command2="$dismPATH /Mount-Image /ImageFile`:$image /PackagePath:$LangpackagePath"

    & $command1
    & $command2
}

try {
    "Start the Deployment and Imaging Tools Environment & create winpe for amd64" | write-host -foregroundcolor magenta
    cmd /k """$DeployImagingToolsENV"" && copype.cmd amd64 %GITHUB_WORKSPACE%\WinPE_amd64 && exit"
    

    "Mounting image" | write-host -foregroundcolor magenta
    & "$env:systemroot\System32\Dism.exe" /Mount-Image /ImageFile:"$env:GITHUB_WORKSPACE\WinPE_amd64\media\sources\boot.wim" /index:1 /MountDir:"$env:GITHUB_WORKSPACE\WinPE_amd64\mount"

    "Adding Optional Components" | write-host -foregroundcolor magenta
    foreach($c in $json.WinPEOptionalComponents){
        "Adding: $c" | write-host -foregroundcolor cyan
        DismAddPackage -packageName $c
    }

    "Unmounting image" | write-host -foregroundcolor magenta
    & "$env:systemroot\System32\Dism.exe" /Unmount-Image /MountDir:"$env:GITHUB_WORKSPACE\WinPE_amd64\mount" /commit

    "Start the Deployment and Imaging Tools Environment & Create ISO file" | write-host -foregroundcolor magenta
    cmd /k """$DeployImagingToolsENV"" && makeWinPEMedia.cmd /ISO %GITHUB_WORKSPACE	%\WinPE_amd64 %GITHUB_WORKSPACE	%\WinPE_amd64.iso && exit"
} catch {
    get-content -path "C:\Windows\Logs\DISM\dism.log" | Where-Object {$_ -like "$(get-date -f 'yyyy-MM-dd')*"} | Select-Object -Last 250
}