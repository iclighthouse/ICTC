/**
 * Module     : TaskHash.mo
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Description: Calculating the Hash Value for Transaction Task.
 * Refers     : https://github.com/iclighthouse/ICTC
 */
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Option "mo:base/Option";
import Text "mo:base/Text";
import Binary "lib/Binary";
import SHA224 "lib/SHA224";
import CRC32 "lib/CRC32";
import TA "TATypes";

module {
    public func arrayAppend<T>(a: [T], b: [T]) : [T]{
        let buffer = Buffer.Buffer<T>(1);
        for (t in a.vals()){
            buffer.add(t);
        };
        for (t in b.vals()){
            buffer.add(t);
        };
        return Buffer.toArray(buffer);
    };
    public func hash(_pre: [Nat8], _input: TA.TaskEvent) : [Nat8]{
        var data: [Nat8] = _pre;
        // //toid
        // data := arrayAppend(data, Binary.BigEndian.fromNat64(Nat64.fromNat(Option.get(_input.toid, 0))));
        // //ttid
        // data := arrayAppend(data, Binary.BigEndian.fromNat64(Nat64.fromNat(_input.ttid)));
        // //Task.callee
        // data := arrayAppend(data, Blob.toArray(Principal.toBlob(_input.task.callee)));
        // //Task.data
        // data := arrayAppend(data, Blob.toArray(Option.get(_input.task.data, Blob.fromArray([]))));
        // //Task.time (ns -> ms) /10^6
        // data := arrayAppend(data, Binary.BigEndian.fromNat64(Nat64.fromIntWrap(_input.task.time / (10**6))));
        // //attempts
        // data := arrayAppend(data, Binary.BigEndian.fromNat64(Nat64.fromNat(_input.attempts)));
        // //result.0 // Status = {#Todo; #Doing; #Done; #Error; #Unknown; };
        // switch(_input.result.0){
        //     case(#Todo){
        //         data := arrayAppend(data, [0:Nat8]);
        //     };
        //     case(#Doing){
        //         data := arrayAppend(data, [1:Nat8]);
        //     };
        //     case(#Done){
        //         data := arrayAppend(data, [2:Nat8]);
        //     };
        //     case(#Error){
        //         data := arrayAppend(data, [3:Nat8]);
        //     };
        //     case(#Unknown){
        //         data := arrayAppend(data, [4:Nat8]);
        //     };
        // };
        // var task: TA.TaskEvent = {
        //     toid = _input.toid;
        //     ttid = _input.ttid;
        //     task = _input.task;
        //     attempts = _input.attempts;
        //     result = _input.result;
        //     callbackStatus = _input.callbackStatus;
        //     time = _input.time;
        //     txHash = Blob.fromArray([]);
        // };
        // data := arrayAppend(data, Blob.toArray(Text.encodeUtf8(debug_show(task))));
        data := arrayAppend(data, Blob.toArray(to_candid(_input)));
        var h : [Nat8] = SHA224.sha224(data);
        var crc : [Nat8] = CRC32.crc32(h);
        return arrayAppend(crc, h);
    };
    public func hashb(_pre: Blob, _input: TA.TaskEvent) : Blob{
        return Blob.fromArray(hash(Blob.toArray(_pre), _input));
    };
};