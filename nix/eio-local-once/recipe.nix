# Experimental provider only; defaults retain upstream 1.6 unchanged. ^nonce-lrzq
{ pkgs, opam-repository-eio }:
let
  version = "1.6+ox-local-once.1";
  upstreamVersion = "1.6";
  sourceCommit = "1fc0efa41ccfb3818b09f54feec90ec29b47f1b6";
  sourceUrl = "https://github.com/ocaml-multicore/eio/releases/download/v1.6/eio-1.6.tbz";
  sourceSha256 = "c1f04986b401094176494863dde1ca9b292b59fdc679a9d7023e558d80fb5b15";
  patchSha256 = "320bf57c259ed34c43306f83662a788eb1c721522bca4ec7a5f9806719e5cd84";
  patch = ./local-once.patch;
  identity = { inherit version upstreamVersion sourceCommit sourceUrl sourceSha256 patchSha256; };
  source = pkgs.applyPatches {
    name = "eio-${version}-source";
    src = pkgs.fetchurl { url = sourceUrl; sha256 = sourceSha256; };
    patches = [ patch ];
  };
  repository = pkgs.runCommand "eio-local-once-opam-repository" {
    nativeBuildInputs = [ pkgs.python3 ];
  } ''
    python ${./make-repository.py} ${opam-repository-eio} ${patch} ${source} "$out" ${pkgs.writeText "eio-local-once-identity.json" (builtins.toJSON identity)}
  '';
in
assert builtins.hashFile "sha256" patch == patchSha256;
{ inherit identity version source repository; }
