# Windows_PE
Automatic build &amp; customization of WinPE

## Basic

```mermaid
flowchart TB
    WR[Winlogon.exe reads HKLM\System\Setup\CmdLine:<br> winpeshl.exe]
    WP[winpeshl.exe runs]
    SE{%SYSTEMDRIVE%\sources\setup.exe exist?}
    RE[Run Setup.exe]
    RW[Read winpeshl.ini]
    AP{Winpeshl.ini exist and has valid content?}
    RS[Run <br>cmd /k %SYSTEMROOT\system32\startnet.cmd]
    SN[Startnet.cmd: <br>wpeinit.exe]
    RA[Run applications as specified in winpeshl.ini<br>Default: %SYSTEMROOT%\System32\bddrun.exe /bootstrap]
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
    PO --> LF
    LF --> BI
    BI --> LB
    subgraph WBM [Windows Boot Manager]
        LB --> BM
        BM --> RB
    end
    RB --> WL 
    subgraph WBL [Windows Boot Loader]
        WL --> LO
    end
    subgraph KRN [Windows NT OS Kernel]
        LO --> NL
        NL --> SM
        SM -.-> W3
        SM --> WN
    end
    
end
WN--> WR
subgraph WinPE 
    WR --> WP --> SE
    SE --> |yes| RE 
    SE --> |no | RW
    RW --> AP
    AP --> |yes| RA
    AP --> |no | RS

subgraph cmd [cmd.exe]
    RS --> SN
    
end
    SN -.-> WI
    RA --> BD
    BD --> WI
    WI -.-> UE
    
    
    UE --> |yes| UX 

    UX --> LT --> LP

    LP --> |no| NT
    LP --> |yes| ET

    NT --> |ZTIGather| BS
    BS --> WW
    WW --> CS
    CS --> DW
    DW --> RT
    RT --> ET

end


    UX -...- |ERROR| cmd


```

## Customization
- Mount <br>`Dism /Mount-Image /ImageFile:"C:\WinPE_amd64\media\sources\boot.wim" /index:1 /MountDir:"C:\WinPE_amd64\mount"`
- Unmount <br> `Dism /Unmount-Image /MountDir:"C:\WinPE_amd64\mount" /commit`
- ToISO <br> `MakeWinPEMedia /ISO C:\WinPE_amd64 C:\WinPE_amd64\WinPE_amd64.iso`

### Drivers
- `Dism /Add-Driver /Image:"C:\WinPE_amd64\mount" /Driver:"C:\SampleDriver\driver.inf"`

### Files
- Add to C:\WinPE_amd64\mount folder. 
  - These files will show up in the X:
- C:\WinPE_amd64\mount\Windows\System32\Startnet.cmd
  - `%SYSTEMROOT%\System32\Startnet.cmd`
- `Wpeinit -unattend:"C:\Unattend.xml"`
### Enabled components
- WinPE-HTA
- WinPE-WMI
- WinPE-NetFX
- WinPE-Scripting
- WinPE-SecureStartup
- WinPE-PlatformID
- WinPE-PowerShell
- WinPE-DismCmdlets
- WinPE-SecureBootCmdlets
### Optional Components

WinPE-DismCmdlets
WinPE-Dot3Svc
WinPE-EnhancedStorage
WinPE-FMAPI
WinPE-Fonts-Legacy
WinPE-Font Support-JA-JP
WinPE-Font Support-KO-KR
WinPE-Font Support-ZH-CN
WinPE-Font Support-ZH-HK
WinPE-GamingPeripherals
Winpe-LegacySetup
WinPE-MDAC
WinPE-PlatformID
WinPE-PPPoE
WinPE-Rejuv
WinPE-RNDIS
WinPE-Setup
WinPE-Setup-Client
WinPE-Setup-Server
WinPE-SRT
WinPE-StorageWMI
WinPE-WDS-Tools
WinPE-WiFi-Package
WinPE-WinReCfg
## Documentation

[WinPE Optional Components](https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-add-packages--optional-components-reference?view=windows-11)

