(** Pure aggregation of recorded metric points into OTLP metric rows, adapted from
    [v1:lib/otel/metric_aggregation.ml] with its [Ox.Capabilities] records replaced by
    {!Meter}'s and its gauge, frequency and summary kinds left to the consumer that asks
    for them. Nothing here suspends, observes cancellation or registers a finalizer: a
    table is ordinary mutable state and belongs to exactly one exporter of one domain. *)

module Metric_key : sig
  type t = {
    name : string;
    description : string;
    unit_ : string;
    kind : Meter.kind;
    attrs : (string * string) list;
  }
  (** What makes two measurements the same series. *)

  val of_point : Meter.point -> t
  (** [of_point point] is the point's identity, with its attributes sorted so that two
      instruments that list the same attributes in a different order are one series. *)
end

type histogram_state = {
  count : int;
  sum : float;
  min : float option;
  max : float option;
  explicit_bounds : float list;
      (** Validated finite strictly ascending explicit upper bounds. *)
  bucket_counts : int list;
      (** Per-bucket counts, [List.length explicit_bounds + 1] long; the last element is
          the overflow bucket. *)
}

(** One aggregated series, ready to be encoded. *)
type aggregate_value = Sum of Meter.number | Histogram of histogram_state

type row = Metric_key.t * (aggregate_value * int * int)
(** A series, its aggregate, and the window's [(start_ms, end_ms)] in the point
    timestamps' unit: milliseconds since the epoch. *)

type t
(** An accumulator: one series per identity, aggregated as points are recorded. *)

val create : max_series:int -> t
(** [create ~max_series] is an empty accumulator that admits at most [max_series] distinct
    series, so a program with unbounded attribute cardinality cannot grow it without
    bound. *)

val add : t -> Meter.point -> bool
(** [add table point] folds [point] into its series: sums a counter, appends a histogram
    sample, and moves the window's end. [false] means the series bound was reached and the
    point was not admitted. *)

val drain : t -> row list
(** [drain table] finishes every series and empties the table, so the same accumulator
    holds the next window. *)

val aggregate_points : Meter.point list -> row list
(** [aggregate_points points] is the aggregate of one batch of points, with no series
    bound: the pure entry point the wire tests and any one-shot caller use. *)
