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
    $global:orisize=get-item -path "$ISO_root\sources\boot.wim" | Select-Object -ExpandProperty length
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
    cmd /c "Dism /Set-ScratchSpace:512 /Image:""$WinPE_root"""
    
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
# function Add-DefaultStartCommands(){
# <#
# .SYNOPSIS
# Default Start commands, immediately after booting WinPe

# .NOTES
# General notes
#  #>

#     "Adding lines to winpeshl.ini" | write-host -ForegroundColor magenta
#     "[LaunchApps]" | Out-File -FilePath .\temp\winpeshl.ini #write to local file
#     foreach($p in $json.winpeshl_commands){
#         "$p" | write-host -ForegroundColor cyan
#         #run in order of appearance, and don’t start until the previous app has terminated.
#         #[LaunchApps]
#         "$p"  | Out-File -append -FilePath .\temp\winpeshl.ini
#         #%SYSTEMROOT%\System32\bddrun.exe /bootstrap
#     }
#     #if($MDT -eq $true) { "%SYSTEMROOT%\System32\bddrun.exe, /bootstrap" | Out-File -append -FilePath .\temp\winpeshl.ini }
#     if(test-path -path "$WinPE_root\windows\system32\winpeshl.ini") {
#         rename-item "$WinPE_root\windows\system32\winpeshl.ini" "$WinPE_root\windows\system32\winpeshl.ini.old"
#     }
#     copy-item .\temp\winpeshl.ini "$WinPE_root\windows\system32\winpeshl.ini"
# }


function Add-FilesToWinPE() {
<#
.SYNOPSIS
Add files & folders to WinPE (Boot.wim)

.NOTES
only from .\source\_winpe where name does not contain .ignore
#>

# replace the old background
    takeown /f "$WinPE_root\Windows\system32\winpe.jpg"
    icacls "$WinPE_root\Windows\system32\winpe.jpg" /grant everyone:f
    Remove-Item "$WinPE_root\Windows\system32\winpe.jpg"
    Copy-Item -Path "$workingdirectory\source\winpe.jpg" -Destination "$WinPE_root\Windows\system32\winpe.jpg" -Force


#custom files:
    "Adding Files & Folders to WinPE" | write-host -ForegroundColor magenta
    $folders = get-childitem -directory -Path ".\source\_winpe" -Recurse |  Where-Object {$_.FullName -notlike "*.ignore*"}  | select -ExpandProperty fullname
    $files = get-childitem -file -Path ".\source\_winpe" -Recurse |  Where-Object {$_.FullName -notlike "*.ignore*"}  | select -ExpandProperty fullname
    
    foreach($fo in $folders) {
        $shortpath = $fo.Substring("$workingdirectory\source\_winpe".length + 1,$fo.length-"$workingdirectory\source\_winpe".length - 1) #get relative path
        if(!(test-path -path "$WinPE_root\$shortpath")){
            New-Item -ItemType Directory "$WinPE_root\$shortpath" -verbose
        }
    }
    foreach($fi in $files) {
            $shortpath = $fi.Substring("$workingdirectory\source\_winpe".length + 1,$fi.length-"$workingdirectory\source\_winpe".length - 1) #get relative path
            copy-item -path  "$fi" -destination "$WinPE_root\$shortpath" -verbose
    }

}

function Add-AppsToWinPE(){
<#
.SYNOPSIS

.NOTES
General notes
#>

    # Powershell 7.2.2
    invoke-restmethod -OutFile ".\temp\pwsh.ps1"  -Uri 'https://aka.ms/install-powershell.ps1'
    .\temp\pwsh.ps1  -Destination "$WinPE_root\Program Files\PowerShell\7"

    #notepad ++
    invoke-restmethod -OutFile ".\temp\npp.8.3.3.portable.x64.zip" -uri "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.3.3/npp.8.3.3.portable.x64.zip"
    7z t ".\temp\npp.8.3.3.portable.x64.zip"
    if($LASTEXITCODE -eq 0){
        7z x -y ".\temp\npp.8.3.3.portable.x64.zip" -o"$WinPE_root\Program Files\Notepad++" 
    }
    #launchbar
    Invoke-RestMethod -OutFile ".\temp\LaunchBar_x64.exe" -Uri "https://www.lerup.com/php/download.php?LaunchBar/LaunchBar_x64.exe"
    copy-item ".\temp\LaunchBar_x64.exe" -Destination "$WinPE_root\windows\system32\" -verbose

    #freecommander
    Invoke-RestMethod -OutFile ".\temp\doublecmd-1.0.5.x86_64-win64.zip" -uri "https://deac-fra.dl.sourceforge.net/project/doublecmd/DC for Windows 64 bit/Double Commander 1.0.5 beta/doublecmd-1.0.5.x86_64-win64.zip"
    7z t ".\temp\doublecmd-1.0.5.x86_64-win64.zip"
    if($LASTEXITCODE -eq 0){
        7z x -y ".\temp\doublecmd-1.0.5.x86_64-win64.zip" -o"$WinPE_root\Program Files" 
    }    
        }
    }    
    #utils
    $json=@"
{
    "System32": [
        "System32\\label.exe",
        "System32\\logman.exe",
        "System32\\runas.exe",
        "System32\\sort.exe",
        "System32\\tzutil.exe",
        "System32\\Utilman.exe",
        "System32\\clip.exe",
        "System32\\eventcreate.exe",
        "System32\\forfiles.exe",
        "System32\\setx.exe",
        "System32\\timeout.exe",
        "System32\\waitfor.exe",
        "System32\\where.exe",
        "System32\\whoami.exe"
        ]
    }
