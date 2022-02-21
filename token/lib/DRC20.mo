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
      gas: Gas;
      name: ?Text;
      symbol: ?Text;
      metadata: ?[Metadata];
      founder: ?Address;
  };
  public type Self = actor {
    allowance : shared query (Address, Spender) -> async Amount;
    approvals : shared query Address -> async [Allowance];
    approve : shared (Spender, Amount, ?Nonce, ?Sa, ?Data) -> async TxnResult;
    balanceOf : shared query Address -> async Amount;
    cyclesBalanceOf : shared query Address -> async Nat;
    cyclesReceive : shared ?Address -> async Nat;
    decimals : shared query () -> async Nat8;
    executeTransfer : shared (Txid, ExecuteType, ?To, ?Nonce, ?Sa, ?Data) -> async TxnResult;
    gas : shared query () -> async Gas;
    lockTransfer : shared (
        To,
        Amount,
        Timeout,
        ?Decider, 
        ?Nonce,
        ?Sa,
        ?Data,
      ) -> async TxnResult;
    lockTransferFrom : shared (
        From,
        To,
        Amount,
        Timeout,
        ?Decider, 
        ?Nonce,
        ?Sa,
        ?Data,
      ) -> async TxnResult;
    metadata : shared query () -> async [Metadata];
    name : shared query () -> async Text;
    standard : shared query () -> async Text;
    subscribe : shared (Callback, [MsgType], ?Sa) -> async Bool;
    subscribed : shared query Address -> async ?Subscription;
    symbol : shared query () -> async Text;
    totalSupply : shared query () -> async Amount;
    transfer : shared (To, Amount, ?Nonce, ?Sa, ?Data) -> async TxnResult;
    transferFrom : shared (
        From,
        To,
        Amount, 
        ?Nonce,
        ?Sa,
        ?Data,
      ) -> async TxnResult;
    txnQuery : shared query TxnQueryRequest -> async TxnQueryResponse;
    txnRecord : shared (Txid) -> async ?TxnRecord;
    getCoinSeconds : shared query ?Address -> async (CoinSeconds, ?CoinSeconds);
  }
}