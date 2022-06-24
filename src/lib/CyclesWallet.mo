// Cycles Wallet
// https://github.com/dfinity/cycles-wallet/
// https://github.com/dfinity/cycles-wallet/blob/main/wallet/src/lib.did

module {
  public type EventKind = {
    #CyclesSent: {
      to: Principal;
      amount: Nat64;
      refund: Nat64;
    };
    #CyclesReceived: {
      from: Principal;
      amount: Nat64;
    };
    #AddressAdded: {
      id: Principal;
      name: ?Text;
      role: Role;
    };
    #AddressRemoved: {
      id: Principal;
    };
    #CanisterCreated: {
      canister: Principal;
      cycles: Nat64;
    };
    #CanisterCalled: {
      canister: Principal;
      method_name: Text;
      cycles: Nat64;
    };
    #WalletDeployed: {
      canister: Principal;
    }
  };

  public type Event = {
    id: Nat32;
    timestamp: Nat64;
    kind: EventKind;
  };

  public type Role = {
    #Contact;
    #Custodian;
    #Controller;
  };

  public type Kind = {
    #Unknown;
    #User;
    #Canister;
  };

  // An entry in the address book. It must have an ID and a role.
  public type AddressEntry = {
    id: Principal;
    name: ?Text;
    kind: Kind;
    role: Role;
  };

  public type WalletResultCreate = {
    #Ok : { canister_id: Principal };
    #Err: Text;
  };

  public type WalletResult = {
    #Ok;
    #Err : Text;
  };

  public type WalletResultCall = {
    #Ok : { return_: Blob };
    #Err : Text;
  };

  public type CanisterSettings = {
    controller: ?Principal;
    controllers: ?[Principal];
    compute_allocation: ?Nat;
    memory_allocation: ?Nat;
    freezing_threshold: ?Nat;
  };

  public type CreateCanisterArgs = {
    cycles: Nat64;
    settings: CanisterSettings;
  };


  // Assets
  public type HeaderField = (Text, Text);

  public type HttpRequest = {
    method: Text;
    url: Text;
    headers: [HeaderField];
    body: Blob;
  };

  public type HttpResponse = {
    status_code: Nat16;
    headers: [HeaderField];
    body: Blob;
    streaming_strategy: ?StreamingStrategy;
  };

  public type StreamingCallbackHttpResponse = {
    body: Blob;
    token: ?Token;
  };

  public type Token = {};

  public type StreamingStrategy = {
    #Callback: {
      callback: shared query (Token) -> async (StreamingCallbackHttpResponse);
      token: Token;
    };
  };
  public type Self = actor {
    wallet_api_version: shared query () -> async (Text);

    // Wallet Name
    name: shared query () -> async (?Text);
    set_name: shared (Text) -> async ();

    // Controller Management
    get_controllers: shared query () -> async ([Principal]);
    add_controller: shared (Principal) -> async ();
    remove_controller: shared (Principal) -> async (WalletResult);

    // Custodian Management
    get_custodians: shared query () -> async ([Principal]);
    authorize: shared (Principal) -> async ();
    deauthorize: shared (Principal) -> async (WalletResult);

    // Cycle Management
    wallet_balance: shared query () -> async ( { amount: Nat64 });
    wallet_send: shared ( { canister: Principal; amount: Nat64 }) -> async (WalletResult);
    wallet_receive: shared () -> async ();  // Endpoint for receiving cycles.

    // Managing canister
    wallet_create_canister: shared (CreateCanisterArgs) -> async (WalletResultCreate);

    wallet_create_wallet: shared (CreateCanisterArgs) -> async (WalletResultCreate);

    wallet_store_wallet_wasm: shared ( {
      wasm_module: Blob;
    }) -> async ();

    // Call Forwarding
    wallet_call: shared ( {
      canister: Principal;
      method_name: Text;
      args: Blob;
      cycles: Nat64;
    }) -> async (WalletResultCall);

    // Address book
    add_address: shared (address: AddressEntry) -> async ();
    list_addresses: shared query () -> async ([AddressEntry]);
    remove_address: shared (address: Principal) -> async (WalletResult);

    // Events
    get_events: shared query (?{ from: ?Nat32; to: ?Nat32; }) -> async ([Event]); //from,to is Event's id (只有controller才能调)
    get_chart: shared query (?{ count: ?Nat32; precision: ?Nat64; } ) -> async ([( Nat64, Nat64 )]); //(time, balance)

    // Assets
    http_request: shared query (request: HttpRequest) -> async (HttpResponse);
  };
}
