/**
 * Module     : ICTC 2PC Test
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Github     : https://github.com/iclighthouse/ICTC/
 */

import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Time "mo:base/Time";
import Option "mo:base/Option";
import Error "mo:base/Error";
import Principal "mo:base/Principal";
import Binary "mo:icl/Binary";
import CallType "../src/CallType";
import TA "../src/TA";
import TPCTM "../src/TPCTM";

shared(installMsg) actor class Example() = this {
    public type CustomCallType = { 
        #This: {
            #foo : (Nat);
        };
    };
    type CallType = CallType.CallType<CustomCallType>;
    type Task = TPCTM.Task<CustomCallType>;
    type TaskResult = CallType.TaskResult;
    private var tokenA_canister = Principal.fromText("ueghb-uqaaa-aaaak-aaioa-cai");
    private var tokenB_canister = Principal.fromText("udhbv-ziaaa-aaaak-aaioq-cai");
    private var x : Nat = 0;
    private func foo(_count: Nat) : Nat{
        x += _count;
        return x;
    };
    private func _localCall(_callee: Principal, _cycles: Nat, _args: CallType, _receipt: ?TPCTM.Receipt) : async (TaskResult){
        switch(_args){
            case(#custom(#This(method))){
                switch(method){
                    case(#foo(count)){
                        var result = foo(count); // Receipt
                        return (#Done, ?#result(?(Binary.BigEndian.fromNat64(Nat64.fromNat(result)), debug_show(result))), null);
                    };
                };
            };
            case(_){ return (#Error, null, ?{code=#future(9901); message="Non-local function."; });};
        };
    };
    private func _taskCallback(_name: Text, _tid: TPCTM.Ttid, _task: Task, _result: TaskResult) : async (){
        taskLogs := TA.arrayAppend(taskLogs, [(_tid, _task, _result)]);
    };
    private func _orderCallback(_name: Text, _oid: TPCTM.Toid, _status: TPCTM.OrderStatus, _data: ?Blob) : async (){
        orderLogs := TA.arrayAppend(orderLogs, [(_oid, _status)]);
    };

    private stable var taskLogs: [(TPCTM.Ttid, Task, TaskResult)] = [];
    private stable var orderLogs: [(TPCTM.Toid, TPCTM.OrderStatus)] = [];
    private var tpc: ?TPCTM.TPCTM<CustomCallType> = null;
    private func _getTPC() : TPCTM.TPCTM<CustomCallType> {
        switch(tpc){
            case(?(_tpc)){ return _tpc };
            case(_){
                let _tpc = TPCTM.TPCTM<CustomCallType>(Principal.fromActor(this), ?_localCall, ?_taskCallback, ?_orderCallback); //?_taskCallback, ?_orderCallback
                tpc := ?_tpc;
                return _tpc;
            };
        };
    };
    
    public query func getX() : async Nat{
        x;
    };
    public query func getTaskLogs() : async [(TPCTM.Ttid, Task, TaskResult)]{
        return taskLogs;
    };
    public query func getOrderLogs() : async [(TPCTM.Toid, TPCTM.OrderStatus)]{
        return orderLogs;
    };
    public shared func clearLogs() : async (){
        taskLogs := [];
        orderLogs := [];
    };
    public shared func claimTestTokens(_account: Text) : async (){
        let act = TA.TA<CustomCallType>(50, 24*3600*1000000000, _localCall, null, ?_taskCallback);
        var task = _task(tokenA_canister, #DRC20(#drc20_transfer(_account, 5000000000, null, null, null)));
        let _tid1 = act.push(task);
        task := _task(tokenB_canister, #DRC20(#drc20_transfer(_account, 5000000000, null, null, null)));
        let _tid2 = act.push(task);
        let _f = act.run();
    };

    
    private func _buildTask(_businessId: ?Blob, _callee: Principal, _callType: CallType, _preTtids: [TPCTM.Ttid]) : TPCTM.TaskRequest<CustomCallType>{
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
    private func _task(_callee: Principal, _callType: CallType) : Task{
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
        let caller: Text = Principal.toText(msg.caller);
        let to: Text = _to;

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

        let oid = _getTPC().create("swap1", null, null);
        var prepare = _buildTask(null, tokenA_canister, #DRC20(#drc20_lockTransferFrom(caller, to, valueA, 5*60, null, null, null, null)), []);
        var commit = _buildTask(null, tokenA_canister, #DRC20(#drc20_executeTransfer(#AutoFill, #sendAll, null, null, null, null)), []);
        var comp = _buildTask(null, tokenA_canister, #DRC20(#drc20_executeTransfer(#AutoFill, #fallback, null, null, null, null)), []);
        let _tid1 = _getTPC().push(oid, prepare, commit, ?comp, null, null);
        prepare := _buildTask(null, tokenB_canister, #DRC20(#drc20_lockTransferFrom(to, caller, valueB, 5*60, null, null, null, null)), []);
        commit := _buildTask(null, tokenB_canister, #DRC20(#drc20_executeTransfer(#AutoFill, #sendAll, null, null, null, null)), []);
        comp := _buildTask(null, tokenB_canister, #DRC20(#drc20_executeTransfer(#AutoFill, #fallback, null, null, null, null)), []);
        let _tid2 = _getTPC().push(oid, prepare, commit, ?comp, null, null);
        _getTPC().close(oid);
        let res = await _getTPC().run(oid);
        return (oid, res);
    };

    public shared(msg) func swap2(_to: Text): async (TPCTM.Toid, ?TPCTM.OrderStatus){ // Blocking
        let valueA: Nat = 100000000;
        let valueB: Nat = 200000000;
        let caller: Text = Principal.toText(msg.caller);
        let to: Text = _to;

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

        let oid = _getTPC().create("swap2", null, null);
        var prepare = _buildTask(null, tokenA_canister, #DRC20(#drc20_lockTransferFrom(caller, to, valueA, 5*60, null, null, null, null)), []);
        var commit = _buildTask(null, tokenA_canister, #DRC20(#drc20_executeTransfer(#AutoFill, #sendAll, null, null, null, null)), []);
        var comp = _buildTask(null, tokenA_canister, #DRC20(#drc20_executeTransfer(#AutoFill, #fallback, null, null, null, null)), []);
        let _tid1 = _getTPC().push(oid, prepare, commit, ?comp, null, null);
        prepare := _buildTask(null, tokenB_canister, #DRC20(#drc20_lockTransferFrom(to, caller, valueB, 5*60, null, null, null, null)), []);
        commit := _buildTask(null, tokenB_canister, #DRC20(#drc20_executeTransfer(#ManualFill(Blob.fromArray([])), #sendAll, null, null, null, null)), []);
        comp := _buildTask(null, tokenB_canister, #DRC20(#drc20_executeTransfer(#ManualFill(Blob.fromArray([])), #fallback, null, null, null, null)), []);
        let _tid2 = _getTPC().push(oid, prepare, commit, ?comp, null, null);
        _getTPC().close(oid);
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
        // switch(_getTPC().status(_toid)){
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
    public query func ictc_2PC_getTO(_toid: TPCTM.Toid) : async ?TPCTM.Order<CustomCallType>{
        return _getTPC().getOrder(_toid);
    };
    public query func ictc_2PC_getTOs(_page: Nat, _size: Nat) : async {data: [(TPCTM.Toid, TPCTM.Order<CustomCallType>)]; totalPage: Nat; total: Nat}{
        return _getTPC().getOrders(_page, _size);
    };
    public query func ictc_2PC_getTOPool() : async [(TPCTM.Toid, ?TPCTM.Order<CustomCallType>)]{
        return _getTPC().getAliveOrders();
    };
    public query func ictc_2PC_getTT(_ttid: TPCTM.Ttid) : async ?TPCTM.TaskEvent<CustomCallType>{
        return _getTPC().getActuator().getTaskEvent(_ttid);
    };
    public query func ictc_2PC_getTTByTO(_toid: TPCTM.Toid) : async [TPCTM.TaskEvent<CustomCallType>]{
        return _getTPC().getTaskEvents(_toid);
    };
    public query func ictc_2PC_getTTs(_page: Nat, _size: Nat) : async {data: [(TPCTM.Ttid, TPCTM.TaskEvent<CustomCallType>)]; totalPage: Nat; total: Nat}{
        return _getTPC().getActuator().getTaskEvents(_page, _size);
    };
    public query func ictc_2PC_getTTPool() : async [(TPCTM.Ttid, Task)]{
        let pool = _getTPC().getActuator().getTaskPool();
        let arr = Array.map<(TPCTM.Ttid, Task), (TPCTM.Ttid, Task)>(pool, 
        func (item:(TPCTM.Ttid, Task)): (TPCTM.Ttid, Task){
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
    public shared(msg) func ictc_clearLog(_expiration: ?Int, _delForced: Bool) : async (){ // Warning: Execute this method with caution
        assert(_onlyIctcAdmin(msg.caller));
        _getTPC().clear(_expiration, _delForced);
    };
    public shared(msg) func ictc_clearTTPool() : async (){ // Warning: Execute this method with caution
        assert(_onlyIctcAdmin(msg.caller));
        _getTPC().getActuator().clearTasks();
    };
    public shared(msg) func ictc_blockTO(_toid: TPCTM.Toid) : async ?TPCTM.Toid{
        assert(_onlyIctcAdmin(msg.caller));
        assert(not(_onlyBlocking(_toid)));
        let saga = _getTPC();
        return saga.block(_toid);
    };
    public shared(msg) func ictc_2PC_blockTO(_toid: TPCTM.Toid) : async ?TPCTM.Toid{
        assert(_onlyIctcAdmin(msg.caller));
        assert(not(_onlyBlocking(_toid)));
        let tpc = _getTPC();
        return tpc.block(_toid);
    };
    // public shared(msg) func ictc_2PC_removeTT(_toid: TPCTM.Toid, _ttid: TPCTM.Ttid) : async ?TPCTM.Ttid{ // Warning: Execute this method with caution
    //     assert(_onlyBlocking(_toid));
    //     let tpc = _getTPC();
    //     tpc.open(_toid);
    //     let ttid = tpc.remove(_toid, _ttid);
    //     tpc.close(_toid);
    //     return ttid;
    // };
    public shared(msg) func ictc_2PC_appendTT(_businessId: ?Blob, _toid: TPCTM.Toid, _forTtid: ?TPCTM.Ttid, _callee: Principal, _callType: CallType, _preTtids: [TPCTM.Ttid]) : async TPCTM.Ttid{
        // Governance or manual compensation (operation allowed only when a transaction order is in blocking status).
        assert(_onlyIctcAdmin(msg.caller));
        assert(_onlyBlocking(_toid)); 
        let tpc = _getTPC();
        tpc.open(_toid);
        let taskRequest = _buildTask(_businessId, _callee, _callType, _preTtids);
        //let ttid = tpc.append(_toid, taskRequest, null, null);
        let ttid = tpc.appendComp(_toid, Option.get(_forTtid, 0), taskRequest, null);
        return ttid;
    };
    /// Try the task again
    public shared(msg) func ictc_2PC_redoTT(_toid: TPCTM.Toid, _ttid: TPCTM.Ttid) : async ?TPCTM.Ttid{
        // Warning: proceed with caution!
        assert(_onlyIctcAdmin(msg.caller));
        let tpc = _getTPC();
        let ttid = tpc.redo(_toid, _ttid);
        try{
            let _r = await tpc.run(_toid);
        }catch(e){
            throw Error.reject("430: ICTC error: "# Error.message(e)); 
        };
        return ttid;
    };
    /// set status of pending task
    public shared(msg) func ictc_2PC_doneTT(_toid: TPCTM.Toid, _ttid: TPCTM.Ttid, _toCallback: Bool) : async ?TPCTM.Ttid{
        // Warning: proceed with caution!
        assert(_onlyIctcAdmin(msg.caller));
        let tpc = _getTPC();
        try{
            let ttid = await* tpc.taskDone(_toid, _ttid, _toCallback);
            return ttid;
        }catch(e){
            throw Error.reject("420: internal call error: "# Error.message(e)); 
        };
    };
    /// set status of pending order
    public shared(msg) func ictc_2PC_doneTO(_toid: TPCTM.Toid, _status: TPCTM.OrderStatus, _toCallback: Bool) : async Bool{
        // Warning: proceed with caution!
        assert(_onlyIctcAdmin(msg.caller));
        let tpc = _getTPC();
        tpc.close(_toid);
        try{
            let res = await* tpc.done(_toid, _status, _toCallback);
            return res;
        }catch(e){
            throw Error.reject("420: internal call error: "# Error.message(e)); 
        };
    };
    public shared(msg) func ictc_2PC_completeTO(_toid: TPCTM.Toid, _status: TPCTM.OrderStatus) : async Bool{
        // After governance or manual compensations, this method needs to be called to complete the transaction order.
        assert(_onlyIctcAdmin(msg.caller));
        assert(_onlyBlocking(_toid));
        let tpc = _getTPC();
        tpc.close(_toid);
        let _r = await tpc.run(_toid);
        return await* _getTPC().complete(_toid, _status);
    };
    public shared(msg) func ictc_2PC_runTO(_toid: TPCTM.Toid) : async ?TPCTM.OrderStatus{
        assert(_onlyIctcAdmin(msg.caller));
        let tpc = _getTPC();
        tpc.close(_toid);
        try{
            let r = await tpc.run(_toid);
            return r;
        }catch(e){
            throw Error.reject("430: ICTC error: "# Error.message(e)); 
        };
    };
    public shared(msg) func ictc_2PC_runTT() : async Bool{ 
        // There is no need to call it normally, but can be called if you want to execute tasks in time when a TO is in the Doing state.
        assert(_onlyIctcAdmin(msg.caller));
        let tpc = _getTPC();
        try{
            let _r = await tpc.run(0);
        }catch(e){
            throw Error.reject("430: ICTC error: "# Error.message(e)); 
        };
        return true;
    };
    /**
    * End: ICTC Transaction Explorer Interface
    */



    // upgrade
    private stable var __tpcDataNew: ?TPCTM.Data<CustomCallType> = null;
    system func preupgrade() {
        let data = _getTPC().getData();
        __tpcDataNew := ?data;
        // assert(List.size(data.actuator.tasks.0) == 0 and List.size(data.actuator.tasks.1) == 0);
    };
    system func postupgrade() {
        switch(__tpcDataNew){
            case(?(data)){
                _getTPC().setData(data);
                __tpcDataNew := null;
            };
            case(_){};
        };
    };

    
};