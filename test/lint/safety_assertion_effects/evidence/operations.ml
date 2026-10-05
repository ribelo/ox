(* ^safe-pcom: bounded standard write/I/O identities. *)
let check cell bytes buffer table channel =
  assert (
    cell := 1;
    true);
  assert (
    Stdlib.decr cell;
    true);
  assert (
    Bytes.set bytes 0 'x';
    true);
  assert (
    Buffer.add_string buffer "required";
    true);
  assert (
    Hashtbl.replace table 1 2;
    true);
  assert (
    output_string channel "required";
    true)
