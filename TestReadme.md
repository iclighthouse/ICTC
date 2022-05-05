# Example
Functional testing of ICTC Asynchronous Actuator (SyncTA) + Saga Manager (SagaTM)

## Code
Example: Example.mo  
TokenA: token/TokenA.mo  
TokenB: token/TokenB.mo  

## Canisters
You can also deploy them yourself.
```
"Test": {
    "ic": "bgwjo-yyaaa-aaaak-aahsq-cai"
  },
  "TokenA": {
    "ic": "ueghb-uqaaa-aaaak-aaioa-cai"
  },
  "TokenB": {
    "ic": "udhbv-ziaaa-aaaak-aaioq-cai"
  }
```

## Test operations
Claim tokens (SyncTA)
```
claimTestTokens : shared (_account: Text) -> async ();
```
Check balance (CallType)
```
balanceOf : shared (_account: Text) -> async (balanceA: Nat, balanceB: Nat);
```
Swap example 1 (SagaTM Forward)
```
swap1 : shared (_to: Text) -> async (SagaTM.Toid, ?SagaTM.OrderStatus);
```
Swap example 2 (SagaTM Backward (Blocking) )
```
swap2 : shared (_to: Text) -> async (SagaTM.Toid, ?SagaTM.OrderStatus);
```
Swap example 3 (SagaTM Backward)
```
swap3 : shared (_to: Text) -> async (SagaTM.Toid, ?SagaTM.OrderStatus);
```