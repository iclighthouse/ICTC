module {
  public type AccountId = Blob;
  public type Address = Text;
  public type From = Address;
  public type To = Address;
  public type Amount = Nat;
  public type Sa = [Nat8];
  public type Nonce = Nat;
  public type Data = Blob;
  public type Gas = { #token : Nat; #cycles : Nat; #noFee };
  public type Config = {
    maxPublicationTries : ?Nat;
    enBlacklist : ?Bool;
    maxStorageTries : ?Nat;
    storageCanister : ?Text;
    miningCanister : ?Text;
    maxCacheNumberPer : ?Nat;
    maxCacheTime : ?Int;
    feeTo : ?Address;
  };
  public type Metadata = { content : Text; name : Text };
  public type Time = Int;
  public type Txid = Blob;
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
  public type Self = actor {
    ictokens_maxSupply : shared query () -> async ?Nat;
    ictokens_top100 : shared query () -> async [(Address, Amount)];
    ictokens_heldFirstTime : shared query Address -> async ?Int;
    ictokens_getConfig : shared query () -> async Config;
    ictokens_snapshot : shared Amount -> async Bool;
    ictokens_clearSnapshot : shared () -> async Bool;
    ictokens_getSnapshot : shared query (Nat, Nat) -> async (Int, [(AccountId, Nat)], Bool);
    ictokens_snapshotBalanceOf : shared query (Nat, Address) -> async (Int, ?Nat);
    ictokens_burn : shared (Amount, ?Nonce, ?Sa, ?Data) -> async TxnResult;
    ictokens_changeOwner : shared Principal -> async Bool;
    ictokens_config : shared Config -> async Bool;
    ictokens_cyclesWithdraw : shared (Principal, Nat, ?[Nat8]) -> async ();
    ictokens_mint : shared (To, Amount, ?Nonce, ?Data) -> async TxnResult;
    ictokens_setGas : shared Gas -> async Bool;
    ictokens_setMetadata : shared [Metadata] -> async Bool;
  }
}
