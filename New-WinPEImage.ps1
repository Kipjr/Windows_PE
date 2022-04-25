Param(
    [ValidateSet("all", "none", "hp","dell","lenovo","vmware")]$branding="vmware",    
    [switch]$mdt,
    [ValidateSet("amd64", "x86", "arm","arm64")]$arch="amd64",
    [string]$workingDirectory=$env:GITHUB_WORKSPACE,
    [string]$apps=$env:INPUT_APPS
)
#https://go.microsoft.com/fwlink/?linkid=2165884 #ADK
#https://go.microsoft.com/fwlink/?linkid=2166133 #ADK Add-on WinPE
#https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-mount-and-customize?view=windows-11
#https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/use-dism-in-windows-powershell-s14?view=windows-11


$json=get-content -path .\env.json -raw | convertfrom-json

$mdt = $mdt.IsPresent
$old_loc=$PWD

if($arch -eq "amd64"){$arch_short="x64"} else {$arch_short=$arch} #amd64 to x64
set-variable -name adkPATH      -value  "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit" -verbose
set-variable -name WinPEPATH    -value  "$adkPATH\Windows Preinstallation Environment" -verbose 
set-variable -name DeployImagingToolsENV -value "$adkPATH\Deployment Tools\DandISetEnv.bat" -verbose  #Deployment and Imaging Tools Environment
$old_loc=$PWD
if(!(test-path -path $workingDirectory)){new-item -itemtype directory -path $workingDirectory}   
set-location $workingDirectory
set-variable -name WinPE_root   -value  "$workingDirectory\WinPE_$arch\mount" -verbose 
set-variable -name ISO_root     -value  "$workingDirectory\WinPE_$arch\media" -verbose

if(!(test-path -path $workingDirectory)){new-item -itemtype directory -path $workingDirectory}   
if(!(test-path -path $workingDirectory\source)){copy-item -Path .\source -destination $workingDirectory -recurse}
set-location $workingDirectory
New-Item -ItemType Directory -Path $workingDirectory -Name temp -force -verbose #folder for temporary files                                                                                   
New-Item -ItemType Directory -Path $workingDirectory -Name source\Drivers\$branding -force  -verbose #folder for drivers of $Brand

function New-WinPE() {
<#
.SYNOPSIS
Create new WinPE Environment

.NOTES
outputfolder will contain:
- fwfiles: efisys.bin,etfsboot.com
- media: sources, bootmgr,bootmgr.efi, EFI, BOOT
- mount: empty
#>
    "Start the Deployment and Imaging Tools Environment & Create WinPE for $arch" | write-host -foregroundcolor magenta
    cmd /c """$DeployImagingToolsENV"" && copype.cmd $arch ""$workingDirectory\WinPE_$arch"" && exit"
    if(!(test-path -path "$workingDirectory\WinPE_$arch") -or ($LASTEXITCODE -eq 1)){
        "unable to create $workingDirectory\WinPE_$arch" | write-host -foregroundcolor cyan
        set-location $old_loc
        exit 1
    }
    remove-item -path "$workingDirectory\WinPE_$arch\fwfiles\efisys.bin" #fix press key to boot from dvd
    copy-item -path "$adkPATH\Deployment Tools\amd64\Oscdimg\efisys_noprompt.bin" -Destination "$workingDirectory\WinPE_$arch\fwfiles\efisys.bin"
}

function New-FolderStructure() {
<#
.SYNOPSIS
generate folderstructure

.NOTES
    Boot
    Deploy\Boot\{boot.wim -> LiteTouchPE_x64.wim} 
    EFI
    bootmgr
    bootmgr.efi    
#>
    get-childitem -Path $ISO_root\* -exclude @("bootmgr","bootmgr.efi","sources","Boot","EFI") -Depth 0 | remove-item -recurse #cleanup
    foreach($f in @("Tools","Templates","Servicing","Scripts","Packages","Out-of-Box Drivers","Operating Systems","Control","Captures","Boot","Backup","Applications","`$OEM`$")){
        New-Item -ItemType Directory -path  "$ISO_root\Deploy" -name "$f"
    } #generate folderstructure
    move-item -path "$ISO_root\sources\boot.wim" "$ISO_root\Deploy\Boot\"
    remove-item -path "$ISO_root\sources" -force 
}

function Mount-WinPE() {
<#
.SYNOPSIS
mount boot.wim to WinPE_$arch\mount

.NOTES
General notes
#>
    "Mounting boot.wim image" | write-host -foregroundcolor magenta
    Mount-WindowsImage -ImagePath "$ISO_root\Deploy\Boot\boot.wim" -index 1  -Path "$WinPE_root"
    cmd /c "Dism /Set-ScratchSpace:1024 /Image:""$WinPE_root"""
}

 Function Add-OptionalComponents() {
<#
.SYNOPSIS
Add WinPE Optional Components

.NOTES
General notes
#>

    "Adding Optional Components to boot.wim" | write-host -foregroundcolor magenta
    foreach($c in $json.WinPEOptionalComponents){
        "Adding: $c" | write-host -foregroundcolor cyan
        Add-WindowsPackage -Path "$WinPE_root" -PackagePath "$WinPEPATH\$arch\WinPE_OCs\$c.cab" -PreventPending
        if(test-path -path "$WinPEPATH\$arch\WinPE_OCs\en-us\$c`_en-us.cab" ){
            Add-WindowsPackage -Path "$WinPE_root" -PackagePath "$WinPEPATH\$arch\WinPE_OCs\en-us\$c`_en-us.cab" -PreventPending
        } else {
            "$c`_en-us.cab not found.. continuing" | write-host -foregroundcolor cyan
        }
    }
}
function Add-DefaultStartCommands(){
<#
.SYNOPSIS
Default Start commands, immediately after booting WinPe

.NOTES
General notes
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
    if($MDT -eq $true) { "%SYSTEMROOT%\System32\bddrun.exe, /bootstrap" | Out-File -append -FilePath .\winpeshl.ini }
    if(test-path -path "$WinPE_root\windows\system32\winpeshl.ini") {
        rename-item "$WinPE_root\windows\system32\winpeshl.ini" "$WinPE_root\windows\system32\winpeshl.ini.old"
    }
    copy-item ./winpeshl.ini "$WinPE_root\windows\system32\winpeshl.ini"
}

