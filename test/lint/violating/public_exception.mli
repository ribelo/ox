[@@@ox_lint.fixture "ox-public-exception: deliberate negative fixture"]

exception Error of string

module Nested : sig
  exception Failure
end
