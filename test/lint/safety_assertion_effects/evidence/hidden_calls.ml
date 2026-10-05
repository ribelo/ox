(* ^safe-pcom ^safe-u7cx: mutable local assignment and implicit callbacks cannot pass as pure. *)
let local () =
  let mutable value = 0 in
  assert (value <- 1; true);
  ignore value
let lazy_parameter cell =
  let predicate (lazy _) = true in
  assert (predicate (lazy (Stdlib.incr cell)))
let lazy_binding cell =
  assert (let lazy _ = lazy (Stdlib.incr cell) in true)
let mutable_callback cell =
  let mutable predicate = fun () -> true in
  predicate <- (fun () -> Stdlib.incr cell; true);
  assert (predicate ())
let binding_operator cell =
  let (let*) () callback = Stdlib.incr cell; callback () in
  assert (let* () = () in true)
