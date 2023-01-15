/**
 * Module     : DRC205Types.mo
 * CanisterId : 6ylab-kiaaa-aaaak-aacga-cai
 * Test       : ix3cb-4iaaa-aaaak-aagbq-cai
 */
import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Nat32 "mo:base/Nat32";
import Blob "mo:base/Blob";
import Time "mo:base/Time";
import Binary "Binary";
import SHA224 "SHA224";
import Buffer "mo:base/Buffer";

module {
  public type Address = Text;
  public type Txid = Blob;
  public type AccountId = Blob;
  public type AppId = Principal;
  public type CyclesWallet = Principal;
  public type Nonce = Nat;
  public type Data = Blob;
  public type Shares = Nat;
  public type Status = {#Failed; #Pending; #Completed; #PartiallyCompletedAndCancelled; #Cancelled;};
  public type TokenType = {
      #Cycles;
      #Icp;
      #Token: Principal;
  };
  public type TokenStd = { #icp; #cycles; #drc20; #dip20; #dft; #icrc1; #ledger; #ext; #other: Text; };
  public type OperationType = {
      #AddLiquidity;
      #RemoveLiquidity;
      #Claim;
      #Swap;
  };
  public type BalanceChange = {
      #DebitRecord: Nat;
      #CreditRecord: Nat;
      #NoChange;
  };
  public type ShareChange = {
      #Mint: Shares;
      #Burn: Shares;
      #NoChange;
  };
  public type TxnRecordTemp = {
        txid: Txid;
        msgCaller: ?Principal;
        caller: AccountId;
        operation: OperationType;
        account: AccountId;
        cyclesWallet: ?CyclesWallet;
        token0: TokenType;
        token1: TokenType;
        token0Value: BalanceChange;
        token1Value: BalanceChange;
        fee: {token0Fee: Nat; token1Fee: Nat; };
        shares: ShareChange;
        time: Time.Time;
        index: Nat;
        nonce: Nonce;
        orderType: { #AMM; #OrderBook; };
        details: [{counterparty: Txid; token0Value: BalanceChange; token1Value: BalanceChange;}];
        data: ?Data;
    };
  public type TxnRecord = {
        txid: Txid;
        msgCaller: ?Principal;
        caller: AccountId;
        operation: OperationType;
        account: AccountId;
        cyclesWallet: ?CyclesWallet;
        token0: TokenType;
        token1: TokenType;
        fee: {token0Fee: Int; token1Fee: Int; };
        shares: ShareChange;
        time: Time.Time;
        index: Nat;
        nonce: Nonce;
        order: {token0Value: ?BalanceChange; token1Value: ?BalanceChange;};
        orderMode: { #AMM; #OrderBook; };
        orderType: ?{ #LMT; #FOK; #FAK; #MKT; };
        filled: {token0Value: BalanceChange; token1Value: BalanceChange;};
        details: [{counterparty: Txid; token0Value: BalanceChange; token1Value: BalanceChange; time: Time.Time;}];
        status: Status;
        data: ?Data;
    };
  public type Setting = {
        EN_DEBUG: Bool;
        MAX_CACHE_TIME: Nat;
        MAX_CACHE_NUMBER_PER: Nat;
        MAX_STORAGE_TRIES: Nat;
    };
    public type Config = {
        EN_DEBUG: ?Bool;
        MAX_CACHE_TIME: ?Nat;
        MAX_CACHE_NUMBER_PER: ?Nat;
        MAX_STORAGE_TRIES: ?Nat;
    };

  public type Self = actor {
    version: shared query () -> async Nat8;
    fee : shared query () -> async (cycles: Nat); //cycles
    store : shared (_txn: TxnRecord) -> async (); 
    storeBatch : shared (_txns: [TxnRecord]) -> async (); 
    storeBytes: shared (_txid: Txid, _data: [Nat8]) -> async (); 
    storeBytesBatch: shared (_txns: [(_txid: Txid, _data: [Nat8])]) -> async (); 
    bucket : shared query (_app: AppId, _txid: Txid, _step: Nat, _version: ?Nat8) -> async (bucket: ?Principal);
  };
  public type Bucket = actor {
    txnBytes: shared query (_app: AppId, _txid: Txid) -> async ?([Nat8], Time.Time);
    txnBytesHistory: shared query (_app: AppId, _txid: Txid) -> async [([Nat8], Time.Time)];
    txn: shared query (_app: AppId, _txid: Txid) -> async ?(TxnRecord, Time.Time);
    txnHistory: shared query (_app: AppId, _txid: Txid) -> async [(TxnRecord, Time.Time)];
    txnHash: shared query (_app: AppId, _txid: Txid, _index: Nat) -> async ?Text;
    txnBytesHash: shared query (_app: AppId, _txid: Txid, _index: Nat) -> async ?Text;
  };
  public type Impl = actor {
    drc205_getConfig : shared query () -> async Setting;
    drc205_canisterId : shared query () -> async Principal;
    drc205_events : shared query (_account: ?Address) -> async [TxnRecord];
    drc205_txn : shared query (_txid: Txid) -> async (txn: ?TxnRecord);
    drc205_txn2 : shared (_txid: Txid) -> async (txn: ?TxnRecord);
  };
  public func arrayAppend<T>(a: [T], b: [T]) : [T]{
        let buffer = Buffer.Buffer<T>(1);
        for (t in a.vals()){
            buffer.add(t);
        };
        for (t in b.vals()){
            buffer.add(t);
        };
        return Buffer.toArray(buffer);
    };
  public func generateTxid(_app: AppId, _caller: AccountId, _nonce: Nat): Txid{
    let appType: [Nat8] = [83:Nat8, 87, 65, 80]; //SWAP
    let canister: [Nat8] = Blob.toArray(Principal.toBlob(_app));
    let caller: [Nat8] = Blob.toArray(_caller);
    let nonce: [Nat8] = Binary.BigEndian.fromNat32(Nat32.fromNat(_nonce));
    let txInfo = arrayAppend(arrayAppend(arrayAppend(appType, canister), caller), nonce);
    let h224: [Nat8] = SHA224.sha224(txInfo);
    return Blob.fromArray(arrayAppend(nonce, h224));
  };
}
