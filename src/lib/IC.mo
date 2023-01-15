// aaaaa-aa
// https://sdk.dfinity.org/docs/interface-spec/_attachments/ic.did
// https://k7gat-daaaa-aaaae-qaahq-cai.ic0.app/listing/ic-management-10246

module {
  public type canister_id = Principal;
  public type canister_settings = {
    freezing_threshold : ?Nat;
    controllers : ?[Principal];
    memory_allocation : ?Nat;
    compute_allocation : ?Nat;
  };
  public type definite_canister_settings = {
    freezing_threshold : Nat;
    controllers : [Principal];
    memory_allocation : Nat;
    compute_allocation : Nat;
  };
  public type user_id = Principal;
  public type wasm_module = [Nat8];
  public type HttpHeader = {
      name : Text;
      value : Text;
  };
  public type HttpMethod = {
      #get;
      #post;
      #head;
  };
  public type TransformArgs = {
    response : CanisterHttpResponsePayload;
    context : Blob;
  };
  public type TransformContext = {
        function : shared query TransformArgs -> async CanisterHttpResponsePayload;
        context : Blob;
    };
  public type CanisterHttpRequestArgs = {
      url : Text;
      max_response_bytes : ?Nat64;
      headers : [HttpHeader];
      body : ?[Nat8];
      method : HttpMethod;
      transform : ?TransformContext;
  };
  public type CanisterHttpResponsePayload = {
      status : Nat;
      headers : [HttpHeader];
      body : [Nat8];
  };
  public type Self = actor {
    canister_status : shared { canister_id : canister_id } -> async {
        status : { #stopped; #stopping; #running };
        memory_size : Nat;
        cycles : Nat;
        settings : definite_canister_settings;
        module_hash : ?[Nat8];
      };
    create_canister : shared { settings : ?canister_settings } -> async {
        canister_id : canister_id;
      };
    delete_canister : shared { canister_id : canister_id } -> async ();
    deposit_cycles : shared { canister_id : canister_id } -> async ();
    install_code : shared {
        arg : [Nat8];
        wasm_module : wasm_module;
        mode : { #reinstall; #upgrade; #install };
        canister_id : canister_id;
      } -> async ();
    provisional_create_canister_with_cycles : shared {
        settings : ?canister_settings;
        amount : ?Nat;
      } -> async { canister_id : canister_id };
    provisional_top_up_canister : shared {
        canister_id : canister_id;
        amount : Nat;
      } -> async ();
    raw_rand : shared () -> async [Nat8];
    start_canister : shared { canister_id : canister_id } -> async ();
    stop_canister : shared { canister_id : canister_id } -> async ();
    uninstall_code : shared { canister_id : canister_id } -> async ();
    update_settings : shared {
        canister_id : Principal;
        settings : canister_settings;
      } -> async ();
    // outcalls (sample:https://github.com/dfinity/examples/blob/master/motoko/exchange_rate/src/Main.mo)
    http_request : shared CanisterHttpRequestArgs -> async CanisterHttpResponsePayload;
  }
}