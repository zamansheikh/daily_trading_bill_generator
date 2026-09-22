; Inno Setup script for the Windows installer.
; Build the app first:  flutter build windows --release
; Then compile this script with Inno Setup 6 (https://jrsoftware.org/isinfo.php).

#define AppName "Daily Trading Bill Generator"
#define AppVersion "1.3.0"
#define AppPublisher "Daily Trading Corporation"
#define AppExe "daily_trading_bill_generator.exe"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{7D2C6C4B-1E7B-4C1B-9E1F-4A3B2C1D0E9F}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
OutputDir=output
OutputBaseFilename=DailyTradingBillGenerator-{#AppVersion}-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
UninstallDisplayIcon={app}\{#AppExe}
SetupIconFile=..\windows\runner\resources\app_icon.ico
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes
AppMutex=DailyTradingBillGeneratorMutex

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"

[Run]
Filename: "{app}\{#AppExe}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
