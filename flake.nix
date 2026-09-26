{
  description = "Eta OCaml development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.opam-nix = {
    url = "github:tweag/opam-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  inputs.opam-repository = {
    url = "github:ocaml/opam-repository/4fde328c35c75c2c7269e426a3cf041888890018";
    flake = false;
  };
  inputs.oxcaml-opam-repository = {
    url = "github:oxcaml/opam-repository/d65f081024758576f7a848bbd369863e7f7c1e81";
    flake = false;
  };
  inputs.oxcaml = {
    url = "github:oxcaml/oxcaml/5.4.0-ox2";
    flake = false;
  };
  inputs.oxcaml-merlin-src = {
    url = "github:oxcaml/oxcaml/2bc3d7bd8298793af4f807724dce6bfd57df1b84";
    flake = false;
  };
  inputs.oxcaml-lsp = {
    url = "github:oxcaml/ocaml-lsp/f617d31c54fdc19270cbab4a21e2ebd260182f66";
    flake = false;
  };

  outputs =
    {
      nixpkgs,
      opam-nix,
      opam-repository,
      oxcaml,
      oxcaml-opam-repository,
      oxcaml-merlin-src,
      oxcaml-lsp,
      ...
    }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          cleanLocalSource =
            src:
            pkgs.lib.cleanSourceWith {
              inherit src;
              filter =
                path: _type:
                let
                  base = baseNameOf path;
                in
                !(
                  base == ".git"
                  || base == "_build"
                  || base == "_opam"
                  || base == ".opam"
                  || base == ".opam-oxcaml"
                  || base == ".reference"
                  || base == ".scratch"
                  || base == ".motel-data"
                  || base == ".nema"
                  || base == ".pi"
                  || base == ".hill-climbing"
                  || base == "node_modules"
                );
          };
          etaSrc = cleanLocalSource ./.;
          patchedOxcaml = pkgs.runCommand "oxcaml-source-patched" { } ''
            cp -R ${oxcaml} "$out"
            chmod -R u+w "$out"
            substituteInPlace "$out/default.nix" \
              --replace-fail 'version = "5.2.0+ox";' 'version = "5.4.0+ox";'
            ${pkgs.perl}/bin/perl -0pi -e 's|new: old: \{\n        buildInputs = \[|new: old: rec {\n        version = "20231231";\n        src = pkgs.fetchFromGitLab {\n          domain = "gitlab.inria.fr";\n          owner = "fpottier";\n          repo = "menhir";\n          rev = version;\n          sha256 = "sha256-veB0ORHp6jdRwCyDDAfc7a7ov8sOeHUmiELdOFf/QYk=";\n        };\n        patches = [ ];\n        buildInputs = [|' "$out/default.nix"
          '';
          oxcamlCompiler =
            (pkgs.callPackage "${patchedOxcaml}/default.nix" {
              src = patchedOxcaml;
              ocamltest = true;
              warnError = false;
            }).overrideAttrs (_old: {
              doCheck = false;
            });
          eioSrc = pkgs.fetchFromGitHub {
            owner = "oxcaml";
            repo = "eio";
            rev = "7de26f5331f1e7aac1c086a5ebe849dd940b5c3e";
            hash = "sha256-2sgXOko6qjTWcb6PONPS+SO7PPKvBEUIU/7U6ooXDyA=";
          };
          # These release sources build against bigstringaf 0.10.0. The +ox
          # source forks require portability annotations it does not provide.
          faradaySrc = pkgs.fetchFromGitHub {
            owner = "inhabitedtype";
            repo = "faraday";
            rev = "0.8.2";
            hash = "sha256-wR4kDocR1t3OLRuudXH8IccYde552O6Gvo5BHNxRbAI=";
          };
          angstromSrc = pkgs.fetchFromGitHub {
            owner = "inhabitedtype";
            repo = "angstrom";
            rev = "0.16.1";
            hash = "sha256-EPqDK+7RU2vHEHvuoTXb8V2FkdXQ6tGu0ghbNPS3gZ4=";
          };
          oxcamlSystemOverlay = final: prev: {
            ocaml-system = prev.ocaml-system.overrideAttrs (old: {
              nativeBuildInputs = [ oxcamlCompiler ];
              preBuild = (old.preBuild or "") + ''
                substituteInPlace gen_ocaml_config.ml \
                  --replace-fail '5.4.0' '5.4.0+ox'
              '';
            });
            ocaml-config = prev.ocaml-config.overrideAttrs (old: {
              postInstall = (old.postInstall or "") + ''
                ln -s ocaml-config/gen_ocaml_config.ml \
                  "$out/share/gen_ocaml_config.ml"
              '';
            });
            ocamlfind = prev.ocamlfind.overrideAttrs (old: {
              postFixup = (old.postFixup or "") + ''
                replacement='"'"$out"'/lib/ocaml/5.4.0/site-lib/toplevel"'
                substituteInPlace "$out/bin/ocaml" \
                  --replace-fail '"$OCAML_TOPLEVEL_PATH"' "$replacement"
              '';
            });
            topkg = prev.topkg.overrideAttrs (old: {
              buildPhase = builtins.replaceStrings
                [ ''args+=("ocaml")'' ]
                [ ''args+=("${final.ocamlfind}/bin/ocaml")'' ]
                old.buildPhase;
            });
            fmt = prev.fmt.overrideAttrs (old: {
              buildPhase = builtins.replaceStrings
                [ ''args+=("ocaml")'' ]
                [ ''args+=("${final.ocamlfind}/bin/ocaml")'' ]
                old.buildPhase;
            });
            mtime = prev.mtime.overrideAttrs (old: {
              buildPhase = builtins.replaceStrings
                [ ''args+=("ocaml")'' ]
                [ ''args+=("${final.ocamlfind}/bin/ocaml")'' ]
                old.buildPhase;
            });
            faraday = prev.faraday.overrideAttrs (_: {
              src = faradaySrc;
              patches = [ ];
            });
            angstrom = prev.angstrom.overrideAttrs (_: {
              src = angstromSrc;
              patches = [ ];
            });
          } // builtins.listToAttrs (map
            (name: {
              inherit name;
              value = prev.${name}.overrideAttrs (_: { src = eioSrc; });
            })
            [ "eio" "eio_linux" "eio_main" "eio_posix" ]);
          buildOpamProjectPrime = builtins.getAttr "buildOpamProject'" opam-nix.lib.${system};
          etaScope = buildOpamProjectPrime
            {
              inherit pkgs;
              overlays = [ oxcamlSystemOverlay ];
              repos = [
                oxcaml-opam-repository
                opam-repository
              ];
              resolveArgs.env.sys-ocaml-version = "5.4.0";
            }
            etaSrc
            {
              ocaml-system = "*";
              # Yojson 3.0.0 does not compile with this OxCaml release.
              yojson = "2.2.2+ox";
            };
          etaPackageNames = [
            "eta"
            "eta_json"
            "eta_ai"
            "eta_ai_openai_codec"
            "eta_ai_openrouter"
            "eta_ai_openai_codex"
            "eta_ai_moonshot"
            "eta_ai_kimi_coding"
            "eta_exa"
            "eta_blocking"
            "eta_eio"
            "eta_http"
            "eta_http_eio"
            "eta_http_h1"
            "eta_http_h2"
            "eta_http_service"
            "eta_http_service_eio"
            "eta_http_tls_openssl"
            "eta_http_ws"
            "eta_ladybug"
            "eta_otel"
            "eta_otel_eio"
            "eta_redacted"
            "eta_router"
            "eta_signal"
            "eta_signal_map"
            "eta_sql"
            "eta_sql_driver"
            "eta_sql_dsl"
            "eta_stream"
            "eta_rpc"
          ];
          etaPackages = builtins.listToAttrs (
            map (name: {
              inherit name;
              value = etaScope.${name};
            }) etaPackageNames
          );
        in
        etaPackages // {
          default = etaPackages.eta;
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          oxCamlSwitch = "5.4.0+ox";
          oxCamlOpamRoot = "$HOME/.cache/opam";
          nativePkgConfigPath = pkgs.lib.makeSearchPathOutput "dev" "lib/pkgconfig" (
            [ pkgs.sqlite ]
            ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
              pkgs.openssl
              pkgs.zlib
            ]
          );
          ladybugdb = pkgs.ladybugdb.overrideAttrs (finalAttrs: _previousAttrs: {
            version = "0.17.1";
            src = pkgs.fetchFromGitHub {
              owner = "LadybugDB";
              repo = "ladybug";
              tag = "v${finalAttrs.version}";
              hash = "sha256-3d0gsSLkO5Np6P4l8AEfEPvzMlkf2wYMCluAtDrwEDc=";
            };
          });
          ladybugLibraryPath =
            "${ladybugdb.lib}/lib/liblbug${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}";
          etaOpamInstall = pkgs.writeShellApplication {
            name = "eta-opam-install";
            runtimeInputs = [
              pkgs.autoconf
              pkgs.coreutils
              pkgs.git
              pkgs.gnumake
              pkgs.m4
              pkgs.opam
              pkgs.patch
              pkgs.pkg-config
              pkgs.python3
              pkgs.sqlite
            ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
              pkgs.gmp
              pkgs.libev
              pkgs.libffi
              pkgs.openssl
              pkgs.zlib
            ];
            text = ''
              switch_name="''${ETA_OPAM_SWITCH:-${oxCamlSwitch}}"
              repo_root="''${ETA_REPO_ROOT:-/home/ribelo/projects/ribelo/ocaml/Eta}"
              cd "$repo_root"

              export OPAMROOT="''${OPAMROOT:-${oxCamlOpamRoot}}"
              export OPAMYES=1
              export PKG_CONFIG_PATH="${nativePkgConfigPath}:''${PKG_CONFIG_PATH:-}"

              if ! opam switch list --short | grep -Fxq "$switch_name"; then
                echo "Missing OPAM switch '$switch_name'." >&2
                echo "Run: shared-ocaml-switch-init" >&2
                exit 1
              fi

              export OPAMSWITCH="$switch_name"
              eval "$(opam env --switch "$switch_name" --set-switch)"

              eta_url="git+file://$repo_root#master"
              packages="''${ETA_OPAM_PACKAGES:-eta eta_json eta_ai eta_ai_openai_codec eta_ai_openrouter eta_ai_openai_codex eta_ai_moonshot eta_ai_kimi_coding eta_blocking eta_eio eta_exa eta_http eta_http_eio eta_http_h1 eta_http_h2 eta_http_service eta_http_service_eio eta_http_tls_openssl eta_http_ws eta_ladybug eta_otel eta_otel_eio eta_redacted eta_router eta_signal eta_signal_map eta_sql eta_sql_driver eta_sql_dsl eta_stream eta_rpc}"
              if [ "$#" -gt 0 ]; then
                packages="$*"
              fi

              for opam_file in "$repo_root"/*.opam; do
                package="$(basename "$opam_file" .opam)"
                opam pin add --kind=git "$package" "$eta_url" --no-action --yes
              done

              package_args=()
              for package in $packages; do
                package_args+=("$package")
              done

              # The OxCaml metadata variants currently over-constrain portability
              # against their unannotated Bigstringaf dependency.
              opam pin add angstrom.0.16.1+ox \
                https://github.com/inhabitedtype/angstrom/archive/0.16.1.tar.gz \
                --no-action --yes
              opam pin add faraday.0.8.2+ox \
                https://github.com/inhabitedtype/faraday/archive/0.8.2.tar.gz \
                --no-action --yes

              # Test and benchmark tooling that no Eta package depends on:
              # qcheck drives the law suites, memtrace is the allocation-trace
              # hook in bench/router.
              opam install alcotest qcheck memtrace --yes
              opam install "''${package_args[@]}" --assume-depexts --yes

              echo "Eta packages installed into OPAM switch: $switch_name"
              echo "$packages"
            '';
          };
          etaOpamInstallOx = pkgs.writeShellApplication {
            name = "eta-opam-install-ox";
            runtimeInputs = [ etaOpamInstall ];
            text = ''
              export ETA_OPAM_SWITCH="${oxCamlSwitch}"
              exec eta-opam-install "$@"
            '';
          };
          oxCamlSetup = pkgs.writeShellApplication {
            name = "eta-oxcaml-init";
            runtimeInputs = [
              etaOpamInstall
            ];
            text = ''
              if [ "$#" -gt 0 ]; then
                export ETA_OPAM_SWITCH="$1"
                shift
              fi
              exec eta-opam-install "$@"
            '';
          };
          editorOcamlBase = pkgs.ocaml-ng.ocamlPackages_5_4;
          editorOcaml = editorOcamlBase.overrideScope (_: _: {
            yojson = editorOcamlBase.yojson_2;
          });
          oxCamlMerlin = editorOcaml.buildDunePackage {
            pname = "merlin";
            version = "ox-2bc3d7bd";
            src = oxcaml-merlin-src;
            postUnpack = ''sourceRoot="$sourceRoot/external/merlin"'';
            propagatedBuildInputs = [
              editorOcaml.csexp
              editorOcaml.yojson
              editorOcaml.findlib
            ];
            buildPhase = ''
              runHook preBuild
              dune build -p merlin,merlin-lib,dot-merlin-reader -j $NIX_BUILD_CORES @install
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              dune install --root . --prefix $out --libdir $OCAMLFIND_DESTDIR merlin merlin-lib dot-merlin-reader
              runHook postInstall
            '';
          };
          oxCamlMenhir = editorOcaml.buildDunePackage {
            pname = "menhir";
            version = "20231231";
            src = pkgs.fetchurl {
              url = "https://gitlab.inria.fr/fpottier/menhir/-/archive/20231231/archive.tar.gz";
              sha512 = "620ff3443143535e03ac98c5e8ee2ddf9ba48f8cfe441302118def1da3e03ffac7f48d4d4cb129766b625ecad0fb341da1baa0169dee8b6d07a5b0bbb735cf2f";
            };
            buildPhase = ''dune build -p menhir,menhirLib,menhirSdk,menhirCST -j $NIX_BUILD_CORES @install'';
            installPhase = ''dune install --root . --prefix $out --libdir $OCAMLFIND_DESTDIR menhir menhirLib menhirSdk menhirCST'';
          };
          oxCamlGrenier = editorOcaml.buildDunePackage {
            pname = "grenier";
            version = "0.16";
            src = pkgs.fetchurl {
              url = "https://github.com/let-def/grenier/releases/download/v0.16/grenier-0.16.tbz";
              sha256 = "8fd22abf9f4589c206008654fa9eebb1cf4a58737ebb34138c6709520f36b75f";
            };
          };
          oxCamlCmon = editorOcaml.buildDunePackage {
            pname = "cmon";
            version = "0.2";
            src = pkgs.fetchurl {
              url = "https://github.com/let-def/cmon/releases/download/v0.2/cmon-0.2.tbz";
              sha256 = "9498b9355dbb62ac83814c758b8bc18ff6eecf2cdd5894ab49c7861acf3682b8";
            };
            propagatedBuildInputs = [
              oxCamlGrenier
              editorOcaml.pprint
            ];
          };
          oxCamlLrgrep = editorOcaml.buildDunePackage {
            pname = "lrgrep";
            version = "0.3";
            src = pkgs.fetchurl {
              url = "https://github.com/let-def/lrgrep/releases/download/v0.3/lrgrep-0.3.tbz";
              sha256 = "84a1874d0c063da371e19c84243aac7c40bfcb9aaf204251e0eb0d1f077f2cde";
            };
            nativeBuildInputs = [ oxCamlMenhir ];
            propagatedBuildInputs = [
              oxCamlCmon
              oxCamlMenhir
            ];
          };
          oxCamlOdocParser = editorOcaml.buildDunePackage {
            pname = "odoc-parser";
            version = "2.0.0";
            src = pkgs.fetchurl {
              url = "https://github.com/ocaml-doc/odoc-parser/releases/download/2.0.0/odoc-parser-2.0.0.tbz";
              sha256 = "407919fbb0eb95761d6fc6ec6777628d94aa1907343bdca678b1880bafb33922";
            };
            propagatedBuildInputs = [
              editorOcaml.astring
              editorOcaml.result
              editorOcaml.camlp-streams
            ];
          };
          oxCamlLsp = editorOcaml.buildDunePackage {
            pname = "ocaml-lsp";
            version = "ox-f617d31c";
            src = oxcaml-lsp;
            nativeBuildInputs = [
              editorOcaml.cppo
              oxCamlMenhir
              pkgs.makeWrapper
            ];
            buildInputs = [
              oxCamlMerlin
              oxCamlLrgrep
              oxCamlMenhir
              oxCamlOdocParser
            ]
            ++ (with editorOcaml; [
              async
              base
              cmarkit
              core
              core_unix
              core_kernel
              csexp
              file_path
              ppx_bin_prot
              ppx_compare
              ppx_enumerate
              ppx_expect
              ppx_jane
              ppx_js_style
              ppx_let
              ppx_log
              ppx_here
              ppx_sexp_conv
              ppx_sexp_message
              ppx_sexp_value
              ppx_string
              ppx_yojson_conv
              re
              re2
              spawn
              uutf
              yojson
              dyn
              sexplib
              ocamlc-loc
            ]);
            buildPhase = ''
              runHook preBuild
              dune build --root . --profile release -j $NIX_BUILD_CORES ocaml-lsp-server/bin/main.exe
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              install -Dm755 _build/default/ocaml-lsp-server/bin/main.exe $out/bin/ocamllsp
              runHook postInstall
            '';
            postInstall = ''wrapProgram $out/bin/ocamllsp --prefix PATH : ${oxCamlMerlin}/bin'';
          };
          oxCamlEditorTools = pkgs.buildEnv {
            name = "eta-oxcaml-editor-tools";
            paths = [
              oxCamlMerlin
              oxCamlLsp
            ];
          };
          oxCamlToolchainCheck = pkgs.writeShellApplication {
            name = "eta-oxcaml-check-toolchain";
            runtimeInputs = [
              pkgs.git
              pkgs.opam
              pkgs.pkg-config
              pkgs.python3
              pkgs.sqlite
              oxCamlEditorTools
            ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
              pkgs.openssl
              pkgs.zlib
            ];
            text = ''
              repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
              cd "$repo_root"

              export OPAMROOT="''${OPAMROOT:-${oxCamlOpamRoot}}"
              export OPAMSWITCH="${oxCamlSwitch}"
              export PKG_CONFIG_PATH="${nativePkgConfigPath}:''${PKG_CONFIG_PATH:-}"
              eval "$(opam env --switch "${oxCamlSwitch}" --set-switch)"
              export PATH="${oxCamlEditorTools}/bin:$PATH"

              test "$(ocamlc -version)" = "${oxCamlSwitch}"
              test "$(dune --version)" = "3.22.2"
              opam list --installed --short ocamlformat | grep -Fxq ocamlformat
              opam list --installed --short utop | grep -Fxq utop
              test "$(command -v ocamlmerlin)" = "${oxCamlEditorTools}/bin/ocamlmerlin"
              test "$(command -v ocamllsp)" = "${oxCamlEditorTools}/bin/ocamllsp"
              mode_probe="tools/oxcaml_toolchain_probe/mode_syntax.ml"
              dune build ./tools/oxcaml_toolchain_probe/mode_syntax.exe
              ocamlformat --enable-outside-detected-project --check "$mode_probe"
              probe_source="$(cat "$mode_probe")"
              printf '%s\n' "$probe_source" \
                | ocamlmerlin single errors -filename "$mode_probe" \
                | python3 tools/oxcaml_toolchain_probe/check_merlin_no_errors.py
              python3 tools/oxcaml_toolchain_probe/check_lsp_no_errors.py "$mode_probe"
              set +e
              printf '%s\n' 'let (identity @ portable) x = x + "nope"' \
                | ocamlmerlin single errors -filename "$mode_probe" \
                | python3 tools/oxcaml_toolchain_probe/check_merlin_no_errors.py
              merlin_neg=$?
              set -e
              test "$merlin_neg" -eq 1
            '';
          };
          oxCamlShippedTests = pkgs.writeShellApplication {
            name = "eta-oxcaml-test-shipped";
            runtimeInputs = [
              pkgs.opam
              pkgs.python3
            ];
            text = ''
              switch_name="''${1:-${oxCamlSwitch}}"
              repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
              cd "$repo_root"

              export OPAMROOT="''${OPAMROOT:-${oxCamlOpamRoot}}"
              export OPAMSWITCH="$switch_name"
              export PKG_CONFIG_PATH="${nativePkgConfigPath}:''${PKG_CONFIG_PATH:-}"
              export ETA_LADYBUG_LIBRARY="${ladybugLibraryPath}"
              eval "$(opam env --switch "$switch_name" --set-switch)"

              # Artifact check is distinct from test execution. The previous
              # helper had divergent build/runtest directory lists and omitted
              # supported native suites. @supported-native-tests is the single
              # execution manifest; see test/supported-native/.
              # The shell uses a separate opam switch: also resolve the Nix
              # package route so compiler-provider conflicts cannot hide here.
              bash scripts/check_compiler_nix.sh
              bash scripts/check_compiler_contract.sh
              bash scripts/check_compiler_solver.sh
              dune build @supported-native-install
              dune build --force @supported-native-tests
              dune build @signal-map-complexity
            '';
          };
          oxCamlHostPackages =
            [
              pkgs.autoconf
              pkgs.cacert
              pkgs.curl
              pkgs.git
              pkgs.go
              pkgs.gnumake
              pkgs.h2spec
              ladybugdb.lib
              pkgs.m4
              pkgs.nghttp2
              pkgs.nodejs_24
              pkgs.oha
              pkgs.opam
              pkgs.patch
              pkgs.pkg-config
              pkgs.sqlite
              pkgs.unzip
              pkgs.which
              etaOpamInstall
              etaOpamInstallOx
              oxCamlSetup
              oxCamlShippedTests
              oxCamlToolchainCheck
              oxCamlEditorTools
            ]
            ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
              pkgs.gmp
              pkgs.caddy
              pkgs.gdb
              pkgs.jq
              pkgs.jdk21_headless
              pkgs.libev
              pkgs.libffi
              pkgs.mkcert
              pkgs.nginx
              pkgs.openssl
              pkgs.scala-cli
              pkgs.valgrind
              pkgs.zlib
            ];
        in
        {
          default = pkgs.mkShell {
            packages = oxCamlHostPackages;

            shellHook = ''
              export OPAMROOT="''${OPAMROOT:-${oxCamlOpamRoot}}"
              export PKG_CONFIG_PATH="${nativePkgConfigPath}:''${PKG_CONFIG_PATH:-}"
              export ETA_LADYBUG_LIBRARY="${ladybugLibraryPath}"
              if [ -d "$OPAMROOT/${oxCamlSwitch}" ]; then
                export OPAMSWITCH="${oxCamlSwitch}"
                eval "$(opam env --switch "${oxCamlSwitch}" --set-switch)"
              fi
              # opam env puts the switch's installed stublibs first on
              # CAML_LD_LIBRARY_PATH, and a bytecode executable resolves
              # dll<lib>_stubs.so through it (Dune emits -dllib but never
              # -dllpath). A repository bytecode test therefore has to prepend
              # its build-tree stub directory or it silently loads the
              # installed copy; see
              # docs/issues/devshell-stub-shadowing/01-use-build-tree-stubs.md.
              export PATH="${oxCamlEditorTools}/bin:$PATH"
              if [ -t 1 ]; then
                echo "Eta OxCaml shell (${oxCamlSwitch})"
                echo "Run 'shared-ocaml-switch-init' to create shared OPAM switches."
                echo "Run 'eta-opam-install' to install Eta packages into ${oxCamlSwitch}."
                echo "Run 'eta-oxcaml-test-shipped' after setup to run the supported-native gate."
              fi
            '';
          };

          oxcaml = pkgs.mkShell {
            packages = oxCamlHostPackages;

            shellHook = ''
              export OPAMROOT="''${OPAMROOT:-${oxCamlOpamRoot}}"
              export PKG_CONFIG_PATH="${nativePkgConfigPath}:''${PKG_CONFIG_PATH:-}"
              export ETA_LADYBUG_LIBRARY="${ladybugLibraryPath}"
              if [ -d "$OPAMROOT/${oxCamlSwitch}" ]; then
                export OPAMSWITCH="${oxCamlSwitch}"
                eval "$(opam env --switch "${oxCamlSwitch}" --set-switch)"
              fi
              # opam env puts the switch's installed stublibs first on
              # CAML_LD_LIBRARY_PATH, and a bytecode executable resolves
              # dll<lib>_stubs.so through it (Dune emits -dllib but never
              # -dllpath). A repository bytecode test therefore has to prepend
              # its build-tree stub directory or it silently loads the
              # installed copy; see
              # docs/issues/devshell-stub-shadowing/01-use-build-tree-stubs.md.
              export PATH="${oxCamlEditorTools}/bin:$PATH"
              if [ -t 1 ]; then
                echo "Eta OxCaml research shell (${oxCamlSwitch})"
                echo "Run 'shared-ocaml-switch-init' to create shared OPAM switches."
                echo "Run 'eta-opam-install' to install Eta packages into ${oxCamlSwitch}."
                echo "Run 'eta-oxcaml-test-shipped' after setup to run the supported-native gate."
              fi
            '';
          };

        }
      );
    };
}
