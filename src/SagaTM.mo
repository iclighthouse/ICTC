/**
 * Module     : SagaTM.mo v1.5
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Description: ICTC Saga Transaction Manager.
 * Refers     : https://github.com/iclighthouse/ICTC
 */

import Nat "mo:base/Nat";
import Array "mo:base/Array";
import Hash "mo:base/Hash";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Iter "mo:base/Iter";
import List "mo:base/List";
import Deque "mo:base/Deque";
import TrieMap "mo:base/TrieMap";
import TA "./TA";
import Error "mo:base/Error";

module {
    public let Version: Nat = 7;
    public type Toid = Nat;
    public type Ttid = TA.Ttid;
    public type Tcid = TA.Ttid;
    public type Callee = TA.Callee;
    public type CallType = TA.CallType;
    public type Receipt = TA.Receipt;
    public type Task = TA.Task;
    public type Status = TA.Status;
    public type Callback = TA.Callback;
    public type LocalCall = TA.LocalCall;
    public type LocalCallAsync = TA.LocalCallAsync;
    public type TaskResult = TA.TaskResult;
    public type TaskEvent = TA.TaskEvent;
    public type ErrorLog = TA.ErrorLog;
    public type CalleeStatus = TA.CalleeStatus;
    public type Settings = {attemptsMax: ?TA.Attempts; recallInterval: ?Int; data: ?Blob};
    public type OrderStatus = {#Todo; #Doing; #Compensating; #Blocking; #Done; #Recovered;};
    public type Compensation = Task;
    public type CompStrategy = { #Forward; #Backward; };
    public type OrderCallback = (_toid: Toid, _status: OrderStatus, _data: ?Blob) -> ();
    public type PushTaskRequest = {
        callee: Callee;
        callType: CallType;
        preTtid: [Ttid];
        attemptsMax: ?Nat;
        recallInterval: ?Int; // nanoseconds
        cycles: Nat;
        data: ?Blob;
    };
    public type PushCompRequest = PushTaskRequest;
    public type SagaTask = {
        ttid: Ttid;
        task: Task;
        comp: ?Compensation; // for auto compensation
        status: Status;
    };
    public type CompTask = {
        forTtid: Ttid;
        tcid: Tcid;
        comp: Compensation;
        status: Status;
    };
    public type Order = {
        name: Text;
        compStrategy: CompStrategy;
        tasks: List.List<SagaTask>;
        allowPushing: {#Opening; #Closed;};
        comps: List.List<CompTask>;
        status: OrderStatus;  // *
        callbackStatus: ?Status;
        time: Time.Time;
        data: ?Blob;
    };
    public type Data = {
        autoClearTimeout: Int; 
        index: Nat; 
        firstIndex: Nat; 
        orders: [(Toid, Order)]; 
        aliveOrders: List.List<(Toid, Time.Time)>; 
        taskEvents: [(Toid, [Ttid])];
        //taskCallback: [(Ttid, Callback)]; 
        //orderCallback: [(Toid, OrderCallback)]; 
        actuator: TA.Data; 
    };

    public class SagaTM(this: Principal, localCall: ?LocalCall, localCallAsync: ?LocalCallAsync, defaultTaskCallback: ?Callback, defaultOrderCallback: ?OrderCallback) {
        let limitAtOnce: Nat = 200;
        var autoClearTimeout: Int = 3*30*24*3600*1000000000; // 3 months
        var index: Toid = 1;
        var firstIndex: Toid = 1;
        var orders = TrieMap.TrieMap<Toid, Order>(Nat.equal, TA.natHash);
        var aliveOrders = List.nil<(Toid, Time.Time)>();
        var taskEvents = TrieMap.TrieMap<Toid, [Ttid]>(Nat.equal, TA.natHash);
        var actuator_: ?TA.TA = null;
        var taskCallback = TrieMap.TrieMap<Ttid, Callback>(Nat.equal, TA.natHash); /*fix*/
        var orderCallback = TrieMap.TrieMap<Toid, OrderCallback>(Nat.equal, TA.natHash);
        var countAsyncMessage : Nat = 0;
        private func actuator() : TA.TA {
            switch(actuator_){
                case(?(_actuator)){ return _actuator; };
                case(_){
                    let localCall_ = Option.get(localCall, func (ct: CallType, r: ?Receipt): (TaskResult){ (#Error, null, ?{code = #future(9902); message = "No local function proxy specified"; }) });
                    let localCallAsync_ = Option.get(localCallAsync, func (ct: CallType, r: ?Receipt): async (TaskResult){ (#Error, null, ?{code = #future(9902); message = "No local function proxy specified"; }) });
                    let act = TA.TA(limitAtOnce, autoClearTimeout, this, localCall_, localCallAsync_, ?_taskCallbackProxy, null);
                    actuator_ := ?act;
                    return act;
                };
            };
            
        };

        // Unique callback entrance. This function will call each specified callback of task
        private func _taskCallbackProxy(_ttid: Ttid, _task: Task, _result: TaskResult) : async (){
            let toid = Option.get(_task.toid, 0);
            switch(_status(toid)){
                case(?(#Todo)){ _setStatus(toid, #Doing); };
                case(_){};
            };
            var orderStatus : OrderStatus = #Todo;
            var strategy: CompStrategy = #Backward;
            var isClosed : Bool = false;
            switch(orders.get(toid)){
                case(?(order)){ 
                    orderStatus := order.status;
                    strategy := order.compStrategy; 
                    isClosed := order.allowPushing == #Closed;
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
                        _taskCallback(_ttid, _task, _result); 
                        taskCallback.delete(_ttid);
                        callbackDone := true;
                    } catch(e){
                        callbackDone := false;
                    };
                };
                case(_){
                    switch(defaultTaskCallback){
                        case(?(_taskCallback)){
                            try{
                                _taskCallback(_ttid, _task, _result);
                                callbackDone := true;
                            }catch(e){
                                callbackDone := false;
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
                        callbackStatus := _orderComplete(toid); 
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
                        callbackStatus := _orderComplete(toid); 
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
                // if (_result.0 == #Done and isClosed and Option.get(_orderLastTid(toid), 0) == _ttid){ //
                //     await _orderComplete(toid, #Done);
                //     _removeTATaskByOid(toid);
                // }
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
        private func _pushOrder(_toid: Toid, _order: Order): (){
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

        private func _taskFromRequest(_toid: Toid, _task: PushTaskRequest, _autoAddPreTtid: Bool) : TA.Task{
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
        private func _compFromRequest(_toid: Toid, _forTtid: ?Ttid, _comp: ?PushCompRequest) : ?Compensation{
            var comp: ?Compensation = null;
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
        // private func _inOrderTasks(_toid: Toid, _ttid: Ttid) : Bool{
        //     switch(orders.get(_toid)){
        //         case(?(order)){
        //             return Option.isSome(List.find(order.tasks, func (t:SagaTask): Bool{ t.ttid == _ttid }));
        //         };
        //         case(_){ return false; };
        //     };
        // };
        private func _putTask(_toid: Toid, _sagaTask: SagaTask) : (){
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
        private func _updateTask(_toid: Toid, _sagaTask: SagaTask) : (){
            switch(orders.get(_toid)){
                case(?(order)){
                    let tasks = List.map(order.tasks, func (t:SagaTask):SagaTask{
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
                    let tasks = List.filter(order.tasks, func (t:SagaTask): Bool{ t.ttid != _ttid });
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
        /// Set the status of TO to #Done. If an error occurs and cannot be caught, the status of TO is #Doing
        private func _orderComplete(_toid: Toid) : ?Status{
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
                                //try{
                                    _orderCallback(_toid, order.status, order.data); 
                                    orderCallback.delete(_toid);
                                    callbackStatus := ?#Done;
                                // }catch(e){
                                //     callbackStatus := ?#Error;
                                // };
                            };
                            case(_){
                                switch(defaultOrderCallback){
                                    case(?(_orderCallback)){
                                        //try{
                                            _orderCallback(_toid, order.status, order.data); 
                                            callbackStatus := ?#Done;
                                        // }catch(e){
                                        //     callbackStatus := ?#Error;
                                        // };
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
        // private func _getTask(_toid: Toid, _ttid: Ttid) : ?SagaTask{
        //     switch(orders.get(_toid)){
        //         case(?(order)){
        //             return List.find(order.tasks, func (t:SagaTask): Bool{ t.ttid == _ttid });
        //         };
        //         case(_){ return null; };
        //     };
        // };
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
        // private func _getComp(_toid: Toid, _tcid: Tcid) : ?CompTask{
        //     switch(orders.get(_toid)){
        //         case(?(order)){
        //             return List.find(order.comps, func (t:CompTask): Bool{ t.tcid == _tcid });
        //         };
        //         case(_){ return null; };
        //     };
        // };
        private func _isCompsDone(_toid: Toid) : Bool{
            switch(orders.get(_toid)){
                case(?(order)){
                    switch(List.pop(order.comps)){
                        case((?(task), ts)){
                            return actuator().isCompleted(task.tcid);
                        };
                        case(_){ return true; };
                    };
                };
                case(_){ return false; };
            };
        };
        private func _statusTest(_toid: Toid) : async (){
            switch(orders.get(_toid)){
                case(?(order)){
                    if (order.status == #Doing and order.allowPushing == #Closed and _isTasksDone(_toid)){
                        _setStatus(_toid, #Done);
                        var callbackStatus : ?Status = null;
                        try{ 
                            callbackStatus := _orderComplete(_toid); 
                            aliveOrders := List.filter(aliveOrders, func (item:(Toid, Time.Time)): Bool{ item.0 != _toid });
                        }catch(e){ 
                            callbackStatus := ?#Error; 
                            _setStatus(_toid, #Blocking);
                        };
                        _setCallbackStatus(_toid, callbackStatus);
                        //await _orderComplete(_toid, #Done);
                    } else if (order.status == #Compensating and order.allowPushing == #Closed and _isCompsDone(_toid)){
                        _setStatus(_toid, #Recovered);
                        var callbackStatus : ?Status = null;
                        try{ 
                            callbackStatus := _orderComplete(_toid); 
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
                    };
                };
                case(_){};
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
        // private func _inOrderComps(_toid: Toid, _tcid: Tcid) : Bool{
        //     switch(orders.get(_toid)){
        //         case(?(order)){
        //             return Option.isSome(List.find(order.comps, func (t:CompTask): Bool{ t.tcid == _tcid }));
        //         };
        //         case(_){ return false; };
        //     };
        // };
        private func _pushComp(_toid: Toid, _ttid: Ttid, _comp: Compensation, _preTtid: ?[Ttid]) : Tcid{
            if (not(_inOrders(_toid))){ return 0; };
            let preTtid = Option.get(_orderLastCid(_toid), 0);
            let task: Task = {
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
            let compTask: CompTask = {
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
                                            let cid = _pushComp(_toid, task.ttid, comp, null);
                                        };
                                        case(_){ // to block
                                            let comp: Compensation = {
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
                                            let cid = _pushComp(_toid, task.ttid, comp, null);
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
        // private func _setComp(_toid: Toid, _ttid: Ttid, _comp: ?Compensation) : Bool{
        //     var res : Bool = false;
        //     switch(orders.get(_toid)){
        //         case(?(order)){
        //             var tasks = order.tasks;
        //             tasks := List.map(tasks, func (t:SagaTask): SagaTask{
        //                 if (t.ttid == _ttid and Option.isNull(t.comp)){
        //                     res := true;
        //                     return {
        //                         ttid = t.ttid;
        //                         task = t.task;
        //                         comp = _comp;
        //                         status = t.status;
        //                     };
        //                 } else { return t; };
        //             });
        //             let orderNew : Order = {
        //                 compStrategy = order.compStrategy;
        //                 tasks = tasks;
        //                 allowPushing = order.allowPushing;
        //                 comps = order.comps;
        //                 status = order.status;
        //                 callbackStatus = order.callbackStatus;
        //                 time = order.time;
        //                 data = order.data;
        //             };
        //             orders.put(_toid, orderNew);
        //         };
        //         case(_){};
        //     };
        //     return res;
        // };
        private func _setTaskStatus(_toid: Toid, _ttid: Ttid, _status: Status) : Bool{
            var res : Bool = false;
            switch(orders.get(_toid)){
                case(?(order)){
                    var tasks = order.tasks;
                    var comps = order.comps;
                    tasks := List.map(tasks, func (t:SagaTask): SagaTask{
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
                    comps := List.map(comps, func (t:CompTask): CompTask{
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
                    let orderNew : Order = {
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
        private func __push(_toid: Toid, _task: PushTaskRequest, _comp: ?PushCompRequest, _autoAddPreTtid: Bool) : Ttid{
            assert(_inOrders(_toid) and _isOpening(_toid));
            let task: TA.Task = _taskFromRequest(_toid, _task, _autoAddPreTtid);
            let tid = actuator().push(task);
            let comp = _compFromRequest(_toid, ?tid, _comp);
            let sagaTask: SagaTask = {
                ttid = tid;
                task = task;
                comp = comp;
                status = #Todo; //Todo
            };
            _putTask(_toid, sagaTask);
            return tid;
        };

        // The following methods are used for transaction order operations.
        public func create(_name: Text, _compStrategy: CompStrategy, _data: ?Blob, _callback: ?OrderCallback) : Toid{
            assert(this != Principal.fromText("aaaaa-aa"));
            let toid = index;
            index += 1;
            let order: Order = {
                name = _name;
                compStrategy = _compStrategy;
                tasks = List.nil<SagaTask>();
                allowPushing = #Opening;
                comps = List.nil<CompTask>();
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
        public func push(_toid: Toid, _task: PushTaskRequest, _comp: ?PushCompRequest, _callback: ?Callback) : Ttid{
            let ttid = __push(_toid, _task, _comp, true);
            switch(_callback){
                case(?(callback)){ taskCallback.put(ttid, callback); };
                case(_){};
            };
            return ttid;
        };
        /// set task done   
        public func taskDone(_toid: Toid, _ttid: Ttid, _toCallback: Bool) : async ?Ttid{
            if (_inAliveOrders(_toid) and not(actuator().isInPool(_ttid)) and not(actuator().isCompleted(_ttid))){
                switch(orders.get(_toid)){
                    case(?(order)){
                        if ((order.status == #Todo or order.status == #Doing or order.status == #Blocking) and not(_isTasksDone(_toid))){
                            try{
                                countAsyncMessage += 2;
                                let res = await actuator().done(_ttid, _toCallback);
                                countAsyncMessage -= Nat.min(2, countAsyncMessage);
                                return res;
                            }catch(e){ 
                                countAsyncMessage -= Nat.min(2, countAsyncMessage); 
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
                            var task_ : ?Task = null;
                            switch(List.find(order.tasks, func (t:SagaTask): Bool{ t.ttid == _ttid })){
                                case(?(sagaTask)){ task_ := ?sagaTask.task; };
                                case(_){};
                            };
                            switch(List.find(order.comps, func (t:CompTask): Bool{ t.tcid == _ttid })){
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
        // public func setCompForLastTask(_toid: Toid, _ttid: Ttid, _comp: ?PushCompRequest) : Bool{
        //     assert(_isOpening(_toid) and Option.get(_orderLastTid(_toid), 0) == _ttid);
        //     let comp = _compFromRequest(_toid, ?_ttid, _comp);
        //     return _setComp(_toid, _ttid, comp);
        // };
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
        // public func doing(_toid: Toid) : (){
        //     switch(_status(_toid)){
        //         case(?(#Todo)){ _setStatus(_toid, #Doing); };
        //         case(_){};
        //     };
        //     if (_status(_toid) == #Doing and not(_isOpening(_toid) and _isTasksDone(_toid))){
        //         _setStatus(_toid, #Done);
        //     };
        // };
        public func run(_toid: Toid) : async ?OrderStatus{ 
            switch(_status(_toid)){
                case(?(#Todo)){ _setStatus(_toid, #Doing); };
                case(_){};
            };
            let actuations = actuator().actuations();
            if (actuations.actuationThreads < 3 or Time.now() > actuations.lastActuationTime + 60*1000000000){ // 60s
                try{ 
                    countAsyncMessage += 2;
                    let count = await actuator().run(); 
                    countAsyncMessage -= Nat.min(2, countAsyncMessage);
                }catch(e){
                    countAsyncMessage -= Nat.min(2, countAsyncMessage);
                };
            };
            if (_toid > 0){
                try{
                    countAsyncMessage += 2;
                    await _statusTest(_toid);
                    countAsyncMessage -= Nat.min(2, countAsyncMessage);
                }catch(e){
                    countAsyncMessage -= Nat.min(2, countAsyncMessage);
                };
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
        public func getOrder(_toid: Toid) : ?Order{
            return orders.get(_toid);
        };
        public func getOrders(_page: Nat, _size: Nat) : {data: [(Toid, Order)]; totalPage: Nat; total: Nat}{
            return TA.getTM<Order>(orders, index, firstIndex, _page, _size);
        };
        public func getAliveOrders() : [(Toid, ?Order)]{
            return Array.map<(Toid, Time.Time), (Toid, ?Order)>(List.toArray(aliveOrders), 
                func (item:(Toid, Time.Time)):(Toid, ?Order) { 
                    return (item.0, orders.get(item.0));
                });
        };
        public func getTaskEvents(_toid: Toid) : [TaskEvent]{
            var events: [TaskEvent] = [];
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
        public func getActuator() : TA.TA{
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
        public func update(_toid: Toid, _ttid: Ttid, _task: PushTaskRequest, _comp: ?PushCompRequest, _callback: ?Callback) : Ttid{
            assert(_inOrders(_toid) and _isOpening(_toid) and not(isCompleted(_toid)));
            assert(not(actuator().isCompleted(_ttid)));
            let task: TA.Task = _taskFromRequest(_toid, _task, false);
            let tid = actuator().update(_ttid, task);
            let comp = _compFromRequest(_toid, ?tid, _comp);
            let sagaTask: SagaTask = {
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
        public func append(_toid: Toid, _task: PushTaskRequest, _comp: ?PushCompRequest, _callback: ?Callback) : Ttid{
            assert(_inOrders(_toid) and _isOpening(_toid) and not(isCompleted(_toid)));
            let ttid = __push(_toid, _task, _comp, false);
            switch(_callback){
                case(?(callback)){ taskCallback.put(ttid, callback); };
                case(_){};
            };
            return ttid;
        };
        public func appendComp(_toid: Toid, _forTtid: Ttid, _comp: PushCompRequest, _callback: ?Callback) : Tcid{
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
        public func complete(_toid: Toid, _status: OrderStatus) : async Bool{
            assert(_status == #Done or _status == #Recovered);
            if (_statusEqual(_toid, #Blocking) and not(_isOpening(_toid)) and (_isTasksDone(_toid) or _isCompsDone(_toid))){
                _setStatus(_toid, _status);
                var callbackStatus : ?Status = null;
                try{ 
                    callbackStatus := _orderComplete(_toid); 
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
            switch(orders.get(_toid)){
                case(?(order)){
                    if (List.size(order.tasks) == 0 and List.size(order.comps) == 0){
                        _setStatus(_toid, #Done);
                        return true;
                    }else{
                        return false;
                    };
                };
                case(_){ return false; };
            };
        };
        public func done(_toid: Toid, _status: OrderStatus, _toCallback: Bool) : async Bool{
            assert(_status == #Done or _status == #Recovered);
            if (_inAliveOrders(_toid) and not(_isOpening(_toid)) and (_isTasksDone(_toid) or _isCompsDone(_toid))){
                _setStatus(_toid, _status);
                if(_toCallback){
                    var callbackStatus : ?Status = null;
                    try{ 
                        callbackStatus := _orderComplete(_toid); 
                        aliveOrders := List.filter(aliveOrders, func (item:(Toid, Time.Time)): Bool{ item.0 != _toid });
                    }catch(e){ 
                        callbackStatus := ?#Error; 
                        _setStatus(_toid, #Blocking);
                    };
                    _setCallbackStatus(_toid, callbackStatus);
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
        public func getData() : Data {
            return {
                autoClearTimeout = autoClearTimeout; 
                index = index; 
                firstIndex = firstIndex; 
                orders = Iter.toArray(orders.entries());
                aliveOrders = aliveOrders; 
                taskEvents = Iter.toArray(taskEvents.entries());
                //taskCallback = Iter.toArray(taskCallback.entries());
                //orderCallback = Iter.toArray(orderCallback.entries());
                actuator = actuator().getData(); 
            };
        };
        public func setData(_data: Data) : (){
            autoClearTimeout := _data.autoClearTimeout;
            index := _data.index; 
            firstIndex := _data.firstIndex; 
            orders := TrieMap.fromEntries(_data.orders.vals(), Nat.equal, TA.natHash);
            aliveOrders := _data.aliveOrders;
            taskEvents := TrieMap.fromEntries(_data.taskEvents.vals(), Nat.equal, TA.natHash);
            //taskCallback := TrieMap.fromEntries(_data.taskCallback.vals(), Nat.equal, Hash.hash);
            //orderCallback := TrieMap.fromEntries(_data.orderCallback.vals(), Nat.equal, Hash.hash);
            actuator().setData(_data.actuator);
        };
        

    };
};