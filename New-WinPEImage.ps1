#https://go.microsoft.com/fwlink/?linkid=2165884 #ADK
#https://go.microsoft.com/fwlink/?linkid=2166133 #ADK Add-on WinPE
#https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-mount-and-customize?view=windows-11

set-location ${Env:WORKING-DIRECTORY}
$json=get-content -path ./env.json -raw | convertfrom-json
$dismloc="$env:systemroot\System32\Dism.exe"

function DismAddPackage {
    Param(
        [string]$image="${Env:WORKING-DIRECTORY}\WinPE_amd64\mount",
        [Parameter(Mandatory=$true)][string]$packageName
    )
    
    $WinPEPath="C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs"
    
    try {
        $packagePath = if(test-path "$WinPEPath\$packageName.cab") { $="$WinPEPath\$packageName.cab" } else {$null}
        $LangpackagePath = if(test-path "$WinPEPath\en-us\$packageName.cab") { "$WinPEPath\en-us\$packageName`_en-us.cab" } else {$null}
    }
    catch {
        write-host "Issue with $packageName.cab"| write-host -foregroundcolor red
        exit 1
    }
    
    $command1="$dismloc /Mount-Image /ImageFile`:$image /PackagePath:$package"
    $command2="$dismloc /Mount-Image /ImageFile`:$image /PackagePath:$LangpackagePath"

    & $command1
    & $command2
}


#Start the Deployment and Imaging Tools Environment as an administrator.
copype amd64 C:\WinPE_amd64

"Mounting image" | write-host -foregroundcolor magenta
& "$env:systemroot\System32\Dism.exe" /Mount-Image /ImageFile:"${Env:WORKING-DIRECTORY}\WinPE_amd64\media\sources\boot.wim" /index:1 /MountDir:"C:\WinPE_amd64\mount"

"Adding Optional Components" | write-host -foregroundcolor magenta
foreach($c in $json.WinPEOptionalComponents){
    "Adding: $c" | write-host -foregroundcolor cyan
    DismAddPackage -packageName $c
}

"Unmounting image" | write-host -foregroundcolor magenta
& "$env:systemroot\System32\Dism.exe" /Unmount-Image /MountDir:"${Env:WORKING-DIRECTORY}\WinPE_amd64\mount" /commit

"Create ISO file" | write-host -foregroundcolor magenta
MakeWinPEMedia /ISO "${Env:WORKING-DIRECTORY}\WinPE_amd64" "${Env:WORKING-DIRECTORY}\WinPE_amd64.iso"
