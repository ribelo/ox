let timeout ~clock duration f =
  Eio.Time.with_timeout clock (Duration.to_seconds_float duration) f
