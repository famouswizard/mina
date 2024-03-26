module type S = sig
  module Error : sig
    type t =
      | Verification_failed of Verifier.Failure.t
      | Coinbase_error of string
      | Insufficient_fee of Currency.Fee.t * Currency.Fee.t
      | Internal_command_status_mismatch
      | Unexpected of Error.t
    [@@deriving sexp]

    val to_string : t -> string

    val to_error : t -> Error.t
  end

  val get_unchecked :
       constraint_constants:Genesis_constants.Constraint_constants.t
    -> coinbase_receiver:Signature_lib.Public_key.Compressed.t
    -> supercharge_coinbase:bool
    -> Staged_ledger_diff.With_valid_signatures_and_proofs.t
    -> ( Mina_transaction.Transaction.Valid.t Mina_base.With_status.t list
         * Transaction_snark_work.t list
         * int
         * Currency.Amount.t list
       , Error.t )
       result

  val get_transactions :
       constraint_constants:Genesis_constants.Constraint_constants.t
    -> coinbase_receiver:Signature_lib.Public_key.Compressed.t
    -> supercharge_coinbase:bool
    -> Staged_ledger_diff.t
    -> ( Mina_transaction.Transaction.t Mina_base.With_status.t list
       , Error.t )
       result
end

include S

val compute_statuses :
     constraint_constants:Genesis_constants.Constraint_constants.t
  -> diff:
       ( Transaction_snark_work.t
       , Mina_base.User_command.Valid.t )
       Staged_ledger_diff.Pre_diff_two.t
       * ( Transaction_snark_work.t
         , Mina_base.User_command.Valid.t )
         Staged_ledger_diff.Pre_diff_one.t
         option
  -> coinbase_receiver:Signature_lib.Public_key.Compressed.t
  -> coinbase_amount:Currency.Amount.t
  -> global_slot:Mina_numbers.Global_slot_since_genesis.t
  -> txn_state_view:Mina_base.Zkapp_precondition.Protocol_state.View.t
  -> ledger:Mina_ledger.Ledger.t
  -> ( ( Transaction_snark_work.t
       , ( Mina_base.Signed_command.With_valid_signature.t
         , Mina_base.Zkapp_command.Valid.t )
         Mina_base.User_command.t_
         Mina_base.With_status.t )
       Staged_ledger_diff.Pre_diff_two.t
       * ( Transaction_snark_work.t
         , ( Mina_base.Signed_command.With_valid_signature.t
           , Mina_base.Zkapp_command.Valid.t )
           Mina_base.User_command.t_
           Mina_base.With_status.t )
         Staged_ledger_diff.Pre_diff_one.t
         option
     , Error.t )
     result

val get :
     check:
       (   Mina_base.User_command.t Mina_base.With_status.t list
        -> ( Mina_base.User_command.Valid.t list
           , Verifier.Failure.t )
           Core_kernel.Result.t
           Async.Deferred.Or_error.t )
  -> constraint_constants:Genesis_constants.Constraint_constants.t
  -> coinbase_receiver:Signature_lib.Public_key.Compressed.t
  -> supercharge_coinbase:bool
  -> Staged_ledger_diff.t
  -> ( Mina_transaction.Transaction.Valid.t Mina_base.With_status.t list
       * Transaction_snark_work.t list
       * int
       * Currency.Amount.t list
     , Error.t )
     result
     Async_kernel.Deferred.t
