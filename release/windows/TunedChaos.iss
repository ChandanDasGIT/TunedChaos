; The Windows installer (Inno Setup 6): TunedChaos-<version>-setup-x64.exe.
; Built in CI from the same folder as the portable ZIP:
;   iscc /DAppVersion=1.0 /DSourceDir=<full path of dist\TunedChaos> /DOutputDir=<full path> release\windows\TunedChaos.iss
; (Relative paths are read from this file's folder.)
; Installs for the current user (no administrator prompt) into
; %LOCALAPPDATA%\Programs\TunedChaos, with a Start menu entry carrying the
; app's Windows id (which the song-change toasts and media controls need).
; Uninstalling keeps your settings and library (%LOCALAPPDATA%\TunedChaos).

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\dist\TunedChaos"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\installer"
#endif

[Setup]
; File types change: Explorer is told to look again
ChangesAssociations=yes
; (The id Windows knows the installed app by: never change it)
AppId={{5DCAD0ED-7FCC-42EE-95A0-8C212AF127B2}
AppName=Tuned Chaos
AppVersion={#AppVersion}
AppVerName=Tuned Chaos {#AppVersion}
AppPublisher=Chandan Das
AppPublisherURL=https://github.com/ChandanDasGIT/TunedChaos
AppSupportURL=https://github.com/ChandanDasGIT/TunedChaos/issues
DefaultDirName={autopf}\TunedChaos
DefaultGroupName=Tuned Chaos
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
LicenseFile={#SourceDir}\LICENSE
SetupIconFile=tunedchaos.ico
UninstallDisplayIcon={app}\TunedChaos.exe
UninstallDisplayName=Tuned Chaos
OutputDir={#OutputDir}
OutputBaseFilename=TunedChaos-{#AppVersion}-setup-x64
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; A running copy is closed first (its files are in use), and started again after an update
CloseApplications=yes
RestartApplications=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Tuned Chaos"; Filename: "{app}\TunedChaos.exe"; AppUserModelID: "ChandanDas.TunedChaos"
Name: "{autodesktop}\Tuned Chaos"; Filename: "{app}\TunedChaos.exe"; AppUserModelID: "ChandanDas.TunedChaos"; Tasks: desktopicon

[Registry]
; "Open with" for music files (not the default player: Windows asks the user)
Root: HKA; Subkey: "Software\Classes\TunedChaos.AudioFile"; ValueType: string; ValueData: "Music file (Tuned Chaos)"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\TunedChaos.AudioFile\DefaultIcon"; ValueType: string; ValueData: """{app}\TunedChaos.exe"",0"
Root: HKA; Subkey: "Software\Classes\TunedChaos.AudioFile\shell\open\command"; ValueType: string; ValueData: """{app}\TunedChaos.exe"" ""%1"""
Root: HKA; Subkey: "Software\Classes\Applications\TunedChaos.exe"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "Tuned Chaos"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Applications\TunedChaos.exe\shell\open\command"; ValueType: string; ValueData: """{app}\TunedChaos.exe"" ""%1"""
Root: HKA; Subkey: "Software\Classes\.mp3\OpenWithProgids"; ValueType: string; ValueName: "TunedChaos.AudioFile"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\TunedChaos.exe\SupportedTypes"; ValueType: string; ValueName: ".mp3"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\.flac\OpenWithProgids"; ValueType: string; ValueName: "TunedChaos.AudioFile"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\TunedChaos.exe\SupportedTypes"; ValueType: string; ValueName: ".flac"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\.ogg\OpenWithProgids"; ValueType: string; ValueName: "TunedChaos.AudioFile"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\TunedChaos.exe\SupportedTypes"; ValueType: string; ValueName: ".ogg"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\.oga\OpenWithProgids"; ValueType: string; ValueName: "TunedChaos.AudioFile"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\TunedChaos.exe\SupportedTypes"; ValueType: string; ValueName: ".oga"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\.opus\OpenWithProgids"; ValueType: string; ValueName: "TunedChaos.AudioFile"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\TunedChaos.exe\SupportedTypes"; ValueType: string; ValueName: ".opus"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\.m4a\OpenWithProgids"; ValueType: string; ValueName: "TunedChaos.AudioFile"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\TunedChaos.exe\SupportedTypes"; ValueType: string; ValueName: ".m4a"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\.aac\OpenWithProgids"; ValueType: string; ValueName: "TunedChaos.AudioFile"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\TunedChaos.exe\SupportedTypes"; ValueType: string; ValueName: ".aac"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\.wav\OpenWithProgids"; ValueType: string; ValueName: "TunedChaos.AudioFile"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\TunedChaos.exe\SupportedTypes"; ValueType: string; ValueName: ".wav"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\.wma\OpenWithProgids"; ValueType: string; ValueName: "TunedChaos.AudioFile"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\TunedChaos.exe\SupportedTypes"; ValueType: string; ValueName: ".wma"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\.webm\OpenWithProgids"; ValueType: string; ValueName: "TunedChaos.AudioFile"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\TunedChaos.exe\SupportedTypes"; ValueType: string; ValueName: ".webm"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\.ape\OpenWithProgids"; ValueType: string; ValueName: "TunedChaos.AudioFile"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\TunedChaos.exe\SupportedTypes"; ValueType: string; ValueName: ".ape"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\.wv\OpenWithProgids"; ValueType: string; ValueName: "TunedChaos.AudioFile"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\TunedChaos.exe\SupportedTypes"; ValueType: string; ValueName: ".wv"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\.aiff\OpenWithProgids"; ValueType: string; ValueName: "TunedChaos.AudioFile"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\TunedChaos.exe\SupportedTypes"; ValueType: string; ValueName: ".aiff"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\.aif\OpenWithProgids"; ValueType: string; ValueName: "TunedChaos.AudioFile"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\TunedChaos.exe\SupportedTypes"; ValueType: string; ValueName: ".aif"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\.m3u\OpenWithProgids"; ValueType: string; ValueName: "TunedChaos.AudioFile"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\TunedChaos.exe\SupportedTypes"; ValueType: string; ValueName: ".m3u"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\.m3u8\OpenWithProgids"; ValueType: string; ValueName: "TunedChaos.AudioFile"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\TunedChaos.exe\SupportedTypes"; ValueType: string; ValueName: ".m3u8"; ValueData: ""

[Run]
Filename: "{app}\TunedChaos.exe"; Description: "{cm:LaunchProgram,Tuned Chaos}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; The folder itself, once empty (yt-dlp's updates and the user's data live elsewhere)
Type: dirifempty; Name: "{app}"
