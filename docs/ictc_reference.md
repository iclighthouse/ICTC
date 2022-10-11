# ICTC Reference

## Quickstart

### ICTC(Saga) - Common implementations

- Imports SagaTM Module.
```
import SagaTM "./src/SagaTM";
```

- (Optional) Implements callback functions for transaction orders and transaction tasks.
```
private func _taskCallback(_tid: SagaTM.Ttid, _task: SagaTM.Task, _result: SagaTM.TaskResult) : async (){
    // do something
};
private func _orderCallback(_oid: SagaTM.Toid, _status: SagaTM.OrderStatus, _data: ?Blob) : async (){
    // do something
};
```

- Implements local tasks. (Each task needs to be internally atomic or able to maintain data consistency.)
```
private func _local(_args: SagaTM.CallType, _receipt: ?SagaTM.Receipt) : async (SagaTM.TaskResult){
    switch(_args){
        case(#This(method)){
            // switch(method){
            //     case(#local_method_name(args)){
            //         // ...
            //     };
            // };
        };
        case(_){ return (#Error, null, ?{code=#future(9901); message="Non-local function."; });};
    };
};
```
Example:
```
private var x : Nat = 0;
private func foo(count: Nat) : (){
    x += 100;
};
private func _local(_args: SagaTM.CallType, _receipt: ?SagaTM.Receipt) : async (SagaTM.TaskResult){
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
```

- (Optional) Custom CallType.mo file.
Modify the CallType.mo file according to your local tasks and the external tasks you need to call.

- Creates a saga object.
```
let saga = SagaTM.SagaTM(Principal.fromActor(this), _local, ?_taskCallback, ?_orderCallback);
```

- Creates a transaction order. (Supports `Forward` and `Backward` modes)
```
let oid = saga.create("TO_name", #Forward, null, null);
```

- Pushs one or more transaction tasks to the specified transaction order.
```
let task: SagaTM.PushTaskRequest = { // for example
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
saga.finish(oid);
let res = await saga.run(oid);
```

- Implements the upgrade function for SagaTM.
```
private stable var __sagaData: [SagaTM.Data] = [];
system func preupgrade() {
    __sagaData := TA.arrayAppend(__sagaData, [_getSaga().getData()]);
};
system func postupgrade() {
    if (__sagaData.size() > 0){
        _getSaga().setData(__sagaData[0]);
        __sagaData := [];
    };
};
```

### ICTC(2PC)

- Imports TPCTM Module.
```
import TPCTM "./src/TPCTM";
```

- (Optional) Implements callback functions for transaction orders and transaction tasks.
```
private func _taskCallback(_tid: TPCTM.Ttid, _task: TPCTM.Task, _result: TPCTM.TaskResult) : async (){
    // do something
};
private func _orderCallback(_oid: TPCTM.Toid, _status: TPCTM.OrderStatus, _data: ?Blob) : async (){
    // do something
};
```

- Implements local tasks. (Each task needs to be internally atomic or able to maintain data consistency.)
```
private func _local(_args: TPCTM.CallType, _receipt: ?TPCTM.Receipt) : async (TPCTM.TaskResult){
    switch(_args){
        case(#This(method)){
            // switch(method){
            //     case(#local_method_name(args)){
            //         // ...
            //     };
            // };
        };
        case(_){ return (#Error, null, ?{code=#future(9901); message="Non-local function."; });};
    };
};
```
Example:
```
private var x : Nat = 0;
private func foo(count: Nat) : (){
    x += 100;
};
private func _local(_args: TPCTM.CallType, _receipt: ?TPCTM.Receipt) : async (TPCTM.TaskResult){
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
```

- (Optional) Custom CallType.mo file.
Modify the CallType.mo file according to your local tasks and the external tasks you need to call.

- Creates a tpc object.
```
let tpc = TPCTM.TPCTM(Principal.fromActor(this), _local, ?_taskCallback, ?_orderCallback);
```

- Creates a transaction order. 
```
let oid = tpc.create("TO_name", null, null);
```

- Pushs one or more transaction tasks to the specified transaction order.
```
let prepare: TPCTM.TaskRequest = { // for example
    callee = token_canister;
    callType = #DRC20(#lockTransferFrom(caller, to, value, 5*60, null, null, null, null)); // method to be called
    preTtid = []; // Pre-dependent tasks
    attemptsMax = ?1; // Maximum number of repeat attempts in case of exception
    recallInterval = ?0; // nanoseconds
    cycles = 0;
    data = null;
};
let commit: TPCTM.TaskRequest = { // for example
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
tpc.finish(oid);
let res = await tpc.run(oid);
```

