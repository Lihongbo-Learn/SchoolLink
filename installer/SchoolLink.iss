#define MyAppName "校联 SchoolLink"
#define MyAppVersion "0.2.0_dev"
#define MyAppPublisher "SchoolLink"
#define MyAppExeName "school_link.exe"
#define SourceDir "..\dist\SchoolLink-Windows"

[Setup]
AppId={{6D3C7B62-8F1B-4C22-9A4B-8E5D8A6C2F11}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\SchoolLink
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=SchoolLink-Setup-{#MyAppVersion}
SetupIconFile=..\apps\app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "快捷方式："; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\校联 SchoolLink"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\校联 Hub 服务端"; Filename: "{app}\hub\SchoolLinkHub.exe"; WorkingDir: "{app}\hub"; Parameters: "--port 8421 --web-root ""{app}\web"""
Name: "{group}\卸载校联"; Filename: "{uninstallexe}"
Name: "{userdesktop}\校联 SchoolLink"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动校联"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Classroom mode lock, profiles and local cache live here. Hub data is kept in
; %LOCALAPPDATA%\SchoolLinkHub and is intentionally preserved.
Type: filesandordirs; Name: "{userappdata}\cn.schoollink"
