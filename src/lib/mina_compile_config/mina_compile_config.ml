[%%import "/src/config/config.mlh"]

(** This file consists of compile-time constants that are not in
    Genesis_constants.
    This file includes all of the constants defined at compile-time for both
    tests and production.
*)

[%%inject "curve_size", curve_size]

[%%inject "genesis_ledger", genesis_ledger]

[%%inject "default_transaction_fee_string", default_transaction_fee]

[%%inject "default_snark_worker_fee_string", default_snark_worker_fee]

[%%inject "minimum_user_command_fee_string", minimum_user_command_fee]

[%%inject "itn_features", itn_features]

[%%ifndef compaction_interval]

let compaction_interval_ms = None

[%%else]

[%%inject "compaction_interval", compaction_interval]

let compaction_interval_ms = Some compaction_interval

[%%endif]

[%%inject "block_window_duration_ms", block_window_duration]

[%%inject "vrf_poll_interval_ms", vrf_poll_interval]

let rpc_handshake_timeout_sec = 60.0

let rpc_heartbeat_timeout_sec = 60.0

let rpc_heartbeat_send_every_sec = 10.0 (*same as the default*)

(** limits on Zkapp_command.t size
    10.26*np + 10.08*n2 + 9.14*n1 < 69.45
    where np: number of single proof updates
    n2: number of pairs of signed/no-auth update
    n1: number of single signed/no-auth update
    and their coefficients representing the cost
  The formula was generated based on benchmarking data conducted on bare
  metal i9 processor with room to include lower spec.
  69.45 was the total time for a combination of updates that was considered
  acceptable.
  The method used to estimate the cost was linear least squares.
*)

let zkapp_proof_update_cost = 10.26

let zkapp_signed_pair_update_cost = 10.08

let zkapp_signed_single_update_cost = 9.14

let zkapp_transaction_cost_limit = 69.45

let max_event_elements = 100

let max_action_elements = 100

[%%inject "network_id", network]

[%%ifndef zkapp_cmd_limit]

let zkapp_cmd_limit = None

[%%else]

[%%inject "zkapp_cmd_limit", zkapp_cmd_limit]

let zkapp_cmd_limit = Some zkapp_cmd_limit

[%%endif]

let zkapp_cmd_limit_hardcap = 128

let zkapps_disabled = false

[%%ifndef slot_tx_end]

let slot_tx_end : int option = None

[%%else]

[%%inject "slot_tx_end", slot_tx_end]

let slot_tx_end = Some slot_tx_end

[%%endif]

[%%ifndef slot_chain_end]

let slot_chain_end : int option = None

[%%else]

[%%inject "slot_chain_end", slot_chain_end]

let slot_chain_end = Some slot_chain_end

[%%endif]

[%%inject "download_snark_keys", download_snark_keys]

let () = Key_cache.set_downloads_enabled download_snark_keys

[%%if cache_exceptions]

let handle_unconsumed_cache_item ~logger:_ ~cache_name =
  let open Core_kernel.Error in
  let msg =
    Core_kernel.sprintf "cached item was not consumed (cache name = \"%s\")"
      cache_name
  in
  raise (of_string msg)

[%%else]

let handle_unconsumed_cache_item ~logger ~cache_name =
  [%log error] "Unconsumed item in cache: $cache"
    ~metadata:[ ("cache", `String (msg cache_name)) ]

[%%endif]

module Time_controller = Time_controller.T

module type Time_controller_intf = Time_controller_intf.S
