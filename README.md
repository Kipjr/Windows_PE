# Windows_PE
[![Create WinPE_amd64.iso](https://github.com/Kipjr/Windows_PE/actions/workflows/main.yml/badge.svg)](https://github.com/Kipjr/Windows_PE/actions/workflows/main.yml) 
[![Donate](https://img.shields.io/badge/Donate-PayPal-green.svg)](https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=C7HN4VAGBTQFS&currency_code=EUR)
<a href="https://www.buymeacoffee.com/kipjr" target="_blank"><img src="https://user-images.githubusercontent.com/12066560/94989781-8bd26280-0577-11eb-9482-26faff60e95d.png" alt="Buy Me A Coffee" style="height: 20px !important;width: 72px !important;" ></a>


Automatic build &amp; customization of WinPE


- [Windows_PE](#windows_pe)
  * [Basic](#basic)
  * [Customization](#customization)
    + [Drivers](#drivers)
    + [Files](#files)
    + [Enabled components](#enabled-components)
    + [Inactive Components](#inactive-components)
  * [Documentation](#documentation)
    + [Full Windows UEFI Boot schematic of Windows PE](#full-windows-uefi-boot-schematic-of-windows-pe)

## Basic

- New-WinPE
- New-FolderStructure
  - _change bloated structure to MDT-based structure_
    -  Remove root language folders and sources
    -  Add MDT-structure and move `boot.wim` to `Deploy\Boot`
- Mount-WinPE
- Add-FilesToWinPE
  - _Loop over contents `source\_winpe`_
- Add-AppsToWinPE
  - _Download applications (portable) and installs to target path_
- Add-OptionalComponents
- Add-BootDrivers
  - _none, all, hp, dell, lenovo, vmware_
  - _Release will contain 'all'_
- Add-Updates
  - `Disabled`
- Invoke-WinPEcleanup
  -  `Disabled`
- Get-HashOfContents
  -  `Disabled` due to permsssion issue in boot.wim system files
- Dismount-Image
- Add-FilesToIso
  - _Loop over contents `source\_iso`_
- Set-BCDData
  - _Required due to folder structure change_
- New-ISO

_Screenshot after <15sec boot:_

![image](https://user-images.githubusercontent.com/12066560/165970164-51bd4f18-9192-4082-a866-2cdbacbd5caa.png)






## Customization
### Basic commands
- Mount <br>`Mount-WindowsImage -ImagePath "$ISO_root\Deploy\Boot\boot.wim" -index 1  -Path "$WinPE_root"`
- Unmount <br> `Dismount-WindowsImage -Path "$WinPE_root" -Save`
- ToISO <br> `makeWinPEMedia.cmd /ISO $workingDirectory\WinPE_$arch workingDirectory\WinPE_$arch.iso`

### Drivers
- `Add-WindowsDriver -Path "$WinPE_root" -Driver ".\source\Drivers\$branding" -verbose -Recurse"`

### Applications

- Launchbar 
  - Quicklaunch for apps
- DeploymentMonitoringTool.exe (included in source)
  - Get info about current machine
- CMTrace_amd64.exe (included in source)
  - Read MDT and other logs
- Process Explorer
- 7-Zip
- Powershell 7.2.2+
- Notepad++
- DoubleCMD
  - File Explorer as Explorer.exe is unavailable 
- Missing executables and added:
  - label
  - logman
  - runas
  - sort
  - tzutil
  - Utilman
  - clip
  - eventcreate
  - forfiles
  - setx
  - timeout
  - waitfor
  - where
  - whoami.exe

### Files
- WinPE (X:\)
  - Add to `$workingDirectory\WinPE_$arch\mount` folder.
  - Included files in `source\_winpe\Windows\System32` to be added to `$workingDirectory\WinPE_$arch\mount\Windows\System32`
    - CMTrace_amd64.exe
    - DeploymentMonitoringTool.exe
    - LaunchBar_x64.exe
    - launchbar.ini
    - test.bat
    - winpeshl.ini 
- ISO
  - Add to `"$workingDirectory\WinPE_$arch\media"` folder


### Enabled components
<details>
  <summary>Click to show</summary>
    
- WinPE-HTA
- WinPE-WMI
- WinPE-NetFX
- WinPE-Scripting
- WinPE-SecureStartup
- WinPE-PlatformID
- WinPE-PowerShell
- WinPE-DismCmdlets
- WinPE-SecureBootCmdlets
- WinPE-StorageWMI
- WinPE-EnhancedStorage
- WinPE-Dot3Svc
- WinPE-FMAPI
- WinPE-FontSupport-WinRE
- WinPE-PlatformId
- WinPE-WDS-Tools
- WinPE-WinReCfg
</details>
    
#### Inactive Components
<details>
  <summary>Click to show</summary>
    
- WinPE-Fonts-Legacy
- WinPE-Font Support-JA-JP
- WinPE-Font Support-KO-KR
- WinPE-Font Support-ZH-CN
- WinPE-Font Support-ZH-HK
- WinPE-GamingPeripherals
- Winpe-LegacySetup
- WinPE-MDAC
- WinPE-PPPoE
- WinPE-Rejuv
- WinPE-RNDIS
- WinPE-Setup
- WinPE-Setup-Client
- WinPE-Setup-Server
- WinPE-SRT
- WinPE-WiFi-Package
</details>


## Documentation

- [WinPE Optional Components](https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-add-packages--optional-components-reference?view=windows-11)


## Full Windows UEFI Boot schematic of Windows PE

```mermaid

%%{init: {'theme': 'dark', 'themeVariables': { 'darkMode': 'true'}}}%%


flowchart TB
    WR[Winlogon.exe reads HKLM\System\Setup\CmdLine:<br> winpeshl.exe]
    WP[winpeshl.exe runs]
    SE{%SYSTEMDRIVE%\sources\setup.exe exist?}
    RE[Run Setup.exe]
    RW[Read winpeshl.ini]
    AP{Winpeshl.ini exist and has valid content?}

    A1[Run App1.exe with parameter /parameter1]


    MD{MDT is included?}
    RS[Run <br>cmd /k %SYSTEMROOT\system32\startnet.cmd]
    SN[Startnet.cmd: <br>wpeinit.exe]

    RA[Run applications as specified in winpeshl.ini<br><br><i>Run app in order of appearance <br>Starts when the previous app has terminated.</i>]

    UE{Unattend.xml exist?}
    UX[Unattend.xml:<br>RunSynchronousCommand<br> wscript.exe X:\Deploy\Scripts\LiteTouch.wsf]
    WI[wpeinit.exe]
    BD[bddrun.exe]
    LT[LiteTouch.wsf]
    LP{Check if there are any Task Sequences in progress <br>c:\minint and/or <br>c:\_SMSTaskSequence\TSEnv.dat}
    ET[Execute Task Sequence]
    NT[New Task Sequence]
    BS[Bootstrap.ini]
    CS[CustomSettings.ini from DeployRoot]
    WW[Welcome Wizard]
    DW[Deployment Wizard]
    RT[Run Task Sequence]

    PO[POST]
    LF[Launch UEFI Firmware]
    BI[Get Boot Info from SRAM]
    LB[Launch Windows Boot Manager]
    BM[EFI-BOOT-BOOTX64]
    RB[Read BCD-file]
    WL[Launch Boot Loader<br>Boot.wim:<br>Winload.efi]
    LO[Load HAL, Registry, Boot Drivers]
    NL[Ntoskrnl.exe]
    SM[SMSS.exe]
    W3[Win32k.sys]
    WN[Winlogon.exe]



subgraph UEFI [UEFI Boot]
    PO ==> LF
    LF ==> BI
    BI ==> LB
    subgraph WBM [Windows Boot Manager]
        LB ==> BM
        BM ==> RB
    end
    RB ==> WL
    subgraph WBL [Windows Boot Loader]
        WL ==> LO
    end
    subgraph KRN [Windows NT OS Kernel]
        LO ==> NL
        NL ==> SM
        SM -.-> W3
        SM ==> WN
    end

end
WN==> WR
subgraph WinPE
    WR ==> WP ==> SE
    SE ==> |yes| RE
    SE ==> |no | RW
    RW ==> AP
    AP ==> |yes| RA

    MD ==> |yes| BD
    MD ==> |no| Error
    RA ==>| %SYSTEMDRIVE%\Apps\App1.exe, /parameter1 | A1
    RA ==>| %SYSTEMROOT%\System32\bddrun.exe, /bootstrap | MD
    AP ==> |no | RS



subgraph cmd [cmd.exe]
    RS ==> SN
end

    
subgraph MDT [MDT]
    SN -.-> WI
    BD ==> WI
    WI -.-> UE
    UE ==> |yes| UX
    UX ==> LT ==> LP
    LP ==> |no| NT
    LP ==> |yes| ET
    NT ==> |ZTIGather| BS
    BS ==> WW
    WW ==> CS
    CS ==> DW
    DW ==> RT
    RT ==> ET
end

end
UX -...- |ERROR| cmd

```

