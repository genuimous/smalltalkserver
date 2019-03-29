unit Server;

interface

uses
  Windows, SysUtils, Classes, SvcMgr, IniFiles, ScktComp, Utils;

type
  TLogType = (ltInfo, ltWarning, ltError, ltDebug);
  TClientMessageType = (cmtTimeRequest, cmtRegistration,
    cmtAuthorization, cmtInclusion, cmtExclusion,
    cmtMessage, cmtPasswordChanging, cmtDisplayNameChanging);
  TServerMessageType = (smtAcknowledgement, smtError, smtTimeStamp,
    smtGreeting, smtMessage, smtConnection, smtDisconnection);

  TSettings = class(TObject)
  private
    FPort: Word;
    FUserDir: string;
    FLogDir: string;
    FDebug: Boolean;
  public
    property Port: Word read FPort;
    property UserDir: string read FUserDir;
    property LogDir: string read FLogDir;
    property Debug: Boolean read FDebug;
    procedure Read(const SettingsFileName: string);
  end;

  TClientMessage = class(TObject)
  private
    FMessageType: TClientMessageType;
    FParams: TStrings;
  public
    property MessageType: TClientMessageType read FMessageType;
    property Params: TStrings read FParams;
    constructor Create(const MessageData: string);
  end;

  TServerMessage = class(TObject)
  private
    FMessageType: TServerMessageType;
    FParams: TStrings;
  public
    constructor Create(const MessageType: TServerMessageType;
      const Params: TStrings);
    procedure Send(Socket: TCustomWinSocket);
  end;

  TAccount = class(TObject)
  private
    ContactList: TStringList;
    FUserName: string;
    FContactListFileName: string;
  public
    property UserName: string read FUserName write FUserName;
    procedure LoadContactList;
    procedure SaveContactList;
    constructor Create(const UserName: string; const DisplayName: string;
      const ContactListFileName: string);
    destructor Destroy; override;
  end;

  TClient = class(TObject)
  private
    Account: TAccount;
    FBuffer: string;
    FConnectTime: TDateTime;
    FLastActivityTime: TDateTime;
    FMessageCount: Cardinal;
    function AccountIsAssigned: Boolean;
  public
    property Buffer: string read FBuffer write FBuffer;
    property ConnectTime: TDateTime read FConnectTime;
    property LastActivityTime: TDateTime read FLastActivityTime
      write FLastActivityTime;
    property MessageCount: Cardinal read FMessageCount write FMessageCount;
    property IsAuthorized: Boolean read AccountIsAssigned;
    procedure Authorise(const UserName: string; const DisplayName: string;
      const ContactListFileName: string);
    procedure Unauthorize;
    constructor Create;
    destructor Destroy; override;
  end;

  TServerService = class(TService)
    ServerSocket: TServerSocket;
    procedure ServiceStart(Sender: TService; var Started: Boolean);
    procedure ServiceStop(Sender: TService; var Stopped: Boolean);
    procedure ServerSocketClientConnect(Sender: TObject;
      Socket: TCustomWinSocket);
    procedure ServerSocketClientDisconnect(Sender: TObject;
      Socket: TCustomWinSocket);
    procedure ServerSocketClientRead(Sender: TObject;
      Socket: TCustomWinSocket);
    procedure ServerSocketClientError(Sender: TObject;
      Socket: TCustomWinSocket; ErrorEvent: TErrorEvent;
      var ErrorCode: Integer);
  private
    { Private declarations }
    ServerVersion: TApplicationVersion;
    Settings: TSettings;
    procedure Log(const LogType: TLogType; const LogText: string);
    function UserProfileFileName(const UserName: string): string;
    function UserContactListFileName(const UserName: string): string;    
    function MessageDataIsOK(const MessageData: string): Boolean;
    procedure ProcessMessage(Socket: TCustomWinSocket; Msg: TClientMessage);
    function UserNameIsOK(const UserName: string): Boolean;
    function UserExists(const UserName: string): Boolean;
    function UserPassword(const UserName: string): string;
    function UserDisplayName(const UserName: string): string;
    function SocketByUserName(const UserName: string): TCustomWinSocket;
    procedure GenerateTimeAnswer(Socket: TCustomWinSocket);
    procedure RegisterUser(Socket: TCustomWinSocket; const UserName: string;
      const Password: string; const DisplayName: string);
    procedure AuthorizeUser(Socket: TCustomWinSocket; const UserName: string;
      const Password: string);
    procedure AddToContactList(Socket: TCustomWinSocket;
      const UserName: string);
    procedure DeleteFromContactList(Socket: TCustomWinSocket;
      const UserName: string);
    procedure DeliverMessage(Socket: TCustomWinSocket; const UserName: string;
      const MessageText: string; const MessageKind: string);
    procedure ChangePassword(Socket: TCustomWinSocket; const Password: string;
      const NewPassword: string);
    procedure ChangeDisplayName(Socket: TCustomWinSocket; const Password: string;
      const NewDisplayName: string);
    procedure ReplyWithAcknowledgement(Socket: TCustomWinSocket);
    procedure ReplyWithError(Socket: TCustomWinSocket; const ErrCode: string);
    procedure SendTimeStamp(Socket: TCustomWinSocket);
    procedure SendGreeting(Socket: TCustomWinSocket; const UserName: string;
      const DisplayName: string);
    procedure SendConnection(Socket: TCustomWinSocket; const UserName: string;
      const DisplayName: string);
    procedure SendDisconnection(Socket: TCustomWinSocket; const UserName: string;
      const DisplayName: string);
    procedure SendMessage(Socket: TCustomWinSocket;
      const UserName: string; const Text: string; const Kind: string);
    procedure CheckUserState(Socket: TCustomWinSocket;
      const UserName: string);
    procedure DistributeUserState(const UserName: string;
      const Active: Boolean);
  public
    { Public declarations }
    function GetServiceController: TServiceController; override;
  end;

var
  ServerService: TServerService;

implementation

{$R *.DFM}

