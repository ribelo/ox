let timeout ~clock duration f =
  Eio.Time.with_timeout clock (Duration.to_seconds_float duration) f

(* ^nmono-8jcy: use Eio's monotonic timeout and its existing cancellation machinery. *)
let timeout_mono ~clock duration f =
  Eio.Time.Timeout.run
    (Eio.Time.Timeout.seconds clock (Duration.to_seconds_float duration))
    f
