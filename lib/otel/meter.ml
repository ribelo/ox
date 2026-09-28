type number = Int of int | Float of float
type histogram_config = float list

let histogram_config bounds =
  let message =
    "Eta_otel.Meter.histogram_config: boundaries must be finite and strictly ascending"
  in
  let rec check = function
    | [] -> ()
    | bound :: rest ->
        if not (Float.is_finite bound) then invalid_arg message;
        (match rest with
        | [] -> ()
        | next :: _ -> if not (bound < next) then invalid_arg message);
        check rest
  in
  check bounds;
  bounds

let histogram_boundaries config = config

type kind = Counter of { monotonic : bool } | Histogram of histogram_config

type point = {
  name : string;
  description : string;
  unit_ : string;
  kind : kind;
  attrs : (string * string) list;
  value : number;
  ts_ms : int;
}

type t = { now_ms : unit -> int; record : point -> unit }

let create ~now_ms ~record = { now_ms; record }

type instrument = {
  meter : t;
  name : string;
  description : string;
  unit_ : string;
  kind : kind;
  attrs : (string * string) list;
}

let instrument meter ~name ?(unit_ = "") ?(description = "") ?(attrs = []) kind =
  if String.trim name = "" then invalid_arg "Eta_otel.Meter: name must not be empty";
  { meter; name; description; unit_; kind; attrs }

let counter meter ~name ?unit_ ?description ?attrs () =
  instrument meter ~name ?unit_ ?description ?attrs (Counter { monotonic = true })

let up_down_counter meter ~name ?unit_ ?description ?attrs () =
  instrument meter ~name ?unit_ ?description ?attrs (Counter { monotonic = false })

let histogram meter ~boundaries ~name ?unit_ ?description ?attrs () =
  instrument meter ~name ?unit_ ?description ?attrs
    (Histogram (histogram_config boundaries))

let measurement instrument value =
  {
    name = instrument.name;
    description = instrument.description;
    unit_ = instrument.unit_;
    kind = instrument.kind;
    attrs = instrument.attrs;
    value;
    ts_ms = instrument.meter.now_ms ();
  }

let add instrument delta =
  match instrument.kind with
  | Counter _ -> instrument.meter.record (measurement instrument (Float delta))
  | Histogram _ -> invalid_arg "Eta_otel.Meter.add: a histogram takes records, not adds"

let record instrument sample =
  match instrument.kind with
  | Histogram _ -> instrument.meter.record (measurement instrument (Float sample))
  | Counter _ -> invalid_arg "Eta_otel.Meter.record: a counter takes adds, not records"
