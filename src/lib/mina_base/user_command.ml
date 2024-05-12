open Core_kernel

module Poly = struct
  [%%versioned
  module Stable = struct
    module V2 = struct
      type ('u, 's) t =
            ('u, 's) Mina_wire_types.Mina_base.User_command.Poly.V2.t =
        | Signed_command of 'u
        | Zkapp_command of 's
      [@@deriving sexp, compare, equal, hash, yojson]

      let to_latest = Fn.id
    end

    module V1 = struct
      type ('u, 's) t = Signed_command of 'u | Snapp_command of 's
      [@@deriving sexp, compare, equal, hash, yojson]

      let to_latest : _ t -> _ V2.t = function
        | Signed_command x ->
            Signed_command x
        | Snapp_command _ ->
            failwith "Snapp_command"
    end
  end]
end

type ('u, 's) t_ = ('u, 's) Poly.Stable.Latest.t =
  | Signed_command of 'u
  | Zkapp_command of 's

module Gen_make (C : Signed_command_intf.Gen_intf) = struct
  let to_signed_command f =
    Quickcheck.Generator.map f ~f:(fun c -> Signed_command c)

  open C.Gen

  let payment ?sign_type ~key_gen ?nonce ~max_amount ~fee_range () =
    to_signed_command
      (payment ?sign_type ~key_gen ?nonce ~max_amount ~fee_range ())

  let payment_with_random_participants ?sign_type ~keys ?nonce ~max_amount
      ~fee_range () =
    to_signed_command
      (payment_with_random_participants ?sign_type ~keys ?nonce ~max_amount
         ~fee_range () )

  let stake_delegation ~key_gen ?nonce ~fee_range () =
    to_signed_command (stake_delegation ~key_gen ?nonce ~fee_range ())

  let stake_delegation_with_random_participants ~keys ?nonce ~fee_range () =
    to_signed_command
      (stake_delegation_with_random_participants ~keys ?nonce ~fee_range ())

  let sequence ?length ?sign_type a =
    Quickcheck.Generator.map
      (sequence ?length ?sign_type a)
      ~f:(List.map ~f:(fun c -> Signed_command c))
end

module Gen = Gen_make (Signed_command)

let gen_signed =
  let module G = Signed_command.Gen in
  let open Quickcheck.Let_syntax in
  let%bind keys =
    Quickcheck.Generator.list_with_length 2
      Mina_base_import.Signature_keypair.gen
  in
  G.payment_with_random_participants ~sign_type:`Real ~keys:(Array.of_list keys)
    ~max_amount:10000 ~fee_range:1000 ()

let gen = Gen.to_signed_command gen_signed

[%%versioned
module Stable = struct
  module V2 = struct
    type t =
      (Signed_command.Stable.V2.t, Zkapp_command.Stable.V1.t) Poly.Stable.V2.t
    [@@deriving sexp, compare, equal, hash, yojson]

    let to_latest = Fn.id
  end
end]

let to_base64 : t -> string = function
  | Signed_command sc ->
      Signed_command.to_base64 sc
  | Zkapp_command zc ->
      Zkapp_command.to_base64 zc

let of_base64 s : t Or_error.t =
  match Signed_command.of_base64 s with
  | Ok sc ->
      Ok (Signed_command sc)
  | Error err1 -> (
      match Zkapp_command.of_base64 s with
      | Ok zc ->
          Ok (Zkapp_command zc)
      | Error err2 ->
          Error
            (Error.of_string
               (sprintf
                  "Could decode Base64 neither to signed command (%s), nor to \
                   zkApp (%s)"
                  (Error.to_string_hum err1) (Error.to_string_hum err2) ) ) )

(*
include Allocation_functor.Make.Versioned_v1.Full_compare_eq_hash (struct
  let id = "user_command"

  [%%versioned
  module Stable = struct
    module V1 = struct
      type t =
        (Signed_command.Stable.V1.t, Snapp_command.Stable.V1.t) Poly.Stable.V1.t
      [@@deriving sexp, compare, equal, hash, yojson]

      let to_latest = Fn.id

      type 'a creator : Signed_command.t -> Snapp_command.t -> 'a

      let create cmd1 cmd2 = (cmd1, cmd2)
    end
  end]
end)
*)

module Zero_one_or_two = struct
  [%%versioned
  module Stable = struct
    module V1 = struct
      type 'a t = [ `Zero | `One of 'a | `Two of 'a * 'a ]
      [@@deriving sexp, compare, equal, hash, yojson]
    end
  end]
