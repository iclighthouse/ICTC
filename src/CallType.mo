/**
 * Module     : CallType.mo v3.0
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Description: Wrapping the methods used by the transaction. 
 * Refers     : https://github.com/iclighthouse/ICTC
 */

import Blob "mo:base/Blob";
import Cycles "mo:base/ExperimentalCycles";
import DRC20 "mo:icl/DRC20";
import ICRC1 "mo:icl/ICRC1";
import ICRC2 "mo:icl/ICRC1";
import Result "mo:base/Result";
import Error "mo:base/Error";
import Option "mo:base/Option";
import Principal "mo:base/Principal";

module {
    public let Version: Nat = 10;
    public type Status = {#Todo; #Doing; #Done; #Error; #Unknown; };
    public type Err = {code: Error.ErrorCode; message: Text; };
    public type CallType<T> = { 
        #__skip;
        #__block;
        #custom: T;
        #ICRC1: {
            #icrc1_transfer : (ICRC1.TransferArgs);
        };
        #ICRC2: {
            #icrc2_approve : (ICRC2.ApproveArgs);
            #icrc2_transfer_from : (ICRC2.TransferFromArgs);
        };
        #DRC20: {
            #drc20_approve : (DRC20.Spender, DRC20.Amount, ?DRC20.Nonce, ?DRC20.Sa, ?DRC20.Data);
            #drc20_executeTransfer : (BlobFill, DRC20.ExecuteType, ?DRC20.To, ?DRC20.Nonce, ?DRC20.Sa, ?DRC20.Data);
            #drc20_lockTransfer : (DRC20.To, DRC20.Amount, DRC20.Timeout, ?DRC20.Decider, ?DRC20.Nonce, ?DRC20.Sa, ?DRC20.Data);
            #drc20_lockTransferFrom : (DRC20.From, DRC20.To, DRC20.Amount, DRC20.Timeout, ?DRC20.Decider, ?DRC20.Nonce, ?DRC20.Sa, ?DRC20.Data );
            #drc20_transfer : (DRC20.To, DRC20.Amount, ?DRC20.Nonce, ?DRC20.Sa, ?DRC20.Data);
            #drc20_transferBatch : ([DRC20.To], [DRC20.Amount], ?DRC20.Nonce, ?DRC20.Sa, ?DRC20.Data);
            #drc20_transferFrom : (DRC20.From, DRC20.To, DRC20.Amount, ?DRC20.Nonce, ?DRC20.Sa, ?DRC20.Data);
            #drc20_dropAccount: ?DRC20.Sa;
        }; 
    };
    public type Return = ([Nat8], Text);
    public type Receipt = {
        #none;
        #result: ?Return;
        #ICRC1: {
            #icrc1_transfer : { #Ok: Nat; #Err: ICRC1.TransferError; };
        };
        #ICRC2: {
            #icrc2_approve : ({ #Ok : Nat; #Err : ICRC2.ApproveError });
            #icrc2_transfer_from : ({ #Ok : Nat; #Err : ICRC2.TransferFromError });
        };
        #DRC20: {
            #drc20_approve : DRC20.TxnResult;
            #drc20_executeTransfer : DRC20.TxnResult;
            #drc20_lockTransfer : DRC20.TxnResult;
            #drc20_lockTransferFrom : DRC20.TxnResult;
            #drc20_transfer : DRC20.TxnResult;
            #drc20_transferBatch : [DRC20.TxnResult];
            #drc20_transferFrom : DRC20.TxnResult;
            #drc20_dropAccount;
        }; 
    };
    public type TaskResult = (Status, receipt: ?Receipt, ?Err);
    public type CustomCall<T> = (callee: Principal, cycles: Nat, CallType<T>, ?Receipt) -> async (TaskResult);

    public type BlobFill = {#AutoFill; #ManualFill: Blob; };
    public type NatFill = {#AutoFill; #ManualFill: Nat; };

    // type ErrorCode = {
    //   // Fatal error.
    //   #system_fatal;
    //   // Transient error.
    //   #system_transient;
    //   // Destination invalid.
    //   #destination_invalid;
    //   // Explicit reject by canister code.
    //   #canister_reject;
    //   // Canister trapped.
    //   #canister_error;
    //   // Future error code (with unrecognized numeric code)
    //   #future : Nat32;
    //     9901    No such actor.
    //     9902    No such method.
    //     9903    Return #err by canister code.
    //     9904    Blocked by code.
    // };

    /// Extracts the txid of DRC20
    public func DRC20Txid(txid: BlobFill, receipt: ?Receipt) : Blob{
        var txid_ = Blob.fromArray([]);
        switch(txid){
            case(#AutoFill){
                switch(receipt){
                    case(?(#DRC20(#drc20_lockTransfer(#ok(v))))){ txid_ := v };
                    case(?(#DRC20(#drc20_lockTransferFrom(#ok(v))))){ txid_ := v };
                    case(?(#DRC20(#drc20_transfer(#ok(v))))){ txid_ := v };
                    case(?(#DRC20(#drc20_transferFrom(#ok(v))))){ txid_ := v };
                    case(?(#DRC20(#drc20_executeTransfer(#ok(v))))){ txid_ := v };
                    case(?(#DRC20(#drc20_approve(#ok(v))))){ txid_ := v };
                    case(_){};
                };
            };
            case(#ManualFill(v)){ txid_ := v };
        };
        return txid_;
    };
    
    /// Extracts the blockIndex of ICRC1/ICRC2
    public func ICRCBlockIndex(index: NatFill, receipt: ?Receipt) : Nat{
        var index_ = 0;
        switch(index){
            case(#AutoFill){
                switch(receipt){
                    case(?(#ICRC1(#icrc1_transfer(#Ok(v))))){ index_ := v };
                    case(?(#ICRC2(#icrc2_approve(#Ok(v))))){ index_ := v };
                    case(?(#ICRC2(#icrc2_transfer_from(#Ok(v))))){ index_ := v };
                    case(_){};
                };
            };
            case(#ManualFill(v)){ index_ := v };
        };
        return index_;
    };

    /// Wrap the calling function
    public func call<T>(_callee: Principal, _cycles: Nat, _call: CustomCall<T>, _args: CallType<T>, _receipt: ?Receipt) : async* TaskResult{
        switch(_args){
            case(#__skip){ return (#Done, ?#none, null); };
            case(#__block){ return (#Error, ?#none, ?{code=#future(9904); message="Blocked by code."; }); };
            case(#custom(T)){
                try{
                    return await _call(_callee, _cycles, _args, _receipt);
                } catch (e){
                    return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                };
            };
            case(#ICRC1(method)){
                let token: ICRC1.Self = actor(Principal.toText(_callee));
                if (_cycles > 0){ Cycles.add(_cycles); };
                switch(method){
                    case(#icrc1_transfer(args)){
                        var result: { #Ok: Nat; #Err: ICRC1.TransferError; } = #Err(#TemporarilyUnavailable); // Receipt
                        try{
                            // do
                            result := await token.icrc1_transfer(args);
                            // check & return
                            switch(result){
                                case(#Ok(id)){ return (#Done, ?#ICRC1(#icrc1_transfer(result)), null); };
                                case(#Err(e)){ return (#Error, ?#ICRC1(#icrc1_transfer(result)), ?{code=#future(9903); message="ICRC1 token Err."; }); };
                            };
                        } catch (e){
                            return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                        };
                    };
                    //case(_){ return (#Error, null, ?{code=#future(9902); message="No such method."; });};
                };
            };
            case(#ICRC2(method)){
                let token: ICRC2.Self = actor(Principal.toText(_callee));
                if (_cycles > 0){ Cycles.add(_cycles); };
                switch(method){
                    case(#icrc2_approve(args)){
                        var result: { #Ok: Nat; #Err: ICRC2.ApproveError; } = #Err(#TemporarilyUnavailable); // Receipt
                        try{
                            // do
                            result := await token.icrc2_approve(args);
                            // check & return
                            switch(result){
                                case(#Ok(id)){ return (#Done, ?#ICRC2(#icrc2_approve(result)), null); };
                                case(#Err(e)){ return (#Error, ?#ICRC2(#icrc2_approve(result)), ?{code=#future(9903); message="ICRC2 token Err."; }); };
                            };
                        } catch (e){
                            return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                        };
                    };
                    case(#icrc2_transfer_from(args)){
                        var result: { #Ok: Nat; #Err: ICRC2.TransferFromError; } = #Err(#TemporarilyUnavailable); // Receipt
                        try{
                            // do
                            result := await token.icrc2_transfer_from(args);
                            // check & return
                            switch(result){
                                case(#Ok(id)){ return (#Done, ?#ICRC2(#icrc2_transfer_from(result)), null); };
                                case(#Err(e)){ return (#Error, ?#ICRC2(#icrc2_transfer_from(result)), ?{code=#future(9903); message="ICRC2 token Err."; }); };
                            };
                        } catch (e){
                            return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                        };
                    };
                };
            };
            case(#DRC20(method)){
                let token: DRC20.Self = actor(Principal.toText(_callee));
                if (_cycles > 0){ Cycles.add(_cycles); };
                switch(method){
                    case(#drc20_approve(spender, amount, nonce, sa, data)){
                        var result: DRC20.TxnResult = #err({code=#UndefinedError; message="No call."}); // Receipt
                        try{
                            // do
                            result := await token.drc20_approve(spender, amount, nonce, sa, data);
                            // check & return
                            switch(result){
                                case(#ok(txid)){ return (#Done, ?#DRC20(#drc20_approve(result)), null); };
                                case(#err(e)){ return (#Error, ?#DRC20(#drc20_approve(result)), ?{code=#future(9903); message=e.message; }); };
                            };
                        } catch (e){
                            return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                        };
                    };
                    case(#drc20_transfer(to, amount, nonce, sa, data)){
                        var result: DRC20.TxnResult = #err({code=#UndefinedError; message="No call."}); // Receipt
                        try{
                            // do
                            result := await token.drc20_transfer(to, amount, nonce, sa, data);
                            // check & return
                            switch(result){
                                case(#ok(txid)){ return (#Done, ?#DRC20(#drc20_transfer(result)), null); };
                                case(#err(e)){ return (#Error, ?#DRC20(#drc20_transfer(result)), ?{code=#future(9903); message=e.message; }); };
                            };
                        } catch (e){
                            return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                        };
                    };
                    case(#drc20_transferBatch(to, amount, nonce, sa, data)){
                        var results: [DRC20.TxnResult] = []; // Receipt
                        try{
                            // do
                            results := await token.drc20_transferBatch(to, amount, nonce, sa, data);
                            // check & return
                            var isSuccess : Bool = true;
                            for (result in results.vals()){
                                switch(result){
                                    case(#ok(txid)){};
                                    case(#err(e)){ isSuccess := false; };
                                };
                            };
                            if (isSuccess){
                                return (#Done, ?#DRC20(#drc20_transferBatch(results)), null);
                            }else{
                                return (#Error, ?#DRC20(#drc20_transferBatch(results)), ?{code=#future(9903); message="Batch transaction error."; });
                            };
                        } catch (e){
                            return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                        };
                    };
                    case(#drc20_transferFrom(from, to, amount, nonce, sa, data)){
                        var result: DRC20.TxnResult = #err({code=#UndefinedError; message="No call."}); // Receipt
                        try{
                            // do
                            result := await token.drc20_transferFrom(from, to, amount, nonce, sa, data);
                            // check & return
                            switch(result){
                                case(#ok(txid)){ return (#Done, ?#DRC20(#drc20_transferFrom(result)), null); };
                                case(#err(e)){ return (#Error, ?#DRC20(#drc20_transferFrom(result)), ?{code=#future(9903); message=e.message; }); };
                            };
                        } catch (e){
                            return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                        };
                    };
                    case(#drc20_lockTransfer(to, amount, timeout, decider, nonce, sa, data)){
                        var result: DRC20.TxnResult = #err({code=#UndefinedError; message="No call."}); // Receipt
                        try{
                            // do
                            result := await token.drc20_lockTransfer(to, amount, timeout, decider, nonce, sa, data);
                            // check & return
                            switch(result){
                                case(#ok(txid)){ return (#Done, ?#DRC20(#drc20_lockTransfer(result)), null); };
                                case(#err(e)){ return (#Error, ?#DRC20(#drc20_lockTransfer(result)), ?{code=#future(9903); message=e.message; }); };
                            };
                        } catch (e){
                            return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                        };
                    };
                    case(#drc20_lockTransferFrom(from, to, amount, timeout, decider, nonce, sa, data)){
                        var result: DRC20.TxnResult = #err({code=#UndefinedError; message="No call."}); // Receipt
                        try{
                            // do
                            result := await token.drc20_lockTransferFrom(from, to, amount, timeout, decider, nonce, sa, data);
                            // check & return
                            switch(result){
                                case(#ok(txid)){ return (#Done, ?#DRC20(#drc20_lockTransferFrom(result)), null); };
                                case(#err(e)){ return (#Error, ?#DRC20(#drc20_lockTransferFrom(result)), ?{code=#future(9903); message=e.message; }); };
                            };
                        } catch (e){
                            return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                        };
                    };
                    case(#drc20_executeTransfer(txid, executeType, to, nonce, sa, data)){
                        let txid_ = DRC20Txid(txid, _receipt);
                        var result: DRC20.TxnResult = #err({code=#UndefinedError; message="No call."}); // Receipt
                        try{
                            // do
                            result := await token.drc20_executeTransfer(txid_, executeType, to, nonce, sa, data);
                            // check & return
                            switch(result){
                                case(#ok(txid)){ return (#Done, ?#DRC20(#drc20_executeTransfer(result)), null); };
                                case(#err(e)){ return (#Error, ?#DRC20(#drc20_executeTransfer(result)), ?{code=#future(9903); message=e.message; }); };
                            };
                        } catch (e){
                            return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                        };
                    };
                    case(#drc20_dropAccount(_sa)){
                        try{
                            // do
                            let f = token.drc20_dropAccount(_sa);
                            // check & return
                            return (#Done, ?#DRC20(#drc20_dropAccount), null);
                        } catch (e){
                            return (#Error, null, ?{code=Error.code(e); message=Error.message(e); });
                        };
                    };
                    //case(_){ return (#Error, null, ?{code=#future(9902); message="No such method."; });};
                };
            };
        };
        
    };

};