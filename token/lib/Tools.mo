/**
 * Module     : Tools.mo v 1.0
 * Author     : Modified by ICLight.house Team
 * Stability  : Experimental
 * Description: Convert subaccount to principal; Convert principal to accoundId.
 * Refers     : https://github.com/stephenandrews/motoko-accountid
 *              https://github.com/flyq/ic_codec
 */

import Prim "mo:⛔";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Char "mo:base/Char";
import Array "mo:base/Array";
import Text "mo:base/Text";
import Principal "mo:base/Principal";
import Option "mo:base/Option";
import Blob "mo:base/Blob";
import Iter "mo:base/Iter";
import P "mo:base/Prelude";
import SHA224 "./SHA224";
import BASE32 "./BASE32";
import CRC32 "./CRC32";
import Hex "./Hex";
import Nat16 "mo:base/Nat16";
import Nat64 "mo:base/Nat64";
import Binary "Binary";
//for test
import Time "mo:base/Time";
import Int "mo:base/Int";

module {

    public type PrincipalForm = {
        #OpaqueId;  //01
        #SelfAuthId;  //02
        #DerivedId;  //03
        #AnonymousId;  //04
        #NoneId;  //trap
    };
    public func slice<T>(a: [T], from: Nat, to: ?Nat): [T]{
        let len = a.size();
        if (len == 0) { return []; };
        var to_: Nat = Option.get(to, Nat.sub(len, 1));
        if (len <= to_){ to_ := len - 1; };
        var na: [T] = [];
        var i: Nat = from;
        while ( i <= to_ ){
            na := Array.append(na, Array.make(a[i]));
            i += 1;
        };
        return na;
    };
    // principalArr to principalText
    public func principalArrToText(pa: [Nat8]) : Text{
        var res: [Nat8] = [];
        res := Array.append(res, CRC32.crc32(pa));
        res := Array.append(res, pa);
        let s = BASE32.encode(#RFC4648 {padding=false}, res);
        let lowercase_s = Text.map(s , Prim.charToLower);
        let len = lowercase_s.size();
        let s_slice = Iter.toArray(Text.toIter(lowercase_s));
        var ret = "";
        var i:Nat = 1;
        for (v in s_slice.vals()){
            ret := ret # Char.toText(v);
            if (i % 5 == 0 and i != len){
                ret := ret # "-";
            };
            i += 1;
        };
        return ret;
    };
    // principalBlob to principal
    public func principalBlobToPrincipal(pb: Blob) : Principal{
        let pa = Blob.toArray(pb);
        let text = principalArrToText(pa);
        return Principal.fromText(text);
    };
    // Generate SubAccount  
    public func getSubAccount(p: Principal, subIndex: Nat64) : [Nat8]{
        let pa = Blob.toArray(Principal.toBlob(p));
        return subAccount(pa, subIndex: Nat64);
    };
    public func subAccount(pa: [Nat8], val: Nat64) : [Nat8]{
        let len = pa.size();
        var res = Array.append([Nat8.fromNat(len)], pa);
        let subLength = Nat.sub(31, len);
        assert(subLength >= 2);
        var suba = Array.init<Nat8>(subLength, 0);
        if (subLength < 8){
            let suba16 = Binary.BigEndian.fromNat16(Nat16.fromNat(Nat64.toNat(val)));
            for (k in suba.keys()){
                if (k >= Nat.sub(subLength, suba16.size())){
                    suba[k] := suba16[k - Nat.sub(subLength, suba16.size())];
                }else{
                    suba[k] := 0;
                };
            };
        } else{
            let suba64 = Binary.BigEndian.fromNat64(val);
            for (k in suba.keys()){
                if (k >= Nat.sub(subLength, suba64.size())){
                    suba[k] := suba64[k - Nat.sub(subLength, suba64.size())];
                }else{
                    suba[k] := 0;
                };
            };
        };
        res := Array.append(res, Array.freeze(suba));
        assert(res.size() == 32);
        return res;
    };
    //Get SubAccount Index (32 bytes)
    public func getSA(subIndex: Nat64) : [Nat8]{
        let sa = Array.init<Nat8>(32, 0);
        let sa64 = Binary.BigEndian.fromNat64(subIndex);
        for (i in Iter.range(24, 31)){
            sa[i] := sa64[i-24];
        };
        return Array.freeze(sa);
    };
    //Convert subaccount to SA(32 bytes)
    public func subToSA(a: [Nat8]) : [Nat8] { 
        let principalLength : Nat = Nat8.toNat(a[0]);
        var subIndex : [var Nat8] = Array.init<Nat8>(a.size(), 0);
        for (i in Iter.range(0, a.size()-1)) {
            if (i <= principalLength){
                subIndex[i] := 0;
            }else{
                subIndex[i] := a[i];
            };
        };
        return Array.freeze(subIndex);
    };
    //Convert subaccount to principal
    public func subToPrincipal(a: [Nat8]) : Principal {
        let length : Nat = Nat.min(Nat8.toNat(a[0]), a.size()-1);
        var bytes : [var Nat8] = Array.init<Nat8>(length, 0);
        for (i in Iter.range(1, length)) {
            bytes[i-1] := a[i];
        };
        return Principal.fromText(principalArrToText(Array.freeze(bytes)));
    };
    public func subHexToPrincipal(h: Hex.Hex) : Principal {
        switch(Hex.decode(h)){
            case (#ok(a)) subToPrincipal(a);
            case (#err(e)) P.unreachable();
        }
    };

    //Convert principal to account
    private let ads : [Nat8] = [10, 97, 99, 99, 111, 117, 110, 116, 45, 105, 100]; //b"\x0Aaccount-id"
    private let sa_zero : [Nat8] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];

    public func principalTextToAccount(t : Text, sa : ?[Nat8]) : [Nat8] {
        return principalToAccount(Principal.fromText(t), sa);
    };
    public func principalToAccount(p : Principal, sa : ?[Nat8]) : [Nat8] {
        return principalBlobToAccount(Principal.toBlob(p), sa);
    };
    public func principalBlobToAccount(b : Blob, sa : ?[Nat8]) : [Nat8] { //Blob & [Nat8]
        return generate(Blob.toArray(b), sa);
    };
    private func generate(data : [Nat8], sa : ?[Nat8]) : [Nat8] {
        var _sa : [Nat8] = sa_zero;
        if (Option.isSome(sa)) {
            _sa := Option.get(sa, _sa);
            while (_sa.size() < 32){
                _sa := Array.append([0:Nat8], _sa);
            };
        };
        var hash : [Nat8] = SHA224.sha224(Array.append(Array.append(ads, data), _sa));
        var crc : [Nat8] = CRC32.crc32(hash);
        return Array.append(crc, hash);                     
    };
    // To Account Blob
    public func principalTextToAccountBlob(t : Text, sa : ?[Nat8]) : Blob {
        return Blob.fromArray(principalTextToAccount(t, sa));
    };
    public func principalToAccountBlob(p : Principal, sa : ?[Nat8]) : Blob {
        return Blob.fromArray(principalToAccount(p, sa));
    };
    public func principalBlobToAccountBlob(b : Blob, sa : ?[Nat8]) : Blob {
        return Blob.fromArray(principalBlobToAccount(b, sa));
    };
    // To Account Hex
    public func principalTextToAccountHex(t : Text, sa : ?[Nat8]) : Hex.Hex {
        return Hex.encode(principalTextToAccount(t, sa));
    };
    public func principalToAccountHex(p : Principal, sa : ?[Nat8]) : Hex.Hex {
        return Hex.encode(principalToAccount(p, sa));
    };
    public func principalBlobToAccountHex(b : Blob, sa : ?[Nat8]) : Hex.Hex {
        return Hex.encode(principalBlobToAccount(b, sa));
    };
    // Account Hex to Account blob
    public func accountHexToAccountBlob(h: Hex.Hex) : ?Blob {
        let a = Hex.decode(h);
        switch (a){
            case (#ok(account:[Nat8])){
                if (isValidAccount(account)){
                    return ?(Blob.fromArray(account));
                } else { 
                    return null; 
                };
            };
            case(#err(_)){
                return null;
            }
        };
    };

    //Other principal tools
    public func principalForm(p : Principal) : PrincipalForm {
        let pArr = Blob.toArray(Principal.toBlob(p));
        if (pArr.size() == 0){
            return #NoneId;
        } else {
            switch(pArr[pArr.size()-1]){
                case (1) { return #OpaqueId; };
                case (2) { return #SelfAuthId; };
                case (3) { return #DerivedId; };
                case (4) { return #AnonymousId; };
                case (_) { return #NoneId; };
            };
        };
    };
    public func isValidAccount(account: [Nat8]): Bool{
        if (account.size() == 32){
            let checksum = slice(account, 0, ?3);
            let hash = slice(account, 4, ?31);
            if (Array.equal(CRC32.crc32(hash), checksum, Nat8.equal)){
                return true;
            };
        };
        return false;
    };
    public func blackhole(): Blob{
        var hash = Array.init<Nat8>(28, 0);
        var crc : [Nat8] = CRC32.crc32(Array.freeze(hash));
        return Blob.fromArray(Array.append(crc, Array.freeze(hash)));   
    };
    // get DRC calldata
    public func getDrcCalldata(_data: ?Blob): [Nat8]{
        var data = Blob.toArray(Option.get(_data, Blob.fromArray([])));
        if (data.size() >= 4){
            let protocol = slice(data, 0, ?2);
            let version: Nat8 = data[3];
            if (protocol[0] == 68 and protocol[1] == 82 and protocol[2] == 67){
                data := slice(data, 4, null);
            };
        };
        return data;
    };
    // set DRC calldata
    public func setDrcCalldata(_data: [Nat8]): Blob{
        let protocol: [Nat8] = [68,82,67]; //DRC
        let version: [Nat8] = [1];
        let data = Array.append(Array.append(protocol, version), _data);
        return Blob.fromArray(data);
    };
    //for test
    public func generateFromNat(n: Nat): Blob{
        var hash = SHA224.sha224(Blob.toArray(Text.encodeUtf8(Nat.toText(n)#Int.toText(Time.now()))));
        var crc : [Nat8] = CRC32.crc32(hash);
        return Blob.fromArray(Array.append(crc, hash));   
    };

};