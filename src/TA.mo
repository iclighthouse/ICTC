/**
 * Module     : TA.mo v2.0
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Description: ICTC Sync Task Actuator.
 * Refers     : https://github.com/iclighthouse/ICTC
 */

import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import CallType "./CallType";
import Deque "mo:base/Deque";
import Hash "mo:base/Hash";
import Iter "mo:base/Iter";
import List "mo:base/List";
import Nat "mo:base/Nat";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import TrieMap "mo:base/TrieMap";
import TATypes "TATypes";
// import TaskHash "TaskHash";
import Nat64 "mo:base/Nat64";
import Binary "mo:icl/Binary";
import ICRC1 "mo:icl/ICRC1";
import Error "mo:base/Error";
// import Call "mo:base/ExperimentalInternetComputer";

module {
    public let Version: Text = "2.3.0";
    public type Domain = CallType.Domain;
    public type Status = CallType.Status;
    public type CallType = CallType.CallType;
    public type Receipt = CallType.Receipt;
    public type LocalCall = CallType.LocalCall;
    //public type LocalCallAsync = CallType.LocalCallAsync;
    public type TaskResult = CallType.TaskResult;
    public type Callee = TATypes.Callee;
    public type CalleeStatus = TATypes.CalleeStatus;
    public type Ttid = TATypes.Ttid; // from 1
    public type Toid = TATypes.Toid; // from 1
    public type Attempts = TATypes.Attempts;
    public type Task = TATypes.Task;
    public type AgentCallback = TATypes.AgentCallback;
    public type Callback = TATypes.Callback;
    public type TaskEvent = TATypes.TaskEvent;
    public type ErrorLog = TATypes.ErrorLog;
    public type Data = {
        tasks: Deque.Deque<(Ttid, Task)>; 
        taskLogs: [(Ttid, TaskEvent)]; 
        errorLogs: [(Nat, ErrorLog)]; 
        callees: [(Callee, CalleeStatus)]; 
        index: Nat; 
        firstIndex: Nat; 
        errIndex: Nat; 
        firstErrIndex: Nat; 
    };
    public func arrayAppend<T>(a: [T], b: [T]) : [T]{
        let buffer = Buffer.Buffer<T>(1);
        for (t in a.vals()){
            buffer.add(t);
        };
        for (t in b.vals()){
            buffer.add(t);
        };
        return Buffer.toArray(buffer);
    };
    // replace Hash.hash (Warning: Incompatible)
    public func natHash(n : Nat) : Hash.Hash{
        return Blob.hash(Blob.fromArray(Binary.BigEndian.fromNat64(Nat64.fromIntWrap(n))));
    };
    public func getTM<V>(_tm: TrieMap.TrieMap<Nat, V>, _index: Nat, _firstIndex: Nat, _page: Nat, _size: Nat) : {data: [(Nat, V)]; totalPage: Nat; total: Nat}{
        let length = _tm.size();
        if (_page < 1 or _size < 1){
            return {data = []; totalPage = 0; total = length; };
        };
        let offset = Nat.sub(_page, 1) * _size;
        var start: Nat = 0;
        var end: Nat = 0;
        if (offset < Nat.sub(_index,1)){
            start := Nat.sub(Nat.sub(_index,1), offset);
            if (start < _firstIndex){
                return {data = []; totalPage = 0; total = length; };
            };
            if (start > Nat.sub(_size, 1)){
                end := Nat.max(Nat.sub(start, Nat.sub(_size, 1)), _firstIndex);
            }else{
                end := _firstIndex;
            };
        }else{
            return {data = []; totalPage = 0; total = length; };
        };
        var data: [(Nat, V)] = [];
        for (i in Iter.range(end, start)){
            switch(_tm.get(i)){
                case(?(item)){
                    data := arrayAppend(data, [(i, item)]);
                };
                case(_){};
            };
        };
        var totalPage: Nat = length / _size;
        if (totalPage * _size < length) { totalPage += 1; };
        return {data = data; totalPage = totalPage; total = length; };
    };
    
    /// limitNum: The actuator runs `limitNum` tasks at once.
    public class TA(limitNum: Nat, autoClearTimeout: Int, this: Principal, localCall: LocalCall, /*localCallAsync: LocalCallAsync,*/ agentCallback: ?AgentCallback, taskCallback: ?Callback) {
        var tasks = Deque.empty<(Ttid, Task)>(); /*fix*/
        var index : Nat = 1;
        var firstIndex : Nat = 1;
        var taskLogs = TrieMap.TrieMap<Ttid, TaskEvent> (Nat.equal, natHash); /*fix*/
        var errIndex : Nat = 1;
        var firstErrIndex : Nat = 1;
        var errorLogs = TrieMap.TrieMap<Nat, ErrorLog> (Nat.equal, natHash); /*fix*/
        var callees = TrieMap.TrieMap<Callee, CalleeStatus> (Principal.equal, Principal.hash);
        var actuationThreads : Nat = 0;
        var lastActuationTime : Time.Time = 0;
        var countAsyncMessage : Nat = 0;
        // var receiption : ?CallType.Receipt = null;
        // public func getReceiption() : ?CallType.Receipt{
        //     return receiption;
        // };

        private func _push(_ttid: Ttid, _task: Task) : () {
            tasks := Deque.pushBack(tasks, (_ttid, _task));
        };
        private func _update(_ttid: Ttid, _task: Task) : () {
            assert(_ttid < index);
            ignore _remove(_ttid);
            _push(_ttid, _task);
        };
        private func _remove(_ttid: Ttid) : ?Ttid{
            let length: Nat = _size();
            if (length == 0){ return null; };
            var res: ?Ttid = null;
            for(i in Iter.range(1, length)){
                switch(Deque.popFront(tasks)){
                    case(?((ttid, task), deque)){
                        tasks := deque;
                        if (_ttid != ttid){
                            _push(ttid, task);
                        }else{
                            res := ?_ttid;
                        };
                    };
                    case(_){};
                };
            };
            return res;
        };
        private func _removeByOid(_toid: Toid) : [Ttid]{
            let length: Nat = _size();
            if (length == 0){ return []; };
            var res: [Ttid] = [];
            for(i in Iter.range(1, length)){
                switch(Deque.popFront(tasks)){
                    case(?((ttid, task), deque)){
                        tasks := deque;
                        if (_toid != Option.get(task.toid, 0)){
                            _push(ttid, task);
                        }else{
                            res := arrayAppend(res, [ttid]);
                        };
                    };
                    case(_){};
                };
            };
            return res;
        };
        private func _size() : Nat {
            return List.size(tasks.0) + List.size(tasks.1);
        };
        private func _toArray() : [(Ttid, Task)] {
            return arrayAppend(List.toArray(tasks.0), List.toArray(tasks.1));
        };
        private func _filter(_ttid: Ttid, _task: Task) : Bool {
            for (preTtid in _task.preTtid.vals()){
                if (preTtid > 0){
                    switch(taskLogs.get(preTtid)){
                        case(?(taskLog)){
                            if (taskLog.result.0 != #Done){ return false; };
                        };
                        case(_){ return false; };
                    };
                };
            };
            switch(taskLogs.get(_ttid)){
                case(?(taskLog)){
                    // if (taskLog.attempts+1 > _task.attemptsMax){
                    //     return false;
                    // };
                    if (Time.now() < taskLog.time + _task.recallInterval){
                        return false;
                    };
                };
                case(_){};
            };
            return true;
        };
        private func _preLog(_ttid: Ttid, _task: Task) : Attempts{
            var attempts: Attempts = 1;
            switch(taskLogs.get(_ttid)){
                case(?(taskLog)){
                    attempts := taskLog.attempts + 1;
                };
                case(_){};
            };
            let taskLog: TaskEvent = {
                toid = _task.toid;
                ttid = _ttid;
                task = _task;
                attempts = attempts;
                result = (#Doing, null, null);
                callbackStatus = ?#Todo;
                time = Time.now();
                txHash = Blob.fromArray([]);
            };
            taskLogs.put(_ttid, taskLog);
            return attempts;
        };
        private func _postLog(_ttid: Ttid, _result: TaskResult) : (){
            switch(taskLogs.get(_ttid)){
                case(?(taskLog)){
                    var log: TaskEvent = {
                        toid = taskLog.toid;
                        ttid = taskLog.ttid;
                        task = taskLog.task;
                        attempts = taskLog.attempts;
                        result = _result;
                        callbackStatus = null;
                        time = Time.now();
                        txHash = taskLog.txHash;
                    };
                    // let txHash = TaskHash.hashb(Blob.fromArray([]), log);
                    // log := {
                    //     toid = log.toid;
                    //     ttid = log.ttid;
                    //     task = log.task;
                    //     attempts = log.attempts;
                    //     result = log.result;
                    //     callbackStatus = log.callbackStatus;
                    //     time = log.time;
                    //     txHash = txHash;
                    // };
                    taskLogs.put(_ttid, log);
                    var calleeStatus = { successCount = 1; failureCount = 0; continuousFailure = 0;};
                    if (_result.0 == #Error or _result.0 == #Unknown){
                        calleeStatus := { successCount = 0; failureCount = 1; continuousFailure = 1;};
                        let errLog = { ttid = _ttid; callee = ?taskLog.task.callee; result = ?_result; time = Time.now(); };
                        errorLogs.put(errIndex, errLog);
                        errIndex += 1;
                    };
                    switch(callees.get(taskLog.task.callee)){
                        case(?(status)){
                            var successCount: Nat = status.successCount;
                            var failureCount: Nat = status.failureCount;
                            var continuousFailure: Nat = status.continuousFailure;
                            if (_result.0 == #Error or _result.0 == #Unknown){
                                failureCount += 1;
                                continuousFailure += 1;
                            }else{
                                successCount += 1;
                                continuousFailure := 0;
                            };
                            calleeStatus := {
                                successCount = successCount;
                                failureCount = failureCount;
                                continuousFailure = continuousFailure;
                            };
                        };
                        case(_){};
                    };
                    callees.put(taskLog.task.callee, calleeStatus);
                };
                case(_){
                    let errLog = { ttid = _ttid; callee = null; result = null; time = Time.now(); };
                    errorLogs.put(errIndex, errLog);
                    errIndex += 1;
                };
            };
        };
        private func _callbackLog(_ttid: Ttid, _callbackStatus: ?Status) : (){
            switch(taskLogs.get(_ttid)){
                case(?(taskLog)){
                    let log: TaskEvent = {
                        toid = taskLog.toid;
                        ttid = taskLog.ttid;
                        task = taskLog.task;
                        attempts = taskLog.attempts;
                        result = taskLog.result;
                        callbackStatus = _callbackStatus;
                        time = taskLog.time;
                        txHash = taskLog.txHash;
                    };
                    taskLogs.put(_ttid, log);
                };
                case(_){};
            };
        };
        private func _clear(_expiration: ?Int, _clearErr: Bool) : (){
            var clearTimeout: Int = Option.get(_expiration, 0);
            if (clearTimeout == 0 and autoClearTimeout > 0){
                clearTimeout := autoClearTimeout;
            }else if(clearTimeout == 0){
                return ();
            };
            var completed: Bool = false;
            var count: Nat = 0;
            while (firstIndex < index and count < 5000 and not(completed)){
                count += 1;
                switch(taskLogs.get(firstIndex)){
                    case(?(taskLog)){
                        if (Time.now() > taskLog.time + clearTimeout){
                            taskLogs.delete(firstIndex);
                            firstIndex += 1;
                        }else{
                            completed := true;
                        };
                    };
                    case(_){
                        firstIndex += 1;
                    };
                };
            };
            if (_clearErr){
                completed := false;
                count := 0;
                while (firstErrIndex < errIndex and count < 500 and not(completed)){
                    count += 1;
                    switch(errorLogs.get(firstErrIndex)){
                        case(?(taskLog)){
                            if (Time.now() > taskLog.time + clearTimeout){
                                errorLogs.delete(firstErrIndex);
                                firstErrIndex += 1;
                            }else{
                                completed := true;
                            };
                        };
                        case(_){
                            firstErrIndex += 1;
                        };
                    };
                };
            };
        };
        // private func _run() : async Nat {
        // };

        public func done(_ttid: Ttid, _toCallback: Bool) : async* ?Ttid{
            var status: Status = #Done;
            switch(taskLogs.get(_ttid)){
                case(?(log)){
                    if (log.result.0 != #Done){
                        if (_toCallback){
                            var callbackStatus: ?Status = null;
                            switch(agentCallback){
                                case(?(_agentCallback)){
                                    try{
                                        await* _agentCallback(_ttid, log.task, (#Done, null, null));
                                        callbackStatus := ?#Done;
                                    } catch(e){
                                        callbackStatus := ?#Error;
                                        status := #Error;
                                    };
                                };
                                case(_){
                                    switch(taskCallback){
                                        case(?(_taskCallback)){
                                            try{
                                                countAsyncMessage += 2;
                                                await _taskCallback("", _ttid, log.task, (#Done, null, null));
                                                callbackStatus := ?#Done;
                                                countAsyncMessage -= Nat.min(2, countAsyncMessage);
                                            } catch(e){
                                                callbackStatus := ?#Error;
                                                status := #Error;
                                                countAsyncMessage -= Nat.min(2, countAsyncMessage);
                                            };
                                        };
                                        case(_){};
                                    };
                                };
                            };
                            _callbackLog(_ttid, callbackStatus);
                        };
                        _postLog(_ttid, (status, null, null));
                        return ?_ttid;
                    } else {
                        return null;
                    };
                };
                case(_){ return null; };
            };
        };

        public func update(_ttid: Ttid, _task: Task) : Ttid {
            assert(_ttid > 0 and _ttid < index);
            _update(_ttid, _task);
            return _ttid;
        };
        public func push(_task: Task) : Ttid {
            var ttid = index;
            index += 1;
            _push(ttid, _task);
            return ttid;
        };
        public func remove(_ttid: Ttid) : ?Ttid{
            return _remove(_ttid);
        };
        public func removeByOid(_toid: Toid) : [Ttid]{
            return _removeByOid(_toid);
        };
        public func run() : async* Nat{
            return await* runSync(null);
        };
        public func runSync(_ttids: ?[Ttid]) : async* Nat{
            var size: Nat = _size();
            var count: Nat = 0;
            var callCount: Nat = 0;
            var receipt: ?CallType.Receipt = null;
            var ttids: [Ttid] = Option.get(_ttids, []);
            actuationThreads += 1;
            while (count < (if (ttids.size() == 0){ limitNum }else{ limitNum * 5 }) and callCount < size * 5 and Option.isSome(Deque.peekFront(tasks))){
                lastActuationTime := Time.now();
                switch(Deque.popFront(tasks)){
                    case(?((ttid, task_), deque)){
                        tasks := deque;
                        var task: Task = task_;
                        var toRedo: Bool = true;
                        if(_filter(ttid, task) and (_ttids == null or Option.isSome(Array.find(ttids, func (t: Ttid): Bool{ t == ttid })))){
                            //get receipt
                            switch(task.forTtid){
                                case(?(forTtid)){
                                    switch(taskLogs.get(forTtid)){
                                        case(?(taskLog)){
                                            receipt := taskLog.result.1;
                                        };
                                        case(_){};
                                    };
                                };
                                case(_){};
                            };
                            //receiption := receipt; // for test
                            //prelog
                            var attempts = _preLog(ttid, task); // attempts+1, set #Doing
                            //call
                            var domain: CallType.Domain = #Canister(task.callee, task.cycles);
                            switch(task.callType){
                                case(#This(method)){ domain := #Local(localCall); };
                                //case(#ThisAsync(method)){ domain := #Local(localCall); }; // /**comp**/
                                case(_){};
                            };
                            var result : TaskResult = (#Doing, null,null);
                            try{
                                countAsyncMessage += 2;
                                result := await* CallType.call(task.callType, domain, receipt);  // (Status, ?Receipt, ?Err)
                                countAsyncMessage -= Nat.min(2, countAsyncMessage);
                            }catch(e){ 
                                result := (#Error, null, ?{code = Error.code(e); message = Error.message(e); });
                                countAsyncMessage -= Nat.min(2, countAsyncMessage); 
                            };
                            lastActuationTime := Time.now();
                            var callbackStatus: ?Status = null;
                            var status: Status = result.0;
                            var errorMsg: ?CallType.Err = result.2;
                            if (status == #Done or status == #Unknown or attempts >= task.attemptsMax){
                                //callback
                                switch(agentCallback){
                                    case(?(_agentCallback)){
                                        try{
                                            await* _agentCallback(ttid, task, result);
                                            callbackStatus := ?#Done;
                                        } catch(e){
                                            callbackStatus := ?#Error;
                                            status := #Error;
                                            errorMsg := ?{code = Error.code(e); message = Error.message(e); };
                                        };
                                        lastActuationTime := Time.now();
                                    };
                                    case(_){
                                        switch(taskCallback){
                                            case(?(_taskCallback)){
                                                try{ // Unable to catch error. If an error occurs, the status of this task is #Doing, and does not exist in the TaskPool
                                                    countAsyncMessage += 2;
                                                    await _taskCallback("", ttid, task, result);
                                                    callbackStatus := ?#Done;
                                                    countAsyncMessage -= Nat.min(2, countAsyncMessage);
                                                } catch(e){
                                                    callbackStatus := ?#Error;
                                                    status := #Error;
                                                    errorMsg := ?{code = Error.code(e); message = Error.message(e); };
                                                    countAsyncMessage -= Nat.min(2, countAsyncMessage);
                                                };
                                                lastActuationTime := Time.now();
                                            };
                                            case(_){};
                                        };
                                    };
                                };
                                //postlog
                                result := (status, result.1, errorMsg);
                                _postLog(ttid, result);
                                //callbacklog
                                _callbackLog(ttid, callbackStatus);
                                toRedo := false;
                            };
                            callCount += 1;
                        };
                        //redo
                        if (toRedo){
                            _push(ttid, task);
                        };
                    };
                    case(_){};
                };
                count += 1;
            };
            //autoClear
            if (count < 20){
                _clear(null, false);
            };
            actuationThreads := 0;
            return callCount;
        };
        public func clear(_expiration: ?Int, _clearErr: Bool) : (){
            _clear(_expiration, _clearErr);
        };
        public func clearTasks() : (){
            tasks := Deque.empty<(Ttid, Task)>();
        };

        public func isInPool(_ttid: Ttid) : Bool{
            return Option.isSome(Array.find(_toArray(), func (item: (Ttid, Task)): Bool{ _ttid == item.0 }));
        };
        public func getTaskPool() : [(Ttid, Task)]{
            return _toArray();
        };
        public func getSize() : Nat{
            return _size();
        };
        public func actuations() : {actuationThreads: Nat; lastActuationTime: Time.Time; countAsyncMessage: Nat}{
            return {actuationThreads = actuationThreads; lastActuationTime = lastActuationTime; countAsyncMessage = countAsyncMessage };
        };
        
        public func isCompleted(_ttid: Ttid) : Bool{
            switch(taskLogs.get(_ttid)){
                case(?(log)){
                    if (log.result.0 == #Done){
                        return true;
                    } else {
                        return false;
                    };
                };
                case(_){ return false; };
            };
        };
        public func getTaskEvent(_ttid: Ttid) : ?TaskEvent{
            return taskLogs.get(_ttid);
        };
        
        public func getTaskEvents(_page: Nat, _size: Nat) : {data: [(Ttid, TaskEvent)]; totalPage: Nat; total: Nat}{
            return getTM<TaskEvent>(taskLogs, index, firstIndex, _page, _size);
        };
        public func getErrorLogs(_page: Nat, _size: Nat) : {data: [(Nat, ErrorLog)]; totalPage: Nat; total: Nat}{
            return getTM<ErrorLog>(errorLogs, errIndex, firstErrIndex, _page, _size);
        };
        public func calleeStatus(_callee: Callee) : ?CalleeStatus{
            return callees.get(_callee);
        };

        public func getData() : Data {
            return {
                tasks = tasks;
                taskLogs = Iter.toArray(taskLogs.entries());
                errorLogs = Iter.toArray(errorLogs.entries());
                callees = Iter.toArray(callees.entries());
                index = index;
                firstIndex = firstIndex;
                errIndex = errIndex;
                firstErrIndex = firstErrIndex;
            };
        };
        public func getDataBase() : Data {
            let _taskLogs = Iter.toArray(Iter.filter(taskLogs.entries(), func (x: (Ttid, TaskEvent)): Bool{
                x.1.time + 96*3600*1000000000 > Time.now() or x.1.result.0 == #Todo or x.1.result.0 == #Doing or 
                List.some(Iter.toList(errorLogs.vals()), func (v: ErrorLog): Bool{ x.0 == v.ttid })
            }));
            return {
                tasks = tasks;
                taskLogs = _taskLogs;
                errorLogs = Iter.toArray(errorLogs.entries());
                callees = Iter.toArray(callees.entries());
                index = index;
                firstIndex = firstIndex;
                errIndex = errIndex;
                firstErrIndex = firstErrIndex;
            };
        };
        public func setData(_data: Data) : (){
            tasks := _data.tasks;
            taskLogs := TrieMap.fromEntries(_data.taskLogs.vals(), Nat.equal, natHash);
            errorLogs := TrieMap.fromEntries(_data.errorLogs.vals(), Nat.equal, natHash);
            callees := TrieMap.fromEntries(_data.callees.vals(), Principal.equal, Principal.hash);
            index := _data.index;
            firstIndex := _data.firstIndex;
            errIndex := _data.errIndex;
            firstErrIndex := _data.firstErrIndex;
        };

    };
    
    
};