const
  // program settings
  LogFileExt: string = '.log';
  DefaultPort: Integer = 8192;
  DefaultUserDir: string = 'User';
  DefaultLogDir: string = 'Log';
  ReceiveBufferSize: Integer = 65535;
  TimeStampDateTimeFormat: string = 'yyyymmddhhnnss';
  ContactListFileName: string = 'contacts.lst';
  ProfileFileName: string = 'user.ini';
  LogDateFormat: string = 'yyyymmdd';
  LogTimeFormat: string = 'hh:nn:ss';

  // message formatting chars
  DataBegChar: Char = '<';
  DataEndChar: Char = '>';
  MsgPartsDelimiterChar: Char = '=';
  MsgBodyBegChar: Char = '{';
  MsgBodyEndChar: Char = '}';
  MsgBodyPartsDelimiterChar: Char = ',';

  // params for encodig/decoding
  EmptyStrCode: string = '?';
  CharsPerEncodedChar: Integer = 2;

  // settings sections
  setsNetwork: string = 'Network';
  setsUser: string = 'User';
  setsLog: string = 'Log';

  // settings params
  setpPort: string = 'Port';
  setpUserDir: string = 'UserDir';
  setpLogDir: string = 'LogDir';
  setpDebug: string = 'Debug';

  // profile sections
  profsUserData: string = 'UserData';

  // profile params
  profpPassword: string = 'Password';
  profpDisplayName: string = 'DisplayName';

  // error codes
  ecBadUserName: string = '1001';
  ecUserAlreadyRegistered: string = '1011';
  ecUserNotRegistered: string = '1021';
  ecWrongPassword: string = '1022';
  ecAuthorizationRequired: string = '1999';
  ecUserNotConnected: string = '2001';
  ecUserAlreadyInContactList: string = '3001';
  ecUserNotExistsInContactList: string = '3002';
  ecCanNotAddSelfToContactList: string = '3099';
  ecMessageKindNotSupported: string = '4001';
  ecMessageBodyIsEmpty: string = '4999';
  ecServerRuntimeException: string = '9999';

  // client message typestrings
  cmtstrTimeRequest: string = 'WT';
  cmtstrRegistration: string = 'REG';
  cmtstrAuthorization: string = 'AUTH';
  cmtstrInclusion: string = 'INCL';
  cmtstrExclusion: string = 'EXCL';
  cmtstrMessage: string = 'MSG';
  cmtstrPasswordChanging: string = 'PWD';
  cmtstrDisplayNameChanging: string = 'NICK';

  // client messages body part counters
  cmbpcTimeRequest: Integer = 0;
  cmbpcRegistration: Integer = 3;
  cmbpcAuthorization: Integer = 2;
  cmbpcInclusion: Integer = 1;
  cmbpcExclusion: Integer = 1;
  cmbpcMessage: Integer = 3;
  cmbpcPasswordChanging: Integer = 2;
  cmbpcDisplayNameChanging: Integer = 2;

  // client messages body elements positions
  cmbepRegistrationUserName: Integer = 0;
  cmbepRegistrationPassword: Integer = 1;
  cmbepRegistrationDisplayName: Integer = 2;
  cmbepAuthorizationUserName: Integer = 0;
  cmbepAuthorizationPassword: Integer = 1;
  cmbepInclusionUserName: Integer = 0;
  cmbepExclusionUserName: Integer = 0;
  cmbepMessageUserName: Integer = 0;
  cmbepMessageText: Integer = 1;
  cmbepMessageKind: Integer = 2;
  cmbepPasswordChangingPassword: Integer = 0;
  cmbepPasswordChangingNewPassword: Integer = 1;
  cmbepDisplayNameChangingPassword: Integer = 0;
  cmbepDisplayNameChangingNewDisplayName: Integer = 1;

  // server message typestrings
  smtstrAcknowledgement: string = 'ACK';
  smtstrError: string = 'ERR';
  smtstrTimeStamp: string = 'TS';
  smtstrGreeting: string = 'HELLO';
  smtstrMessage: string = 'MSG';
  smtstrConnection: string = 'CONNECT';
  smtstrDisconnection: string = 'DISCONNECT';

  // server messages body part counters
  smbpcAcknowledgement: Integer = 1;
  smbpcError: Integer = 2;
  smbpcTimeStamp: Integer = 1;
  smbpcGreeting: Integer = 2;
  smbpcMessage: Integer = 3;
  smbpcConnection: Integer = 2;
  smbpcDisconnection: Integer = 2;

  // server messages body elements positions
  smbepTimeStampDateTime: Integer = 0;
  smbepMessageUserName: Integer = 0;
  smbepMessageText: Integer = 1;
  smbepMessageKind: Integer = 2;
  smbepConnectionUserName: Integer = 0;
  smbepConnectionDisplayName: Integer = 1;
  smbepDisconnectionUserName: Integer = 0;
  smbepDisconnectionDisplayName: Integer = 1;
  smbepAcknowledgementMessageCount: Integer = 0;
  smbepErrorMessageCount: Integer = 0;
  smbepErrorErrCode: Integer = 1;
  smbepGreetingUserName: Integer = 0;
  smbepGreetingDisplayName: Integer = 1;

  // message kinds (for text messages)
  mkSimple: string = 'SPL';
  mkAutoAnswer: string = 'AANSW';

resourcestring
  rsLogDir = 'Log directory is %s';
  rsLogInfoPrefix = '[INFO]';
  rsLogWarningPrefix = '[WARNING]';
  rsLogErrorPrefix = '[ERROR]';
  rsLogDebugPrefix = '[DEBUG]';
  rsUserDir = 'User directory is %s';
  rsServerStarting = 'SmallTalk Server %d.%d.%d.%d is about to start';
  rsServerStarted = 'Server started';
  rsServerStopping = 'Server begun shutdown procedure';
  rsServerStopped = 'Server stopped';
  rsSocketListening = 'Listening on port %d';
  rsClientConnected = 'Client connected (%s)';
  rsClientDisconnected = 'Client disconnected (%s)';
  rsDataIncoming = 'Data received from %s (%s)';
  rsDataProcessing = 'Processing message data (%s) from %s...';
  rsDataProcessed = 'Message data from %s has been processed successfully';
  rsDataProcessingError = 'Error processing message data received from %s!';
  rsDataWrongFormat = 'Data received from %s has wrong format!';
  rsDataContainsRubbish = 'Data received from %s contains rubbish!';
  rsDataIncorrect = 'Data received from %s is incorrect!';
  rsDataExceedsLimit = 'Data received from %s exceeds limit!';
  rsDataReceivingError = 'Error receiving data from %s!';
  rsTimeRequest = 'Time request received from %s';
  rsTimeRequestAccepted = 'Time request from client %s has been accepted';
  rsRegistration = 'Registration received from %s';
  rsRegistrationAccepted = 'Client %s has been registered as %s (%s)';
  rsRegistrationCreatingProfileError = 'Can not create profile for user %s!';
  rsRegistrationAlreadyRegistered = 'Can not register client %s because username %s is already registered';
  rsRegistrationBadUserName = 'Can not register client %s because username %s is not valid';
  rsRegistrationEmpty = 'Can not register client %s because at least one mandatory field is empty';
  rsRegistrationError = 'Can not register client %s!';
  rsAuthorization = 'Authorization received from %s';
  rsAuthorizationAccepted = 'Client %s has been authorized as %s';
  rsAuthorizationWrongPassword = 'Can not authorize client %s because password given for username %s is wrong';
  rsAuthorizationNotRegistered = 'Can not authorize client %s because username %s is not registered';
  rsAuthorizationBadUserName = 'Can not authorize client %s because username %s is not valid';
  rsAuthorizationEmpty = 'Can not authorize client %s because at least one mandatory field is empty';
  rsAuthorizationError = 'Can not authorize client %s!';
  rsMessage = 'Message received from %s';
  rsMessageAccepted = 'Message for user %s has been accepted from %s';
  rsMessageNotConnected = 'Can not accept message from %s because receiver %s is not connected';
  rsMessageUnknownKind = 'Can not accept message from %s because message kind %s is not supported';
  rsMessageNotRegistered = 'Can not accept message from %s because receiver %s is not registered';
  rsMessageBadUserName = 'Can not accept message from %s because receiver name %s is incorrect';
  rsMessageEmpty = 'Can not accept message from %s because at least one mandatory field is empty';
  rsMessageNotAuthorized = 'Can not accept message from client %s because it is not authorized';
  rsMessageError = 'Can not accept message from %s!';
  rsMessageSent = 'Message from user %s has been sent to %s';
  rsMessageSendingError = 'Can not send message to %s!';
  rsInclusion = 'Contact adding received from %s';
  rsInclusionAccepted = 'Contact %s has been added to contact list of client %s';
  rsInclusionSelf = 'Can not add contact for client %s because username %s is equal to itself';
  rsInclusionAlreadyInList = 'Contact %s already exists in contact list of client %s';
  rsInclusionNotRegistered = 'Can not add contact for client %s because username %s is not registered';
  rsInclusionBadUserName = 'Can not add contact for client %s because username %s is incorrect';
  rsInclusionEmpty = 'Can not add contact for client %s because at least one mandatory field is empty';
  rsInclusionNotAuthorized = 'Can not add contact for client %s because it is not authorized';
  rsInclusionError = 'Can not add contact for client %s!';
  rsExclusion = 'Contact deleting received from %s';
  rsExclusionAccepted = 'Contact %s has been deleted from contact list of client %s';
  rsExclusionNotInList = 'Contact %s does not exists in contact list of client %s';
  rsExclusionNotRegistered = 'Can not delete contact for client %s because username %s is not registered';
  rsExclusionBadUserName = 'Can not delete contact for client %s because username %s is incorrect';
  rsExclusionEmpty = 'Can not delete contact for client %s because at least one mandatory field is empty';
  rsExclusionNotAuthorized = 'Can not delete contact for client %s because it is not authorized';
  rsExclusionError = 'Can not delete contact for client %s!';
  rsDisplayNameChanging = 'Nickname changing received from %s';
  rsDisplayNameChangingAccepted = 'Display name of user %s has been changed to %s';
  rsDisplayNameChangingWrongPassword = 'Can not change display name of client %s because current password is wrong';
  rsDisplayNameChangingEmpty = 'Can not change display name of client %s because at least one mandatory field is empty';
  rsDisplayNameChangingNotAuthorized = 'Can not change display name of client %s because it is not authorized';
  rsDisplayNameChangingError = 'Can not change display name of client %s!';
  rsPasswordChanging = 'Password changing received from %s';
  rsPasswordChangingAccepted = 'Password of user %s has been changed';
  rsPasswordChangingWrongPassword = 'Can not change password of client %s because current password is wrong';
  rsPasswordChangingEmpty = 'Can not change password of client %s because at least one mandatory field is empty';
  rsPasswordChangingNotAuthorized = 'Can not change password of client %s because it is not authorized';
  rsPasswordChangingError = 'Can not change password of client %s!';
  rsGreetingSent = 'Greeting for user %s has been sent to %s';
  rsGreetingSendingError = 'Can not send greeting to %s!';
  rsAcknowledgementSent = 'Acknowledgement (%d) has been sent to %s';
  rsAcknowledgementSendingError = 'Can not send acknowledgement to %s!';
  rsErrorSent = 'Error (%d) %s has been sent to %s';
  rsErrorSendingError = 'Can not send error to %s!';
  rsTimeStampSent = 'Timestamp has been sent to %s';
  rsTimeStampSendingError = 'Can not send timestamp to %s!';
  rsConnectionSent = 'Connection of user %s has been sent to %s';
  rsConnectionSendingError = 'Can not send connection to %s!';
  rsDisconnectionSent = 'Disconnection of user %s has been sent to %s';
  rsDisconnectionSendingError = 'Can not send disconnection to %s!';
  rsDisplayNameReadingError = 'Can not read display name for user %s!';
  rsPasswordReadingError = 'Can not read password name for user %s!';
  rsClientConnectionError = 'Error occured in connection of client %s';

