/**
 * Module     : ICTC Saga Test
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
import Error "mo:base/Error";
import CallType "../src/CallType";
import Principal "mo:base/Principal";
import TA "../src/TA";
import SagaTM "../src/SagaTM";

shared(installMsg) actor class Example() = this {
    type CallType = CallType.CallType;
    type TaskResult = CallType.TaskResult;
    private var tokenA_canister = Principal.fromText("ueghb-uqaaa-aaaak-aaioa-cai");
    private var tokenB_canister = Principal.fromText("udhbv-ziaaa-aaaak-aaioq-cai");
    private var x : Nat = 0;
    private func foo(count: Nat) : (){
        x += 100;
    };
    private func _local(_args: SagaTM.CallType, _receipt: ?SagaTM.Receipt) : (SagaTM.TaskResult){
        switch(_args){
            case(#This(method)){
                switch(method){
                    case(#foo(count)){
                        var result = foo(count); // Receipt
                        return (#Done, ?#This(#foo(result)), null);
                    };
                };
            };
            case(_){ return (#Error, null, ?{code=#future(9901); message="Non-local function."; });};
        };
    };
    private func _localAsync(_args: SagaTM.CallType, _receipt: ?SagaTM.Receipt) : async (SagaTM.TaskResult){
        switch(_args){
            case(#This(method)){
                switch(method){
                    case(#foo(count)){
                        var result = foo(count); // Receipt
                        return (#Done, ?#This(#foo(result)), null);
                    };
                };
            };
            case(_){ return (#Error, null, ?{code=#future(9901); message="Non-local function."; });};
        };
    };
    private func _taskCallback(_tid: SagaTM.Ttid, _task: SagaTM.Task, _result: SagaTM.TaskResult) : (){
        taskLogs := TA.arrayAppend(taskLogs, [(_tid, _task, _result)]);
    };
    private func _orderCallback(_oid: SagaTM.Toid, _status: SagaTM.OrderStatus, _data: ?Blob) : (){
        orderLogs := TA.arrayAppend(orderLogs, [(_oid, _status)]);
    };

    private stable var taskLogs: [(SagaTM.Ttid, SagaTM.Task, TaskResult)] = [];
    private stable var orderLogs: [(SagaTM.Toid, SagaTM.OrderStatus)] = [];
    private var saga: ?SagaTM.SagaTM = null;
    private func _getSaga() : SagaTM.SagaTM {
        switch(saga){
            case(?(_saga)){ return _saga };
            case(_){
                let _saga = SagaTM.SagaTM(Principal.fromActor(this), ?_local, ?_localAsync, ?_taskCallback, ?_orderCallback); //?_taskCallback, ?_orderCallback
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
        let act = TA.TA(50, 24*3600*1000000000, Principal.fromActor(this), _local, _localAsync, null, ?_taskCallback);
        var task = _task(tokenA_canister, #DRC20(#transfer(_account, 5000000000, null, null, null)), []);
        let tid1 = act.push(task);
        task := _task(tokenB_canister, #DRC20(#transfer(_account, 5000000000, null, null, null)), []);
        let tid2 = act.push(task);
        let f = act.run();
    };

    
    private func _buildTask(_businessId: ?Blob, _callee: Principal, _callType: SagaTM.CallType, _preTtid: [SagaTM.Ttid]) : SagaTM.PushTaskRequest{
        return {
            callee = _callee;
            callType = _callType;
            preTtid = _preTtid;
            attemptsMax = ?1;
            recallInterval = ?0; // nanoseconds
            cycles = 0;
            data = _businessId;
        };
    };
    private func _task(_callee: Principal, _callType: SagaTM.CallType, _preTtid: [SagaTM.Ttid]) : SagaTM.Task{
        return {
            callee = _callee;
            callType = _callType;
            preTtid = _preTtid;
            toid = null;
            forTtid = null;
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

        let oid = _getSaga().create("swap1", #Forward, null, null);
        var task = _buildTask(null, tokenA_canister, #DRC20(#transferFrom(caller, contract, valueA+tokenFee, null, null, null)), []);
        let tid1 =_getSaga().push(oid, task, null, null);
        task := _buildTask(null, tokenB_canister, #DRC20(#transferFrom(to, contract, valueB+tokenFee, null, null, null)), []);
        let tid2 =_getSaga().push(oid, task, null, null);
        task := _buildTask(null, Principal.fromActor(this), #This(#foo(1)), []);
        let tid3 =_getSaga().push(oid, task, null, null);
        task := _buildTask(null, tokenA_canister, #DRC20(#transfer(to, valueA, null, null, null)), []);
        let tid4 =_getSaga().push(oid, task, null, null);
        task := _buildTask(null, tokenB_canister, #DRC20(#transfer(caller, valueB, null, null, null)), []);
        let tid5 =_getSaga().push(oid, task, null, null);
        _getSaga().close(oid);
        let res = await _getSaga().run(oid);
        return (oid, res);
    };

//     The callee achieves internal task atomicity
// Caller takes a variety of ways to achieve eventual consistency, including 
// ** Retries 
// ** Automatic reversal task 
// ** Governance or manual reversal task
// Debit first, credit later principle (receive first, freezable txn first)
// Caller-led principle (the caller acts as coordinator)

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

        let oid = _getSaga().create("swap2", #Backward, null, null);
        var task = _buildTask(null, tokenA_canister, #DRC20(#transferFrom(caller, contract, valueA+tokenFee, null, null, null)), []);
        var comp = _buildTask(null, tokenA_canister, #DRC20(#transfer(caller, valueA, null, null, null)), []);
        let tid1 =_getSaga().push(oid, task, ?comp, null);
        task := _buildTask(null, tokenB_canister, #DRC20(#transferFrom(to, contract, valueB+tokenFee, null, null, null)), []);
        comp := _buildTask(null, tokenB_canister, #DRC20(#transfer(to, valueB, null, null, null)), []);
        let tid2 =_getSaga().push(oid, task, ?comp, null);
        task := _buildTask(null, Principal.fromActor(this), #This(#foo(1)), []);
        comp := _buildTask(null, Principal.fromActor(this), #__skip, []);
        let tid3 =_getSaga().push(oid, task, ?comp, null);
        task := _buildTask(null, tokenA_canister, #DRC20(#transfer(to, valueA, null, null, null)), []);
        let tid4 =_getSaga().push(oid, task, null, null);
        task := _buildTask(null, tokenB_canister, #DRC20(#transfer(caller, valueB, null, null, null)), []);
        let tid5 =_getSaga().push(oid, task, null, null);
        _getSaga().close(oid);
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

        let oid = _getSaga().create("swap3", #Backward, null, null);
        var task = _buildTask(null, tokenA_canister, #DRC20(#lockTransferFrom(caller, to, valueA, 100000, null, null, null, null)), []);
        var comp = _buildTask(null, tokenA_canister, #DRC20(#executeTransfer(#AutoFill, #fallback, null, null, null, null)), []);
        let tid1 =_getSaga().push(oid, task, ?comp, null);
        task := _buildTask(null, tokenB_canister, #DRC20(#lockTransferFrom(to, caller, valueB, 100000, null, null, null, null)), []);
        comp := _buildTask(null, tokenB_canister, #DRC20(#executeTransfer(#AutoFill, #fallback, null, null, null, null)), []);
        let tid2 =_getSaga().push(oid, task, ?comp, null);
        task := _buildTask(null, Principal.fromActor(this), #This(#foo(1)), []);
        comp := _buildTask(null, Principal.fromActor(this), #__skip, []);
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
        task := _buildTask(null, tokenA_canister, #DRC20(#executeTransfer(#ManualFill(txid1), #sendAll, null, null, null, null)), []);
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
        task := _buildTask(null, tokenB_canister, #DRC20(#executeTransfer(#ManualFill(txid2), #sendAll, null, null, null, null)), []);
        let tid5 =_getSaga().push(oid, task, null, null);
        _getSaga().close(oid);
        return (oid, await _getSaga().run(oid));
    };
    
    /**
    * ICTC Transaction Explorer Interface
    * (Optional) Implement the following interface, which allows you to browse transaction records and execute compensation transactions through a UI interface.
    * https://cmqwp-uiaaa-aaaaj-aihzq-cai.raw.ic0.app/
    */
    // ICTC: management functions
    private stable var ictc_admins: [Principal] = [];
    private func _onlyIctcAdmin(_caller: Principal) : Bool { 
        return Option.isSome(Array.find(ictc_admins, func (t: Principal): Bool{ t == _caller }));
    }; 
    private func _onlyBlocking(_toid: Nat) : Bool{
        /// Saga
        switch(_getSaga().status(_toid)){
            case(?(status)){ return status == #Blocking };
            case(_){ return false; };
        };
        /// 2PC
        // switch(_getTPC().status(_toid)){
        //     case(?(status)){ return status == #Blocking };
        //     case(_){ return false; };
        // };
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

    // SagaTM Scan
    public query func ictc_TM() : async Text{
        return "Saga";
    };
    /// Saga
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

    // Transaction Governance
    // public shared(msg) func ictc_clearTTPool() : async (){ // Warning: Execute this method with caution
    //     assert(_onlyIctcAdmin(msg.caller));
    //     _getSaga().getActuator().clearTasks();
    // };
    public shared(msg) func ictc_blockTO(_toid: SagaTM.Toid) : async ?SagaTM.Toid{
        assert(_onlyIctcAdmin(msg.caller));
        assert(not(_onlyBlocking(_toid)));
        let saga = _getSaga();
        return saga.block(_toid);
    };
    // public shared(msg) func ictc_removeTT(_toid: SagaTM.Toid, _ttid: SagaTM.Ttid) : async ?SagaTM.Ttid{ // Warning: Execute this method with caution
    //     assert(_onlyIctcAdmin(msg.caller));
    //     assert(_onlyBlocking(_toid));
    //     let saga = _getSaga();
    //     saga.open(_toid);
    //     let ttid = saga.remove(_toid, _ttid);
    //     saga.close(_toid);
    //     return ttid;
    // };
    public shared(msg) func ictc_appendTT(_businessId: ?Blob, _toid: SagaTM.Toid, _forTtid: ?SagaTM.Ttid, _callee: Principal, _callType: SagaTM.CallType, _preTtids: [SagaTM.Ttid]) : async SagaTM.Ttid{
        // Governance or manual compensation (operation allowed only when a transaction order is in blocking status).
        assert(_onlyIctcAdmin(msg.caller));
        assert(_onlyBlocking(_toid));
        let saga = _getSaga();
        saga.open(_toid);
        let taskRequest = _buildTask(_businessId, _callee, _callType, _preTtids);
        //let ttid = saga.append(_toid, taskRequest, null, null);
        let ttid = saga.appendComp(_toid, Option.get(_forTtid, 0), taskRequest, null);
        return ttid;
    };
    /// Try the task again
    public shared(msg) func ictc_redoTT(_toid: SagaTM.Toid, _ttid: SagaTM.Ttid) : async ?SagaTM.Ttid{
        // Warning: proceed with caution!
        assert(_onlyIctcAdmin(msg.caller));
        let saga = _getSaga();
        let ttid = saga.redo(_toid, _ttid);
        try{
            let r = await saga.run(_toid);
        }catch(e){
            throw Error.reject("430: ICTC error: "# Error.message(e)); 
        };
        return ttid;
    };
    /// set status of pending task
    public shared(msg) func ictc_doneTT(_toid: SagaTM.Toid, _ttid: SagaTM.Ttid, _toCallback: Bool) : async ?SagaTM.Ttid{
        // Warning: proceed with caution!
        assert(_onlyIctcAdmin(msg.caller));
        let saga = _getSaga();
        try{
            let ttid = await saga.taskDone(_toid, _ttid, _toCallback);
            return ttid;
        }catch(e){
            throw Error.reject("420: internal call error: "# Error.message(e)); 
        };
    };
    /// set status of pending order
    public shared(msg) func ictc_doneTO(_toid: SagaTM.Toid, _status: SagaTM.OrderStatus, _toCallback: Bool) : async Bool{
        // Warning: proceed with caution!
        assert(_onlyIctcAdmin(msg.caller));
        let saga = _getSaga();
        saga.close(_toid);
        try{
            let res = await saga.done(_toid, _status, _toCallback);
            return res;
        }catch(e){
            throw Error.reject("420: internal call error: "# Error.message(e)); 
        };
    };
    /// Complete blocking order
    public shared(msg) func ictc_completeTO(_toid: SagaTM.Toid, _status: SagaTM.OrderStatus) : async Bool{
        // After governance or manual compensations, this method needs to be called to complete the transaction order.
        assert(_onlyIctcAdmin(msg.caller));
        assert(_onlyBlocking(_toid));
        let saga = _getSaga();
        saga.close(_toid);
        try{
            let r = await saga.run(_toid);
        }catch(e){
            throw Error.reject("430: ICTC error: "# Error.message(e)); 
        };
        try{
            let r = await _getSaga().complete(_toid, _status);
            return r;
        }catch(e){
            throw Error.reject("430: ICTC error: "# Error.message(e)); 
        };
    };
    public shared(msg) func ictc_runTO(_toid: SagaTM.Toid) : async ?SagaTM.OrderStatus{
        assert(_onlyIctcAdmin(msg.caller));
        let saga = _getSaga();
        saga.close(_toid);
        try{
            let r = await saga.run(_toid);
            return r;
        }catch(e){
            throw Error.reject("430: ICTC error: "# Error.message(e)); 
        };
    };
    public shared(msg) func ictc_runTT() : async Bool{ 
        // There is no need to call it normally, but can be called if you want to execute tasks in time when a TO is in the Doing state.
        assert(_onlyIctcAdmin(msg.caller));
        let saga = _getSaga();
        try{
            let r = await saga.run(0);
        }catch(e){
            throw Error.reject("430: ICTC error: "# Error.message(e)); 
        };
        return true;
    };
    /**
    * End: ICTC Transaction Explorer Interface
    */



    // upgrade
    /// Saga
    private stable var __sagaDataNew: ?SagaTM.Data = null;
    system func preupgrade() {
        let data = _getSaga().getData();
        __sagaDataNew := ?data;
        // assert(List.size(data.actuator.tasks.0) == 0 and List.size(data.actuator.tasks.1) == 0);
    };
    system func postupgrade() {
        switch(__sagaDataNew){
            case(?(data)){
                _getSaga().setData(data);
                __sagaDataNew := null;
            };
            case(_){};
        };
    };

    
};