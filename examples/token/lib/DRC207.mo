/**
 * Module     : DRC207.mo (Canister Monitor)
 * Author     : ICLight.house Team
 * Github     : https://github.com/iclighthouse/DRC_standards/
 */
module {
  public type canister_id = Principal;

  public type definite_canister_settings = {
    freezing_threshold : Nat;
    controllers : [Principal];
    memory_allocation : Nat;
    compute_allocation : Nat;
  };

  public type canister_status = {
     status : { #stopped; #stopping; #running };
     memory_size : Nat;
     cycles : Nat;
     settings : definite_canister_settings;
     module_hash : ?[Nat8];
  };

  /// monitorable_by_self:
  ///     If `true` is entered, it's required to add the canister's own canister_id to its controllers.
  /// monitorable_by_blackhole:
  ///     `monitorable_by_blackhole.canister_id`(principal) means that a blackhole is specified to read the canister status, For example `7hdtw-jqaaa-aaaak-aaccq-cai`.
  ///     If monitorable_by_blackhole.canister_id is entered, it's is required to add the blackhole's canister_id to the canister's controllers.
  /// cycles_receivable:
  ///     If `true` is entered, It means that the canister has implemented wallet_receive().
  /// timer: 
  ///     the `timer.interval_seconds` should be greater than or equal to 5 minutes (300 seconds), 
  ///     timer.interval_seconds=`0` means that timer_tick() will be executed once per heartbeat by the Monitor, 
  ///     Notes: Timer_tick() will be executed once the eventType `TimerTick` has been subscribed to in the Monitor. There is no guarantee that timer_tick() will be triggered on time.
  public type DRC207Support = {
    monitorable_by_self: Bool;
    monitorable_by_blackhole: { allowed: Bool; canister_id: ?Principal; };
    cycles_receivable: Bool;
    timer: { enable: Bool; interval_seconds: ?Nat; }; 
  };

  public type IC = actor {
   canister_status : { canister_id : canister_id } -> async canister_status;
  };

  public type Self = actor {
    drc207 : shared query () -> async DRC207Support;
    canister_status : shared () -> async canister_status;
    timer_tick : shared () -> async ();
    wallet_receive : shared () -> async ();
  };

}
/* Implementation example:

    /// DRC207 support
    public func drc207() : async DRC207.DRC207Support{
        return {
            monitorable_by_self = true;
            monitorable_by_blackhole = { allowed = true; canister_id = ?Principal.fromText("7hdtw-jqaaa-aaaak-aaccq-cai"); };
            cycles_receivable = true;
            timer = { enable = true; interval_seconds = ?300; };   // 5 minutes 
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
    public func timer_tick(): async (){
        // do something
    };
*/