procedure ServiceController(CtrlCode: DWord); stdcall;
begin
  ServerService.Controller(CtrlCode);
end;

function TServerService.GetServiceController: TServiceController;
begin
  Result := ServiceController;
end;

procedure TServerService.ServiceStart(Sender: TService;
  var Started: Boolean);
begin
  Settings := TSettings.Create;
  Settings.Read(SettingsFileName);

  ForceDirectories(Settings.LogDir);
  ForceDirectories(Settings.UserDir);

  ServerVersion := ApplicationVersion;
  Log(ltInfo, Format(rsServerStarting, [ServerVersion.Major, ServerVersion.Minor, ServerVersion.Release, ServerVersion.Build]));

  Log(ltInfo, Format(rsLogDir, [Settings.LogDir]));
  Log(ltInfo, Format(rsUserDir, [Settings.UserDir]));

  ServerSocket.Port := Settings.Port;
  ServerSocket.Open;

  Log(ltInfo, Format(rsSocketListening, [Settings.Port]));
  Log(ltInfo, rsServerStarted);
end;

procedure TServerService.ServiceStop(Sender: TService;
  var Stopped: Boolean);
begin
  Log(ltInfo, rsServerStopping);
  ServerSocket.Close;
  Log(ltInfo, rsServerStopped);
end;

procedure TServerService.Log(const LogType: TLogType;
  const LogText: string);
var
  LogTime: string;
  LogPrefix: string;
  LogFileName: string;
begin
  if (LogType <> ltDebug) or Settings.Debug then
  begin
    LogTime := FormatDateTime(LogTimeFormat, Now);

    case LogType of
      ltInfo: LogPrefix := rsLogInfoPrefix;
      ltWarning: LogPrefix := rsLogWarningPrefix;
      ltError: LogPrefix := rsLogErrorPrefix;
      ltDebug: LogPrefix := rsLogDebugPrefix;
    end;

    LogFileName := IncludeTrailingPathDelimiter(Settings.LogDir) + FormatDateTime(LogDateFormat, Now) + LogFileExt;

    WriteStrToFile(LogTime + Space + LogPrefix + Space + LogText, LogFileName);
  end;
end;

procedure TServerService.ServerSocketClientConnect(Sender: TObject;
  Socket: TCustomWinSocket);
var
  Client: TClient;
begin
  Log(ltInfo, Format(rsClientConnected, [Socket.RemoteAddress]));

  Client := TClient.Create;
  Socket.Data := Client;
end;

procedure TServerService.ServerSocketClientDisconnect(Sender: TObject;
  Socket: TCustomWinSocket);
var
  Client: TClient;
begin
  Log(ltInfo, Format(rsClientDisconnected, [Socket.RemoteAddress]));

  Client := Socket.Data;
  if Assigned(Client) then
  begin
    if Client.IsAuthorized then
    begin
      DistributeUserState(Client.Account.UserName, False);
    end;

    FreeAndNil(Client);
  end;
end;

procedure TServerService.ServerSocketClientRead(Sender: TObject;
  Socket: TCustomWinSocket);
var
  Client: TClient;
  ReceivedText: string;
  ChPos: Integer;
  MsgDataBegMark, MsgDataEndMark: Integer;
  MsgData: string;
  Msg: TClientMessage;
begin
  Client := Socket.Data;

  try
    // recieve data
    ReceivedText := Socket.ReceiveText;

    Log(ltDebug, Format(rsDataIncoming, [Socket.RemoteAddress, ReceivedText]));

    // copy data to buffer
    Client.Buffer := Client.Buffer + ReceivedText;

    repeat
      // check size of buffer (to avoid overrun)
      if Length(Client.Buffer) <= ReceiveBufferSize then
      begin
        MsgDataBegMark := 0;
        MsgDataEndMark := 0;
        ChPos := 0;

        // determine where message begins and ends
        repeat
          Inc(ChPos);

          if Client.Buffer[ChPos] = DataBegChar then MsgDataBegMark := ChPos;
          if Client.Buffer[ChPos] = DataEndChar then MsgDataEndMark := ChPos;
        until (MsgDataBegMark > 0) and (MsgDataEndMark > 0) or (ChPos = Length(Client.Buffer));

        if (MsgDataBegMark > 0) and (MsgDataEndMark > 0) then
        // we have start and end message marks
        begin
          MsgData := Copy(Client.Buffer, MsgDataBegMark + 1, MsgDataEndMark - MsgDataBegMark - 1);
          Client.Buffer := Copy(Client.Buffer, MsgDataEndMark + 1, Length(Client.Buffer) - MsgDataEndMark + 1);
          if MessageDataIsOK(MsgData) then
          begin
            try
              // parsing message data
              Log(ltDebug, Format(rsDataProcessing, [MsgData, Socket.RemoteAddress]));
              Msg := TClientMessage.Create(MsgData);

              try
                // processing message
                ProcessMessage(Socket, Msg);
              finally
                FreeAndNil(Msg);
              end;
              Log(ltDebug, Format(rsDataProcessed, [Socket.RemoteAddress]));
            except
              on E: Exception do
              begin
                Log(ltError, Format(rsDataProcessingError, [Socket.RemoteAddress]) + Space + E.Message);
              end;
            end;
          end
          else
          begin
            Log(ltWarning, Format(rsDataWrongFormat, [Socket.RemoteAddress]));
          end;  
        end
        else
        // start or end mark is absent
        begin
          if MsgDataBegMark > 0 then
          // only start mark exists
          begin
            if MsgDataBegMark <> 1 then
            // start mark must be at first position
            begin
              Log(ltWarning, Format(rsDataContainsRubbish, [Socket.RemoteAddress]));
              Client.Buffer := Copy(Client.Buffer, MsgDataBegMark, Length(Client.Buffer) - MsgDataBegMark + 1);
            end
          end
          else
          // no marks at all
          begin
            Log(ltWarning, Format(rsDataIncorrect, [Socket.RemoteAddress]));
            Client.Buffer := EmptyStr;
          end;
        end;
      end
      else
      begin
        Log(ltWarning, Format(rsDataExceedsLimit, [Socket.RemoteAddress]));
        Client.Buffer := EmptyStr;
      end;
    until (Client.Buffer = EmptyStr) or (CharPos(DataBegChar, Client.Buffer) = 1) and (CharPos(DataEndChar, Client.Buffer) = 0);
  except
    on E: Exception do
    begin
      Log(ltError, Format(rsDataReceivingError, [Socket.RemoteAddress]) + Space + E.Message);
    end;
  end;
