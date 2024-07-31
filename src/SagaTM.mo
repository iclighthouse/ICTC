/**
 * Module     : SagaTM.mo v3.0
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Description: ICTC Saga Transaction Manager.
 * Refers     : https://github.com/iclighthouse/ICTC
 */

import Nat "mo:base/Nat";
import Array "mo:base/Array";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Iter "mo:base/Iter";
import List "mo:base/List";
import TrieMap "mo:base/TrieMap";
import TA "./TA";
import Error "mo:base/Error";

module {
    public let Version: Nat = 10;
    public type Toid = Nat;
    public type Ttid = TA.Ttid;
    public type Tcid = TA.Ttid;
    public type Callee = TA.Callee;
    public type CallType<T> = TA.CallType<T>;
    public type Receipt = TA.Receipt;
    public type Task<T> = TA.Task<T>;
    public type Status = TA.Status;
    public type TaskCallback<T> = TA.TaskCallback<T>;
    public type CustomCall<T> = TA.CustomCall<T>;
    public type TaskResult = TA.TaskResult;
    public type TaskEvent<T> = TA.TaskEvent<T>;
    public type ErrorLog = TA.ErrorLog;
    public type CalleeStatus = TA.CalleeStatus;
    public type Settings = {attemptsMax: ?TA.Attempts; recallInterval: ?Int; data: ?Blob};
    public type OrderStatus = {#Todo; #Doing; #Compensating; #Blocking; #Done; #Recovered;};
    public type Compensation<T> = Task<T>;
    public type CompStrategy = { #Forward; #Backward; };
    public type OrderCallback = (_toName: Text, _toid: Toid, _status: OrderStatus, _data: ?Blob) -> async ();
    public type PushTaskRequest<T> = {
        callee: Callee;
        callType: CallType<T>;
        preTtid: [Ttid];
        attemptsMax: ?Nat;
        recallInterval: ?Int; // nanoseconds
        cycles: Nat;
        data: ?Blob;
    };
    public type PushCompRequest<T> = PushTaskRequest<T>;
    public type SagaTask<T> = {
        ttid: Ttid;
        task: Task<T>;
        comp: ?Compensation<T>; // for auto compensation
        status: Status;
    };
    public type CompTask<T> = {
        forTtid: Ttid;
        tcid: Tcid;
        comp: Compensation<T>;
        status: Status;
    };
    public type Order<T> = {
        name: Text;
        compStrategy: CompStrategy;
        tasks: List.List<SagaTask<T>>;
        allowPushing: {#Opening; #Closed;};
        comps: List.List<CompTask<T>>;
        status: OrderStatus;  // *
        callbackStatus: ?Status;
        time: Time.Time;
        data: ?Blob;
    };
    public type Data<T> = {
        autoClearTimeout: Int; 
        index: Nat; 
        firstIndex: Nat; 
        orders: [(Toid, Order<T>)]; 
        aliveOrders: List.List<(Toid, Time.Time)>; 
        taskEvents: [(Toid, [Ttid])];
        actuator: TA.Data<T>; 
    };

    /// ## Transaction Manager for Saga mode.
    /// - Transaction Order: is a complete transaction containing one or more tasks.
    /// - Transaction Task: is a task within a transaction that is required to be data consistent internally (atomicity) and 
    /// preferably acceptable for multiple attempts without repeated execution (idempotence).
    public class SagaTM<T>(this: Principal, call: ?CustomCall<T>, defaultTaskCallback: ?TaskCallback<T>, defaultOrderCallback: ?OrderCallback) {
        let limitAtOnce: Nat = 500;
        var autoClearTimeout: Int = 3*30*24*3600*1000000000; // 3 months
        var index: Toid = 1;
        var firstIndex: Toid = 1;
        var orders = TrieMap.TrieMap<Toid, Order<T>>(Nat.equal, TA.natHash);
        var aliveOrders = List.nil<(Toid, Time.Time)>();
        var taskEvents = TrieMap.TrieMap<Toid, [Ttid]>(Nat.equal, TA.natHash);
        var actuator_: ?TA.TA<T> = null;
        var taskCallback = TrieMap.TrieMap<Ttid, TaskCallback<T>>(Nat.equal, TA.natHash); /*fix*/
        var orderCallback = TrieMap.TrieMap<Toid, OrderCallback>(Nat.equal, TA.natHash);
        var countAsyncMessage : Nat = 0;

        private func actuator() : TA.TA<T> {
            switch(actuator_){
                case(?(_actuator)){ return _actuator; };
                case(_){
                    let call_ = Option.get(call, func (_callee: Principal, _cycles: Nat, _ct: CallType<T>, _r: ?Receipt): async (TaskResult){ (#Error, null, ?{code = #future(9902); message = "No custom calling function proxy specified"; }) });
                    let act = TA.TA<T>(limitAtOnce, autoClearTimeout, call_, ?_taskCallbackProxy, null);
                    actuator_ := ?act;
                    return act;
                };
            };
        };

        // Unique callback entrance. This function will call each specified callback of task
        private func _taskCallbackProxy(_ttid: Ttid, _task: Task<T>, _result: TaskResult) : async* (){
            let toid = Option.get(_task.toid, 0);
            switch(_status(toid)){
                case(?(#Todo)){ _setStatus(toid, #Doing); };
                case(_){};
            };
            var orderStatus : OrderStatus = #Todo;
            var strategy: CompStrategy = #Backward;
            var isClosed : Bool = false;
            var toName : Text = "";
            switch(orders.get(toid)){
                case(?(order)){ 
                    orderStatus := order.status;
                    strategy := order.compStrategy; 
                    isClosed := order.allowPushing == #Closed;
                    toName := order.name;
                };
                case(_){};
            };
            // task status
            ignore _setTaskStatus(toid, _ttid, _result.0);
            // task callback
            var callbackDone : Bool = false;
            switch(taskCallback.get(_ttid)){
                case(?(_taskCallback)){ 
                    try{
                        countAsyncMessage += 2;
                        await _taskCallback(toName, _ttid, _task, _result); 
                        countAsyncMessage -= Nat.min(2, countAsyncMessage); 
                        taskCallback.delete(_ttid);
                        callbackDone := true;
                    } catch(e){
                        callbackDone := false;
                        countAsyncMessage -= Nat.min(2, countAsyncMessage);
                    };
                };
                case(_){
                    switch(defaultTaskCallback){
                        case(?(_taskCallback)){
                            try{
                                countAsyncMessage += 2;
                                await _taskCallback(toName, _ttid, _task, _result);
                                countAsyncMessage -= Nat.min(2, countAsyncMessage);
                                callbackDone := true;
                            }catch(e){
                                callbackDone := false;
                                countAsyncMessage -= Nat.min(2, countAsyncMessage);
                            };
                        };
                        case(_){ callbackDone := true; };
                    };
                };
            };
            // process
            if (orderStatus == #Compensating){ //Compensating
                if (_result.0 == #Done and isClosed and Option.get(_orderLastCid(toid), 0) == _ttid){ 
                    _setStatus(toid, #Recovered);
                    var callbackStatus : ?Status = null;
                    try{ 
                        callbackStatus := await* _orderComplete(toid); 
                        aliveOrders := List.filter(aliveOrders, func (item:(Toid, Time.Time)): Bool{ item.0 != toid });
                    }catch(e){ 
                        callbackStatus := ?#Error; 
                        _setStatus(toid, #Blocking);
                    };
                    _setCallbackStatus(toid, callbackStatus);
                    //await _orderComplete(toid, #Recovered);
                    _removeTATaskByOid(toid);
                }else if (_result.0 == #Error or _result.0 == #Unknown or not(callbackDone)){ //Blocking
                    _setStatus(toid, #Blocking);
                };
            } else if (orderStatus == #Doing){ //Doing 
                if (_result.0 == #Done and isClosed and Option.get(_orderLastTid(toid), 0) == _ttid){ // Done
                    _setStatus(toid, #Done);
                    var callbackStatus : ?Status = null;
                    try{ 
                        callbackStatus := await* _orderComplete(toid); 
                        aliveOrders := List.filter(aliveOrders, func (item:(Toid, Time.Time)): Bool{ item.0 != toid });
                    }catch(e){ 
                        callbackStatus := ?#Error; 
                        _setStatus(toid, #Blocking);
                    };
                    _setCallbackStatus(toid, callbackStatus);
                    //await _orderComplete(toid, #Done);
                }else if (_result.0 == #Error and strategy == #Backward){ // recovery
                    _setStatus(toid, #Compensating);
                    _compensate(toid, _ttid);
                }else if (_result.0 == #Error or _result.0 == #Unknown or not(callbackDone)){ //Blocking
                    _setStatus(toid, #Blocking);
                };
            } else { // Blocking
                //
            };
            //taskEvents
            switch(taskEvents.get(toid)){
                case(?(events)){
                    taskEvents.put(toid, TA.arrayAppend(events, [_ttid]));
                };
                case(_){
                    taskEvents.put(toid, [_ttid]);
                };
            };
            //return
            if (not(callbackDone)){
                throw Error.reject("Task Callback Error.");
            };
        };


        // private functions
        private func _inOrders(_toid: Toid): Bool{
            return Option.isSome(orders.get(_toid));
        };
        private func _inAliveOrders(_toid: Toid): Bool{
            return Option.isSome(List.find(aliveOrders, func (item: (Toid, Time.Time)): Bool{ item.0 == _toid }));
        };
        private func _pushOrder(_toid: Toid, _order: Order<T>): (){
            orders.put(_toid, _order);
            _clear(null, false);
        };
        private func _clear(_expiration: ?Int, _delForced: Bool) : (){
            var clearTimeout: Int = Option.get(_expiration, 0);
            if (clearTimeout == 0 and autoClearTimeout > 0){
                clearTimeout := autoClearTimeout;
            }else if(clearTimeout == 0){
                return ();
            };
            var completed: Bool = false;
            var moveFirstPointer: Bool = true;
            var i: Nat = firstIndex;
            while (i < index and not(completed)){
                switch(orders.get(i)){
                    case(?(order)){
                        if (Time.now() > order.time + clearTimeout and (_delForced or order.status == #Done or order.status == #Recovered)){
                            _deleteOrder(i); // delete the record.
                            i += 1;
                        }else if (Time.now() > order.time + clearTimeout){
                            i += 1;
                            moveFirstPointer := false;
                        }else{
                            moveFirstPointer := false;
                            completed := true;
                        };
                    };
                    case(_){
                        i += 1;
                    };
                };
                if (moveFirstPointer) { firstIndex += 1; };
            };
        };
        private func _deleteOrder(_toid: Toid) : (){
            switch(orders.get(_toid)){
                case(?(order)){
                    orders.delete(_toid);
                    taskEvents.delete(_toid);
                };
                case(_){};
            };
        };

        private func _taskFromRequest(_toid: Toid, _task: PushTaskRequest<T>, _autoAddPreTtid: Bool) : TA.Task<T>{
            var preTtid = _task.preTtid;
            let lastTtid = Option.get(_orderLastTid(_toid), 0);
            if (_autoAddPreTtid and Option.isNull(Array.find(preTtid, func (ttid:Ttid):Bool{ttid == lastTtid})) and lastTtid > 0){
                preTtid := TA.arrayAppend(preTtid, [lastTtid]);
            };
            return {
                callee = _task.callee; 
                callType = _task.callType; 
                preTtid = preTtid; 
                toid = ?_toid; 
                forTtid = null;
                attemptsMax = Option.get(_task.attemptsMax, 1); 
                recallInterval = Option.get(_task.recallInterval, 0); 
                cycles = _task.cycles;
                data = _task.data;
                time = Time.now();
            };
        };
        private func _compFromRequest(_toid: Toid, _forTtid: ?Ttid, _comp: ?PushCompRequest<T>) : ?Compensation<T>{
            var comp: ?Compensation<T> = null;
            switch(_comp){
                case(?(compensation)){
                    comp := ?{
                        callee = compensation.callee; 
                        callType = compensation.callType; 
                        preTtid = []; 
                        toid = ?_toid; 
                        forTtid = _forTtid;
                        attemptsMax = Option.get(compensation.attemptsMax, 1); 
                        recallInterval = Option.get(compensation.recallInterval, 0); 
                        cycles = compensation.cycles;
                        data = compensation.data;
                        time = Time.now();
                    }; 
                };
                case(_){};
            };
            return comp;
        };
        private func _orderLastTid(_toid: Toid) : ?Ttid{
            switch(orders.get(_toid)){
                case(?(order)){
                    switch(List.pop(order.tasks)){
                        case((?(task), ts)){
                            return ?task.ttid;
                        };
                        case(_){ return null; };
                    };
                };
                case(_){ return null; };
            };
        };
        private func _putTask(_toid: Toid, _sagaTask: SagaTask<T>) : (){
            switch(orders.get(_toid)){
                case(?(order)){
                    assert(order.allowPushing == #Opening);
                    let tasks = List.push(_sagaTask, order.tasks);
                    let orderNew = {
                        name = order.name;
                        compStrategy = order.compStrategy;
                        tasks = tasks;
                        allowPushing = order.allowPushing;
                        comps = order.comps;
                        status = order.status;
                        callbackStatus = order.callbackStatus;
                        time = order.time;
                        data = order.data;
                    };
                    orders.put(_toid, orderNew);
                };
                case(_){};
            };
            if (_toid > 0 and not(_inAliveOrders(_toid))){
                aliveOrders := List.push((_toid, Time.now()), aliveOrders);
            };
        };
        private func _updateTask(_toid: Toid, _sagaTask: SagaTask<T>) : (){
            switch(orders.get(_toid)){
                case(?(order)){
                    let tasks = List.map(order.tasks, func (t:SagaTask<T>):SagaTask<T>{
                        if (t.ttid == _sagaTask.ttid){ _sagaTask } else { t };
                    });
                    let orderNew = {
                        name = order.name;
                        compStrategy = order.compStrategy;
                        tasks = tasks;
                        allowPushing = order.allowPushing;
                        comps = order.comps;
                        status = order.status;
                        callbackStatus = order.callbackStatus;
                        time = order.time;
                        data = order.data;
                    };
                    orders.put(_toid, orderNew);
                };
                case(_){};
            };
            if (_toid > 0 and not(_inAliveOrders(_toid))){
                aliveOrders := List.push((_toid, Time.now()), aliveOrders);
            };
        };
        private func _removeTask(_toid: Toid, _ttid: Ttid) : (){
            switch(orders.get(_toid)){
                case(?(order)){
                    let tasks = List.filter(order.tasks, func (t:SagaTask<T>): Bool{ t.ttid != _ttid });
                    let orderNew = {
                        name = order.name;
                        compStrategy = order.compStrategy;
                        tasks = tasks;
                        allowPushing = order.allowPushing;
                        comps = order.comps;
                        status = order.status;
                        callbackStatus = order.callbackStatus;
                        time = order.time;
                        data = order.data;
                    };
                    orders.put(_toid, orderNew);
                };
                case(_){};
            };
        };

        private func _removeTATaskByOid(_toid: Toid) : (){
            ignore actuator().removeByOid(_toid);
            switch(orders.get(_toid)){
                case(?(order)){
                    for (task in List.toArray(order.tasks).vals()){ 
                        taskCallback.delete(task.ttid);
                    };
                    for (task in List.toArray(order.comps).vals()){ 
                        taskCallback.delete(task.tcid);
                    };
                };
                case(_){};
            };
        };

        private func _isOpening(_toid: Toid) : Bool{
            switch(orders.get(_toid)){
                case(?(order)){ return order.allowPushing == #Opening };
                case(_){ return false; };
            };
        };
        private func _allowPushing(_toid: Toid, _setting: {#Opening; #Closed; }) : (){
            switch(orders.get(_toid)){
                case(?(order)){
                    let orderNew = {
                        name = order.name;
                        compStrategy = order.compStrategy;
                        tasks = order.tasks;
                        allowPushing = _setting;
                        comps = order.comps;
                        status = order.status;
                        callbackStatus = order.callbackStatus;
                        time = order.time;
                        data = order.data;
                    };
                    orders.put(_toid, orderNew);
                };
                case(_){};
            };
        };
        private func _status(_toid: Toid) : ?OrderStatus{
            switch(orders.get(_toid)){
                case(?(order)){
                    return ?order.status;
                };
                case(_){ return null; };
            };
        };
        private func _statusEqual(_toid: Toid, _status: OrderStatus) : Bool{
            switch(orders.get(_toid)){
                case(?(order)){
                    return order.status == _status;
                };
                case(_){ return false; };
            };
        };
        // Set the status of TO to #Done. If an error occurs and cannot be caught, the status of TO is #Doing
        private func _orderComplete(_toid: Toid) : async* ?Status{
            var callbackStatus : ?Status = null;
            switch(orders.get(_toid)){
                case(?(order)){
                    for (task in List.toArray(order.tasks).vals()){ 
                        taskCallback.delete(task.ttid);
                    };
                    for (comp in List.toArray(order.comps).vals()){ 
                        taskCallback.delete(comp.tcid);
                    };
                    //try{ 
                        switch(orderCallback.get(_toid)){
                            case(?(_orderCallback)){ 
                                try{
                                    countAsyncMessage += 2;
                                    await _orderCallback(order.name, _toid, order.status, order.data); 
                                    countAsyncMessage -= Nat.min(2, countAsyncMessage);
                                    orderCallback.delete(_toid);
                                    callbackStatus := ?#Done;
                                }catch(e){
                                    callbackStatus := ?#Error;
                                    countAsyncMessage -= Nat.min(2, countAsyncMessage);
                                };
                            };
                            case(_){
                                switch(defaultOrderCallback){
                                    case(?(_orderCallback)){
                                        try{
                                            countAsyncMessage += 2;
                                            await _orderCallback(order.name, _toid, order.status, order.data); 
                                            countAsyncMessage -= Nat.min(2, countAsyncMessage);
                                            callbackStatus := ?#Done;
                                        }catch(e){
                                            callbackStatus := ?#Error;
                                            countAsyncMessage -= Nat.min(2, countAsyncMessage);
                                        };
                                    };
                                    case(_){};
                                };
                            };
                        };
                    // } catch(e) {
                    //     callbackStatus := ?#Error;
                    // };
                };
                case(_){};
            };
            return callbackStatus;
        };
        private func _getTtids(_toid: Toid): [Ttid]{
            var res : [Ttid] = [];
            switch(orders.get(_toid)){
                case(?(order)){
                    for (task in List.toArray(order.tasks).vals()){ 
                        res := TA.arrayAppend(res, [task.ttid]);
                    };
                    for (comp in List.toArray(order.comps).vals()){ 
                        res := TA.arrayAppend(res, [comp.tcid]);
                    };
                };
                case(_){};
            };
            return res;
        };
        private func _setStatus(_toid: Toid, _setting: OrderStatus) : (){
            switch(orders.get(_toid)){
                case(?(order)){
                    let orderNew = {
                        name = order.name;
                        compStrategy = order.compStrategy;
                        tasks = order.tasks;
                        allowPushing = order.allowPushing;
                        comps = order.comps;
                        status = _setting;
                        callbackStatus = order.callbackStatus;
                        time = order.time;
                        data = order.data;
                    };
                    orders.put(_toid, orderNew);
                };
                case(_){};
            };
        };
        private func _setCallbackStatus(_toid: Toid, _setting: ?Status) : (){
            switch(orders.get(_toid)){
                case(?(order)){
                    let orderNew = {
                        name = order.name;
                        compStrategy = order.compStrategy;
                        tasks = order.tasks;
                        allowPushing = order.allowPushing;
                        comps = order.comps;
                        status = order.status;
                        callbackStatus = _setting;
                        time = order.time;
                        data = order.data;
                    };
                    orders.put(_toid, orderNew);
                };
                case(_){};
            };
        };
        private func _isTasksDone(_toid: Toid) : Bool{
            switch(orders.get(_toid)){
                case(?(order)){
                    switch(List.pop(order.tasks)){
                        case((?(task), ts)){
                            return actuator().isCompleted(task.ttid);
                        };
                        case(_){ return true; };
                    };
                };
                case(_){ return false; };
            };
        };
        private func _isCompsDone(_toid: Toid) : Bool{
            switch(orders.get(_toid)){
                case(?(order)){
                    switch(List.pop(order.comps)){
                        case((?(task), ts)){
                            return actuator().isCompleted(task.tcid);
                        };
                        case(_){ return false; };
                    };
                };
                case(_){ return false; };
            };
        };
        private func _statusTest(_toid: Toid) : async* (){
            switch(orders.get(_toid)){
                case(?(order)){
                    if (order.status == #Doing and order.allowPushing == #Closed and _isTasksDone(_toid)){
                        _setStatus(_toid, #Done);
                        var callbackStatus : ?Status = null;
                        try{ 
                            callbackStatus := await* _orderComplete(_toid); 
                            aliveOrders := List.filter(aliveOrders, func (item:(Toid, Time.Time)): Bool{ item.0 != _toid });
                        }catch(e){ 
                            callbackStatus := ?#Error; 
                            _setStatus(_toid, #Blocking);
                        };
                        _setCallbackStatus(_toid, callbackStatus);
                        //await _orderComplete(_toid, #Done);
                    } else if (order.status == #Compensating and order.allowPushing == #Closed and (_isCompsDone(_toid) or List.size(order.comps) == 0)){
                        _setStatus(_toid, #Recovered);
                        var callbackStatus : ?Status = null;
                        try{ 
                            callbackStatus := await* _orderComplete(_toid); 
                            aliveOrders := List.filter(aliveOrders, func (item:(Toid, Time.Time)): Bool{ item.0 != _toid });
                        }catch(e){ 
                            callbackStatus := ?#Error; 
                            _setStatus(_toid, #Blocking);
                        };
                        _setCallbackStatus(_toid, callbackStatus);
                        //await _orderComplete(_toid, #Recovered);
                        _removeTATaskByOid(_toid);
                    } else if (order.status == #Blocking and order.allowPushing == #Closed and _isTasksDone(_toid)){
                        // await _orderComplete(_toid, #Done);
                        // _removeTATaskByOid(_toid);
                    } else if (order.status == #Done or order.status == #Recovered){
                        aliveOrders := List.filter(aliveOrders, func (item:(Toid, Time.Time)): Bool{ item.0 != _toid });
                    };
                };
                case(_){
                    aliveOrders := List.filter(aliveOrders, func (item:(Toid, Time.Time)): Bool{ item.0 != _toid });
                };
            };
        };
        private func _orderLastCid(_toid: Toid) : ?Tcid{
            switch(orders.get(_toid)){
                case(?(order)){
                    switch(List.pop(order.comps)){
                        case((?(comp), ts)){
                            return ?comp.tcid;
                        };
                        case(_){ return null; };
                    };
                };
                case(_){ return null; };
            };
        };
        private func _pushComp(_toid: Toid, _ttid: Ttid, _comp: Compensation<T>, _preTtid: ?[Ttid]) : Tcid{
            if (not(_inOrders(_toid))){ return 0; };
            let preTtid = Option.get(_orderLastCid(_toid), 0);
            let task: Task<T> = {
                callee = _comp.callee;
                callType = _comp.callType;
                preTtid = Option.get(_preTtid, [preTtid]);
                toid = _comp.toid;
                forTtid = ?_ttid;
                attemptsMax = _comp.attemptsMax;
                recallInterval = _comp.recallInterval;
                cycles = _comp.cycles;
                data = _comp.data;
                time = Time.now();
            };
            let cid = actuator().push(task);
            let compTask: CompTask<T> = {
                forTtid = _ttid;
                tcid = cid;
                comp = task;
                status = #Todo; //Todo
            };
            switch(orders.get(_toid)){
                case(?(order)){
                    let comps = List.push(compTask, order.comps);
                    let orderNew = {
                        name = order.name;
                        compStrategy = order.compStrategy;
                        tasks = order.tasks;
                        allowPushing = order.allowPushing;
                        comps = comps;
                        status = order.status;
                        callbackStatus = order.callbackStatus;
                        time = order.time;
                        data = order.data;
                    };
                    orders.put(_toid, orderNew);
                };
                case(_){};
            };
            return cid;
        };
        private func _compensate(_toid: Toid, _errTask: Ttid) : (){
            switch(orders.get(_toid)){
                case(?(order)){
                    var tasks = order.tasks;
                    var item = List.pop(tasks);
                    while(Option.isSome(item.0)){
                        tasks := item.1;
                        switch(item.0){
                            case(?(task)){
                                if (task.ttid < _errTask){
                                    switch(task.comp){
                                        case(?(comp)){
                                            ignore _pushComp(_toid, task.ttid, comp, null);
                                        };
                                        case(_){ // to block
                                            let comp: Compensation<T> = {
                                                callee = task.task.callee;
                                                callType = #__block;
                                                preTtid = [];
                                                toid = ?_toid;
                                                forTtid = ?task.ttid;
                                                attemptsMax = 1;
                                                recallInterval = 0; // nanoseconds
                                                cycles = 0;
                                                data = null;
                                                time = Time.now();
                                            };
                                            ignore _pushComp(_toid, task.ttid, comp, null);
                                        };
                                    };
                                };
                            };
                            case(_){};
                        };
                        item := List.pop(tasks);
                    };
                };
                case(_){};
            };
        };
        private func _setTaskStatus(_toid: Toid, _ttid: Ttid, _status: Status) : Bool{
            var res : Bool = false;
            switch(orders.get(_toid)){
                case(?(order)){
                    var tasks = order.tasks;
                    var comps = order.comps;
                    tasks := List.map(tasks, func (t:SagaTask<T>): SagaTask<T>{
                        if (t.ttid == _ttid){
                            res := true;
                            return {
                                ttid = t.ttid;
                                task = t.task;
                                comp = t.comp;
                                status = _status;
                            };
                        } else { return t; };
                    });
                    comps := List.map(comps, func (t:CompTask<T>): CompTask<T>{
                        if (t.tcid == _ttid){
                            res := true;
                            return {
                                forTtid = t.forTtid;
                                tcid = t.tcid;
                                comp = t.comp;
                                status = _status;
                            };
                        } else { return t; };
                    });
                    let orderNew : Order<T> = {
                        name = order.name;
                        compStrategy = order.compStrategy;
                        tasks = tasks;
                        allowPushing = order.allowPushing;
                        comps = comps;
                        status = order.status;
                        callbackStatus = order.callbackStatus;
                        time = order.time;
                        data = order.data;
                    };
                    orders.put(_toid, orderNew);
                };
                case(_){};
            };
            return res;
        };
        private func __push(_toid: Toid, _task: PushTaskRequest<T>, _comp: ?PushCompRequest<T>, _autoAddPreTtid: Bool) : Ttid{
            assert(_inOrders(_toid) and _isOpening(_toid));
            let task: TA.Task<T> = _taskFromRequest(_toid, _task, _autoAddPreTtid);
            let tid = actuator().push(task);
            let comp = _compFromRequest(_toid, ?tid, _comp);
            let sagaTask: SagaTask<T> = {
                ttid = tid;
                task = task;
                comp = comp;
                status = #Todo; //Todo
            };
            _putTask(_toid, sagaTask);
            return tid;
        };

        // The following methods are used for transaction order operations.

        /// Create a transaction order and return the transaction ID (toid)
        public func create(_name: Text, _compStrategy: CompStrategy, _data: ?Blob, _callback: ?OrderCallback) : Toid{
            assert(this != Principal.fromText("aaaaa-aa"));
            let toid = index;
            index += 1;
            let order: Order<T> = {
                name = _name;
                compStrategy = _compStrategy;
                tasks = List.nil<SagaTask<T>>();
                allowPushing = #Opening;
                comps = List.nil<CompTask<T>>();
                progress = #Completed(0);
                status = #Todo;
                callbackStatus = null;
                time = Time.now();
                data = _data;
            };
            _pushOrder(toid, order);
            switch(_callback){
                case(?(callback)){ orderCallback.put(toid, callback); };
                case(_){};
            };
            return toid;
        };

        /// Pushes a task to a specified transaction order.
        public func push(_toid: Toid, _task: PushTaskRequest<T>, _comp: ?PushCompRequest<T>, _callback: ?TaskCallback<T>) : Ttid{
            let ttid = __push(_toid, _task, _comp, true);
            switch(_callback){
                case(?(callback)){ taskCallback.put(ttid, callback); };
                case(_){};
            };
            return ttid;
        };

        /// Sets the status of a task to #Done. requires that the transaction order the task is in is not complete and is in #Todo, 
        /// #Doing, or #Blocking.  
        public func taskDone(_toid: Toid, _ttid: Ttid, _toCallback: Bool) : async* ?Ttid{
            if (_inAliveOrders(_toid) and not(actuator().isInPool(_ttid)) and not(actuator().isCompleted(_ttid))){
                switch(orders.get(_toid)){
                    case(?(order)){
                        if ((order.status == #Todo or order.status == #Doing or order.status == #Blocking) and not(_isTasksDone(_toid))){
                            try{
                                let res = await* actuator().done(_ttid, _toCallback);
                                return res;
                            }catch(e){ 
                                return null;
                            };
                        };
                    };
                    case(_){};
                };
            };
            return null;
        };

        /// task redo
        public func redo(_toid: Toid, _ttid: Ttid) : ?Ttid{ // Warning: proceed with caution!
            if (_inAliveOrders(_toid) and not(actuator().isInPool(_ttid)) and not(actuator().isCompleted(_ttid))){
                switch(orders.get(_toid)){
                    case(?(order)){
                        if ((order.status == #Todo or order.status == #Doing or order.status == #Blocking) and not(_isTasksDone(_toid))){
                            //var taskStatus : Status = #Unknown;
                            var task_ : ?Task<T> = null;
                            switch(List.find(order.tasks, func (t:SagaTask<T>): Bool{ t.ttid == _ttid })){
                                case(?(sagaTask)){ task_ := ?sagaTask.task; };
                                case(_){};
                            };
                            switch(List.find(order.comps, func (t:CompTask<T>): Bool{ t.tcid == _ttid })){
                                case(?(compTask)){ task_ := ?compTask.comp; };
                                case(_){};
                            };
                            switch(task_){
                                case(?(task)){
                                    return ?(actuator().update(_ttid, task));
                                };
                                case(_){};
                            };
                        } else{};
                    };
                    case(_){};
                };
            };
            return null;
        };
        public func open(_toid: Toid) : (){
            _allowPushing(_toid, #Opening);
        };
        public func close(_toid: Toid) : (){
            _allowPushing(_toid, #Closed);
        };
        // @deprecated : It will be deprecated
        public func finish(_toid: Toid) : (){ 
            close(_toid);
        };
        // public func isEmpty(_toid: Toid) : Bool{
        //     switch(orders.get(_toid)){
        //         case(?(order)){ List.size(order.tasks) == 0 };
        //         case(_){ true };
        //     };
        // };
        public func run(_toid: Toid) : async ?OrderStatus{ 
            switch(_status(_toid)){
                case(?(#Todo)){ _setStatus(_toid, #Doing); };
                case(_){};
            };
            let actuations = actuator().actuations();
            if (actuations.actuationThreads < 5 or Time.now() > actuations.lastActuationTime + 60*1000000000){ // 60s
                try{ 
                    ignore await* actuator().run(); 
                }catch(e){};
            };
            if (_toid > 0){
                try{
                    await* _statusTest(_toid);
                }catch(e){};
            };
            return _status(_toid);
        };
        public func runSync(_toid: Toid) : async ?OrderStatus{ 
            switch(_status(_toid)){
                case(?(#Todo)){ _setStatus(_toid, #Doing); };
                case(_){};
            };
            let actuations = actuator().actuations();
            if (actuations.actuationThreads > 10){
                throw Error.reject("ICTC execution threads exceeded the limit.");
            };
            ignore await* actuator().runSync(if (_toid > 0) { ?_getTtids(_toid) } else { null }); 
            if (_toid > 0){
                try{ await* _statusTest(_toid); }catch(e){};
            };
            return _status(_toid);
        };

        // The following methods are used for queries.
        public func asyncMessageSize() : Nat{
            return countAsyncMessage + actuator().actuations().countAsyncMessage;
        };
        public func count() : Nat{
            return index - 1;
        };
        public func status(_toid: Toid) : ?OrderStatus{
            return _status(_toid);
        };
        public func isCompleted(_toid: Toid) : Bool{
            return _statusEqual(_toid, #Done);
        };
        public func isTaskCompleted(_ttid: Ttid) : Bool{
            return actuator().isCompleted(_ttid);
        };
        public func getOrder(_toid: Toid) : ?Order<T>{
            return orders.get(_toid);
        };
        public func getOrders(_page: Nat, _size: Nat) : {data: [(Toid, Order<T>)]; totalPage: Nat; total: Nat}{
            return TA.getTM<Order<T>>(orders, index, firstIndex, _page, _size);
        };
        public func getAliveOrders() : [(Toid, ?Order<T>)]{
            return Array.map<(Toid, Time.Time), (Toid, ?Order<T>)>(List.toArray(aliveOrders), 
                func (item:(Toid, Time.Time)):(Toid, ?Order<T>) { 
                    return (item.0, orders.get(item.0));
                });
        };
        public func getBlockingOrders() : [(Toid, Order<T>)]{
            return Array.mapFilter<(Toid, Time.Time), (Toid, Order<T>)>(List.toArray(aliveOrders), 
                func (item:(Toid, Time.Time)): ?(Toid, Order<T>) { 
                    switch(orders.get(item.0)){
                        case(?order){
                            if (order.status == #Blocking){
                                return ?(item.0, order);
                            }else{
                                return null;
                            };
                        };
                        case(_){ return null };
                    };
                });
        };
        public func getTaskEvents(_toid: Toid) : [TaskEvent<T>]{
            var events: [TaskEvent<T>] = [];
            for (tid in Option.get(taskEvents.get(_toid), []).vals()){
                let event_ =  actuator().getTaskEvent(tid);
                switch(event_){
                    case(?(event)) { events := TA.arrayAppend(events, [event]); };
                    case(_){};
                };
            };
            return events;
        };
        // public func getTaskEvent(_ttid: Ttid) : ?TaskEvent{
        //     return actuator().getTaskEvent(_ttid);
        // };
        // public func getAllEvents(_page: Nat, _size: Nat) : {data: [(Tid, TaskEvent)]; totalPage: Nat; total: Nat}{ 
        //     return actuator().getTaskEvents(_page, _size);
        // };
        public func getActuator() : TA.TA<T>{
            return actuator();
        };
        

        // The following methods are used for clean up historical data.
        public func setCacheExpiration(_expiration: Int) : (){
            autoClearTimeout := _expiration;
        };
        public func clear(_expiration: ?Int, _delForced: Bool) : (){
            _clear(_expiration, _delForced);
            actuator().clear(_expiration, _delForced);
        };
        
        // The following methods are used for governance or manual compensation.
        /// update: Used to modify a task when blocking.
        public func update(_toid: Toid, _ttid: Ttid, _task: PushTaskRequest<T>, _comp: ?PushCompRequest<T>, _callback: ?TaskCallback<T>) : Ttid{
            assert(_inOrders(_toid) and _isOpening(_toid) and not(isCompleted(_toid)));
            assert(not(actuator().isCompleted(_ttid)));
            let task: TA.Task<T> = _taskFromRequest(_toid, _task, false);
            let tid = actuator().update(_ttid, task);
            let comp = _compFromRequest(_toid, ?tid, _comp);
            let sagaTask: SagaTask<T> = {
                ttid = tid;
                task = task;
                comp = comp;
                status = #Todo; //Todo
            };
            _updateTask(_toid, sagaTask);
            taskCallback.delete(tid);
            switch(_callback){
                case(?(callback)){ taskCallback.put(tid, callback); };
                case(_){};
            };
            return tid;
        };
        /// remove: Used to undo an unexecuted task.
        public func remove(_toid: Toid, _ttid: Ttid) : ?Ttid{
            assert(_inOrders(_toid) and _isOpening(_toid) and not(isCompleted(_toid)));
            assert(not(actuator().isCompleted(_ttid)));
            let tid_ = actuator().remove(_ttid);
            _removeTask(_toid, _ttid);
            taskCallback.delete(_ttid);
            return tid_;
        };
        /// append: Used to add a new task to an executing transaction order.
        public func append(_toid: Toid, _task: PushTaskRequest<T>, _comp: ?PushCompRequest<T>, _callback: ?TaskCallback<T>) : Ttid{
            assert(_inOrders(_toid) and _isOpening(_toid) and not(isCompleted(_toid)));
            let ttid = __push(_toid, _task, _comp, false);
            switch(_callback){
                case(?(callback)){ taskCallback.put(ttid, callback); };
                case(_){};
            };
            return ttid;
        };
        public func appendComp(_toid: Toid, _forTtid: Ttid, _comp: PushCompRequest<T>, _callback: ?TaskCallback<T>) : Tcid{
            assert(_inOrders(_toid) and _isOpening(_toid) and not(isCompleted(_toid)));
            let comp = _taskFromRequest(_toid, _comp, false);
            let tcid = _pushComp(_toid, _forTtid, comp, ?comp.preTtid);
            switch(_callback){
                case(?(callback)){ taskCallback.put(tcid, callback); };
                case(_){};
            };
            return tcid;
        };
        /// complete: Used to change the status of a blocked order to completed.
        public func complete(_toid: Toid, _status: OrderStatus) : async* Bool{
            assert(_status == #Done or _status == #Recovered);
            if (_statusEqual(_toid, #Blocking) and not(_isOpening(_toid)) and (_isTasksDone(_toid) or _isCompsDone(_toid))){
                _setStatus(_toid, _status);
                var callbackStatus : ?Status = null;
                try{ 
                    callbackStatus := await* _orderComplete(_toid); 
                    aliveOrders := List.filter(aliveOrders, func (item:(Toid, Time.Time)): Bool{ item.0 != _toid });
                }catch(e){ 
                    callbackStatus := ?#Error; 
                    _setStatus(_toid, #Blocking);
                };
                _setCallbackStatus(_toid, callbackStatus);
                //await _orderComplete(_toid, _status);
                _removeTATaskByOid(_toid);
                return true;
            };
            return false;
        };
        public func doneEmpty(_toid: Toid) : Bool{
            if (_toid == 0){
                for ((toid, order) in orders.entries()){
                    if (List.size(order.tasks) == 0 and List.size(order.comps) == 0){
                        _setStatus(toid, #Done);
                        aliveOrders := List.filter(aliveOrders, func (item:(Toid, Time.Time)): Bool{ item.0 != toid });
                    };
                };
                return true;
            }else{
                switch(orders.get(_toid)){
                    case(?(order)){
                        if (List.size(order.tasks) == 0 and List.size(order.comps) == 0){
                            _setStatus(_toid, #Done);
                            aliveOrders := List.filter(aliveOrders, func (item:(Toid, Time.Time)): Bool{ item.0 != _toid });
                            return true;
                        }else{
                            return false;
                        };
                    };
                    case(_){ return false; };
                };
            };
        };
        public func done(_toid: Toid, _status: OrderStatus, _toCallback: Bool) : async* Bool{
            assert(_status == #Done or _status == #Recovered);
            if (_inAliveOrders(_toid) and not(_isOpening(_toid))){
                _setStatus(_toid, _status);
                if(_toCallback){
                    var callbackStatus : ?Status = null;
                    try{ 
                        callbackStatus := await* _orderComplete(_toid); 
                        aliveOrders := List.filter(aliveOrders, func (item:(Toid, Time.Time)): Bool{ item.0 != _toid });
                    }catch(e){ 
                        callbackStatus := ?#Error; 
                        _setStatus(_toid, #Blocking);
                    };
                    _setCallbackStatus(_toid, callbackStatus);
                }else{
                    aliveOrders := List.filter(aliveOrders, func (item:(Toid, Time.Time)): Bool{ item.0 != _toid });
                };
                //await _orderComplete(_toid, _status);
                _removeTATaskByOid(_toid);
                return true;
            };
            return false;
        };
        public func block(_toid: Toid) : ?Toid{
            if (_inAliveOrders(_toid)){
                switch(orders.get(_toid)){
                    case(?(order)){
                        if ((order.status == #Todo or order.status == #Doing or order.status == #Compensating) and
                        Time.now() > order.time + 30*60*1000000000){
                            _setStatus(_toid, #Blocking);
                            return ?_toid;
                        };
                        return null;
                    };
                    case(_){ return null; };
                };
            };
            return null;
        };

        // The following methods are used for data backup and reset.
        public func getData() : Data<T> {
            return {
                autoClearTimeout = autoClearTimeout; 
                index = index; 
                firstIndex = firstIndex; 
                orders = Iter.toArray(orders.entries());
                aliveOrders = aliveOrders; 
                taskEvents = Iter.toArray(taskEvents.entries());
                actuator = actuator().getData(); 
            };
        };
        public func getDataBase() : Data<T> {
            let _orders = Iter.toArray(Iter.filter(orders.entries(), func (x: (Toid, Order<T>)): Bool{
                x.1.time + 72*3600*1000000000 > Time.now() or List.some(aliveOrders, func (t: (Toid, Time.Time)): Bool{ x.0 == t.0 })
            }));
            let _taskEvents = Iter.toArray(Iter.filter(taskEvents.entries(), func (x: (Toid, [Ttid])): Bool{
                Option.isSome(Array.find(_orders, func (t: (Toid, Order<T>)): Bool{ x.0 == t.0 }))
            }));
            return {
                autoClearTimeout = autoClearTimeout; 
                index = index; 
                firstIndex = firstIndex; 
                orders = _orders;
                aliveOrders = aliveOrders; 
                taskEvents = _taskEvents;
                actuator = actuator().getDataBase(); 
            };
        };
        public func setData(_data: Data<T>) : (){
            autoClearTimeout := _data.autoClearTimeout;
            index := _data.index; 
            firstIndex := _data.firstIndex; 
            orders := TrieMap.fromEntries(_data.orders.vals(), Nat.equal, TA.natHash);
            aliveOrders := _data.aliveOrders;
            taskEvents := TrieMap.fromEntries(_data.taskEvents.vals(), Nat.equal, TA.natHash);
            actuator().setData(_data.actuator);
        };
        

    };
};