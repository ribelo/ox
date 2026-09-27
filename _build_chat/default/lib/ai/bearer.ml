let header ~api_key =
  [ ("Authorization", "Bearer " ^ Eta_observability.Redact.expose api_key) ]
