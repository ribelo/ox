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

      # Eta's packages are whatever dune-project declares; nothing here names one
      # by hand. `packages` and ETA_OPAM_PACKAGES are both derived from this
      # list, so a package a worker declares appears in both without an edit and
      # a v1 package name cannot linger. Dune keeps package metadata in
      # dune-project (generate_opam_files true), so the stanzas are the source of
      # truth; the generated *.opam files exist only after a build.
      duneProjectLines = nixpkgs.lib.splitString "\n" (builtins.readFile ./dune-project);
      # A comment cannot open a stanza, so dropping comment-only and blank lines
      # keeps a commented-out (package ...) out of the list.
      duneProjectCode = nixpkgs.lib.concatStringsSep "\n" (
        builtins.filter
          (line: builtins.match "[ \t]*;.*" line == null && builtins.match "[ \t]*" line == null)
          duneProjectLines
      );
      # The (name X) dune requires inside each (package ...) form. Splitting on
      # the marker drops everything before the first form, which is where the
      # project's own (name eta) lives.
      packageStanzaName =
        stanza:
        let
          found = builtins.filter (name: name != null) (
            builtins.map
              (line: builtins.match ".*\\(name[ \t]+([^ \t()\"]+)\\).*" line)
              (nixpkgs.lib.splitString "\n" stanza)
          );
        in
        if found == [ ] then null else builtins.head (builtins.head found);
      etaPackageNames = builtins.filter (name: name != null) (
        builtins.map packageStanzaName (
          builtins.tail (nixpkgs.lib.splitString "(package" duneProjectCode)
        )
      );
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
          etaPackages = builtins.listToAttrs (
            map (name: {
              inherit name;
              value = etaScope.${name};
            }) etaPackageNames
          );
          # `nix build` with no attribute: the kernel package once dune-project
          # declares it, otherwise the first package declared there.
          defaultPackage =
            if etaPackages ? eta then
              etaPackages.eta
            else if etaPackageNames == [ ] then
              throw "dune-project declares no (package ...) stanza, so there is no default package"
            else
              etaPackages.${builtins.head etaPackageNames};
        in
        etaPackages // { default = defaultPackage; }
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
              pkgs.gnugrep
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
              # The tree this shell is in, not the v1 checkout the flake was
              # copied from.
              repo_root="''${ETA_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
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
              # Where opam installed this switch, and where the removal step
              # parks the files a dependent's executable needs to keep running.
              switch_prefix="$(opam var prefix --switch "$switch_name")"
              preserved_dir="$switch_prefix/.opam-switch/preserved-by-eta-opam-install"

              # The packages dune-project declares, expanded by the flake when
              # it evaluates: a stale generated *.opam file cannot be pinned.
              declared="${builtins.concatStringsSep " " etaPackageNames}"
              if [ -z "$declared" ]; then
                echo "dune-project declares no package; refusing to touch the shared switch." >&2
                exit 1
              fi
              # Pin kind git at this checkout's HEAD: opam fetches that commit,
              # so only committed sources are installed and the pin cannot move
              # under a consumer's feet. Every pin carries the commit as its
              # version, so one opam list call answers "which commit is in this
              # switch", and the {= version} constraint eta's opam files put on
              # conf-eta-oxcaml resolves for all pins alike.
              eta_commit="$(git -C "$repo_root" rev-parse HEAD)"
              eta_url="git+file://$repo_root#$eta_commit"
              # Derived from dune-project: every declared package, nothing else.
              packages="''${ETA_OPAM_PACKAGES:-$declared}"
              if [ "$#" -gt 0 ]; then
                packages="$*"
              fi

              # 1. Remove every installed eta* / ppx_eta* package this tree does
              #    not declare: v1's Eta, including the preprocessors that came
              #    from the same repository. opam takes their reverse
              #    dependencies with them, so a compiled v1 consumer loses its
              #    files; the executables of those dependents are preserved
              #    across the removal below, and are not rebuilt
              #    (docs/issues/shared-switch/01-shared-switch.md, 2026-09-26).
              removed=()
              for package in $(opam list --installed --short); do
                case "$package" in
                  eta* | ppx_eta*) ;;
                  *) continue ;;
                esac
                case " $declared " in
                  *" $package "*) continue ;;
                esac
                removed+=("$package")
              done
              if [ "''${#removed[@]}" -gt 0 ]; then
                echo "Removing v1 Eta packages from OPAM switch $switch_name (opam removes their reverse dependencies too): ''${removed[*]}"

                # Removing a package deletes every file its dependents
                # installed, executables included, and a consumer that is
                # already running must keep working. Copy what a dependent needs
                # at run time -- its bin/sbin executables, the share/etc data
                # beside them and any runtime stubs -- out of the switch first,
                # then put those files back as plain untracked files after the
                # removal. Nothing already at the destination is overwritten,
                # and a dependent with no installed-file manifest is reported
                # rather than guessed at.
                removed_csv=""
                for package in "''${removed[@]}"; do
                  removed_csv="''${removed_csv:+$removed_csv,}$package"
                done
                dependents=()
                for package in $(opam list --installed --short --recursive --depends-on "$removed_csv"); do
                  case "$package" in
                    eta* | ppx_eta*) continue ;;
                  esac
                  dependents+=("$package")
                done
                preserved=()
                for package in "''${dependents[@]}"; do
                  changes="$switch_prefix/.opam-switch/install/$package.changes"
                  if [ ! -f "$changes" ]; then
                    echo "No installed-file manifest for $package; its binaries cannot be preserved." >&2
                    continue
                  fi
                  in_removed=0
                  while IFS= read -r line; do
                    case "$line" in
                      "removed: ["*) in_removed=1; continue ;;
                      "removed: "*) continue ;;
                      "]"*) in_removed=0; continue ;;
                    esac
                    if [ "$in_removed" = "1" ]; then
                      continue
                    fi
                    # Every entry is a quoted path, in a list (added: [ ... ])
                    # or on one line (added: "bin/pie", contents-changed:
                    # "bin/pie"); the descriptor beside it -- {F:S<size>T<mtime>}
                    # or {D} -- is not needed. Only removed: entries are files
                    # opam has already taken away.
                    IFS='"' read -r _ relative _ <<< "$line"
                    case "$relative" in
                      bin/* | sbin/* | share/* | etc/* | lib/stublibs/*) ;;
                      *) continue ;;
                    esac
                    if [ ! -f "$switch_prefix/$relative" ]; then
                      continue
                    fi
                    mkdir -p "$preserved_dir/$package/$(dirname "$relative")"
                    cp -p "$switch_prefix/$relative" "$preserved_dir/$package/$relative"
                    preserved+=("$package/$relative")
                  done < "$changes"
                done

                opam remove "''${removed[@]}" --yes

                for entry in "''${preserved[@]}"; do
                  destination="$switch_prefix/''${entry#*/}"
                  if [ -e "$destination" ]; then
                    echo "Kept existing $destination (not overwritten)"
                    continue
                  fi
                  mkdir -p "$(dirname "$destination")"
                  cp -p "$preserved_dir/$entry" "$destination"
                  echo "Preserved $destination"
                done
              fi

              # 1b. v1's pins name the v1 checkout; drop them so a removed
              #     package cannot come back through a later opam install.
              #     Declared packages are re-pinned below.
              for pin in $(opam pin list --short); do
                case "$pin" in
                  eta* | ppx_eta*) ;;
                  *) continue ;;
                esac
                case " $declared " in
                  *" $pin "*) continue ;;
                esac
                opam pin remove "$pin" --no-action --yes
              done

              # 2. Nothing to do when every requested package already carries
              #    this commit: re-running the command is not a rebuild.
              requested=()
              for package in $packages; do
                requested+=("$package")
              done
              have="$(opam list --installed --short --columns=name,version "''${requested[@]}" 2>/dev/null | grep -c " $eta_commit$" || true)"
              if [ "$have" = "''${#requested[@]}" ]; then
                echo "Eta packages already installed from $repo_root at $eta_commit in OPAM switch $switch_name; nothing to do."
                exit 0
              fi

              # 3. Pin every declared package to this commit and install the
              #    requested set.
              for package in $declared; do
                opam pin add --kind=git --no-action --with-version "$eta_commit" \
                  --yes "$package" "$eta_url"
              done

              # The OxCaml metadata variants currently over-constrain portability
              # against their unannotated Bigstringaf dependency.
              opam pin add angstrom.0.16.1+ox \
                https://github.com/inhabitedtype/angstrom/archive/0.16.1.tar.gz \
                --no-action --yes
              opam pin add faraday.0.8.2+ox \
                https://github.com/inhabitedtype/faraday/archive/0.8.2.tar.gz \
                --no-action --yes

              # Test tooling no Eta package depends on: alcotest and qcheck
              # drive suites, memtrace is an allocation-trace hook.
              opam install alcotest qcheck memtrace --yes
              opam install "''${requested[@]}" --assume-depexts --yes

              echo "Eta packages installed into OPAM switch: $switch_name"
              echo "Source: $repo_root at $eta_commit"
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
              # v1 checked tools/oxcaml_toolchain_probe/ (mode syntax through
              # merlin, ocamllsp and ocamlformat). This tree carries no such
              # probe; the checks above are the toolchain contract.
            '';
          };
          oxCamlShippedTests = pkgs.writeShellApplication {
            name = "eta-oxcaml-test-shipped";
            runtimeInputs = [ pkgs.opam ];
            text = ''
              switch_name="''${1:-${oxCamlSwitch}}"
              repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
              cd "$repo_root"

              export OPAMROOT="''${OPAMROOT:-${oxCamlOpamRoot}}"
              export OPAMSWITCH="$switch_name"
              export PKG_CONFIG_PATH="${nativePkgConfigPath}:''${PKG_CONFIG_PATH:-}"
              export ETA_LADYBUG_LIBRARY="${ladybugLibraryPath}"
              eval "$(opam env --switch "$switch_name" --set-switch)"

              # v1's supported-native manifest, compiler-contract scripts and
              # signal-map complexity alias do not exist here; this switch runs
              # the gate AGENTS.md requires.
              dune build @install
              dune build --force @runtest
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
                echo "Run 'eta-opam-install-ox' to pin this checkout's packages into ${oxCamlSwitch} (it removes v1 Eta packages)."
                echo "Run 'eta-oxcaml-test-shipped' after setup to run the build and test gates."
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
                echo "Run 'eta-opam-install-ox' to pin this checkout's packages into ${oxCamlSwitch} (it removes v1 Eta packages)."
                echo "Run 'eta-oxcaml-test-shipped' after setup to run the build and test gates."
              fi
            '';
          };

        }
      );
    };
}
