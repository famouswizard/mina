module type S = sig
  module Scalar_challenge = Scalar_challenge
  module Endo = Endo
  open Core_kernel
  open Async_kernel
  open Pickles_types
  open Hlist
  module Tick_field_sponge = Tick_field_sponge
  module Util = Util
  module Step_main_inputs = Step_main_inputs
  module Backend = Backend
  module Sponge_inputs = Sponge_inputs
  module Impls = Impls
  module Tag = Tag
  module Types_map = Types_map
  module Step_verifier = Step_verifier
  module Common = Common

  exception Return_digest of Md5.t

  module type Statement_intf = sig
    type field

    type t

    val to_field_elements : t -> field array
  end

  module type Statement_var_intf =
    Statement_intf with type field := Impls.Step.Field.t

  module type Statement_value_intf =
    Statement_intf with type field := Impls.Step.field

  module Verification_key : sig
    [%%versioned:
    module Stable : sig
      module V2 : sig
        type t [@@deriving to_yojson]
      end
    end]

    (* combinator generated by `deriving fields` in implementation *)
    val index : t -> Impls.Wrap.Verification_key.t

    val dummy : t Lazy.t

    module Id : sig
      type t [@@deriving sexp, equal]

      val dummy : unit -> t

      val to_string : t -> string
    end

    val load :
         cache:Key_cache.Spec.t list
      -> Id.t
      -> (t * [ `Cache_hit | `Locally_generated ]) Deferred.Or_error.t
  end

  module type Proof_intf = sig
    type statement

    type t

    val verification_key : Verification_key.t Lazy.t

    val id : Verification_key.Id.t Lazy.t

    val verify : (statement * t) list -> unit Or_error.t Deferred.t

    val verify_promise : (statement * t) list -> unit Or_error.t Promise.t
  end

  module Proof : sig
    type ('max_width, 'mlmb) t

    val dummy : 'w Nat.t -> 'm Nat.t -> _ Nat.t -> domain_log2:int -> ('w, 'm) t

    module Make (W : Nat.Intf) (MLMB : Nat.Intf) : sig
      type nonrec t = (W.n, MLMB.n) t [@@deriving sexp, compare, yojson, hash]

      val to_base64 : t -> string

      val of_base64 : string -> (t, string) Result.t
    end

    module Proofs_verified_2 : sig
      [%%versioned:
      module Stable : sig
        module V2 : sig
          type t = Make(Nat.N2)(Nat.N2).t
          [@@deriving sexp, compare, equal, yojson, hash]

          val to_yojson_full : t -> Yojson.Safe.t
        end
      end]

      val to_yojson_full : t -> Yojson.Safe.t
    end
  end

  module Statement_with_proof : sig
    type ('s, 'max_width, _) t = ('max_width, 'max_width) Proof.t
  end

  module Inductive_rule : sig
    module B : sig
      type t = Impls.Step.Boolean.var
    end

    module Previous_proof_statement : sig
      type ('prev_var, 'width) t =
        { public_input : 'prev_var
        ; proof : ('width, 'width) Proof.t Impls.Step.As_prover.Ref.t
        ; proof_must_verify : B.t
        }

      module Constant : sig
        type ('prev_value, 'width) t =
          { public_input : 'prev_value
          ; proof : ('width, 'width) Proof.t
          ; proof_must_verify : bool
          }
      end
    end

    (** This type relates the types of the input and output types of an inductive
        rule's [main] function to the type of the public input to the resulting
        circuit.
    *)
    type ( 'var
         , 'value
         , 'input_var
         , 'input_value
         , 'ret_var
         , 'ret_value )
         public_input =
      | Input :
          ('var, 'value) Impls.Step.Typ.t
          -> ('var, 'value, 'var, 'value, unit, unit) public_input
      | Output :
          ('ret_var, 'ret_value) Impls.Step.Typ.t
          -> ( 'ret_var
             , 'ret_value
             , unit
             , unit
             , 'ret_var
             , 'ret_value )
             public_input
      | Input_and_output :
          ('var, 'value) Impls.Step.Typ.t
          * ('ret_var, 'ret_value) Impls.Step.Typ.t
          -> ( 'var * 'ret_var
             , 'value * 'ret_value
             , 'var
             , 'value
             , 'ret_var
             , 'ret_value )
             public_input

    (** The input type of an inductive rule's main function. *)
    type 'public_input main_input =
      { public_input : 'public_input
            (** The publicly-exposed input to the circuit's main function. *)
      }

    (** The return type of an inductive rule's main function. *)
    type ('prev_vars, 'widths, 'public_output, 'auxiliary_output) main_return =
      { previous_proof_statements :
          ('prev_vars, 'widths) H2.T(Previous_proof_statement).t
            (** A list of booleans, determining whether each previous proof must
          verify.
      *)
      ; public_output : 'public_output
            (** The publicly-exposed output from the circuit's main function. *)
      ; auxiliary_output : 'auxiliary_output
            (** The auxiliary output from the circuit's main function. This value
          is returned to the prover, but not exposed to or used by verifiers.
      *)
      }

    (** This type models an "inductive rule". It includes
        - the list of previous statements which this one assumes
        - the snarky main function

        The types parameters are:
        - ['prev_vars] the tuple-list of public input circuit types to the previous
          proofs.
        - For example, [Boolean.var * (Boolean.var * unit)] represents 2 previous
          proofs whose public inputs are booleans
        - ['prev_values] the tuple-list of public input non-circuit types to the
          previous proofs.
        - For example, [bool * (bool * unit)] represents 2 previous proofs whose
          public inputs are booleans.
        - ['widths] is a tuple list of the maximum number of previous proofs each
          previous proof itself had.
        - For example, [Nat.z Nat.s * (Nat.z * unit)] represents 2 previous
          proofs where the first has at most 1 previous proof and the second had
          zero previous proofs.
        - ['heights] is a tuple list of the number of inductive rules in each of
          the previous proofs
        - For example, [Nat.z Nat.s Nat.s * (Nat.z Nat.s * unit)] represents 2
          previous proofs where the first had 2 inductive rules and the second
          had 1.
        - ['a_var] is the in-circuit type of the [main] function's public input.
        - ['a_value] is the out-of-circuit type of the [main] function's public
          input.
        - ['ret_var] is the in-circuit type of the [main] function's public output.
        - ['ret_value] is the out-of-circuit type of the [main] function's public
          output.
        - ['auxiliary_var] is the in-circuit type of the [main] function's
          auxiliary data, to be returned to the prover but not exposed in the
          public input.
        - ['auxiliary_value] is the out-of-circuit type of the [main] function's
          auxiliary data, to be returned to the prover but not exposed in the
          public input.
    *)
    type ( 'prev_vars
         , 'prev_values
         , 'widths
         , 'heights
         , 'a_var
         , 'a_value
         , 'ret_var
         , 'ret_value
         , 'auxiliary_var
         , 'auxiliary_value )
         t =
      { identifier : string
      ; prevs : ('prev_vars, 'prev_values, 'widths, 'heights) H4.T(Tag).t
      ; main :
             'a_var main_input
          -> ('prev_vars, 'widths, 'ret_var, 'auxiliary_var) main_return
      ; uses_lookup : bool
      }
  end

  val verify_promise :
       (module Nat.Intf with type n = 'n)
    -> (module Statement_value_intf with type t = 'a)
    -> Verification_key.t
    -> ('a * ('n, 'n) Proof.t) list
    -> unit Or_error.t Promise.t

  val verify :
       (module Nat.Intf with type n = 'n)
    -> (module Statement_value_intf with type t = 'a)
    -> Verification_key.t
    -> ('a * ('n, 'n) Proof.t) list
    -> unit Or_error.t Deferred.t

  module Prover : sig
    type ('prev_values, 'local_widths, 'local_heights, 'a_value, 'proof) t =
         ?handler:
           (   Snarky_backendless.Request.request
            -> Snarky_backendless.Request.response )
      -> 'a_value
      -> 'proof
  end

  module Provers : module type of H3_2.T (Prover)

  module Dirty : sig
    type t = [ `Cache_hit | `Generated_something | `Locally_generated ]

    val ( + ) : t -> t -> t
  end

  module Cache_handle : sig
    type t

    val generate_or_load : t -> Dirty.t
  end

  module Side_loaded : sig
    module Verification_key : sig
      [%%versioned:
      module Stable : sig
        module V2 : sig
          type t [@@deriving sexp, equal, compare, hash, yojson]
        end
      end]

      include Codable.Base58_check_intf with type t := t

      include Codable.Base64_intf with type t := t

      val dummy : t

      open Impls.Step

      val to_input : t -> Field.Constant.t Random_oracle_input.Chunked.t

      module Checked : sig
        type t

        val to_input : t -> Field.t Random_oracle_input.Chunked.t
      end

      val typ : (Checked.t, t) Impls.Step.Typ.t

      val of_compiled : _ Tag.t -> t

      module Max_branches : Nat.Add.Intf

      module Max_width = Nat.N2
    end

    module Proof : sig
      [%%versioned:
      module Stable : sig
        module V2 : sig
          (* TODO: This should really be able to be any width up to the max width... *)
          type t =
            (Verification_key.Max_width.n, Verification_key.Max_width.n) Proof.t
          [@@deriving sexp, equal, yojson, hash, compare]

          val to_base64 : t -> string

          val of_base64 : string -> (t, string) Result.t
        end
      end]

      val of_proof : _ Proof.t -> t

      val to_base64 : t -> string

      val of_base64 : string -> (t, string) Result.t
    end

    val create :
         name:string
      -> max_proofs_verified:(module Nat.Add.Intf with type n = 'n1)
      -> uses_lookup:Plonk_types.Opt.Flag.t
      -> typ:('var, 'value) Impls.Step.Typ.t
      -> ('var, 'value, 'n1, Verification_key.Max_branches.n) Tag.t

    val verify_promise :
         typ:('var, 'value) Impls.Step.Typ.t
      -> (Verification_key.t * 'value * Proof.t) list
      -> unit Or_error.t Promise.t

    val verify :
         typ:('var, 'value) Impls.Step.Typ.t
      -> (Verification_key.t * 'value * Proof.t) list
      -> unit Or_error.t Deferred.t

    (* Must be called in the inductive rule snarky function defining a
       rule for which this tag is used as a predecessor. *)
    val in_circuit :
      ('var, 'value, 'n1, 'n2) Tag.t -> Verification_key.Checked.t -> unit

    (* Must be called immediately before calling the prover for the inductive rule
       for which this tag is used as a predecessor. *)
    val in_prover : ('var, 'value, 'n1, 'n2) Tag.t -> Verification_key.t -> unit

    val srs_precomputation : unit -> unit
  end

  (** This compiles a series of inductive rules defining a set into a proof
      system for proving membership in that set, with a prover corresponding
      to each inductive rule. *)
  val compile_promise :
       ?self:('var, 'value, 'max_proofs_verified, 'branches) Tag.t
    -> ?cache:Key_cache.Spec.t list
    -> ?disk_keys:
         (Cache.Step.Key.Verification.t, 'branches) Vector.t
         * Cache.Wrap.Key.Verification.t
    -> ?return_early_digest_exception:bool
    -> ?override_wrap_domain:Pickles_base.Proofs_verified.t
    -> public_input:
         ( 'var
         , 'value
         , 'a_var
         , 'a_value
         , 'ret_var
         , 'ret_value )
         Inductive_rule.public_input
    -> auxiliary_typ:('auxiliary_var, 'auxiliary_value) Impls.Step.Typ.t
    -> branches:(module Nat.Intf with type n = 'branches)
    -> max_proofs_verified:
         (module Nat.Add.Intf with type n = 'max_proofs_verified)
    -> name:string
    -> constraint_constants:Snark_keys_header.Constraint_constants.t
    -> choices:
         (   self:('var, 'value, 'max_proofs_verified, 'branches) Tag.t
          -> ( 'prev_varss
             , 'prev_valuess
             , 'widthss
             , 'heightss
             , 'a_var
             , 'a_value
             , 'ret_var
             , 'ret_value
             , 'auxiliary_var
             , 'auxiliary_value )
             H4_6.T(Inductive_rule).t )
    -> unit
    -> ('var, 'value, 'max_proofs_verified, 'branches) Tag.t
       * Cache_handle.t
       * (module Proof_intf
            with type t = ('max_proofs_verified, 'max_proofs_verified) Proof.t
             and type statement = 'value )
       * ( 'prev_valuess
         , 'widthss
         , 'heightss
         , 'a_value
         , ( 'ret_value
           * 'auxiliary_value
           * ('max_proofs_verified, 'max_proofs_verified) Proof.t )
           Promise.t )
         H3_2.T(Prover).t

  (** This compiles a series of inductive rules defining a set into a proof
      system for proving membership in that set, with a prover corresponding
      to each inductive rule. *)
  val compile :
       ?self:('var, 'value, 'max_proofs_verified, 'branches) Tag.t
    -> ?cache:Key_cache.Spec.t list
    -> ?disk_keys:
         (Cache.Step.Key.Verification.t, 'branches) Vector.t
         * Cache.Wrap.Key.Verification.t
    -> ?override_wrap_domain:Pickles_base.Proofs_verified.t
    -> public_input:
         ( 'var
         , 'value
         , 'a_var
         , 'a_value
         , 'ret_var
         , 'ret_value )
         Inductive_rule.public_input
    -> auxiliary_typ:('auxiliary_var, 'auxiliary_value) Impls.Step.Typ.t
    -> branches:(module Nat.Intf with type n = 'branches)
    -> max_proofs_verified:
         (module Nat.Add.Intf with type n = 'max_proofs_verified)
    -> name:string
    -> constraint_constants:Snark_keys_header.Constraint_constants.t
    -> choices:
         (   self:('var, 'value, 'max_proofs_verified, 'branches) Tag.t
          -> ( 'prev_varss
             , 'prev_valuess
             , 'widthss
             , 'heightss
             , 'a_var
             , 'a_value
             , 'ret_var
             , 'ret_value
             , 'auxiliary_var
             , 'auxiliary_value )
             H4_6.T(Inductive_rule).t )
    -> unit
    -> ('var, 'value, 'max_proofs_verified, 'branches) Tag.t
       * Cache_handle.t
       * (module Proof_intf
            with type t = ('max_proofs_verified, 'max_proofs_verified) Proof.t
             and type statement = 'value )
       * ( 'prev_valuess
         , 'widthss
         , 'heightss
         , 'a_value
         , ( 'ret_value
           * 'auxiliary_value
           * ('max_proofs_verified, 'max_proofs_verified) Proof.t )
           Deferred.t )
         H3_2.T(Prover).t
end
