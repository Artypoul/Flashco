[Setup]
AppId=FlashcoInstallerVersionHarness
AppName=Flashco Installer Version Harness
AppVersion=1
DefaultDirName={#SourcePath}\app
CreateAppDir=yes
Uninstallable=no
CreateUninstallRegKey=no
PrivilegesRequired=lowest
OutputDir=.
OutputBaseFilename=versions-harness
WizardStyle=modern

[Code]
@@CONSTANTS@@

var
  GuardFailureMessage: String;
  InstalledVersion, IncomingVersion, RegistryMode, RegisteredPath: String;
  StopCalls, Prompts: Integer;

function FixtureAllUsers: Boolean;
begin
  Result := ExpandConstant('{param:all-users|1}') = '1';
end;

function FixtureSilent: Boolean;
begin
  Result := ExpandConstant('{param:policy-silent|0}') = '1';
end;

function Fixture64BitMode: Boolean;
begin
  Result := ExpandConstant('{param:mode64|1}') = '1';
end;

function FixtureRegKeyExists(const RootKey: Integer; const SubKey: String): Boolean;
begin
  if SubKey <> 'Software\Microsoft\Windows\CurrentVersion\Uninstall\2E1E050C-79CA-52FB-82C4-52FDC3F5D780_is1' then
    RaiseException('Queried a different product registration');
  Result := ((RegistryMode = 'machine64') and (RootKey = HKLM64)) or
    ((RegistryMode = 'machine32') and (RootKey = HKLM32)) or
    ((RegistryMode = 'user') and (RootKey = HKCU)) or
    (((RegistryMode = 'query-failure') or (RegistryMode = 'location-only') or
      (RegistryMode = 'location-case') or (RegistryMode = 'location-conflict')) and
      (RootKey = HKLM64)) or
    (((RegistryMode = 'duplicate') or (RegistryMode = 'conflict')) and
      ((RootKey = HKLM64) or (RootKey = HKLM32)));
end;

function FixtureRegQueryStringValue(const RootKey: Integer;
    const SubKey, ValueName: String; var Value: String): Boolean;
begin
  Result := FixtureRegKeyExists(RootKey, SubKey) and (RegistryMode <> 'query-failure');
  if not Result then Exit;
  if ValueName = 'DisplayVersion' then
  begin
    Value := InstalledVersion;
    Exit;
  end;
  if (ValueName <> 'Inno Setup: App Path') and (ValueName <> 'InstallLocation') then
    RaiseException('Unexpected registration value: ' + ValueName);
  if (RegistryMode = 'location-only') and (ValueName = 'Inno Setup: App Path') then
  begin
    Result := False;
    Exit;
  end;
  Value := RegisteredPath;
  if (RegistryMode = 'conflict') and (RootKey = HKLM32) then
    Value := 'D:\OtherInstallation\Flashco';
  if ValueName = 'InstallLocation' then
  begin
    if RegistryMode = 'location-case' then Value := Uppercase(Value);
    if RegistryMode = 'location-conflict' then Value := 'D:\OtherInstallation\Flashco';
  end;
end;

function ConfirmDowngrade(const Installed, Incoming: String): Boolean;
begin
  Prompts := Prompts + 1;
  Result := ExpandConstant('{param:confirm|0}') = '1';
end;

function HasRunningInstalledApp: Boolean;
begin
  Result := False;
end;

function HelperOwnershipConflict: Boolean;
begin
  Result := False;
end;

function StopInstalledHelper(var FailureMessage: String): Boolean;
begin
  StopCalls := StopCalls + 1;
  Result := True;
end;

function HelperServiceStillRegistered(var FailureMessage: String): Boolean;
begin
  Result := False;
end;

@@PRODUCTION@@

procedure RunCase;
var
  Failure: String;
  NeedsRestart, Accepted, ExpectedAccepted: Boolean;
begin
  RegistryMode := ExpandConstant('{param:registry|machine64}');
  InstalledVersion := ExpandConstant('{param:installed|0.8.99+1}');
  IncomingVersion := ExpandConstant('{param:incoming|0.9.0+2026101401}');
  RegisteredPath := ExpandConstant('{param:installed-path|{app}}');
  ExpectedAccepted := ExpandConstant('{param:accept|1}') = '1';
  NeedsRestart := False;
  Failure := TestPrepareToInstall(NeedsRestart);
  Accepted := Failure = '';
  if Accepted <> ExpectedAccepted then
    RaiseException('Wrong version/path decision: ' + Failure);
  if StopCalls <> Ord(ExpectedAccepted) then
    RaiseException('Cleanup ran before policy acceptance');
  if Prompts <> StrToInt(ExpandConstant('{param:prompts|0}')) then
    RaiseException('Wrong number of downgrade confirmations');
  if ExpandConstant('{param:recheck|0}') = '1' then
  begin
    InstalledVersion := '0.10.0+1';
    Failure := TestPrepareToInstall(NeedsRestart);
    if (Failure = '') or (StopCalls <> 1) or (Prompts <> 1) then
      RaiseException('Changed registration reused old acceptance');
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Outcome: String;
begin
  if CurStep <> ssInstall then Exit;
  try
    RunCase;
    Outcome := 'PASS';
  except
    Outcome := 'FAIL: ' + GetExceptionMessage;
  end;
  SaveStringToFile(ExpandConstant('{param:result}'), Outcome, False);
  Abort;
end;