end;

{ TSettings }

procedure TSettings.Read(const SettingsFileName: string);
var
  AppPath: string;
begin
  AppPath := ExtractFilePath(ApplicationFileName);

  with TIniFile.Create(SettingsFileName) do
  begin
    try
      FPort := ReadInteger(setsNetwork, setpPort, DefaultPort);
      FUserDir := ReadString(setsUser, setpUserDir, AppPath + DefaultUserDir);
      FLogDir := ReadString(setsLog, setpLogDir, AppPath + DefaultLogDir);
      FDebug := ReadBool(setsLog, setpDebug, False);
    finally
      Free;
    end;
  end;
end;

{ TClient }

function TClient.AccountIsAssigned: Boolean;
begin
  Result := Assigned(Account);
end;

procedure TClient.Authorise(const UserName: string; const DisplayName: string;
  const ContactListFileName: string);
begin
  Account := TAccount.Create(UserName, DisplayName, ContactListFileName);
end;

constructor TClient.Create;
begin
  FBuffer := EmptyStr;
  FConnectTime := Now;
  FLastActivityTime := Now;
  FMessageCount := 0;
end;

procedure TClient.Unauthorize;
begin
  FreeAndNil(Account);
end;

{ TClientMessage }

constructor TClientMessage.Create(const MessageData: string);
var
  MsgDelimiterPos, MsgBodyBegPos, MsgBodyEndPos: Integer;
  MsgTypeStr, MsgBodyStr: string;
  Params: TStrings;
  ParamCounter: Integer;
begin
  // parsing message data
  MsgDelimiterPos := CharPos(MsgPartsDelimiterChar, MessageData);
  MsgBodyBegPos := CharPos(MsgBodyBegChar, MessageData);
  MsgBodyEndPos := CharPos(MsgBodyEndChar, MessageData);

  MsgTypeStr := Copy(MessageData, 1, MsgDelimiterPos - 1);
  MsgBodyStr := Copy(MessageData, MsgBodyBegPos + 1, MsgBodyEndPos - MsgBodyBegPos - 1);

  if MsgTypeStr = cmtstrTimeRequest then FMessageType := cmtTimeRequest;
  if MsgTypeStr = cmtstrRegistration then FMessageType := cmtRegistration;
  if MsgTypeStr = cmtstrAuthorization then FMessageType := cmtAuthorization;
  if MsgTypeStr = cmtstrInclusion then FMessageType := cmtInclusion;
  if MsgTypeStr = cmtstrExclusion then FMessageType := cmtExclusion;
  if MsgTypeStr = cmtstrMessage then FMessageType := cmtMessage;
  if MsgTypeStr = cmtstrPasswordChanging then FMessageType := cmtPasswordChanging;
  if MsgTypeStr = cmtstrDisplayNameChanging then FMessageType := cmtDisplayNameChanging;

  Params := DisAssembleStr(MsgBodyStr, MsgBodyPartsDelimiterChar);

  // decoding params
  SetLength(FParams, Length(Params));
  if Length(Params) > 0 then
  begin
    for ParamCounter := 0 to Length(FParams) - 1 do
    begin
      FParams[ParamCounter] := DecodeStr(Params[ParamCounter], EmptyStrCode, CharsPerEncodedChar);
    end;
  end;
end;

function TServerService.MessageDataIsOK(const MessageData: string): Boolean;
var
  MsgDelimiterPos, MsgBodyBegPos, MsgBodyEndPos: Integer;
  MsgBodyStr, MsgTypeStr: string;
  MsgBodyParts: TStrings;

  function TypeIsOK(const MsgTypeStr: string;
    const MsgBodyPartCount: Integer): Boolean;
  begin
    Result := True;

    if
      not
      (
        (MsgTypeStr = cmtstrTimeRequest) and (MsgBodyPartCount = cmbpcTimeRequest)
        or
        (MsgTypeStr = cmtstrRegistration) and (MsgBodyPartCount = cmbpcRegistration)
        or
        (MsgTypeStr = cmtstrAuthorization) and (MsgBodyPartCount = cmbpcAuthorization)
        or
        (MsgTypeStr = cmtstrInclusion) and (MsgBodyPartCount = cmbpcInclusion)
        or
        (MsgTypeStr = cmtstrExclusion) and (MsgBodyPartCount = cmbpcExclusion)
        or
        (MsgTypeStr = cmtstrMessage) and (MsgBodyPartCount = cmbpcMessage)
        or
        (MsgTypeStr = cmtstrPasswordChanging) and (MsgBodyPartCount = cmbpcPasswordChanging)
        or
        (MsgTypeStr = cmtstrDisplayNameChanging) and (MsgBodyPartCount = cmbpcDisplayNameChanging)
      )
    then
    begin
      Result := False;
    end;
  end;

  function BodyIsOK(MsgBodyParts: TStrings): Boolean;
  var
    MsgBodyPartsCounter: Integer;
  begin
    Result := True;

    if Length(MsgBodyParts) > 0 then
    begin
      for MsgBodyPartsCounter := 0 to Length(MsgBodyParts) - 1 do
      begin
        if
          not
          (
            (Length(MsgBodyParts[MsgBodyPartsCounter]) > 0)
            and
            (Length(MsgBodyParts[MsgBodyPartsCounter]) mod CharsPerEncodedChar = 0)
            and
            StrConsistsOfChars(MsgBodyParts[MsgBodyPartsCounter], HexCharSet)
            or
            (MsgBodyParts[MsgBodyPartsCounter] = EmptyStrCode)
          )
        then
        begin
          Result := False;
          Break;
        end;
      end;
    end;
  end;
begin
  Result := True;

  // checking all delimiters are set properly
  if
    not
    (
      (CharCount(MsgPartsDelimiterChar, MessageData) = 1)
      and
      (CharCount(MsgBodyBegChar, MessageData) = 1)
      and
      (CharCount(MsgBodyEndChar, MessageData) = 1)
    )
  then
  begin
    Result := False;
  end
  else
  begin
    // checking position of delimiters
    MsgDelimiterPos := CharPos(MsgPartsDelimiterChar, MessageData);
    MsgBodyBegPos := CharPos(MsgBodyBegChar, MessageData);
    MsgBodyEndPos := CharPos(MsgBodyEndChar, MessageData);

    if
      not
      (
        (MsgBodyBegPos < MsgBodyEndPos)
        and
        (MsgDelimiterPos + 1 = MsgBodyBegPos)
        and
        (MsgDelimiterPos > 1)
        and
        (MsgBodyEndPos = Length(MessageData))
      )
    then
    begin
      Result := False;
    end
    else
    begin
      MsgTypeStr := Copy(MessageData, 1, MsgDelimiterPos - 1);
      MsgBodyStr := Copy(MessageData, MsgBodyBegPos + 1, MsgBodyEndPos - MsgBodyBegPos - 1);
      SetLength(MsgBodyParts, 0);
      if Length(MsgBodyStr) > 0 then
        MsgBodyParts := DisAssembleStr(MsgBodyStr, MsgBodyPartsDelimiterChar);

      // checking data
      if
        not
        (
          TypeIsOK(MsgTypeStr, Length(MsgBodyParts))
          and
          BodyIsOK(MsgBodyParts)
        )
      then
      begin
        Result := False;
      end;
    end;
  end;
end;

