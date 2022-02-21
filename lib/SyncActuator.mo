/**
 * Module     : SyncActuator.mo v0.1
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Description: ICTC Task SyncActuator.
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
import CallType "./CallType"; 
// import Call "mo:base/ExperimentalInternetComputer";

// As motoko does not currently support features such as candid encode/decode, call_raw and reflection, a temporary solution is used.
module {
    public let Version: Nat = 1;
    public type CallType = CallType.CallType;
    public type Callee = Principal;
    public type CalleeStatus = {
        successCount: Nat;
        failureCount: Nat;
        continuousFailure: Nat;
    };
    public type Tid = Nat; // from 1
    public type Attempts = Nat;
    public type Task = {
        callee: Callee;
        callType: CallType;
        attemptsMax: Attempts;
        recallInterval: Int; // nanoseconds
        preTid: ?Tid;
        data: ?Blob;
        time: Time.Time;
    };
    public type Callback = (_tid: Tid, _task: Task, _result: CallType.TaskResult) -> async ();
    public type TaskLog = {
        task: Task;
        callback: ?Callback;
        attempts: Attempts;
        result: CallType.TaskResult;  // (Status, ?Receipt, ?Err)
        callbackStatus: ?CallType.Status;
        time: Time.Time;
    };
    public type ErrorLog = { // errorLog
        tid: Tid;
        callee: ?Callee;
        message: Text;
        time: Time.Time;
    };
    
    /// tasksAtOnce: The actuator runs `tasksAtOnce` tasks at once.
    public class SyncActuator(tasksAtOnce: Nat) {
        let autoClearTimeout: Int = 3*30*24*3600*1000000000; // 3 months
        var tasks = Deque.empty<(Tid, Task, ?Callback)>();
        var index : Nat = 1;
        var firstIndex : Nat = 1;
        var taskLogs = TrieMap.TrieMap<Tid, TaskLog> (Nat.equal, Hash.hash);
        var errIndex : Nat = 1;
        var firstErrIndex : Nat = 1;
        var errorLogs = TrieMap.TrieMap<Nat, ErrorLog> (Nat.equal, Hash.hash);
        var callees = TrieMap.TrieMap<Callee, CalleeStatus> (Principal.equal, Principal.hash);

        private func _push(_tid: Tid, _task: Task, _callback: ?Callback) : () {
            tasks := Deque.pushBack(tasks, (_tid, _task, _callback));
        };
        private func _update(_tid: Tid, _task: Task, _callback: ?Callback) : () {
            assert(_tid < index);
            ignore _remove(_tid);
            _push(_tid, _task, _callback);
        };
        private func _remove(_tid: Tid) : ?Tid{
            let length: Nat = _size();
            if (length == 0){ return null; };
            var res: ?Tid = null;
            for(i in Iter.range(1, length)){
                switch(Deque.popFront(tasks)){
                    case(?((tid, task, callback), deque)){
                        tasks := deque;
                        if (_tid != tid){
                            _push(tid, task, callback);
                        }else{
                            res := ?_tid;
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
        private func _toArray() : [(Tid, Task, ?Callback)] {
            return Array.append(List.toArray(tasks.0), List.toArray(tasks.1));
        };
        private func _filter(_tid: Tid, _task: Task) : Bool {
            switch(_task.preTid){
                case(?(preTid)){
                    switch(taskLogs.get(preTid)){
                        case(?(taskLog)){
                            if (taskLog.result.0 != #Done){ return false; };
                        };
                        case(_){ return false; };
                    };
                };
                case(_){};
            };
            switch(taskLogs.get(_tid)){
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
        private func _preLog(_tid: Tid, _task: Task, _callback: ?Callback) : Attempts{
            var attempts: Attempts = 1;
            switch(taskLogs.get(_tid)){
                case(?(taskLog)){
                    attempts := taskLog.attempts + 1;
                };
                case(_){};
            };
            let taskLog: TaskLog = {
                task = _task;
                callback = _callback;
                attempts = attempts;
                result = (#Doing, null, null);
                callbackStatus = null;
                time = Time.now();
            };
            taskLogs.put(_tid, taskLog);
            return attempts;
        };
        private func _postLog(_tid: Tid, _result: CallType.TaskResult, _callbackStatus: ?CallType.Status) : (){
            switch(taskLogs.get(_tid)){
                case(?(taskLog)){
                    let log: TaskLog = {
                        task = taskLog.task;
                        callback = taskLog.callback;
                        attempts = taskLog.attempts;
                        result = _result;
                        callbackStatus = _callbackStatus;
                        time = Time.now();
                    };
                    taskLogs.put(_tid, log);
                    var calleeStatus = { successCount = 1; failureCount = 0; continuousFailure = 0;};
                    if (_result.0 == #Error or _result.0 == #Unknown){
                        calleeStatus := { successCount = 0; failureCount = 1; continuousFailure = 1;};
                        let errLog = { tid = _tid; callee = ?taskLog.task.callee; message = "Calling error."; time = Time.now(); };
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
                    let errLog = { tid = _tid; callee = null; message = "No pre-log exists."; time = Time.now(); };
                    errorLogs.put(errIndex, errLog);
                    errIndex += 1;
                };
            };
        };
        private func _clear(_expiration: ?Int) : (){
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
        private func _run() : async Nat {
            var size: Nat = _size();
            var count: Nat = 0;
            while (count < tasksAtOnce and count < size and Option.isSome(Deque.peekFront(tasks))){
                switch(Deque.popFront(tasks)){
                    case(?((tid, task, callback), deque)){
                        tasks := deque;
                        var toRedo: Bool = true;
                        if(_filter(tid, task)){
                            //prelog
                            var attempts = _preLog(tid, task, callback);
                            //call
                            let result = await CallType.call(task.callType, task.callee);  // (Status, ?Receipt, ?Err)
                            //callback
                            var callbackStatus: ?CallType.Status = null;
                            switch(callback){
                                case(?(callback_)){
                                    try{
                                        await callback_(tid, task, result);
                                        callbackStatus := ?#Done;
                                    } catch(e){
                                        callbackStatus := ?#Error;
                                    };
                                };
                                case(_){};
                            };
                            //postlog
                            _postLog(tid, result, callbackStatus);
                            if (attempts >= task.attemptsMax){
                                toRedo := false;
                            } else if (result.0 != #Error){
                                toRedo := false;
                            };
                        };
                        //redo
                        if (toRedo){
                            _push(tid, task, callback);
                        };
                        //autoClear
                        _clear(null);
                        count += 1;
                    };
                    case(_){};
                };
            };
            return count;
        };

        public func put(_tid: ?Tid, _callee: Callee, _callType: CallType, _callback: ?Callback, 
        _setting: ?{attempts: ?Attempts; recallInterval: ?Int; preTid: ?Tid; data: ?Blob}) : Tid {
            var act: {#Push; #Update} = #Push;
            var tid = 0;
            if (Option.isSome(_tid)){
                act := #Update;
                tid := Option.get(_tid, 0);
                assert(tid < index);
            }else{
                tid := index; 
                index += 1;
            };
            let setting = Option.get(_setting, {attempts = ?1; recallInterval = ?0; preTid = null; data = null});
            let task = {
                callee = _callee;
                callType = _callType;
                attemptsMax = Option.get(setting.attempts, 1);
                recallInterval = Option.get(setting.recallInterval, 0); // nanoseconds
                preTid = setting.preTid;
                data = setting.data;
                time = Time.now();
            };
            if (act == #Push){
                _push(tid, task, _callback);
            } else {
                _update(tid, task, _callback);
            };
            return tid;
        };
        public func push(_callee: Callee, _callType: CallType, _callback: ?Callback, 
        _setting: ?{attempts: ?Attempts; recallInterval: ?Int; preTid: ?Tid; data: ?Blob}) : Tid {
            return put(null, _callee, _callType, _callback, _setting);
        };
        public func remove(_tid: Tid) : ?Tid{
            return _remove(_tid);
        };
        public func run() : async Nat{
            return await _run();
        };
        public func clear(_expiration: ?Int) : (){
            _clear(_expiration);
        };
        public func getTaskPool() : [(Tid, Task, ?Callback)]{
            return _toArray();
        };
        public func getTaskLog(_tid: Tid) : ?TaskLog{
            return taskLogs.get(_tid);
        };
        public func getTaskLogs(_page: Nat, _size: Nat) : {data: [(Tid, TaskLog)]; totalPage: Nat; total: Nat}{
            assert(_page > 0 and _size > 0);
            let length = taskLogs.size();
            let offset = Nat.sub(_page, 1) * _size;
            var start: Nat = 0;
            var end: Nat = 0;
            if (offset < Nat.sub(index,1)){
                start := Nat.sub(Nat.sub(index,1), offset);
                if (start < firstIndex){
                    return {data = []; totalPage = 0; total = length; };
                };
                if (start > Nat.sub(_size, 1)){
                    end := Nat.max(Nat.sub(start, Nat.sub(_size, 1)), firstIndex);
                }else{
                    end := firstIndex;
                };
            }else{
                return {data = []; totalPage = 0; total = length; };
            };
            var data: [(Tid, TaskLog)] = [];
            for (i in Iter.range(end, start)){
                switch(taskLogs.get(i)){
                    case(?(taskLog)){
                        data := Array.append(data, [(i, taskLog)]);
                    };
                    case(_){};
                };
            };
            var totalPage: Nat = length / _size;
            if (totalPage * _size < length) { totalPage += 1; };
            return {data = data; totalPage = totalPage; total = length; };
        };
        public func getErrorLogs(_page: Nat, _size: Nat) : {data: [(Nat, ErrorLog)]; totalPage: Nat; total: Nat}{
            assert(_page > 0 and _size > 0);
            let length = errorLogs.size();
            let offset = Nat.sub(_page, 1) * _size;
            var start: Nat = 0;
            var end: Nat = 0;
            if (offset < Nat.sub(errIndex,1)){
                start := Nat.sub(Nat.sub(errIndex,1), offset);
                if (start < firstErrIndex){
                    return {data = []; totalPage = 0; total = length; };
                };
                if (start > Nat.sub(_size, 1)){
                    end := Nat.max(Nat.sub(start, Nat.sub(_size, 1)), firstErrIndex);
                }else{
                    end := firstErrIndex;
                };
            }else{
                return {data = []; totalPage = 0; total = length; };
            };
            var data: [(Nat, ErrorLog)] = [];
            for (i in Iter.range(end, start)){
                switch(errorLogs.get(i)){
                    case(?(errorLog)){
                        data := Array.append(data, [(i, errorLog)]);
                    };
                    case(_){};
                };
            };
            var totalPage: Nat = length / _size;
            if (totalPage * _size < length) { totalPage += 1; };
            return {data = data; totalPage = totalPage; total = length; };
        };
        public func calleeStatus(_callee: Callee) : ?CalleeStatus{
            return callees.get(_callee);
        };

        public func getData() : {tasks: Deque.Deque<(Tid, Task, ?Callback)>; taskLogs: [(Tid, TaskLog)]; 
        errorLogs: [(Nat, ErrorLog)]; callees: [(Callee, CalleeStatus)]; index: Nat; firstIndex: Nat; errIndex: Nat; firstErrIndex: Nat; } {
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
        public func setData(_data: {tasks: Deque.Deque<(Tid, Task, ?Callback)>; taskLogs: [(Tid, TaskLog)]; errorLogs: [(Nat, ErrorLog)]; 
        callees: [(Callee, CalleeStatus)]; index: Nat; firstIndex: Nat; errIndex: Nat; firstErrIndex: Nat; }) : (){
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