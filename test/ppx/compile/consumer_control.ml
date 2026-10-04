(* ^nderive-s2lt ^nderive-9atb ^nderive-p4tq: encoder references compile. *)
let top = Encoder_only.yojson_of_t 1
let nested = Encoder_only.M.yojson_of_t 2
let abstract = Manual_encoder.yojson_of_t (Manual_encoder.make 3)
let signature = Native_encoders.yojson_of_t (Native_encoders.make 4)
let nested_signature = Module_codecs.Only.yojson_of_t