procedure TServerService.ProcessMessage(Socket: TCustomWinSocket;
  Msg: TClientMessage);
var
  Client: TClient;
begin
  Client := Socket.Data;

  Client.LastActivityTime := Now;
  Client.MessageCount := Client.MessageCount + 1;

  case Msg.MessageType of
    cmtTimeRequest:
    begin
      Log(ltInfo, Format(rsTimeRequest, [Socket.RemoteAddress]));
      GenerateTimeAnswer(Socket);
    end;
    cmtRegistration:
    begin
      Log(ltInfo, Format(rsRegistration, [Socket.RemoteAddress]));
      RegisterUser(Socket, Msg.Params[cmbepRegistrationUserName], Msg.Params[cmbepRegistrationPassword], Msg.Params[cmbepRegistrationDisplayName]);
    end;
    cmtAuthorization:
    begin
      Log(ltInfo, Format(rsAuthorization, [Socket.RemoteAddress]));
      AuthorizeUser(Socket, Msg.Params[cmbepAuthorizationUserName], Msg.Params[cmbepAuthorizationPassword]);
    end;
    cmtInclusion:
    begin
      Log(ltInfo, Format(rsInclusion, [Socket.RemoteAddress]));
      AddToContactList(Socket, Msg.Params[cmbepInclusionUserName]);
    end;
    cmtExclusion:
    begin
      Log(ltInfo, Format(rsExclusion, [Socket.RemoteAddress]));
      DeleteFromContactList(Socket, Msg.Params[cmbepExclusionUserName]);
    end;
    cmtMessage:
    begin
      Log(ltInfo, Format(rsMessage, [Socket.RemoteAddress]));
      DeliverMessage(Socket, Msg.Params[cmbepMessageUserName], Msg.Params[cmbepMessageText], Msg.Params[cmbepMessageKind]);
    end;
    cmtPasswordChanging:
    begin
      Log(ltInfo, Format(rsPasswordChanging, [Socket.RemoteAddress]));
      ChangePassword(Socket, Msg.Params[cmbepPasswordChangingPassword], Msg.Params[cmbepPasswordChangingNewPassword]);
    end;
    cmtDisplayNameChanging:
    begin
      Log(ltInfo, Format(rsDisplayNameChanging, [Socket.RemoteAddress]));
      ChangeDisplayName(Socket, Msg.Params[cmbepDisplayNameChangingPassword], Msg.Params[cmbepDisplayNameChangingNewDisplayName]);
    end;
  end;
end;

destructor TClient.Destroy;
begin
  if Assigned(Account) then
  begin
    FreeAndNil(Account);
  end;  
end;

{ TServerMessage }

constructor TServerMessage.Create(const MessageType: TServerMessageType;
  const Params: TStrings);
begin
  FMessageType := MessageType;
  FParams := Params;
end;

procedure TServerMessage.Send(Socket: TCustomWinSocket);
var
  ParamCounter: Integer;
  MessageData: string;
begin
  MessageData := EmptyStr;

  MessageData := MessageData + DataBegChar;

  case FMessageType of
    smtAcknowledgement: MessageData := MessageData + smtstrAcknowledgement;
    smtError: MessageData := MessageData + smtstrError;
    smtTimeStamp: MessageData := MessageData + smtstrTimeStamp;
    smtGreeting: MessageData := MessageData + smtstrGreeting;
    smtMessage: MessageData := MessageData + smtstrMessage;
    smtConnection: MessageData := MessageData + smtstrConnection;
    smtDisconnection: MessageData := MessageData + smtstrDisconnection;
  end;

  MessageData := MessageData + MsgPartsDelimiterChar;

  MessageData := MessageData + MsgBodyBegChar;
  if Length(FParams) > 0 then
    for ParamCounter := 0 to Length(FParams) - 1 do
    begin
      MessageData := MessageData + EncodeStr(FParams[ParamCounter], EmptyStrCode, CharsPerEncodedChar);

      if ParamCounter < Length(FParams) - 1 then
      begin
        MessageData := MessageData + MsgBodyPartsDelimiterChar;
      end;  
    end;
  MessageData := MessageData + MsgBodyEndChar;

  MessageData := MessageData + DataEndChar;

  Socket.SendText(MessageData);
end;

procedure TServerService.SendTimeStamp(Socket: TCustomWinSocket);
var
  MessageType: TServerMessageType;
  Params: TStrings;
  Msg: TServerMessage;
begin
  try
    MessageType := smtTimeStamp;

    SetLength(Params, smbpcTimeStamp);
    Params[smbepTimeStampDateTime] := FormatDateTime(TimeStampDateTimeFormat, Now);

    Msg := TServerMessage.Create(MessageType, Params);

    try
      Msg.Send(Socket);
      Log(ltInfo, Format(rsTimeStampSent, [Socket.RemoteAddress]));
    finally
      FreeAndNil(Msg);
    end;
  except
    on E: Exception do
    begin
      Log(ltError, Format(rsTimeStampSent, [Socket.RemoteAddress]) + Space + E.Message);
    end;
  end;
end;

procedure TServerService.RegisterUser(Socket: TCustomWinSocket;
  const UserName: string; const Password: string; const DisplayName: string);
var
  ProfileFileName: string;
begin
  try
    // checking fields are not empty
    if (UserName <> EmptyStr) and (Password <> EmptyStr) and (DisplayName <> EmptyStr) then
    begin
      // checking user name
      if UserNameIsOK(UserName) then
      begin
        ProfileFileName := UserProfileFileName(UserName);

        if not FileExists(ProfileFileName) then
        begin
          // registering new user
          try
            ForceDirectories(ExtractFilePath(ProfileFileName));

            with TIniFile.Create(ProfileFileName) do
            begin
              try
                WriteString(profsUserData, profpPassword, EncodeStr(Password, EmptyStrCode, CharsPerEncodedChar));
                WriteString(profsUserData, profpDisplayName, EncodeStr(DisplayName, EmptyStrCode, CharsPerEncodedChar));
              finally
                Free;
              end;
            end;

            Log(ltInfo, Format(rsRegistrationAccepted, [Socket.RemoteAddress, UserName, DisplayName]));

            ReplyWithAcknowledgement(Socket);
          except
            on E: Exception do
            begin
              Log(ltError, Format(rsRegistrationCreatingProfileError, [UserName]) + Space + E.Message);

              ReplyWithError(Socket, ecServerRuntimeException);
            end;
          end;
        end
        else
        begin
          // the user already exists
          Log(ltInfo, Format(rsRegistrationAlreadyRegistered, [Socket.RemoteAddress, UserName]));

          ReplyWithError(Socket, ecUserAlreadyRegistered);
        end;
      end
      else
      begin
        // bad user name
        Log(ltInfo, Format(rsRegistrationBadUserName, [Socket.RemoteAddress, UserName]));

        ReplyWithError(Socket, ecBadUserName);
      end;
    end
    else
    begin
      // necessary data is missing
      Log(ltInfo, Format(rsRegistrationEmpty, [Socket.RemoteAddress]));

      ReplyWithError(Socket, ecMessageBodyIsEmpty);
    end;
  except
    on E: Exception do
    begin
      Log(ltError, Format(rsRegistrationError, [Socket.RemoteAddress]) + Space + E.Message);

      ReplyWithError(Socket, ecServerRuntimeException);
    end;
  end;
end;

function TServerService.UserProfileFileName(
  const UserName: string): string;
begin
  Result := IncludeTrailingPathDelimiter(IncludeTrailingPathDelimiter(Settings.UserDir) + UserName) + ProfileFileName;
end;

procedure TServerService.AuthorizeUser(Socket: TCustomWinSocket;
  const UserName: string; const Password: string);
var
  Client, OldClient: TClient;
  OldSocket: TCustomWinSocket;
  ContactCounter: Integer;
