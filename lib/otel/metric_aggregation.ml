module Metric_key = struct
  type t = {
    name : string;
    description : string;
    unit_ : string;
    kind : Meter.kind;
    attrs : (string * string) list;
  }

  let normalize_attrs = function
    | ([] | [ _ ]) as attrs -> attrs
    | attrs -> List.sort compare attrs

  let of_point (p : Meter.point) =
    {
      name = p.name;
      description = p.description;
      unit_ = p.unit_;
      kind = p.kind;
      attrs = normalize_attrs p.attrs;
    }

  let equal a b =
    String.equal a.name b.name
    && String.equal a.description b.description
    && String.equal a.unit_ b.unit_ && a.kind = b.kind && a.attrs = b.attrs

  let hash = Hashtbl.hash
end

module Table = Hashtbl.Make (Metric_key)

type histogram_state = {
  count : int;
  sum : float;
  min : float option;
  max : float option;
  explicit_bounds : float list;
  bucket_counts : int list;
}

type aggregate_value = Sum of Meter.number | Histogram of histogram_state
type row = Metric_key.t * (aggregate_value * int * int)

let ms_to_ns_saturating ms =
  if ms <= 0 then 0 else if ms > max_int / 1_000_000 then max_int else ms * 1_000_000

let float_of_number = function Meter.Int n -> float_of_int n | Float f -> f

let add_number a b =
  match (a, b) with
  | Meter.Int a, Meter.Int b ->
      if (b > 0 && a > max_int - b) || (b < 0 && a < min_int - b) then
        Meter.Float (float_of_int a +. float_of_int b)
      else Int (a + b)
  | Float a, Float b -> Float (a +. b)
  | Int a, Float b -> Float (float_of_int a +. b)
  | Float a, Int b -> Float (a +. float_of_int b)

let bucket_counts boundaries samples =
  let counts = Array.make (List.length boundaries + 1) 0 in
  List.iter
    (fun sample ->
      let rec bucket index = function
        | [] -> index
        | boundary :: rest ->
            if sample <= boundary then index else bucket (index + 1) rest
      in
      let index = bucket 0 boundaries in
      counts.(index) <- counts.(index) + 1)
    samples;
  Array.to_list counts

let min_max samples =
  let rec loop count sum min_v max_v = function
    | [] -> (count, sum, min_v, max_v)
    | sample :: rest ->
        let min_v =
          match min_v with
          | None -> Some sample
          | Some current -> Some (min current sample)
        in
        let max_v =
          match max_v with
          | None -> Some sample
          | Some current -> Some (max current sample)
        in
        loop (count + 1) (sum +. sample) min_v max_v rest
  in
  loop 0 0.0 None None samples

let histogram_state boundaries samples =
  let count, sum, min, max = min_max samples in
  {
    count;
    sum;
    min;
    max;
    explicit_bounds = boundaries;
    bucket_counts = bucket_counts boundaries samples;
  }

(* ^notel-8ixo: one accumulator per series. Counters and up-down counters add their
   increments; the only difference between them is the [isMonotonic] bit the encoder
   writes, because an export window reports what happened during it. *)
type acc = Acc_sum of Meter.number | Acc_histogram of float list

let start_acc kind value =
  match (kind, value) with
  | Meter.Counter _, value -> Acc_sum value
  | Histogram _, value -> Acc_histogram [ float_of_number value ]

let update_acc kind acc value =
  match (kind, acc) with
  | Meter.Counter _, Acc_sum current -> Acc_sum (add_number current value)
  | Histogram _, Acc_histogram samples -> Acc_histogram (float_of_number value :: samples)
  | _ -> invalid_arg "Eta_otel.Metric_aggregation.update_acc: kind/acc mismatch"

let finish_acc kind acc =
  match (kind, acc) with
  | Meter.Counter _, Acc_sum value -> Sum value
  | Histogram config, Acc_histogram samples ->
      Histogram (histogram_state (Meter.histogram_boundaries config) (List.rev samples))
  | _ -> invalid_arg "Eta_otel.Metric_aggregation.finish_acc: kind/acc mismatch"

type entry = { mutable acc : acc; start_ms : int; mutable end_ms : int }
type t = { table : entry Table.t; max_series : int; mutable series : int }

let create ~max_series =
  { table = Table.create 16; max_series = max 1 max_series; series = 0 }

let add t (point : Meter.point) =
  let key = Metric_key.of_point point in
  match Table.find_opt t.table key with
  | Some entry ->
      entry.acc <- update_acc key.kind entry.acc point.value;
      entry.end_ms <- point.ts_ms;
      true
  | None ->
      if t.series >= t.max_series then false
      else begin
        Table.replace t.table key
          {
            acc = start_acc key.kind point.value;
            start_ms = point.ts_ms;
            end_ms = point.ts_ms;
          };
        t.series <- t.series + 1;
        true
      end

let drain t =
  let rows =
    Table.fold
      (fun key entry out ->
        ( key,
          ( finish_acc key.kind entry.acc,
            ms_to_ns_saturating entry.start_ms,
            ms_to_ns_saturating entry.end_ms ) )
        :: out)
      t.table []
  in
  Table.reset t.table;
  t.series <- 0;
  rows

let aggregate_points points =
  let t = create ~max_series:max_int in
  List.iter (fun point -> ignore (add t point : bool)) points;
  drain t
