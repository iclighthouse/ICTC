/**
 * Module     : ICDex.mo
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Description: An OrderBook Dex.
 * Refers     : https://github.com/iclighthouse/
 */

import Time "mo:base/Time";
import Result "mo:base/Result";
import List "mo:base/List";
import DRC205 "DRC205Types";

module {
    public type AccountId = Blob;
    public type Address = Text;
    public type Txid = Blob;
    public type Toid = Nat;
    public type Amount = Nat;
    public type Sa = [Nat8];
    public type Nonce = Nat;
    public type Data = Blob;
    public type Timestamp = Nat;
    public type PeriodNs = Int;
    public type IcpE8s = Nat;
    public type TokenStd = DRC205.TokenStd;
    public type TokenType = {
        #Cycles;
        #Icp;
        #Token: Principal;
    };
    public type TokenSymbol = Text;
    public type TokenInfo = (Principal, TokenSymbol, TokenStd);
    //type OrderType = { #Make; #Take; };
    public type OperationType = {
        #AddLiquidity;
        #RemoveLiquidity;
        #Claim;
        #Swap;
    };
    public type DebitToken = Principal;
    public type CreditToken = Principal;
    public type AccountSetting = {enPoolMode: Bool; start: ?Nonce; modeSwitchHistory: [(startNonce:Nonce, endNonce:Nonce)]; enKeepingBalance: Bool};
    public type KeepingBalance = {token0:{locked: Amount; available: Amount}; token1:{locked: Amount; available: Amount}};
    //OrderBook
    public type BalanceChange = {
        #DebitRecord: Nat; // account "-"   contract "+"
        #CreditRecord: Nat; // account "+"   contract "-"
        #NoChange;
    };
    public type Quantity = Nat;
    public type Price = Nat; // This means how many smallest_units of token1 it takes to exchange UNIT_SIZE smallest_units of token0.
    public type OrderSide = { #Sell; #Buy; };
    public type OrderType = { #LMT; #FOK; #FAK; #MKT; }; // #STOP; 
    public type OrderPrice = { quantity: {#Buy: (Quantity, Amount); #Sell: Quantity; }; price: Price; };
    public type PriceResponse = { quantity: Nat; price: Nat; };
    public type OrderFilled = {counterparty: Txid; token0Value: BalanceChange; token1Value: BalanceChange; time: Time.Time };
    public type TradingStatus = { #Todo; #Pending; #Closed; #Cancelled; };
    public type TradingOrder = {
        account: AccountId;
        icrc1Account: ?{owner: Principal; subaccount: ?Blob; };
        txid: Txid;
        orderType: OrderType;
        orderPrice: OrderPrice;
        time: Time.Time;
        expiration: Time.Time;
        toids: [Toid];
        remaining: OrderPrice;
        refund: (token0: Nat, token1: Nat, toid: Nat);
        filled: [OrderFilled];
        status: TradingStatus;
        gas : { gas0: Nat; gas1: Nat; };
        fee : { fee0: Int; fee1: Int; };
        index : Nat;
        nonce: Nat;
        data: ?Blob;
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
    public type DexSetting = {
        UNIT_SIZE: Nat; // 1000000 token smallest units
        ICP_FEE: IcpE8s; // 10000 E8s
        TRADING_FEE: Nat; // /1000000   value 5000 means 0.5%
        MAKER_BONUS_RATE: Nat; // /100  value 50  means 50%
        MAX_TPS: Nat; 
        MAX_PENDINGS: Nat;
        STORAGE_INTERVAL: Nat; // seconds
        ICTC_RUN_INTERVAL: Nat; // seconds
    };
    public type DexConfig = {
        UNIT_SIZE: ?Nat;
        ICP_FEE: ?IcpE8s;
        TRADING_FEE: ?Nat;
        MAKER_BONUS_RATE: ?Nat;
        MAX_TPS: ?Nat; 
        MAX_PENDINGS: ?Nat;
        STORAGE_INTERVAL: ?Nat; // seconds
        ICTC_RUN_INTERVAL: ?Nat; // seconds
        ORDER_EXPIRATION_DURATION: ?Int // seconds
    };
    public type Vol = { value0: Amount; value1: Amount; };
    public type PriceWeighted = {
        token0TimeWeighted: Nat;
        token1TimeWeighted: Nat;
        updateTime: Timestamp; 
    };
    public type Liquidity = {
        value0: Amount;
        value1: Amount;
        shares: Amount;
        shareWeighted: { shareTimeWeighted: Nat; updateTime: Timestamp; };
        unitValue: (value0: Amount, value1: Amount);
        vol: Vol;
        priceWeighted: PriceWeighted;
        swapCount: Nat64;
    };
    public type Liquidity2 = {
        token0: Amount;
        token1: Amount;
        shares: Amount;
        shareWeighted: { shareTimeWeighted: Nat; updateTime: Timestamp; };
        unitValue: (value0: Amount, value1: Amount);
        vol: Vol;
        price: Nat;
        unitSize: Nat;
        priceWeighted: PriceWeighted;
        orderCount: Nat64;
        userCount: Nat64;
    };
    public type OrderStatusResponse = {#Completed: DRC205.TxnRecord; #Pending: TradingOrder; #Failed: TradingOrder; #None; };
    public type TradingResult = Result.Result<{   //<#ok, #err> 
        txid: Txid;
        filled : [OrderFilled];
        status : TradingStatus;
    }, {
        code: {
            #NonceError;
            #InvalidAmount;
            #InsufficientBalance;
            #TransferException;
            #UnacceptableVolatility;
            #TransactionBlocking;
            #UndefinedError;
        };
        message: Text;
    }>;
    public type InitArgs = {
        name: Text;
        token0: Principal;
        token1: Principal;
        unitSize: Nat64;
        owner: ?Principal;
    };
    public type KBar = {kid: Nat; open: Nat; high: Nat; low: Nat; close: Nat; vol: Vol; updatedTs: Timestamp};
    public type TrieList<K, V> = {data: [(K, V)]; total: Nat; totalPage: Nat; };
    public type ListPage = Nat;
    public type ListSize = Nat;
    public type Self = actor {
        //create : shared (_sa: ?Sa) -> async (Text, Nat); // (TxAccount, Nonce)
        getTxAccount : shared query (_account: Address) -> async ({owner: Principal; subaccount: ?Blob}, Text, Nonce, Txid); // (ICRC1.Account, TxAccount, Nonce, Txid)
        trade : shared (_order: OrderPrice, _orderType: OrderType, _expiration: ?PeriodNs, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) -> async TradingResult;
        trade_b : shared (_order: OrderPrice, _orderType: OrderType, _expiration: ?PeriodNs, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data, _brokerage: ?{broker: Principal; rate: Float}) -> async TradingResult;
        tradeMKT : shared (_token: DebitToken, _value: Amount, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) -> async TradingResult;
        tradeMKT_b : shared (_token: DebitToken, _value: Amount, _limitPrice: ?Nat, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data, _brokerage: ?{broker: Principal; rate: Float}) -> async TradingResult;
        cancel : shared (_nonce: Nonce, _sa: ?Sa) -> async ();
        cancelByTxid : shared (_txid: Txid, _sa: ?Sa) -> async ();
        cancelAll : shared ({#management: ?AccountId; #self_sa: ?Sa}, ?{#Sell; #Buy}) -> async ();
        fallback : shared (_nonce: Nonce, _sa: ?Sa) -> async Bool;
        fallbackByTxid : shared (_txid: Txid, _sa: ?Sa) -> async Bool;
        pending : shared query (_account: ?Address, _page: ?ListPage, _size: ?ListSize) -> async TrieList<Txid, TradingOrder>;
        status : shared query (_account: Address, _nonce: Nonce) -> async OrderStatusResponse;
        statusByTxid : shared query (_txid: Txid) -> async OrderStatusResponse;
        makerRebate : shared query (_maker: Address) -> async (rebateRate: Float, feeRebate: Float);
        level10 : shared query () -> async (unitSize: Nat, orderBook: {ask: [PriceResponse]; bid: [PriceResponse]});
        level100 : shared query () -> async (unitSize: Nat, orderBook: {ask: [PriceResponse]; bid: [PriceResponse]});
        name : shared query () -> async Text;
        version : shared query () -> async Text;
        token0 : shared query () -> async (DRC205.TokenType, ?TokenStd);
        token1 : shared query () -> async (DRC205.TokenType, ?TokenStd);
        count : shared query (_account: ?Address) -> async Nat;
        fee : shared query () -> async {maker: { buy: Float; sell: Float }; taker: { buy: Float; sell: Float }};
        feeStatus : shared query () -> async FeeStatus;
        liquidity : shared query (_account: ?Address) -> async Liquidity; // @deprecated: This method will be deprecated
        liquidity2 : shared query (_account: ?Address) -> async Liquidity2;
        getQuotes : shared query (_ki: Nat) -> async [KBar];
        latestFilled : shared query () -> async [(Timestamp, Txid, OrderFilled, OrderSide)];
        orderExpirationDuration : shared query () -> async Int;
        info : shared query () -> async {
            name: Text;
            version: Text;
            decimals: Nat8;
            owner: Principal;
            paused: Bool;
            setting: DexSetting;
            token0: TokenInfo;
            token1: TokenInfo;
        };
        stats : shared query () -> async {price:Float; change24h:Float; vol24h:Vol; totalVol:Vol};
        getConfig : shared query () -> async DexSetting;
        accountSetting : shared query (_a: Address) -> async AccountSetting;
        accountConfig : shared(_exMode: {#PoolMode; #TunnelMode}, _enKeepingBalance: Bool, _sa: ?Sa) -> async ();
        getDepositAccount : shared query (_account: Address) -> async ({owner: Principal; subaccount: ?Blob}, Address);
        poolBalance : shared query ()-> async {token0: Amount; token1: Amount};
        accountBalance : shared query (_a: Address) -> async KeepingBalance;
        safeAccountBalance : shared query (_a: Address) -> async {balance: KeepingBalance; pendingOrders: (Amount, Amount); price: Nat; unitSize: Nat;};
        deposit : shared (_token: {#token0;#token1}, _value: Amount, _sa: ?Sa) -> async ();
        depositFallback : shared (_sa: ?Sa) -> async (value0: Amount, value1: Amount);
        withdraw : shared (_value0: ?Amount, _value1: ?Amount, _sa: ?Sa) -> async (value0: Amount, value1: Amount);
    };
    public type DRC205 = actor {
        drc205_canisterId : shared query () -> async Principal;
        drc205_events : shared query (_account: ?DRC205.Address) -> async [DRC205.TxnRecord];
        drc205_events2 : shared query (_account: ?DRC205.Address, _startTime: ?Time.Time) -> async [DRC205.TxnRecord];
        drc205_txn : shared query (_txid: DRC205.Txid) -> async (txn: ?DRC205.TxnRecord);
        drc205_txn2 : shared (_txid: DRC205.Txid) -> async (txn: ?DRC205.TxnRecord);
    };
 };