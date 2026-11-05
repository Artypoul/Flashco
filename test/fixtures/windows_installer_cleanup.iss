[Setup]
AppId=FlashcoInstallerCleanupHarness
AppName=Flashco Installer Cleanup Harness
AppVersion=1
DefaultDirName={#SourcePath}\app
CreateAppDir=no
Uninstallable=no
CreateUninstallRegKey=no
PrivilegesRequired=lowest
OutputDir=.
OutputBaseFilename=cleanup-harness
WizardStyle=modern

[Code]
const
  HelperServiceName = 'FlashcoHelperService';
  HelperServiceWaitAttempts = 3;
  HelperServicePollDelay = 0;

var
  Scenario: String;
  Registered: Boolean;
  CurrentState: String;
  Commands: String;
  Queries: Integer;
  StopPolls: Integer;
  DeletePolls: Integer;
  StartPolls: Integer;
  ReferenceHeld: Boolean;
  ManagerHeld: Boolean;

function OpenSCManagerW(MachineName, DatabaseName: THandle;
    DesiredAccess: LongWord): THandle;
begin
  ManagerHeld := Scenario <> 'manager-failure';
  Result := 0;
  if ManagerHeld then Result := 2;
end;

function OpenServiceW(Manager: THandle; ServiceName: String;
    DesiredAccess: LongWord): THandle;
begin
  if not ManagerHeld or (Manager <> 2) or (ServiceName <> HelperServiceName) then
    RaiseException('Invalid service manager or name');
  Result := 0;
  if Registered and (Scenario <> 'reference-failure') and (Scenario <> 'open-pending-delete') and
      (Scenario <> 'absent-replaced') then
  begin
    Result := 1;
    ReferenceHeld := True;
  end;
end;

function FixtureLastError: LongWord;
begin
  if Scenario = 'open-pending-delete' then Result := 1072
  else if (Scenario = 'absent') or (Scenario = 'absent-replaced') then Result := 1060
  else Result := 5;
end;

procedure ReleaseServiceHandle(ServiceHandle: THandle);
begin
  if ServiceHandle = 2 then
  begin
    if not ManagerHeld then RaiseException('Closed an invalid service manager');
    ManagerHeld := False;
    Exit;
  end;
  if not ReferenceHeld or (ServiceHandle <> 1) then
    RaiseException('Closed an invalid service reference');
  ReferenceHeld := False;
end;

function QueryHelperService(var Found: Boolean; var BinaryPath, State: String;
    var FailureMessage: String): Boolean;
begin
  Queries := Queries + 1;
  if Scenario = 'query-failure' then
  begin
    FailureMessage := 'fixture query failure';
    Result := False;
    Exit;
  end;
  if StopPolls > 0 then
  begin
    StopPolls := StopPolls - 1;
    if StopPolls = 0 then CurrentState := 'Stopped';
  end;
  if StartPolls > 0 then
  begin
    StartPolls := StartPolls - 1;
    if StartPolls = 0 then CurrentState := 'Running';
  end;
  if DeletePolls > 0 then
  begin
    if ReferenceHeld then RaiseException('Deletion polled before closing service reference');
    DeletePolls := DeletePolls - 1;
    if DeletePolls = 0 then Registered := False;
  end;
  Found := Registered;
  if Scenario = 'held-registration-missing' then Found := False;
  State := CurrentState;
  BinaryPath := '"' + ExpandConstant('{app}\FlashcoHelperService.exe') + '" --owner-sid S-1-5-18';
  if (Scenario = 'foreign') or (Scenario = 'absent-replaced') or
      ((Scenario = 'replaced') and (Queries >= 3)) then
    BinaryPath := '"D:\OtherInstallation\FlashcoHelperService.exe"';
  Result := True;
end;

function RunServiceCommand(const Command: String; var ResultCode: Integer;
    var FailureMessage: String): Boolean;
begin
  if not ReferenceHeld then RaiseException('Service mutation without a stable reference');
  Commands := Commands + Command + ';';
  Result := True;
  ResultCode := 0;
  if Scenario = 'command-failure' then
  begin
    FailureMessage := 'fixture command failed';
    Result := False;
  end
  else if Command = 'stop' then
  begin
    if (Scenario = 'start-pending') and (CurrentState = 'Start Pending') then
    begin
      ResultCode := 1061;
      StartPolls := 1;
    end
    else if Scenario = 'stop-failure' then ResultCode := 5
    else if Scenario = 'already-stopped' then
    begin
      ResultCode := 1062;
      CurrentState := 'Stopped';
    end
    else
    begin
      CurrentState := 'Stop Pending';
      if Scenario <> 'stuck-stop' then StopPolls := 2;
    end;
  end
  else if Command = 'delete' then
  begin
    if Scenario = 'delete-failure' then ResultCode := 5
    else if Scenario <> 'stuck-delete' then
    begin
      DeletePolls := 2;
      if Scenario = 'pending-delete' then ResultCode := 1072;
    end;
  end
  else RaiseException('Unexpected service verb: ' + Command);
end;

function QueryInstalledHelperProcesses(var Running: Boolean;
    var FailureMessage: String): Boolean;
begin
  Result := True;
  Running := Scenario = 'stuck-process';
end;

@@PRODUCTION@@

procedure RunCase;
var
  Failure: String;
  ExpectedSuccess, Success: Boolean;
  ExpectedCommands: String;
begin
  if not IsInstalledHelperProcessPath(ExpandConstant('{app}\FlashcoCore.exe')) then
    RaiseException('Owned Core path was not recognized');
  if IsInstalledHelperProcessPath('D:\OtherInstallation\FlashcoCore.exe') or
      IsInstalledHelperProcessPath('') or IsInstalledHelperProcessPath('FlashcoCore.exe') then
    RaiseException('An unowned process path was accepted');
  Registered := Scenario <> 'absent';
  if Scenario = 'open-pending-delete' then DeletePolls := 2;
  CurrentState := 'Stopped';
  if (Scenario = 'running') or (Scenario = 'already-stopped') or
      (Scenario = 'stuck-stop') or (Scenario = 'stop-failure') or
      (Scenario = 'replaced') then CurrentState := 'Running';
  if Scenario = 'start-pending' then CurrentState := 'Start Pending';
  ExpectedSuccess := (Scenario = 'absent') or (Scenario = 'missing-binary') or
    (Scenario = 'running') or (Scenario = 'already-stopped') or
    (Scenario = 'pending-delete') or (Scenario = 'start-pending') or
    (Scenario = 'open-pending-delete');
  Success := StopInstalledHelper(Failure);
  if ReferenceHeld then RaiseException('Leaked service reference');
  if ManagerHeld then RaiseException('Leaked service manager');
  if Success <> ExpectedSuccess then
    RaiseException('Unexpected cleanup result for ' + Scenario + ': ' + Failure);
  if Success and Registered then RaiseException('Cleanup succeeded with a registered service');
  if not Success and (Failure = '') then RaiseException('Failure was not explained');
  if (Scenario = 'absent') or (Scenario = 'foreign') or (Scenario = 'query-failure') or
      (Scenario = 'reference-failure') or (Scenario = 'manager-failure') or
      (Scenario = 'open-pending-delete') or (Scenario = 'absent-replaced') or
      (Scenario = 'held-registration-missing') then
    ExpectedCommands := ''
  else if Scenario = 'start-pending' then ExpectedCommands := 'stop;stop;delete;'
  else if (Scenario = 'running') or (Scenario = 'already-stopped') then
    ExpectedCommands := 'stop;delete;'
  else if (Scenario = 'stuck-stop') or (Scenario = 'stop-failure') or
      (Scenario = 'replaced') then ExpectedCommands := 'stop;'
  else ExpectedCommands := 'delete;';
  if Commands <> ExpectedCommands then
    RaiseException('Wrong service actions: ' + Commands + ' expected ' + ExpectedCommands);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Outcome: String;
begin
  if CurStep <> ssInstall then Exit;
  Scenario := ExpandConstant('{param:scenario|missing-binary}');
  try
    RunCase;
    Outcome := 'PASS';
  except
    Outcome := 'FAIL: ' + GetExceptionMessage;
  end;
  SaveStringToFile(ExpandConstant('{param:result}'), Outcome, False);
  Abort;
end;
