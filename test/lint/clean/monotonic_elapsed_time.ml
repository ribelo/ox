let elapsed clock =
  let started = Eio.Time.Mono.now clock in
  Mtime.Span.to_float_ns (Mtime.span started (Eio.Time.Mono.now clock)) /. 1e9

let civil_delay clock due = Eio.Time.sleep clock (due -. Eio.Time.now clock)

let metadata clock =
  let stamp = Eio.Time.now clock in
  let format (a, b) = Printf.sprintf "%g/%g" a b in
  ignore (format (stamp, stamp))

let calendar_fraction clock =
  let truncate = floor in
  let stamp = Eio.Time.now clock in
  let seconds = truncate stamp in
  int_of_float ((stamp -. seconds) *. 1000.)

module Eio = struct
  module Time = struct
    let now () = 7.
  end
end

let shadow () = Eio.Time.now () -. Eio.Time.now ()
