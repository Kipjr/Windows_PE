#https://go.microsoft.com/fwlink/?linkid=2165884 #ADK
#https://go.microsoft.com/fwlink/?linkid=2166133 #ADK Add-on WinPE
#https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-mount-and-customize?view=windows-11
#https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/use-dism-in-windows-powershell-s14?view=windows-11

$json=get-content -path .\env.json -raw | convertfrom-json
$adkPATH="C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit"
$WinPEPATH="$adkPATH\Windows Preinstallation Environment"
$DeployImagingToolsENV="$adkPATH\Deployment Tools\DandISetEnv.bat" #Deployment and Imaging Tools Environment

<# 
    Creation of WinPE
 #>
 
"Start the Deployment and Imaging Tools Environment & Create WinPE for amd64" | write-host -foregroundcolor magenta
cmd /k """$DeployImagingToolsENV"" && copype.cmd amd64 %GITHUB_WORKSPACE%\WinPE_amd64 && exit"

"Mounting boot.wim image" | write-host -foregroundcolor magenta
Mount-WindowsImage -ImagePath "$env:GITHUB_WORKSPACE\WinPE_amd64\media\sources\boot.wim" -index 1  -Path "$env:GITHUB_WORKSPACE\WinPE_amd64\mount"
$WinPE_root = "$env:GITHUB_WORKSPACE\WinPE_amd64\mount"

<# 
    Optional Components
 #>
 
"Adding Optional Components to boot.wim" | write-host -foregroundcolor magenta
foreach($c in $json.WinPEOptionalComponents){
    "Adding: $c" | write-host -foregroundcolor cyan
    Add-WindowsPackage -Path "$env:GITHUB_WORKSPACE\WinPE_amd64\mount" -PackagePath "$WinPEPATH\amd64\WinPE_OCs\$c.cab" -PreventPending
    if(test-path -path "$WinPEPATH\amd64\WinPE_OCs\en-us\$c`_en-us.cab" ){
        Add-WindowsPackage -Path "$env:GITHUB_WORKSPACE\WinPE_amd64\mount" -PackagePath "$WinPEPATH\amd64\WinPE_OCs\en-us\$c`_en-us.cab" -PreventPending
    } else {
     "$c`_en-us.cab not found.. continuing" | write-host -foregroundcolor cyan
    }
}

<# 
    Default Start commands
 #>
 
"Adding lines to winpeshl.ini" | write-host -ForegroundColor magenta
"[LaunchApps]" | Out-File -FilePath .\winpeshl.ini #write to local file
foreach($p in $json.winpeshl_commands){
    "$p" | write-host -ForegroundColor cyan
    #run in order of appearance, and don’t start until the previous app has terminated.
    #[LaunchApps]
    "$p"  | Out-File -append -FilePath .\winpeshl.ini
    #%SYSTEMROOT%\System32\bddrun.exe /bootstrap
}
"%SYSTEMROOT%\System32\bddrun.exe, /bootstrap" | Out-File -append -FilePath .\winpeshl.ini
if(test-path -path "$env:GITHUB_WORKSPACE\WinPE_amd64\mount\windows\system32\winpeshl.ini") {
    rename-item "$env:GITHUB_WORKSPACE\WinPE_amd64\mount\windows\system32\winpeshl.ini" "$env:GITHUB_WORKSPACE\WinPE_amd64\mount\windows\system32\winpeshl.ini.old"
}
copy-item ./winpeshl.ini "$env:GITHUB_WORKSPACE\WinPE_amd64\mount\windows\system32\winpeshl.ini"

<# 
    Add files & folders
 #>
 
"Adding Files & Folders" | write-host -ForegroundColor magenta
$oldloc=get-location 
set-location .\source\_winpe
$folders = get-childitem -directory -Path "." -Recurse |  where {$_.FullName -notlike "*.ignore*"}  | Resolve-Path -Relative
$files = get-childitem -file -Path "." -Recurse |  where {$_.FullName -notlike "*.ignore*"}   | Resolve-Path -Relative

foreach($fo in $folders) {
    if(!(test-path -path "$WinPE_root\$fo")){
        New-Item -ItemType Directory "$WinPE_root\$fo" -verbose
    }
}
foreach($fi in $files) {
        copy-item -path  "$fi" -destination "$WinPE_root\$fi" -verbose
}
Set-Location $oldloc

<# 
    Add Drivers
 #>
 
"Adding drivers" | write-host -ForegroundColor magenta    
foreach($b in $json.bootdrivers){
    "$b" | write-host -ForegroundColor cyan
    $infitem = get-childitem $json.bootdrivers -Recurse  -Filter "*.inf" | select -ExpandProperty FullName
    foreach($i in $infitem){
        if(test-path -path $i) {
            Add-WindowsDriver -Path "$env:GITHUB_WORKSPACE\WinPE_amd64\mount" -Driver "$i" -ForceUnsigned
        }
    }
}

<# 
    Generating hash of contents
 #>
 
# "Generating hash of contents boot.wim " | write-host -foregroundcolor magenta #issue with access denied
 #get-childitem "$env:GITHUB_WORKSPACE\WinPE_amd64\mount" -Recurse -File | select @{n="File";e={$_.Fullname| Resolve-Path -Relative }}, @{n="SHA256_filehash";e={ ($_.fullname | Get-FileHash -Algorithm SHA256).hash }} | Export-Csv -Path .\filelist_boot.wim.csv -Delimiter ";"

<# 
    Umounting & create iso
 #>
 
"Unmounting boot.wim image" | write-host -foregroundcolor magenta
Dismount-WindowsImage -Path "$env:GITHUB_WORKSPACE\WinPE_amd64\mount" -Save

"Start the Deployment and Imaging Tools Environment & Create ISO file from mount folder" | write-host -foregroundcolor magenta
cmd /k """$DeployImagingToolsENV"" && makeWinPEMedia.cmd /ISO %GITHUB_WORKSPACE%\WinPE_amd64 %GITHUB_WORKSPACE%\WinPE_amd64.iso && exit"

# get-content -path "C:\Windows\Logs\DISM\dism.log" | Where-Object {$_ -like "$(get-date -f 'yyyy-MM-dd')*"} | Select-Object -Last 250

