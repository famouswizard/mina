(*
 * This file has been generated by the OCamlClientCodegen generator for openapi-generator.
 *
 * Generated by: https://openapi-generator.tech
 *
 * Schema Block_transaction.t : BlockTransaction contains a populated Transaction and the BlockIdentifier that contains it. 
 *)

type t =
  { block_identifier : Block_identifier.t
  ; transaction : Transaction.t
  ; (* The timestamp of the block in milliseconds since the Unix Epoch. The timestamp is stored in milliseconds because some blockchains produce blocks more often than once a second.  *)
    (* Warning: This field is not part of the official spec, hence it's marked as optional *)
    timestamp : int64 option
  }
[@@deriving yojson { strict = false }, show, eq]

let to_yojson ({ timestamp; _ } as t) =
  let v = to_yojson t in
  match (timestamp, v) with
  | None, `Assoc l ->
      (* Remove the timestamp field if it's not set, since it's not part of the
         official spec *)
      `Assoc (List.filter (fun (k, _) -> k <> "timestamp") l)
  | Some _, _ | None, _ ->
      v
(* impossible *)

(** BlockTransaction contains a populated Transaction and the BlockIdentifier that contains it.  *)
let create ?(timestamp : int64 option) (block_identifier : Block_identifier.t)
    (transaction : Transaction.t) : t =
  { block_identifier; transaction; timestamp }
