/**
 * Module     : types.mo
 * Copyright  : 2021 DFinance Team
 * License    : Apache 2.0 with LLVM Exception
 * Maintainer : DFinance Team <hello@dfinance.ai>
 * Stability  : Experimental
 */

import Time "mo:base/Time";
import P "mo:base/Prelude";

module {
    /// Update call operations
    public type Operation = {
        #mint;
        #burn;
        #transfer;
        #transferFrom;
        #approve;
    };
    public type TransactionStatus = {
        #succeeded;
        #inprogress;
        #failed;
    };
    /// Update call operation record fields
    public type TxRecord = {
        caller: ?Principal;
        op: Operation;
        index: Nat;
        from: Principal;
        to: Principal;
        amount: Nat;
        fee: Nat;
        timestamp: Time.Time;
        status: TransactionStatus;
    };

    public type Metadata = {
        logo : Text;
        name : Text;
        symbol : Text;
        decimals : Nat8;
        totalSupply : Nat;
        owner : Principal;
        fee : Nat;
    };

    // returns tx index or error msg
    public type TxReceipt = {
        #Ok: Nat;
        #Err: {
            #InsufficientAllowance;
            #InsufficientBalance;
            #ErrorOperationStyle;
            #Unauthorized;
            #LedgerTrap;
            #ErrorTo;
            #Other: Text;
            #BlockUsed;
            #AmountTooSmall;
        };
    };

    public type TokenInfo = {
        metadata: Metadata;
        feeTo: Principal;
        // status info
        historySize: Nat;
        deployTime: Time.Time;
        holderNumber: Nat;
        cycles: Nat;
    };

    public func unwrap<T>(x : ?T) : T =
        switch x {
            case null { P.unreachable() };
            case (?x_) { x_ };
        };
    
    public type Self = actor {
        transfer : shared (to: Principal, value: Nat) -> async TxReceipt;
        transferFrom : shared (from: Principal, to: Principal, value: Nat) -> async TxReceipt;
        approve : shared (spender: Principal, value: Nat) -> async TxReceipt;
        logo : shared query () -> async Text;
        name : shared query () -> async Text;
        symbol : shared query () -> async Text;
        decimals : shared query () -> async Nat8;
        totalSupply : shared query () -> async Nat;
        getTokenFee : shared query () -> async Nat;
        balanceOf : shared query (who: Principal) -> async Nat;
        allowance : shared query (owner: Principal, spender: Principal) -> async Nat;
        getMetadata : shared query () -> async Metadata;
        historySize : shared query () -> async Nat;
        getTokenInfo : () -> async TokenInfo;
    };
}; 