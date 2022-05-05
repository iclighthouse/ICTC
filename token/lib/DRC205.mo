/**
 * Module     : DRC205.mo
 * Canister   : 6ylab-kiaaa-aaaak-aacga-cai
 */
import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Nat32 "mo:base/Nat32";
import Blob "mo:base/Blob";
import Time "mo:base/Time";
import Binary "Binary";
import SHA224 "SHA224";

module {
  public type Address = Text;
  public type Txid = Blob;
  public type AccountId = Blob;
  public type CyclesWallet = Principal;
  public type Nonce = Nat;
  public type Data = Blob;
  public type Shares = Nat;
  public type TokenType = {
      #Cycles;
      #Icp;
      #Token: Principal;
  };
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
  public type TxnRecord = {
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

  public type Self = actor {
    version: shared query () -> async Nat8;
    fee : shared query () -> async (cycles: Nat); //cycles
    store : shared (_txn: TxnRecord) -> async (); 
    storeBytes: shared (_txid: Txid, _data: [Nat8]) -> async (); 
    bucket : shared query (_canister: Principal, _txid: Txid, _step: Nat, _version: ?Nat8) -> async (bucket: ?Principal);
  };
  public type Bucket = actor {
    txnBytes: shared query (_app: Principal, _txid: Txid) -> async ?([Nat8], Time.Time);
    txn: shared query (_app: Principal, _txid: Txid) -> async ?(TxnRecord, Time.Time);
  };
  public func generateTxid(_app: Principal, _caller: AccountId, _nonce: Nat): Txid{
    let appType: [Nat8] = [83:Nat8, 87, 65, 80]; //SWAP
    let canister: [Nat8] = Blob.toArray(Principal.toBlob(_app));
    let caller: [Nat8] = Blob.toArray(_caller);
    let nonce: [Nat8] = Binary.BigEndian.fromNat32(Nat32.fromNat(_nonce));
    let txInfo = Array.append(Array.append(Array.append(appType, canister), caller), nonce);
    let h224: [Nat8] = SHA224.sha224(txInfo);
    return Blob.fromArray(Array.append(nonce, h224));
  };
}
