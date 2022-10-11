/**
 * Module     : DRC20.mo
 * Author     : ICLight.house Team
 * Github     : https://github.com/iclighthouse/DRC_standards/
 */
module {
  public type AccountId = Blob;
  public type Address = Text;
  public type From = Address;
  public type To = Address;
  public type Spender = Address;
  public type Decider = Address;
  public type Amount = Nat;
  public type Sa = [Nat8];
  public type Nonce = Nat;
  public type Data = Blob;
  public type Timeout = Nat32;
  public type Allowance = { remaining : Nat; spender : AccountId };
  public type Callback = shared TxnRecord -> async ();
  public type ExecuteType = { #sendAll; #send : Nat; #fallback };
  public type Gas = { #token : Nat; #cycles : Nat; #noFee };
  public type Metadata = { content : Text; name : Text };
  public type MsgType = { #onApprove; #onExecute; #onTransfer; #onLock };
  public type CoinSeconds = { coinSeconds: Nat; updateTime: Int };
  public type Operation = {
    #approve : { allowance : Nat };
    #lockTransfer : { locked : Nat; expiration : Time; decider : AccountId };
    #transfer : { action : { #burn; #mint; #send } };
    #executeTransfer : { fallback : Nat; lockedTxid : Txid };
  };
  public type Subscription = { callback : Callback; msgTypes : [MsgType] };
  public type Time = Int;
  public type Transaction = {
    to : AccountId;
    value : Nat;
    data : ?Blob;
    from : AccountId;
    operation : Operation;
  };
  public type Txid = Blob;
  public type TxnQueryRequest = {
    #txnCount : { owner : Address };
    #lockedTxns : { owner : Address };
    #lastTxids : { owner : Address };
    #lastTxidsGlobal;
    #getTxn : { txid : Txid };
    #txnCountGlobal;
    #getEvents: { owner: ?Address; };
  };
  public type TxnQueryResponse = {
    #txnCount : Nat;
    #lockedTxns : { txns : [TxnRecord]; lockedBalance : Nat };
    #lastTxids : [Txid];
    #lastTxidsGlobal : [Txid];
    #getTxn : ?TxnRecord;
    #txnCountGlobal : Nat;
    #getEvents: [TxnRecord];
  };
  public type TxnRecord = {
    gas : Gas;
    transaction : Transaction;
    txid : Txid;
    nonce : Nat;
    timestamp : Time;
    msgCaller : ?Principal;
    caller : AccountId;
    index : Nat;
  };
  public type TxnResult = {
    #ok : Txid;
    #err : {
      code : {
        #InsufficientGas;
        #InsufficientAllowance;
        #UndefinedError;
        #InsufficientBalance;
        #NonceError;
        #NoLockedTransfer;
        #DuplicateExecutedTransfer;
        #LockedTransferExpired;
      };
      message : Text;
    };
  };
  public type InitArgs = {
      totalSupply: Nat;
      decimals: Nat8;
      fee: Nat;
      name: ?Text;
      symbol: ?Text;
      metadata: ?[Metadata];
      founder: ?Address;
  };
  public type Self = actor {
    standard : shared query () -> async Text;
    drc20_allowance : shared query (Address, Spender) -> async Amount;
    drc20_approvals : shared query Address -> async [Allowance];
    drc20_approve : shared (Spender, Amount, ?Nonce, ?Sa, ?Data) -> async TxnResult;
    drc20_balanceOf : shared query Address -> async Amount;
    drc20_decimals : shared query () -> async Nat8;
    drc20_executeTransfer : shared (Txid, ExecuteType, ?To, ?Nonce, ?Sa, ?Data) -> async TxnResult;
    drc20_fee : shared query () -> async Amount;
    drc20_lockTransfer : shared (To, Amount, Timeout, ?Decider, ?Nonce, ?Sa, ?Data) -> async TxnResult;
    drc20_lockTransferFrom : shared (From, To, Amount, Timeout, ?Decider, ?Nonce, ?Sa, ?Data) -> async TxnResult;
    drc20_metadata : shared query () -> async [Metadata];
    drc20_name : shared query () -> async Text;
    drc20_subscribe : shared (Callback, [MsgType], ?Sa) -> async Bool;
    drc20_subscribed : shared query Address -> async ?Subscription;
    drc20_symbol : shared query () -> async Text;
    drc20_totalSupply : shared query () -> async Amount;
    drc20_transfer : shared (To, Amount, ?Nonce, ?Sa, ?Data) -> async TxnResult;
    drc20_transferFrom : shared (From, To, Amount, ?Nonce, ?Sa, ?Data) -> async TxnResult;
    drc20_txnQuery : shared query TxnQueryRequest -> async TxnQueryResponse;
    drc20_txnRecord : shared (Txid) -> async ?TxnRecord;
    drc20_getCoinSeconds : shared query ?Address -> async (CoinSeconds, ?CoinSeconds);
    drc20_dropAccount : shared (?Sa) -> async Bool;
    drc20_holdersCount : shared query () -> async (balances: Nat, nonces: Nat, dropedAccounts: Nat);
  }
}