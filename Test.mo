/**
 * Module     : ICTCTest.mo
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Github     : https://github.com/iclighthouse/ICTC/
 */

import Array "mo:base/Array";
import Nat "mo:base/Nat";
import Iter "mo:base/Iter";
import CallType "./lib/CallType";
import Principal "mo:base/Principal";
import SyncActuator "./lib/SyncActuator";

shared(installMsg) actor class ICTC() = this {
    type CallType = CallType.CallType;
    private var tokenA_canister = Principal.fromText("ueghb-uqaaa-aaaak-aaioa-cai");
    private var tokenB_canister = Principal.fromText("udhbv-ziaaa-aaaak-aaioq-cai");
    private var actuator = SyncActuator.SyncActuator(20);
    private stable var callbackLogs: [(SyncActuator.Tid, SyncActuator.Task, CallType.TaskResult)] = [];

    public query func getLogs() : async [(SyncActuator.Tid, SyncActuator.Task, CallType.TaskResult)]{
        return callbackLogs;
    };
    public shared func clearLogs() : async (){
        callbackLogs := [];
    };
    public shared func balanceOf(_account: Text) : async (balanceA: Nat, balanceB: Nat){
        let resA = await CallType.call(#DRC20(#balanceOf(_account)), tokenA_canister);
        let resB = await CallType.call(#DRC20(#balanceOf(_account)), tokenB_canister);
        var balanceA: Nat = 0;
        if (resA.0 == #Done){
            switch(resA.1){
                case(?(#DRC20(#balanceOf(value)))){ balanceA := value; };
                case(_){};
            };
        };
        var balanceB: Nat = 0;
        if (resB.0 == #Done){
            switch(resB.1){
                case(?(#DRC20(#balanceOf(value)))){ balanceB := value; };
                case(_){};
            };
        };
        return (balanceA, balanceB);
    };

    private func _callback(_tid: SyncActuator.Tid, _task: SyncActuator.Task, _result: CallType.TaskResult) : async (){
        callbackLogs := Array.append(callbackLogs, [(_tid, _task, _result)]);
    };

    public shared(msg) func swap(to: Text): async Bool{
        let valueA: Nat = 100000000;
        let valueB: Nat = 200000000;
        let from: Text = Principal.toText(msg.caller);
        let contract: Text =  Principal.toText(Principal.fromActor(this));
        let tid1 = actuator.push(tokenA_canister, #DRC20(#transferFrom(from, contract, valueA, null, null, null)), ?_callback, null);
        let tid2 = actuator.push(tokenB_canister, #DRC20(#transferFrom(to, contract, valueB, null, null, null)), ?_callback, ?{attempts=null; recallInterval=null; preTid=?tid1; data=null; });
        let tid3 = actuator.push(tokenA_canister, #DRC20(#transfer(to, valueA-10, null, null, null)), ?_callback, ?{attempts=null; recallInterval=null; preTid=?tid2; data=null; });
        let tid4 = actuator.push(tokenB_canister, #DRC20(#transfer(from, valueB-10, null, null, null)), ?_callback, ?{attempts=null; recallInterval=null; preTid=?tid2; data=null; });
        let f = await actuator.run();
        return true;
    };
    public shared(msg) func redo(_tid: Nat) : async Bool{
        switch(actuator.getTaskLog(_tid)){
            case(?(taskLog)){
                let tid = actuator.put(?_tid, taskLog.task.callee, taskLog.task.callType, taskLog.callback, 
                ?{attempts=?taskLog.task.attemptsMax; recallInterval=?taskLog.task.recallInterval; preTid=taskLog.task.preTid; data=taskLog.task.data; });
                let f = actuator.run();
                return true;
            };
            case(_){ return false; };
        };
    };
    public shared(msg) func run() : async Nat{
        await actuator.run();
    };
    public shared(msg) func remove(_tid: Nat) : async ?Nat{
            return actuator.remove(_tid);
        };

    public shared(msg) func clear(_expiration: Int) : async (){
        actuator.clear(?_expiration);
    };

    public query func getTaskPool() : async Nat{
        actuator.getTaskPool().size();
    };

    public query func getErrorLogs(_page: Nat, _size: Nat) : async {data: [(Nat, SyncActuator.ErrorLog)]; totalPage: Nat; total: Nat}{
        actuator.getErrorLogs(_page, _size);
    };

    public query func calleeStatus(_callee: Principal) : async ?SyncActuator.CalleeStatus{
        actuator.calleeStatus(_callee);
    };

    public query func getIndex() : async (Nat, Nat, Nat, Nat){
        let res = actuator.getData();
        return (
            res.index,
            res.firstIndex,
            res.errIndex,
            res.firstErrIndex
        );
    };

    
};