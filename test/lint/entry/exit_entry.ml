(* ^nlintc-du4v ^nlintc-kdcl: only status tails at real sinks are terminal. *)
module Process = Stdlib

let work () = ()

let () =
  Process.exit
    (try
       work ();
       0
     with _ -> 1)

let () =
  Process.exit
    (let () = work () in
     try
       work ();
       0
     with _ -> 1)

let () =
  Process.exit
    (if true then
       try
         work ();
         0
       with _ -> 1
     else 0)

let () =
  Process.exit
    (match () with
    | () -> (
        try
          work ();
          0
        with _ -> 1))

let () = Process.exit (match work () with () -> 0 | exception _ -> 1)

let () =
  Ox_caps.Cap_stdlib.exit ~caps:(Ox_caps_door.powerbox ())
    (try
       work ();
       0
     with _ -> 1)

(* Let RHSs, discarded prefixes, deferred/unknown callbacks and mutable routes stay findings. *)
let () =
  let status =
    try
      work ();
      0
    with _ -> 1
  in
  Process.exit status

let () =
  Process.exit
    (let discarded =
       try
         work ();
         0
       with _ -> 1
     in
     ignore discarded;
     0)

let () =
  Process.exit
    (ignore
       (try
          work ();
          0
        with _ -> 1);
     0)

let () =
  let deferred () =
    Process.exit
      (try
         work ();
         0
       with _ -> 1)
  in
  ignore deferred

let invoke callback = callback ()

let () =
  Process.exit
    (invoke (fun () ->
         try
           work ();
           0
         with _ -> 1))

let () =
  let exit _ = () in
  exit
    (try
       work ();
       0
     with _ -> 1)

let () =
  (try work () with _ -> ());
  work ()

let () =
  let result = ref 0 in
  (try work () with _ -> result := 1);
  Process.exit !result

type outcome = { status : int }

let () =
  let result =
    {
      status =
        (try
           work ();
           0
         with _ -> 1);
    }
  in
  Process.exit result.status