end

module Verifiable = struct
  [%%versioned
  module Stable = struct
    module V2 = struct
      type t =
        ( Signed_command.Stable.V2.t
        , Zkapp_command.Verifiable.Stable.V1.t )
        Poly.Stable.V2.t
      [@@deriving sexp, compare, equal, hash, yojson]

      let to_latest = Fn.id
    end
  end]

  let fee_payer (t : t) =
    match t with
    | Signed_command x ->
        Signed_command.fee_payer x
    | Zkapp_command p ->
        Account_update.Fee_payer.account_id p.fee_payer
end

let to_verifiable (t : t) ~failed ~find_vk : Verifiable.t Or_error.t =
  match t with
  | Signed_command c ->
      Ok (Signed_command c)
  | Zkapp_command cmd ->
      Zkapp_command.Verifiable.create ~failed ~find_vk cmd
      |> Or_error.map ~f:(fun cmd -> Zkapp_command cmd)

module Make_to_all_verifiable
    (Strategy : Zkapp_command.Verifiable.Create_all_intf) =
struct
  let to_all_verifiable (ts : t Strategy.Command_wrapper.t list) ~load_vk_cache
      : Verifiable.t Strategy.Command_wrapper.t list Or_error.t =
    let open Or_error.Let_syntax in
    (* First we tag everything with its index *)
    let its = List.mapi ts ~f:(fun i x -> (i, x)) in
    (* then we partition out the zkapp commands *)
    let izk_cmds, is_cmds =
      List.partition_map its ~f:(fun (i, cmd) ->
          match Strategy.Command_wrapper.unwrap cmd with
          | Zkapp_command c ->
              First (i, Strategy.Command_wrapper.map cmd ~f:(Fn.const c))
          | Signed_command c ->
              Second (i, Strategy.Command_wrapper.map cmd ~f:(Fn.const c)) )
    in
    (* then unzip the indices *)
    let ixs, zk_cmds = List.unzip izk_cmds in
    (* then we verify the zkapp commands *)
    (* TODO: we could optimize this by skipping the fee payer and non-proof authorizations *)
    let accounts_referenced =
      List.fold_left zk_cmds ~init:Account_id.Set.empty ~f:(fun set zk_cmd ->
          Strategy.Command_wrapper.unwrap zk_cmd
          |> Zkapp_command.accounts_referenced |> Account_id.Set.of_list
          |> Set.union set )
    in
    let vk_cache = load_vk_cache accounts_referenced in
    let%map vzk_cmds = Strategy.create_all zk_cmds vk_cache in
    (* rezip indices *)
    let ivzk_cmds = List.zip_exn ixs vzk_cmds in
    (* Put them back in with a sort by index (un-partition) *)
    let ivs =
      List.map is_cmds ~f:(fun (i, cmd) ->
          (i, Strategy.Command_wrapper.map cmd ~f:(fun c -> Signed_command c)) )
      @ List.map ivzk_cmds ~f:(fun (i, cmd) ->
            (i, Strategy.Command_wrapper.map cmd ~f:(fun c -> Zkapp_command c)) )
      |> List.sort ~compare:(fun (i, _) (j, _) -> i - j)
    in
    (* Drop the indices *)
    List.unzip ivs |> snd
end

module Unapplied_sequence =
  Make_to_all_verifiable (Zkapp_command.Verifiable.From_unapplied_sequence)
module Applied_sequence =
  Make_to_all_verifiable (Zkapp_command.Verifiable.From_applied_sequence)

let of_verifiable (t : Verifiable.t) : t =
  match t with
  | Signed_command x ->
      Signed_command x
  | Zkapp_command p ->
      Zkapp_command (Zkapp_command.of_verifiable p)

let fee : t -> Currency.Fee.t = function
  | Signed_command x ->
      Signed_command.fee x
  | Zkapp_command p ->
      Zkapp_command.fee p

