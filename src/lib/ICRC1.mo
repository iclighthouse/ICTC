/**
 * Module     : ICRC1.mo
 */
module {
    // Number of nanoseconds since the UNIX epoch in UTC timezone.
    public type Timestamp = Nat64;
    // Number of nanoseconds between two [Timestamp]s.
    public type Duration = Nat64;
    public type Subaccount = Blob;
    public type Account = { owner : Principal; subaccount : ?Subaccount; };
    public type Value = { #Nat : Nat; #Int : Int; #Text : Text; #Blob : Blob };
    public type TransferArgs = {
        from_subaccount: ?Subaccount;
        to: Account;
        amount: Nat;
        fee: ?Nat;
        memo: ?Blob;
        created_at_time: ?Timestamp; // nanos
    };
    public type TransferError = {
        #BadFee : { expected_fee : Nat };
        #BadBurn : { min_burn_amount : Nat };
        #InsufficientFunds : { balance : Nat };
        #TooOld : { allowed_window_nanos : Duration };
        #CreatedInFuture;
        #Duplicate : { duplicate_of : Nat };
        #TemporarilyUnavailable;
        #GenericError: { error_code : Nat; message : Text };
    };
    
    public type Self = actor {
        icrc1_supported_standards : shared query () -> async [{ name : Text; url : Text }];
        icrc1_metadata : shared query () -> async [(Text, Value)];
        icrc1_name : shared query () -> async Text;
        icrc1_symbol : shared query () -> async Text;
        icrc1_decimals : shared query () -> async Nat8;
        icrc1_fee : shared query () -> async Nat;
        icrc1_total_supply : shared query () -> async Nat;
        icrc1_minting_account : shared query () -> async ?Account;
        icrc1_balance_of : shared query (_owner: Account) -> async Nat;
        icrc1_transfer : shared (_args: TransferArgs) -> async { #Ok: Nat; #Err: TransferError; };
    }
};