begin
  try
    Client := Socket.Data;

    if Client.IsAuthorized then
      Client.Unauthorize;

    // checking fields are not empty
    if (UserName <> EmptyStr) and (Password <> EmptyStr) then
    begin
      // checking user name
      if UserNameIsOK(UserName) then
      begin
        // checking user exists
        if UserExists(UserName) then
        begin
          // checking password
          if Password = UserPassword(UserName) then
          begin
            // checking user is already authorized by another client
            OldSocket := SocketByUserName(UserName);

            // cleaning previous authorization
            if Assigned(OldSocket) then
            begin
              OldClient := OldSocket.Data;
              FreeAndNil(OldClient);
              OldSocket.Close;
            end;

            // creating authorization
            Client.Authorise(UserName, DisplayName, UserContactListFileName(UserName));

            Log(ltInfo, Format(rsAuthorizationAccepted, [Socket.RemoteAddress, UserName]));

            ReplyWithAcknowledgement(Socket);

            // sending greeting
            SendGreeting(Socket, UserName, UserDisplayName(UserName));

            // sending connection of the user to all interested clients
            DistributeUserState(UserName, True);

            // reading contact list and sending user states
            Client.Account.LoadContactList;
            if Client.Account.ContactList.Count > 0 then
            begin
              for ContactCounter := 0 to Client.Account.ContactList.Count - 1 do
              begin
                if UserExists(Client.Account.ContactList[ContactCounter]) then
                begin
                  CheckUserState(Socket, Client.Account.ContactList[ContactCounter]);
                end;
              end;
            end;
          end
          else
          begin
            // wrong password
            Log(ltInfo, Format(rsAuthorizationWrongPassword, [Socket.RemoteAddress, UserName]));

            ReplyWithError(Socket, ecWrongPassword);
          end;
        end
        else
        begin
          // no such user
          Log(ltInfo, Format(rsAuthorizationNotRegistered, [Socket.RemoteAddress, UserName]));

          ReplyWithError(Socket, ecUserNotRegistered);
        end;
      end
      else
      begin
        // bad user name
        Log(ltInfo, Format(rsAuthorizationBadUserName, [Socket.RemoteAddress, UserName]));

        ReplyWithError(Socket, ecBadUserName);
      end;
    end
    else
    begin
      // necessary data is missing
      Log(ltInfo, Format(rsAuthorizationEmpty, [Socket.RemoteAddress]));

      ReplyWithError(Socket, ecMessageBodyIsEmpty);
    end;
  except
    on E: Exception do
    begin
      Log(ltError, Format(rsAuthorizationError, [Socket.RemoteAddress]) + Space + E.Message);

      ReplyWithError(Socket, ecServerRuntimeException);
    end;  
  end;
end;

function TServerService.UserNameIsOK(const UserName: string): Boolean;
begin
  Result := StrConsistsOfChars(UserName, UserNameCharSet);
end;

function TServerService.UserExists(const UserName: string): Boolean;
begin
  Result := FileExists(UserProfileFileName(UserName));
end;

function TServerService.SocketByUserName(
  const UserName: string): TCustomWinSocket;
var
  Client: TClient;
  ConnectionCounter: Integer;
begin
  Result := nil;

  for ConnectionCounter := 0 to ServerSocket.Socket.ActiveConnections - 1 do
  begin
    Client := ServerSocket.Socket.Connections[ConnectionCounter].Data;

    if Client.IsAuthorized then
    begin
      if Client.Account.UserName = UserName then
      begin
        Result := ServerSocket.Socket.Connections[ConnectionCounter];
        Break;
      end;
    end;
  end;
end;

procedure TServerService.DeliverMessage(Socket: TCustomWinSocket;
  const UserName: string; const MessageText: string; const MessageKind: string);
var
  Client: TClient;
  Receiver: TCustomWinSocket;
begin
  try
    Client := Socket.Data;

    // checking user authorization
    if Client.IsAuthorized then
    begin
      // checking fields are not empty
      if (UserName <> EmptyStr) and (MessageText <> EmptyStr) and (MessageKind <> EmptyStr) then
      begin
        // checking message kind
        if (MessageKind = mkSimple) or (MessageKind = mkAutoAnswer) then
        begin
          // checking user name
          if UserNameIsOK(UserName) then
          begin
            // checking user exists
            if UserExists(UserName) then
            begin
              // at first we need to find receiver's connection
              Receiver := SocketByUserName(UserName);

              // checking the connection was found
              if Assigned(Receiver) then
              begin
                Log(ltInfo, Format(rsMessageAccepted, [UserName, Socket.RemoteAddress]));

                ReplyWithAcknowledgement(Socket);

                SendMessage(Receiver, Client.Account.UserName, MessageText, MessageKind);
              end
              else
              begin
                // user is not connected
                Log(ltInfo, Format(rsMessageNotConnected, [Socket.RemoteAddress, UserName]));

                ReplyWithError(Socket, ecUserNotConnected);
              end;
            end
            else
            begin
              // no such user
              Log(ltInfo, Format(rsMessageNotRegistered, [Socket.RemoteAddress, UserName]));

              ReplyWithError(Socket, ecUserNotRegistered);
            end;
          end
          else
          begin
            // bad user name
            Log(ltInfo, Format(rsMessageBadUserName, [Socket.RemoteAddress, UserName]));

            ReplyWithError(Socket, ecBadUserName);
          end;
        end
        else
        begin
          // unknown message kind
          Log(ltInfo, Format(rsMessageUnknownKind, [Socket.RemoteAddress, MessageKind]));

          ReplyWithError(Socket, ecMessageKindNotSupported);
        end;
      end
      else
      begin
        // necessary data is missing
        Log(ltInfo, Format(rsMessageEmpty, [Socket.RemoteAddress]));

        ReplyWithError(Socket, ecMessageBodyIsEmpty);
      end;
    end
    else
    begin
      // client is not authorized
      Log(ltInfo, Format(rsMessageNotAuthorized, [Socket.RemoteAddress]));

      ReplyWithError(Socket, ecAuthorizationRequired);
    end;
  except
    on E: Exception do
    begin
      Log(ltError, Format(rsMessageError, [Socket.RemoteAddress]) + Space + E.Message);

      ReplyWithError(Socket, ecServerRuntimeException);
    end;
  end;
end;

procedure TServerService.SendMessage(Socket: TCustomWinSocket;
  const UserName: string; const Text: string; const Kind: string);
var
  MessageType: TServerMessageType;
  Params: TStrings;
  Msg: TServerMessage;
begin
  try
    MessageType := smtMessage;

    SetLength(Params, smbpcMessage);
    Params[smbepMessageUserName] := UserName;
    Params[smbepMessageText] := Text;
    Params[smbepMessageKind] := Kind;

    Msg := TServerMessage.Create(MessageType, Params);

    try
      Msg.Send(Socket);
      Log(ltInfo, Format(rsMessageSent, [UserName, Socket.RemoteAddress]));
    finally
      FreeAndNil(Msg);
    end;
  except
    on E: Exception do
    begin
      Log(ltError, Format(rsMessageSendingError, [Socket.RemoteAddress]) + Space + E.Message);
    end;
  end;
end;

function TServerService.UserContactListFileName(
  const UserName: string): string;
begin
  Result := IncludeTrailingPathDelimiter(IncludeTrailingPathDelimiter(Settings.UserDir) + UserName) + ContactListFileName;
end;

{ TAccount }

constructor TAccount.Create(const UserName: string; const DisplayName: string;
  const ContactListFileName: string);
begin
  FUserName := UserName;
  FContactListFileName := ContactListFileName;

  ContactList := TStringList.Create;
end;

destructor TAccount.Destroy;
begin
  if Assigned(ContactList) then
    FreeAndNil(ContactList);
end;

procedure TServerService.AddToContactList(Socket: TCustomWinSocket;
  const UserName: string);
var
  Client: TClient;
