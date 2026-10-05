{
  description = "Ox OCaml development environment";

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
  # Upstream Eio's own release, not oxcaml/eio (an unmaintained snapshot that the
  # OxCaml repository's eio.1.3+ox points at). Only the four Eio packages are
  # taken from this revision; see eioOpamRepository below (^neio-k3vq).
  inputs.opam-repository-eio = {
    url = "github:ocaml/opam-repository/2da7d48d1861cf46ff10773584abdee8693bde2b";
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
      opam-repository-eio,
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

      # Ox's packages are whatever dune-project declares; nothing here names one
      # by hand. `packages` and OX_OPAM_PACKAGES are both derived from this
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
      # project's own (name ox) lives.
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
      oxPackageNames = builtins.filter (name: name != null) (
        builtins.map packageStanzaName (
          builtins.tail (nixpkgs.lib.splitString "(package" duneProjectCode)
        )
      );
      # An opam repository holding exactly upstream Eio 1.6 (eio, eio_posix,
      # eio_linux, eio_main). Listed first in every opam-nix resolution so the
      # OxCaml repository's eio.1.3+ox can never be chosen; dune-project also
      # requires eio >= 1.6. Consumers put the same value first in their repos
      # (^neio-k3vq).
      eioOpamRepository =
        system:
        (opam-nix.lib.${system}).filterOpamRepo {
          eio = "1.6";
          eio_posix = "1.6";
          eio_linux = "1.6";
          eio_main = "1.6";
        } opam-repository-eio;
      eioLocalOnceRecipe = system: import ./nix/eio-local-once/recipe.nix {
        pkgs = import nixpkgs { inherit system; };
        inherit opam-repository-eio;
      };
      oxBuild =
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
          oxSrc = cleanLocalSource ./.;
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
          };
          buildOpamProjectPrime = builtins.getAttr "buildOpamProject'" opam-nix.lib.${system};
          oxScope = buildOpamProjectPrime
            {
              inherit pkgs;
              overlays = [ oxcamlSystemOverlay ];
              repos = [
                (eioOpamRepository system)
                oxcaml-opam-repository
                opam-repository
              ];
              resolveArgs.env.sys-ocaml-version = "5.4.0";
            }
            oxSrc
            {
              ocaml-system = "*";
              # Yojson 3.0.0 does not compile with this OxCaml release.
              yojson = "2.2.2+ox";
            };
          experiment = import ./nix/eio-local-once {
            inherit pkgs oxcamlSystemOverlay oxcamlCompiler oxSrc oxPackageNames
              oxcaml-opam-repository opam-repository;
            mkScope = buildOpamProjectPrime;
            recipe = eioLocalOnceRecipe system;
          };
          oxPackages = builtins.listToAttrs (
            map (name: {
              inherit name;
              value = oxScope.${name};
            }) oxPackageNames
          );
          # `nix build` with no attribute: the kernel package once dune-project
          # declares it, otherwise the first package declared there.
          defaultPackage =
            if oxPackages ? ox then
              oxPackages.ox
            else if oxPackageNames == [ ] then
              throw "dune-project declares no (package ...) stanza, so there is no default package"
            else
              oxPackages.${builtins.head oxPackageNames};
        in
        {
          packages = oxPackages // {
            default = defaultPackage;
            eio-local-once = experiment.closure;
          };
          inherit experiment;
        };
    in
    {
      legacyPackages = forAllSystems (system: {
        eioOpamRepository = eioOpamRepository system;
        eioLocalOnceOpamRepository = (eioLocalOnceRecipe system).repository;
        eioLocalOnceScope = (oxBuild system).experiment.scope;
      });

      packages = forAllSystems (system: (oxBuild system).packages);

      checks = forAllSystems (system: {
        eio-local-once = (oxBuild system).experiment.nativeCheck;
        eio-local-once-external = (oxBuild system).experiment.externalCheck;
        eio-local-once-closure = (oxBuild system).experiment.closure;
      });

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
          oxOpamInstallCore = pkgs.writeShellApplication {
            name = "ox-opam-install-core";
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
              switch_name="''${OX_OPAM_SWITCH:-${oxCamlSwitch}}"
              # The tree this shell is in, not the v1 checkout the flake was
              # copied from.
              repo_root="''${OX_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
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
              preserved_dir="$switch_prefix/.opam-switch/preserved-by-ox-opam-install"

              # The packages dune-project declares, expanded by the flake when
              # it evaluates: a stale generated *.opam file cannot be pinned.
              declared="${builtins.concatStringsSep " " oxPackageNames}"
              if [ -z "$declared" ]; then
                echo "dune-project declares no package; refusing to touch the shared switch." >&2
                exit 1
              fi
              # Pin kind git at this checkout's HEAD: opam fetches that commit,
              # so only committed sources are installed and the pin cannot move
              # under a consumer's feet. Every pin carries the commit as its
              # version, so one opam list call answers "which commit is in this
              # switch", and the {= version} constraint ox's opam files put on
              # conf-ox-oxcaml resolves for all pins alike.
              ox_commit="$(git -C "$repo_root" rev-parse HEAD)"
              ox_url="git+file://$repo_root#$ox_commit"
              # Derived from dune-project: every declared package, nothing else.
              packages="''${OX_OPAM_PACKAGES:-$declared}"
              if [ "$#" -gt 0 ]; then
                packages="$*"
              fi

              # 1. Remove every installed package of this family this tree does
              #    not declare: the legacy eta* / ppx_eta* names installed by
              #    v1 and by the eta-next line (conf-eta-oxcaml included), and
              #    any ox / ox_* / ppx_ox* package a previous revision of this
              #    tree installed. opam takes their reverse dependencies with
              #    them, so a compiled consumer loses its files; the executables
              #    of those dependents are preserved across the removal below,
              #    and are not rebuilt
              #    (docs/issues/shared-switch/01-shared-switch.md, 2026-09-26).
              #    The patterns are exact: oxcaml-* guard packages are the
              #    toolchain, not this family, and must never be removed here.
              removed=()
              for package in $(opam list --installed --short); do
                case "$package" in
                  eta | eta_* | ppx_eta* | conf-eta-oxcaml | ox | ox_* | ppx_ox*) ;;
                  *) continue ;;
                esac
                case " $declared " in
                  *" $package "*) continue ;;
                esac
                removed+=("$package")
              done
              if [ "''${#removed[@]}" -gt 0 ]; then
                echo "Removing legacy Eta and stale ox packages from OPAM switch $switch_name (opam removes their reverse dependencies too): ''${removed[*]}"

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
                    eta | eta_* | ppx_eta* | conf-eta-oxcaml | ox | ox_* | ppx_ox*) continue ;;
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
                  eta | eta_* | ppx_eta* | conf-eta-oxcaml | ox | ox_* | ppx_ox*) ;;
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
              have="$(opam list --installed --short --columns=name,version "''${requested[@]}" 2>/dev/null | grep -c " $ox_commit$" || true)"
              if [ "$have" = "''${#requested[@]}" ]; then
                echo "Ox packages already installed from $repo_root at $ox_commit in OPAM switch $switch_name; nothing to do."
                exit 0
              fi

              # 3a. Installing a new ox commit makes opam rebuild every installed
              #     package that depends on it (Pie, grip, inn, ...), replacing the
              #     executables a running service will exec on its next start.
              #     Keep the executables exactly as they were: snapshot them here,
              #     put them back after the install, and leave each rebuilt one
              #     beside it as <file>.ox-<commit> for an explicit, tested
              #     cut-over (found 2026-09-28: an ox install rebuilt Pie's
              #     production binary).
              keep_dir="$preserved_dir/before-$ox_commit"
              declared_csv=""
              for package in $declared; do
                declared_csv="''${declared_csv:+$declared_csv,}$package"
              done
              kept=()
              for package in $(opam list --installed --short --recursive --depends-on "$declared_csv" 2>/dev/null); do
                case "$package" in
                  eta | eta_* | ppx_eta* | conf-eta-oxcaml | ox | ox_* | ppx_ox* | conf-ox-oxcaml) continue ;;
                esac
                # This repository's own packages (ppx_yojson_minimal, ...) are
                # what is being installed, not dependents to keep.
                case " $declared " in
                  *" $package "*) continue ;;
                esac
                changes="$switch_prefix/.opam-switch/install/$package.changes"
                [ -f "$changes" ] || continue
                while IFS= read -r line; do
                  IFS='"' read -r _ relative _ <<< "$line"
                  case "$relative" in
                    bin/* | sbin/*) ;;
                    *) continue ;;
                  esac
                  [ -f "$switch_prefix/$relative" ] || continue
                  mkdir -p "$keep_dir/$(dirname "$relative")"
                  cp -p "$switch_prefix/$relative" "$keep_dir/$relative"
                  kept+=("$relative")
                done < "$changes"
              done

              # 3. Pin every declared package to this commit and install the
              #    requested set.
              for package in $declared; do
                opam pin add --kind=git --no-action --with-version "$ox_commit" \
                  --yes "$package" "$ox_url"
              done

              # The OxCaml metadata variants currently over-constrain portability
              # against their unannotated Bigstringaf dependency.
              opam pin add angstrom.0.16.1+ox \
                https://github.com/inhabitedtype/angstrom/archive/0.16.1.tar.gz \
                --no-action --yes
              opam pin add faraday.0.8.2+ox \
                https://github.com/inhabitedtype/faraday/archive/0.8.2.tar.gz \
                --no-action --yes

              # Upstream Eio's release, never the OxCaml repository's eio.1.3+ox
              # (an unmaintained oxcaml/eio snapshot). dune-project requires
              # eio >= 1.6; eio_linux 1.6 brings uring >= 2.15 from opam.ocaml.org
              # (^neio-k3vq).
              #
              # The OxCaml compiler's switch invariant (ocaml-variants 5.4.0+ox ->
              # oxcaml-patch-guards) admits only "no eio" or eio = 1.3+ox through
              # oxcaml-<pkg>-patches. Each guard is pinned to its own opam file
              # with that one constraint changed to >= 1.6, kept under the switch;
              # the guards' other dependencies and conflicts are untouched.
              guard_root="$switch_prefix/.opam-switch/ox-upstream-eio"
              for package in eio eio_posix eio_linux eio_main; do
                guard="oxcaml-$package-patches"
                mkdir -p "$guard_root/$guard"
                opam show "$guard.enabled" --raw \
                  | sed -E 's/\(= "1\.3\+ox"\)/(>= "1.6")/' > "$guard_root/$guard/opam.new"
                if grep -q '1\.3+ox' "$guard_root/$guard/opam.new" \
                  || ! grep -q '>= "1.6"' "$guard_root/$guard/opam.new"; then
                  echo "Unexpected $guard definition; refusing to pin it:" >&2
                  cat "$guard_root/$guard/opam.new" >&2
                  exit 1
                fi
                mv -f "$guard_root/$guard/opam.new" "$guard_root/$guard/opam"
                opam pin add "$guard.enabled" "$guard_root/$guard" --kind=path \
                  --no-action --yes
                opam pin add "$package.1.6" \
                  https://github.com/ocaml-multicore/eio/releases/download/v1.6/eio-1.6.tbz \
                  --no-action --yes
              done

              # Test tooling no Ox package depends on: alcotest and qcheck
              # drive suites, memtrace is an allocation-trace hook.
              opam install alcotest qcheck memtrace --yes
              opam install "''${requested[@]}" --assume-depexts --yes

              for relative in "''${kept[@]}"; do
                current="$switch_prefix/$relative"
                if [ -f "$current" ] && cmp -s "$current" "$keep_dir/$relative"; then
                  continue
                fi
                if [ -f "$current" ]; then
                  mv -f "$current" "$current.ox-''${ox_commit:0:8}"
                  echo "Rebuilt $relative kept beside the original as $relative.ox-''${ox_commit:0:8}"
                fi
                cp -p "$keep_dir/$relative" "$current.ox-keep"
                mv -f "$current.ox-keep" "$current"
                echo "Kept $relative unchanged"
              done

              echo "Ox packages installed into OPAM switch: $switch_name"
              echo "Source: $repo_root at $ox_commit"
              echo "$packages"
            '';
          };
          # The name consumers call: it forces the shared OxCaml switch and
          # then runs the core installer, so a consumer's shell needs no
          # OX_OPAM_SWITCH of its own.
          oxOpamInstall = pkgs.writeShellApplication {
            name = "ox-opam-install";
            runtimeInputs = [ oxOpamInstallCore ];
            text = ''
              export OX_OPAM_SWITCH="${oxCamlSwitch}"
              exec ox-opam-install-core "$@"
            '';
          };
          oxCamlSetup = pkgs.writeShellApplication {
            name = "ox-oxcaml-init";
            runtimeInputs = [
              oxOpamInstallCore
            ];
            text = ''
              if [ "$#" -gt 0 ]; then
                export OX_OPAM_SWITCH="$1"
                shift
              fi
              exec ox-opam-install-core "$@"
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
            name = "ox-oxcaml-editor-tools";
            paths = [
              oxCamlMerlin
              oxCamlLsp
            ];
          };
          oxCamlToolchainCheck = pkgs.writeShellApplication {
            name = "ox-oxcaml-check-toolchain";
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
            name = "ox-oxcaml-test-shipped";
            runtimeInputs = [ pkgs.opam ];
            text = ''
              switch_name="''${1:-${oxCamlSwitch}}"
              repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
              cd "$repo_root"

              export OPAMROOT="''${OPAMROOT:-${oxCamlOpamRoot}}"
              export OPAMSWITCH="$switch_name"
              export PKG_CONFIG_PATH="${nativePkgConfigPath}:''${PKG_CONFIG_PATH:-}"
              export OX_LADYBUG_LIBRARY="${ladybugLibraryPath}"
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
              # ^ncapslint-ebh6: capability rules use the compiler-matched ox_lint.
              pkgs.sqlite
              pkgs.unzip
              pkgs.which
              oxOpamInstall
              oxOpamInstallCore
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
          eio-local-once = (oxBuild system).experiment.devShell;
          default = pkgs.mkShell {
            packages = oxCamlHostPackages;

            shellHook = ''
              export OPAMROOT="''${OPAMROOT:-${oxCamlOpamRoot}}"
              export PKG_CONFIG_PATH="${nativePkgConfigPath}:''${PKG_CONFIG_PATH:-}"
              export OX_LADYBUG_LIBRARY="${ladybugLibraryPath}"
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
                echo "Ox OxCaml shell (${oxCamlSwitch})"
                echo "Run 'shared-ocaml-switch-init' to create shared OPAM switches."
                echo "Run 'ox-opam-install' to pin this checkout's packages into ${oxCamlSwitch} (it removes legacy Eta and stale ox packages)."
                echo "Run 'ox-oxcaml-test-shipped' after setup to run the build and test gates."
              fi
            '';
          };

          oxcaml = pkgs.mkShell {
            packages = oxCamlHostPackages;

            shellHook = ''
              export OPAMROOT="''${OPAMROOT:-${oxCamlOpamRoot}}"
              export PKG_CONFIG_PATH="${nativePkgConfigPath}:''${PKG_CONFIG_PATH:-}"
              export OX_LADYBUG_LIBRARY="${ladybugLibraryPath}"
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
                echo "Ox OxCaml research shell (${oxCamlSwitch})"
                echo "Run 'shared-ocaml-switch-init' to create shared OPAM switches."
                echo "Run 'ox-opam-install' to pin this checkout's packages into ${oxCamlSwitch} (it removes legacy Eta and stale ox packages)."
                echo "Run 'ox-oxcaml-test-shipped' after setup to run the build and test gates."
              fi
            '';
          };

        }
      );
    };
}
