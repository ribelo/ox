let bad ~sw = Cancellation.with_ (fun cancel -> Concurrent.par ~sw (fun () -> Channel.receive ~cancel (Channel.create ())) (fun () -> Ok ()))
