[Setup]
AppId={{APP_ID}}
AppVersion={{APP_VERSION}}
AppName={{DISPLAY_NAME}}
AppPublisher={{PUBLISHER_NAME}}
AppPublisherURL={{PUBLISHER_URL}}
AppSupportURL={{PUBLISHER_URL}}
AppUpdatesURL={{PUBLISHER_URL}}
DefaultDirName={code:GetInstallDir}
UsePreviousAppDir=no
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename={{OUTPUT_BASE_FILENAME}}
Compression=lzma
SolidCompression=yes
SetupIconFile={{SETUP_ICON_FILE}}
WizardStyle=modern
CloseApplications=no
SetupLogging=yes
PrivilegesRequired={{PRIVILEGES_REQUIRED}}
ArchitecturesAllowed={{ARCH}}
ArchitecturesInstallIn64BitMode={{ARCH}}

[Code]
const
  HelperServiceName = 'FlashcoHelperService';
  HelperServiceWaitAttempts = 300;
  HelperServicePollDelay = 100;
  FlashcoUninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{{APP_ID}}_is1';

var
  GuardFailureMessage: String;
  PartialPostInstallFailure: Boolean;
  PartialPostInstallFailureMessage: String;

function OpenSCManagerW(MachineName, DatabaseName: THandle;
    DesiredAccess: LongWord): THandle;
  external 'OpenSCManagerW@advapi32.dll stdcall';

function OpenServiceW(Manager: THandle; ServiceName: String;
    DesiredAccess: LongWord): THandle;
  external 'OpenServiceW@advapi32.dll stdcall';

procedure ReleaseServiceHandle(ServiceHandle: THandle);
  external 'CloseServiceHandle@advapi32.dll stdcall';

function NormalizeFullPath(const Value: String): String;
var
  Path: String;
