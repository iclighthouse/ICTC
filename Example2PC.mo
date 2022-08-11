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
import TA "./src/TA";
import TPCTM "./src/TPCTM";

shared(installMsg) actor class Example() = this {
    type CallType = CallType.CallType;
    type TaskResult = CallType.TaskResult;
    private var tokenA_canister = Principal.fromText("ueghb-uqaaa-aaaak-aaioa-cai");
    private var tokenB_canister = Principal.fromText("udhbv-ziaaa-aaaak-aaioq-cai");
    private var x : Nat = 0;
    private func foo(count: Nat) : (){
        x += 100;
    };
    private func _local(_args: TPCTM.CallType, _receipt: ?TPCTM.Receipt) : async (TPCTM.TaskResult){
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
    private func _taskCallback(_tid: TPCTM.Ttid, _task: TPCTM.Task, _result: TPCTM.TaskResult) : async (){
        taskLogs := TA.arrayAppend(taskLogs, [(_tid, _task, _result)]);
    };
    private func _orderCallback(_oid: TPCTM.Toid, _status: TPCTM.OrderStatus, _data: ?Blob) : async (){
        orderLogs := TA.arrayAppend(orderLogs, [(_oid, _status)]);
    };

    private stable var taskLogs: [(TPCTM.Ttid, TPCTM.Task, TaskResult)] = [];
    private stable var orderLogs: [(TPCTM.Toid, TPCTM.OrderStatus)] = [];
    private var tpc: ?TPCTM.TPCTM = null;
    private func _getTPC() : TPCTM.TPCTM {
        switch(tpc){
            case(?(_tpc)){ return _tpc };
            case(_){
                let _tpc = TPCTM.TPCTM(Principal.fromActor(this), _local, ?_taskCallback, ?_orderCallback); //?_taskCallback, ?_orderCallback
                tpc := ?_tpc;
                return _tpc;
            };
        };
    };
    
    public query func getX() : async Nat{
        x;
    };
    public query func getTaskLogs() : async [(TPCTM.Ttid, TPCTM.Task, TaskResult)]{
        return taskLogs;
    };
    public query func getOrderLogs() : async [(TPCTM.Toid, TPCTM.OrderStatus)]{
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
        let act = TA.TA(50, 24*3600*1000000000, Principal.fromActor(this), _local, ?_taskCallback);
        var task = _task(tokenA_canister, #DRC20(#transfer(_account, 5000000000, null, null, null)));
        let tid1 = act.push(task);
        task := _task(tokenB_canister, #DRC20(#transfer(_account, 5000000000, null, null, null)));
        let tid2 = act.push(task);
        let f = act.run();
    };

    
    private func _buildTask(_businessId: ?Blob, _callee: Principal, _callType: TPCTM.CallType, _preTtids: [TPCTM.Ttid]) : TPCTM.TaskRequest{
        return {
            callee = _callee;
            callType = _callType;
            preTtid = _preTtids;
            attemptsMax = ?1;
            recallInterval = ?0; // nanoseconds
            cycles = 0;
            data = _businessId;
        };
    };
    private func _task(_callee: Principal, _callType: TPCTM.CallType) : TPCTM.Task{
        return {
            callee = _callee;
            callType = _callType;
            preTtid = [];
            toid = null;
            forTtid = null;
            attemptsMax = 3;
            recallInterval = (5*1000000000); // nanoseconds
            cycles = 0;
            data = null;
            time = Time.now();
        };
    };

    public shared(msg) func swap1(_to: Text): async (TPCTM.Toid, ?TPCTM.OrderStatus){
        let valueA: Nat = 100000000;
        let valueB: Nat = 200000000;
        let tokenFee: Nat = 100000;
        let caller: Text = Principal.toText(msg.caller);
        let to: Text = _to;
        let contract: Text =  Principal.toText(Principal.fromActor(this));

        // Transaction:
        /// prepare
        // tokenA: lockTransferFrom caller -> to  1.00000010
        // tokenB: lockTransferFrom to -> caller  2.00000010
        /// commit
        // tokenA: executeTransfer $tx1 #sendAll
        // tokenB: executeTransfer $tx2 #sendAll
        /// compensate
        // tokenA: executeTransfer $tx1 #fallback
        // tokenB: executeTransfer $tx2 #fallback

        let oid = _getTPC().create(null, null);
        var prepare = _buildTask(null, tokenA_canister, #DRC20(#lockTransferFrom(caller, to, valueA, 5*60, null, null, null, null)), []);
        var commit = _buildTask(null, tokenA_canister, #DRC20(#executeTransfer(#AutoFill, #sendAll, null, null, null, null)), []);
        var comp = _buildTask(null, tokenA_canister, #DRC20(#executeTransfer(#AutoFill, #fallback, null, null, null, null)), []);
        let tid1 = _getTPC().push(oid, prepare, commit, ?comp, null, null);
        prepare := _buildTask(null, tokenB_canister, #DRC20(#lockTransferFrom(to, caller, valueB, 5*60, null, null, null, null)), []);
        commit := _buildTask(null, tokenB_canister, #DRC20(#executeTransfer(#AutoFill, #sendAll, null, null, null, null)), []);
        comp := _buildTask(null, tokenB_canister, #DRC20(#executeTransfer(#AutoFill, #fallback, null, null, null, null)), []);
        let tid2 = _getTPC().push(oid, prepare, commit, ?comp, null, null);
        _getTPC().finish(oid);
        let res = await _getTPC().run(oid);
        return (oid, res);
    };

    public shared(msg) func swap2(_to: Text): async (TPCTM.Toid, ?TPCTM.OrderStatus){ // Blocking
        let valueA: Nat = 100000000;
        let valueB: Nat = 200000000;
        let tokenFee: Nat = 100000;
        let caller: Text = Principal.toText(msg.caller);
        let to: Text = _to;
        let contract: Text =  Principal.toText(Principal.fromActor(this));

        // Transaction:
        /// prepare
        // tokenA: lockTransferFrom caller -> to  1.00000010
        // tokenB: lockTransferFrom to -> caller  2.00000010
        /// commit
        // tokenA: executeTransfer $tx1 #sendAll
        // tokenB: executeTransfer $tx2 #sendAll
        /// compensate
        // tokenA: executeTransfer $tx1 #fallback
        // tokenB: executeTransfer $tx2 #fallback

        let oid = _getTPC().create(null, null);
        var prepare = _buildTask(null, tokenA_canister, #DRC20(#lockTransferFrom(caller, to, valueA, 5*60, null, null, null, null)), []);
        var commit = _buildTask(null, tokenA_canister, #DRC20(#executeTransfer(#AutoFill, #sendAll, null, null, null, null)), []);
        var comp = _buildTask(null, tokenA_canister, #DRC20(#executeTransfer(#AutoFill, #fallback, null, null, null, null)), []);
        let tid1 = _getTPC().push(oid, prepare, commit, ?comp, null, null);
        prepare := _buildTask(null, tokenB_canister, #DRC20(#lockTransferFrom(to, caller, valueB, 5*60, null, null, null, null)), []);
        commit := _buildTask(null, tokenB_canister, #DRC20(#executeTransfer(#ManualFill(Blob.fromArray([])), #sendAll, null, null, null, null)), []);
        comp := _buildTask(null, tokenB_canister, #DRC20(#executeTransfer(#ManualFill(Blob.fromArray([])), #fallback, null, null, null, null)), []);
        let tid2 = _getTPC().push(oid, prepare, commit, ?comp, null, null);
        _getTPC().finish(oid);
        let res = await _getTPC().run(oid);
        return (oid, res);
    };

    
    /**
    * ICTC Transaction Explorer Interface
    * (Optional) Implement the following interface, which allows you to browse transaction records and execute compensation transactions through a UI interface.
    * https://cmqwp-uiaaa-aaaaj-aihzq-cai.raw.ic0.app/
    */
    // ICTC: management functions
    private stable var ictc_admins: [Principal] = [installMsg.caller];
    private func _onlyIctcAdmin(_caller: Principal) : Bool { 
        return Option.isSome(Array.find(ictc_admins, func (t: Principal): Bool{ t == _caller }));
    }; 
    private func _onlyBlocking(_toid: Nat) : Bool{
        /// Saga
        // switch(_getSaga().status(_toid)){
        //     case(?(status)){ return status == #Blocking };
        //     case(_){ return false; };
        // };
        /// 2PC
        switch(_getTPC().status(_toid)){
            case(?(status)){ return status == #Blocking };
            case(_){ return false; };
        };
    };
    public query func ictc_getAdmins() : async [Principal]{
        return ictc_admins;
    };
    public shared(msg) func ictc_addAdmin(_admin: Principal) : async (){
        assert(_onlyIctcAdmin(msg.caller));
        if (Option.isNull(Array.find(ictc_admins, func (t: Principal): Bool{ t == _admin }))){
            ictc_admins := TA.arrayAppend(ictc_admins, [_admin]);
        };
    };
    public shared(msg) func ictc_removeAdmin(_admin: Principal) : async (){
        assert(_onlyIctcAdmin(msg.caller));
        ictc_admins := Array.filter(ictc_admins, func (t: Principal): Bool{ t != _admin });
    };

    // TPCTM Scan
    public query func ictc_TM() : async Text{
        return "2PC";
    };
    /// 2PC
    public query func ictc_2PC_getTOCount() : async Nat{
        return _getTPC().count();
    };
    public query func ictc_2PC_getTO(_toid: TPCTM.Toid) : async ?TPCTM.Order{
        return _getTPC().getOrder(_toid);
    };
    public query func ictc_2PC_getTOs(_page: Nat, _size: Nat) : async {data: [(TPCTM.Toid, TPCTM.Order)]; totalPage: Nat; total: Nat}{
        return _getTPC().getOrders(_page, _size);
    };
    public query func ictc_2PC_getTOPool() : async [(TPCTM.Toid, ?TPCTM.Order)]{
        return _getTPC().getAliveOrders();
    };
    public query func ictc_2PC_getTT(_ttid: TPCTM.Ttid) : async ?TPCTM.TaskEvent{
        return _getTPC().getActuator().getTaskEvent(_ttid);
    };
    public query func ictc_2PC_getTTByTO(_toid: TPCTM.Toid) : async [TPCTM.TaskEvent]{
        return _getTPC().getTaskEvents(_toid);
    };
    public query func ictc_2PC_getTTs(_page: Nat, _size: Nat) : async {data: [(TPCTM.Ttid, TPCTM.TaskEvent)]; totalPage: Nat; total: Nat}{
        return _getTPC().getActuator().getTaskEvents(_page, _size);
    };
    public query func ictc_2PC_getTTPool() : async [(TPCTM.Ttid, TPCTM.Task)]{
        let pool = _getTPC().getActuator().getTaskPool();
        let arr = Array.map<(TPCTM.Ttid, TPCTM.Task), (TPCTM.Ttid, TPCTM.Task)>(pool, 
        func (item:(TPCTM.Ttid, TPCTM.Task)): (TPCTM.Ttid, TPCTM.Task){
            (item.0, item.1);
        });
        return arr;
    };
    public query func ictc_2PC_getTTErrors(_page: Nat, _size: Nat) : async {data: [(Nat, TPCTM.ErrorLog)]; totalPage: Nat; total: Nat}{
        return _getTPC().getActuator().getErrorLogs(_page, _size);
    };
    public query func ictc_2PC_getCalleeStatus(_callee: Principal) : async ?TPCTM.CalleeStatus{
        return _getTPC().getActuator().calleeStatus(_callee);
    };

    // Transaction Governance
    // public shared(msg) func ictc_2PC_clearTT() : async (){ // Warning: Execute this method with caution
    //     assert(_onlyOwner(msg.caller));
    //     _getTPC().getActuator().clearTasks();
    // };
    // public shared(msg) func ictc_2PC_removeTT(_toid: TPCTM.Toid, _ttid: TPCTM.Ttid) : async ?TPCTM.Ttid{ // Warning: Execute this method with caution
    //     assert(_onlyBlocking(_toid));
    //     let tpc = _getTPC();
    //     tpc.open(_toid);
    //     let ttid = tpc.remove(_toid, _ttid);
    //     tpc.finish(_toid);
    //     return ttid;
    // };
    public shared(msg) func ictc_2PC_appendTT(_businessId: ?Blob, _toid: TPCTM.Toid, _forTtid: ?TPCTM.Ttid, _callee: Principal, _callType: TPCTM.CallType, _preTtids: [TPCTM.Ttid]) : async TPCTM.Ttid{
        // Governance or manual compensation (operation allowed only when a transaction order is in blocking status).
        // assert(_onlyIctcAdmin(msg.caller));
        assert(_onlyBlocking(_toid)); 
        let tpc = _getTPC();
        tpc.open(_toid);
        let taskRequest = _buildTask(_businessId, _callee, _callType, _preTtids);
        //let ttid = tpc.append(_toid, taskRequest, null, null);
        let ttid = tpc.appendComp(_toid, Option.get(_forTtid, 0), taskRequest, null);
        return ttid;
    };
    public shared(msg) func ictc_2PC_completeTO(_toid: TPCTM.Toid, _status: TPCTM.OrderStatus) : async Bool{
        // After governance or manual compensations, this method needs to be called to complete the transaction order.
        // assert(_onlyIctcAdmin(msg.caller));
        assert(_onlyBlocking(_toid));
        let tpc = _getTPC();
        tpc.finish(_toid);
        let r = await tpc.run(_toid);
        return await _getTPC().complete(_toid, _status);
    };
    /**
    * End: ICTC Transaction Explorer Interface
    */



    // upgrade
    /// Saga
    // private stable var __sagaData: [SagaTM.Data] = [];
    // system func preupgrade() {
    //     __sagaData := TA.arrayAppend(__sagaData, [_getSaga().getData()]);
    // };
    // system func postupgrade() {
    //     if (__sagaData.size() > 0){
    //         _getSaga().setData(__sagaData[0]);
    //         __sagaData := [];
    //     };
    // };
    /// 2PC
    private stable var __tpcData: [TPCTM.Data] = [];
    system func preupgrade() {
        __tpcData := TA.arrayAppend(__tpcData, [_getTPC().getData()]);
    };
    system func postupgrade() {
        if (__tpcData.size() > 0){
            _getTPC().setData(__tpcData[0]);
            __tpcData := [];
        };
    };

    
};