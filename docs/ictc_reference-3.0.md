# ICTC Reference

## Quickstart

### ICTC v3.0 (Saga) - Common implementations

- Imports SagaTM Module.

(use vessel package tool)
```
import SagaTM "mo:ictc/SagaTM";
```

- Custom CallType.
```
public type CustomCallType = { 
    // #This: {
    //     #foo : (Nat);
    // };
};
```

- (Optional) Implements callback functions for transaction orders and transaction tasks.
```
private func _taskCallback(_name: Text, _tid: SagaTM.Ttid, _task: SagaTM.Task<CustomCallType>, _result: SagaTM.TaskResult) : (){
    // do something
};
private func _orderCallback(_name: Text, _oid: SagaTM.Toid, _status: SagaTM.OrderStatus, _data: ?Blob) : (){
    // do something
};
```

- Implements local tasks. (Each task needs to be internally atomic or able to maintain data consistency.)
```
private func _localCall(_callee: Principal, _cycles: Nat, _args: SagaTM.CallType<CustomCallType>, _receipt: ?SagaTM.Receipt) : async (TaskResult){
    switch(_args){
        case(#custom(#This(method))){
            // switch(method){
            //    case(#foo(count)){
            //        var result = foo(count); // Receipt
            //        return (#Done, ?#result(?(Binary.BigEndian.fromNat64(Nat64.fromNat(result)), debug_show(result))), null);
            //    };
            // };
        };
        case(_){ return (#Error, null, ?{code=#future(9901); message="Non-local function."; });};
    };
};
```

- Creates a saga object.
```
let saga = SagaTM.SagaTM<CustomCallType>(Principal.fromActor(this), ?_localCall, ?_taskCallback, ?_orderCallback);
```

- Creates a transaction order. (Supports `Forward` and `Backward` modes)
```
let oid = saga.create("TO_name", #Forward, null, null);
```

- Pushs one or more transaction tasks to the specified transaction order.
```
let task: SagaTM.PushTaskRequest<CustomCallType> = { // for example
    callee = Principal.fromText("ryjl3-tyaaa-aaaaa-aaaba-cai");
    callType = #Ledger(#transfer(ledger_transferArgs)); // method to be called
    preTtid = []; // Pre-dependent tasks
    attemptsMax = ?1; // Maximum number of repeat attempts in case of exception
    recallInterval = ?0; // nanoseconds
    cycles = 0;
    data = null;
};
let tid1 = saga.push(oid, task, null, null);
```

- Executes the transaction order.
```
saga.close(oid);
let res = await saga.run(oid);
```

- Implements the upgrade function for SagaTM.
```
private stable var __sagaData: ?SagaTM.Data = null;
system func preupgrade() {
    let data = _getSaga().getData();
    __sagaData := ?data;
    // assert(List.size(data.actuator.tasks.0) == 0 and List.size(data.actuator.tasks.1) == 0);
};
system func postupgrade() {
    switch(__sagaData){
        case(?(data)){
            _getSaga().setData(data);
            __sagaData := null;
        };
        case(_){};
    };
};
```

### ICTC v3.0 (2PC)

- Imports SagaTM Module.

(use vessel package tool)
```
import TPCTM "mo:ictc/TPCTM";
```

- Custom CallType.
```
public type CustomCallType = { 
    // #This: {
    //     #foo : (Nat);
    // };
};
```

- (Optional) Implements callback functions for transaction orders and transaction tasks.
```
private func _taskCallback(_name: Text, _tid: TPCTM.Ttid, _task: TPCTM.Task<CustomCallType>, _result: TPCTM.TaskResult) : (){
    // do something
};
private func _orderCallback(_name: Text, _oid: TPCTM.Toid, _status: TPCTM.OrderStatus, _data: ?Blob) : (){
    // do something
};
```

- Implements local tasks. (Each task needs to be internally atomic or able to maintain data consistency.)
```
private func _localCall(_callee: Principal, _cycles: Nat, _args: TPCTM.CallType<CustomCallType>, _receipt: ?TPCTM.Receipt) : async (TPCTM.TaskResult){
    switch(_args){
        case(#custom(#This(method))){
            // switch(method){
            //     case(#foo(count)){
            //         var result = foo(count); // Receipt
            //         return (#Done, ?#result(?(Binary.BigEndian.fromNat64(Nat64.fromNat(result)), debug_show(result))), null);
            //     };
            // };
        };
        case(_){ return (#Error, null, ?{code=#future(9901); message="Non-local function."; });};
    };
};
```

- (Optional) Custom CallType.mo file.
Modify the CallType.mo file according to your local tasks and the external tasks you need to call.

- Creates a tpc object.
```
let tpc = TPCTM.TPCTM<CustomCallType>(Principal.fromActor(this), ?_localCall, ?_taskCallback, ?_orderCallback);
```

- Creates a transaction order. 
```
let oid = tpc.create("TO_name", null, null);
```

- Pushs one or more transaction tasks to the specified transaction order.
```
let prepare: TPCTM.TaskRequest<CustomCallType> = { // for example
    callee = token_canister;
    callType = #DRC20(#lockTransferFrom(caller, to, value, 5*60, null, null, null, null)); // method to be called
    preTtid = []; // Pre-dependent tasks
    attemptsMax = ?1; // Maximum number of repeat attempts in case of exception
    recallInterval = ?0; // nanoseconds
    cycles = 0;
    data = null;
};
let commit: TPCTM.TaskRequest<CustomCallType> = { // for example
    callee = token_canister;
    callType = #DRC20(#executeTransfer(#AutoFill, #sendAll, null, null, null, null)); // method to be called
    preTtid = []; // Pre-dependent tasks
    attemptsMax = ?1; // Maximum number of repeat attempts in case of exception
    recallInterval = ?0; // nanoseconds
    cycles = 0;
    data = null;
};
let tid1 = tpc.push(oid, prepare, commit, null, null, null);
```

