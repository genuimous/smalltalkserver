program SmallTalkServer;

uses
  SvcMgr,
  Server in 'Server.pas' {ServerService: TService},
  Utils in 'Utils.pas';

{$R *.RES}

begin
  Application.Initialize;
  Application.CreateForm(TServerService, ServerService);
  Application.Run;
end.
