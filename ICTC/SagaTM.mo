/**
 * Module     : SagaTM.mo v0.1
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
import SyncTA "./SyncTA";

module {
    public let Version: Nat = 1;
    public type Toid = Nat;
    public type Ttid = SyncTA.Ttid;
    public type Tcid = SyncTA.Ttid;
    public type Callee = SyncTA.Callee;
    public type CallType = SyncTA.CallType;
    public type Receipt = SyncTA.Receipt;
    public type Task = SyncTA.Task;
    public type Status = SyncTA.Status;
    public type Callback = SyncTA.Callback;
    public type LocalCall = SyncTA.LocalCall;
    public type TaskResult = SyncTA.TaskResult;
    public type TaskEvent = SyncTA.TaskEvent;
    public type ErrorLog = SyncTA.ErrorLog;
    public type CalleeStatus = SyncTA.CalleeStatus;
    public type Settings = {attemptsMax: ?SyncTA.Attempts; recallInterval: ?Int; data: ?Blob};
    public type OrderStatus = {#Todo; #Doing; #Compensating; #Blocking; #Done; #Recovered;};
    public type Compensation = Task;
    public type CompStrategy = { #Forward; #Backward; };
    public type OrderCallback = (_toid: Toid, _status: OrderStatus, _data: ?Blob) -> async ();
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
    };
    public type CompTask = {
        forTtid: Ttid;
        tcid: Tcid;
        comp: Compensation;
    };
    public type Order = {
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
        actuator: SyncTA.Data; 
    };

    public class SagaTM(this: Principal, localCall: LocalCall, taskCallback: ?Callback, orderCallback: ?OrderCallback) {
        let limitAtOnce: Nat = 20;
        var autoClearTimeout: Int = 3*30*24*3600*1000000000; // 3 months
        var index: Toid = 1;
        var firstIndex: Toid = 1;
        var orders = TrieMap.TrieMap<Toid, Order> (Nat.equal, Hash.hash);
        var aliveOrders = List.nil<(Toid, Time.Time)>();
        var taskEvents = TrieMap.TrieMap<Toid, [Ttid]> (Nat.equal, Hash.hash);
        var actuator_: ?SyncTA.SyncTA = null;
        private func actuator() : SyncTA.SyncTA {
            switch(actuator_){
                case(?(_actuator)){ return _actuator; };
                case(_){
                    let act = SyncTA.SyncTA(limitAtOnce, autoClearTimeout, this, localCall, ?_taskCallbackProxy);
                    actuator_ := ?act;
                    return act;
                };
            };
            
        };

        // Unique callback entrance. This function will call each specified callback of task
        private func _taskCallbackProxy(_ttid: Ttid, _task: Task, _result: TaskResult) : async (){
            let toid = Option.get(_task.toid, 0);
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
            // callback
            switch(taskCallback){
                case(?(_taskCallback)){
                    await _taskCallback(_ttid, _task, _result);
                };
                case(_){};
            };
            // process
            if (orderStatus == #Compensating){ //Compensating
                if (_result.0 == #Done and isClosed and Option.get(_orderLastCid(toid), 0) == _ttid){ 
                    await _orderComplete(toid, #Recovered);
                    ignore actuator().removeByOid(toid);
                }else if (_result.0 == #Error or _result.0 == #Unknown){ //Blocking
                    _setStatus(toid, #Blocking);
                };
            } else if (orderStatus == #Doing){ //Doing
                if (_result.0 == #Done and isClosed and Option.get(_orderLastTid(toid), 0) == _ttid){ //
                    await _orderComplete(toid, #Done);
                }else if (_result.0 == #Error and strategy == #Backward){ // recovery
                    _setStatus(toid, #Compensating);
                    _compensate(toid, _ttid);
                }else if (_result.0 == #Error or _result.0 == #Unknown){ //Blocking
                    _setStatus(toid, #Blocking);
                };
            } else { // Blocking
                if (_result.0 == #Done and isClosed and Option.get(_orderLastTid(toid), 0) == _ttid){ //
                    await _orderComplete(toid, #Done);
                    ignore actuator().removeByOid(toid);
                }
            };
            //taskEvents
            switch(taskEvents.get(toid)){
                case(?(events)){
                    taskEvents.put(toid, Array.append(events, [_ttid]));
                };
                case(_){
                    taskEvents.put(toid, [_ttid]);
                };
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
            _clear(false);
        };
        private func _clear(_delExc: Bool) : (){
            var completed: Bool = false;
            var moveFirstPointer: Bool = true;
            var i: Nat = firstIndex;
            while (i < index and not(completed)){
                switch(orders.get(i)){
                    case(?(order)){
                        if (Time.now() > order.time + autoClearTimeout and (_delExc or order.status == #Done or order.status == #Recovered)){
                            _deleteOrder(i); // delete the record.
                            i += 1;
                        }else if (Time.now() > order.time + autoClearTimeout){
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

        private func _taskFromRequest(_toid: Toid, _task: PushTaskRequest) : SyncTA.Task{
            var preTtid = _task.preTtid;
            let lastTtid = Option.get(_orderLastTid(_toid), 0);
            if (Option.isNull(Array.find(preTtid, func (ttid:Ttid):Bool{ttid == lastTtid})) and lastTtid > 0){
                preTtid := Array.append(preTtid, [lastTtid]);
            };
            return {
                callee = _task.callee; 
                callType = _task.callType; 
                preTtid = preTtid; 
                toid = ?_toid; 
                compFor = null;
                attemptsMax = Option.get(_task.attemptsMax, 1); 
                recallInterval = Option.get(_task.recallInterval, 0); 
                cycles = _task.cycles;
                data = _task.data;
                time = Time.now();
            };
        };
        private func _compFromRequest(_toid: Toid, _forTtid: Ttid, _comp: ?PushCompRequest) : ?Compensation{
            var comp: ?Compensation = null;
            switch(_comp){
                case(?(compensation)){
                    comp := ?{
                        callee = compensation.callee; 
                        callType = compensation.callType; 
                        preTtid = []; 
                        toid = ?_toid; 
                        compFor = ?_forTtid;
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
        private func _inOrderTasks(_toid: Toid, _ttid: Ttid) : Bool{
            switch(orders.get(_toid)){
                case(?(order)){
                    return Option.isSome(List.find(order.tasks, func (t:SagaTask): Bool{ t.ttid == _ttid }));
                };
                case(_){ return false; };
            };
        };
        private func _putTask(_toid: Toid, _sagaTask: SagaTask) : (){
            switch(orders.get(_toid)){
                case(?(order)){
                    assert(order.allowPushing == #Opening);
                    let tasks = List.push(_sagaTask, order.tasks);
                    let orderNew = {
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
        private func _orderComplete(_toid: Toid, _tatus: OrderStatus) : async (){
            _setStatus(_toid, _tatus);
            var callbackStatus : ?Status = null;
            switch(orders.get(_toid)){
                case(?(order)){
                    switch(orderCallback){
                        case(?(_orderCallback)){
                            try{ 
                                await _orderCallback(_toid, _tatus, order.data); 
                                callbackStatus := ?#Done;
                            } catch(e) {
                                callbackStatus := ?#Error;
                            };
                        };
                        case(_){};
                    };
                    aliveOrders := List.filter(aliveOrders, func (item:(Toid, Time.Time)): Bool{ item.0 != _toid });
                };
                case(_){};
            };
            _setCallbackStatus(_toid, callbackStatus);
        };
        private func _setStatus(_toid: Toid, _setting: OrderStatus) : (){
            switch(orders.get(_toid)){
                case(?(order)){
                    let orderNew = {
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
        private func _getTask(_toid: Toid, _ttid: Ttid) : ?SagaTask{
            switch(orders.get(_toid)){
                case(?(order)){
                    return List.find(order.tasks, func (t:SagaTask): Bool{ t.ttid == _ttid });
                };
                case(_){ return null; };
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
        private func _getComp(_toid: Toid, _tcid: Tcid) : ?CompTask{
            switch(orders.get(_toid)){
                case(?(order)){
                    return List.find(order.comps, func (t:CompTask): Bool{ t.tcid == _tcid });
                };
                case(_){ return null; };
            };
        };
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
                        await _orderComplete(_toid, #Done);
                    } else if (order.status == #Compensating and order.allowPushing == #Closed and _isCompsDone(_toid)){
                        await _orderComplete(_toid, #Recovered);
                        ignore actuator().removeByOid(_toid);
                    } else if (order.status == #Blocking and order.allowPushing == #Closed and _isTasksDone(_toid)){
                        await _orderComplete(_toid, #Done);
                        ignore actuator().removeByOid(_toid);
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
        private func _inOrderComps(_toid: Toid, _tcid: Tcid) : Bool{
            switch(orders.get(_toid)){
                case(?(order)){
                    return Option.isSome(List.find(order.comps, func (t:CompTask): Bool{ t.tcid == _tcid }));
                };
                case(_){ return false; };
            };
        };
        private func _pushComp(_toid: Toid, _ttid: Ttid, _comp: Compensation) : Tcid{
            if (not(_inOrders(_toid))){ return 0; };
            let preTtid = _orderLastCid(_toid);
            let task: Task = {
                callee = _comp.callee;
                callType = _comp.callType;
                preTtid = [Option.get(preTtid, 0)];
                toid = _comp.toid;
                compFor = ?_ttid;
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
            };
            switch(orders.get(_toid)){
                case(?(order)){
                    let comps = List.push(compTask, order.comps);
                    let orderNew = {
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
                                            let cid = _pushComp(_toid, task.ttid, comp);
                                        };
                                        case(_){ // to block
                                            let comp: Compensation = {
                                                callee = task.task.callee;
                                                callType = #__block;
                                                preTtid = [];
                                                toid = ?_toid;
                                                compFor = ?task.ttid;
                                                attemptsMax = 1;
                                                recallInterval = 0; // nanoseconds
                                                cycles = 0;
                                                data = null;
                                                time = Time.now();
                                            };
                                            let cid = _pushComp(_toid, task.ttid, comp);
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
        private func _setComp(_toid: Toid, _ttid: Ttid, _comp: ?Compensation) : Bool{
            var res : Bool = false;
            switch(orders.get(_toid)){
                case(?(order)){
                    var tasks = order.tasks;
                    tasks := List.map(tasks, func (t:SagaTask): SagaTask{
                        if (t.ttid == _ttid and Option.isNull(t.comp)){
                            res := true;
                            return {
                                ttid = t.ttid;
                                task = t.task;
                                comp = _comp;
                            };
                        } else { return t; };
                    });
                    let orderNew : Order = {
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
            return res;
        };

        // The following methods are used for transaction order operations.
        public func create(_compStrategy: CompStrategy, _data: ?Blob) : Toid{
            assert(this != Principal.fromText("aaaaa-aa"));
            let toid = index;
            index += 1;
            let order: Order = {
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
            return toid;
        };
        public func push(_toid: Toid, _task: PushTaskRequest, _comp: ?PushCompRequest) : Ttid{
            assert(_inOrders(_toid) and _isOpening(_toid));
            let task: SyncTA.Task = _taskFromRequest(_toid, _task);
            let tid = actuator().push(task);
            let comp = _compFromRequest(_toid, tid, _comp);
            let sagaTask: SagaTask = {
                ttid = tid;
                task = task;
                comp = comp;
            };
            _putTask(_toid, sagaTask);
            return tid;
        };
        public func setComp(_toid: Toid, _ttid: Ttid, _comp: ?PushCompRequest) : Bool{
            assert(_isOpening(_toid) and Option.get(_orderLastTid(_toid), 0) == _ttid);
            let comp = _compFromRequest(_toid, _ttid, _comp);
            return _setComp(_toid, _ttid, comp);
        };
        public func open(_toid: Toid) : (){
            _allowPushing(_toid, #Opening);
        };
        public func finish(_toid: Toid) : (){
            _allowPushing(_toid, #Closed);
        };
        public func run(_toid: Toid) : async ?OrderStatus{
            switch(_status(_toid)){
                case(?(#Todo)){ _setStatus(_toid, #Doing); };
                case(_){};
            };
            try{
                let count = await actuator().run();
            }catch(e){};
            await _statusTest(_toid);
            return _status(_toid);
        };

        // The following methods are used for queries.
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
            return SyncTA.getTM<Order>(orders, _page, _size, index, firstIndex);
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
                    case(?(event)) { events := Array.append(events, [event]); };
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
        public func getActuator() : SyncTA.SyncTA{
            return actuator();
        };
        

        // The following methods are used for clean up historical data.
        public func setCacheExpiration(_expiration: Int) : (){
            autoClearTimeout := _expiration;
        };
        public func clear(_delExc: Bool) : (){
            _clear(_delExc);
            actuator().clear(null, _delExc);
        };
        
        // The following methods are used for governance or manual compensation.
        /// update: Used to modify a task when blocking.
        public func update(_toid: Toid, _ttid: Ttid, _task: PushTaskRequest, _comp: ?PushCompRequest) : Ttid{
            assert(_inOrders(_toid) and _isOpening(_toid) and not(isCompleted(_toid)));
            assert(not(actuator().isCompleted(_ttid)));
            let task: SyncTA.Task = _taskFromRequest(_toid, _task);
            let tid = actuator().update(_ttid, task);
            let comp = _compFromRequest(_toid, tid, _comp);
            let sagaTask: SagaTask = {
                ttid = tid;
                task = task;
                comp = comp;
            };
            _updateTask(_toid, sagaTask);
            return tid;
        };
        /// remove: Used to undo an unexecuted task.
        public func remove(_toid: Toid, _ttid: Ttid) : ?Ttid{
            assert(_inOrders(_toid) and _isOpening(_toid) and not(isCompleted(_toid)));
            assert(not(actuator().isCompleted(_ttid)));
            let tid_ = actuator().remove(_ttid);
            _removeTask(_toid, _ttid);
            return tid_;
        };
        /// append: Used to add a new task to an executing transaction order.
        public func append(_toid: Toid, _task: PushTaskRequest, _comp: ?PushCompRequest) : Ttid{
            assert(_inOrders(_toid) and _isOpening(_toid) and not(isCompleted(_toid)));
            return push(_toid, _task, _comp);
        };
        /// complete: Used to change the status of a blocked order to completed.
        public func complete(_toid: Toid, _status: OrderStatus) : async Bool{
            assert(_status == #Done or _status == #Recovered);
            if (_statusEqual(_toid, #Blocking) and not(_isOpening(_toid)) and _isTasksDone(_toid)){
                await _orderComplete(_toid, #Done);
                ignore actuator().removeByOid(_toid);
                return true;
            };
            return false;
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
                actuator = actuator().getData(); 
            };
        };
        public func setData(_data: Data) : (){
            autoClearTimeout := _data.autoClearTimeout;
            index := _data.index; 
            firstIndex := _data.firstIndex; 
            orders := TrieMap.fromEntries(_data.orders.vals(), Nat.equal, Hash.hash);
            aliveOrders := _data.aliveOrders;
            taskEvents := TrieMap.fromEntries(_data.taskEvents.vals(), Nat.equal, Hash.hash);
            actuator().setData(_data.actuator);
        };
        

    };
};