begin
  try
    Client := Socket.Data;
    
    // checking user authorization
    if Client.IsAuthorized then
    begin
      // checking fields are not empty
      if UserName <> EmptyStr then
      begin
        // checking user name
        if UserNameIsOK(UserName) then
        begin
          // checking user exists
          if UserExists(UserName) then
          begin
            // checking user is not in contact list
            if not (Client.Account.ContactList.IndexOf(UserName) >= 0) then
            begin
              if UserName <> Client.Account.UserName then
              begin
                Client.Account.ContactList.Add(UserName);
                Client.Account.SaveContactList;

                Log(ltInfo, Format(rsInclusionAccepted, [UserName, Socket.RemoteAddress]));

                ReplyWithAcknowledgement(Socket);

                CheckUserState(Socket, UserName);
              end
              else
              begin
                // adding self account is not allowed
                Log(ltInfo, Format(rsInclusionSelf, [Socket.RemoteAddress, UserName]));

                ReplyWithError(Socket, ecCanNotAddSelfToContactList);
              end;
            end
            else
            begin
              // already in contact list
              Log(ltInfo, Format(rsInclusionAlreadyInList, [UserName, Socket.RemoteAddress]));

              ReplyWithError(Socket, ecUserAlreadyInContactList);
            end;
          end
          else
          begin
            // no such user
            Log(ltInfo, Format(rsInclusionNotRegistered, [Socket.RemoteAddress, UserName]));

            ReplyWithError(Socket, ecUserNotRegistered);
          end;
        end
        else
        begin
          // bad user name
          Log(ltInfo, Format(rsInclusionBadUserName, [Socket.RemoteAddress, UserName]));

          ReplyWithError(Socket, ecBadUserName);
        end;
      end
      else
      begin
        // necessary data is missing
        Log(ltInfo, Format(rsInclusionEmpty, [Socket.RemoteAddress]));

        ReplyWithError(Socket, ecMessageBodyIsEmpty);
      end;
    end
    else
    begin
      // client is not authorized
      Log(ltInfo, Format(rsInclusionNotAuthorized, [Socket.RemoteAddress]));

      ReplyWithError(Socket, ecAuthorizationRequired);
    end;
  except
    on E: Exception do
    begin
      Log(ltError, Format(rsInclusionError, [Socket.RemoteAddress]) + Space + E.Message);

      ReplyWithError(Socket, ecServerRuntimeException);
    end;
  end;
end;

procedure TServerService.DeleteFromContactList(Socket: TCustomWinSocket;
  const UserName: string);
var
  Client: TClient;
  ContactIndex: Integer;
begin
  try
    Client := Socket.Data;

    // checking user authorization
    if Client.IsAuthorized then
    begin
      // checking fields are not empty
      if UserName <> EmptyStr then
      begin
        // checking user name
        if UserNameIsOK(UserName) then
        begin
          // checking user exists
          if UserExists(UserName) then
          begin
            // checking user is in contact list
            ContactIndex := Client.Account.ContactList.IndexOf(UserName);
            if ContactIndex >= 0 then
            begin
              Client.Account.ContactList.Delete(ContactIndex);
              Client.Account.SaveContactList;

              Log(ltInfo, Format(rsExclusionAccepted, [UserName, Socket.RemoteAddress]));

              ReplyWithAcknowledgement(Socket);
            end
            else
            begin
              // not exists in contact list
              Log(ltInfo, Format(rsExclusionNotInList, [UserName, Socket.RemoteAddress]));

              ReplyWithError(Socket, ecUserNotExistsInContactList);
            end;
          end
          else
          begin
            // no such user
            Log(ltInfo, Format(rsExclusionNotRegistered, [Socket.RemoteAddress, UserName]));

            ReplyWithError(Socket, ecUserNotRegistered);
          end;
        end
        else
        begin
          // bad user name
          Log(ltInfo, Format(rsExclusionBadUserName, [Socket.RemoteAddress, UserName]));

          ReplyWithError(Socket, ecBadUserName);
        end;
      end
      else
      begin
        // necessary data is missing
        Log(ltInfo, Format(rsExclusionEmpty, [Socket.RemoteAddress]));

        ReplyWithError(Socket, ecMessageBodyIsEmpty);
      end;
    end
    else
    begin
      // client is not authorized
      Log(ltInfo, Format(rsExclusionNotAuthorized, [Socket.RemoteAddress]));

      ReplyWithError(Socket, ecAuthorizationRequired);
    end;
  except
    on E: Exception do
    begin
      Log(ltError, Format(rsExclusionError, [Socket.RemoteAddress]) + Space + E.Message);

      ReplyWithError(Socket, ecServerRuntimeException);
    end;
  end;    
end;

procedure TAccount.LoadContactList;
begin
  if FileExists(FContactListFileName) then
  begin
    ContactList.LoadFromFile(FContactListFileName);
  end;
end;

procedure TAccount.SaveContactList;
begin
  ContactList.SaveToFile(FContactListFileName);
end;

procedure TServerService.CheckUserState(Socket: TCustomWinSocket;
  const UserName: string);
var
  ClientSocket: TCustomWinSocket;
begin
  ClientSocket := SocketByUserName(UserName);

  if Assigned(ClientSocket) then
  begin
    SendConnection(Socket, UserName, UserDisplayName(UserName));
  end
  else
  begin
    SendDisconnection(Socket, UserName, UserDisplayName(UserName));
  end;
end;

procedure TServerService.SendConnection(Socket: TCustomWinSocket;
  const UserName: string; const DisplayName: string);
var
  MessageType: TServerMessageType;
  Params: TStrings;
  Msg: TServerMessage;
begin
  try
    MessageType := smtConnection;

    SetLength(Params, smbpcConnection);
    Params[smbepConnectionUserName] := UserName;
    Params[smbepConnectionDisplayName] := DisplayName;

    Msg := TServerMessage.Create(MessageType, Params);

    try
      Msg.Send(Socket);
      Log(ltInfo, Format(rsConnectionSent, [UserName, Socket.RemoteAddress]));
    finally
      FreeAndNil(Msg);
    end;
  except
    on E: Exception do
    begin
      Log(ltError, Format(rsConnectionSendingError, [Socket.RemoteAddress]) + Space + E.Message);
    end;
  end;
end;

procedure TServerService.SendDisconnection(Socket: TCustomWinSocket;
  const UserName: string; const DisplayName: string);
var
  MessageType: TServerMessageType;
  Params: TStrings;
  Msg: TServerMessage;
begin
  try
    MessageType := smtDisconnection;

    SetLength(Params, smbpcDisconnection);
    Params[smbepDisconnectionUserName] := UserName;
    Params[smbepDisconnectionDisplayName] := DisplayName;

    Msg := TServerMessage.Create(MessageType, Params);

    try
      Msg.Send(Socket);
      Log(ltInfo, Format(rsDisconnectionSent, [UserName, Socket.RemoteAddress]));
    finally
      FreeAndNil(Msg);
    end;
  except
    on E: Exception do
    begin
      Log(ltError, Format(rsDisconnectionSendingError, [Socket.RemoteAddress]) + Space + E.Message);
    end;
  end;
end;

function TServerService.UserDisplayName(const UserName: string): string;
begin
  try
    with TIniFile.Create(UserProfileFileName(UserName)) do
    begin
      try
        Result := DecodeStr(ReadString(profsUserData, profpDisplayName, EmptyStr), EmptyStrCode, CharsPerEncodedChar);
      finally
        Free;
      end;
    end;
  except
    on E: Exception do
    begin
      Log(ltError, Format(rsDisplayNameReadingError, [UserName]) + Space + E.Message);
    end;
  end;
end;

procedure TServerService.ReplyWithAcknowledgement(
  Socket: TCustomWinSocket);
var
  Client: TClient;
  MessageType: TServerMessageType;
  Params: TStrings;
  Msg: TServerMessage;
begin
  try
    Client := Socket.Data;
    
    MessageType := smtAcknowledgement;

    SetLength(Params, smbpcAcknowledgement);
    Params[smbepAcknowledgementMessageCount] := IntToStr(Client.MessageCount);

    Msg := TServerMessage.Create(MessageType, Params);

    try
      Msg.Send(Socket);
      Log(ltInfo, Format(rsAcknowledgementSent, [Client.MessageCount, Socket.RemoteAddress]));
    finally
      FreeAndNil(Msg);
    end;
  except
    on E: Exception do
    begin
      Log(ltError, Format(rsAcknowledgementSendingError, [Socket.RemoteAddress]) + Space + E.Message);
    end;
  end;
