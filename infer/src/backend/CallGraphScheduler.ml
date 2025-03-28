(*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

open! IStd
module L = Logging

let log =
  (* In call-graph scheduling, log progress every [per_procedure_logging_granularity] procedures.
     The default roughly reflects the average number of procedures in a C++ file. *)
  let per_procedure_logging_granularity = 200 in
  (* [procs_left] is set to 1 so that we log the first procedure sent to us. *)
  let procs_left = ref 1 in
  fun proc_name ->
    decr procs_left ;
    if !procs_left <= 0 then (
      L.log_task "Analyzing %a, next logging in %d procedures@." Procname.pp proc_name
        per_procedure_logging_granularity ;
      procs_left := per_procedure_logging_granularity )


(* How it works:

   - the queue [pending] contains the currently-known items of work, which are all the nodes at the
   same height (from the leaves), filled by [fill_queue].

   - when picking up a node to process, flag it so it isn't picked again. Remove it from the graph
   once the work on that node is done in [finished] so the graph gets gradually smaller and the cost
   of walking the graph decreases as we go.

   - to figure out if there is more work, take from the queue; if that's empty then it may be that
   there is no more work, or that we need to get nodes from the next level, so call [fill_queue] to
   check which one is the case.

   - **invariant**: if [is_empty ()] then [next ()] is [None]
*)
let bottom_up call_graph =
  let open TaskSchedulerTypes in
  let remaining = ref (CallGraph.n_procs call_graph) in
  let remaining_tasks () = !remaining in
  let pending : CallGraph.Node.t Queue.t = Queue.create () in
  let fill_queue () = CallGraph.iter_unflagged_leaves ~f:(Queue.enqueue pending) call_graph in
  (* prime the pending queue so that [empty] doesn't immediately return true *)
  fill_queue () ;
  let scheduled = ref 0 in
  (* cached query to avoid redoing work we do at the end of scheduling such as creating debug files
     *)
  let totally_empty = ref false in
  let is_empty () =
    !totally_empty
    ||
    let is_empty = Int.equal 0 !scheduled && Queue.is_empty pending in
    if is_empty then (
      (* see toplevel comment *)
      fill_queue () ;
      let is_really_empty = Queue.is_empty pending in
      if is_really_empty then (
        remaining := 0 ;
        L.progress "Finished call graph scheduling, %d procs remaining (in, or reaching, cycles).@."
          (CallGraph.n_procs call_graph) ;
        if Config.debug_level_analysis > 0 then CallGraph.to_dotty call_graph CallGraphCyclesDot ;
        (* save some memory *)
        CallGraph.reset call_graph ;
        (* there is no equivalent to [Hashtbl.reset] so set capacity to min, freeing the old array *)
        Queue.set_capacity pending 1 ;
        totally_empty := true ) ) ;
    !totally_empty
  in
  let rec next for_child =
    match Queue.dequeue pending with
    | None ->
        fill_queue () ;
        if Queue.is_empty pending then None else next for_child
    | Some n when n.flag || not (CallGraph.mem call_graph n.id) ->
        next for_child
    | Some n ->
        incr scheduled ;
        log n.pname ;
        CallGraph.Node.set_flag n ;
        Some (Procname {proc_name= n.pname; specialization= None})
  in
  let finished ~result:_ = function
    | Procname {proc_name} ->
        decr remaining ;
        decr scheduled ;
        CallGraph.remove call_graph proc_name
    | File _ ->
        L.die InternalError "Only Procnames are scheduled but File target was received"
  in
  {TaskGenerator.remaining_tasks; is_empty; finished; next}
