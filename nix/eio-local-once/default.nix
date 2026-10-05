# Genuine solved scopes; no shared-switch activation or package-path inheritance. ^nonce-lrzq
{ pkgs, mkScope, oxcamlSystemOverlay, oxcamlCompiler, oxSrc, oxPackageNames,
  oxcaml-opam-repository, opam-repository, recipe }:
let
  providerNames = [ "eio" "eio_posix" "eio_main" ] ++ pkgs.lib.optional pkgs.stdenv.isLinux "eio_linux";
  query = {
    ocaml-system = "*";
    yojson = "2.2.2+ox";
    # Pinned repository-native variants; Dune reports upstream CLI version 3.22.2.
    dune = "3.22.2+ox";
    alcotest = "1.9.0+ox";
    qcheck = "*";
    memtrace = "*";
  } // builtins.listToAttrs (map (name: { inherit name; value = recipe.version; }) providerNames);
  solve = src: mkScope {
    inherit pkgs;
    overlays = [ oxcamlSystemOverlay ];
    repos = [ recipe.repository oxcaml-opam-repository opam-repository ];
    resolveArgs.env.sys-ocaml-version = "5.4.0";
  } src query;
  scope = solve oxSrc;
  externalScope = solve ../../test/core/eio_local_once/external;
  usesProvider = pkg:
    builtins.elem (pkg.pname or "") providerNames
    || pkgs.lib.any usesProvider (pkg.buildInputs or [ ]);
  affectedNames = builtins.filter (name: usesProvider scope.${name}) oxPackageNames;
  expectedAffected = [ "ox" "ox_test" "ox_json" "ox_rpc" "ox_http" "ox_ipc"
    "ox_process" "ox_blocking" "ox_otel" "ox_observability" "ox_app" "ox_sql"
    "ox_ai" "ox_ai_systemone" "ox_ai_openrouter" "ox_ai_realtime" "ox_ai_chat" ];
  closure = pkgs.linkFarm "ox-eio-local-once-full-closure"
    (map (name: { inherit name; path = scope.${name}; }) (providerNames ++ oxPackageNames));
  tools = resolved: [ oxcamlCompiler resolved.ocamlfind resolved.dune
    pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.python3 pkgs.git pkgs.pkg-config pkgs.stdenv.cc ];
  lane = resolved: names: label:
    let
      packages = map (name: resolved.${name}) (providerNames ++ names)
        ++ [ resolved.ocamlfind resolved.alcotest resolved.qcheck resolved.memtrace ];
      libraryClosure = map (entry: entry.drv) (builtins.genericClosure {
        startSet = map (drv: { key = toString drv; inherit drv; }) packages;
        operator = entry: map (drv: { key = toString drv; inherit drv; }) (entry.drv.buildInputs or [ ]);
      });
      manifest = pkgs.writeText "eio-local-once-${label}-provenance.json" (builtins.toJSON {
        inherit (recipe) identity;
        scope = label;
        compiler = toString oxcamlCompiler;
        dune = toString resolved.dune;
        findlib = toString resolved.ocamlfind;
        source = toString recipe.source;
        providers = builtins.listToAttrs (map (name: { inherit name; value = toString resolved.${name}; }) providerNames);
        consumers = builtins.listToAttrs (map (name: { inherit name; value = toString resolved.${name}; })
          (if label == "ox" then affectedNames else [ ]));
        externalConsumer = if label == "external" then toString resolved.eio_local_once_probe else null;
        libraryRoots = map toString libraryClosure;
      });
      isolate = ''
        unset OPAMROOT OPAMSWITCH OPAM_SWITCH_PREFIX OCAMLPATH CAML_LD_LIBRARY_PATH OCAMLLIB OCAML_TOPLEVEL_PATH OCAMLFIND_CONF OCAMLFIND_COMMANDS
        export PATH="${pkgs.lib.makeBinPath (tools resolved ++ packages)}"
        export OCAMLLIB="$(${oxcamlCompiler}/bin/ocamlc -where)"
        export OCAMLPATH="${pkgs.lib.makeSearchPath "lib/ocaml/5.4.0/site-lib" libraryClosure}"
        export CAML_LD_LIBRARY_PATH="${pkgs.lib.makeSearchPath "lib/ocaml/5.4.0/site-lib/stublibs" libraryClosure}"
        export OCAMLFIND_CONF="$(${resolved.ocamlfind}/bin/ocamlfind printconf conf)"
        export OCAMLFIND_COMMANDS="ocamlc=${oxcamlCompiler}/bin/ocamlc ocamlopt=${oxcamlCompiler}/bin/ocamlopt ocaml=${oxcamlCompiler}/bin/ocaml"
        export EIO_LOCAL_ONCE_OCAMLPATH="$OCAMLPATH"
        export EIO_LOCAL_ONCE_CAML_LD_LIBRARY_PATH="$CAML_LD_LIBRARY_PATH"
        export EIO_LOCAL_ONCE_MANIFEST="${manifest}"
        export EIO_LOCAL_ONCE_SOURCE="${recipe.source}"
        export EIO_LOCAL_ONCE_PATCH="${./local-once.patch}"
      '';
      check = pkgs.runCommand "eio-local-once-${label}-native-check" {
        nativeBuildInputs = tools resolved;
        buildInputs = packages;
      } ''
        ${isolate}
        export EIO_LOCAL_ONCE_LOG_DIR="$out"
        bash ${../../test/core/eio_local_once}/check.sh ${../../test/core/eio_local_once}/cases ${oxcamlCompiler}/bin/ocamlopt
        cp ${manifest} "$out/provenance.json"
      '';
    in { inherit packages isolate check manifest; };
  local = lane scope oxPackageNames "ox";
  external = lane externalScope [ "eio_local_once_probe" ] "external";
  devShell = pkgs.mkShell {
    inputsFrom = map (name: scope.${name}) oxPackageNames;
    nativeBuildInputs = tools scope;
    buildInputs = local.packages;
    shellHook = local.isolate;
  };
in
assert builtins.sort builtins.lessThan affectedNames == builtins.sort builtins.lessThan expectedAffected;
{
  inherit scope devShell closure affectedNames;
  nativeCheck = local.check;
  externalCheck = external.check;
  inherit (external) manifest;
}
