import Time "mo:base/Time";
import Result "mo:base/Result";
import DRC205 "DRC205Types";

module {
    public type Timestamp = Nat; // seconds (Time.Time/1000000000)
    public type Address = Text;
    public type AccountId = Blob;
    public type Token = Principal;
    public type Amount = Nat;
    public type Sa = [Nat8];
    public type Shares = Nat;
    public type Nonce = Nat;
    public type Data = Blob;
    public type Txid = Blob;
    public type TokenSymbol = Text;
    public type TokenInfo = (Principal, TokenSymbol, TokenStd);
    public type TokenValue = {#token0: Amount; #token1: Amount};
    public type OrderRequest = {#add: {token: Token; value: Amount}; #receive: {token: Token; value: Amount} };
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
        ICP_FEE: Nat;
        RETENTION_RATE: Nat;
        MAX_VOLATILITY: Nat;
        //SYNC_INTERVAL: Nat;
    };
    public type ConfigRequest = { 
        TOKEN0_LIMIT: ?Nat;
        TOKEN1_LIMIT: ?Nat;
        FEE: ?Nat;
        ICP_FEE: ?Nat;
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
    public type OrderStatusResponse = {#Completed: DRC205.TxnRecord; #Pending: SwappingOrder; #Failed: SwappingOrder; #None; };
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
            #InsufficientBalance;
            #InsufficientShares;
            #InsufficientPoolFund;
            #DepositInProgress;
            #UndefinedError;
        };
        message: Text;
    }>;
    // public type OrderTemp = {  // AccountId -> OrderTemp
    //     icrc1Account: ?{owner: Principal; subaccount: ?Blob; };
    //     operation: DRC205.OperationType;
    //     locked0: Amount; 
    //     lockedTxid0: ?Txid; 
    //     locked1: Amount; 
    //     lockedTxid1: ?Txid;
    // };
    public type AccountBalance = {
        available0: Amount;
        locked0: Amount;
        available1: Amount;
        locked1: Amount;
    };
    public type SwappingOrder = {  // Txid -> SwappingOrder
        account: AccountId;
        icrc1Account: ?{owner: Principal; subaccount: ?Blob; };
        operation: DRC205.OperationType;
        value0: Amount; // put token0 amount
        value1: Amount; // or/and token1 amount
        toid: Nat; // SagaTM.Toid
        status: TxnStatus;
        time: Time.Time;
    };
    public type Side = { #Token0ToToken1; #Token1ToToken0; };
    public type KBar = {kid: Nat; open: Nat; high: Nat; low: Nat; close: Nat; vol: Nat; updatedTs: Timestamp};
    public type TrieList<K, V> = {data: [(K, V)]; total: Nat; totalPage: Nat; };
    public type Self = actor {
        name : shared query () -> async Text;
        version : shared query () -> async Text;
        decimals : shared query () -> async Nat8;
        token0 : shared query () -> async (DRC205.TokenType, ?TokenStd);
        token1 : shared query () -> async (DRC205.TokenType, ?TokenStd);
        getConfig : shared query () -> async Config;
        getDepositAccount : shared (_account: Address) -> async ({owner: Principal; subaccount: ?Blob}, Address, Nonce, Txid); // get deposit account and nonce
        swap : shared (_order: OrderRequest, _slip: ?Nat, _autoWithdraw: ?Bool, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) -> async TxnResult;
        add : shared (_value0: ?Amount, _value1: ?Amount, _autoWithdraw: ?Bool, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) -> async TxnResult;
        remove : shared (_shares: ?Amount, _autoWithdraw: ?Bool, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) -> async TxnResult;
        fallback : shared (_sa: ?Sa) -> async (); 
        withdraw : shared (_autoWithdraw: ?Bool, _sa: ?Sa) -> async ();
        autoWithdrawal : shared query (_account: Address) -> async Bool;
        liquidity : shared query (_account: ?Address) -> async Liquidity;
        balance : shared query (_account: Address) -> async AccountBalance;
        pending : shared query (_account: ?Address, _page: ?Nat, _size: ?Nat) -> async TrieList<Txid, SwappingOrder>;
        status : shared query (_account: Address, _nonce: Nat) -> async OrderStatusResponse;
        statusByTxid : shared query (_txid: Txid) -> async OrderStatusResponse;
        getQuotes : shared query (_ki: Nat) -> async [KBar];
        feeStatus : shared query () -> async FeeStatus;
        yield : shared query () -> async (apy24h: {apyToken0: Float; apyToken1: Float}, apy7d: {apyToken0: Float; apyToken1: Float});
        info : shared query () -> async {
            name: Text;
            version: Text;
            decimals: Nat8;
            owner: Principal;
            paused: Bool;
            setting: Config;
            token0: TokenInfo;
            token1: TokenInfo;
        };
    }
}