(* for filtering *)
let minimum_fee = Mina_compile_config.minimum_user_command_fee

let has_insufficient_fee t = Currency.Fee.(fee t < minimum_fee)

let is_disabled = function
  | Zkapp_command _ ->
      Mina_compile_config.zkapps_disabled
  | _ ->
      false

(* always `Accessed` for fee payer *)
let accounts_accessed (t : t) (status : Transaction_status.t) :
    (Account_id.t * [ `Accessed | `Not_accessed ]) list =
  match t with
  | Signed_command x ->
      Signed_command.account_access_statuses x status
  | Zkapp_command ps ->
      Zkapp_command.account_access_statuses ps status

let accounts_referenced (t : t) =
  List.map (accounts_accessed t Applied) ~f:(fun (acct_id, _status) -> acct_id)

let fee_payer (t : t) =
  match t with
  | Signed_command x ->
      Signed_command.fee_payer x
  | Zkapp_command p ->
      Zkapp_command.fee_payer p

(** The application nonce is the nonce of the fee payer at which a user command can be applied. *)
let applicable_at_nonce (t : t) =
  match t with
  | Signed_command x ->
      Signed_command.nonce x
  | Zkapp_command p ->
      Zkapp_command.applicable_at_nonce p

let expected_target_nonce t = Account.Nonce.succ (applicable_at_nonce t)

let extract_vks : t -> (Account_id.t * Verification_key_wire.t) List.t =
  function
  | Signed_command _ ->
      []
  | Zkapp_command cmd ->
      Zkapp_command.extract_vks cmd

(** The target nonce is what the nonce of the fee payer will be after a user command is successfully applied. *)
let target_nonce_on_success (t : t) =
  match t with
  | Signed_command x ->
      Account.Nonce.succ (Signed_command.nonce x)
  | Zkapp_command p ->
      Zkapp_command.target_nonce_on_success p

let fee_token (t : t) =
  match t with
  | Signed_command x ->
      Signed_command.fee_token x
  | Zkapp_command x ->
      Zkapp_command.fee_token x

let valid_until (t : t) =
  match t with
  | Signed_command x ->
      Signed_command.valid_until x
  | Zkapp_command { fee_payer; _ } -> (
      match fee_payer.Account_update.Fee_payer.body.valid_until with
      | Some valid_until ->
          valid_until
      | None ->
          Mina_numbers.Global_slot_since_genesis.max_value )

module Valid = struct
  type t_ = t

  [%%versioned
  module Stable = struct
    module V2 = struct
      type t =
        ( Signed_command.With_valid_signature.Stable.V2.t
        , Zkapp_command.Valid.Stable.V1.t )
        Poly.Stable.V2.t
      [@@deriving sexp, compare, equal, hash, yojson]

      let to_latest = Fn.id
    end
  end]

  module Gen = Gen_make (Signed_command.With_valid_signature)
end

let check_verifiable (t : Verifiable.t) : Valid.t Or_error.t =
  match t with
  | Signed_command x -> (
      match Signed_command.check x with
      | Some c ->
          Ok (Signed_command c)
      | None ->
          Or_error.error_string "Invalid signature" )
  | Zkapp_command p ->
      Ok (Zkapp_command (Zkapp_command.Valid.of_verifiable p))

let check ~failed ~find_vk (t : t) : Valid.t Or_error.t =
  to_verifiable ~failed ~find_vk t |> Or_error.bind ~f:check_verifiable

let forget_check (t : Valid.t) : t =
  match t with
  | Zkapp_command x ->
      Zkapp_command (Zkapp_command.Valid.forget x)
  | Signed_command c ->
      Signed_command (c :> Signed_command.t)

