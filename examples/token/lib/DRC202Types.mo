/**
 * Module     : DRC202Types.mo
 * CanisterId : y5a36-liaaa-aaaak-aacqa-cai
 * Test       : iq2ev-rqaaa-aaaak-aagba-cai
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
  public type AccountId = Blob;
  public type Time = Time.Time;
  public type Txid = Blob;
  public type Token = Principal;
  public type Gas = { #token : Nat; #cycles : Nat; #noFee };
  public type Operation = {
    #approve : { allowance : Nat };
    #lockTransfer : { locked : Nat; expiration : Time; decider : AccountId };
    #transfer : { action : { #burn; #mint; #send } };
    #executeTransfer : { fallback : Nat; lockedTxid : Txid };
  };
  public type Transaction = {
    to : AccountId;
    value : Nat;
    data : ?Blob;
    from : AccountId;
    operation : Operation;
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
    setStd : shared (Text) -> async (); 
    store : shared (_txn: TxnRecord) -> async (); 
    storeBatch : shared (_txns: [TxnRecord]) -> async (); 
    storeBytes: shared (_txid: Txid, _data: [Nat8]) -> async (); 
    storeBytesBatch: shared (_txns: [(_txid: Txid, _data: [Nat8])]) -> async (); 
    bucket : shared query (_token: Principal, _txid: Txid, _step: Nat, _version: ?Nat8) -> async (bucket: ?Principal);
  };
  public type Bucket = actor {
    txnBytes: shared query (_token: Token, _txid: Txid) -> async ?([Nat8], Time.Time);
    txnBytesHistory: shared query (_token: Token, _txid: Txid) -> async [([Nat8], Time.Time)];
    txn: shared query (_token: Token, _txid: Txid) -> async ?(TxnRecord, Time.Time);
    txnHistory: shared query (_token: Token, _txid: Txid) -> async [(TxnRecord, Time.Time)];
    txnHash: shared query (_token: Token, _txid: Txid, _index: Nat) -> async ?Text;
    txnBytesHash: shared query (_token: Token, _txid: Txid, _index: Nat) -> async ?Text;
  };
  public type Impl = actor {
    drc202_getConfig : shared query () -> async Setting;
    drc202_canisterId : shared query () -> async Principal;
    drc202_events : shared query (_account: ?Address) -> async [TxnRecord];
    drc202_txn : shared query (_txid: Txid) -> async (txn: ?TxnRecord);
    drc202_txn2 : shared (_txid: Txid) -> async (txn: ?TxnRecord);
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
  public func generateTxid(_canister: Principal, _caller: AccountId, _nonce: Nat): Txid{
    let canister: [Nat8] = Blob.toArray(Principal.toBlob(_canister));
    let caller: [Nat8] = Blob.toArray(_caller);
    let nonce: [Nat8] = Binary.BigEndian.fromNat32(Nat32.fromNat(_nonce));
    let txInfo = arrayAppend(arrayAppend(canister, caller), nonce);
    let h224: [Nat8] = SHA224.sha224(txInfo);
    return Blob.fromArray(arrayAppend(nonce, h224));
  };
}