- Implements the upgrade function for TPCTM.
```
private stable var __tpcData: [TPCTM.Data] = [];
system func preupgrade() {
    __tpcData := TA.arrayAppend(__tpcData, [_getTPC().getData()]);
};
system func postupgrade() {
    if (__tpcData.size() > 0){
        _getTPC().setData(__tpcData[0]);
        __tpcData := [];
    };
};
```

## Methods (API)

### ICTC(Saga)

```
public func create (_name: Text, _compStrategy: CompStrategy, _data: ?Blob, _callback: ?OrderCallback) : Toid

public func push(_toid: Toid, _task: PushTaskRequest, _comp: ?PushCompRequest, _callback: ?Callback) : Ttid

public func open(_toid: Toid) : ()

public func finish(_toid: Toid) : ()

public func run(_toid: Toid) : async ?OrderStatus

public func count() : Nat

public func status(_toid: Toid) : ?OrderStatus

public func isCompleted(_toid: Toid) : Bool

public func isTaskCompleted(_ttid: Ttid) : Bool

public func getOrder(_toid: Toid) : ?Order

public func getOrders(_page: Nat, _size: Nat) : {data: [(Toid, Order)]; totalPage: Nat; total: Nat}

public func getAliveOrders() : [(Toid, ?Order)]

public func getTaskEvents(_toid: Toid) : [TaskEvent]

public func getActuator() : TA.TA

public func setCacheExpiration(_expiration: Int) : ()

public func clear(_delExc: Bool) : ()

public func update(_toid: Toid, _ttid: Ttid, _task: PushTaskRequest, _comp: ?PushCompRequest, _callback: ?Callback) : Ttid

public func remove(_toid: Toid, _ttid: Ttid) : ?Ttid

public func append(_toid: Toid, _task: PushTaskRequest, _comp: ?PushCompRequest, _callback: ?Callback) : Ttid

public func appendComp(_toid: Toid, _forTtid: Ttid, _comp: PushCompRequest, _callback: ?Callback) : Tcid

public func complete(_toid: Toid, _status: OrderStatus) : async Bool

public func getData() : Data

public func setData(_data: Data) : ()
```

### ICTC(2PC)

```
public func create(_name: Text, _data: ?Blob, _callback: ?OrderCallback) : Toid

public func push(_toid: Toid, _prepare: TaskRequest, _commit: TaskRequest, _comp: ?TaskRequest, _prepareCallback: ?Callback, _commitCallback: ?Callback) : Ttid

public func open(_toid: Toid) : ()

public func finish(_toid: Toid) : ()

public func run(_toid: Toid) : async ?OrderStatus

public func count() : Nat

public func status(_toid: Toid) : ?OrderStatus

public func isCompleted(_toid: Toid) : Bool

public func isTaskCompleted(_ttid: Ttid) : Bool

public func getOrder(_toid: Toid) : ?Order

public func getOrders(_page: Nat, _size: Nat) : {data: [(Toid, Order)]; totalPage: Nat; total: Nat}

public func getAliveOrders() : [(Toid, ?Order)]

public func getTaskEvents(_toid: Toid) : [TaskEvent]

public func getActuator() : TA.TA

public func setCacheExpiration(_expiration: Int) : ()

public func clear(_delExc: Bool) : ()

public func update(_toid: Toid, _ttid: Ttid, _prepare: TaskRequest, _commit: TaskRequest, _comp: ?TaskRequest, _prepareCallback: ?Callback, _commitCallback: ?Callback) : Ttid

public func remove(_toid: Toid, _ttid: Ttid) : ?Ttid

public func append(_toid: Toid, _prepare: TaskRequest, _commit: TaskRequest, _comp: ?TaskRequest, _prepareCallback: ?Callback, _commitCallback: ?Callback) : Ttid

public func appendComp(_toid: Toid, _forTtid: Ttid, _comp: TaskRequest, _callback: ?Callback) : Tcid

public func complete(_toid: Toid, _status: OrderStatus) : async Bool

public func getData() : Data

public func setData(_data: Data) : ()
```