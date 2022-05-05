/**
 * Module     : DRC20.mo
 * Author     : ICLighthouse Team
 * License    : Apache License 2.0
 * Stability  : Experimental
 * Github     : https://github.com/iclighthouse/DRC_standards/
 */

import AID "./lib/AID";
import Array "mo:base/Array";
import BigEndian "mo:base/Char";
import Binary "./lib/Binary";
import Blob "mo:base/Blob";
import Cycles "mo:base/ExperimentalCycles";
import CyclesWallet "./sys/CyclesWallet";
import DRC202 "./lib/DRC202";
import Deque "mo:base/Deque";
import Trie "mo:base/Trie";
import Hex "./lib/Hex";
import Int "mo:base/Int";
import Int32 "mo:base/Int32";
import Iter "mo:base/Iter";
import List "mo:base/List";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Option "mo:base/Option";
import Order "mo:base/Order";
import Prim "mo:⛔";
import Principal "mo:base/Principal";
import SHA224 "./lib/SHA224";
import Time "mo:base/Time";
import Types "./lib/DRC20";
import DRC207 "./lib/DRC207";
import DIP20 "./lib/DIP20Types";

//record { totalSupply=10000000000000; decimals=8; gas=variant{token=100000}; name=opt "TokenTest"; symbol=opt "TTT"; metadata=null; founder=null;} 
shared(installMsg) actor class DRC20(initArgs: Types.InitArgs) = this {
    /*
    * Types 
    */
    type Metadata = Types.Metadata;
    type Gas = Types.Gas;
    type Address = Types.Address; //Text
    type AccountId = Types.AccountId; //Blob
    type Txid = Types.Txid;  //Blob
    type TxnResult = Types.TxnResult;
    type ExecuteType = Types.ExecuteType;
    type Operation = Types.Operation;
    type Transaction = Types.Transaction;
    type TxnRecord = Types.TxnRecord;
    type Callback = Types.Callback;
    type MsgType = Types.MsgType;
    type Subscription = Types.Subscription;
    type Allowance = Types.Allowance;
    type TxnQueryRequest =Types.TxnQueryRequest;
    type TxnQueryResponse =Types.TxnQueryResponse;
    type CoinSeconds = Types.CoinSeconds;
    type From = Address;
    type To = Address;
    type Spender = Address;
    type Decider = Address;
    type Amount = Nat;
    type Sa = [Nat8];
    type Nonce = Nat;
    type Data = Blob;
    type Timeout = Nat32;
    type Config = Types.Config;

    /*
    * Config 
    */
    private stable var MAX_CACHE_TIME: Int = 3 * 30 * 24 * 3600 * 1000000000; // 3 months
    private stable var MAX_CACHE_NUMBER_PER: Nat = 100; 
    private stable var FEE_TO: AccountId = AID.blackhole();  
    private stable var STORAGE_CANISTER: Text = "y5a36-liaaa-aaaak-aacqa-cai";
    private stable var MAX_PUBLICATION_TRIES: Nat = 2; 
    private stable var MAX_STORAGE_TRIES: Nat = 2; 

    /* 
    * State Variables 
    */
    private stable var standard_: Text = "dip20; drc20; ictokens"; //ict
    private stable var owner: Principal = installMsg.caller; //ict
    private stable var name_: Text = Option.get(initArgs.name, "");
    private stable var symbol_: Text = Option.get(initArgs.symbol, "");
    private stable let decimals_: Nat8 = initArgs.decimals;
    private stable var totalSupply_: Nat = initArgs.totalSupply;
    private stable var totalCoinSeconds: CoinSeconds = {coinSeconds = 0; updateTime = Time.now()};
    private stable var gas_: Gas = initArgs.gas;
    private stable var metadata_: [Metadata] = Option.get(initArgs.metadata, []);
    private stable var txnRecords: Trie.Trie<Txid, TxnRecord> = Trie.empty();
    private stable var globalTxns = Deque.empty<(Txid, Time.Time)>();
    private stable var globalLastTxns = Deque.empty<Txid>();
    private stable var index: Nat = 0;
    private stable var balances: Trie.Trie<AccountId, Nat> = Trie.empty();
    private stable var coinSeconds: Trie.Trie<AccountId, CoinSeconds> = Trie.empty();
    private stable var nonces: Trie.Trie<AccountId, Nat> = Trie.empty();
    private stable var lastTxns_: Trie.Trie<AccountId, Deque.Deque<Txid>> = Trie.empty();
    private stable var lockedTxns_: Trie.Trie<AccountId, [Txid]> = Trie.empty();
    private stable var allowances: Trie.Trie2D<AccountId, AccountId, Nat> = Trie.empty(); 
    private stable var subscriptions: Trie.Trie<AccountId, Subscription> = Trie.empty();
    private stable var cyclesBalances: Trie.Trie<AccountId, Nat> = Trie.empty();
    private stable var storeRecords = List.nil<(Txid, Nat)>();
    private stable var publishMessages = List.nil<(AccountId, MsgType, Txid, Nat)>();
    private stable var top100_: [(AccountId, Nat)] = [];
    private stable var top100Threshold: Nat = 0;
    private stable var firstTime: Trie.Trie<AccountId, Time.Time> = Trie.empty();
    private stable var balancesSnapshot: [(Trie.Trie<AccountId, Nat>, Time.Time)] = [];
    
    /* 
    * Local Functions
    */
    private func _onlyOwner(_caller: Principal) : Bool { //ict
        return _caller == owner;
    };  // assert(_onlyOwner(msg.caller));
    private func keyb(t: Blob) : Trie.Key<Blob> { return { key = t; hash = Blob.hash(t) }; };
    private func _getTxnRecord(_txid: Txid): ?TxnRecord{
        return Trie.get(txnRecords, keyb(_txid), Blob.equal);
    };
    private func _insertTxnRecord(_txn: TxnRecord): (){
        var txid = _txn.txid;
        txnRecords := Trie.put(txnRecords, keyb(txid), Blob.equal, _txn).0;
        _pushGlobalTxns(txid);
    };
    private func _deleteTxnRecord(_txid: Txid, _isDeep: Bool): (){
        switch(Trie.get(txnRecords, keyb(_txid), Blob.equal)){
            case(?(record)){ //Existence record
                var caller = record.caller;
                var from = record.transaction.from;
                var to = record.transaction.to;
                var timestamp = record.timestamp;
                if (not(_inLockedTxns(_txid, from))){ //Not in from's LockedTxns
                    if (Time.now() - timestamp > MAX_CACHE_TIME){ //Expired
                        _cleanLastTxns(caller);
                        _cleanLastTxns(from);
                        _cleanLastTxns(to);
                        switch(record.transaction.operation){
                            case(#lockTransfer(v)){ _cleanLastTxns(v.decider); };
                            case(_){};
                        };
                        txnRecords := Trie.remove(txnRecords, keyb(_txid), Blob.equal).0;
                    } else if (_isDeep and not(_inLastTxns(_txid, caller)) and 
                        not(_inLastTxns(_txid, from)) and not(_inLastTxns(_txid, to))) {
                        switch(record.transaction.operation){
                            case(#lockTransfer(v)){ 
                                if (not(_inLastTxns(_txid, v.decider))){
                                    txnRecords := Trie.remove(txnRecords, keyb(_txid), Blob.equal).0;
                                };
                            };
                            case(_){
                                txnRecords := Trie.remove(txnRecords, keyb(_txid), Blob.equal).0;
                            };
                        };
                    };
                };
            };
            case(_){};
        };
    };
    private func _getAccountId(_address: Address): AccountId{
        switch (AID.accountHexToAccountBlob(_address)){
            case(?(a)){
                return a;
            };
            case(_){
                var p = Principal.fromText(_address);
                var a = AID.principalToAccountBlob(p, null);
                return a;
            };
        };
    }; 
    private func _getAccountIdFromPrincipal(_p: Principal, _sa: ?[Nat8]): AccountId{
        var a = AID.principalToAccountBlob(_p, _sa);
        return a;
    }; // AccountIdToPrincipal: accountMaps.get(_a)
    private stable let founder_: AccountId = _getAccountId(Option.get(initArgs.founder, Principal.toText(installMsg.caller)));
    private func _getTxid(_caller: AccountId): Txid{
        var _nonce: Nat = _getNonce(_caller);
        return DRC202.generateTxid(Principal.fromActor(this), _caller, _nonce);
    };
    private func _getBalance(_a: AccountId): Nat{
        switch(Trie.get(balances, keyb(_a), Blob.equal)){  
            case(?(balance)){
                return balance;
            };
            case(_){
                return 0;
            };
        };
    };
    private func _setBalance(_a: AccountId, _v: Nat): (){
        let originalValue = _getBalance(_a);
        // CoinSeconds 
        let now = Time.now();
        let coinSecondsItem = Option.get(Trie.get(coinSeconds, keyb(_a), Blob.equal), {coinSeconds = 0; updateTime = now });
        let newCoinSeconds = coinSecondsItem.coinSeconds + originalValue * (Int.abs(now - coinSecondsItem.updateTime) / 1000000000);
        coinSeconds := Trie.put(coinSeconds, keyb(_a), Blob.equal, {coinSeconds = newCoinSeconds; updateTime = now}).0;
        if(_v == 0){
            balances := Trie.remove(balances, keyb(_a), Blob.equal).0;
        } else {
            balances := Trie.put(balances, keyb(_a), Blob.equal, _v).0;
            switch (gas_){
                case(#token(fee)){
                    if (_v < fee/2){
                        ignore _burn(_a, _v, false);
                        return ();
                    };
                };
                case(_){};
            }
        };
        _pushTop100(_a, _getBalance(_a));
        _putFirstTime(_a);
    };
    private func _getNonce(_a: AccountId): Nat{
        switch(Trie.get(nonces, keyb(_a), Blob.equal)){ 
            case(?(nonce)){
                return nonce;
            };
            case(_){
                return 0;
            };
        };
    };
    private func _addNonce(_a: AccountId): (){
        var n = _getNonce(_a);
        nonces := Trie.put(nonces, keyb(_a), Blob.equal, n+1).0;
        index += 1;
    };
    private func _pushGlobalTxns(_txid: Txid): (){
        // push new txid.
        globalTxns := Deque.pushFront(globalTxns, (_txid, Time.now()));
        globalLastTxns := Deque.pushFront(globalLastTxns, _txid);
        var size = List.size(globalLastTxns.0) + List.size(globalLastTxns.1);
        while (size > MAX_CACHE_NUMBER_PER){
            size -= 1;
            switch (Deque.popBack(globalLastTxns)){
                case(?(q, v)){
                    globalLastTxns := q;
                };
                case(_){};
            };
        };
        // pop expired txids, and delete their records.
        switch(Deque.peekBack(globalTxns)){
            case (?(txid, ts)){
                var timestamp: Time.Time = ts;
                while (Time.now() - timestamp > MAX_CACHE_TIME){
                    switch (Deque.popBack(globalTxns)){
                        case(?(q, v)){
                            globalTxns := q;
                            _deleteTxnRecord(v.0, false); // delete the record.
                        };
                        case(_){};
                    };
                    switch(Deque.peekBack(globalTxns)){
                        case(?(txid_,ts_)){
                            timestamp := ts_;
                        };
                        case(_){
                            timestamp := Time.now();
                        };
                    };
                };
            };
            case(_){};
        };
    };
    private func _getGlobalLastTxns(): [Txid]{
        var l = List.append(globalLastTxns.0, List.reverse(globalLastTxns.1));
        return List.toArray(l);
    };
    private func _inLastTxns(_txid: Txid, _a: AccountId): Bool{
        switch(Trie.get(lastTxns_, keyb(_a), Blob.equal)){ 
            case(?(txidsQ)){
                var l = List.append(txidsQ.0, List.reverse(txidsQ.1));
                return List.some(l, func (v: Txid): Bool { v == _txid });
            };
            case(_){
                return false;
            };
        };
    };
    private func _getLastTxns(_a: AccountId): [Txid]{
        switch(Trie.get(lastTxns_, keyb(_a), Blob.equal)){
            case(?(txidsQ)){
                var l = List.append(txidsQ.0, List.reverse(txidsQ.1));
                return List.toArray(l);
            };
            case(_){
                return [];
            };
        };
    };
    private func _cleanLastTxns(_a: AccountId): (){
        switch(Trie.get(lastTxns_, keyb(_a), Blob.equal)){
            case(?(q)){  
                var txids: Deque.Deque<Txid> = q;
                var size = List.size(txids.0) + List.size(txids.1);
                while (size > MAX_CACHE_NUMBER_PER){
                    size -= 1;
                    switch (Deque.popBack(txids)){
                        case(?(q, v)){
                            txids := q;
                        };
                        case(_){};
                    };
                };
                switch(Deque.peekBack(txids)){
                    case (?(txid)){
                        let txn_ = _getTxnRecord(txid);
                        switch(txn_){
                            case(?(txn)){
                                var timestamp = txn.timestamp;
                                while (Time.now() - timestamp > MAX_CACHE_TIME and size > 0){
                                    switch (Deque.popBack(txids)){
                                        case(?(q, v)){
                                            txids := q;
					                        size -= 1;
                                        };
                                        case(_){};
                                    };
                                    switch(Deque.peekBack(txids)){
                                        case(?(txid)){
                                            let txn_ = _getTxnRecord(txid);
                                            switch(txn_){
                                                case(?(txn)){ timestamp := txn.timestamp; };
                                                case(_){};
                                            };
                                        };
                                        case(_){ timestamp := Time.now(); };
                                    };
                                };
                            };
                            case(_){
                                switch (Deque.popBack(txids)){
                                    case(?(q, v)){
                                        txids := q;
                                        size -= 1;
                                    };
                                    case(_){};
                                };
                            };
                        };
                    };
                    case(_){};
                };
                if (size == 0){
                    lastTxns_ := Trie.remove(lastTxns_, keyb(_a), Blob.equal).0;
                }else{
                    lastTxns_ := Trie.put(lastTxns_, keyb(_a), Blob.equal, txids).0;
                };
            };
            case(_){};
        };
    };
    private func _pushLastTxn(_as: [AccountId], _txid: Txid): (){
        let len = _as.size();
        if (len == 0){ return (); };
        for (i in Iter.range(0, Nat.sub(len,1))){
            var count: Nat = 0;
            for (j in Iter.range(i, Nat.sub(len,1))){
                if (Blob.equal(_as[i], _as[j])){ count += 1; };
            };
            if (count == 1){
                switch(Trie.get(lastTxns_, keyb(_as[i]), Blob.equal)){
                    case(?(q)){
                        var txids: Deque.Deque<Txid> = q;
                        txids := Deque.pushFront(txids, _txid);
                        lastTxns_ := Trie.put(lastTxns_, keyb(_as[i]), Blob.equal, txids).0;
                        _cleanLastTxns(_as[i]);
                    };
                    case(_){
                        var new = Deque.empty<Txid>();
                        new := Deque.pushFront(new, _txid);
                        lastTxns_ := Trie.put(lastTxns_, keyb(_as[i]), Blob.equal, new).0;
                    };
                };
            };
        };
    };
    private func _inLockedTxns(_txid: Txid, _a: AccountId): Bool{
        switch(Trie.get(lockedTxns_, keyb(_a), Blob.equal)){ 
            case(?(txids)){
                switch (Array.find(txids, func (v: Txid): Bool { v == _txid })){
                    case(?(v)){
                        return true;
                    };
                    case(_){
                        return false;
                    };
                };
            };
            case(_){
                return false;
            };
        };
    };
    private func _getLockedTxns(_a: AccountId): [Txid]{
        switch(Trie.get(lockedTxns_, keyb(_a), Blob.equal)){
            case(?(txids)){
                return txids;
            };
            case(_){
                return [];
            };
        };
    };
    private func _appendLockedTxn(_a: AccountId, _txid: Txid): (){
        switch(Trie.get(lockedTxns_, keyb(_a), Blob.equal)){
            case(?(arr)){
                var txids: [Txid] = arr;
                txids := Array.append([_txid], txids);
                lockedTxns_ := Trie.put(lockedTxns_, keyb(_a), Blob.equal, txids).0;
            };
            case(_){
                lockedTxns_ := Trie.put(lockedTxns_, keyb(_a), Blob.equal, [_txid]).0;
            };
        };
    };
    private func _dropLockedTxn(_a: AccountId, _txid: Txid): (){
        switch(Trie.get(lockedTxns_, keyb(_a), Blob.equal)){
            case(?(arr)){
                var txids: [Txid] = arr;
                txids := Array.filter(txids, func (t: Txid): Bool { t != _txid });
                if (txids.size() == 0){
                    lockedTxns_ := Trie.remove(lockedTxns_, keyb(_a), Blob.equal).0;
                };
                lockedTxns_ := Trie.put(lockedTxns_, keyb(_a), Blob.equal, txids).0;
                _deleteTxnRecord(_txid, true);
            };
            case(_){};
        };
    };
    private func _getAllowances(_a: AccountId): [Allowance]{
        switch(Trie.get(allowances, keyb(_a), Blob.equal)){ 
            case(?(allowTrie)){
                var a = Iter.map(Trie.iter(allowTrie), func (entry: (AccountId, Nat)): Allowance{
                    return { spender = entry.0; remaining = entry.1; };
                });
                return Iter.toArray(a);
            };
            case(_){
                return [];
            };
        };
    };
    private func _getAllowance(_a: AccountId, _s: AccountId): Nat{
        switch(Trie.get(allowances, keyb(_a), Blob.equal)){
            case(?(allowTrie)){
                switch(Trie.get(allowTrie, keyb(_s), Blob.equal)){
                    case(?(v)){
                        return v;
                    };
                    case(_){
                        return 0;
                    };
                };
            };
            case(_){
                return 0;
            };
        };
    };
    private func _setAllowance(_a: AccountId, _s: AccountId, _v: Nat): (){
        if (_v > 0){
            allowances := Trie.put2D(allowances, keyb(_a), Blob.equal, keyb(_s), Blob.equal, _v);
        }else{
            allowances := Trie.remove2D(allowances, keyb(_a), Blob.equal, keyb(_s), Blob.equal).0;
        };
    };
    private func _getSubscription(_a: AccountId): ?Subscription{
        return Trie.get(subscriptions, keyb(_a), Blob.equal);
    };
    private func _getSubCallback(_a: AccountId, _mt: MsgType): ?Callback{
        switch(Trie.get(subscriptions, keyb(_a), Blob.equal)){
            case(?(sub)){
                var msgTypes = sub.msgTypes;
                var found = Array.find(msgTypes, func (mt: MsgType): Bool { mt == _mt });
                switch(found){
                    case(?(v)){ return ?sub.callback; };
                    case(_){ return null; };
                };
            };
            case(_){
                return null;
            };
        };
    };
    private func _setSubscription(_a: AccountId, _sub: Subscription): (){
        if (_sub.msgTypes.size() == 0){
            subscriptions := Trie.remove(subscriptions, keyb(_a), Blob.equal).0;
        } else{
            subscriptions := Trie.put(subscriptions, keyb(_a), Blob.equal, _sub).0;
        };
    };
    // pushMessages
    private func _pushMessages(_subs: [AccountId], _msgType: MsgType, _txid: Txid) : (){
        let len = _subs.size();
        if (len == 0){ return (); };
        for (i in Iter.range(0, Nat.sub(len,1))){
            var count: Nat = 0;
            for (j in Iter.range(i, Nat.sub(len,1))){
                if (Blob.equal(_subs[i], _subs[j])){ count += 1; };
            };
            if (count == 1){
                publishMessages := List.push((_subs[i], _msgType, _txid, 0), publishMessages);
            };
        };
    };
    // publish
    private func _publish() : async (){
        var _publishMessages = List.nil<(AccountId, MsgType, Txid, Nat)>();
        var item = List.pop(publishMessages);
        while (Option.isSome(item.0)){
            publishMessages := item.1;
            switch(item.0){
                case(?(account, msgType, txid, callCount)){
                    switch(_getSubCallback(account, msgType)){
                        case(?(callback)){
                            if (callCount < MAX_PUBLICATION_TRIES){
                                switch(_getTxnRecord(txid)){
                                    case(?(txn)){
                                        try{
                                            await callback(txn);
                                        } catch(e){ //push
                                            _publishMessages := List.push((account, msgType, txid, callCount+1), _publishMessages);
                                        };
                                    };
                                    case(_){};
                                };
                            };
                        };
                        case(_){};
                    };
                };
                case(_){};
            };
            item := List.pop(publishMessages);
        };
        publishMessages := _publishMessages;
    };
    private func _getCyclesBalances(_a: AccountId) : Nat{
        switch(Trie.get(cyclesBalances, keyb(_a), Blob.equal)){ 
            case(?(balance)){ return balance; };
            case(_){ return 0; };
        };
    };
    private func _setCyclesBalances(_a: AccountId, _v: Nat) : (){
        if(_v == 0){
            cyclesBalances := Trie.remove(cyclesBalances, keyb(_a), Blob.equal).0;
        } else {
            switch (gas_){
                case(#cycles(fee)){
                    if (_v < fee/2){
                        cyclesBalances := Trie.remove(cyclesBalances, keyb(_a), Blob.equal).0;
                    } else{
                        cyclesBalances := Trie.put(cyclesBalances, keyb(_a), Blob.equal, _v).0;
                    };
                };
                case(_){
                    cyclesBalances := Trie.put(cyclesBalances, keyb(_a), Blob.equal, _v).0;
                };
            }
        };
    };
    private func _checkFee(_caller: AccountId, _percent: Nat, _amount: Nat): Bool{
        let cyclesAvailable = Cycles.available(); 
        switch(gas_){
            case(#cycles(v)){
                if(v > 0) {
                    let fee = Nat.max(v * _percent / 100, 1);
                    if (cyclesAvailable >= fee){
                        return true;
                    } else {
                        let callerBalance = _getCyclesBalances(_caller);
                        if (callerBalance >= fee){
                            return true;
                        } else {
                            return false;
                        };
                    };
                };
                return true;
            };
            case(#token(v)){ 
                if(v > 0) {
                    let fee = Nat.max(v * _percent / 100, 1);
                    if (_getBalance(_caller) >= fee + _amount){
                        return true;
                    } else {
                        return false;
                    };
                };
                return true;
            };
            case(_){ return true; };
        };
    };
    private func _chargeFee(_caller: AccountId, _percent: Nat): Bool{
        let cyclesAvailable = Cycles.available(); 
        switch(gas_){
            case(#cycles(v)){
                if(v > 0) {
                    let fee = Nat.max(v * _percent / 100, 1);
                    if (cyclesAvailable >= fee){
                        let accepted = Cycles.accept(fee); 
                        let feeToBalance = _getCyclesBalances(FEE_TO);
                        _setCyclesBalances(FEE_TO, feeToBalance + accepted);
                        return true;
                    } else {
                        let callerBalance = _getCyclesBalances(_caller);
                        if (callerBalance >= fee){
                            _setCyclesBalances(_caller, callerBalance - fee);
                            let feeToBalance = _getCyclesBalances(FEE_TO);
                            _setCyclesBalances(FEE_TO, feeToBalance + fee);
                            return true;
                        } else {
                            return false;
                        };
                    };
                };
                return true;
            };
            case(#token(v)){ 
                if(v > 0) {
                    let fee = Nat.max(v * _percent / 100, 1);
                    if (_getBalance(_caller) >= fee){
                        ignore _send(_caller, FEE_TO, fee, false);
                        return true;
                    } else {
                        return false;
                    };
                };
                return true;
            };
            case(_){ return true; };
        };
    };
    private func _send(_from: AccountId, _to: AccountId, _value: Nat, _isCheck: Bool): Bool{
        var balance_from = _getBalance(_from);
        if (balance_from >= _value){
            if (not(_isCheck)) { 
                balance_from -= _value;
                _setBalance(_from, balance_from);
                var balance_to = _getBalance(_to);
                balance_to += _value;
                _setBalance(_to, balance_to);
            };
            return true;
        } else {
            return false;
        };
    };
    private func _mint(_to: AccountId, _value: Nat): Bool{
        var balance_to = _getBalance(_to);
        balance_to += _value;
        _setBalance(_to, balance_to);
        totalCoinSeconds := {
            coinSeconds = totalCoinSeconds.coinSeconds + totalSupply_ * (Int.abs(Time.now() - totalCoinSeconds.updateTime) / 1000000000); 
            updateTime = Time.now();
        };
        totalSupply_ += _value;
        return true;
    };
    private func _burn(_from: AccountId, _value: Nat, _isCheck: Bool): Bool{
        var balance_from = _getBalance(_from);
        if (balance_from >= _value){
            if (not(_isCheck)) { 
                balance_from -= _value;
                _setBalance(_from, balance_from);
                totalCoinSeconds := {
                    coinSeconds = totalCoinSeconds.coinSeconds + totalSupply_ * (Int.abs(Time.now() - totalCoinSeconds.updateTime) / 1000000000); 
                    updateTime = Time.now();
                };
                totalSupply_ -= _value;
            };
            return true;
        } else {
            return false;
        };
    };
    private func _lock(_from: AccountId, _value: Nat, _isCheck: Bool): Bool{
        var balance_from = _getBalance(_from);
        if (balance_from >= _value){
            if (not(_isCheck)) { 
                balance_from -= _value;
                _setBalance(_from, balance_from);
            };
            return true;
        } else {
            return false;
        };
    };
    private func _execute(_from: AccountId, _to: AccountId, _value: Nat, _fallback: Nat): Bool{
        var balance_from = _getBalance(_from) + _fallback;
        _setBalance(_from, balance_from);
        var balance_to = _getBalance(_to) + _value;
        _setBalance(_to, balance_to);
        return true;
    };
    private func _checkNonceAndGetData(_caller: AccountId, _data: ?Blob) : (Bool, [Nat8]){
        let data = Blob.toArray(Option.get(_data, Blob.fromArray([])));
        var isChecked: Bool = true;
        if (data.size() >= 9){
            let protocol = AID.slice(data, 0, ?2);
            let version: Nat8 = data[3];
            if (protocol[0] == 68 and protocol[1] == 82 and protocol[2] == 67 and data[4] == 1){
                let txnNonce = Nat32.toNat(Binary.BigEndian.toNat32(AID.slice(data, 5, ?8)));
                if (_getNonce(_caller) != txnNonce){
                    isChecked := false;
                };
            };
        };
        return (isChecked, data);
    };
    // Do not update state variables before calling _transfer
    private func _transfer(_msgCaller: Principal, _sa: ?[Nat8], _from: AccountId, _to: AccountId, _value: Nat, _nonce: ?Nat, _data: ?Blob,  
    _operation: Operation, _isAllowance: Bool): (result: TxnResult) {
        var callerPrincipal = _msgCaller;
        let caller = _getAccountIdFromPrincipal(_msgCaller, _sa);
        let txid = _getTxid(caller);
        let from = _from;
        let to = _to;
        let value = _value; 
        var gas = gas_;
        var allowed: Nat = 0; // *
        var spendValue = _value; // *
        if (_isAllowance){
            allowed := _getAllowance(from, caller);
        };
        let data = Option.get(_data, Blob.fromArray([]));
        if (data.size() > 65536){
            return #err({ code=#UndefinedError; message="The length of _data must be less than 65536B"; });
        };
        if (Option.isSome(_nonce) and _getNonce(caller) != Option.get(_nonce,0)){
            return #err({ code=#NonceError; message="Wrong nonce! The nonce value should be "#Nat.toText(_getNonce(caller)); });
        };
        // check and operate
        switch(_operation){
            case(#transfer(operation)){
                switch(operation.action){
                    case(#send){
                        if (not(_send(from, to, value, true))){
                            return #err({ code=#InsufficientBalance; message="Insufficient Balance"; });
                        } else if (_isAllowance and allowed < spendValue){
                            return #err({ code=#InsufficientAllowance; message="Insufficient Allowance"; });
                        };
                        ignore _send(from, to, value, false);
                        var as: [AccountId] = [from, to];
                        if (_isAllowance and spendValue > 0){
                            _setAllowance(from, caller, allowed - spendValue);
                            as := Array.append(as, [caller]);
                        };
                        _pushLastTxn(as, txid); 
                        _pushMessages(as, #onTransfer, txid);
                    };
                    case(#mint){
                        ignore _mint(to, value);
                        var as: [AccountId] = [to];
                        _pushLastTxn(as, txid); 
                        as := Array.append(as, [caller]);
                        _pushMessages(as, #onTransfer, txid);
                        gas := #noFee;
                    };
                    case(#burn){
                        if (not(_burn(from, value, true))){
                            return #err({ code=#InsufficientBalance; message="Insufficient Balance"; });
                        } else if (_isAllowance and allowed < spendValue){
                            return #err({ code=#InsufficientAllowance; message="Insufficient Allowance"; });
                        };
                        ignore _burn(from, value, false);
                        var as: [AccountId] = [from];
                        if (_isAllowance and spendValue > 0){
                            _setAllowance(from, caller, allowed - spendValue);
                            as := Array.append(as, [caller]);
                        };
                        _pushLastTxn(as, txid); 
                        _pushMessages(as, #onTransfer, txid);
                    };
                };
            };
            case(#lockTransfer(operation)){
                spendValue := operation.locked;
                if (not(_lock(from, operation.locked, true))){
                    return #err({ code=#InsufficientBalance; message="Insufficient Balance"; });
                } else if (_isAllowance and allowed < spendValue){
                    return #err({ code=#InsufficientAllowance; message="Insufficient Allowance"; });
                };
                ignore _lock(from, operation.locked, false);
                var as: [AccountId] = [from, to, operation.decider];
                if (_isAllowance and spendValue > 0){
                    _setAllowance(from, caller, allowed - spendValue);
                    as := Array.append(as, [caller]);
                };
                _pushLastTxn(as, txid);
                _pushMessages(as, #onLock, txid);
                _appendLockedTxn(from, txid);
            };
            case(#executeTransfer(operation)){
                spendValue := 0;
                ignore _execute(from, to, value, operation.fallback);
                var as: [AccountId] = [from, to, caller];
                _pushLastTxn(as, txid);
                _pushMessages(as, #onExecute, txid);
                _dropLockedTxn(from, operation.lockedTxid);
                gas := #noFee;
            };
            case(#approve(operation)){
                spendValue := 0;
                _setAllowance(from, to, operation.allowance); 
                var as: [AccountId] = [from, to];
                _pushLastTxn(as, txid);
                _pushMessages(as, #onApprove, txid);
                //callerPrincipal := Principal.fromText("2vxsx-fae");  // [4] Anonymous principal
            };
        };
        
        // insert record
        var txn: TxnRecord = {
            txid = txid;
            msgCaller = null; // If you want to maintain anonymity, you can hide the principal of the caller
            caller = caller;
            timestamp = Time.now();
            index = index;
            nonce = _getNonce(caller);
            gas = gas;
            transaction = {
                from = from;
                to = to;
                value = value; 
                operation = _operation;
                data = _data;
            };
        };
        _insertTxnRecord(txn); 
        // update nonce
        _addNonce(caller); 
        // push storeRecords
        storeRecords := List.push((txid, 0), storeRecords);
        return #ok(txid);
    };
    // records storage (DRC202 Standard)
    private func _drc202Store() : async (){
        let drc202: DRC202.Self = actor(STORAGE_CANISTER);
        var _storeRecords = List.nil<(Txid, Nat)>();
        let storageFee = await drc202.fee();
        var item = List.pop(storeRecords);
        while (Option.isSome(item.0)){
            storeRecords := item.1;
            switch(item.0){
                case(?(txid, callCount)){
                    if (callCount < MAX_STORAGE_TRIES){
                        switch(_getTxnRecord(txid)){
                            case(?(txn)){
                                try{
                                    Cycles.add(storageFee);
                                    await drc202.store(txn);
                                } catch(e){ //push
                                    _storeRecords := List.push((txid, callCount+1), _storeRecords);
                                };
                            };
                            case(_){};
                        };
                    };
                };
                case(_){};
            };
            item := List.pop(storeRecords);
        };
        storeRecords := _storeRecords;
    };
    // push and sort top100
    private func _pushTop100(_a: AccountId, _balance: Nat) : (){ 
        var top100 = Array.filter(top100_, func (v:(AccountId,Nat)): Bool { v.0 != _a });
        if (_balance >= top100Threshold){
            top100 := Array.append(top100, [(_a, _balance)]);
            top100 := Array.sort(top100, func (v1:(AccountId,Nat), v2:(AccountId,Nat)):Order.Order {
                //reverse order
                if (v1.1 > v2.1){
                    return #less;
                }else if (v1.1 == v2.1){
                    return #equal;
                }else{
                    return #greater;
                };
            });
            if (top100.size() > 200 and top100[200].1 > top100Threshold){
                top100Threshold := top100[200].1;
            };
        };
        top100_ := AID.slice(top100, 0, ?199);
    };
    // put first time
    private func _putFirstTime(_a: AccountId) : (){
        switch(Trie.get(firstTime, keyb(_a), Blob.equal)){
            case(?(ft)){};
            case(_){
                firstTime := Trie.put(firstTime, keyb(_a), Blob.equal, Time.now()).0;
            };
        };
    };

    /* 
    * Shared Functions
    */
    /// Returns standard name.
    public query func standard() : async Text{
        return standard_;
    };

    // dip20

    private func _receipt(_result: TxnResult) : DIP20.TxReceipt{
        switch(_result){
            case(#ok(txid)){
                switch(_getTxnRecord(txid)){
                    case(?(txn)){ return #Ok(txn.index) };
                    case(_){ return #Ok(0) };
                };
            };
            case(#err(err)){
                switch(err.code){
                    case(#InsufficientGas) { return #Err(#InsufficientBalance) };
                    case(#InsufficientAllowance) { return #Err(#InsufficientAllowance) };
                    case(#UndefinedError) { return #Err(#Other(err.message)) };
                    case(#InsufficientBalance) { return #Err(#InsufficientBalance) };
                    case(#NonceError) { return #Err(#Other(err.message)) };
                    case(#NoLockedTransfer) { return #Err(#Other(err.message)) };
                    case(#DuplicateExecutedTransfer) { return #Err(#Other(err.message)) };
                    case(#LockedTransferExpired) { return #Err(#Other(err.message)) };
                };
            };
        };
    };
    public shared(msg) func transfer(to: Principal, value: Nat) : async DIP20.TxReceipt {
        let _from = _getAccountIdFromPrincipal(msg.caller, null);
        let _to = _getAccountIdFromPrincipal(to, null);
        // dip20 does not support account-id, sub-account, nonce, attached data
        let res = await __transferFrom(msg.caller, _from, _to, value, null, null, null, false);
        return _receipt(res);
    };
    public shared(msg) func transferFrom(from: Principal, to: Principal, value: Nat) : async DIP20.TxReceipt {
        let _from = _getAccountIdFromPrincipal(from, null);
        let _to = _getAccountIdFromPrincipal(to, null);
        // dip20 does not support account-id, sub-account, nonce, attached data
        let res = await __transferFrom(msg.caller, _from, _to, value, null, null, null, true);
        return _receipt(res);
    };
    public shared(msg) func approve(spender: Principal, value: Nat) : async DIP20.TxReceipt {
        // dip20 does not support account-id, sub-account, nonce, attached data
        let res = await __approve(msg.caller, Principal.toText(spender), value, null, null, null);
        return _receipt(res);
    };
    private func _getLogo() : Text{
        for (meta in metadata_.vals()){
            if (meta.name == "logo" or meta.name == "Logo" or meta.name == "LOGO") { return meta.content; };
        };
        return "";
    };
    public query func logo() : async Text {
        return _getLogo();
    };
    public query func name() : async Text {
        return name_;
    };
    public query func symbol() : async Text {
        return symbol_;
    };
    public query func decimals() : async Nat8 {
        return decimals_;
    };
    public query func totalSupply() : async Nat {
        return totalSupply_;
    };
    private func _getFee() : Nat{
        switch(gas_){
            case(#token(v)){ return v; };
            case(_){ return 0; };  // When Cycles is used as gas, it is not represented properly.
        };
    };
    public query func getTokenFee() : async Nat {
        return _getFee();
    };
    public query func balanceOf(who: Principal) : async Nat {
        return _getBalance(_getAccountIdFromPrincipal(who, null));
    };
    public query func allowance(owner: Principal, spender: Principal) : async Nat {
        return _getAllowance(_getAccountIdFromPrincipal(owner, null), _getAccountIdFromPrincipal(spender, null));
    };
    public query func getMetadata() : async DIP20.Metadata {
        return {
            logo = _getLogo();
            name = name_;
            symbol = symbol_;
            decimals = decimals_;
            totalSupply = totalSupply_;
            owner = owner; // No owner
            fee = _getFee();
        };
    };
    public query func historySize() : async Nat {
        return index;
    };
    public query func getTokenInfo(): async DIP20.TokenInfo {
        return {
            metadata = {
                logo = _getLogo();
                name = name_;
                symbol = symbol_;
                decimals = decimals_;
                totalSupply = totalSupply_;
                owner = owner;
                fee = _getFee();
            };
            feeTo = Principal.fromText("aaaaa-aa"); // It indicates the blackhole address
            historySize = index;
            deployTime = 0; // No deployTime
            holderNumber = Trie.size(balances);
            cycles = Cycles.balance();
        };
    };

    // drc20

    /// Returns the name of the token.
    public query func drc20_name() : async Text{
        return name_;
    };
    /// Returns the symbol of the token.
    public query func drc20_symbol() : async Text{
        return symbol_;
    };
    /// Returns the number of decimals the token uses.
    public query func drc20_decimals() : async Nat8{
        return decimals_;
    };
    /// Returns the extend metadata info of the token.
    public query func drc20_metadata() : async [Metadata]{
        return metadata_;
    };
    /// Sends/donates cycles to the token canister in _account's name, and return cycles balance of the account/token.
    /// If the parameter `_account` is null, it means donation.
    public shared(msg) func drc20_cyclesReceive(_account: ?Address) : async (balance: Nat){
        return __cyclesReceive(msg.caller, _account);
    };
    private func __cyclesReceive(__caller: Principal, _account: ?Address) : (balance: Nat){
        let amount = Cycles.available(); 
        assert(amount >= 100000000);
        let accepted = Cycles.accept(amount); 
        var account = FEE_TO; //_getAccountIdFromPrincipal(Principal.fromActor(this));
        switch(_account){
            case(?(a)){
                account := _getAccountId(a);
            };
            case(_){};
        };
        let balance = _getCyclesBalances(account);
        _setCyclesBalances(account, balance + accepted);
        return balance + accepted;
    };

    /// Returns the cycles balance of the given account _owner in the token.
    public query func drc20_cyclesBalanceOf(_owner: Address) : async (balance: Nat){
        return _getCyclesBalances(_getAccountId(_owner));
    };
    /// Returns the transaction fee of the token.
    public query func drc20_gas() : async Gas{
        return gas_;
    };
    /// Returns the total token supply.
    public query func drc20_totalSupply() : async Amount{
        return totalSupply_;
    };
    /// Returns coinSeconds value
    public query func drc20_getCoinSeconds(_owner: ?Address) : async (totalCoinSeconds: CoinSeconds, accountCoinSeconds: ?CoinSeconds){
        return __getCoinSeconds(_owner);
    };
    private func __getCoinSeconds(_owner: ?Address) : (totalCoinSeconds: CoinSeconds, accountCoinSeconds: ?CoinSeconds){
        let now = Time.now();
        let newTotalCoinSeconds = { coinSeconds = totalCoinSeconds.coinSeconds + totalSupply_ * (Int.abs(now - totalCoinSeconds.updateTime) / 1000000000); updateTime = now; };
        switch(_owner){
            case(?(owner)){ 
                let account = _getAccountId(owner);
                switch(Trie.get(coinSeconds, keyb(account), Blob.equal)){ 
                    case(?(coinSecondsItem)){
                        let newAccountCoinSeconds = { coinSeconds = coinSecondsItem.coinSeconds + _getBalance(account) * (Int.abs(now - coinSecondsItem.updateTime) / 1000000000); updateTime = now; };
                        return (newTotalCoinSeconds, ?newAccountCoinSeconds);
                    };
                    case(_){ return (newTotalCoinSeconds, null); };
                };
            };
            case(_){ return (newTotalCoinSeconds, null); };
        };
    };
    /// Returns the account balance of the given account _owner, not including the locked balance.
    public query func drc20_balanceOf(_owner: Address) : async (balance: Amount){
        return _getBalance(_getAccountId(_owner));
    };
    /// Transfers _value amount of tokens from caller's account to address _to, returns type TxnResult.
    public shared(msg) func drc20_transfer(_to: To, _value: Amount, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) : async (result: TxnResult) {
        return await __transferFrom(msg.caller, _getAccountIdFromPrincipal(msg.caller, _sa), _getAccountId(_to), _value, _nonce, _sa, _data, false);
    };
    /// Transfers _value amount of tokens from address _from to address _to, returns type TxnResult.
    public shared(msg) func drc20_transferFrom(_from: From, _to: To, _value: Amount, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) : 
    async (result: TxnResult) {
        return await __transferFrom(msg.caller, _getAccountId(_from), _getAccountId(_to), _value, _nonce, _sa, _data, true);
    };
    private func __transferFrom(__caller: Principal, _from: AccountId, _to: AccountId, _value: Amount, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data, _isSpender: Bool) : 
    async (result: TxnResult) {
        let caller = _getAccountIdFromPrincipal(__caller, _sa);
        let from = _from;
        let to = _to;
        let operation: Operation = #transfer({ action = #send; });
        // check fee
        if(not(_checkFee(from, 100, _value))){
            return #err({ code=#InsufficientBalance; message="Insufficient Balance"; });
        };
        // transfer
        let res = _transfer(__caller, _sa, from, to, _value, _nonce, _data, operation, _isSpender);
        // publish
        let pub = _publish();
        // records storage (DRC202 Standard)
        let store = _drc202Store();
        // charge fee
        switch(res){
            case(#ok(v)){ ignore _chargeFee(from, 100); return res; };
            case(#err(v)){ return res; };
        };
    };
    /// Locks a transaction, specifies a `_decider` who can decide the execution of this transaction, 
    /// and sets an expiration period `_timeout` seconds after which the locked transaction will be unlocked.
    /// The parameter _timeout should not be greater than 64,000,000 seconds.
    public shared(msg) func drc20_lockTransfer(_to: To, _value: Amount, _timeout: Timeout, 
    _decider: ?Decider, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) : async (result: TxnResult) {
        return await __lockTransferFrom(msg.caller, _getAccountIdFromPrincipal(msg.caller, _sa), _getAccountId(_to), _value, _timeout, _decider, _nonce, _sa, _data, false);
    };
    /// `spender` locks a transaction.
    public shared(msg) func drc20_lockTransferFrom(_from: From, _to: To, _value: Amount, 
    _timeout: Timeout, _decider: ?Decider, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) : async (result: TxnResult) {
        return await __lockTransferFrom(msg.caller, _getAccountId(_from), _getAccountId(_to), _value, _timeout, _decider, _nonce, _sa, _data, true);
    };
    private func __lockTransferFrom(__caller: Principal, _from: AccountId, _to: AccountId, _value: Amount, 
    _timeout: Timeout, _decider: ?Decider, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data, _isSpender: Bool) : async (result: TxnResult) {
        if (_timeout > 64000000){
            return #err({ code=#UndefinedError; message="Parameter _timeout should not be greater than 64,000,000 seconds."; });
        };
        var decider: AccountId = _getAccountIdFromPrincipal(__caller, _sa);
        switch(_decider){
            case(?(v)){ decider := _getAccountId(v); };
            case(_){};
        };
        let operation: Operation = #lockTransfer({ 
            locked = _value;  // be locked for the amount
            expiration = Time.now() + Int32.toInt(Int32.fromNat32(_timeout)) * 1000000000;  
            decider = decider;
        });
        let from = _from;
        let to = _to;
        // check fee
        if(not(_checkFee(from, 100, _value))){
            return #err({ code=#InsufficientBalance; message="Insufficient Balance"; });
        };
        // transfer
        let res = _transfer(__caller, _sa, from, to, 0, _nonce, _data, operation, _isSpender);
        // publish
        let pub = _publish();
        // records storage (DRC202 Standard)
        let store = _drc202Store();
        // charge fee
        switch(res){
            case(#ok(v)){ ignore _chargeFee(from, 100); return res; };
            case(#err(v)){ return res; };
        };
    };
    /// The `decider` executes the locked transaction `_txid`, or the `owner` can fallback the locked transaction after the lock has expired.
    /// If the recipient of the locked transaction `_to` is decider, the decider can specify a new recipient `_to`.
    public shared(msg) func drc20_executeTransfer(_txid: Txid, _executeType: ExecuteType, _to: ?To, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) : async (result: TxnResult) {
        return await __executeTransfer(msg.caller, _txid, _executeType, _to, _nonce, _sa, _data);
    };
    private func __executeTransfer(__caller: Principal, _txid: Txid, _executeType: ExecuteType, _to: ?To, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) : async (result: TxnResult) {
        let txid = _txid;
        let caller = _getAccountIdFromPrincipal(__caller, _sa);
        // check fee
        // if(not(_checkFee(caller, 100, 0))){
        //     return #err({ code=#InsufficientGas; message="Insufficient Gas"; });
        // };
        switch(_getTxnRecord(txid)){
            case(?(txn)){
                let from = txn.transaction.from;
                var to = txn.transaction.to;
                switch(txn.transaction.operation){
                    case(#lockTransfer(v)){
                        if (not(_inLockedTxns(txid, from))){
                            return #err({ code=#DuplicateExecutedTransfer; message="The transaction has already been executed"; });
                        };
                        let locked = v.locked;
                        let expiration = v.expiration;
                        let decider = v.decider;
                        var fallback: Nat = 0;
                        switch(_to){
                            case(?(newTo)){ 
                                if (caller == decider and decider == to){
                                    to := _getAccountId(newTo); 
                                } else {
                                    return #err({ code=#UndefinedError; message="No permission to change the address `to`"; });
                                };
                            };
                            case(_){};
                        };
                        switch(_executeType){
                            case(#fallback){
                                if (not( caller == decider or (Time.now() > expiration and caller == from) )) {
                                    return #err({ code=#UndefinedError; message="No Permission"; });
                                };
                                fallback := locked;
                            };
                            case(#sendAll){
                                if (Time.now() > expiration){
                                    return #err({ code=#LockedTransferExpired; message="Locked Transfer Expired"; });
                                };
                                if (caller != decider){
                                    return #err({ code=#UndefinedError; message="No Permission"; });
                                };
                                fallback := 0;
                            };
                            case(#send(v)){
                                if (Time.now() > expiration){
                                    return #err({ code=#LockedTransferExpired; message="Locked Transfer Expired"; });
                                };
                                if (caller != decider){
                                    return #err({ code=#UndefinedError; message="No Permission"; });
                                };
                                fallback := locked - v;
                            };
                        };
                        var value: Nat = 0;
                        if (locked > fallback){
                            value := locked - fallback;
                        };
                        let operation: Operation = #executeTransfer({ 
                            lockedTxid = txid;  
                            fallback = fallback;
                        });
                        let res = _transfer(__caller, _sa, from, to, value, _nonce, _data, operation, false);
                        // publish
                        let pub = _publish();
                        // records storage (DRC202 Standard)
                        let store = _drc202Store();
                        // charge fee
                        // switch(res){
                        //     case(#ok(v)){ ignore _chargeFee(caller, 100); };
                        //     case(#err(v)){ };
                        // };
                        return res;
                    };
                    case(_){
                        return #err({ code=#NoLockedTransfer; message="No Locked Transfer"; });
                    };
                };
            };
            case(_){
                return #err({ code=#NoLockedTransfer; message="No Locked Transfer"; });
            };
        };
    };
    /// Queries the transaction records information.
    public query func drc20_txnQuery(_request: TxnQueryRequest) : async (response: TxnQueryResponse){
        return __txnQuery(_request);
    };
    private func __txnQuery(_request: TxnQueryRequest) : (response: TxnQueryResponse){
        switch(_request){
            case(#txnCountGlobal){
                return #txnCountGlobal(index);
            };
            case(#txnCount(args)){
                var account = _getAccountId(args.owner);
                return #txnCount(_getNonce(account));
            };
            case(#getTxn(args)){
                return #getTxn(_getTxnRecord(args.txid));
            };
            case(#lastTxidsGlobal){
                return #lastTxidsGlobal(_getGlobalLastTxns());
            };
            case(#lastTxids(args)){
                return #lastTxids(_getLastTxns(_getAccountId(args.owner)));
            };
            case(#lockedTxns(args)){
                var txids = _getLockedTxns(_getAccountId(args.owner));
                var lockedBalance: Nat = 0;
                var txns: [TxnRecord] = [];
                for (txid in txids.vals()){
                    switch(_getTxnRecord(txid)){
                        case(?(record)){
                            switch(record.transaction.operation){
                                case(#lockTransfer(v)){
                                    lockedBalance += v.locked;
                                };
                                case(_){};
                            };
                            txns := Array.append(txns, [record]);
                        };
                        case(_){};
                    };
                };
                return #lockedTxns({ lockedBalance = lockedBalance; txns = txns; });   
            };
            case(#getEvents(args)){
                switch(args.owner) {
                    case(null){
                        var i: Nat = 0;
                        return #getEvents(Array.chain(_getGlobalLastTxns(), func (value:Txid): [TxnRecord]{
                            if (i < MAX_CACHE_NUMBER_PER){
                                i += 1;
                                switch(_getTxnRecord(value)){
                                    case(?(r)){ return [r]; };
                                    case(_){ return []; };
                                };
                            }else{ return []; };
                        }));
                    };
                    case(?(address)){
                        return #getEvents(Array.chain(_getLastTxns(_getAccountId(address)), func (value:Txid): [TxnRecord]{
                            switch(_getTxnRecord(value)){
                                case(?(r)){ return [r]; };
                                case(_){ return []; };
                            };
                        }));
                    };
                };
            };
        };
    };
    /// returns txn record. It's an update method that will try to find txn record in the DRC202 canister if the record does not exist in the token canister.
    public shared func drc20_txnRecord(_txid: Txid) : async ?TxnRecord{
        return await __txnRecord(_txid);
    };
    private func __txnRecord(_txid: Txid) : async ?TxnRecord{
        let drc202: DRC202.Self = actor(STORAGE_CANISTER);
        var step: Nat = 0;
        func _getTxn(_token: Principal, _txid: Txid) : async ?TxnRecord{
            switch(await drc202.bucket(_token, _txid, step, null)){
                case(?(bucketId)){
                    let bucket: DRC202.Bucket = actor(Principal.toText(bucketId));
                    switch(await bucket.txn(_token, _txid)){
                        case(?(txn, time)){ return ?txn; };
                        case(_){
                            step += 1;
                            return await _getTxn(_token, _txid);
                        };
                    };
                };
                case(_){ return null; };
            };
        };
        switch(_getTxnRecord(_txid)){
            case(?(txn)){ return ?txn; };
            case(_){
                return await _getTxn(Principal.fromActor(this), _txid);
            };
        };
    };

    /// Subscribes to the token's messages, giving the callback function and the types of messages as parameters.
    public shared(msg) func drc20_subscribe(_callback: Callback, _msgTypes: [MsgType], _sa: ?Sa) : async Bool{
        return __subscribe(msg.caller, _callback, _msgTypes, _sa);
    };
    private func __subscribe(__caller: Principal, _callback: Callback, _msgTypes: [MsgType], _sa: ?Sa) : Bool{
        let caller = _getAccountIdFromPrincipal(__caller, _sa);
        assert(_chargeFee(caller, 100));
        let sub: Subscription = {
            callback = _callback;
            msgTypes = _msgTypes;
        };
        _setSubscription(caller, sub);
        return true;
    };
    /// Returns the subscription status of the subscriber `_owner`. 
    public query func drc20_subscribed(_owner: Address) : async (result: ?Subscription){
        return _getSubscription(_getAccountId(_owner));
    };
    /// Allows `_spender` to withdraw from your account multiple times, up to the `_value` amount.
    /// If this function is called again it overwrites the current allowance with `_value`. 
    public shared(msg) func drc20_approve(_spender: Spender, _value: Amount, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) : async (result: TxnResult){
        return await __approve(msg.caller, _spender, _value, _nonce, _sa, _data); 
    };
    private func __approve(__caller: Principal, _spender: Spender, _value: Amount, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) : async (result: TxnResult){
        let from = _getAccountIdFromPrincipal(__caller, _sa);
        let to = _getAccountId(_spender);
        let operation: Operation = #approve({ allowance = _value; });
        // check fee
        if(not(_checkFee(from, 100, 0))){
            return #err({ code=#InsufficientGas; message="Insufficient Gas"; });
        };
        // transfer
        let res = _transfer(__caller, _sa, from, to, 0, _nonce, _data, operation, false);
        // publish
        let pub = _publish();
        // records storage (DRC202 Standard)
        let store = _drc202Store();
        // charge fee
        switch(res){
            case(#ok(v)){ ignore _chargeFee(from, 100); return res; };
            case(#err(v)){ return res; };
        };
    };
    /// Returns the amount which `_spender` is still allowed to withdraw from `_owner`.
    public query func drc20_allowance(_owner: Address, _spender: Spender) : async (remaining: Amount) {
        return _getAllowance(_getAccountId(_owner), _getAccountId(_spender));
    };
    /// Returns all your approvals with a non-zero amount.
    public query func drc20_approvals(_owner: Address) : async (allowances: [Allowance]) {
        return _getAllowances(_getAccountId(_owner));
    };

    /* 
    * Owner's Management
    */
    public query func ictokens_getOwner() : async Principal{  //ict
        return owner;
    };
    public shared(msg) func ictokens_changeOwner(_newOwner: Principal) : async Bool{  //ict
        assert(_onlyOwner(msg.caller));
        owner := _newOwner;
        return true;
    };
    // config 
    public shared(msg) func ictokens_config(config: Config) : async Bool{ //ict
        assert(_onlyOwner(msg.caller));
        MAX_CACHE_TIME := Option.get(config.maxCacheTime, MAX_CACHE_TIME);
        MAX_CACHE_NUMBER_PER := Option.get(config.maxCacheNumberPer, MAX_CACHE_NUMBER_PER);
        FEE_TO := _getAccountId(Option.get(config.feeTo, Hex.encode(Blob.toArray(FEE_TO)))); 
        STORAGE_CANISTER := Option.get(config.storageCanister, STORAGE_CANISTER);
        MAX_PUBLICATION_TRIES := Option.get(config.maxPublicationTries, MAX_PUBLICATION_TRIES);
        MAX_STORAGE_TRIES := Option.get(config.maxStorageTries, MAX_STORAGE_TRIES);
        return true;
    };
    public query func ictokens_getConfig() : async Config{ //ict
        return { //ict
            maxCacheTime = ?MAX_CACHE_TIME;
            maxCacheNumberPer = ?MAX_CACHE_NUMBER_PER;
            feeTo = ?Hex.encode(Blob.toArray(FEE_TO));
            storageCanister = ?STORAGE_CANISTER;
            maxPublicationTries = ?MAX_PUBLICATION_TRIES;
            maxStorageTries = ?MAX_STORAGE_TRIES;
        };
    };
    public shared(msg) func ictokens_setMetadata(_metadata: [Metadata]) : async Bool{ //ict
        assert(_onlyOwner(msg.caller));
        metadata_ := _metadata;
        return true;
    };
    public shared(msg) func ictokens_setGas(_gas: Gas) : async Bool{ //ict
        assert(_onlyOwner(msg.caller));
        gas_ := _gas;
        return true;
    };

    /*
    * Extended functions
    */
    /// Withdrawal of cycles, only for the balance in his name
    public shared(msg) func ictokens_cyclesWithdraw(_wallet: Principal, _amount: Nat, _sa: ?Sa): async (){ //ict
        let cyclesWallet: CyclesWallet.Self = actor(Principal.toText(_wallet));
        var account = _getAccountIdFromPrincipal(msg.caller, _sa);
        let balance = _getCyclesBalances(account);
        assert(balance >= _amount);
        _setCyclesBalances(account, balance - _amount);
        Cycles.add(_amount);
        await cyclesWallet.wallet_receive();
    };
    /// top100
    public query func ictokens_top100() : async [(Address, Nat)]{
        return Array.map<(AccountId, Nat), (Address, Nat)>(AID.slice(top100_, 0, ?99), func (item: (AccountId, Nat)): (Address, Nat){
            return (Hex.encode(Blob.toArray(item.0)), item.1);
        });
    };
    /// held first time 
    public query func ictokens_heldFirstTime(_owner: Address) : async ?Time.Time{
        let account = _getAccountId(_owner);
        return Trie.get(firstTime, keyb(account), Blob.equal);
    };
    /// Snapshot
    public shared(msg) func ictokens_snapshot(_threshold: Amount) : async Bool{  //ict
        assert(_onlyOwner(msg.caller));
        let balancesTrie = Trie.filter(balances, func (key:AccountId, value:Nat):Bool{ value >= _threshold });
        balancesSnapshot := Array.append(balancesSnapshot, [(balancesTrie, Time.now())]);
        return true;
    };
    public shared(msg) func ictokens_clearSnapshot() : async Bool{  //ict
        assert(_onlyOwner(msg.caller));
        balancesSnapshot := [];
        return true;
    };
    // _snap=0,1,2...  _page=1,2,3...  page-size:200   
    public query func ictokens_getSnapshot(_snap: Nat, _page: Nat) : async (Time.Time, [(AccountId, Nat)], Bool){ 
        let (balances_,snapTime) = balancesSnapshot[_snap];
        let length = Trie.size(balances_);
        var isEnd = false;
        let from = Nat.sub(Nat.max(_page,1), 1) * 200;
        if (from+199 >= length){ isEnd := true; };
        let arr = AID.slice(Trie.toArray(balances_, func (k:AccountId, v:Nat):((AccountId, Nat)){ (k, v) }), from, ?(from+199));
        return (snapTime, arr, isEnd);
    };
    public query func ictokens_snapshotBalanceOf(_snap: Nat, _owner: Address) : async (Time.Time, ?Nat) {
        let (balances_,snapTime) = balancesSnapshot[_snap];
        let account = _getAccountId(_owner);
        return (snapTime, Trie.get(balances_, keyb(account), Blob.equal));
    };

    /// canister memory
    public query func getMemory() : async (Nat,Nat,Nat,Nat32){
        return (Prim.rts_memory_size(), Prim.rts_heap_size(), Prim.rts_total_allocation(),Prim.stableMemorySize());
    };

    // DRC207 ICMonitor
    /// DRC207 support
    public func drc207() : async DRC207.DRC207Support{
        return {
            monitorable_by_self = true;
            monitorable_by_blackhole = { allowed = true; canister_id = ?Principal.fromText("7hdtw-jqaaa-aaaak-aaccq-cai"); };
            cycles_receivable = true;
            timer = { enable = false; interval_seconds = null; }; 
        };
    };
    /// canister_status
    public func canister_status() : async DRC207.canister_status {
        let ic : DRC207.IC = actor("aaaaa-aa");
        await ic.canister_status({ canister_id = Principal.fromActor(this) });
    };
    /// receive cycles
    public func wallet_receive(): async (){
        let amout = Cycles.available();
        let accepted = Cycles.accept(amout);
    };
    /// timer tick
    // public func timer_tick(): async (){
    //     //
    // };


    /* 
    * Genesis
    */
    private stable var genesisCreated: Bool = false;
    if (not(genesisCreated)){
        balances := Trie.put(balances, keyb(founder_), Blob.equal, totalSupply_).0;
        coinSeconds := Trie.put(coinSeconds, keyb(founder_), Blob.equal, {coinSeconds = 0; updateTime = Time.now()}).0;
        var txn: TxnRecord = {
            txid = Blob.fromArray([0:Nat8,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]);
            msgCaller = ?installMsg.caller;
            caller = AID.principalToAccountBlob(installMsg.caller, null);
            timestamp = Time.now();
            index = index;
            nonce = 0;
            gas = #noFee;
            transaction = {
                from = AID.blackhole();
                to = founder_;
                value = totalSupply_; 
                operation = #transfer({ action = #mint; });
                data = null;
            };
        };
        index += 1;
        nonces := Trie.put(nonces, keyb(AID.principalToAccountBlob(installMsg.caller, null)), Blob.equal, 1).0;
        txnRecords := Trie.put(txnRecords, keyb(txn.txid), Blob.equal, txn).0;
        globalTxns := Deque.pushFront(globalTxns, (txn.txid, Time.now()));
        globalLastTxns := Deque.pushFront(globalLastTxns, txn.txid);
        lastTxns_ := Trie.put(lastTxns_, keyb(founder_), Blob.equal, Deque.pushFront(Deque.empty<Txid>(), txn.txid)).0;
        genesisCreated := true;
        // push storeRecords
        storeRecords := List.push((txn.txid, 0), storeRecords);
    };

};
