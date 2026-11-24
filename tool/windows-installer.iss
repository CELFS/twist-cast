#define BundleDir AddBackslash(SourcePath) + "..\build\windows\x64\runner\Release"
#define PackageVersion AppVersion + "." + BuildNumber
#if GetVersionNumbersString(BundleDir + "\twist_cast.exe") != PackageVersion
  #error Windows executable version does not match the release.
#endif

[Setup]
AppId=app.twist.cast
AppName=TwistCast
AppVersion={#AppVersion}
AppPublisher=TwistCast contributors
VersionInfoVersion={#PackageVersion}
DefaultDirName={localappdata}\Programs\TwistCast
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputBaseFilename=twist-cast-{#AppVersion}-windows-x64-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\twist_cast.exe
Compression=lzma2
SolidCompression=yes

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Excludes: "*.pdb,*.lib,*.exp"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#NoticesDir}\*"; DestDir: "{app}\Licenses"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{autoprograms}\TwistCast"; Filename: "{app}\twist_cast.exe"; WorkingDir: "{app}"
