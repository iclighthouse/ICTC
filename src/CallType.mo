/**
 * Module     : CallType.mo
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Description: Wrapping the methods used by the transaction. Modify this file to suit your needs.
                Notes: Upgrading canister after modifying CallType and Receipt types will cause the transaction log to be lost.
 * Refers     : https://github.com/iclighthouse/ICTC
 */

import Blob "mo:base/Blob";
import CF "./lib/CF";
import Cycles "mo:base/ExperimentalCycles";
import CyclesWallet "./lib/CyclesWallet";
import DRC20 "./lib/DRC20";
import DIP20 "./lib/DIP20";
import ICTokens "./lib/ICTokens";
import ICSwap "./lib/ICSwap";
import Error "mo:base/Error";
import IC "./lib/IC";
import Ledger "./lib/Ledger";
import Option "mo:base/Option";
import Principal "mo:base/Principal";

module {
    public let Version: Nat = 1;
    public let ICCanister: Text = "aaaaa-aa";
    public let LedgerCanister: Text = "ryjl3-tyaaa-aaaaa-aaaba-cai";
    public let CFCanister: Text = "6nmrm-laaaa-aaaak-aacfq-cai";
    public type Status = {#Todo; #Doing; #Done; #Error; #Unknown; };
    public type Err = {code: Error.ErrorCode; message: Text; };
    public type TaskResult = (Status, ?Receipt, ?Err);
    public type LocalCall = (CallType, ?Receipt) -> async (TaskResult);
    /// type ErrorCode = {
    ///   // Fatal error.
    ///   #system_fatal;
    ///   // Transient error.
    ///   #system_transient;
    ///   // Destination invalid.
    ///   #destination_invalid;
    ///   // Explicit reject by canister code.
    ///   #canister_reject;
    ///   // Canister trapped.
    ///   #canister_error;
    ///   // Future error code (with unrecognized numeric code)
    ///   #future : Nat32;
    ///     9901    No such actor.
    ///     9902    No such method.
    ///     9903    Return #err by canister code.
    ///     9904    Blocked by code.
    /// };

    // Re-wrapping of the canister's methods, parameters and return values.
    /// Wrap method names and parameters.
    public type CallType = { 
        #__skip;
        #__block;
        #IC: {
            #canister_status: { canister_id: Principal; };
            #deposit_cycles: { canister_id: Principal; };
            #raw_rand;
            #start_canister: { canister_id: Principal; };
            #stop_canister: { canister_id: Principal; };
            #update_settings: { canister_id : Principal; settings : IC.canister_settings; };
        }; 
        #Ledger: {
            #transfer: Ledger.TransferArgs;
            #account_balance: Ledger.AccountBalanceArgs;
        }; 
        #CyclesWallet: {
            #wallet_balance;
            #wallet_send: { canister: Principal; amount: Nat64 };
            #wallet_receive;  // Endpoint for receiving cycles.
            #wallet_call: { canister: Principal; method_name: Text; args: Blob; cycles: Nat64; };
            #get_events: ?{ from: ?Nat32; to: ?Nat32; };
            #get_chart: ?{ count: ?Nat32; precision: ?Nat64; };
        }; 
        // #CyclesFinance: {
        //     #getAccountId: CF.Address;
        //     #add : (CF.Address, ?CF.Nonce, ?CF.Data);
        //     #remove : (?CF.Shares, CF.CyclesWallet, ?CF.Nonce, ?CF.Sa, ?CF.Data);
        //     #cyclesToIcp : (CF.Address, ?CF.Nonce, ?CF.Data);
        //     #icpToCycles : (CF.IcpE8s, CF.CyclesWallet, ?CF.Nonce, ?CF.Sa, ?CF.Data);
        //     #claim : (CF.CyclesWallet, ?CF.Nonce, ?CF.Sa, ?CF.Data);
        //     #getEvents : ?CF.Address;
        //     #liquidity : ?CF.Address;
        //     #lpRewards : CF.Address;
        //     #txnRecord2 : CF.Txid;
        //     #withdraw: ?CF.Sa;
        //     #yield;
        // };
        #DRC20: {
            #approve : (DRC20.Spender, DRC20.Amount, ?DRC20.Nonce, ?DRC20.Sa, ?DRC20.Data);
            #balanceOf : DRC20.Address;
            #cyclesReceive : ?DRC20.Address;
            #decimals;
            #executeTransfer : (DRC20.Txid, DRC20.ExecuteType, ?DRC20.To, ?DRC20.Nonce, ?DRC20.Sa, ?DRC20.Data);
            #lockTransfer : (DRC20.To, DRC20.Amount, DRC20.Timeout, ?DRC20.Decider, ?DRC20.Nonce, ?DRC20.Sa, ?DRC20.Data);
            #lockTransferFrom : (DRC20.From, DRC20.To, DRC20.Amount, DRC20.Timeout, ?DRC20.Decider, ?DRC20.Nonce, ?DRC20.Sa, ?DRC20.Data );
            #subscribe : (DRC20.Callback, [DRC20.MsgType], ?DRC20.Sa);
            #transfer : (DRC20.To, DRC20.Amount, ?DRC20.Nonce, ?DRC20.Sa, ?DRC20.Data);
            #transferFrom : (DRC20.From, DRC20.To, DRC20.Amount, ?DRC20.Nonce, ?DRC20.Sa, ?DRC20.Data);
            #txnQuery : DRC20.TxnQueryRequest;
            #txnRecord : DRC20.Txid;
            #getCoinSeconds : ?DRC20.Address;
        }; 
        #ICTokens: {
            #mint: (_to:DRC20.Address, _value: DRC20.Amount, _nonce: ?DRC20.Nonce, _data: ?DRC20.Data);
            #burn: (_value: DRC20.Amount, _nonce: ?DRC20.Nonce, _sa: ?DRC20.Sa, _data: ?DRC20.Data);
            #heldFirstTime: DRC20.Address;
        };
        #DIP20: {
            #transfer : (to: Principal, value: Nat);
            #transferFrom : (from: Principal, to: Principal, value: Nat);
            #approve : (spender: Principal, value: Nat);
            #decimals;
            #balanceOf : (who: Principal);
        };
        #ICSwap: {
            #swap : (_value: {#token0: ICSwap.Amount; #token1: ICSwap.Amount}, _nonce: ?ICSwap.Nonce, _sa: ?ICSwap.Sa, _data: ?ICSwap.Data);
            #swap2 : (_tokenId: Principal, _value: ICSwap.Amount, _nonce: ?ICSwap.Nonce, _sa: ?ICSwap.Sa, _data: ?ICSwap.Data);
            #add : (_value0: ?ICSwap.Amount, _value1: ?ICSwap.Amount, _nonce: ?ICSwap.Nonce, _sa: ?ICSwap.Sa, _data: ?ICSwap.Data);
            #remove : (_shares: ?ICSwap.Amount, _nonce: ?ICSwap.Nonce, _sa: ?ICSwap.Sa, _data: ?ICSwap.Data);
            #claim : (_nonce: ?ICSwap.Nonce, _sa: ?ICSwap.Sa, _data: ?ICSwap.Data);
            #fallback : (_sa: ?ICSwap.Sa);
        };
        #This: {
            #foo: (Nat);
        };
    };

    /// Wrap return values of methods.
    public type Receipt = { 
        #__skip;
        #__block;
        #IC: {
            #canister_status: {
                status : { #stopped; #stopping; #running };
                memory_size : Nat;
                cycles : Nat;
                settings : IC.definite_canister_settings;
                module_hash : ?[Nat8];
            };
            #deposit_cycles: ();
            #raw_rand : [Nat8];
            #start_canister: ();
            #stop_canister: ();
            #update_settings: ();
        }; 
        #Ledger: {
            #transfer: Ledger.TransferResult;
            #account_balance: Ledger.ICP;
        }; 
        #CyclesWallet: {
            #wallet_balance: { amount: Nat64 };
            #wallet_send: CyclesWallet.WalletResult;
            #wallet_receive: ();
            #wallet_call: CyclesWallet.WalletResultCall;
            #get_events: [CyclesWallet.Event];
            #get_chart: [( Nat64, Nat64 )]; // (time, balance)
        }; 
        // #CyclesFinance: {
        //     #getAccountId: Text;
        //     #add : CF.TxnResult;
        //     #remove : CF.TxnResult;
        //     #cyclesToIcp : CF.TxnResult;
        //     #icpToCycles : CF.TxnResult;
        //     #claim : CF.TxnResult;
        //     #getEvents : [CF.TxnRecord];
        //     #liquidity : CF.Liquidity;
        //     #lpRewards : { cycles: Nat; icp: Nat; };
        //     #txnRecord2 : ?CF.TxnRecord;
        //     #withdraw: ();
        //     #yield: (apy24h: { apyCycles: Float; apyIcp: Float; }, apy7d: { apyCycles: Float; apyIcp: Float; });
        // };
        #DRC20: {
            #approve : DRC20.TxnResult;
            #balanceOf : DRC20.Amount;
            #cyclesReceive : Nat;
            #decimals: Nat8;
            #executeTransfer : DRC20.TxnResult;
            #lockTransfer : DRC20.TxnResult;
            #lockTransferFrom : DRC20.TxnResult;
            #subscribe : Bool;
            #transfer : DRC20.TxnResult;
            #transferFrom : DRC20.TxnResult;
            #txnQuery : DRC20.TxnQueryResponse;
            #txnRecord : ?DRC20.TxnRecord;
            #getCoinSeconds : (DRC20.CoinSeconds, ?DRC20.CoinSeconds);
        }; 
        #ICTokens: {
            #mint: DRC20.TxnResult;
            #burn: DRC20.TxnResult;
            #heldFirstTime: ?Int;
        };
        #DIP20: {
            #transfer : DIP20.TxReceipt;
            #transferFrom : DIP20.TxReceipt;
            #approve : DIP20.TxReceipt;
            #decimals : Nat8;
            #balanceOf : Nat;
        };
        #ICSwap: {
            #swap : ICSwap.TxnResult;
            #swap2 : ICSwap.TxnResult;
            #add : ICSwap.TxnResult;
            #remove : ICSwap.TxnResult;
            #claim : ICSwap.TxnResult;
            #fallback : ();
        };
        #This: {
            #foo: ();
        };
    };

    public type Domain = {
        #Local : LocalCall;
        #Canister : (Principal, Nat); // (Canister-id, AddCycles)
    };

    /// Wrap the calling function
    public func call(_args: CallType, _domain: Domain, _receipt: ?Receipt) : async TaskResult{
        switch(_domain){
            // Local Task Call
            case(#Local(localCall)){
                switch(_args){
                    case(#__skip){ return (#Done, ?#__skip, null); };
                    case(#__block){ return (#Error, ?#__block, ?{code=#future(9904); message="Blocked by code."; }); };
                    case(#This(method)){
                        try{
                            return await localCall(_args, _receipt);
                        } catch (e){
                            return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                        };
                    };
                    case(_){ return (#Error, null, ?{code=#future(9901); message="No such actor."; }); };
                };
            };
            // Cross-Canister Task Call
            case(#Canister((callee, cycles))){
                var calleeId = Principal.toText(callee);
                switch(_args){
                    case(#__skip){ return (#Done, ?#__skip, null); };
                    case(#__block){ return (#Error, ?#__block, ?{code=#future(9904); message="Blocked by code."; }); };
                    case(#Ledger(method)){
                        let ledger: Ledger.Self = actor(calleeId);
                        switch(method){
                            case(#account_balance(args)){
                                var result: Ledger.ICP = { e8s = 0;}; // Receipt
                                try{
                                    // do
                                    result := await ledger.account_balance(args);
                                    // check & return
                                    return (#Done, ?#Ledger(#account_balance(result)), null);
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#transfer(args)){
                                var result: Ledger.TransferResult = #Ok(0); // Receipt
                                try{
                                    // do
                                    result := await ledger.transfer(args);
                                    // check & return
                                    switch(result){
                                        case(#Ok(high)){ return (#Done, ?#Ledger(#transfer(result)), null); };
                                        case(#Err(e)){ return (#Error, ?#Ledger(#transfer(result)), ?{code=#future(9903); message="ICP Transfer Error."; }); };
                                    };
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                        };
                    };
                    case(#DRC20(method)){
                        let token: DRC20.Self = actor(calleeId);
                        if (cycles > 0){ Cycles.add(cycles); };
                        switch(method){
                            case(#balanceOf(user)){
                                var result: Nat = 0; // Receipt
                                try{
                                    // do
                                    result := await token.drc20_balanceOf(user);
                                    // check & return
                                    return (#Done, ?#DRC20(#balanceOf(result)), null);
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#approve(spender, amount, nonce, sa, data)){
                                var result: DRC20.TxnResult = #err({code=#UndefinedError; message="Not called."}); // Receipt
                                try{
                                    // do
                                    result := await token.drc20_approve(spender, amount, nonce, sa, data);
                                    // check & return
                                    switch(result){
                                        case(#ok(txid)){ return (#Done, ?#DRC20(#approve(result)), null); };
                                        case(#err(e)){ return (#Error, ?#DRC20(#approve(result)), ?{code=#future(9903); message=e.message; }); };
                                    };
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#transfer(to, amount, nonce, sa, data)){
                                var result: DRC20.TxnResult = #err({code=#UndefinedError; message="Not called."}); // Receipt
                                try{
                                    // do
                                    result := await token.drc20_transfer(to, amount, nonce, sa, data);
                                    // check & return
                                    switch(result){
                                        case(#ok(txid)){ return (#Done, ?#DRC20(#transfer(result)), null); };
                                        case(#err(e)){ return (#Error, ?#DRC20(#transfer(result)), ?{code=#future(9903); message=e.message; }); };
                                    };
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#transferFrom(from, to, amount, nonce, sa, data)){
                                var result: DRC20.TxnResult = #err({code=#UndefinedError; message="Not called."}); // Receipt
                                try{
                                    // do
                                    result := await token.drc20_transferFrom(from, to, amount, nonce, sa, data);
                                    // check & return
                                    switch(result){
                                        case(#ok(txid)){ return (#Done, ?#DRC20(#transferFrom(result)), null); };
                                        case(#err(e)){ return (#Error, ?#DRC20(#transferFrom(result)), ?{code=#future(9903); message=e.message; }); };
                                    };
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#lockTransfer(to, amount, timeout, decider, nonce, sa, data)){
                                var result: DRC20.TxnResult = #err({code=#UndefinedError; message="Not called."}); // Receipt
                                try{
                                    // do
                                    result := await token.drc20_lockTransfer(to, amount, timeout, decider, nonce, sa, data);
                                    // check & return
                                    switch(result){
                                        case(#ok(txid)){ return (#Done, ?#DRC20(#lockTransfer(result)), null); };
                                        case(#err(e)){ return (#Error, ?#DRC20(#lockTransfer(result)), ?{code=#future(9903); message=e.message; }); };
                                    };
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#lockTransferFrom(from, to, amount, timeout, decider, nonce, sa, data)){
                                var result: DRC20.TxnResult = #err({code=#UndefinedError; message="Not called."}); // Receipt
                                try{
                                    // do
                                    result := await token.drc20_lockTransferFrom(from, to, amount, timeout, decider, nonce, sa, data);
                                    // check & return
                                    switch(result){
                                        case(#ok(txid)){ return (#Done, ?#DRC20(#lockTransferFrom(result)), null); };
                                        case(#err(e)){ return (#Error, ?#DRC20(#lockTransferFrom(result)), ?{code=#future(9903); message=e.message; }); };
                                    };
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#executeTransfer(txid, executeType, to, nonce, sa, data)){
                                var result: DRC20.TxnResult = #err({code=#UndefinedError; message="Not called."}); // Receipt
                                var txid_ = txid;
                                if (txid == Blob.fromArray([])){
                                    switch(_receipt){
                                        case(?(#DRC20(#lockTransferFrom(#ok(_txid))))){ txid_ := _txid };
                                        case(_){};
                                    };
                                };
                                try{
                                    // do
                                    result := await token.drc20_executeTransfer(txid_, executeType, to, nonce, sa, data);
                                    // check & return
                                    switch(result){
                                        case(#ok(txid)){ return (#Done, ?#DRC20(#executeTransfer(result)), null); };
                                        case(#err(e)){ return (#Error, ?#DRC20(#executeTransfer(result)), ?{code=#future(9903); message=e.message; }); };
                                    };
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#subscribe(callback, msgTypes, sa)){
                                var result: Bool = false; // Receipt
                                try{
                                    // do
                                    result := await token.drc20_subscribe(callback, msgTypes, sa);
                                    // check & return
                                    if (result) { return (#Done, ?#DRC20(#subscribe(result)), null); }
                                    else { return (#Error, ?#DRC20(#subscribe(result)), ?{code=#future(9903); message="Subscription failed."; }); };
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#txnQuery(request)){
                                var result: DRC20.TxnQueryResponse = #getTxn(null); // Receipt
                                try{
                                    // do
                                    result := await token.drc20_txnQuery(request);
                                    // check & return
                                    return (#Done, ?#DRC20(#txnQuery(result)), null);
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#txnRecord(txid)){
                                var result: ?DRC20.TxnRecord = null; // Receipt
                                try{
                                    // do
                                    result := await token.drc20_txnRecord(txid);
                                    // check & return
                                    return (#Done, ?#DRC20(#txnRecord(result)), null);
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#getCoinSeconds(user)){
                                var result: (DRC20.CoinSeconds, ?DRC20.CoinSeconds) = ({coinSeconds=0; updateTime=0}, null); // Receipt
                                try{
                                    // do
                                    result := await token.drc20_getCoinSeconds(user);
                                    // check & return
                                    return (#Done, ?#DRC20(#getCoinSeconds(result)), null);
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(_){ return (#Error, null, ?{code=#future(9902); message="No such method."; });};
                        };
                    };
                    case(#DIP20(method)){
                        let token: DIP20.Self = actor(calleeId);
                        if (cycles > 0){ Cycles.add(cycles); };
                        switch(method){
                            case(#balanceOf(user)){
                                var result: Nat = 0; // Receipt
                                try{
                                    // do
                                    result := await token.balanceOf(user);
                                    // check & return
                                    return (#Done, ?#DIP20(#balanceOf(result)), null);
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#approve(spender, amount)){
                                var result: DIP20.TxReceipt = #Err(#Other("")); // Receipt
                                try{
                                    // do
                                    result := await token.approve(spender, amount);
                                    // check & return
                                    switch(result){
                                        case(#Ok(txid)){ return (#Done, ?#DIP20(#approve(result)), null); };
                                        case(#Err(e)){ return (#Error, ?#DIP20(#approve(result)), ?{code=#future(9903); message="DIP20 token Err."; }); };
                                    };
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#transfer(to, amount)){
                                var result: DIP20.TxReceipt = #Err(#Other("")); // Receipt
                                try{
                                    // do
                                    result := await token.transfer(to, amount);
                                    // check & return
                                    switch(result){
                                        case(#Ok(txid)){ return (#Done, ?#DIP20(#transfer(result)), null); };
                                        case(#Err(e)){ return (#Error, ?#DIP20(#transfer(result)), ?{code=#future(9903); message="DIP20 token Err."; }); };
                                    };
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#transferFrom(from, to, amount)){
                                var result: DIP20.TxReceipt = #Err(#Other("")); // Receipt
                                try{
                                    // do
                                    result := await token.transferFrom(from, to, amount);
                                    // check & return
                                    switch(result){
                                        case(#Ok(txid)){ return (#Done, ?#DIP20(#transferFrom(result)), null); };
                                        case(#Err(e)){ return (#Error, ?#DIP20(#transferFrom(result)), ?{code=#future(9903); message="DIP20 token Err."; }); };
                                    };
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(_){ return (#Error, null, ?{code=#future(9902); message="No such method."; });};
                        };
                    };
                    case(#ICTokens(method)){
                        let token: ICTokens.Self = actor(calleeId);
                        if (cycles > 0){ Cycles.add(cycles); };
                        switch(method){
                            case(#mint(_to, _value, _nonce, _data)){
                                var result: ICTokens.TxnResult = #err({code=#UndefinedError; message="Not called."}); // Receipt
                                try{
                                    // do
                                    result := await token.ictokens_mint(_to, _value, _nonce, _data);
                                    // check & return
                                    switch(result){
                                        case(#ok(txid)){ return (#Done, ?#ICTokens(#mint(result)), null); };
                                        case(#err(e)){ return (#Error, ?#ICTokens(#mint(result)), ?{code=#future(9903); message="Calling Err."; }); };
                                    };
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#burn(_value, _nonce, _sa, _data)){
                                var result: ICTokens.TxnResult = #err({code=#UndefinedError; message="Not called."}); // Receipt
                                try{
                                    // do
                                    result := await token.ictokens_burn(_value, _nonce, _sa, _data);
                                    // check & return
                                    switch(result){
                                        case(#ok(txid)){ return (#Done, ?#ICTokens(#burn(result)), null); };
                                        case(#err(e)){ return (#Error, ?#ICTokens(#burn(result)), ?{code=#future(9903); message="Calling Err."; }); };
                                    };
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#heldFirstTime(_owner)){
                                var result: ?Int = ?0; // Receipt
                                try{
                                    // do
                                    result := await token.ictokens_heldFirstTime(_owner);
                                    // check & return
                                    return (#Done, ?#ICTokens(#heldFirstTime(result)), null);
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            //case(_){ return (#Error, null, ?{code=#future(9902); message="No such method."; });};
                        };
                    };
                    case(#ICSwap(method)){
                        let swap: ICSwap.Self = actor(calleeId);
                        if (cycles > 0){ Cycles.add(cycles); };
                        switch(method){
                            case(#swap(_value, _nonce, _sa, _data)){
                                var result: ICSwap.TxnResult = #err({code=#UndefinedError; message="Not called."}); // Receipt
                                try{
                                    // do
                                    result := await swap.swap(_value, _nonce, _sa, _data);
                                    // check & return
                                    switch(result){
                                        case(#ok(res)){ return (#Done, ?#ICSwap(#swap(result)), null); };
                                        case(#err(e)){ return (#Error, ?#ICSwap(#swap(result)), ?{code=#future(9903); message="Calling Err."; }); };
                                    };
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#swap2(_tokenId, _value, _nonce, _sa, _data)){
                                var result: ICSwap.TxnResult = #err({code=#UndefinedError; message="Not called."}); // Receipt
                                try{
                                    // do
                                    result := await swap.swap2(_tokenId, _value, _nonce, _sa, _data);
                                    // check & return
                                    switch(result){
                                        case(#ok(res)){ return (#Done, ?#ICSwap(#swap2(result)), null); };
                                        case(#err(e)){ return (#Error, ?#ICSwap(#swap2(result)), ?{code=#future(9903); message="Calling Err."; }); };
                                    };
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#add(_value0, _value1, _nonce, _sa, _data)){
                                var result: ICSwap.TxnResult = #err({code=#UndefinedError; message="Not called."}); // Receipt
                                try{
                                    // do
                                    result := await swap.add(_value0, _value1, _nonce, _sa, _data);
                                    // check & return
                                    switch(result){
                                        case(#ok(res)){ return (#Done, ?#ICSwap(#add(result)), null); };
                                        case(#err(e)){ return (#Error, ?#ICSwap(#add(result)), ?{code=#future(9903); message="Calling Err."; }); };
                                    };
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#remove(_shares, _nonce, _sa, _data)){
                                var result: ICSwap.TxnResult = #err({code=#UndefinedError; message="Not called."}); // Receipt
                                try{
                                    // do
                                    result := await swap.remove(_shares, _nonce, _sa, _data);
                                    // check & return
                                    switch(result){
                                        case(#ok(res)){ return (#Done, ?#ICSwap(#remove(result)), null); };
                                        case(#err(e)){ return (#Error, ?#ICSwap(#remove(result)), ?{code=#future(9903); message="Calling Err."; }); };
                                    };
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#claim(_nonce, _sa, _data)){
                                var result: ICSwap.TxnResult = #err({code=#UndefinedError; message="Not called."}); // Receipt
                                try{
                                    // do
                                    result := await swap.claim(_nonce, _sa, _data);
                                    // check & return
                                    switch(result){
                                        case(#ok(res)){ return (#Done, ?#ICSwap(#claim(result)), null); };
                                        case(#err(e)){ return (#Error, ?#ICSwap(#claim(result)), ?{code=#future(9903); message="Calling Err."; }); };
                                    };
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                            case(#fallback(_sa)){
                                try{
                                    // do
                                    let result = await swap.fallback(_sa);
                                    // check & return
                                    return (#Done, ?#ICSwap(#fallback(result)), null);
                                } catch (e){
                                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                                };
                            };
                        };
                    };
                    case(_){ return (#Error, null, ?{code=#future(9901); message="No such actor."; });};
                };
            };
        };
        
    };

};