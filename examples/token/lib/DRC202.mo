/**
 * Module     : DRC202.mo
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Description: DRC202 Token Records Storage.
 * Refers     : https://github.com/iclighthouse/
 * Canister   : y5a36-liaaa-aaaak-aacqa-cai
 */

import Array "mo:base/Array";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Hash "mo:base/Hash";
import Blob "mo:base/Blob";
import Option "mo:base/Option";
import Time "mo:base/Time";
import List "mo:base/List";
import Deque "mo:base/Deque";
import Trie "mo:base/Trie";
import Iter "mo:base/Iter";
import Cycles "mo:base/ExperimentalCycles";
import SHA224 "./SHA224";
import CRC32 "./CRC32";
import T "DRC202Types";

module {
    public type Address = T.Address;
    public type Txid = T.Txid;
    public type AccountId = T.AccountId;
    public type Token = T.Token;
    public type Gas = T.Gas;
    public type Operation = T.Operation;
    public type TxnRecord = T.TxnRecord;
    public type Proxy = T.Self;
    public type Bucket = T.Bucket;
    public type Setting = T.Setting;
    public type Config = T.Config;
    public type DataTemp = {
        setting: Setting;
        txnRecords: Trie.Trie<Txid, TxnRecord>;
        globalTxns: Deque.Deque<(Txid, Time.Time)>;
        globalLastTxns: Deque.Deque<Txid>;
        lastTxns_: Trie.Trie<AccountId, Deque.Deque<Txid>>; 
        lockedTxns_: Trie.Trie<AccountId, [Txid]>; 
        storeRecords: List.List<(Txid, Nat)>;
    };

    public class DRC202(_setting: Setting, _tokenStd: Text){
        var hasSetStd: Bool = false;
        var setting: Setting = _setting;
        var txnRecords: Trie.Trie<Txid, TxnRecord> = Trie.empty(); 
        var globalTxns = Deque.empty<(Txid, Time.Time)>(); 
        var globalLastTxns = Deque.empty<Txid>(); 
        var lastTxns_: Trie.Trie<AccountId, Deque.Deque<Txid>> = Trie.empty();
        var lockedTxns_: Trie.Trie<AccountId, [Txid]> = Trie.empty();
        var storeRecords = List.nil<(Txid, Nat)>(); 
        var errCount: Nat = 0;
        public func getErrCount() : Nat{ errCount };

        private func keyp(t: Principal) : Trie.Key<Principal> { return { key = t; hash = Principal.hash(t) }; };
        private func keyb(t: Blob) : Trie.Key<Blob> { return { key = t; hash = Blob.hash(t) }; };

        private func pushGlobalTxns(_txid: Txid): (){ 
            // push new txid.
            globalTxns := Deque.pushFront(globalTxns, (_txid, Time.now()));
            globalLastTxns := Deque.pushFront(globalLastTxns, _txid);
            var size = List.size(globalLastTxns.0) + List.size(globalLastTxns.1);
            while (size > setting.MAX_CACHE_NUMBER_PER){
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
                    while (Time.now() - timestamp > setting.MAX_CACHE_TIME){
                        switch (Deque.popBack(globalTxns)){
                            case(?(q, v)){
                                globalTxns := q;
                                deleteTxnRecord(v.0, false); // delete the record.
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
        private func inLastTxns(_txid: Txid, _a: AccountId): Bool{
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
        private func deleteTxnRecord(_txid: Txid, _isDeep: Bool): (){
            switch(Trie.get(txnRecords, keyb(_txid), Blob.equal)){
                case(?(record)){ //Existence record
                    var caller = record.caller;
                    var from = record.transaction.from;
                    var to = record.transaction.to;
                    var timestamp = record.timestamp;
                    if (not(inLockedTxns(_txid, from))){ //Not in from's LockedTxns
                        if (Time.now() - timestamp > setting.MAX_CACHE_TIME){ //Expired
                            cleanLastTxns(caller);
                            cleanLastTxns(from);
                            cleanLastTxns(to);
                            switch(record.transaction.operation){
                                case(#lockTransfer(v)){ cleanLastTxns(v.decider); };
                                case(_){};
                            };
                            txnRecords := Trie.remove(txnRecords, keyb(_txid), Blob.equal).0;
                        } else if (_isDeep and not(inLastTxns(_txid, caller)) and 
                            not(inLastTxns(_txid, from)) and not(inLastTxns(_txid, to))) {
                            switch(record.transaction.operation){
                                case(#lockTransfer(v)){ 
                                    if (not(inLastTxns(_txid, v.decider))){
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
        private func cleanLastTxns(_a: AccountId): (){
            switch(Trie.get(lastTxns_, keyb(_a), Blob.equal)){
                case(?(q)){  
                    var txids: Deque.Deque<Txid> = q;
                    var size = List.size(txids.0) + List.size(txids.1);
                    while (size > setting.MAX_CACHE_NUMBER_PER){
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
                            let txn_ = getTxnRecord(txid);
                            switch(txn_){
                                case(?(txn)){
                                    var timestamp = txn.timestamp;
                                    while (Time.now() - timestamp > setting.MAX_CACHE_TIME and size > 0){
                                        switch (Deque.popBack(txids)){
                                            case(?(q, v)){
                                                txids := q;
                                                size -= 1;
                                            };
                                            case(_){};
                                        };
                                        switch(Deque.peekBack(txids)){
                                            case(?(txid)){
                                                let txn_ = getTxnRecord(txid);
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
        private func getTxnRecord(_txid: Txid): ?TxnRecord{
            return Trie.get(txnRecords, keyb(_txid), Blob.equal);
        };
        private func insertTxnRecord(_txn: TxnRecord): (){
            var txid = _txn.txid;
            assert(Blob.toArray(txid).size() == 32);
            assert(Blob.toArray(_txn.caller).size() == 32);
            assert(Blob.toArray(_txn.transaction.from).size() == 32 and Blob.toArray(_txn.transaction.to).size() == 32);
            txnRecords := Trie.put(txnRecords, keyb(txid), Blob.equal, _txn).0;
            storeRecords := List.push((txid, 0), storeRecords);
            pushGlobalTxns(txid);
            //pushLastTxn
        };
        private func getTxnRecord2(_token: Principal, _txid: Txid) : async (txn: ?TxnRecord){
            var step: Nat = 0;
            func _getTxn(_token: Principal, _txid: Txid) : async ?TxnRecord{
                switch(await drc202().bucket(_token, _txid, step, null)){
                    case(?(bucketId)){
                        let bucket: T.Bucket = actor(Principal.toText(bucketId));
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
            switch(getTxnRecord(_txid)){
                case(?(txn)){ return ?txn; };
                case(_){
                    return await _getTxn(_token, _txid);
                };
            };
        };
        public func getAccountId(p : Principal, sa: ?[Nat8]) : Blob {
            let data = Blob.toArray(Principal.toBlob(p));
            let ads : [Nat8] = [10, 97, 99, 99, 111, 117, 110, 116, 45, 105, 100]; //b"\x0Aaccount-id"
            var _sa : [Nat8] = [0:Nat8,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
            _sa := Option.get(sa, _sa);
            var hash : [Nat8] = SHA224.sha224(T.arrayAppend(T.arrayAppend(ads, data), _sa));
            var crc : [Nat8] = CRC32.crc32(hash);
            return Blob.fromArray(T.arrayAppend(crc, hash));                     
        };

        // public methods
        public func pushLastTxn(_as: [AccountId], _txid: Txid): (){
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
                            cleanLastTxns(_as[i]);
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
        public func inLockedTxns(_txid: Txid, _a: AccountId): Bool{
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
        public func getLockedTxns(_a: AccountId): [Txid]{
            switch(Trie.get(lockedTxns_, keyb(_a), Blob.equal)){
                case(?(txids)){
                    return txids;
                };
                case(_){
                    return [];
                };
            };
        };
        public func appendLockedTxn(_a: AccountId, _txid: Txid): (){
            switch(Trie.get(lockedTxns_, keyb(_a), Blob.equal)){
                case(?(arr)){
                    var txids: [Txid] = arr;
                    txids := T.arrayAppend([_txid], txids);
                    lockedTxns_ := Trie.put(lockedTxns_, keyb(_a), Blob.equal, txids).0;
                };
                case(_){
                    lockedTxns_ := Trie.put(lockedTxns_, keyb(_a), Blob.equal, [_txid]).0;
                };
            };
        };
        public func dropLockedTxn(_a: AccountId, _txid: Txid): (){
            switch(Trie.get(lockedTxns_, keyb(_a), Blob.equal)){
                case(?(arr)){
                    var txids: [Txid] = arr;
                    txids := Array.filter(txids, func (t: Txid): Bool { t != _txid });
                    if (txids.size() == 0){
                        lockedTxns_ := Trie.remove(lockedTxns_, keyb(_a), Blob.equal).0;
                    };
                    lockedTxns_ := Trie.put(lockedTxns_, keyb(_a), Blob.equal, txids).0;
                    deleteTxnRecord(_txid, true);
                };
                case(_){};
            };
        };
        public func drc202CanisterId() : Principal{
            if (setting.EN_DEBUG) {
                return Principal.fromText("iq2ev-rqaaa-aaaak-aagba-cai");
            } else {
                return Principal.fromText("y5a36-liaaa-aaaak-aacqa-cai");
            };
        };
        public func drc202() : T.Self{
            return actor(Principal.toText(drc202CanisterId()));
        };
        public func config(_config: Config) : Bool {
            setting := {
                EN_DEBUG: Bool = Option.get(_config.EN_DEBUG, setting.EN_DEBUG);
                MAX_CACHE_TIME: Nat = Option.get(_config.MAX_CACHE_TIME, setting.MAX_CACHE_TIME);
                MAX_CACHE_NUMBER_PER: Nat = Option.get(_config.MAX_CACHE_NUMBER_PER, setting.MAX_CACHE_NUMBER_PER);
                MAX_STORAGE_TRIES: Nat = Option.get(_config.MAX_STORAGE_TRIES, setting.MAX_STORAGE_TRIES);
            };
            return true;
        };
        public func getConfig() : Setting{
            return setting;
        };
        public func generateTxid(_token: Principal, _caller: AccountId, _nonce: Nat) : Txid{
            return T.generateTxid(_token, _caller, _nonce);
        };

        public func get(_txid: Txid): ?TxnRecord{
            return getTxnRecord(_txid);
        };

        public func put(_txn: TxnRecord): (){
            return insertTxnRecord(_txn);
        };
        public func getLastTxns(_account: ?AccountId): [Txid]{
            switch(_account){
                case(?(a)){
                    switch(Trie.get(lastTxns_, keyb(a), Blob.equal)){
                        case(?(swaps)){
                            var l = List.append(swaps.0, List.reverse(swaps.1));
                            return List.toArray(l);
                        };
                        case(_){
                            return [];
                        };
                    };
                };
                case(_){
                    var l = List.append(globalLastTxns.0, List.reverse(globalLastTxns.1));
                    return List.toArray(l);
                };
            };
        };
        public func getEvents(_account: ?AccountId) : [TxnRecord]{
            switch(_account) {
                case(null){
                    var i: Nat = 0;
                    return Array.chain(getLastTxns(null), func (value:Txid): [TxnRecord]{
                        if (i < getConfig().MAX_CACHE_NUMBER_PER){
                            i += 1;
                            switch(getTxnRecord(value)){
                                case(?(r)){ return [r]; };
                                case(_){ return []; };
                            };
                        }else{ return []; };
                    });
                };
                case(?(account)){
                    return Array.chain(getLastTxns(?account), func (value:Txid): [TxnRecord]{
                        switch(getTxnRecord(value)){
                            case(?(r)){ return [r]; };
                            case(_){ return []; };
                        };
                    });
                };
            }
        };
        
        public func get2(_app: Principal, _txid: Txid) : async (txn: ?TxnRecord){
            return await getTxnRecord2(_app, _txid);
        };
        // records storage (DRC202 Standard)
        public func store() : async (){
            if (not(hasSetStd)){
                try{
                    await drc202().setStd(_tokenStd);
                    hasSetStd := true;
                } catch(e){};
            };
            var _storeRecords = List.nil<(Txid, Nat)>();
            let storageFee = await drc202().fee();
            var item = List.pop(storeRecords);
            var n : Nat = 0;
            let m : Nat = 20;
            while (Option.isSome(item.0) and n < m){
                storeRecords := item.1;
                switch(item.0){
                    case(?(txid, callCount)){
                        if (callCount < setting.MAX_STORAGE_TRIES){
                            switch(getTxnRecord(txid)){
                                case(?(txn)){
                                    try{
                                        Cycles.add(storageFee);
                                        await drc202().store(txn);
                                    } catch(e){ //push
                                        errCount += 1;
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
                n += 1;
            };
            //storeRecords := _storeRecords;
            _rePush(_storeRecords);
        };
        private func _rePush(_store: List.List<(Txid, Nat)>) : (){
            //var _storeRecords = _store;
            List.iterate(_store, func (t: (Txid, Nat)){
                storeRecords := List.push(t, storeRecords);
            });
        };

        // for updating
        public func getData() : DataTemp {
            return {
                setting = setting;
                txnRecords = txnRecords;
                globalTxns = globalTxns;
                globalLastTxns = globalLastTxns;
                lastTxns_ = lastTxns_; 
                lockedTxns_ = lockedTxns_; 
                storeRecords = storeRecords;
            };
        };
        public func setData(_data: DataTemp) : (){
            setting := _data.setting;
            txnRecords := _data.txnRecords;
            globalTxns := _data.globalTxns;
            globalLastTxns := _data.globalLastTxns;
            lastTxns_ := _data.lastTxns_; 
            lockedTxns_ := _data.lockedTxns_; 
            storeRecords := _data.storeRecords;
        };
    };
 };
