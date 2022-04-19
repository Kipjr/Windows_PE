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
    Mount-WindowsImage -ImagePath "$env:GITHUB_WORKSPACE\WinPE_amd64\media\sources\boot.wim" -index 1  -Path "$env:GITHUB_WORKSPACE\WinPE_amd64\mount"
    

    "Adding Optional Components" | write-host -foregroundcolor magenta
    foreach($c in $json.WinPEOptionalComponents){
        "Adding: $c" | write-host -foregroundcolor cyan
        Add-WindowsPackage -Path "$env:GITHUB_WORKSPACE\WinPE_amd64\mount" -PackagePath "$WinPEOCPath\$c.cab" -PreventPending
        Add-WindowsPackage -Path "$env:GITHUB_WORKSPACE\WinPE_amd64\mount" -PackagePath "$WinPEOCPath\en-us\$c`_en-us.cab" -PreventPending
        
    }

<#     "Adding lines to winpeshl.ini" | write-host -ForegroundColor magenta
    "[LaunchApps]" | Out-File -FilePath .\winpeshl.ini
    
    foreach($p in $json.winpeshl_commands){
        "$c" | write-host -ForegroundColor cyan
        #run in order of appearance, and don’t start until the previous app has terminated.
        #[LaunchApps]
        "$c"  | Out-File -FilePath .\winpeshl.ini
        #%SYSTEMROOT%\System32\bddrun.exe /bootstrap
    }
    "%SYSTEMROOT%\System32\bddrun.exe, /bootstrap" | Out-File -FilePath .\winpeshl.ini
    rename-item "$env:GITHUB_WORKSPACE\WinPE_amd64\mount\windows\system32\winpeshl.ini" "$env:GITHUB_WORKSPACE\WinPE_amd64\mount\windows\system32\winpeshl.ini.old"
    copy-item ./winpeshl.ini "$env:GITHUB_WORKSPACE\WinPE_amd64\mount\windows\system32\winpeshl.ini" #>
    
<#     "Adding drivers" | write-host -ForegroundColor magenta    
    foreach($b in $json.bootdrivers){
        "$b" | write-host -ForegroundColor cyan
        Add-WindowsDriver -Path "$env:GITHUB_WORKSPACE\WinPE_amd64\mount" -Driver "$b" -ForceUnsigned
    }
 #>
    "Unmounting image" | write-host -foregroundcolor magenta
    Dismount-WindowsImage -Path "$env:GITHUB_WORKSPACE\WinPE_amd64\mount" -Save
    
    "Start the Deployment and Imaging Tools Environment & Create ISO file" | write-host -foregroundcolor magenta
    cmd /k """$DeployImagingToolsENV"" && makeWinPEMedia.cmd /ISO %GITHUB_WORKSPACE%\WinPE_amd64 %GITHUB_WORKSPACE%\WinPE_amd64.iso && exit"
#} catch {
 #   get-content -path "C:\Windows\Logs\DISM\dism.log" | Where-Object {$_ -like "$(get-date -f 'yyyy-MM-dd')*"} | Select-Object -Last 250
#}