let to_valid_unsafe (t : t) =
  `If_this_is_used_it_should_have_a_comment_justifying_it
    ( match t with
    | Zkapp_command x ->
        let (`If_this_is_used_it_should_have_a_comment_justifying_it x) =
          Zkapp_command.Valid.to_valid_unsafe x
        in
        Zkapp_command x
    | Signed_command x ->
        (* This is safe due to being immediately wrapped again. *)
        let (`If_this_is_used_it_should_have_a_comment_justifying_it x) =
          Signed_command.to_valid_unsafe x
        in
        Signed_command x )

let filter_by_participant (commands : t list) public_key =
  List.filter commands ~f:(fun user_command ->
      Core_kernel.List.exists
        (accounts_referenced user_command)
        ~f:
          (Fn.compose
             (Signature_lib.Public_key.Compressed.equal public_key)
             Account_id.public_key ) )

(* A metric on user commands that should correspond roughly to resource costs
   for validation/application *)
let weight : t -> int = function
  | Signed_command signed_command ->
      Signed_command.payload signed_command |> Signed_command_payload.weight
  | Zkapp_command zkapp_command ->
      Zkapp_command.weight zkapp_command

(* Fee per weight unit *)
let fee_per_wu (user_command : Stable.Latest.t) : Currency.Fee_rate.t =
  (*TODO: return Or_error*)
  Currency.Fee_rate.make_exn (fee user_command) (weight user_command)

let valid_size ~genesis_constants = function
  | Signed_command _ ->
      Ok ()
  | Zkapp_command zkapp_command ->
      Zkapp_command.valid_size ~genesis_constants zkapp_command

let has_zero_vesting_period = function
  | Signed_command _ ->
      false
  | Zkapp_command p ->
      Zkapp_command.has_zero_vesting_period p

let is_incompatible_version = function
  | Signed_command _ ->
      false
  | Zkapp_command p ->
      Zkapp_command.is_incompatible_version p

module Well_formedness_error = struct
  (* syntactically-evident errors such that a user command can never succeed *)
  type t =
    | Insufficient_fee
    | Zero_vesting_period
    | Zkapp_too_big of (Error.t[@to_yojson Error_json.error_to_yojson])
    | Transaction_type_disabled
    | Incompatible_version
  [@@deriving compare, to_yojson, sexp]

  let to_string = function
    | Insufficient_fee ->
        "Insufficient fee"
    | Zero_vesting_period ->
        "Zero vesting period"
    | Zkapp_too_big err ->
        sprintf "Zkapp too big (%s)" (Error.to_string_hum err)
    | Incompatible_version ->
        "Set verification-key permission is updated to an incompatible version"
    | Transaction_type_disabled ->
        "Transaction type disabled"
end

let check_well_formedness ~genesis_constants t :
    (unit, Well_formedness_error.t list) result =
  let preds =
    let open Well_formedness_error in
    [ (has_insufficient_fee, Insufficient_fee)
    ; (has_zero_vesting_period, Zero_vesting_period)
    ; (is_incompatible_version, Incompatible_version)
    ; (is_disabled, Transaction_type_disabled)
    ]
  in
  let errs0 =
    List.fold preds ~init:[] ~f:(fun acc (f, err) ->
        if f t then err :: acc else acc )
  in
  let errs =
    match valid_size ~genesis_constants t with
    | Ok () ->
        errs0
    | Error err ->
        Zkapp_too_big err :: errs0
  in
  if List.is_empty errs then Ok () else Error errs

type fee_payer_summary_t = Signature.t * Account.key * int
[@@deriving yojson, hash]

let fee_payer_summary : t -> fee_payer_summary_t = function
  | Zkapp_command cmd ->
      let fp = Zkapp_command.fee_payer_account_update cmd in
      let open Account_update in
      let body = Fee_payer.body fp in
      ( Fee_payer.authorization fp
      , Body.Fee_payer.public_key body
      , Body.Fee_payer.nonce body |> Unsigned.UInt32.to_int )
  | Signed_command cmd ->
      Signed_command.
        (signature cmd, fee_payer_pk cmd, nonce cmd |> Unsigned.UInt32.to_int)

let fee_payer_summary_json =
  Fn.compose fee_payer_summary_t_to_yojson fee_payer_summary

let fee_payer_summary_string =
  let to_string (signature, pk, nonce) =
    sprintf "%s (%s %d)"
      (Signature.to_base58_check signature)
      (Signature_lib.Public_key.Compressed.to_base58_check pk)
      nonce
  in
  Fn.compose to_string fee_payer_summary
