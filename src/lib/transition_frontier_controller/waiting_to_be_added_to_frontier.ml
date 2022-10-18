open Core_kernel
open Context

(** Promote a transition that is in [Building_breadcrumb] state with
    [Processed] status to [Waiting_to_be_added_to_frontier] state.
*)
let promote_to ~context:(module Context : CONTEXT)
    ~substate:{ Substate.children; status } ~block_vc ~aux =
  let breadcrumb =
    match status with
    | Processed b ->
        b
    | _ ->
        failwith "promote_building_breadcrumb: expected to be processed"
  in
  let consensus_state =
    Frontier_base.Breadcrumb.protocol_state_with_hashes breadcrumb
    |> With_hash.data |> Mina_state.Protocol_state.consensus_state
  in
  Option.iter block_vc ~f:(fun valid_cb ->
      accept_gossip ~context:(module Context) ~valid_cb consensus_state ) ;
  Context.write_breadcrumb breadcrumb ;
  Transition_state.Waiting_to_be_added_to_frontier
    { breadcrumb
    ; source =
        (if aux.Transition_state.received_via_gossip then `Gossip else `Catchup)
    ; children
    }
