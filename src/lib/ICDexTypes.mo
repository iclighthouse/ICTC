/**
 * Module     : ICDex.mo
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Description: An OrderBook Dex.
 * Refers     : https://github.com/iclighthouse/
 */

import Time "mo:base/Time";
import Result "mo:base/Result";
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
    //OrderBook
    public type BalanceChange = {
        #DebitRecord: Nat; // account "-"   contract "+"
        #CreditRecord: Nat; // account "+"   contract "-"
        #NoChange;
    };
    public type OrderSide = { #Sell; #Buy; };
    public type OrderType = { #LMT; #FOK; #FAK; #MKT; }; // #MKT; 
    public type OrderPrice = { quantity: {#Buy: (quantity: Nat, amount: Nat); #Sell: Nat; }; price: Nat; };
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
        fee : { fee0: Nat; fee1: Nat; };
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
    };
    public type DexConfig = {
        UNIT_SIZE: ?Nat;
        ICP_FEE: ?IcpE8s;
        TRADING_FEE: ?Nat;
        MAKER_BONUS_RATE: ?Nat;
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
    public type KBar = {kid: Nat; open: Nat; high: Nat; low: Nat; close: Nat; vol: Nat; updatedTs: Timestamp};
    public type TrieList<K, V> = {data: [(K, V)]; total: Nat; totalPage: Nat; };
    public type Self = actor {
        //create : shared (_sa: ?Sa) -> async (Text, Nat); // (TxAccount, Nonce)
        getTxAccount : shared query (_account: Address) -> async ({owner: Principal; subaccount: ?Blob}, Text, Nonce, Txid); // (ICRC1.Account, TxAccount, Nonce, Txid)
        trade : shared (_order: OrderPrice, _orderType: OrderType, _expiration: ?Int, _nonce: ?Nat, _sa: ?Sa, _data: ?Data) -> async TradingResult;
        tradeMKT : shared (_token: Principal, _value: Amount, _nonce: ?Nat, _sa: ?Sa, _data: ?Data) -> async TradingResult;
        cancel : shared (_nonce: Nat, _sa: ?Sa) -> async ();
        cancel2 : shared (_txid: Txid, _sa: ?Sa) -> async ();
        fallback : shared (_nonce: Nat, _sa: ?Sa) -> async Bool;
        fallback2 : shared (_txid: Txid, _sa: ?Sa) -> async Bool;
        pending : shared query (_account: ?Address, _page: ?Nat, _size: ?Nat) -> async TrieList<Txid, TradingOrder>;
        status : shared query (_account: Address, _nonce: Nat) -> async OrderStatusResponse;
        statusByTxid : shared query (_txid: Txid) -> async OrderStatusResponse;
        makerRebate : shared query (_maker: Address) -> async (rate: Float, feeRebate: Float);
        level10 : shared query () -> async {ask: [OrderPrice]; bid: [OrderPrice]};
        level100 : shared query () -> async {ask: [OrderPrice]; bid: [OrderPrice]};
        name : shared query () -> async Text;
        version : shared query () -> async Text;
        token0 : shared query () -> async (DRC205.TokenType, ?TokenStd);
        token1 : shared query () -> async (DRC205.TokenType, ?TokenStd);
        count : shared query (_account: ?Address) -> async Nat;
        feeStatus : shared query () -> async FeeStatus;
        liquidity : shared query (_account: ?Address) -> async Liquidity;
        getQuotes : shared query (_ki: Nat) -> async [KBar];
        latestFilled : shared query () -> async [(Timestamp, Txid, OrderFilled, OrderSide)];
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
    };
    public type DRC205 = actor {
        drc205_canisterId : shared query () -> async Principal;
        drc205_events : shared query (_account: ?DRC205.Address) -> async [DRC205.TxnRecord];
        drc205_txn : shared query (_txid: DRC205.Txid) -> async (txn: ?DRC205.TxnRecord);
        drc205_txn2 : shared (_txid: DRC205.Txid) -> async (txn: ?DRC205.TxnRecord);
    };
 };