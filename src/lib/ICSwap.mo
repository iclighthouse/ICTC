import Time "mo:base/Time";
import Result "mo:base/Result";
import DRC205 "DRC205Types";

module {
    public type Timestamp = Nat; // seconds (Time.Time/1000000000)
    public type Address = Text;
    public type AccountId = Blob;
    public type Amount = Nat;
    public type Sa = [Nat8];
    public type Shares = Nat;
    public type Nonce = Nat;
    public type Data = Blob;
    public type Txid = Blob;
    public type TxnRecord = DRC205.TxnRecord;
    public type ShareWeighted = {
        shareTimeWeighted: Nat; 
        updateTime: Timestamp; 
    };
    public type Vol = {
        value0: Amount;
        value1: Amount; 
    };
    public type PriceWeighted = {
        token0TimeWeighted: Nat;
        token1TimeWeighted: Nat;
        updateTime: Timestamp; 
    };
    public type Yield = {
        accrued: {value0: Amount; value1: Amount;};
        rate: {rate0: Nat; rate1: Nat; };   //  per 100000000 shares
        unitValue: {value0: Amount; value1: Amount;}; // per 10000000 shares
        updateTime: Timestamp;
        isClosed: Bool;
    };
    public type Liquidity = {
        value0: Amount;
        value1: Amount;
        shares: Shares;
        shareWeighted: ShareWeighted;
        unitValue: (value0: Amount, value1: Amount);
        vol: Vol;
        priceWeighted: PriceWeighted;
        swapCount: Nat64;
    };
    public type FeeBalance = {
        value0: Amount;
        value1: Amount;
    };
    public type FeeStatus = {
        feeRate: Float;
        feeBalance: FeeBalance;
        totalFee: FeeBalance;
    };
    public type TransStatus = {
        #Processing;
        #Success;
        #Failure;
        #Fallback;
    };
    public type ErrorAction = {#redo; #fallback; #skip;};
    public type ErrorLog = {
        user: AccountId;
        txid: Txid;
        toid: Blob;
        ttid: Blob;
        action: ErrorAction;
        time: Timestamp;
    };
    public type TokenStd = DRC205.TokenStd;
    public type InitArgs = {
        name: Text;
        token0: Principal;
        token0Std: TokenStd;
        token1: Principal;
        token1Std: TokenStd;
        owner: Principal;
    };
    public type Config = { 
        TOKEN0_LIMIT: Nat;
        TOKEN1_LIMIT: Nat;
        FEE: Nat;
        RETENTION_RATE: Nat;
        MAX_VOLATILITY: Nat;
        //SYNC_INTERVAL: Nat;
    };
    public type ConfigRequest = { 
        TOKEN0_LIMIT: ?Nat;
        TOKEN1_LIMIT: ?Nat;
        FEE: ?Nat;
        RETENTION_RATE: ?Nat;
        MAX_VOLATILITY: ?Nat;
        //SYNC_INTERVAL: ?Nat;
    };
    public type BalanceChange = {
        #DebitRecord: Nat;
        #CreditRecord: Nat;
        #NoChange;
    };
    public type ShareChange = {
        #Mint: Shares;
        #Burn: Shares;
        #NoChange;
    };
    public type TxnStatus = { #Pending; #Success; #Failure; #Blocking; };
    public type TxnResult = Result.Result<{   //<#ok, #err> 
        txid: Txid;
        status: TxnStatus;
    }, {
        code: {
            #NonceError;
            #InvalidAmount;
            #TransferException;
            #UnacceptableVolatility;
            #TransactionBlocking;
            #InsufficientShares;
            #PoolIsEmpty;
            #UndefinedError;
        };
        message: Text;
    }>;
    public type OrderTemp = {  // AccountId -> OrderTemp
        operation: DRC205.OperationType;
        locked0: Amount; 
        lockedTxid0: ?Txid; 
        locked1: Amount; 
        lockedTxid1: ?Txid;
    };
    public type OrderPending = {  // Txid -> OrderPending
        account: AccountId;
        operation: DRC205.OperationType;
        value0: Amount; 
        value1: Amount; 
        toid: Nat; // SagaTM.Toid
        status: TxnStatus;
        time: Time.Time;
    };
    public type Self = actor {
        //fallback2(Address)
        //addFromTransfer(Address)
        //swapFromLockTransfer(Address)
        //swapFromTransfer(_token: Principal, _account: Address, _value: Amount, _txid: Txid)
        name : shared query () -> async Text;
        version : shared query () -> async Text;
        decimals : shared query () -> async Nat8;
        token0 : shared query () -> async (DRC205.TokenType, ?TokenStd);
        token1 : shared query () -> async (DRC205.TokenType, ?TokenStd);
        getConfig : shared query () -> async Config;
        count : shared query (_account: ?Address) -> async Nat;
        swap : shared (_value: {#token0: Amount; #token1: Amount}, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) -> async TxnResult;
        swap2 : shared (_tokenId: Principal, _value: Amount, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) -> async TxnResult;
        add : shared (_value0: ?Amount, _value1: ?Amount, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) -> async TxnResult;
        remove : shared (_shares: ?Amount, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) -> async TxnResult;
        claim : shared (_nonce: ?Nonce, _sa: ?Sa, _data: ?Data) -> async TxnResult;
        tokenNotify : shared (_token: Principal, _txid: Txid) -> async ();
        fallback : shared (_sa: ?Sa) -> async (); 
        liquidity : shared query (_account: ?Address) -> async Liquidity;
        pending : shared query (_account: ?Address) -> async { tempLocked: [(AccountId, OrderTemp)]; pending: [(Txid, OrderPending)] };
        txnPending : shared query (_txid: Txid) -> async ?OrderPending;
        getEvents : shared query (_account: ?Address) -> async [TxnRecord];
        lastTxids : shared query (_account: ?Address) -> async [Txid];
        txnRecord : shared query (_txid: Txid) -> async (txn: ?TxnRecord);
        txnRecord2 : shared (_txid: Txid) -> async (txn: ?TxnRecord);
        feeStatus : shared query () -> async FeeStatus;
        yield : shared query () -> async (apy24h: {apyToken0: Float; apyToken1: Float}, apy7d: {apyToken0: Float; apyToken1: Float});
        lpRewards : shared query (_account: Address, _includePending: Bool) -> async ({value0:Nat; value1:Nat});
    }
}
