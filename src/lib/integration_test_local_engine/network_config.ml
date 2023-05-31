open Integration_test_lib
open Core_kernel
open Signature_lib
open Mina_base
open Currency

module Network_config = struct
  module Cli_inputs = Cli_inputs

  type block_producer_config =
    { name : string (* ; id : string *)
    ; keypair : Network_keypair.t
    ; libp2p_secret : string
    }
  [@@deriving to_yojson]

  type snark_coordinator_config =
    { name : string; public_key : string; worker_nodes : int }
  [@@deriving to_yojson]


  type terraform_config =
    { 
    runtime_config : Yojson.Safe.t
          [@to_yojson fun j -> `String (Yojson.Safe.to_string j)]
    ; block_producer_configs : block_producer_config list
    ; log_precomputed_blocks : bool
    ; archive_node_count : int
    ; mina_archive_schema : string
    ; mina_archive_schema_aux_files : string list
    ; snark_coordinator_config : snark_coordinator_config option
    ; snark_worker_fee : string
    }
  [@@deriving to_yojson]

  type t =
    { mina_automation_location : string
    ; debug_arg : bool
    ; genesis_keypairs :
        (Network_keypair.t Core.String.Map.t
        [@to_yojson
          fun map ->
            `Assoc
              (Core.Map.fold_right ~init:[]
                 ~f:(fun ~key:k ~data:v accum ->
                   (k, Network_keypair.to_yojson v) :: accum )
                 map )] )
    ; constants : Test_config.constants
    ; terraform: terraform_config
    }
  [@@deriving to_yojson]

  let expand ~logger ~_test_name ~(cli_inputs : Cli_inputs.t) ~(debug : bool)
      ~(test_config : Test_config.t) ~(_images : Test_config.Container_images.t)
      =
    let { 
        genesis_ledger
        ; block_producers
        ; snark_coordinator
        ; snark_worker_fee
        ; num_archive_nodes
        ; log_precomputed_blocks (* ; num_plain_nodes *)
        ; proof_config
        ; Test_config.k
        ; delta
        ; slots_per_epoch
        ; slots_per_sub_window
        ; txpool_max_size
        ; _
        } =
      test_config
    in
    (* check to make sure the test writer hasn't accidentally created duplicate names of accounts and keys *)
    let key_names_list =
      List.map genesis_ledger ~f:(fun acct -> acct.account_name)
    in
    if List.contains_dup ~compare:String.compare key_names_list then
      failwith
        "All accounts in genesis ledger must have unique names.  Check to make \
         sure you are not using the same account_name more than once" ;
    let all_nodes_names_list =
      List.map block_producers ~f:(fun acct -> acct.node_name)
      @ match snark_coordinator with None -> [] | Some n -> [ n.node_name ]
    in
    if List.contains_dup ~compare:String.compare all_nodes_names_list then
      failwith
        "All nodes in testnet must have unique names.  Check to make sure you \
         are not using the same node_name more than once" ;

    (* GENERATE ACCOUNTS AND KEYPAIRS *)
    let keypairs =
      List.take
        (* the first keypair is the genesis winner and is assumed to be untimed. Therefore dropping it, and not assigning it to any block producer *)
        (List.drop
           (Array.to_list (Lazy.force Key_gen.Sample_keypairs.keypairs))
           1 )
        (List.length genesis_ledger)
    in
    let labeled_accounts :
        ( Runtime_config.Accounts.single
        * (Public_key.Compressed.t * Private_key.t) )
        String.Map.t =
      String.Map.empty
    in
    let rec add_accounts mp zip =
      match zip with
      | [] ->
          mp
      | hd :: tl ->
          let ( { Test_config.Test_Account.balance; account_name; timing }
              , (pk, sk) ) =
            hd
          in
          let timing =
            match timing with
            | Account.Timing.Untimed ->
                None
            | Timed t ->
                Some
                  { Runtime_config.Accounts.Single.Timed.initial_minimum_balance =
                      t.initial_minimum_balance
                  ; cliff_time = t.cliff_time
                  ; cliff_amount = t.cliff_amount
                  ; vesting_period = t.vesting_period
                  ; vesting_increment = t.vesting_increment
                  }
          in
          let default = Runtime_config.Accounts.Single.default in
          let acct =
            { default with
              pk = Public_key.Compressed.to_string pk
            ; sk = Some (Private_key.to_base58_check sk)
            ; balance =
                Balance.of_mina_string_exn balance
                (* delegation currently unsupported *)
            ; delegate = None
            ; timing
            }
          in
          add_accounts
            (String.Map.add_exn mp ~key:account_name ~data:(acct, (pk, sk)))
            tl
    in
    let genesis_ledger_accounts =
      add_accounts labeled_accounts (List.zip_exn genesis_ledger keypairs)
    in
    (* DAEMON CONFIG *)
    let constraint_constants =
      Genesis_ledger_helper.make_constraint_constants
        ~default:Genesis_constants.Constraint_constants.compiled proof_config
    in
    let runtime_config =
      { Runtime_config.daemon =
          Some
            { txpool_max_size = Some txpool_max_size
            ; peer_list_url = None
            ; zkapp_proof_update_cost = None
            ; zkapp_signed_single_update_cost = None
            ; zkapp_signed_pair_update_cost = None
            ; zkapp_transaction_cost_limit = None
            ; max_event_elements = None
            ; max_action_elements = None
            }
      ; genesis =
          Some
            { k = Some k
            ; delta = Some delta
            ; slots_per_epoch = Some slots_per_epoch
            ; slots_per_sub_window = Some slots_per_sub_window
            ; genesis_state_timestamp =
                Some Core.Time.(to_string_abs ~zone:Zone.utc (now ()))
            }
      ; proof = Some proof_config (* TODO: prebake ledger and only set hash *)
      ; ledger =
          Some
            { base =
                Accounts
                  (let tuplist = String.Map.data genesis_ledger_accounts in
                   List.map tuplist ~f:(fun tup ->
                       let acct, _ = tup in
                       acct ) )
            ; add_genesis_winner = None
            ; num_accounts = None
            ; balances = []
            ; hash = None
            ; name = None
            }
      ; epoch_data = None
      }
    in
    let genesis_constants =
      Or_error.ok_exn
        (Genesis_ledger_helper.make_genesis_constants ~logger
           ~default:Genesis_constants.compiled runtime_config )
    in
    let constants : Test_config.constants =
      { constraints = constraint_constants; genesis = genesis_constants }
    in
    (* BLOCK PRODUCER CONFIG *)
    let mk_net_keypair keypair_name (pk, sk) =
      let keypair =
        { Keypair.public_key = Public_key.decompress_exn pk; private_key = sk }
      in
      Network_keypair.create_network_keypair ~keypair_name ~keypair
    in
    let block_producer_config name keypair =
      { name; keypair; libp2p_secret = "" }
    in
    let block_producer_configs =
      List.map block_producers ~f:(fun node ->
          let _, key_tup =
            match String.Map.find genesis_ledger_accounts node.account_name with
            | Some acct ->
                acct
            | None ->
                let failstring =
                  Format.sprintf
                    "Failing because the account key of all initial block \
                     producers must be in the genesis ledger.  name of Node: \
                     %s.  name of Account which does not exist: %s"
                    node.node_name node.account_name
                in
                failwith failstring
          in
          block_producer_config node.node_name
            (mk_net_keypair node.account_name key_tup) )
    in
    let mina_archive_schema = "create_schema.sql" in
    let long_commit_id =
      if String.is_substring Mina_version.commit_id ~substring:"[DIRTY]" then
        String.sub Mina_version.commit_id ~pos:7
          ~len:(String.length Mina_version.commit_id - 7)
      else Mina_version.commit_id
    in
    let mina_archive_base_url =
      "https://raw.githubusercontent.com/MinaProtocol/mina/" ^ long_commit_id
      ^ "/src/app/archive/"
    in
    let mina_archive_schema_aux_files =
      [ mina_archive_base_url ^ "create_schema.sql"
      ; mina_archive_base_url ^ "zkapp_tables.sql"
      ]
    in
    let genesis_keypairs =
      String.Map.of_alist_exn
        (List.map (String.Map.to_alist genesis_ledger_accounts)
           ~f:(fun element ->
             let kp_name, (_, (pk, sk)) = element in
             (kp_name, mk_net_keypair kp_name (pk, sk)) ) )
    in
    let snark_coordinator_config =
      match snark_coordinator with
      | None ->
          None
      | Some node ->
          let network_kp =
            match String.Map.find genesis_keypairs node.account_name with
            | Some acct ->
                acct
            | None ->
                let failstring =
                  Format.sprintf
                    "Failing because the account key of all initial snark \
                     coordinators must be in the genesis ledger.  name of \
                     Node: %s.  name of Account which does not exist: %s"
                    node.node_name node.account_name
                in
                failwith failstring
          in
          Some
            { name = node.node_name
            ; public_key =
                Public_key.Compressed.to_base58_check
                  (Public_key.compress network_kp.keypair.public_key)
            ; worker_nodes = node.worker_nodes
            }
    in

    (* NETWORK CONFIG *)
    { mina_automation_location = cli_inputs.mina_bin_location
    ; debug_arg = debug
    ; genesis_keypairs
    ; constants
    ; terraform =
        { 
        runtime_config = Runtime_config.to_yojson runtime_config
        ; block_producer_configs
        ; log_precomputed_blocks
        ; archive_node_count = num_archive_nodes
        ; mina_archive_schema
        ; mina_archive_schema_aux_files
        ; snark_coordinator_config
        ; snark_worker_fee
        }
    }

end
