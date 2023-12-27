import CallType "./CallType";
import Time "mo:base/Time";
module {
    public type Status = CallType.Status;
    public type CallType<T> = CallType.CallType<T>;
    public type Receipt = CallType.Receipt;
    public type CustomCall<T> = CallType.CustomCall<T>;
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
    public type Task<T> = {
        callee: Callee;
        callType: CallType<T>;
        preTtid: [Ttid];
        toid: ?Toid;
        forTtid: ?Ttid;
        attemptsMax: Attempts;
        recallInterval: Int; // nanoseconds
        cycles: Nat;
        data: ?Blob;
        time: Time.Time;
    };
    public type AgentCallback<T> = (_ttid: Ttid, _task: Task<T>, _result: TaskResult) -> async* ();
    public type TaskCallback<T> = (_toName: Text, _ttid: Ttid, _task: Task<T>, _result: TaskResult) -> async ();
    public type TaskEvent<T> = {
        toid: ?Toid;
        ttid: Ttid;
        task: Task<T>;
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