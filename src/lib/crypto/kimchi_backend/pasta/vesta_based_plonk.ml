open Core_kernel
open Kimchi_backend_common
open Kimchi_pasta_basic
module Field = Fp
module Curve = Vesta

module Bigint = struct
  include Field.Bigint

  let of_data _ = failwith __LOC__

  let to_field = Field.of_bigint

  let of_field = Field.to_bigint
end

let field_size : Bigint.t = Field.size

module Verification_key = struct
  type t =
    ( Pasta_bindings.Fp.t
    , Kimchi_bindings.Protocol.SRS.Fp.t
    , Pasta_bindings.Fq.t Kimchi_types.or_infinity Kimchi_types.poly_comm )
    Kimchi_types.VerifierIndex.verifier_index

  let to_string _ = failwith __LOC__

  let of_string _ = failwith __LOC__

  let shifts (t : t) = t.shifts
end

module R1CS_constraint_system =
  Kimchi_pasta_constraint_system.Vesta_constraint_system

let lagrange srs domain_log2 : _ Kimchi_types.poly_comm array =
  let domain_size = Int.pow 2 domain_log2 in
  Array.init domain_size ~f:(fun i ->
      Kimchi_bindings.Protocol.SRS.Fp.lagrange_commitment srs domain_size i )

let with_lagrange f (vk : Verification_key.t) =
  f (lagrange vk.srs vk.domain.log_size_of_group) vk

let with_lagranges f (vks : Verification_key.t array) =
  let lgrs =
    Array.map vks ~f:(fun vk -> lagrange vk.srs vk.domain.log_size_of_group)
  in
  f lgrs vks

module Rounds_vector = Rounds.Step_vector
module Rounds = Rounds.Step

module Keypair = Dlog_plonk_based_keypair.Make (struct
  let name = "vesta"

  module Rounds = Rounds
  module Urs = Kimchi_bindings.Protocol.SRS.Fp
  module Index = Kimchi_bindings.Protocol.Index.Fp
  module Curve = Curve
  module Poly_comm = Fp_poly_comm
  module Scalar_field = Field
  module Verifier_index = Kimchi_bindings.Protocol.VerifierIndex.Fp
  module Gate_vector = Kimchi_bindings.Protocol.Gates.Vector.Fp
  module Constraint_system = R1CS_constraint_system
end)

