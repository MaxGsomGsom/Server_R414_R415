unit uServerDM;

interface

uses
  IdContext,
  IdTCPStream,
  SyncObjs,
  IdTCPConnection,
  Generics.Collections,
  uClientDM,
  IdTCPServer,
  IdGlobal,
  IdSocketHandle,
  Classes,
  uRequestDM,
  uHandlerStationR414DM,
  uHandlerStationR415DM,
  uHandlerCrossDM,
  uStationR414DM,
  uStationR415DM,
  uCrossDM;


type
  TAddRemoveUpdateClient = procedure (StationR414: TStationR414;
    StationR415: TStationR415; Cross: TCross) of object;

  TServer = class
    private
      Connections: TList<TIdTCPConnection>;

      FOnAddClient: TAddRemoveUpdateClient;
      FOnRemoveClient: TAddRemoveUpdateClient;
      FonUpdateClient: TAddRemoveUpdateClient;

      HandlerStationR414: THandlerStationR414;
      HandlerStationR415: THandlerStationR415;
      HandlerCross: THandlerCross;

      Section: TCriticalSection;
      TCPServer: TIdTCPServer;

      procedure ServerConnect(AContext: TIdContext);
      procedure ServerDisconnect(AContext: TIdContext);
      procedure ServerExecute(AContext: TIdContext);
      procedure MessageParser(Connection: TIdTCPConnection;
        StrRequest : string);
      procedure RegisterClient (Connection : TIdTCPConnection;
        Request: TRequest);
      procedure SendMessage(Connection: TIdTCPConnection;
        Request: TRequest);overload;
      function SendMessage(Client: TClient; Request: TRequest):
        Boolean; overload;
      procedure AddClient(Connection: TIdTCPConnection);
      procedure Clear;
    public
      constructor Create (Port : TIdPort; MaxConnections : Integer);
      function GetStatusServer : Boolean;
      property StatusServer : Boolean read GetStatusServer;
      procedure StartServer;
      procedure StopServer;
      function ReadPort: Integer;
      procedure WritePort(Value: Integer);
      function ReadMaxConnections: Integer;
      procedure WriteMaxConnections(Value: Integer);

      procedure DoOnStationR414(StationR414: TStationR414);
      procedure DoOnRemoveStationR414(StationR414: TStationR414);
      procedure DoOnUpdateStationR414(StationR414: TStationR414);

      property Port: Integer read ReadPort write WritePort;
      property MaxConnections: Integer read ReadMaxConnections
        write WriteMaxConnections;

      property onAddClient: TAddRemoveUpdateClient
      read FOnAddClient write FOnAddClient;
      property onRemoveClient: TAddRemoveUpdateClient
      read FOnRemoveClient write FOnRemoveClient;
      property onUpdateClient: TAddRemoveUpdateClient
      read FonUpdateClient write FonUpdateClient;

  end;

