let header ~api_key =
  [ ("Authorization", "Bearer " ^ Ox_observability.Redact.expose api_key) ]
