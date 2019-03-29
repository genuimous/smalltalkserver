object ServerService: TServerService
  OldCreateOrder = False
  AllowPause = False
  DisplayName = 'SmallTalk Server'
  OnStart = ServiceStart
  OnStop = ServiceStop
  Left = 884
  Top = 381
  Height = 227
  Width = 213
  object ServerSocket: TServerSocket
    Active = False
    Port = 0
    ServerType = stNonBlocking
    OnClientConnect = ServerSocketClientConnect
    OnClientDisconnect = ServerSocketClientDisconnect
    OnClientRead = ServerSocketClientRead
    OnClientError = ServerSocketClientError
    Left = 32
    Top = 24
  end
end
