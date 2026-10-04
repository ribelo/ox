(* ^nlintc-kdcl: stdlib_lock clean evidence. *)
[@@@warning "-32-34-37"]

let fiber () = Eio.Mutex.create ()

module Mutex = struct
  let create () = ()
end

module Condition = struct
  let create () = ()
end

module Semaphore = struct
  module Counting = struct
    let make _ = ()
  end
end

let local () =
  Mutex.create ();
  Condition.create ();
  Semaphore.Counting.make 0