function Add-FilesToWinPE() {
<#
.SYNOPSIS
Add files & folders to WinPE (Boot.wim)

.NOTES
only from .\source\_winpe where name does not contain .ignore
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
}

function Add-BootDrivers(){
<#
.SYNOPSIS
Add Boot-critical Drivers from HP,Dell or Lenovo

.NOTES
Net, Disk, Chipset (Thunderbolt)
#>

    $arr = if($branding -eq "all") {
        $json.bootdrivers.PSOBJect.Properties.value
    } elseif($branding -eq "none") {
        $null
    } else {
        $json.bootdrivers.$branding
    }
    "Adding drivers" | write-host -ForegroundColor magenta    
    foreach($b in $arr){
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
    $infitem = get-childitem ".\source\Drivers" -Recurse  -Filter "*.inf" | where-object {$_.FullName -like "*$arch_short*" } | Select-Object -ExpandProperty FullName
    foreach($i in $infitem){
        "adding $i" | write-host -ForegroundColor cyan
        Add-WindowsDriver -Path "$WinPE_root" -Driver "$i" -verbose
    }
}

Function get-HashOfContents() {
<#
.SYNOPSIS
Create hash of filecontens of boot.wim

.NOTES
General notes
#>

    "Generating hash of contents boot.wim " | write-host -foregroundcolor magenta #issue with access denied
    get-childitem "$WinPE_root" -Recurse -File | select @{n="File";e={$_.Fullname| Resolve-Path -Relative }}, @{n="SHA256_filehash";e={ ($_.fullname | Get-FileHash -Algorithm SHA256).hash }} | Export-Csv -Path .\filelist_boot.wim.csv -Delimiter ";"
}

Function Dismount-Image(){
<#
.SYNOPSIS
Unmount /mount to boot.wim

.NOTES
General notes
#>
 
    "Unmounting boot.wim image" | write-host -foregroundcolor magenta
    Dismount-WindowsImage -Path "$WinPE_root" -Save
}

Function Add-FilesToIso(){
<#
.SYNOPSIS
Add other files to iso file

.NOTES
General notes
#>
    "Adding Contents of source\_iso to ISO" | write-host -ForegroundColor magenta
    copy-item -Path ".\source\_iso\*" -destination "$ISO_root" -recurse -verbose
}

Function Set-BCDData() {
<#
.SYNOPSIS
from .\WinPE_$arch create .iso file

.NOTES
General notes
#>

    "update *.wim in BCD" | write-host -foregroundcolor magenta
    $wimPath =  get-childitem -path $ISO_root\*.wim -Recurse | select -ExpandProperty FullName #find wim and get path
    $filePath = $wimpath.substring($ISO_root.length, ($wimpath.length - $ISO_root.length) ) #get relative path
    
    #bcdedit [/store <filename>] /set [{<id>}] <datatype> <value>
    
    $bcdPath1 = "$ISO_root\Boot\BCD" #Legacy
    $bcdstring1 = $(Get-BcdEntry -Store $bcdPath1  -id default).elements.where({$_.name -eq "device"}).value  #win11 only module
    $bcdstring1 = $bcdstring1.Replace("\sources\boot.wim",$filePath)
    $commands1= @("device","osdevice") | foreach-object { "bcdedit --% /store `"$bcdpath1`" /set `{default`} $_ $bcdstring1" } #https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_parsing?view=powershell-7.2#the-stop-parsing-token
    $commands1 | foreach-object { invoke-expression $_ }

    $bcdPath2 = "$ISO_root\EFI\Microsoft\Boot\BCD" #EFI
    $bcdstring2 = $(Get-BcdEntry -Store $bcdPath2 -id default).elements.where({$_.name -eq "device"}).value  #win11 only module
    $bcdstring2 = $bcdstring2.Replace("\sources\boot.wim",$filePath)
    $commands2= @("device","osdevice") | foreach-object { "bcdedit --% /store `"$bcdpath2`" /set `{default`} $_ $bcdstring2" } #https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_parsing?view=powershell-7.2#the-stop-parsing-token
    $commands2 | foreach-object { invoke-expression $_ }
}

Function New-ISO(){
<#
.SYNOPSIS
from .\WinPE_$arch create .iso file

.NOTES
General notes
#>

    "Start the Deployment and Imaging Tools Environment & Create ISO file from WinPE_$arch folder" | write-host -foregroundcolor magenta
    cmd /k """$DeployImagingToolsENV"" && makeWinPEMedia.cmd /ISO ""$workingDirectory\WinPE_$arch"" ""$workingDirectory\WinPE_$arch.iso"" && exit"
}
# get-content -path "C:\Windows\Logs\DISM\dism.log" | Where-Object {$_ -like "$(get-date -f 'yyyy-MM-dd')*"} | Select-Object -Last 250

New-WinPE
New-FolderStructure
Mount-WinPE
Add-OptionalComponents
Add-DefaultStartCommands
Add-FilesToWinPE
Add-BootDrivers
#Get-HashOfContents
Dismount-Image
Add-FilesToIso
Set-BCDData
New-ISO

set-location $old_loc