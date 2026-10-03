open Ox
let stop_ids : Interrupt_id.t list ref Eio.Fiber.key = Eio.Fiber.create_key ()

let request_stop ~sw id =
  Option.iter (fun ids -> ids := id :: !ids) (Eio.Fiber.get stop_ids);
  Eio.Switch.fail sw (Eio.Cancel.Cancelled (Interrupt_id.stop id))

let render ~stop_ids ~interrupt_exit ~exit_code ~defect_exit ~success diagnose pp_err =
  function
  | Exit.Success value -> success value
  | Exit.Failure (Cause.Interrupt (Some id))
    when List.exists (Interrupt_id.equal id) !stop_ids ->
      interrupt_exit
  | Exit.Failure (Cause.Fail err) ->
      diagnose ~kind:`Validation (Format.asprintf "%a\n" pp_err err);
      exit_code err
  | Exit.Failure cause ->
      diagnose ~kind:`Defect (Format.asprintf "%a\n" (Cause.pp pp_err) cause);
      defect_exit
