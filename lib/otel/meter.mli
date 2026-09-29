(** Metric instruments: a counter, an up-down counter and a histogram, recorded in direct
    style from any fiber.

    An instrument belongs to a {!t} — the meter an exporter hands out — and carries its
    name and attributes, so one measurement is one call that allocates no identity.
    Recording never suspends, forks no fiber and registers no finalizer: it updates the
    meter's aggregation table in place, and the exporter that owns the meter drains that
    table on its interval, on flush and when its switch ends. A meter and every instrument
    made from it belong to one domain, like {!Ox_observability.Logger}: a program that
    records from several domains keeps one meter per domain. ^notel-bez2

    {!counter} and {!up_down_counter} report the sum of the {!add} calls that fall in one
    export window, so a counter never decreases and an up-down counter may: they differ
    only in OTLP's [isMonotonic], and both are delta sums because an export window reports
    what happened during it. {!histogram} reports one {!record} per sample against the
    explicit bounds the instrument was created with. *)

type number =
  | Int of int
  | Float of float
      (** A measurement as OTLP distinguishes them: [Int] crosses the wire as [asInt], a
          decimal string, and [Float] as [asDouble]. Instrument calls record doubles; a
          caller that builds a {!point} itself chooses. *)

type histogram_config
(** Validated explicit histogram upper bounds. Overflow is not a bound. *)

val histogram_config : float list -> histogram_config
(** [histogram_config bounds] is [bounds] once it is finite and strictly ascending.
    @raise Invalid_argument
      if a bound is not finite, or the list is not strictly ascending. Duplicate zeros,
      including mixed-sign zero, are rejected. *)

val histogram_boundaries : histogram_config -> float list
(** [histogram_boundaries config] is the validated explicit bounds. *)

(** What an instrument measures. *)
type kind = Counter of { monotonic : bool } | Histogram of histogram_config

type point = {
  name : string;
  description : string;
  unit_ : string;
  kind : kind;
  attrs : (string * string) list;
  value : number;
  ts_ms : int;  (** milliseconds since the epoch, from the meter's [now_ms] *)
}
(** One measurement, as the exporter stores it before aggregation. *)

type t
(** A meter: the clock a point is stamped from, and where the point goes. *)

val create : now_ms:(unit -> int) -> record:(point -> unit) -> t
(** [create ~now_ms ~record] is a meter that stamps each point with [now_ms ()] and hands
    it to [record]. Exporters call this; a program gets its meter from {!Ox_otel.meter}.
*)

type instrument
(** One named series: its kind, its unit and its attributes. Recording through an
    instrument never allocates a fresh identity, so a program creates instruments once. *)

val counter :
  t ->
  name:string ->
  ?unit_:string ->
  ?description:string ->
  ?attrs:(string * string) list ->
  unit ->
  instrument
(** [counter meter ~name ()] is a monotonic counter: its {!add} calls are summed in the
    export window and sent as an OTLP delta sum with [isMonotonic] set. A negative
    increment is a caller defect the exporter does not clamp — a value that can go down
    belongs on an {!up_down_counter}.
    @raise Invalid_argument if [name] is empty. ^notel-bez2 *)

val up_down_counter :
  t ->
  name:string ->
  ?unit_:string ->
  ?description:string ->
  ?attrs:(string * string) list ->
  unit ->
  instrument
(** [up_down_counter meter ~name ()] is a counter whose {!add} may be negative, summed in
    the export window and sent as a non-monotonic OTLP delta sum. ^notel-bez2 *)

val histogram :
  t ->
  boundaries:float list ->
  name:string ->
  ?unit_:string ->
  ?description:string ->
  ?attrs:(string * string) list ->
  unit ->
  instrument
(** [histogram meter ~boundaries ~name ()] counts one {!record} per sample into the
    explicit buckets [boundaries] (plus an overflow bucket), with the window's count, sum,
    min and max.
    @raise Invalid_argument
      if [name] is empty or [boundaries] is not finite and strictly ascending. ^notel-bez2
*)

val add : instrument -> float -> unit
(** [add instrument delta] records one increment on a counter.
    @raise Invalid_argument if [instrument] is a histogram, whose samples use {!record}.
*)

val record : instrument -> float -> unit
(** [record instrument sample] records one histogram sample.
    @raise Invalid_argument if [instrument] is a counter, whose increments use {!add}. *)
