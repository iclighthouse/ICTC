/**
 * Module     : SyncTA.mo v0.2
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Description: ICTC Sync Task Actuator.
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
import Buffer "mo:base/Buffer";
import CallType "./CallType"; 
// import Call "mo:base/ExperimentalInternetComputer";

// As motoko does not currently support features such as candid encode/decode, call_raw and reflection, a temporary solution is used.
module {
    public let Version: Nat = 1;
    public type Domain = CallType.Domain;
    public type Status = CallType.Status;
    public type CallType = CallType.CallType;
    public type Receipt = CallType.Receipt;
    public type LocalCall = CallType.LocalCall;
    public type TaskResult = CallType.TaskResult;
    public type Callee = Principal;
    public type CalleeStatus = {
        successCount: Nat;
        failureCount: Nat;
        continuousFailure: Nat;
    };
    public type Ttid = Nat; // from 1
    public type Toid = Nat; // from 1
    public type Attempts = Nat;
    public type Task = {
        callee: Callee;
        callType: CallType;
        preTtid: [Ttid];
        toid: ?Toid;
        compFor: ?Ttid;
        attemptsMax: Attempts;
        recallInterval: Int; // nanoseconds
        cycles: Nat;
        data: ?Blob;
        time: Time.Time;
    };
    public type Callback = (_ttid: Ttid, _task: Task, _result: TaskResult) -> async ();
    public type TaskEvent = {
        toid: ?Toid;
        ttid: Ttid;
        task: Task;
        attempts: Attempts;
        result: TaskResult;  // (Status, ?Receipt, ?Err)
        callbackStatus: ?Status;
        time: Time.Time;
    };
    public type ErrorLog = { // errorLog
        ttid: Ttid;
        callee: ?Callee;
        result: ?TaskResult;
        time: Time.Time;
    };
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
        return buffer.toArray();
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
    
    /// limitAtOnce: The actuator runs `limitAtOnce` tasks at once.
    public class SyncTA(limitAtOnce: Nat, autoClearTimeout: Int, this: Principal, localCall: LocalCall, taskCallback: ?Callback) {
        var tasks = Deque.empty<(Ttid, Task)>();
        var index : Nat = 1;
        var firstIndex : Nat = 1;
        var taskLogs = TrieMap.TrieMap<Ttid, TaskEvent> (Nat.equal, Hash.hash);
        var errIndex : Nat = 1;
        var firstErrIndex : Nat = 1;
        var errorLogs = TrieMap.TrieMap<Nat, ErrorLog> (Nat.equal, Hash.hash);
        var callees = TrieMap.TrieMap<Callee, CalleeStatus> (Principal.equal, Principal.hash);
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
                callbackStatus = null;
                time = Time.now();
            };
            taskLogs.put(_ttid, taskLog);
            return attempts;
        };
        private func _postLog(_ttid: Ttid, _result: TaskResult) : (){
            switch(taskLogs.get(_ttid)){
                case(?(taskLog)){
                    let log: TaskEvent = {
                        toid = taskLog.toid;
                        ttid = taskLog.ttid;
                        task = taskLog.task;
                        attempts = taskLog.attempts;
                        result = _result;
                        callbackStatus = null;
                        time = Time.now();
                    };
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
            var moveFirstPointer: Bool = true;
            var i: Nat = firstIndex;
            while (i < index and not(completed)){
                switch(taskLogs.get(i)){
                    case(?(taskLog)){
                        if (Time.now() > taskLog.time + clearTimeout and taskLog.result.0 != #Todo and taskLog.result.0 != #Doing){
                            taskLogs.delete(i);
                            i += 1;
                        }else if (Time.now() > taskLog.time + clearTimeout){
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
            if (_clearErr){
                completed := false;
                while (firstErrIndex < errIndex and not(completed)){
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
        private func _run() : async Nat {
            var size: Nat = _size();
            var count: Nat = 0;
            var callCount: Nat = 0;
            var receipt: ?CallType.Receipt = null;
            while (count < limitAtOnce and callCount < size * 2 and Option.isSome(Deque.peekFront(tasks))){
                switch(Deque.popFront(tasks)){
                    case(?((ttid, task), deque)){
                        tasks := deque;
                        var toRedo: Bool = true;
                        if(_filter(ttid, task)){
                            //get receipt
                            switch(task.compFor){
                                case(?(compForTid)){
                                    switch(taskLogs.get(compForTid)){
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
                            var attempts = _preLog(ttid, task); // attempts+1
                            //call
                            var domain: CallType.Domain = #Canister(task.callee, task.cycles);
                            switch(task.callType){
                                case(#This(method)){ domain := #Local(localCall); };
                                case(_){};
                            };
                            let result = await CallType.call(task.callType, domain, receipt);  // (Status, ?Receipt, ?Err)
                            if (result.0 != #Error or attempts >= task.attemptsMax){
                                //callback
                                var callbackStatus: ?Status = null;
                                switch(taskCallback){
                                    case(?(_taskCallback)){
                                        try{
                                            await _taskCallback(ttid, task, result);
                                            callbackStatus := ?#Done;
                                        } catch(e){
                                            callbackStatus := ?#Error;
                                        };
                                    };
                                    case(_){};
                                };
                                //postlog
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
                        //autoClear
                        _clear(null, false);
                        count += 1;
                    };
                    case(_){};
                };
            };
            return callCount;
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
        public func run() : async Nat{
            return await _run();
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
        public func setData(_data: Data) : (){
            tasks := _data.tasks;
            taskLogs := TrieMap.fromEntries(_data.taskLogs.vals(), Nat.equal, Hash.hash);
            errorLogs := TrieMap.fromEntries(_data.errorLogs.vals(), Nat.equal, Hash.hash);
            callees := TrieMap.fromEntries(_data.callees.vals(), Principal.equal, Principal.hash);
            index := _data.index;
            firstIndex := _data.firstIndex;
            errIndex := _data.errIndex;
            firstErrIndex := _data.firstErrIndex;
        };

    };
    
    
};