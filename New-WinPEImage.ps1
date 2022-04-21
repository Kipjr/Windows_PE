#https://go.microsoft.com/fwlink/?linkid=2165884 #ADK
#https://go.microsoft.com/fwlink/?linkid=2166133 #ADK Add-on WinPE
#https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-mount-and-customize?view=windows-11
#https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/use-dism-in-windows-powershell-s14?view=windows-11

$arch="x64"
$branding = $env:INPUT_BRANDING
$json=get-content -path .\env.json -raw | convertfrom-json
$adkPATH="C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit"
$WinPEPATH="$adkPATH\Windows Preinstallation Environment"
$DeployImagingToolsENV="$adkPATH\Deployment Tools\DandISetEnv.bat" #Deployment and Imaging Tools Environment
New-Item -ItemType Directory -Path . -Name sources\Drivers\$branding -verbose #folder for drivers of $Brand

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
    Add files & folders to WinPE
 #>
 
"Adding Files & Folders to WinPE" | write-host -ForegroundColor magenta
$oldloc=get-location 
set-location .\source\_winpe
$folders = get-childitem -directory -Path "." -Recurse |  Where-Object {$_.FullName -notlike "*.ignore*"}  | Resolve-Path -Relative
$files = get-childitem -file -Path "." -Recurse |  Where-Object {$_.FullName -notlike "*.ignore*"}   | Resolve-Path -Relative

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
foreach($b in $json.bootdrivers.$branding){
    "$b" | write-host -ForegroundColor cyan
    if((test-path($b)) -and ($b -like ".\source\Drivers\*")){
        #it's a file path and in .\source\Drivers\
    }
    elseif($b -match 'https?://.*?\.(zip|rar|exe|7z|cab)') {
        #it's a web url
        $filename = $b | split-path -Leaf
        $foldername = $filename | Split-Path -LeafBase
        $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        $session.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.4896.127 Safari/537.36"
        Invoke-WebRequest -UseBasicParsing -Uri "$b" -WebSession $session -OutFile .\temp\$filename
        #Expand-Archive -Path  -DestinationPath .\source\Drivers\$foldername
        7z t ".\temp\$filename"
        if($LASTEXITCODE -eq 0){
            7z x -y ".\temp\$filename" -o".\source\Drivers\$branding\$foldername" 
        } else {
            "unable to extract $b " | write-host -ForegroundColor cyan
            continue
        }
    }
    else {
        "$b is not a file or an URL" | write-host -ForegroundColor cyan
        continue
    }
}
$infitem = get-childitem ".\source\Drivers\" -Recurse  -Filter "*.inf" | where-object {$_.FullName -like "$arch" } | Select-Object -ExpandProperty FullName
    foreach($i in $infitem){
        if(test-path -path $i) {
            Add-WindowsDriver -Path "$env:GITHUB_WORKSPACE\WinPE_amd64\mount" -Driver "$i"
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


"Adding Contents of source\_iso to ISO" | write-host -ForegroundColor magenta
copy-item -Path ".\source\_iso" -destination "$env:GITHUB_WORKSPACE\WinPE_amd64" -recurse -verbose


<# 
    Create ISO
 #>

"Start the Deployment and Imaging Tools Environment & Create ISO file from WinPE_amd64 folder" | write-host -foregroundcolor magenta
cmd /k """$DeployImagingToolsENV"" && makeWinPEMedia.cmd /ISO %GITHUB_WORKSPACE%\WinPE_amd64 %GITHUB_WORKSPACE%\WinPE_amd64_$branding.iso && exit"

# get-content -path "C:\Windows\Logs\DISM\dism.log" | Where-Object {$_ -like "$(get-date -f 'yyyy-MM-dd')*"} | Select-Object -Last 250

