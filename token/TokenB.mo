/**
 * Module     : DRC20.mo
 * Author     : ICLighthouse Team
 * License    : Apache License 2.0
 * Stability  : Experimental
 * Github     : https://github.com/iclighthouse/DRC_standards/
 */

import HashMap "mo:base/HashMap";
import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Option "mo:base/Option";
import Blob "mo:base/Blob";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Int "mo:base/Int";
import Int32 "mo:base/Int32";
import Iter "mo:base/Iter";
import List "mo:base/List";
import Time "mo:base/Time";
import Deque "mo:base/Deque";
import Cycles "mo:base/ExperimentalCycles";
import Types "./lib/DRC20";
import AID "./lib/AID";
import Hex "./lib/Hex";
import Binary "./lib/Binary";
import SHA224 "./lib/SHA224";
import DRC202 "./lib/DRC202";

//record { totalSupply=1000000000000; decimals=8; gas=variant{token=10}; name=opt "TokenTest"; symbol=opt "TTT"; metadata=null; founder=null;} 
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

    /*
    * Config 
    */
    private stable var MAX_CACHE_TIME: Int = 3 * 30 * 24 * 3600 * 1000000000; // 3 months
    private stable var MAX_CACHE_NUMBER_PER: Nat = 100; 
    private stable var FEE_TO: AccountId = AID.blackhole();  
    private stable var STORAGE_CANISTER: Text = /* test */"iq2ev-rqaaa-aaaak-aagba-cai"; // /* main */"y5a36-liaaa-aaaak-aacqa-cai";
    private stable var MAX_PUBLICATION_TRIES: Nat = 2; 
    private stable var MAX_STORAGE_TRIES: Nat = 2; 

    /* 
    * State Variables 
    */
    private stable var standard_: Text = "DRC20 1.0"; 
    //private stable var owner: Principal = installMsg.caller; 
    private stable var name_: Text = Option.get(initArgs.name, "");
    private stable var symbol_: Text = Option.get(initArgs.symbol, "");
    private stable let decimals_: Nat8 = initArgs.decimals;
    private stable var totalSupply_: Nat = initArgs.totalSupply;
    private stable var totalCoinSeconds: CoinSeconds = {coinSeconds = 0; updateTime = Time.now()};
    private stable var gas_: Gas = initArgs.gas;
    private stable var metadata_: [Metadata] = Option.get(initArgs.metadata, []);
    private var txnRecords = HashMap.HashMap<Txid, TxnRecord>(1, Blob.equal, Blob.hash);
    private stable var globalTxns = Deque.empty<(Txid, Time.Time)>();
    private stable var globalLastTxns = Deque.empty<Txid>();
    private stable var index: Nat = 0;
    private var balances = HashMap.HashMap<AccountId, Nat>(1, Blob.equal, Blob.hash);
    private var coinSeconds = HashMap.HashMap<AccountId, CoinSeconds>(1, Blob.equal, Blob.hash);
    private var nonces = HashMap.HashMap<AccountId, Nat>(1, Blob.equal, Blob.hash);
    private var lastTxns_ = HashMap.HashMap<AccountId, Deque.Deque<Txid>>(1, Blob.equal, Blob.hash); //from to caller
    private var lockedTxns_ = HashMap.HashMap<AccountId, [Txid]>(1, Blob.equal, Blob.hash); //from
    private var allowances = HashMap.HashMap<AccountId, HashMap.HashMap<AccountId, Nat>>(1, Blob.equal, Blob.hash);
    private var subscriptions = HashMap.HashMap<AccountId, Subscription>(1, Blob.equal, Blob.hash);
    private var cyclesBalances = HashMap.HashMap<AccountId, Nat>(1, Blob.equal, Blob.hash);
    private stable var storeRecords = List.nil<(Txid, Nat)>();
    private stable var publishMessages = List.nil<(AccountId, MsgType, Txid, Nat)>();
    // only for upgrade
    private stable var txnRecordsEntries : [(Txid, TxnRecord)] = [];
    private stable var balancesEntries : [(AccountId, Nat)] = [];
    private stable var coinSecondsEntries : [(AccountId, CoinSeconds)] = [];
    private stable var noncesEntries : [(AccountId, Nat)] = [];
    private stable var lastTxns_Entries : [(AccountId, Deque.Deque<Txid>)] = [];
    private stable var lockedTxns_Entries : [(AccountId, [Txid])] = [];
    private stable var allowancesEntries : [(AccountId, [(AccountId, Nat)])] = [];
    private stable var subscriptionsEntries : [(AccountId, Subscription)] = [];
    private stable var cyclesBalancesEntries : [(AccountId, Nat)] = [];
    
    /* 
    * Local Functions
    */
    // private func _onlyOwner(_caller: Principal) : Bool { 
    //     return _caller == owner;
    // };  // assert(_onlyOwner(msg.caller));
    private func _getTxnRecord(_txid: Txid): ?TxnRecord{
        return txnRecords.get(_txid);
    };
    private func _insertTxnRecord(_txn: TxnRecord): (){
        var txid = _txn.txid;
        txnRecords.put(txid, _txn);
        _pushGlobalTxns(txid);
    };
    private func _deleteTxnRecord(_txid: Txid, _isDeep: Bool): (){
        switch(txnRecords.get(_txid)){
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
                        txnRecords.delete(_txid);
                    } else if (_isDeep and not(_inLastTxns(_txid, caller)) and 
                        not(_inLastTxns(_txid, from)) and not(_inLastTxns(_txid, to))) {
                        switch(record.transaction.operation){
                            case(#lockTransfer(v)){ 
                                if (not(_inLastTxns(_txid, v.decider))){
                                    txnRecords.delete(_txid);
                                };
                            };
                            case(_){
                                txnRecords.delete(_txid);
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
        switch(balances.get(_a)){
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
        let coinSecondsItem = Option.get(coinSeconds.get(_a), {coinSeconds = 0; updateTime = now });
        let newCoinSeconds = coinSecondsItem.coinSeconds + originalValue * (Int.abs(now - coinSecondsItem.updateTime) / 1000000000);
        coinSeconds.put(_a, {coinSeconds = newCoinSeconds; updateTime = now});
        if(_v == 0){
            balances.delete(_a);
        } else {
            balances.put(_a, _v);
            switch (gas_){
                case(#token(fee)){
                    if (_v < fee/2){
                        ignore _burn(_a, _v, false);
                    };
                };
                case(_){};
            }
        };
    };
    private func _getNonce(_a: AccountId): Nat{
        switch(nonces.get(_a)){
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
        nonces.put(_a, n+1);
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
        switch(lastTxns_.get(_a)){
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
        switch(lastTxns_.get(_a)){
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
        switch(lastTxns_.get(_a)){
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
                    lastTxns_.delete(_a);
                }else{
                    lastTxns_.put(_a, txids);
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
                switch(lastTxns_.get(_as[i])){
                    case(?(q)){
                        var txids: Deque.Deque<Txid> = q;
                        txids := Deque.pushFront(txids, _txid);
                        lastTxns_.put(_as[i], txids);
                        _cleanLastTxns(_as[i]);
                    };
                    case(_){
                        var new = Deque.empty<Txid>();
                        new := Deque.pushFront(new, _txid);
                        lastTxns_.put(_as[i], new);
                    };
                };
            };
        };
    };
    private func _inLockedTxns(_txid: Txid, _a: AccountId): Bool{
        switch(lockedTxns_.get(_a)){
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
        switch(lockedTxns_.get(_a)){
            case(?(txids)){
                return txids;
            };
            case(_){
                return [];
            };
        };
    };
    private func _appendLockedTxn(_a: AccountId, _txid: Txid): (){
        switch(lockedTxns_.get(_a)){
            case(?(arr)){
                var txids: [Txid] = arr;
                txids := Array.append([_txid], txids);
                lockedTxns_.put(_a, txids);
            };
            case(_){
                lockedTxns_.put(_a, [_txid]);
            };
        };
    };
    private func _dropLockedTxn(_a: AccountId, _txid: Txid): (){
        switch(lockedTxns_.get(_a)){
            case(?(arr)){
                var txids: [Txid] = arr;
                txids := Array.filter(txids, func (t: Txid): Bool { t != _txid });
                if (txids.size() == 0){
                    lockedTxns_.delete(_a);
                };
                lockedTxns_.put(_a, txids);
                _deleteTxnRecord(_txid, true);
            };
            case(_){};
        };
    };
    private func _getAllowances(_a: AccountId): [Allowance]{
        switch(allowances.get(_a)){
            case(?(allowHashMap)){
                var a = Iter.map(allowHashMap.entries(), func (entry: (AccountId, Nat)): Allowance{
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
        switch(allowances.get(_a)){
            case(?(hm)){
                switch(hm.get(_s)){
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
        switch(allowances.get(_a)){
            case(?(hm)){
                if (_v > 0){
                    hm.put(_s, _v);
                } else {
                    hm.delete(_s);
                };
                //allowances.put(_a, hm);
                if (hm.size() == 0){
                    allowances.delete(_a);
                };
            };
            case(_){
                if (_v > 0){
                    var new = HashMap.HashMap<AccountId, Nat>(1, Blob.equal, Blob.hash);
                    new.put(_s, _v);
                    allowances.put(_a, new);
                };
            };
        };
    };
    private func _getSubscription(_a: AccountId): ?Subscription{
        return subscriptions.get(_a);
    };
    private func _getSubCallback(_a: AccountId, _mt: MsgType): ?Callback{
        switch(subscriptions.get(_a)){
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
            subscriptions.delete(_a);
        } else{
            subscriptions.put(_a, _sub);
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
        switch(cyclesBalances.get(_a)){
            case(?(balance)){ return balance; };
            case(_){ return 0; };
        };
    };
    private func _setCyclesBalances(_a: AccountId, _v: Nat) : (){
        if(_v == 0){
            cyclesBalances.delete(_a);
        } else {
            switch (gas_){
                case(#cycles(fee)){
                    if (_v < fee/2){
                        cyclesBalances.delete(_a);
                    } else{
                        cyclesBalances.put(_a, _v);
                    };
                };
                case(_){
                    cyclesBalances.put(_a, _v);
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
    // Do not update state variables before calling _transfer
    private func _transfer(_msgCaller: Principal, _sa: ?[Nat8], _from: AccountId, _to: AccountId, _value: Nat, _nonce: ?Nat, _data: ?Blob, 
    _operation: Operation, _isAllowance: Bool): (result: TxnResult) {
        var callerPrincipal = _msgCaller;
        let caller = _getAccountIdFromPrincipal(_msgCaller, _sa);
        let txid = _getTxid(caller);
        let from = _from;
        let to = _to;
        let value = _value; 
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
            gas = gas_;
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

    /* 
    * Shared Functions
    */
    /// Returns standard name.
    public query func standard() : async Text{
        return standard_;
    };
    /// Returns the name of the token.
    public query func name() : async Text{
        return name_;
    };
    /// Returns the symbol of the token.
    public query func symbol() : async Text{
        return symbol_;
    };
    /// Returns the number of decimals the token uses.
    public query func decimals() : async Nat8{
        return decimals_;
    };
    /// Returns the extend metadata info of the token.
    public query func metadata() : async [Metadata]{
        return metadata_;
    };
    /// Sends/donates cycles to the token canister in _account's name, and return cycles balance of the account/token.
    /// If the parameter `_account` is null, it means donation.
    public shared(msg) func cyclesReceive(_account: ?Address) : async (balance: Nat){
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
    public query func cyclesBalanceOf(_owner: Address) : async (balance: Nat){
        var account = _getAccountId(_owner);
        return _getCyclesBalances(account);
    };
    /// Returns the transaction fee of the token.
    public query func gas() : async Gas{
        return gas_;
    };
    /// Returns the total token supply.
    public query func totalSupply() : async Amount{
        return totalSupply_;
    };
    /// Returns coinSeconds value
    public query func getCoinSeconds(_owner: ?Address) : async (totalCoinSeconds: CoinSeconds, accountCoinSeconds: ?CoinSeconds){
        let now = Time.now();
        let newTotalCoinSeconds = { coinSeconds = totalCoinSeconds.coinSeconds + totalSupply_ * (Int.abs(now - totalCoinSeconds.updateTime) / 1000000000); updateTime = now; };
        switch(_owner){
            case(?(owner)){ 
                let account = _getAccountId(owner);
                switch(coinSeconds.get(account)){
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
    public query func balanceOf(_owner: Address) : async (balance: Amount){
        return _getBalance(_getAccountId(_owner));
    };
    /// Transfers _value amount of tokens from caller's account to address _to, returns type TxnResult.
    public shared(msg) func transfer(_to: To, _value: Amount, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) : async (result: TxnResult) {
        let from = _getAccountIdFromPrincipal(msg.caller, _sa);
        let to = _getAccountId(_to);
        let operation: Operation = #transfer({ action = #send; });
        // check fee
        if(not(_checkFee(from, 100, _value))){
            return #err({ code=#InsufficientGas; message="Insufficient Gas"; });
        };
        // transfer
        let res = _transfer(msg.caller, _sa, from, to, _value, _nonce, _data, operation, false);
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
    /// Transfers _value amount of tokens from address _from to address _to, returns type TxnResult.
    public shared(msg) func transferFrom(_from: From, _to: To, _value: Amount, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) : 
    async (result: TxnResult) {
        let caller = _getAccountIdFromPrincipal(msg.caller, _sa);
        let from = _getAccountId(_from);
        let to = _getAccountId(_to);
        let operation: Operation = #transfer({ action = #send; });
        // check fee
        if(not(_checkFee(from, 100, _value))){
            return #err({ code=#InsufficientGas; message="Insufficient Gas"; });
        };
        // transfer
        let res = _transfer(msg.caller, _sa, from, to, _value, _nonce, _data, operation, true);
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
    /// The parameter _timeout should not be greater than 1000000 seconds.
    public shared(msg) func lockTransfer(_to: To, _value: Amount, _timeout: Timeout, 
    _decider: ?Decider, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) : async (result: TxnResult) {
        if (_timeout > 1000000){
            return #err({ code=#UndefinedError; message="_timeout should not be greater than 1000000 seconds."; });
        };
        var decider: AccountId = _getAccountIdFromPrincipal(msg.caller, _sa);
        switch(_decider){
            case(?(v)){ decider := _getAccountId(v); };
            case(_){};
        };
        let operation: Operation = #lockTransfer({ 
            locked = _value;  // be locked for the amount
            expiration = Time.now() + Int32.toInt(Int32.fromNat32(_timeout)) * 1000000000;  
            decider = decider;
        });
        let from = _getAccountIdFromPrincipal(msg.caller, _sa);
        let to = _getAccountId(_to);
        // check fee
        if(not(_checkFee(from, 100, _value))){
            return #err({ code=#InsufficientGas; message="Insufficient Gas"; });
        };
        // transfer
        let res = _transfer(msg.caller, _sa, from, to, 0, _nonce, _data, operation, false);
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
    /// `spender` locks a transaction.
    public shared(msg) func lockTransferFrom(_from: From, _to: To, _value: Amount, 
    _timeout: Timeout, _decider: ?Decider, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) : async (result: TxnResult) {
        if (_timeout > 1000000){
            return #err({ code=#UndefinedError; message="_timeout should not be greater than 1000000 seconds."; });
        };
        var decider: AccountId = _getAccountIdFromPrincipal(msg.caller, _sa);
        switch(_decider){
            case(?(v)){ decider := _getAccountId(v); };
            case(_){};
        };
        let operation: Operation = #lockTransfer({ 
            locked = _value;  // be locked for the amount
            expiration = Time.now() + Int32.toInt(Int32.fromNat32(_timeout)) * 1000000000;  
            decider = decider;
        });
        let caller = _getAccountIdFromPrincipal(msg.caller, _sa);
        let from = _getAccountId(_from);
        let to = _getAccountId(_to);
        // check fee
        if(not(_checkFee(from, 100, _value))){
            return #err({ code=#InsufficientGas; message="Insufficient Gas"; });
        };
        // transfer
        let res = _transfer(msg.caller, _sa, from, to, 0, _nonce, _data, operation, true);
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
    public shared(msg) func executeTransfer(_txid: Txid, _executeType: ExecuteType, _to: ?To, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) : async (result: TxnResult) {
        let txid = _txid;
        let caller = _getAccountIdFromPrincipal(msg.caller, _sa);
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
                        let res = _transfer(msg.caller, _sa, from, to, value, _nonce, _data, operation, false);
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
    public query func txnQuery(_request: TxnQueryRequest) : async (response: TxnQueryResponse){
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
    public shared func txnRecord(_txid: Txid) : async ?TxnRecord{
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
    public shared(msg) func subscribe(_callback: Callback, _msgTypes: [MsgType], _sa: ?Sa) : async Bool{
        let caller = _getAccountIdFromPrincipal(msg.caller, _sa);
        assert(_chargeFee(caller, 100));
        let sub: Subscription = {
            callback = _callback;
            msgTypes = _msgTypes;
        };
        _setSubscription(caller, sub);
        return true;
    };
    /// Returns the subscription status of the subscriber `_owner`. 
    public query func subscribed(_owner: Address) : async (result: ?Subscription){
        return _getSubscription(_getAccountId(_owner));
    };
    /// Allows `_spender` to withdraw from your account multiple times, up to the `_value` amount.
    /// If this function is called again it overwrites the current allowance with `_value`. 
    public shared(msg) func approve(_spender: Spender, _value: Amount, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) : async (result: TxnResult){
        let from = _getAccountIdFromPrincipal(msg.caller, _sa);
        let to = _getAccountId(_spender);
        let operation: Operation = #approve({ allowance = _value; });
        // check fee
        if(not(_checkFee(from, 100, 0))){
            return #err({ code=#InsufficientGas; message="Insufficient Gas"; });
        };
        // transfer
        let res = _transfer(msg.caller, _sa, from, to, 0, _nonce, _data, operation, false);
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
    public query func allowance(_owner: Address, _spender: Spender) : async (remaining: Amount) {
        return _getAllowance(_getAccountId(_owner), _getAccountId(_spender));
    };
    /// Returns all your approvals with a non-zero amount.
    public query func approvals(_owner: Address) : async (allowances: [Allowance]) {
        return _getAllowances(_getAccountId(_owner));
    };

    /* 
    * Genesis
    */
    private stable var genesisCreated: Bool = false;
    if (not(genesisCreated)){
        balances.put(founder_, totalSupply_);
        coinSeconds.put(founder_, {coinSeconds = 0; updateTime = Time.now()});
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
        nonces.put(AID.principalToAccountBlob(installMsg.caller, null), 1);
        txnRecords.put(txn.txid, txn);
        globalTxns := Deque.pushFront(globalTxns, (txn.txid, Time.now()));
        globalLastTxns := Deque.pushFront(globalLastTxns, txn.txid);
        lastTxns_.put(founder_, Deque.pushFront(Deque.empty<Txid>(), txn.txid));
        genesisCreated := true;
        // push storeRecords
        storeRecords := List.push((txn.txid, 0), storeRecords);
    };

};