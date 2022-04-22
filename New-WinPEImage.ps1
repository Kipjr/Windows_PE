Param(
    $branding = "all" #$env:INPUT_BRANDING
    $mdt = $false #$env:INPUT_MDT
    $arch="x64"
    $workingDirectory=$env:GITHUB_WORKSPACE
)
#https://go.microsoft.com/fwlink/?linkid=2165884 #ADK
#https://go.microsoft.com/fwlink/?linkid=2166133 #ADK Add-on WinPE
#https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-mount-and-customize?view=windows-11
#https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/use-dism-in-windows-powershell-s14?view=windows-11



$json=get-content -path .\env.json -raw | convertfrom-json
$adkPATH="C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit"
$WinPEPATH="$adkPATH\Windows Preinstallation Environment"
$DeployImagingToolsENV="$adkPATH\Deployment Tools\DandISetEnv.bat" #Deployment and Imaging Tools Environment
$WinPE_root = "$workingDirectory\WinPE_amd64\mount"
$ISO_root = "$workingDirectory\WinPE_amd64\media"

New-Item -ItemType Directory -Path . -Name temp -verbose #folder for temporary files                                                                                   
New-Item -ItemType Directory -Path . -Name source\Drivers\$branding -verbose #folder for drivers of $Brand
New-Item -ItemType Directory -Path . -Name source\_iso -verbose #folder for drivers of $Brand


function New-WinPE() {
    "Start the Deployment and Imaging Tools Environment & Create WinPE for amd64" | write-host -foregroundcolor magenta
    cmd /k """$DeployImagingToolsENV"" && copype.cmd amd64 ""$workingDirectory""\WinPE_amd64 && exit"
}

function New-FolderStructure() {
<# 
  generate folderstructure
#>

# Boot
# Deploy 
# EFI
# bootmgr
# bootmgr.efi    
    foreach($f in @("Tools","Templates","Servicing","Scripts","Packages","Out-of-Box Drivers","Operating Systems","Control","Captures","Boot","Backup","Applications","`$OEM`$")){
        New-Item -ItemType Directory -path  "$ISO_root" -name "$f"
    } #generate folderstructure
    get-childitem -Path $ISO_root\* -exclude @("bootmgr","bootmgr.efi","sources","Boot","EFI") -Depth 0 | remove-item #cleanup                                                                                                                                                                                                                  
}

function Mount-WinPE() {
    "Mounting boot.wim image" | write-host -foregroundcolor magenta
    Mount-WindowsImage -ImagePath "$ISO_root\sources\boot.wim" -index 1  -Path "$WinPE_root"
}

 Function Add-OptionalComponents() {
<# 
    Optional Components
 #>
    "Adding Optional Components to boot.wim" | write-host -foregroundcolor magenta
    foreach($c in $json.WinPEOptionalComponents){
        "Adding: $c" | write-host -foregroundcolor cyan
        Add-WindowsPackage -Path "$WinPE_root" -PackagePath "$WinPEPATH\amd64\WinPE_OCs\$c.cab" -PreventPending
        if(test-path -path "$WinPEPATH\amd64\WinPE_OCs\en-us\$c`_en-us.cab" ){
            Add-WindowsPackage -Path "$WinPE_root" -PackagePath "$WinPEPATH\amd64\WinPE_OCs\en-us\$c`_en-us.cab" -PreventPending
        } else {
         "$c`_en-us.cab not found.. continuing" | write-host -foregroundcolor cyan
        }
    }
 }
function Add-DefaultStartCommands(){
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
    if($MDT -eq $true) { "%SYSTEMROOT%\System32\bddrun.exe, /bootstrap" | Out-File -append -FilePath .\winpeshl.ini }
    if(test-path -path "$WinPE_root\windows\system32\winpeshl.ini") {
        rename-item "$WinPE_root\windows\system32\winpeshl.ini" "$WinPE_root\windows\system32\winpeshl.ini.old"
    }
    copy-item ./winpeshl.ini "$WinPE_root\windows\system32\winpeshl.ini"
}

function Add-FilesToWinPE() {
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
}

function Add-BootDrivers(){
<# 
    Add Drivers
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
    $infitem = get-childitem ".\source\Drivers" -Recurse  -Filter "*.inf" | where-object {$_.FullName -like "$arch" } | Select-Object -ExpandProperty FullName
        foreach($i in $infitem){
            if(test-path -path $i) {
                Add-WindowsDriver -Path "$WinPE_root" -Driver "$i"
        }
    }
}

Function get-HashOfContents() {
<# 
    Generating hash of contents
 #>
 
    "Generating hash of contents boot.wim " | write-host -foregroundcolor magenta #issue with access denied
     get-childitem "$WinPE_root" -Recurse -File | select @{n="File";e={$_.Fullname| Resolve-Path -Relative }}, @{n="SHA256_filehash";e={ ($_.fullname | Get-FileHash -Algorithm SHA256).hash }} | Export-Csv -Path .\filelist_boot.wim.csv -Delimiter ";"
}

Function Dismount-Image(){
<# 
    Umounting & create iso
 #>
 
    "Unmounting boot.wim image" | write-host -foregroundcolor magenta
    Dismount-WindowsImage -Path "$WinPE_root" -Save
}

Function Add-FilesToIso(){
    "Adding Contents of source\_iso to ISO" | write-host -ForegroundColor magenta
    copy-item -Path ".\source\_iso\*" -destination "$ISO_root" -recurse -verbose
}

Function Create-ISO(){
<# 
    Create ISO
 #>

    "Start the Deployment and Imaging Tools Environment & Create ISO file from WinPE_amd64 folder" | write-host -foregroundcolor magenta
    cmd /k """$DeployImagingToolsENV"" && makeWinPEMedia.cmd /ISO ""$workingDirectory""\WinPE_amd64 ""$workingDirectory""\WinPE_amd64.iso && exit"
}
# get-content -path "C:\Windows\Logs\DISM\dism.log" | Where-Object {$_ -like "$(get-date -f 'yyyy-MM-dd')*"} | Select-Object -Last 250

New-WinPE
New-FolderStructure
Mount-WinPE
Add-OptionalComponents
Add-DefaultStartCommands
Add-FilesToWinPE
Add-BootDrivers
Get-HashOfContents
Dismount-Image
Add-FilesToIso
Create-ISO
