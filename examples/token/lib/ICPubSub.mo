/**
 * Module     : ICPubSub.mo
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Description: IC pub/sub message consumption model.
 * Refers     : https://github.com/iclighthouse/
 */

import Array "mo:base/Array";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Trie "mo:base/Trie";
import List "mo:base/List";
import Blob "mo:base/Blob";
import Iter "mo:base/Iter";
import Option "mo:base/Option";
import DRC20 "DRC20";

module {
    public type Message = DRC20.TxnRecord; // Define message type
    public type Callback = DRC20.Callback; // Define callback function type
    public type AccountId = DRC20.AccountId;
    public type DataTemp<T> = {
        setting: Setting;
        subscriptions: Trie.Trie<AccountId, Subscription<T>>;
        publishMessages: List.List<(AccountId, T, Message, Nat)>;
    };
    public type Subscription<T> = { callback : Callback; msgTypes : [T] };
    public type Setting = {
        MAX_PUBLICATION_TRIES: Nat;
    };
    public type Config = {
        MAX_PUBLICATION_TRIES: ?Nat;
    };
    
    public class ICPubSub<T>(_setting: Setting, isEq: (T, T) -> Bool){
        var setting: Setting = _setting;
        var subscriptions: Trie.Trie<AccountId, Subscription<T>> = Trie.empty();
        var publishMessages = List.nil<(AccountId, T, Message, Nat)>();
        var countThreads : Nat = 0;

        private func keyb(t: Blob) : Trie.Key<Blob> { return { key = t; hash = Blob.hash(t) }; };
        private func getSubCallback(_a: AccountId, _t: T): ?Callback{
            switch(Trie.get(subscriptions, keyb(_a), Blob.equal)){
                case(?(sub)){
                    var msgTypes = sub.msgTypes;
                    var found = Array.find(msgTypes, func (t: T): Bool { isEq(t, _t) });
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
        public func config(_config: Config) : Bool {
            setting := {
                MAX_PUBLICATION_TRIES: Nat = Option.get(_config.MAX_PUBLICATION_TRIES, setting.MAX_PUBLICATION_TRIES);
            };
            return true;
        };
        public func getConfig() : Setting{
            return setting;
        };
        public func getSub(_a: AccountId): ?Subscription<T>{ //getSubscription
            return Trie.get(subscriptions, keyb(_a), Blob.equal);
        };
        public func sub(_a: AccountId, _sub: Subscription<T>): (){ //setSubscription
            if (_sub.msgTypes.size() == 0){
                subscriptions := Trie.remove(subscriptions, keyb(_a), Blob.equal).0;
            } else{
                subscriptions := Trie.put(subscriptions, keyb(_a), Blob.equal, _sub).0;
            };
        };
        public func put(_subs: [AccountId], _msgType: T, _msg: Message) : (){ //pushMessages
            let len = _subs.size();
            if (len == 0){ return (); };
            for (i in Iter.range(0, Nat.sub(len,1))){
                var count: Nat = 0;
                for (j in Iter.range(i, Nat.sub(len,1))){
                    if (Blob.equal(_subs[i], _subs[j])){ count += 1; };
                };
                if (count == 1){
                    publishMessages := List.push((_subs[i], _msgType, _msg, 0), publishMessages);
                };
            };
        };
        public func pub() : async (){ //publish
            countThreads += 1;
            var _publishMessages = List.nil<(AccountId, T, Message, Nat)>();
            var item = List.pop(publishMessages);
            var n : Nat = 0;
            let m : Nat = 20;
            while (Option.isSome(item.0) and n < m){
                publishMessages := item.1;
                switch(item.0){
                    case(?(account, msgType, msg, callCount)){
                        switch(getSubCallback(account, msgType)){
                            case(?(callback)){
                                if (callCount < setting.MAX_PUBLICATION_TRIES){
                                    try{
                                        await callback(msg);
                                    } catch(e){ //push
                                        _publishMessages := List.push((account, msgType, msg, callCount+1), _publishMessages);
                                    };
                                };
                            };
                            case(_){};
                        };
                    };
                    case(_){};
                };
                item := List.pop(publishMessages);
                n += 1;
            };
            publishMessages := List.append(publishMessages, _publishMessages);
            countThreads := 0;
        };
        public func threads() : Nat{
            return countThreads;
        };

        // for updating
        public func getData() : DataTemp<T> {
            return {
                setting = setting;
                subscriptions = subscriptions;
                publishMessages = publishMessages;
            };
        };
        public func setData(_data: DataTemp<T>) : (){
            setting := _data.setting;
            subscriptions := _data.subscriptions;
            publishMessages := _data.publishMessages;
        };
    };
};