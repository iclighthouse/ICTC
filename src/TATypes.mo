import CallType "./CallType";
import Time "mo:base/Time";
module {
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
        forTtid: ?Ttid;
        attemptsMax: Attempts;
        recallInterval: Int; // nanoseconds
        cycles: Nat;
        data: ?Blob;
        time: Time.Time;
    };
    public type AgentCallback = (_ttid: Ttid, _task: Task, _result: TaskResult) -> async* ();
    public type Callback = (_toName: Text, _ttid: Ttid, _task: Task, _result: TaskResult) -> async ();
    public type TaskEvent = {
        toid: ?Toid;
        ttid: Ttid;
        task: Task;
        attempts: Attempts;
        result: TaskResult;  // (Status, ?Receipt, ?Err)
        callbackStatus: ?Status;
        time: Time.Time;
        txHash: Blob;
    };
    public type ErrorLog = { // errorLog
        ttid: Ttid;
        callee: ?Callee;
        result: ?TaskResult;
        time: Time.Time;
    };
};