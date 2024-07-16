# ICTC 

## Abstract

IC Transaction Coordinator (ICTC) is a distributed transaction framework for Defi applications on IC network. It supports Motoko language. The core idea of ICTC is inspired by the DTC (Distributed Transaction Coordinator), which is commonly used in the financial sector.

## Motivation

Developing dapps based on IC networks, especially Defi applications, we have to face the problem of atomicity, which is essentially a data consistency problem for distributed transactions. The biggest challenge facing distributed transactions on blockchain networks compared to traditional distributed transactions is the different assumption of trust in the participating entities. While traditional distributed transactions are based on trustworthiness assumptions for participating entities, distributed transactions on blockchain networks are based on untrustworthiness assumptions for participating entities, and it only trusts smart contract code. 

When a method in Canister needs to execute a cross-container call, it will face the threat of inconsistent data due to a fault in the callee. Three types of faults may occur.

- Business error: e.g. insufficient token balance.
- Runtime error: e.g. divide-by-0 error.
- Fail-stop: e.g. the subnet where the callee is located is inaccessible.

The IC network is free from fail-stop most of the time, but there is still the potential for this type of failures to occur. If the Defi application cannot robustly handle failures and maintain eventual consistency, the consequences could be catastrophic. 

So we need a new framework that requires a concerted effort from both the caller and the callee to provide features that support the execution of distributed transactions. ICTC is based on [Base: An Acid Alternative](https://queue.acm.org/detail.cfm?id=1394128), and seeks eventual consistency of data in cross-canister transactions. Unfortunately, ICTC can only achieve "best-effort delivery" and requires governance compensation or manual compensation mechanisms as a final guarantee to achieve eventual consistency.

ICTC requires that each participant achieves.

- The callee achieves internal task atomicity
- The callee implements functionality to meet eventual consistency as appropriate, including
    - Allowing retries (requires idempotency)
    - Use Nonce (guarantees orderly execution of txns, idempotency)
    - Txid is globally unique and can be pre-calculated (txid can be calculated before sending a txn)
    - Provision of reversal transaction functions (rollback operations)
- Caller takes a variety of ways to achieve eventual consistency, including
    - Retries
    - Automatic reversal transaction
    - Governance or manual reversal transaction
- Debit first, credit later principle (receive first, freezable txn first)
- Caller-led principle (the caller acts as coordinator)


## Technology Architecture

ICTC consists of Transaction Manager (TM), Task Actuator (TA), and Transaction Compensator (TC).

Transaction Order: A transaction, including one or more transaction tasks, that requires all tasks to be either fully successful or fully rejected.   
Transaction Task: A task within a transaction, including local tasks of the caller and remote tasks of other parties involved.

![ICTC](img/ictc.jpg)

## Task Actuator

The Task Actuator uses a "best-effort delivery" policy and will definitely return a result (success/failure). 

![Task Actuator](img/ictc-ta.png)

## Transaction Manager

The Transaction Manager is used to manage the status of transactions, operate the Actuator, handle exceptions and call the Compensator. Transaction Manager implementation includes the Saga Transaction Manager (SagaTM) and the 2PC Transaction Manager (TPCTM).

**Saga Transaction Manager**

![Saga Transaction Manager](img/ictc-saga.png)

**2PC Transaction Manager**

![2PC Transaction Manager](img/ictc-2pc.png)

## Transaction Compensator

The Transaction Compensator function is implemented in Transaction Manager and is used to execute compensation operations when an exception occurs in a transaction, including automatic compensation, governance or manual compensation.

## Roadmap

- ICTC Framework PoC Version  (done)
- Synchronous Actuator  (done)
- Saga Transaction Manager  (done)
- ICTC Framework Alpha Version  (done)
- Transaction Actuator (done)
- 2PC Transaction Manager (done)
- ICTC Framework Beta Version (done)
- ICTC Framework v1.0 (done)
- ICTC Framework v1.5  (done)
- ICTC Framework v2.0  (done)
- ICTC Framework v3.0  (done)

## Reference Docs

Note: Version 3.0 is not compatible with version 2.0 and requires refactoring your code to upgrade.

[ICTC v3.0 Reference](./docs/ictc_reference-3.0.md)

[ICTC v2.0 Reference](./docs/ictc_reference-2.0.md)

[ICTC v1.5 Reference](./docs/ictc_reference-1.5.md)

[ICTC v1.0 Reference](./docs/ictc_reference.md)

## Use in vessel

package-set.dhall
```
    ...
    { dependencies = [ "base", "icl" ] : List Text
    , name = "ictc"
    , repo = "https://github.com/iclighthouse/ICTC"
    , version = "-- commit hash --"
    }
    ...
```

vessel.dhall
```
    {
    dependencies = [ "base", "icl", "ictc" ],
    compiler = None Text
    }
```

motoko
```
import CallType "mo:ictc/CallType";
import TA "mo:ictc/TA";
import SagaTM "mo:ictc/SagaTM";
```

## ICTC explorer

https://cmqwp-uiaaa-aaaaj-aihzq-cai.raw.ic0.app/

## Examples

```
public shared(msg) func foo(): async (SagaTM.Toid, ?SagaTM.OrderStatus){
    let valueA: Nat = 100000000; // TokenA
    let valueB: Nat = 200000000; // TokenB
    let tokenFee: Nat = 100000; // TokenA & TokenB
    let owner: Text = Principal.toText(msg.caller);
    let to: Text = "xxxxx(principal)xxxxx";
    let contract: Text =  Principal.toText(Principal.fromActor(this));

    // Create a Saga transaction order (TO).
    let oid = _getSaga().create("swap", #Forward, null, null); 

    // Push tasks into TO.
    var task = _buildTask(null, tokenA_canister, #DRC20(#drc20_transferFrom(owner, contract, valueA+tokenFee, null, null, null)), []);
    let _tid1 =_getSaga().push(oid, task, null, null); 
    task := _buildTask(null, tokenB_canister, #DRC20(#drc20_transferFrom(to, contract, valueB+tokenFee, null, null, null)), []);
    let _tid2 =_getSaga().push(oid, task, null, null);
    task := _buildTask(null, Principal.fromActor(this), #custom(#This(#foo(1))), []);
    let _tid3 =_getSaga().push(oid, task, null, null);
    task := _buildTask(null, tokenA_canister, #DRC20(#drc20_transfer(to, valueA, null, null, null)), []);
    let _tid4 =_getSaga().push(oid, task, null, null);
    task := _buildTask(null, tokenB_canister, #DRC20(#drc20_transfer(owner, valueB, null, null, null)), []);
    let _tid5 =_getSaga().push(oid, task, null, null);

    // After this, no further push tasks are allowed.
    _getSaga().close(oid); 

    // Execute the transaction order (TO), where all tasks are executed sequentially and synchronously, and if one of the tasks is failed, the whole TO will be suspended and marked as "Blocking".
    let res = await _getSaga().run(oid); 
    
    return (oid, res);
};
```

### Example.mo (Saga)

[./examples/Example.mo](./examples/Example.mo)

### Example2PC.mo (2PC)

[./examples/Example2PC.mo](./examples/Example2PC.mo)

## Powering projects

- [ICDex](http://icdex.io) (Orderbook DEX)
- [ICSwap](http://icswap.io) (AMM DEX)

## Community

Twitter: [@ICLighthouse](https://twitter.com/ICLighthouse)   
Medium: [https://medium.com/@ICLighthouse](https://medium.com/@ICLighthouse)  
Discord: [https://discord.gg/FQZFGGq7zv](https://discord.gg/FQZFGGq7zv)  