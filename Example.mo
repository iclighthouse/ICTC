/**
 * Module     : ICTCTest.mo
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Github     : https://github.com/iclighthouse/ICTC/
 */

import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Nat "mo:base/Nat";
import Iter "mo:base/Iter";
import Time "mo:base/Time";
import Option "mo:base/Option";
import CallType "./src/CallType";
import Principal "mo:base/Principal";
import SyncTA "./src/SyncTA";
import SagaTM "./src/SagaTM";

shared(installMsg) actor class Example() = this {
    type CallType = CallType.CallType;
    type TaskResult = CallType.TaskResult;
    private var tokenA_canister = Principal.fromText("ueghb-uqaaa-aaaak-aaioa-cai");
    private var tokenB_canister = Principal.fromText("udhbv-ziaaa-aaaak-aaioq-cai");
    private var x : Nat = 0;
    private func foo(count: Nat) : (){
        x += 100;
    };
    private func _local(_args: SagaTM.CallType, _receipt: ?SagaTM.Receipt) : async (SagaTM.TaskResult){
        switch(_args){
            case(#This(method)){
                switch(method){
                    case(#foo(count)){
                        var result = foo(count); // Receipt
                        return (#Done, ?#This(#foo), null);
                    };
                };
            };
            case(_){ return (#Error, null, ?{code=#future(9901); message="Non-local function."; });};
        };
    };
    private func _taskCallback(_tid: SagaTM.Ttid, _task: SagaTM.Task, _result: SagaTM.TaskResult) : async (){
        taskLogs := SyncTA.arrayAppend(taskLogs, [(_tid, _task, _result)]);
    };
    private func _orderCallback(_oid: SagaTM.Toid, _status: SagaTM.OrderStatus, _data: ?Blob) : async (){
        orderLogs := SyncTA.arrayAppend(orderLogs, [(_oid, _status)]);
    };

    private stable var taskLogs: [(SagaTM.Ttid, SagaTM.Task, TaskResult)] = [];
    private stable var orderLogs: [(SagaTM.Toid, SagaTM.OrderStatus)] = [];
    private var saga: ?SagaTM.SagaTM = null;
    private func _getSaga() : SagaTM.SagaTM {
        switch(saga){
            case(?(_saga)){ return _saga };
            case(_){
                let _saga = SagaTM.SagaTM(Principal.fromActor(this), _local, ?_taskCallback, ?_orderCallback); //?_taskCallback, ?_orderCallback
                saga := ?_saga;
                return _saga;
            };
        };
    };
    
    public query func getX() : async Nat{
        x;
    };
    public query func getTaskLogs() : async [(SagaTM.Ttid, SagaTM.Task, TaskResult)]{
        return taskLogs;
    };
    public query func getOrderLogs() : async [(SagaTM.Toid, SagaTM.OrderStatus)]{
        return orderLogs;
    };
    public shared func clearLogs() : async (){
        taskLogs := [];
        orderLogs := [];
    };
    public shared func balanceOf(_account: Text) : async (balanceA: Nat, balanceB: Nat){
        let resA = await CallType.call(#DRC20(#balanceOf(_account)), #Canister(tokenA_canister, 0), null);
        let resB = await CallType.call(#DRC20(#balanceOf(_account)), #Canister(tokenB_canister, 0), null);
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
    public shared func claimTestTokens(_account: Text) : async (){
        let act = SyncTA.SyncTA(50, 24*3600*1000000000, Principal.fromActor(this), _local, ?_taskCallback);
        var task = _task(tokenA_canister, #DRC20(#transfer(_account, 5000000000, null, null, null)), []);
        let tid1 = act.push(task);
        task := _task(tokenB_canister, #DRC20(#transfer(_account, 5000000000, null, null, null)), []);
        let tid2 = act.push(task);
        let f = act.run();
    };

    
    private func _buildTask(_callee: Principal, _callType: SagaTM.CallType, _preTtid: [SagaTM.Ttid]) : SagaTM.PushTaskRequest{
        return {
            callee = _callee;
            callType = _callType;
            preTtid = _preTtid;
            attemptsMax = ?1;
            recallInterval = ?0; // nanoseconds
            cycles = 0;
            data = null;
        };
    };
    private func _task(_callee: Principal, _callType: SagaTM.CallType, _preTtid: [SagaTM.Ttid]) : SagaTM.Task{
        return {
            callee = _callee;
            callType = _callType;
            preTtid = _preTtid;
            toid = null;
            compFor = null;
            attemptsMax = 3;
            recallInterval = (5*1000000000); // nanoseconds
            cycles = 0;
            data = null;
            time = Time.now();
        };
    };

    public shared(msg) func swap1(_to: Text): async (SagaTM.Toid, ?SagaTM.OrderStatus){
        let valueA: Nat = 100000000;
        let valueB: Nat = 200000000;
        let tokenFee: Nat = 100000;
        let caller: Text = Principal.toText(msg.caller);
        let to: Text = _to;
        let contract: Text =  Principal.toText(Principal.fromActor(this));

        // Transaction:
        // tokenA: transferFrom caller -> contract  1.00000010
        // tokenB: transferFrom to -> contract  2.00000010
        // local: _foo  x+100
        // tokenA: transfer contract -> to  1.00000000
        // tokenB: transfer contract -> caller  2.00000000

        let oid = _getSaga().create(#Forward, null, null);
        var task = _buildTask(tokenA_canister, #DRC20(#transferFrom(caller, contract, valueA+tokenFee, null, null, null)), []);
        let tid1 =_getSaga().push(oid, task, null, null);
        task := _buildTask(tokenB_canister, #DRC20(#transferFrom(to, contract, valueB+tokenFee, null, null, null)), []);
        let tid2 =_getSaga().push(oid, task, null, null);
        task := _buildTask(Principal.fromActor(this), #This(#foo(1)), []);
        let tid3 =_getSaga().push(oid, task, null, null);
        task := _buildTask(tokenA_canister, #DRC20(#transfer(to, valueA, null, null, null)), []);
        let tid4 =_getSaga().push(oid, task, null, null);
        task := _buildTask(tokenB_canister, #DRC20(#transfer(caller, valueB, null, null, null)), []);
        let tid5 =_getSaga().push(oid, task, null, null);
        _getSaga().finish(oid);
        let res = await _getSaga().run(oid);
        return (oid, res);
    };
    public shared(msg) func swap2(_to: Text): async (SagaTM.Toid, ?SagaTM.OrderStatus){
        let valueA: Nat = 100000000;
        let valueB: Nat = 200000000;
        let tokenFee: Nat = 100000;
        let caller: Text = Principal.toText(msg.caller);
        let to: Text = _to;
        let contract: Text =  Principal.toText(Principal.fromActor(this));

        // Transaction:
        // tokenA: transferFrom caller -> contract  1.00000010  // Rollback when an exception occurs
        // tokenB: transferFrom to -> contract  2.00000010  // Rollback when an exception occurs
        // local: _foo  x+100  // Skip when an exception occurs
        // tokenA: transfer contract -> to  1.00000000  // Block when an exception occurs
        // tokenB: transfer contract -> caller  2.00000000  // Block when an exception occurs

        let oid = _getSaga().create(#Backward, null, null);
        var task = _buildTask(tokenA_canister, #DRC20(#transferFrom(caller, contract, valueA+tokenFee, null, null, null)), []);
        var comp = _buildTask(tokenA_canister, #DRC20(#transfer(caller, valueA, null, null, null)), []);
        let tid1 =_getSaga().push(oid, task, ?comp, null);
        task := _buildTask(tokenB_canister, #DRC20(#transferFrom(to, contract, valueB+tokenFee, null, null, null)), []);
        comp := _buildTask(tokenB_canister, #DRC20(#transfer(to, valueB, null, null, null)), []);
        let tid2 =_getSaga().push(oid, task, ?comp, null);
        task := _buildTask(Principal.fromActor(this), #This(#foo(1)), []);
        comp := _buildTask(Principal.fromActor(this), #__skip, []);
        let tid3 =_getSaga().push(oid, task, ?comp, null);
        task := _buildTask(tokenA_canister, #DRC20(#transfer(to, valueA, null, null, null)), []);
        let tid4 =_getSaga().push(oid, task, null, null);
        task := _buildTask(tokenB_canister, #DRC20(#transfer(caller, valueB, null, null, null)), []);
        let tid5 =_getSaga().push(oid, task, null, null);
        _getSaga().finish(oid);
        let res = await _getSaga().run(oid);
        return (oid, res);
    };
    public shared(msg) func swap3(_to: Text): async (SagaTM.Toid, ?SagaTM.OrderStatus){
        let valueA: Nat = 100000000;
        let valueB: Nat = 200000000;
        let tokenFee: Nat = 100000;
        let caller: Text = Principal.toText(msg.caller);
        let to: Text = _to;
        let contract: Text =  Principal.toText(Principal.fromActor(this));

        // Transaction:
        // tokenA: lockTransfer caller -> to  1.00000000    comp: execute
        // tokenB: lockTransfer to -> caller  2.00000000    comp: execute
        // local: _foo  x+100
        // tokenA: executeTransfer caller -> to  1.00000000
        // tokenB: executeTransfer to -> caller  2.00000000

        let oid = _getSaga().create(#Backward, null, null);
        var task = _buildTask(tokenA_canister, #DRC20(#lockTransferFrom(caller, to, valueA, 100000, null, null, null, null)), []);
        var comp = _buildTask(tokenA_canister, #DRC20(#executeTransfer(Blob.fromArray([]), #fallback, null, null, null, null)), []);
        let tid1 =_getSaga().push(oid, task, ?comp, null);
        task := _buildTask(tokenB_canister, #DRC20(#lockTransferFrom(to, caller, valueB, 100000, null, null, null, null)), []);
        comp := _buildTask(tokenB_canister, #DRC20(#executeTransfer(Blob.fromArray([]), #fallback, null, null, null, null)), []);
        let tid2 =_getSaga().push(oid, task, ?comp, null);
        task := _buildTask(Principal.fromActor(this), #This(#foo(1)), []);
        comp := _buildTask(Principal.fromActor(this), #__skip, []);
        let tid3 =_getSaga().push(oid, task, null, null);
        let res = await _getSaga().run(oid);
        var txid1 : Blob = Blob.fromArray([]);
        switch(_getSaga().getActuator().getTaskEvent(tid1)){
            case(?(event)){
                switch(event.result.1){
                    case(?(#DRC20(#executeTransfer(#ok(_txid))))){ txid1 := _txid };
                    case(_){};
                };
            };
            case(_){ return (oid, await _getSaga().run(oid)); /* blocking */};
        };
        task := _buildTask(tokenA_canister, #DRC20(#executeTransfer(txid1, #sendAll, null, null, null, null)), []);
        let tid4 =_getSaga().push(oid, task, null, null);
        var txid2 : Blob = Blob.fromArray([]);
        switch(_getSaga().getActuator().getTaskEvent(tid2)){
            case(?(event)){
                switch(event.result.1){
                    case(?(#DRC20(#executeTransfer(#ok(_txid))))){ txid2 := _txid };
                    case(_){};
                };
            };
            case(_){ return (oid, await _getSaga().run(oid)); /* blocking */};
        };
        task := _buildTask(tokenB_canister, #DRC20(#executeTransfer(txid2, #sendAll, null, null, null, null)), []);
        let tid5 =_getSaga().push(oid, task, null, null);
        _getSaga().finish(oid);
        return (oid, await _getSaga().run(oid));
    };
    
    // ICTC: management functions
    private func _onlyBlocking(_toid: SagaTM.Toid) : Bool{
        switch(_getSaga().status(_toid)){
            case(?(status)){ return status == #Blocking };
            case(_){ return false; };
        };
    };
    public query func ictc_getTOCount() : async Nat{
        return _getSaga().count();
    };
    public query func ictc_getTO(_toid: SagaTM.Toid) : async ?SagaTM.Order{
        return _getSaga().getOrder(_toid);
    };
    public query func ictc_getTOs(_page: Nat, _size: Nat) : async {data: [(SagaTM.Toid, SagaTM.Order)]; totalPage: Nat; total: Nat}{
        return _getSaga().getOrders(_page, _size);
    };
    public query func ictc_getTOPool() : async [(SagaTM.Toid, ?SagaTM.Order)]{
        return _getSaga().getAliveOrders();
    };
    public query func ictc_getTT(_ttid: SagaTM.Ttid) : async ?SagaTM.TaskEvent{
        return _getSaga().getActuator().getTaskEvent(_ttid);
    };
    public query func ictc_getTTByTO(_toid: SagaTM.Toid) : async [SagaTM.TaskEvent]{
        return _getSaga().getTaskEvents(_toid);
    };
    public query func ictc_getTTs(_page: Nat, _size: Nat) : async {data: [(SagaTM.Ttid, SagaTM.TaskEvent)]; totalPage: Nat; total: Nat}{
        return _getSaga().getActuator().getTaskEvents(_page, _size);
    };
    public query func ictc_getTTPool() : async [(SagaTM.Ttid, SagaTM.Task)]{
        let pool = _getSaga().getActuator().getTaskPool();
        let arr = Array.map<(SagaTM.Ttid, SagaTM.Task), (SagaTM.Ttid, SagaTM.Task)>(pool, 
        func (item:(SagaTM.Ttid, SagaTM.Task)): (SagaTM.Ttid, SagaTM.Task){
            (item.0, item.1);
        });
        return arr;
    };
    public query func ictc_getTTErrors(_page: Nat, _size: Nat) : async {data: [(Nat, SagaTM.ErrorLog)]; totalPage: Nat; total: Nat}{
        return _getSaga().getActuator().getErrorLogs(_page, _size);
    };
    public query func ictc_getCalleeStatus(_callee: Principal) : async ?SagaTM.CalleeStatus{
        return _getSaga().getActuator().calleeStatus(_callee);
    };
    // Governance
    // public shared(msg) func ictc_clearTT() : async (){ // Warning: Execute this method with caution
    //     assert(_onlyOwner(msg.caller));
    //     _getSaga().getActuator().clearTasks();
    // };
    public shared(msg) func ictc_removeTT(_toid: SagaTM.Toid, _ttid: SagaTM.Ttid) : async ?SagaTM.Ttid{
        assert(_onlyBlocking(_toid));
        let saga = _getSaga();
        saga.open(_toid);
        let ttid = saga.remove(_toid, _ttid);
        saga.finish(_toid);
        return ttid;
    };
    public shared(msg) func ictc_appendTT(_txid: Blob, _toid: SagaTM.Toid, _callee: Principal, _callType: SagaTM.CallType, _preTtids: [SagaTM.Ttid]) : async SagaTM.Ttid{
        assert(_onlyBlocking(_toid));
        let saga = _getSaga();
        saga.open(_toid);
        let taskRequest = _buildTask(_callee, _callType, _preTtids);
        let ttid = saga.append(_toid, taskRequest, null, null);
        //saga.finish(_toid);
        //let f = saga.run(_toid);
        return ttid;
    };
    public shared(msg) func ictc_completeTO(_toid: SagaTM.Toid, _status: SagaTM.OrderStatus) : async Bool{
        assert(_onlyBlocking(_toid));
        let saga = _getSaga();
        saga.finish(_toid);
        let r = await saga.run(_toid);
        return await _getSaga().complete(_toid, _status);
    };



    // upgrade
    private stable var __sagaData: [SagaTM.Data] = [];
    system func preupgrade() {
        __sagaData := SyncTA.arrayAppend(__sagaData, [_getSaga().getData()]);
    };
    system func postupgrade() {
        if (__sagaData.size() > 0){
            _getSaga().setData(__sagaData[0]);
            __sagaData := [];
        };
    };

    
};