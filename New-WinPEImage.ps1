#https://go.microsoft.com/fwlink/?linkid=2165884 #ADK
#https://go.microsoft.com/fwlink/?linkid=2166133 #ADK Add-on WinPE
#https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-mount-and-customize?view=windows-11
#https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/use-dism-in-windows-powershell-s14?view=windows-11

$json=get-content -path .\env.json -raw | convertfrom-json
$adkPATH="C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit"
$WinPEPATH="$adkPATH\Windows Preinstallation Environment"
$WinPEOCPath="$WinPEPATH\amd64\WinPE_OCs"

$DeployImagingToolsENV="$adkPATH\Deployment Tools\DandISetEnv.bat" #Deployment and Imaging Tools Environment


    
    


#try {
    "Start the Deployment and Imaging Tools Environment & create winpe for amd64" | write-host -foregroundcolor magenta
    cmd /k """$DeployImagingToolsENV"" && copype.cmd amd64 %GITHUB_WORKSPACE%\WinPE_amd64 && exit"
    

    "Mounting image" | write-host -foregroundcolor magenta
    Mount-WindowsImage -ImagePath "$env:GITHUB_WORKSPACE\WinPE_amd64\media\sources\boot.wim"  -Path "$env:GITHUB_WORKSPACE\WinPE_amd64\mount"
    

    "Adding Optional Components" | write-host -foregroundcolor magenta
    foreach($c in $json.WinPEOptionalComponents){
        "Adding: $c" | write-host -foregroundcolor cyan
        Add-WindowsPackage -Path "$env:GITHUB_WORKSPACE\WinPE_amd64\mount" -PackagePath "$WinPEOCPath\$c.cab"
        Add-WindowsPackage -Path "$env:GITHUB_WORKSPACE\WinPE_amd64\mount" -PackagePath "$WinPEOCPath\en-us\$c.cab"
    }

    "Unmounting image" | write-host -foregroundcolor magenta
    Dismount-WindowsImage -Path "$env:GITHUB_WORKSPACE\WinPE_amd64\mount" -Save
    
    "Start the Deployment and Imaging Tools Environment & Create ISO file" | write-host -foregroundcolor magenta
    cmd /k """$DeployImagingToolsENV"" && makeWinPEMedia.cmd /ISO %GITHUB_WORKSPACE%\WinPE_amd64 %GITHUB_WORKSPACE%\WinPE_amd64.iso && exit"
#} catch {
 #   get-content -path "C:\Windows\Logs\DISM\dism.log" | Where-Object {$_ -like "$(get-date -f 'yyyy-MM-dd')*"} | Select-Object -Last 250
#}