- Executes the transaction order.
```
tpc.close(oid);
let res = await tpc.run(oid);
```

- Implements the upgrade function for TPCTM.
```
private stable var __tpcData: ?TPCTM.Data = null;
system func preupgrade() {
    let data = _getTPC().getData();
    __tpcData := ?data;
    // assert(List.size(data.actuator.tasks.0) == 0 and List.size(data.actuator.tasks.1) == 0);
};
system func postupgrade() {
    switch(__tpcData){
        case(?(data)){
            _getTPC().setData(data);
            __tpcData := null;
        };
        case(_){};
    };
};
```

## ICTC explorer

https://cmqwp-uiaaa-aaaaj-aihzq-cai.raw.ic0.app/

## Methods (API)

### ICTC(Saga)

```
public func create(_name: Text, _compStrategy: CompStrategy, _data: ?Blob, _callback: ?OrderCallback) : Toid

public func push(_toid: Toid, _task: PushTaskRequest, _comp: ?PushCompRequest, _callback: ?Callback) : Ttid

public func taskDone(_toid: Toid, _ttid: Ttid, _toCallback: Bool) : async* ?Ttid

public func redo(_toid: Toid, _ttid: Ttid) : ?Ttid

public func open(_toid: Toid) : ()

public func close(_toid: Toid) : ()

public func run(_toid: Toid) : async ?OrderStatus

public func runSync(_toid: Toid) : async ?OrderStatus

public func asyncMessageSize() : Nat

public func count() : Nat

public func status(_toid: Toid) : ?OrderStatus

public func isCompleted(_toid: Toid) : Bool

public func isTaskCompleted(_ttid: Ttid) : Bool

public func getOrder(_toid: Toid) : ?Order

public func getOrders(_page: Nat, _size: Nat) : {data: [(Toid, Order)]; totalPage: Nat; total: Nat}

public func getAliveOrders() : [(Toid, ?Order)]

public func getBlockingOrders() : [(Toid, Order)]

public func getTaskEvents(_toid: Toid) : [TaskEvent]

public func getActuator() : TA.TA

public func setCacheExpiration(_expiration: Int) : ()

public func clear(_expiration: ?Int, _delForced: Bool) : ()

public func update(_toid: Toid, _ttid: Ttid, _task: PushTaskRequest, _comp: ?PushCompRequest, _callback: ?Callback) : Ttid

public func remove(_toid: Toid, _ttid: Ttid) : ?Ttid

public func append(_toid: Toid, _task: PushTaskRequest, _comp: ?PushCompRequest, _callback: ?Callback) : Ttid

public func appendComp(_toid: Toid, _forTtid: Ttid, _comp: PushCompRequest, _callback: ?Callback) : Tcid

public func complete(_toid: Toid, _status: OrderStatus) : async* Bool

public func doneEmpty(_toid: Toid) : Bool

public func done(_toid: Toid, _status: OrderStatus, _toCallback: Bool) : async* Bool

public func block(_toid: Toid) : ?Toid

public func getData() : Data

public func setData(_data: Data) : ()
```

### ICTC(2PC)

```
public func create(_name: Text, _data: ?Blob, _callback: ?OrderCallback) : Toid

public func push(_toid: Toid, _prepare: TaskRequest, _commit: TaskRequest, _comp: ?TaskRequest, _prepareCallback: ?Callback, _commitCallback: ?Callback) : Ttid

public func taskDone(_toid: Toid, _ttid: Ttid, _toCallback: Bool) : async* ?Ttid

public func redo(_toid: Toid, _ttid: Ttid) : ?Ttid

public func open(_toid: Toid) : ()

public func close(_toid: Toid) : ()

public func run(_toid: Toid) : async ?OrderStatus

public func runSync(_toid: Toid) : async ?OrderStatus

public func asyncMessageSize() : Nat

public func count() : Nat

public func status(_toid: Toid) : ?OrderStatus

public func isCompleted(_toid: Toid) : Bool

public func isTaskCompleted(_ttid: Ttid) : Bool

public func getOrder(_toid: Toid) : ?Order

public func getOrders(_page: Nat, _size: Nat) : {data: [(Toid, Order)]; totalPage: Nat; total: Nat}

public func getAliveOrders() : [(Toid, ?Order)]

public func getBlockingOrders() : [(Toid, Order)]

public func getTaskEvents(_toid: Toid) : [TaskEvent]

public func getActuator() : TA.TA

public func setCacheExpiration(_expiration: Int) : ()

public func clear(_expiration: ?Int, _delForced: Bool) : ()

public func update(_toid: Toid, _ttid: Ttid, _prepare: TaskRequest, _commit: TaskRequest, _comp: ?TaskRequest, _prepareCallback: ?Callback, _commitCallback: ?Callback) : Ttid

public func remove(_toid: Toid, _ttid: Ttid) : ?Ttid

public func append(_toid: Toid, _prepare: TaskRequest, _commit: TaskRequest, _comp: ?TaskRequest, _prepareCallback: ?Callback, _commitCallback: ?Callback) : Ttid

public func appendComp(_toid: Toid, _forTtid: Ttid, _comp: TaskRequest, _callback: ?Callback) : Tcid

public func complete(_toid: Toid, _status: OrderStatus) : async* Bool

public func doneEmpty(_toid: Toid) : Bool

public func done(_toid: Toid, _status: OrderStatus, _toCallback: Bool) : async* Bool

public func block(_toid: Toid) : ?Toid

public func getData() : Data

public func setData(_data: Data) : ()
```