module Proof = struct
  module Challenge_polynomial = struct
    [%%versioned
    module Stable = struct
      module V1 = struct
        type t =
          ( Curve.Affine.Stable.V1.t
          , Field.Stable.V1.t )
          Plonk_dlog_proof.Challenge_polynomial.Stable.V1.t
        [@@deriving sexp, compare, yojson]

        let to_latest = Fn.id
      end
    end]

    type ('g, 'fq) t_ = ('g, 'fq) Plonk_dlog_proof.Challenge_polynomial.t =
      { challenges : 'fq array; commitment : 'g }

    type ty = (Curve.Affine.t, Field.t) Plonk_dlog_proof.Challenge_polynomial.t

    let challenges { Plonk_dlog_proof.Challenge_polynomial.challenges; _ } =
      challenges

    let commitment { Plonk_dlog_proof.Challenge_polynomial.commitment; _ } =
      commitment
  end

  module T = struct
    let id = "pasta_vesta"

    let hash_fold_array f s x = hash_fold_list f s (Array.to_list x)

    [%%versioned
    module Stable = struct
      module V2 = struct
        module T = struct
          type t =
            ( Curve.Affine.Stable.V1.t
            , Field.Stable.V1.t
            , Field.Stable.V1.t array )
            Pickles_types.Plonk_types.Proof.Stable.V2.t
          [@@deriving compare, sexp, yojson, hash, equal]

          let id = "plong_dlog_proof_" ^ id

          type 'a creator =
               messages:
                 Curve.Affine.t Pickles_types.Plonk_types.Messages.Stable.V2.t
            -> openings:
                 ( Curve.Affine.t
                 , Field.t
                 , Field.t array )
                 Pickles_types.Plonk_types.Openings.Stable.V2.t
            -> 'a

          let map_creator c ~f ~messages ~openings = f (c ~messages ~openings)

          let create ~messages ~openings =
            let open Pickles_types.Plonk_types.Proof in
            { messages; openings }
        end

        include T

        include (
          Allocation_functor.Make.Full
            (T) :
              Allocation_functor.Intf.Output.Full_intf
                with type t := t
                 and type 'a creator := 'a creator )

        let to_latest = Fn.id
      end
    end]

    include (
      Stable.Latest :
        sig
          type t [@@deriving compare, sexp, yojson, hash, equal, bin_io]
        end
        with type t := t )

    [%%define_locally Stable.Latest.(create)]
  end

  include Plonk_dlog_proof.Make (struct
    module Scalar_field = Field
    module Base_field = Fq
    module Challenge_polynomial = Challenge_polynomial
    include T

    module Backend = struct
      type t =
        ( Pasta_bindings.Fq.t Kimchi_types.or_infinity
        , Pasta_bindings.Fp.t )
        Kimchi_types.prover_proof

      include Kimchi_bindings.Protocol.Proof.Fp

      let batch_verify vks ts =
        Promise.run_in_thread (fun () -> batch_verify vks ts)

      let create_aux ~f:create (pk : Keypair.t) primary auxiliary prev_chals
          prev_comms =
        (* external values contains [1, primary..., auxiliary ] *)
        let external_values i =
          let open Field.Vector in
          if i < length primary then get primary i
          else get auxiliary (i - length primary)
        in

        (* compute witness *)
        let computed_witness =
          R1CS_constraint_system.compute_witness pk.cs external_values
        in
        let num_rows = Array.length computed_witness.(0) in

        (* convert to Rust vector *)
        let witness_cols =
          Array.init Kimchi_backend_common.Constants.columns ~f:(fun col ->
              let witness = Field.Vector.create () in
              for row = 0 to num_rows - 1 do
                Field.Vector.emplace_back witness computed_witness.(col).(row)
              done ;
              witness )
        in
        create pk.index witness_cols prev_chals prev_comms

      let create_async (pk : Keypair.t) primary auxiliary prev_chals prev_comms
          =
        create_aux pk primary auxiliary prev_chals prev_comms
          ~f:(fun pk auxiliary_input prev_challenges prev_sgs ->
            Promise.run_in_thread (fun () ->
                create pk auxiliary_input prev_challenges prev_sgs ) )

      let create_and_verify_async (pk : Keypair.t) primary auxiliary prev_chals
          prev_comms =
        create_aux pk primary auxiliary prev_chals prev_comms
          ~f:(fun pk auxiliary_input prev_challenges prev_sgs ->
            Promise.run_in_thread (fun () ->
                create_and_verify pk auxiliary_input prev_challenges prev_sgs ) )

      let create (pk : Keypair.t) primary auxiliary prev_chals prev_comms =
        create_aux pk primary auxiliary prev_chals prev_comms ~f:create
    end

    module Verifier_index = Kimchi_bindings.Protocol.VerifierIndex.Fp
    module Index = Keypair

    module Evaluations_backend = struct
      type t = Scalar_field.t Kimchi_types.proof_evaluations
    end

    module Opening_proof_backend = struct
      type t =
        (Curve.Affine.Backend.t, Scalar_field.t) Kimchi_types.opening_proof
    end

    module Poly_comm = Fp_poly_comm
    module Curve = Curve
  end)

  include T
end

module Proving_key = struct
  type t = Keypair.t

  include
    Core_kernel.Binable.Of_binable_with_uuid
      (Core_kernel.Unit)
      (struct
        type nonrec t = t

        let to_binable _ = ()

        let of_binable () = failwith "TODO"

        let caller_identity = Bin_prot.Shape.Uuid.of_string "TODO"
      end)

  let is_initialized _ = `Yes

  let set_constraint_system _ _ = ()

  let to_string _ = failwith "TODO"

  let of_string _ = failwith "TODO"
end

module Oracles = Plonk_dlog_oracles.Make (struct
  module Verifier_index = Verification_key
  module Field = Field
  module Proof = Proof

  module Backend = struct
    include Kimchi_bindings.Protocol.Oracles.Fp

    let create = with_lagrange create
  end
end)
