(** Fiber-friendly exclusive publication gate (Eio). Writers publish under the
    lock; readers wait rather than observing intermediate row state. Never
    blocks the whole domain.

    Writer preference: new readers wait while any writer is waiting or holding
    the write callback. The write callback runs with the mutex held.

    [Eio.Condition.await] relocks its mutex before returning or raising
    cancellation, so writer decrement/unlock cleanup is installed before any
    wait, and a cancelled waiter still owns the mutex. *)

type t = {
  mutex : Eio.Mutex.t;
  cond : Eio.Condition.t;
  mutable writers_waiting : int;
  mutable active_readers : int;
}

let create () =
  {
    mutex = Eio.Mutex.create ();
    cond = Eio.Condition.create ();
    writers_waiting = 0;
    active_readers = 0;
  }

let release_read ~(io : Io.t @ yielding) t =
  Shim.cancel_protect (fun () ->
      Shim.mutex_use_ro ~io t.mutex (fun () ->
          t.active_readers <- t.active_readers - 1;
          if t.active_readers = 0 then Eio.Condition.broadcast t.cond))

let with_read ~(io : Io.t @ yielding) t
    (f : (unit -> 'a) @ local once yielding) =
  Shim.mutex_lock ~io t.mutex;
  let acquired = ref false in
  Shim.protect
    ~finally:(fun () ->
      if !acquired then release_read ~io t
      else Shim.cancel_protect (fun () -> Eio.Mutex.unlock t.mutex))
    (fun () ->
      while t.writers_waiting > 0 do
        Shim.condition_await ~io t.cond t.mutex
      done;
      t.active_readers <- t.active_readers + 1;
      acquired := true;
      Eio.Mutex.unlock t.mutex;
      f ()) [@nontail]

let with_write ~(io : Io.t @ yielding)
    ?(on_waiting : (unit -> (unit, 'e) result) @ local unyielding =
      fun () -> Ok ()) t
    (f : (unit -> ('a, 'e) result) @ local once yielding) =
  Shim.mutex_lock ~io t.mutex;
  t.writers_waiting <- t.writers_waiting + 1;
  Shim.protect
    ~finally:(fun () ->
      Shim.cancel_protect (fun () ->
          t.writers_waiting <- t.writers_waiting - 1;
          Eio.Condition.broadcast t.cond;
          Eio.Mutex.unlock t.mutex))
    (fun () ->
      let r = if t.active_readers > 0 then on_waiting () else Ok () in
      Shim.bind r (fun () ->
          while t.active_readers > 0 do
            Shim.condition_await ~io t.cond t.mutex
          done;
          f ()) [@nontail]) [@nontail]