end;

procedure TServerService.GenerateTimeAnswer(Socket: TCustomWinSocket);
begin
  Log(ltInfo, Format(rsTimeRequestAccepted, [Socket.RemoteAddress]));

  ReplyWithAcknowledgement(Socket);

  SendTimeStamp(Socket);
end;

procedure TServerService.ReplyWithError(Socket: TCustomWinSocket;
  const ErrCode: string);
var
  Client: TClient;
  MessageType: TServerMessageType;
  Params: TStrings;
  Msg: TServerMessage;
begin
  try
    Client := Socket.Data;

    MessageType := smtError;

    SetLength(Params, smbpcError);
    Params[smbepErrorMessageCount] := IntToStr(Client.MessageCount);
    Params[smbepErrorErrCode] := ErrCode;

    Msg := TServerMessage.Create(MessageType, Params);

    try
      Msg.Send(Socket);
      Log(ltInfo, Format(rsErrorSent, [Client.MessageCount, ErrCode, Socket.RemoteAddress]));
    finally
      FreeAndNil(Msg);
    end;
  except
    on E: Exception do
    begin
      Log(ltError, Format(rsErrorSendingError, [Socket.RemoteAddress]) + Space + E.Message);
    end;
  end;
end;

procedure TServerService.DistributeUserState(const UserName: string;
  const Active: Boolean);
var
  Client: TClient;
  ConnectionCounter: Integer;
  DisplayName: string;
begin
  DisplayName := UserDisplayName(UserName);

  for ConnectionCounter := 0 to ServerSocket.Socket.ActiveConnections - 1 do
  begin
    Client := ServerSocket.Socket.Connections[ConnectionCounter].Data;

    if Client.IsAuthorized then
    begin
      if Client.Account.UserName <> UserName then
      begin
        if Client.Account.ContactList.IndexOf(UserName) >= 0 then
        begin
          if Active then
          begin
            SendConnection(ServerSocket.Socket.Connections[ConnectionCounter], UserName, DisplayName);
          end
          else
          begin
            SendDisconnection(ServerSocket.Socket.Connections[ConnectionCounter], UserName, DisplayName);
          end;
        end;
      end;
    end;
  end;
end;

function TServerService.UserPassword(const UserName: string): string;
begin
  try
    with TIniFile.Create(UserProfileFileName(UserName)) do
    begin
      try
        Result := DecodeStr(ReadString(profsUserData, profpPassword, EmptyStr), EmptyStrCode, CharsPerEncodedChar);
      finally
        Free;
      end;
    end;
  except
    on E: Exception do
    begin
      Log(ltError, Format(rsPasswordReadingError, [UserName]) + Space + E.Message);
    end;
  end;
end;

procedure TServerService.ServerSocketClientError(Sender: TObject;
  Socket: TCustomWinSocket; ErrorEvent: TErrorEvent;
  var ErrorCode: Integer);
begin
  ErrorCode := 0;

  Log(ltWarning, Format(rsClientConnectionError, [Socket.RemoteAddress]));
  Socket.Close;
end;

procedure TServerService.SendGreeting(Socket: TCustomWinSocket;
  const UserName: string; const DisplayName: string);
var
  MessageType: TServerMessageType;
  Params: TStrings;
  Msg: TServerMessage;
begin
  try
    MessageType := smtGreeting;

    SetLength(Params, smbpcGreeting);
    Params[smbepGreetingUserName] := UserName;
    Params[smbepGreetingDisplayName] := DisplayName;

    Msg := TServerMessage.Create(MessageType, Params);

    try
      Msg.Send(Socket);
      Log(ltInfo, Format(rsGreetingSent, [UserName, Socket.RemoteAddress]));
    finally
      FreeAndNil(Msg);
    end;
  except
    on E: Exception do
    begin
      Log(ltError, Format(rsGreetingSendingError, [Socket.RemoteAddress]) + Space + E.Message);
    end;
  end;
end;

procedure TServerService.ChangeDisplayName(Socket: TCustomWinSocket;
  const Password: string; const NewDisplayName: string);
var
  Client: TClient;
begin
  try
    Client := Socket.Data;

    // checking user authorization
    if Client.IsAuthorized then
    begin
      // checking fields are not empty
      if (Password <> EmptyStr) and (NewDisplayName <> EmptyStr)then
      begin
        // checking password
        if Password = UserPassword(Client.Account.UserName) then
        begin
          with TIniFile.Create(UserProfileFileName(Client.Account.UserName)) do
          begin
            try
              WriteString(profsUserData, profpDisplayName, EncodeStr(NewDisplayName, EmptyStrCode, CharsPerEncodedChar));
            finally
              Free;
            end;
          end;

          Log(ltInfo, Format(rsDisplayNameChangingAccepted, [Client.Account.UserName, NewDisplayName]));

          ReplyWithAcknowledgement(Socket);

          DistributeUserState(Client.Account.UserName, True);
        end
        else
        begin
          // wrong password
          Log(ltInfo, Format(rsDisplayNameChangingWrongPassword, [Socket.RemoteAddress]));

          ReplyWithError(Socket, ecWrongPassword);
        end;
      end
      else
      begin
        // necessary data is missing
        Log(ltInfo, Format(rsDisplayNameChangingEmpty, [Socket.RemoteAddress]));

        ReplyWithError(Socket, ecMessageBodyIsEmpty);
      end;
    end
    else
    begin
      // client is not authorized
      Log(ltInfo, Format(rsDisplayNameChangingNotAuthorized, [Socket.RemoteAddress]));

      ReplyWithError(Socket, ecAuthorizationRequired);
    end;
  except
    on E: Exception do
    begin
      Log(ltError, Format(rsDisplayNameChangingError, [Socket.RemoteAddress]) + Space + E.Message);

      ReplyWithError(Socket, ecServerRuntimeException);
    end;
  end;
end;

procedure TServerService.ChangePassword(Socket: TCustomWinSocket;
  const Password: string; const NewPassword: string);
var
  Client: TClient;
begin
  try
    Client := Socket.Data;

    // checking user authorization
    if Client.IsAuthorized then
    begin
      // checking fields are not empty
      if (Password <> EmptyStr) and (NewPassword <> EmptyStr)then
      begin
        // checking password
        if Password = UserPassword(Client.Account.UserName) then
        begin
          with TIniFile.Create(UserProfileFileName(Client.Account.UserName)) do
          begin
            try
              WriteString(profsUserData, profpPassword, EncodeStr(NewPassword, EmptyStrCode, CharsPerEncodedChar));
            finally
              Free;
            end;
          end;

          Log(ltInfo, Format(rsPasswordChangingAccepted, [Client.Account.UserName]));

          ReplyWithAcknowledgement(Socket);
        end
        else
        begin
          // wrong password
          Log(ltInfo, Format(rsPasswordChangingWrongPassword, [Socket.RemoteAddress]));

          ReplyWithError(Socket, ecWrongPassword);
        end;
      end
      else
      begin
        // necessary data is missing
        Log(ltInfo, Format(rsPasswordChangingEmpty, [Socket.RemoteAddress]));

        ReplyWithError(Socket, ecMessageBodyIsEmpty);
      end;
    end
    else
    begin
      // client is not authorized
      Log(ltInfo, Format(rsPasswordChangingNotAuthorized, [Socket.RemoteAddress]));

      ReplyWithError(Socket, ecAuthorizationRequired);
    end;
  except
    on E: Exception do
    begin
      Log(ltError, Format(rsPasswordChangingError, [Socket.RemoteAddress]) + Space + E.Message);

      ReplyWithError(Socket, ecServerRuntimeException);
    end;
  end;
end;

end.