"@ | convertfrom-json
    # $json.psobject.members.where({$_.MemberType -eq "NoteProperty"}).Name
    foreach($j in $json.system32){
        Copy-Item -path "$env:SystemRoot\$j" -Destination "$WinPE_root\windows\system32\" -verbose
    }
    #remote Desktop
    # Copy-Item -path "$env:SystemRoot\system32\d3d10_1.dll" "$WinPE_root\windows\system32\"
    # Copy-Item -path "$env:SystemRoot\system32\d3d10_1core.dll" "$WinPE_root\windows\system32\"
    # Copy-Item -path "$env:SystemRoot\system32\dxgi.dll" "$WinPE_root\windows\system32\"
    # Copy-Item -path "$env:SystemRoot\system32\msacm32.dll" "$WinPE_root\windows\system32\"
    # Copy-Item -path "$env:SystemRoot\system32\mstsc.exe" "$WinPE_root\windows\system32\"
    # Copy-Item -path "$env:SystemRoot\system32\mstscax.dll" "$WinPE_root\windows\system32\"
    # Copy-Item -path "$env:SystemRoot\system32\msvbvm60.dll" "$WinPE_root\windows\system32\"
    # Copy-Item -path "$env:SystemRoot\system32\msvfw32.dll" "$WinPE_root\windows\system32\"
    # Copy-Item -path "$env:SystemRoot\system32\en-us\msacm32.dll.mui" "$WinPE_root\windows\system32\en-us\"
    # Copy-Item -path "$env:SystemRoot\system32\en-us\mstsc.exe.mui" "$WinPE_root\windows\system32\en-us\"
    # Copy-Item -path "$env:SystemRoot\system32\en-us\mstscax.dll.mui" "$WinPE_root\windows\system32\en-us\"
    # Copy-Item -path "$env:SystemRoot\system32\en-us\msvfw32.dll.mui" "$WinPE_root\windows\system32\en-us\"

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
        if((test-path($b)) -and ($b -notlike ".\source\Drivers\$branding")){
            #it's a file path and not in .\source\Drivers\$branding
            Copy-Item -Path "$b" -Destination ".\source\Drivers\$branding" -Verbose
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
    "Injecting drivers from .\source\Drivers" | write-host -ForegroundColor cyan
    Add-WindowsDriver -Path "$WinPE_root" -Driver ".\source\Drivers\$branding" -verbose -Recurse
    
}


function Add-Updates(){
    <#
    .SYNOPSIS
    Add updates
    
    .NOTES
    
    #>
    Write-Host "Injecting updates from .\source\Updates"
    Get-ChildItem ".\source\Updates" | ForEach-Object { 
        Add-WindowsPackage -Path $WinPE_root -PackagePath ".\source\Updates\$_" 
    }
}

function Invoke-WinPEcleanup() {
<#
.SYNOPSIS
Clean stuff

.NOTES
General notes
#>

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
    $endsize=get-item -path "$ISO_root\Deploy\Boot\boot.wim" | Select-Object -ExpandProperty length
    #Export-WindowsImage -SourceImagePath "$ISO_root\Deploy\Boot\boot.wim"  -DestinationImagePath "$ISO_root\Deploy\Boot\boot.wim"  -SourceIndex 1 -Setbootable -compressionType max
    #$optsize=get-item -path "$ISO_root\Deploy\Boot\boot.wim" | Select-Object -ExpandProperty length
    "Size increase after modifying: $([float]($endsize / $global:orisize)) - $global:orisize-->$endsize" | write-host -foregroundcolor magenta
    #"Size reduction after optimizing $([float]($optsize / $endsize)) - $endsize-->$optsize" | write-host -foregroundcolor magenta
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
#Add-DefaultStartCommands
Add-FilesToWinPE
Add-AppsToWinPE
Add-OptionalComponents
Add-BootDrivers
#Add-Updates
#Invoke-WinPEcleanup
#Get-HashOfContents
Dismount-Image
Add-FilesToIso
Set-BCDData
New-ISO

set-location $old_loc