begin
  Result := '';
  Path := Trim(Value);
  StringChangeEx(Path, '/', '\', True);

  if not (((Length(Path) >= 3) and (Copy(Path, 2, 2) = ':\')) or
      (Copy(Path, 1, 2) = '\\')) then
  begin
    Exit;
  end;

  Result := ExpandFileName(Path);
  if (Length(Result) > 3) and (Copy(Result, Length(Result), 1) = '\') then
  begin
    Delete(Result, Length(Result), 1);
  end;
end;

function NormalizeInstallDirectory(const Value: String): String;
var
  Remainder: String;
  Separator: Integer;
begin
  Result := NormalizeFullPath(Value);
  if (Length(Result) <= 3) or FileExists(Result) then
  begin
    Result := '';
    Exit;
  end;
  if Copy(Result, 1, 2) = '\\' then
  begin
    Remainder := Copy(Result, 3, Length(Result));
    Separator := Pos('\', Remainder);
    if Separator > 0 then
      Remainder := Copy(Remainder, Separator + 1, Length(Remainder));
    if (Separator = 0) or (Pos('\', Remainder) = 0) then Result := '';
  end;
end;

function SplitVersionParts(Value: String; const Separator: String): TArrayOfString;
var
  Position, Count: Integer;
begin
  SetArrayLength(Result, 0);
  repeat
    Position := Pos(Separator, Value);
    Count := GetArrayLength(Result);
    SetArrayLength(Result, Count + 1);
    if Position = 0 then
      Result[Count] := Value
    else
    begin
      Result[Count] := Copy(Value, 1, Position - 1);
      Delete(Value, 1, Position);
    end;
  until Position = 0;
end;

function IsVersionNumber(const Value: String): Boolean;
var
  i: Integer;
begin
  Result := False;
  if Value = '' then Exit;
  for i := 1 to Length(Value) do
    if (Value[i] < '0') or (Value[i] > '9') then Exit;
  Result := True;
end;

function CompareVersionNumber(Left, Right: String): Integer;
begin
  while (Length(Left) > 1) and (Left[1] = '0') do Delete(Left, 1, 1);
  while (Length(Right) > 1) and (Right[1] = '0') do Delete(Right, 1, 1);
  Result := 0;
  if Length(Left) < Length(Right) then Result := -1
  else if Length(Left) > Length(Right) then Result := 1
  else if Left < Right then Result := -1
  else if Left > Right then Result := 1;
end;

function ReadInstallerVersion(Value: String; var Release, Prerelease: TArrayOfString;
    var Build: String): Boolean;
var
  Position, i, j: Integer;
  Character: Char;
begin
  Result := False;
  Value := Trim(Value);
  Build := '0';
  Position := Pos('+', Value);
  if Position > 0 then
  begin
    Build := Copy(Value, Position + 1, Length(Value));
    Delete(Value, Position, Length(Value));
    if not IsVersionNumber(Build) then Exit;
  end;
  SetArrayLength(Prerelease, 0);
  Position := Pos('-', Value);
  if Position > 0 then
  begin
    Prerelease := SplitVersionParts(Copy(Value, Position + 1, Length(Value)), '.');
    Delete(Value, Position, Length(Value));
    for i := 0 to GetArrayLength(Prerelease) - 1 do
    begin
      if Prerelease[i] = '' then Exit;
      for j := 1 to Length(Prerelease[i]) do
      begin
        Character := Prerelease[i][j];
        if not (((Character >= '0') and (Character <= '9')) or
            ((Character >= 'a') and (Character <= 'z')) or
            ((Character >= 'A') and (Character <= 'Z')) or (Character = '-')) then Exit;
      end;
    end;
  end;
  Release := SplitVersionParts(Value, '.');
  if GetArrayLength(Release) <> 3 then Exit;
  for i := 0 to 2 do
    if not IsVersionNumber(Release[i]) then Exit;
  Result := True;
end;

function CompareInstallerVersions(const Left, Right: String; var Comparison: Integer): Boolean;
var
  LeftRelease, RightRelease, LeftPre, RightPre: TArrayOfString;
  LeftBuild, RightBuild: String;
  i, Count: Integer;
  LeftNumeric, RightNumeric: Boolean;
begin
  Result := False;
  Comparison := 0;
  if not ReadInstallerVersion(Left, LeftRelease, LeftPre, LeftBuild) or
      not ReadInstallerVersion(Right, RightRelease, RightPre, RightBuild) then Exit;
  Result := True;
  for i := 0 to 2 do
  begin
    Comparison := CompareVersionNumber(LeftRelease[i], RightRelease[i]);
    if Comparison <> 0 then Exit;
  end;
  if (GetArrayLength(LeftPre) = 0) and (GetArrayLength(RightPre) > 0) then
    Comparison := 1
  else if (GetArrayLength(LeftPre) > 0) and (GetArrayLength(RightPre) = 0) then
    Comparison := -1;
  if Comparison <> 0 then Exit;
  Count := GetArrayLength(LeftPre);
  if GetArrayLength(RightPre) < Count then Count := GetArrayLength(RightPre);
  for i := 0 to Count - 1 do
  begin
    LeftNumeric := IsVersionNumber(LeftPre[i]);
    RightNumeric := IsVersionNumber(RightPre[i]);
    if LeftNumeric and RightNumeric then
      Comparison := CompareVersionNumber(LeftPre[i], RightPre[i])
    else if LeftNumeric then Comparison := -1
    else if RightNumeric then Comparison := 1
    else Comparison := CompareStr(LeftPre[i], RightPre[i]);
    if Comparison <> 0 then Exit;
  end;
  if GetArrayLength(LeftPre) < GetArrayLength(RightPre) then Comparison := -1
  else if GetArrayLength(LeftPre) > GetArrayLength(RightPre) then Comparison := 1
  else Comparison := CompareVersionNumber(LeftBuild, RightBuild);
end;

function ReadInstalledRegistration(const RootKey: Integer; var Found: Boolean;
    var InstallPath, Version, FailureMessage: String): Boolean;
var
  OtherPath: String;
begin
  Result := True;
  Found := RegKeyExists(RootKey, FlashcoUninstallKey);
  if not Found then Exit;
  if not RegQueryStringValue(RootKey, FlashcoUninstallKey, 'Inno Setup: App Path', InstallPath) and
      not RegQueryStringValue(RootKey, FlashcoUninstallKey, 'InstallLocation', InstallPath) then
  begin
    FailureMessage := 'Windows could not read the existing Flashco installation directory.';
    Result := False;
    Exit;
  end;
  if RegQueryStringValue(RootKey, FlashcoUninstallKey, 'InstallLocation', OtherPath) and
      not SameText(NormalizeInstallDirectory(OtherPath), NormalizeInstallDirectory(InstallPath)) then
  begin
    FailureMessage := 'The existing Flashco registration contains conflicting installation directories.';
    Result := False;
    Exit;
  end;
  if not RegQueryStringValue(RootKey, FlashcoUninstallKey, 'DisplayVersion', Version) then
  begin
    FailureMessage := 'Windows could not read the existing Flashco version.';
    Result := False;
  end;
end;

function MergeInstalledRegistration(const RootKey: Integer; const MachineScope, AllUsers, In64BitMode: Boolean;
    var Found: Boolean; var InstallPath, Version, FailureMessage: String): Boolean;
var
  Registered: Boolean;
  Path, RegisteredVersion: String;
  Comparison: Integer;
begin
  Result := False;
  if not ReadInstalledRegistration(RootKey, Registered, Path, RegisteredVersion, FailureMessage) then Exit;
  if not Registered then
  begin
    Result := True;
    Exit;
  end;
  if MachineScope <> AllUsers then
  begin
    FailureMessage := 'Flashco is installed for a different user scope. Use the matching installer mode before changing installation scope.';
    Exit;
  end;
  if MachineScope and ((RootKey = HKLM64) <> In64BitMode) then
  begin
    FailureMessage := 'Flashco is registered in a different installation mode. Use the matching installer to preserve its uninstall information.';
    Exit;
  end;
  Path := NormalizeInstallDirectory(Path);
  if Path = '' then
  begin
    FailureMessage := 'The existing Flashco installation directory is invalid. Its files and settings were left unchanged.';
    Exit;
  end;
  if not CompareInstallerVersions(RegisteredVersion, RegisteredVersion, Comparison) then
  begin
    FailureMessage := 'The existing Flashco version is missing or invalid. Repair its installation registration before retrying.';
    Exit;
  end;
  if Found then
  begin
    if not SameText(Path, InstallPath) then
    begin
      FailureMessage := 'Multiple Flashco installations are registered in different directories. Resolve the conflicting installation first.';
      Exit;
    end;
    if CompareInstallerVersions(RegisteredVersion, Version, Comparison) and (Comparison > 0) then
      Version := RegisteredVersion;
  end
  else
  begin
    Found := True;
    InstallPath := Path;
    Version := RegisteredVersion;
  end;
  Result := True;
end;

function FindInstalledFlashco(const AllUsers, In64BitMode: Boolean; var Found: Boolean;
    var InstallPath, Version, FailureMessage: String): Boolean;
begin
  Result := False;
  Found := False;
  InstallPath := '';
  Version := '';
  if IsWin64 and not MergeInstalledRegistration(HKLM64, True, AllUsers, In64BitMode,
      Found, InstallPath, Version, FailureMessage) then Exit;
  if not MergeInstalledRegistration(HKLM32, True, AllUsers, In64BitMode,
      Found, InstallPath, Version, FailureMessage) then Exit;
  Result := MergeInstalledRegistration(HKCU, False, AllUsers, In64BitMode,
    Found, InstallPath, Version, FailureMessage);
end;

function GetInstallDir(Param: String): String;
var
  Found: Boolean;
  Path, Version, FailureMessage: String;
begin
  Result := ExpandConstant('{{INSTALL_DIR_NAME}}');
  if FindInstalledFlashco(IsAdminInstallMode, Is64BitInstallMode, Found, Path, Version, FailureMessage) then
  begin
    if Found then Result := Path;
  end
  else Log(FailureMessage);
end;

function ConfirmDowngrade(const Installed, Incoming: String): Boolean;
begin
  Result := SuppressibleMsgBox(
    FmtMessage(CustomMessage('DowngradeWarning'), [Installed, Incoming]),
    mbConfirmation, MB_YESNO or MB_DEFBUTTON2, IDNO) = IDYES;
end;

function CheckInstalledVersion(const TargetPath, Incoming: String;
    const AllUsers, In64BitMode, Silent, AllowDowngrade: Boolean; var FailureMessage: String): Boolean;
var
  Found: Boolean;
  InstallPath, Version: String;
  Comparison: Integer;
begin
  Result := False;
  if not FindInstalledFlashco(AllUsers, In64BitMode, Found, InstallPath, Version, FailureMessage) then Exit;
  if not Found then
  begin
    if FileExists(AddBackslash(TargetPath) + '{{EXECUTABLE_NAME}}') then
    begin
      FailureMessage := 'Flashco files exist without a readable installation version. Restore its installation registration before retrying.';
      Exit;
    end;
    Result := True;
    Exit;
  end;
  if not SameText(NormalizeInstallDirectory(TargetPath), InstallPath) then
  begin
    FailureMessage := 'Flashco is already installed in ' + InstallPath + '. Reinstall into that directory to preserve its installation.';
    Exit;
  end;
  if not CompareInstallerVersions(Version, Incoming, Comparison) then
  begin
    FailureMessage := 'Windows could not compare the installed and incoming Flashco versions.';
    Exit;
  end;
  Log('Replacing Flashco ' + Version + ' with ' + Incoming + ' in ' + InstallPath);
  if Comparison > 0 then
  begin
    if Silent then
    begin
      if not AllowDowngrade then
      begin
        FailureMessage := 'A newer Flashco version is installed. Silent downgrade requires /ALLOWDOWNGRADE=1.';
        Exit;
      end;
      Log('Downgrade explicitly allowed by /ALLOWDOWNGRADE=1');
    end
    else if not ConfirmDowngrade(Version, Incoming) then
    begin
      FailureMessage := 'The Flashco downgrade was canceled. Its installed files and settings were left unchanged.';
      Exit;
    end;
  end;
  Result := True;
end;

function TryExtractExecutablePath(const CommandLine: String; var ExecutablePath: String): Boolean;
var
  ClosingQuote: Integer;
  Remainder: String;
  i: Integer;
begin
  Result := False;
  ExecutablePath := '';
  if CommandLine = '' then
  begin
    Exit;
  end;

  if Copy(CommandLine, 1, 1) = '"' then
  begin
    ClosingQuote := Pos('"', Copy(CommandLine, 2, Length(CommandLine)));
    if ClosingQuote = 0 then
    begin
      Exit;
    end;
    ExecutablePath := Copy(CommandLine, 2, ClosingQuote - 1);
    Remainder := Copy(CommandLine, ClosingQuote + 2, Length(CommandLine));
    if (Remainder <> '') and (Copy(Remainder, 1, 1) <> ' ') and
        (Copy(Remainder, 1, 1) <> #9) then
    begin
      Exit;
    end;
  end
  else
  begin
    i := 1;
    while (i <= Length(CommandLine)) and
        (Copy(CommandLine, i, 1) <> ' ') and (Copy(CommandLine, i, 1) <> #9) do
    begin
      i := i + 1;
    end;
    ExecutablePath := Copy(CommandLine, 1, i - 1);
  end;

  Result := ExecutablePath <> '';
end;

function QueryHelperService(var Found: Boolean; var BinaryPath, State: String;
    var FailureMessage: String): Boolean;
var
  Locator: Variant;
  Services: Variant;
  Objects: Variant;
  Service: Variant;
  Count: Integer;
begin
  Result := False;
  Found := False;
  BinaryPath := '';
  State := '';
  try
    Locator := CreateOleObject('WbemScripting.SWbemLocator');
    Services := Locator.ConnectServer('.', 'root\CIMV2');
    Objects := Services.ExecQuery(
      'SELECT PathName, State FROM Win32_Service WHERE Name=''' + HelperServiceName + '''');
    Count := Objects.Count;
    if Count < 0 then
    begin
      FailureMessage := 'Windows could not verify the Helper service registration.';
      Exit;
    end;
    if Count = 0 then
    begin
      Result := True;
      Exit;
    end;
    if Count <> 1 then
    begin
      FailureMessage := 'Windows returned an unexpected number of Helper service registrations.';
      Exit;
    end;

    Service := Objects.ItemIndex(0);
    if VarIsNull(Service.PathName) or VarIsEmpty(Service.PathName) or
        VarIsNull(Service.State) or VarIsEmpty(Service.State) then
    begin
      FailureMessage := 'Windows did not provide the Helper service path and state.';
      Exit;
    end;
    BinaryPath := Service.PathName;
    State := Service.State;
    if (Trim(BinaryPath) = '') or (Trim(State) = '') then
    begin
      FailureMessage := 'Windows returned an incomplete Helper service path or state.';
      Exit;
    end;
    if not (SameText(State, 'Stopped') or SameText(State, 'Start Pending') or
        SameText(State, 'Stop Pending') or SameText(State, 'Running') or
        SameText(State, 'Continue Pending') or SameText(State, 'Pause Pending') or
        SameText(State, 'Paused')) then
    begin
      FailureMessage := 'Windows returned an unknown Helper service state.';
      Exit;
    end;
    Found := True;
    Result := True;
  except
    FailureMessage := 'Windows could not verify the Helper service registration: ' + GetExceptionMessage;
  end;
end;

function HelperOwnershipConflict(): Boolean;
var
  Found: Boolean;
  BinaryPath: String;
  State: String;
  ServiceExePath: String;
  ExpectedPath: String;
begin
  Result := True;
  if not QueryHelperService(Found, BinaryPath, State, GuardFailureMessage) then
  begin
    Exit;
  end;
  if not Found then
  begin
    Result := False;
    Exit;
  end;

  if not TryExtractExecutablePath(BinaryPath, ServiceExePath) then
  begin
    GuardFailureMessage := 'The registered Helper service has an unrecognized executable command line.';
    Exit;
  end;
  ServiceExePath := NormalizeFullPath(ServiceExePath);
  ExpectedPath := NormalizeFullPath(ExpandConstant('{app}\FlashcoHelperService.exe'));
  if (ServiceExePath = '') or (ExpectedPath = '') then
  begin
    GuardFailureMessage := 'Windows could not verify the Helper service executable path.';
    Exit;
  end;
  if not SameText(ServiceExePath, ExpectedPath) then
  begin
    GuardFailureMessage := 'A Helper service with the same service name belongs to another installation. Remove it from that installation first.';
    Exit;
  end;

  Result := False;
end;

function HelperServiceStillRegistered(var FailureMessage: String): Boolean;
var
  Found: Boolean;
  BinaryPath: String;
  State: String;
begin
  Result := True;
  if not QueryHelperService(Found, BinaryPath, State, FailureMessage) then
  begin
    Exit;
  end;
  if Found then
  begin
    FailureMessage := 'The Helper service is still registered. It was left unchanged; retry after it has stopped.';
    Exit;
  end;
  Result := False;
end;

function HasRunningInstalledApp(): Boolean;
var
  Locator: Variant;
  Services: Variant;
  Objects: Variant;
  Process: Variant;
  Count: Integer;
  i: Integer;
  ImagePath: String;
  ExpectedPath: String;
begin
  Result := True;
  try
    Locator := CreateOleObject('WbemScripting.SWbemLocator');
    Services := Locator.ConnectServer('.', 'root\CIMV2');
    Objects := Services.ExecQuery(
      'SELECT ExecutablePath FROM Win32_Process WHERE Name=''Flashco.exe''');
    Count := Objects.Count;
    if Count < 0 then
    begin
      GuardFailureMessage := 'Windows could not verify whether Flashco is running.';
      Exit;
    end;

    ExpectedPath := NormalizeFullPath(ExpandConstant('{app}\Flashco.exe'));
    if ExpectedPath = '' then
    begin
      GuardFailureMessage := 'Windows could not verify the Flashco installation path.';
      Exit;
    end;

    for i := 0 to Count - 1 do
    begin
      Process := Objects.ItemIndex(i);
      if VarIsNull(Process.ExecutablePath) or VarIsEmpty(Process.ExecutablePath) then
      begin
        GuardFailureMessage := 'Windows could not identify the path of a running Flashco process. Close Flashco and retry.';
        Exit;
      end;
      ImagePath := NormalizeFullPath(Process.ExecutablePath);
      if ImagePath = '' then
      begin
        GuardFailureMessage := 'Windows returned an invalid path for a running Flashco process.';
        Exit;
      end;
      if SameText(ImagePath, ExpectedPath) then
      begin
        GuardFailureMessage := 'Flashco is still running from this installation. Turn off the VPN and choose Exit from the Flashco tray menu, then retry.';
        Exit;
      end;
    end;

    Result := False;
  except
    GuardFailureMessage := 'Windows could not verify whether Flashco is running: ' + GetExceptionMessage;
  end;
end;

function QueryInstalledHelper(var Found: Boolean; var State: String;
    var FailureMessage: String): Boolean;
var
  BinaryPath: String;
  ServiceExePath: String;
  ExpectedPath: String;
begin
  Result := False;
  if not QueryHelperService(Found, BinaryPath, State, FailureMessage) then Exit;
  if not Found then
  begin
    Result := True;
    Exit;
  end;
  if not TryExtractExecutablePath(BinaryPath, ServiceExePath) then
  begin
    FailureMessage := 'The registered Helper service has an unrecognized executable command line.';
    Exit;
  end;
  ServiceExePath := NormalizeFullPath(ServiceExePath);
  ExpectedPath := NormalizeFullPath(ExpandConstant('{app}\FlashcoHelperService.exe'));
  if (ServiceExePath = '') or (ExpectedPath = '') or
      not SameText(ServiceExePath, ExpectedPath) then
  begin
    FailureMessage := 'The registered Helper service does not belong to this installation. It was left unchanged.';
    Exit;
  end;
  Result := True;
end;

function RunServiceCommand(const Command: String; var ResultCode: Integer;
    var FailureMessage: String): Boolean;
var
  ControllerPath: String;
begin
  ControllerPath := ExpandConstant('{sys}\sc.exe');
  Result := Exec(ControllerPath, Command + ' ' + HelperServiceName,
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  if Result then
    Log('Helper service ' + Command + ' exit code: ' + IntToStr(ResultCode))
  else
    FailureMessage := 'Windows could not run the service controller to ' + Command + ' the Helper service.';
end;

function WaitForInstalledHelper(const WaitForDeletion: Boolean;
    var FailureMessage: String): Boolean;
var
  Found: Boolean;
  State: String;
  Attempt, ResultCode: Integer;
begin
  Result := False;
  for Attempt := 1 to HelperServiceWaitAttempts do
  begin
    if not QueryInstalledHelper(Found, State, FailureMessage) then Exit;
    if not Found or (not WaitForDeletion and SameText(State, 'Stopped')) then
    begin
      Result := True;
      Exit;
    end;
    if not WaitForDeletion and (SameText(State, 'Running') or SameText(State, 'Paused')) then
    begin
      if not RunServiceCommand('stop', ResultCode, FailureMessage) then Exit;
      if (ResultCode <> 0) and (ResultCode <> 1060) and
          (ResultCode <> 1061) and (ResultCode <> 1062) then
      begin
        FailureMessage := 'Windows failed to stop the Helper service (exit code ' + IntToStr(ResultCode) + ').';
        Exit;
      end;
    end;
    if Attempt < HelperServiceWaitAttempts then Sleep(HelperServicePollDelay);
  end;
  if WaitForDeletion then
    FailureMessage := 'Windows still reports the Helper service as registered. Close Services and other service-management windows, then retry; a restart may be needed.'
  else
    FailureMessage := 'Windows did not confirm that the Helper service stopped. No application files were removed.';
end;

function IsInstalledHelperProcessPath(const ImagePath: String): Boolean;
var
  Path: String;
begin
  Path := NormalizeFullPath(ImagePath);
  Result := (Path <> '') and
    (SameText(Path, NormalizeFullPath(ExpandConstant('{app}\FlashcoHelperService.exe'))) or
     SameText(Path, NormalizeFullPath(ExpandConstant('{app}\FlashcoCore.exe'))));
end;

function QueryInstalledHelperProcesses(var Running: Boolean;
    var FailureMessage: String): Boolean;
var
  Locator: Variant;
  Services: Variant;
  Objects: Variant;
  Process: Variant;
  Count: Integer;
  i: Integer;
  ImagePath: String;
begin
  Result := False;
  Running := False;
  try
    Locator := CreateOleObject('WbemScripting.SWbemLocator');
    Services := Locator.ConnectServer('.', 'root\CIMV2');
    Objects := Services.ExecQuery(
      'SELECT ExecutablePath FROM Win32_Process WHERE Name=''FlashcoHelperService.exe'' OR Name=''FlashcoCore.exe''');
    Count := Objects.Count;
    if Count < 0 then
    begin
      FailureMessage := 'Windows could not verify the Helper and Core processes.';
      Exit;
    end;
    for i := 0 to Count - 1 do
    begin
      Process := Objects.ItemIndex(i);
      if VarIsNull(Process.ExecutablePath) or VarIsEmpty(Process.ExecutablePath) then
      begin
        FailureMessage := 'Windows could not identify the path of a Helper or Core process.';
        Exit;
      end;
      ImagePath := NormalizeFullPath(Process.ExecutablePath);
      if ImagePath = '' then
      begin
        FailureMessage := 'Windows returned an invalid Helper or Core process path.';
        Exit;
      end;
      if IsInstalledHelperProcessPath(ImagePath) then Running := True;
    end;
    Result := True;
  except
    FailureMessage := 'Windows could not verify the Helper and Core processes: ' + GetExceptionMessage;
  end;
end;

function WaitForInstalledHelperProcesses(var FailureMessage: String): Boolean;
var
  Running: Boolean;
  Attempt: Integer;
begin
  Result := False;
  for Attempt := 1 to HelperServiceWaitAttempts do
  begin
    if not QueryInstalledHelperProcesses(Running, FailureMessage) then Exit;
    if not Running then
    begin
      Result := True;
      Exit;
    end;
    if Attempt < HelperServiceWaitAttempts then Sleep(HelperServicePollDelay);
  end;
  FailureMessage := 'The Helper or Core process still uses this installation. No application files were removed; close it and retry.';
end;

function AcquireHelperReference(var ServiceHandle: THandle;
    var FailureMessage: String): Boolean;
var
  Manager: THandle;
  ErrorCode: LongWord;
begin
  Result := False;
  ServiceHandle := 0;
  Manager := OpenSCManagerW(0, 0, $0001);
  if Manager = 0 then
  begin
    FailureMessage := 'Windows could not open the service manager: ' + SysErrorMessage(DLLGetLastError);
    Exit;
  end;
  try
    ServiceHandle := OpenServiceW(Manager, HelperServiceName, $0001);
    ErrorCode := DLLGetLastError;
  finally
    ReleaseServiceHandle(Manager);
  end;
  if (ServiceHandle = 0) and (ErrorCode <> 1060) and (ErrorCode <> 1072) then
  begin
    FailureMessage := 'Windows could not hold the Helper service registration: ' + SysErrorMessage(ErrorCode);
    Exit;
  end;
  Result := True;
end;

function RemoveHeldHelper(var FailureMessage: String): Boolean;
var
  Found: Boolean;
  State: String;
  ResultCode: Integer;
begin
  Result := False;
  if not QueryInstalledHelper(Found, State, FailureMessage) then Exit;
  if not Found then
  begin
    FailureMessage := 'Windows could not confirm the held Helper service registration. Retry after its deletion completes.';
    Exit;
  end;
  if not SameText(State, 'Stopped') then
  begin
    if not SameText(State, 'Stop Pending') then
    begin
      if not RunServiceCommand('stop', ResultCode, FailureMessage) then Exit;
      if (ResultCode <> 0) and (ResultCode <> 1060) and
          (ResultCode <> 1061) and (ResultCode <> 1062) then
      begin
        FailureMessage := 'Windows failed to stop the Helper service (exit code ' + IntToStr(ResultCode) + ').';
        Exit;
      end;
    end;
    if not WaitForInstalledHelper(False, FailureMessage) then Exit;
  end;
  if not QueryInstalledHelper(Found, State, FailureMessage) then Exit;
  if not Found then
  begin
    FailureMessage := 'Windows could not confirm the held Helper service registration. Retry after its deletion completes.';
    Exit;
  end;
  if not SameText(State, 'Stopped') then
  begin
    FailureMessage := 'The Helper service is running again. Close Flashco and retry.';
    Exit;
  end;
  if not RunServiceCommand('delete', ResultCode, FailureMessage) then Exit;
  if (ResultCode <> 0) and (ResultCode <> 1060) and (ResultCode <> 1072) then
  begin
    FailureMessage := 'Windows failed to remove the Helper service (exit code ' + IntToStr(ResultCode) + ').';
    Exit;
  end;
  Result := True;
end;

function StopInstalledHelper(var FailureMessage: String): Boolean;
var
  ServiceHandle: THandle;
  Removed: Boolean;
begin
  Result := False;
  { Keep the registration alive so sc.exe cannot resolve a replacement with the same name. }
  if not AcquireHelperReference(ServiceHandle, FailureMessage) then Exit;
  if ServiceHandle = 0 then
  begin
    if WaitForInstalledHelper(True, FailureMessage) then
      Result := WaitForInstalledHelperProcesses(FailureMessage);
    Exit;
  end;
  try
    Removed := RemoveHeldHelper(FailureMessage);
  finally
    ReleaseServiceHandle(ServiceHandle);
  end;
  if not Removed then Exit;
  if WaitForInstalledHelper(True, FailureMessage) then
    Result := WaitForInstalledHelperProcesses(FailureMessage);
end;

function ClearStaleProxy(var FailureMessage: String): Boolean;
var
  AppPath: String;
  ResultCode: Integer;
begin
  Result := False;
  AppPath := ExpandConstant('{app}\{{EXECUTABLE_NAME}}');
  if not FileExists(AppPath) then
  begin
    FailureMessage := 'Flashco is missing, so stale proxy settings could not be cleared.';
    Exit;
  end;
  if not Exec(AppPath, '--clear-stale-proxy', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    FailureMessage := 'Windows could not start Flashco to clear stale proxy settings.';
    Exit;
  end;
  if ResultCode <> 0 then
  begin
    FailureMessage := 'Flashco could not clear stale proxy settings (exit code ' + IntToStr(ResultCode) + ').';
    Exit;
  end;
  Result := True;
end;

function PointsIntoApp(Value: String): Boolean;
begin
  Result := Pos(Lowercase(AddBackslash(ExpandConstant('{app}'))), Lowercase(Value)) > 0;
end;

// The value name is appName and the schemes are protocolSchemes, both in
// lib/common.
procedure RemoveUserRegistrations;
var
  Schemes: TArrayOfString;
  Value: String;
  i: Integer;
begin
  if RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', '{{APP_NAME}}', Value) and PointsIntoApp(Value) then
  begin
    RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', '{{APP_NAME}}');
    RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run', '{{APP_NAME}}');
  end;

  Schemes := ['clash', 'clashmeta', 'flashco'];
  for i := 0 to GetArrayLength(Schemes)-1 do
  begin
    if RegQueryStringValue(HKCU, 'Software\Classes\' + Schemes[i] + '\shell\open\command', '', Value) and PointsIntoApp(Value) then
    begin
      RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Classes\' + Schemes[i]);
    end;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  FailureMessage: String;
begin
  Result := '';
  GuardFailureMessage := '';
  if not CheckInstalledVersion(ExpandConstant('{app}'), '{{APP_VERSION}}',
      IsAdminInstallMode, Is64BitInstallMode, WizardSilent,
      ExpandConstant('{param:ALLOWDOWNGRADE|0}') = '1', FailureMessage) then
  begin
    Result := FailureMessage;
    Exit;
  end;
  if HasRunningInstalledApp() then
  begin
    Result := GuardFailureMessage;
    Exit;
  end;
  if HelperOwnershipConflict() then
  begin
    Result := GuardFailureMessage;
    Exit;
  end;
  if not StopInstalledHelper(FailureMessage) then
  begin
    Result := FailureMessage;
    Exit;
  end;
  if HelperServiceStillRegistered(FailureMessage) then
  begin
    Result := FailureMessage;
    Exit;
  end;
  GuardFailureMessage := '';
  if HasRunningInstalledApp() then
  begin
    Result := GuardFailureMessage;
    Exit;
  end;
  if HelperOwnershipConflict() then
  begin
    Result := GuardFailureMessage;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  FailureMessage: String;
begin
  if CurStep = ssPostInstall then
  begin
    if not ClearStaleProxy(FailureMessage) then
    begin
      PartialPostInstallFailure := True;
      PartialPostInstallFailureMessage := FailureMessage;
      Log('Post-install stale proxy cleanup failed: ' + FailureMessage);
    end;
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = wpFinished) and PartialPostInstallFailure then
  begin
    WizardForm.FinishedHeadingLabel.Caption := 'Installation completed with a warning';
    WizardForm.FinishedLabel.Caption := 'Flashco files were installed, but stale proxy cleanup failed. Review proxy settings before launching Flashco.' + #13#10 + PartialPostInstallFailureMessage;
    WizardForm.AdjustLabelHeight(WizardForm.FinishedLabel);
  end;
end;

function ShouldLaunchAfterInstall(): Boolean;
begin
  Result := not PartialPostInstallFailure;
end;

function GetCustomSetupExitCode: Integer;
begin
  Result := 0;
  if PartialPostInstallFailure then
  begin
    Result := 9;
  end;
end;

function InitializeUninstall(): Boolean;
var
  FailureMessage: String;
begin
  Result := False;
  GuardFailureMessage := '';
  if HasRunningInstalledApp() then
  begin
    MsgBox(GuardFailureMessage, mbError, MB_OK);
    Exit;
  end;
  if HelperOwnershipConflict() then
  begin
    MsgBox(GuardFailureMessage, mbError, MB_OK);
    Exit;
  end;
  if not StopInstalledHelper(FailureMessage) then
  begin
    MsgBox(FailureMessage, mbError, MB_OK);
    Exit;
  end;
  if HelperServiceStillRegistered(FailureMessage) then
  begin
    MsgBox(FailureMessage, mbError, MB_OK);
    Exit;
  end;
  GuardFailureMessage := '';
  if HasRunningInstalledApp() then
  begin
    MsgBox(GuardFailureMessage, mbError, MB_OK);
    Exit;
  end;
  if HelperOwnershipConflict() then
  begin
    MsgBox(GuardFailureMessage, mbError, MB_OK);
    Exit;
  end;
  if not ClearStaleProxy(FailureMessage) then
  begin
    MsgBox(FailureMessage + ' Uninstall was canceled; review the application state before retrying.', mbError, MB_OK);
    Exit;
  end;
  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    RemoveUserRegistrations;
  end;
end;

[CustomMessages]
DowngradeWarning=Flashco %1 is already installed. This installer contains the older version %2. Replace the application files? Your settings and profiles will be kept.
russian.DowngradeWarning=Уже установлен Flashco %1. Этот установщик содержит более старую версию %2. Заменить файлы приложения? Настройки и профили будут сохранены.

[Languages]
{% for locale in LOCALES %}
{% if locale.lang == 'en' %}Name: "english"; MessagesFile: "compiler:Default.isl"{% endif %}
{% if locale.lang == 'hy' %}Name: "armenian"; MessagesFile: "compiler:Languages\\Armenian.isl"{% endif %}
{% if locale.lang == 'bg' %}Name: "bulgarian"; MessagesFile: "compiler:Languages\\Bulgarian.isl"{% endif %}
{% if locale.lang == 'ca' %}Name: "catalan"; MessagesFile: "compiler:Languages\\Catalan.isl"{% endif %}
{% if locale.lang == 'zh' %}
Name: "chineseSimplified"; MessagesFile: {% if locale.file %}{{ locale.file }}{% else %}"compiler:Languages\\ChineseSimplified.isl"{% endif %}
{% endif %}
{% if locale.lang == 'co' %}Name: "corsican"; MessagesFile: "compiler:Languages\\Corsican.isl"{% endif %}
{% if locale.lang == 'cs' %}Name: "czech"; MessagesFile: "compiler:Languages\\Czech.isl"{% endif %}
{% if locale.lang == 'da' %}Name: "danish"; MessagesFile: "compiler:Languages\\Danish.isl"{% endif %}
{% if locale.lang == 'nl' %}Name: "dutch"; MessagesFile: "compiler:Languages\\Dutch.isl"{% endif %}
{% if locale.lang == 'fi' %}Name: "finnish"; MessagesFile: "compiler:Languages\\Finnish.isl"{% endif %}
{% if locale.lang == 'fr' %}Name: "french"; MessagesFile: "compiler:Languages\\French.isl"{% endif %}
{% if locale.lang == 'de' %}Name: "german"; MessagesFile: "compiler:Languages\\German.isl"{% endif %}
{% if locale.lang == 'he' %}Name: "hebrew"; MessagesFile: "compiler:Languages\\Hebrew.isl"{% endif %}
{% if locale.lang == 'is' %}Name: "icelandic"; MessagesFile: "compiler:Languages\\Icelandic.isl"{% endif %}
{% if locale.lang == 'it' %}Name: "italian"; MessagesFile: "compiler:Languages\\Italian.isl"{% endif %}
{% if locale.lang == 'ja' %}Name: "japanese"; MessagesFile: "compiler:Languages\\Japanese.isl"{% endif %}
{% if locale.lang == 'no' %}Name: "norwegian"; MessagesFile: "compiler:Languages\\Norwegian.isl"{% endif %}
{% if locale.lang == 'pl' %}Name: "polish"; MessagesFile: "compiler:Languages\\Polish.isl"{% endif %}
{% if locale.lang == 'pt' %}Name: "portuguese"; MessagesFile: "compiler:Languages\\Portuguese.isl"{% endif %}
{% if locale.lang == 'ru' %}Name: "russian"; MessagesFile: "compiler:Languages\\Russian.isl"{% endif %}
{% if locale.lang == 'sk' %}Name: "slovak"; MessagesFile: "compiler:Languages\\Slovak.isl"{% endif %}
{% if locale.lang == 'sl' %}Name: "slovenian"; MessagesFile: "compiler:Languages\\Slovenian.isl"{% endif %}
{% if locale.lang == 'es' %}Name: "spanish"; MessagesFile: "compiler:Languages\\Spanish.isl"{% endif %}
{% if locale.lang == 'tr' %}Name: "turkish"; MessagesFile: "compiler:Languages\\Turkish.isl"{% endif %}
{% if locale.lang == 'uk' %}Name: "ukrainian"; MessagesFile: "compiler:Languages\\Ukrainian.isl"{% endif %}
{% endfor %}

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: {% if CREATE_DESKTOP_ICON != true %}unchecked{% else %}checkedonce{% endif %}
[Files]
Source: "{{SOURCE_DIR}}\\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{autoprograms}\\{{DISPLAY_NAME}}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"
Name: "{autodesktop}\\{{DISPLAY_NAME}}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"; Tasks: desktopicon
[Run]
Filename: "{app}\\{{EXECUTABLE_NAME}}"; Description: "{cm:LaunchProgram,{{DISPLAY_NAME}}}"; Check: ShouldLaunchAfterInstall; Flags: {% if PRIVILEGES_REQUIRED == 'admin' %}runascurrentuser{% endif %} nowait postinstall skipifsilent