implementation
  /// <summary>
  /// ����������� ������.
  /// </summary>
  /// <param name="Port">���� �������.</param>
  /// <param name="MaxConnections">������������ ���������� �����������.</param>
  constructor TServer.Create (Port : TIdPort; MaxConnections : Integer);
  begin
    TCPServer := TIdTCPServer.Create(nil);
    if (Port > 0) and (Port < 65535) then
      TCPServer.DefaultPort := Port
    else
      TCPServer.DefaultPort := 2106;

    if MaxConnections > 0 then
      TCPServer.MaxConnections := MaxConnections
    else
      TCPServer.MaxConnections:= 1;
    Section := TCriticalSection.Create;

    Connections := TList<TIdTCPConnection>.Create;

    HandlerStationR414 := THandlerStationR414.Create;

    TCPServer.OnConnect := ServerConnect;
    TCPServer.OnDisconnect := ServerDisconnect;
    TCPServer.OnExecute := ServerExecute;

    HandlerStationR414.onAddStationR414 := DoOnStationR414;
    HandlerStationR414.onRemoveStationR414 := DoOnRemoveStationR414;
    HandlerStationR414.onUpdateStationR414 := DoOnUpdateStationR414;
  end;

  /// <summary>
  /// ������ ���� �������.
  /// </summary>
  /// <param name="Value">��������.</param>
  procedure TServer.WritePort(Value: Integer);
  begin
    TCPServer.DefaultPort := Value;
  end;

  /// <summary>
  /// ���������� ���� �������.
  /// </summary>
  function TServer.ReadPort;
  begin
    Exit(TCPServer.DefaultPort);
  end;

  /// <summary>
  /// ������ ���������� ���������� �������.
  /// </summary>
  /// <param name="Value">��������.</param>
  procedure TServer.WriteMaxConnections(Value: Integer);
  begin
    TCPServer.MaxConnections := Value;
  end;

  /// <summary>
  /// ���������� ������������ ��������� �����������.
  /// </summary>
  function TServer.ReadMaxConnections;
  begin
    Exit(TCPServer.MaxConnections);
  end;

  /// <summary>
  /// �������� ������� onAddClient.
  /// </summary>
  /// <param name="StationR414">������ ������ TStationR414.</param>
  procedure TServer.DoOnStationR414(StationR414: TStationR414);
  begin
    onAddClient(StationR414, nil, nil);
  end;

  /// <summary>
  /// �������� ������� onRemoveClient.
  /// </summary>
  /// <param name="StationR414">������ ������ TStationR414.</param>
  procedure TServer.DoOnRemoveStationR414(StationR414: TStationR414);
  begin
    onRemoveClient(StationR414, nil, nil);
  end;

  /// <summary>
  /// �������� ������� onUpdateClient.
  /// </summary>
  /// <param name="StationR414">������ ������ TStationR414.</param>
  procedure TServer.DoOnUpdateStationR414(StationR414: TStationR414);
  begin
    onUpdateClient(StationR414, nil, nil);
  end;

  /// <summary>
  /// ���������� ��������� �������.
  /// </summary>
  /// <param name="Client">
  /// ������ ������ TClient.
  /// ������, �������� ���������� ��������� ���������.
  /// </param>
  /// <param name="Request">
  /// ������ ������ TRequest.
  /// ������ ��� �������� �������.
  /// </param>
  function TServer.SendMessage(Client: TClient; Request: TRequest): Boolean;
  begin
    if Client <> nil then
    begin
      Client.SendMessage(Request);
      Exit(True);
    end;
    Exit(False);
  end;

   /// <summary>
  /// ����������� ������ � ��������� ������������� � �������� �������.
  /// </summary>
  /// <param name="Connection">���������� � �������������.</param>
  /// <param name="Request">��������� ������������� �������.</param>
  procedure TServer.SendMessage(Connection: TIdTCPConnection;
        Request: TRequest);
  var
    Client: TClient;
  begin
    if (Request <> nil)
      and (Connection <> nil) then
    begin
      Client := HandlerStationR414.FindByConnection(Connection);

      if Client = nil then
      begin
        Connection.IOHandler.WriteLn(Request.ConvertToText,
          TIdTextEncoding.UTF8);
        Exit;
      end;

      if SendMessage(Client, Request) then Exit;
    end;
  end;

  /// <summary>
  /// ���������� ������ �������.
  /// </summary>
  function TServer.GetStatusServer : Boolean;
  begin
    Exit(TCPServer.Active);
  end;

  /// <summary>
  /// ��������� ������.
  /// </summary>
  procedure TServer.StartServer;
  begin
    Clear;
    TCPServer.Active:= True;
  end;

  /// <summary>
  /// ���������� ������� ������ ��������.
  /// </summary>
  procedure TServer.Clear;
  begin
    HandlerStationR414.Clear;
  end;

  /// <summary>
  /// ������������� ������.
  /// </summary>
  procedure TServer.StopServer;
  begin
    Clear;
    TCPServer.Scheduler.AcquireYarn;
    TCPServer.Scheduler.ActiveYarns.Clear;
    TCPServer.Active:= False;
  end;

  /// <summary>
  /// ���������� ����������� ������� � �������.
  /// </summary>
  /// <param name="AContext">�������� ������.</param>
  procedure TServer.ServerConnect(AContext: TIdContext);
  begin
    AContext.Connection.IOHandler.DefStringEncoding := TIdTextEncoding.UTF8;
    //AddClient(AContext.Connection);
  end;

  /// <summary>
  /// ���������� ���������� ������� �� �������.
  /// </summary>
  /// <param name="AContext">�������� ������.</param>
  procedure TServer.ServerDisconnect(AContext: TIdContext);
  begin
    HandlerStationR414.RemoveClient(AContext.Connection);
  end;

  /// <summary>
  /// ���������� �������� �������.
  /// </summary>
  /// <param name="AContext">�������� ������.</param>
  procedure TServer.ServerExecute(AContext: TIdContext);
  begin
    try
      if AContext.Connection.Connected
        and (AContext.Connection.IOHandler <> nil)
        and (AContext.Connection.IOHandler.Connected) then
        MessageParser(AContext.Connection,
          AContext.Connection.IOHandler.ReadLn(TIdTextEncoding.UTF8));
    except

    end;
  end;

  /// <summary>
  /// ��������� ������ ������� � ������. ���������� ������������ �� ����������.
  /// </summary>
  /// <param name="Connection">������ ������ TIdTCPConnection.</param>
  procedure TServer.AddClient(Connection: TIdTCPConnection);//TODO: ��������� ��� ���������.
  begin
    try
      Section.Enter;
      Connections.Add(Connection);
      Section.Leave;
    except
      Connection.Disconnect;
    end;
  end;

  /// <summary>
  /// ����������� ��������.
  /// </summary>
  /// <param name="Connection">������ ����������.</param>
  /// <param name="Name">��� ������������.</param>
  procedure TServer.RegisterClient (Connection : TIdTCPConnection;
    Request: TRequest);
  var
    Response: TRequest;
    ClientType: string;
  begin
    Response := TRequest.Create;
    ClientType := Request.GetValue('type');
    if Request.GetValue('username') <> '' then
    begin
      if ClientType = CLIENT_STATION_R414 then
      begin
         if HandlerStationR414.RegistrationClient(Request, Connection) then
        Exit;
      end;
    end;
    Response.Name := REQUEST_NAME_ERROR;
    SendMessage(Connection, Response);
  end;

  /// <summary>
  /// ������ ���������.
  /// </summary>
  /// <param name="Connection">������ ����������.</param>
  /// <param name="strMessage">��������� ���������� �� ������������.</param>
  procedure TServer.MessageParser(Connection: TIdTCPConnection;
    StrRequest : string);
  var
    Request, Response: TRequest;
    PairedStationR414: TStationR414;
  begin
    if Length(StrRequest) > 0 then
    begin
      try
        Response := TRequest.Create;
        Request := TRequest.Create;
        Request.ConvertToKeyValueList(StrRequest);

        if (Request.Name = REQUEST_NAME_REGISTRATION) then
        begin
          RegisterClient(Connection, Request);
        end
        else if(Request.Name = REQUEST_NAME_STATION_PARAMS) then
        begin
          if not (HandlerStationR414.SendParamsLinkedStationByHeadConnection(Connection,
            Request)) then
            begin
              Response.Name := REQUEST_NAME_ERROR;
              SendMessage(Connection, Response);
            end;
        end
        else if Request.Name = REQUEST_NAME_GET_ALL_STATIONS then
        begin
          SendMessage(Connection, HandlerStationR414.GetAllClients);
        end
        else if (Request.Name = REQUEST_NAME_MESSAGE) then
        begin
        Response.Name:= REQUEST_NAME_MESSAGE;
        Response.AddKeyValue(KEY_MESSAGE, Request.GetValue(KEY_MESSAGE));
               PairedStationR414:= HandlerStationR414.FindByConnection(Connection).LinkedStation;
               if not (PairedStationR414 = nil) then  begin
                 SendMessage(PairedStationR414, Request);
               end;

        end;
      except

      end;
    end;
  end;

end.
