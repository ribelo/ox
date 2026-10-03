type state = {
  domain : Domain.id;
  mutable live : bool;
  mutable canceled : bool;
  mutable waiters : Eio.Condition.t list;
}
type t = { state : state @@ global }
let check_source s =
  if Domain.self () <> s.domain then invalid_arg "cross-domain source";
  if not s.live then invalid_arg "finished source"
module Source = struct
  type t = state
  let cancel s =
    check_source s;
    if not s.canceled then (
      s.canceled <- true;
      List.iter Eio.Condition.broadcast s.waiters)
end
let source (t : t @ local) = check_source t.state; t.state
let is_canceled (t : t @ local) = (source t).canceled
let attach (t : t @ local) condition =
  let s = source t in
  s.waiters <- condition :: s.waiters
let detach (t : t @ local) condition =
  let s = source t in
  let rec remove = function
    | [] -> []
    | x :: xs when x == condition -> xs
    | x :: xs -> x :: remove xs
  in
  s.waiters <- remove s.waiters
let with_source source (f : (t @ local -> 'a) @ local once) =
  check_source source;
  let token = stack_ { state = source } in
  f token [@nontail]
let with_ (f : (t @ local -> 'a) @ local once) =
  let s = { domain = Domain.self (); live = true; canceled = false; waiters = [] } in
  let token = stack_ { state = s } in
  let finish () =
    s.live <- false;
    if s.waiters <> [] then failwith "attached cancellation waiter escaped"
  in
  match f token [@nontail] with
  | value -> finish (); value
  | exception ex ->
      let bt = Printexc.get_raw_backtrace () in
      finish (); Printexc.raise_with_backtrace ex bt
