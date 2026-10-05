[@@@ox.domain]
type request = Ox_ai_systemone.Codecs.request
type question = Ox_ai_systemone.Types.choice_question
type event = Ox_ai_realtime.Session.event
type schema = Ox_ai_openrouter.Responses.schema
type logged = Ox_observability.Logger.value
module type Codec = module type of Ox_observability.Redact
