let
  # We specify sources via Niv: use "niv update nixpkgs" to update nixpkgs, for example.
  sources = import ./util/nix/sources.nix { };

  # `tomlkit` >= 0.8.0 is required to build `jsonschema` >= 4.11.0 (older
  # version do not support some valid TOML syntax: sdispater/tomlkit#148).  The
  # updated `tomlkit` must be used by `makeRemoveSpecialDependenciesHook`
  # inside `poetry2nix`, therefore just providing the updated version through
  # our `nix/pyproject.toml` does not work, and using an overlay is required.
  pythonOverlay = final: prev: {
    python3 = prev.python3.override {
      packageOverrides = self: super: {
        tomlkit = super.tomlkit.overridePythonAttrs(old: rec {
          version = "0.11.4";
          src = super.fetchPypi {
            inherit (old) pname;
            inherit version;
            sha256 = "sha256-MjWpAQ+uVDI+cnw6wG+3IHUv5mNbNCbjedrsYPvUSoM=";
          };
        });
      };
    };
  };
in
# However, if you want to override Niv's inputs, this will let you do that.
{ pkgs ? import sources.nixpkgs { overlays = [ pythonOverlay ]; }
, poetry2nix ? pkgs.callPackage (import sources.poetry2nix) { }
, avr ? true
, arm ? true
, teensy ? true }:
with pkgs;
let
  avrlibc = pkgsCross.avr.libcCross;

  avr_incflags = [
    "-isystem ${avrlibc}/avr/include"
    "-B${avrlibc}/avr/lib/avr5"
    "-L${avrlibc}/avr/lib/avr5"
    "-B${avrlibc}/avr/lib/avr35"
    "-L${avrlibc}/avr/lib/avr35"
    "-B${avrlibc}/avr/lib/avr51"
    "-L${avrlibc}/avr/lib/avr51"
  ];

  # Builds the python env based on nix/pyproject.toml and
  # nix/poetry.lock Use the "poetry update --lock", "poetry add
  # --lock" etc. in the nix folder to adjust the contents of those
  # files if the requirements*.txt files change
  pythonEnv = poetry2nix.mkPoetryEnv {
    projectDir = ./util/nix;
    overrides = poetry2nix.overrides.withDefaults (self: super: {
      pillow = super.pillow.overridePythonAttrs(old: {
        # Use preConfigure from nixpkgs to fix library detection issues and
        # impurities which can break the build process; this also requires
        # adding propagatedBuildInputs and buildInputs from the same source.
        propagatedBuildInputs = (old.buildInputs or []) ++ pkgs.python3.pkgs.pillow.propagatedBuildInputs;
        buildInputs = (old.buildInputs or []) ++ pkgs.python3.pkgs.pillow.buildInputs;
        preConfigure = (old.preConfigure or "") + pkgs.python3.pkgs.pillow.preConfigure;
      });
      qmk = super.qmk.overridePythonAttrs(old: {
        # Allow QMK CLI to run "qmk" as a subprocess (the wrapper changes
        # $PATH and breaks these invocations).
        dontWrapPythonPrograms = true;
      });
    });
  };
in
mkShell {
  name = "qmk-firmware";

  buildInputs = [ clang-tools dfu-programmer dfu-util diffutils git pythonEnv niv util-linux ]
    ++ lib.optional avr [
      pkgsCross.avr.buildPackages.binutils
      pkgsCross.avr.buildPackages.gcc8
      avrlibc
      avrdude
    ]
    ++ lib.optional arm [ gcc-arm-embedded ]
    ++ lib.optional teensy [ teensy-loader-cli ];

  AVR_CFLAGS = lib.optional avr avr_incflags;
  AVR_ASFLAGS = lib.optional avr avr_incflags;
  shellHook = ''
    # Prevent the avr-gcc wrapper from picking up host GCC flags
    # like -iframework, which is problematic on Darwin
    unset NIX_CFLAGS_COMPILE_FOR_TARGET

    # This pinned shell ships Git older than zdiff3; configure this checkout
    # and its initialized submodules to use the broadly supported diff3 style.
    git config merge.conflictStyle diff3
    git submodule foreach --recursive 'git config merge.conflictStyle diff3' 2>/dev/null || true

    printf '%s\n' \
      '╭─ Miryoku · QMK ─────────────────────────────────────────────╮' \
      '│ Keyboard: Ferris Sweep · standard Miryoku configuration       │' \
      '│ Build:  qmk-ferris-build                                      │' \
      '│ Flash:  qmk-ferris-flash (USB bootloader)                     │' \
      '│ Frood: qmk-frood-left/right-flash <mounted-volume>          │' \
      '│ Sea-Picro: qmk-ferris-left-flash / right-flash <volume>       │' \
      '╰──────────────────────────────────────────────────────────────╯' \
      'Frood RP2040 in Ferris Sweep: mount the RP2 volume and pass its path.' \
      'Sea-Picro: hold BOOTSEL/reset to mount a half, then use its matching flash helper.' \
      'QWERTY + VI navigation; standard Miryoku home-row mods; alpha-row combos: W+R media/esc, U+O fun/del.'

    qmk-ferris-setup() {
      git config merge.conflictStyle diff3 || return
      git submodule foreach --recursive 'git config merge.conflictStyle diff3' 2>/dev/null || true
      git -c merge.conflictStyle=diff3 submodule update --init --recursive
    }

    # Build or flash the original AVR Ferris Sweep, not Sea-Picro.
    qmk-ferris-build() {
      qmk-ferris-setup || return
      make ferris/sweep:manna-harbour_miryoku "$@"
    }
    qmk-ferris-flash() {
      case "''${1:-}" in
        /*|./*|../*)
          printf '%s\n' 'For Sea-Picro use qmk-ferris-left-flash <volume> or qmk-ferris-right-flash <volume>.' >&2
          return 2 ;;
      esac
      qmk-ferris-setup || return
      make ferris/sweep:manna-harbour_miryoku:flash "$@"
    }
    alias ferris-sweep=qmk-ferris-build
    alias ferris-sweep-flash=qmk-ferris-flash

    # Frood is an RP2040 Pro Micro controller. Build each Ferris Sweep half
    # with explicit handedness and copy the UF2 to the caller's mounted volume.
    qmk-frood-left() {
      qmk-ferris-setup || return
      make CONVERT_TO=promicro_rp2040 \
        TARGET=ferris_sweep_manna-harbour_miryoku_promicro_rp2040_left \
        EXTRAFLAGS=-DINIT_EE_HANDS_LEFT ferris/sweep:manna-harbour_miryoku "$@"
    }
    qmk-frood-right() {
      qmk-ferris-setup || return
      make CONVERT_TO=promicro_rp2040 \
        TARGET=ferris_sweep_manna-harbour_miryoku_promicro_rp2040_right \
        EXTRAFLAGS=-DINIT_EE_HANDS_RIGHT ferris/sweep:manna-harbour_miryoku "$@"
    }
    qmk-frood-left-flash() {
      if [ "$#" -ne 1 ]; then printf '%s\n' 'Usage: qmk-frood-left-flash <mounted-RP2-volume>' >&2; return 2; fi
      qmk-frood-left || return
      qmk-ferris-flash-uf2 "$PWD/ferris_sweep_manna-harbour_miryoku_promicro_rp2040_left.uf2" "$1"
    }
    qmk-frood-right-flash() {
      if [ "$#" -ne 1 ]; then printf '%s\n' 'Usage: qmk-frood-right-flash <mounted-RP2-volume>' >&2; return 2; fi
      qmk-frood-right || return
      qmk-ferris-flash-uf2 "$PWD/ferris_sweep_manna-harbour_miryoku_promicro_rp2040_right.uf2" "$1"
    }

    # Build left/right Ferris Sweep UF2 firmware for Sea-Picro (RP2040 CE).
    # uf2-split-left/right are FLASH targets in QMK. Build normally with
    # the same handedness defines instead, retaining separate output files.
    qmk-ferris-left() {
      qmk-ferris-setup || return
      make CONVERT_TO=rp2040_ce TARGET=ferris_sweep_manna-harbour_miryoku_rp2040_ce_left \
        EXTRAFLAGS=-DINIT_EE_HANDS_LEFT ferris/sweep:manna-harbour_miryoku "$@"
    }
    qmk-ferris-right() {
      qmk-ferris-setup || return
      make CONVERT_TO=rp2040_ce TARGET=ferris_sweep_manna-harbour_miryoku_rp2040_ce_right \
        EXTRAFLAGS=-DINIT_EE_HANDS_RIGHT ferris/sweep:manna-harbour_miryoku "$@"
    }
    qmk-ferris-build-uf2() {
      qmk-ferris-left && qmk-ferris-right || return
      printf '%s\n' 'Built UF2 firmware. For flashing, boot a half into BOOTSEL and run the matching qmk-ferris-left-flash or qmk-ferris-right-flash helper.'
    }

    qmk-ferris-flash-uf2() {
      if [ "$#" -ne 2 ]; then
        printf '%s\n' 'Usage: qmk-ferris-flash-uf2 <firmware.uf2> <mounted-bootloader-volume>' >&2
        return 2
      fi
      local firmware="$1" mountpoint_path="$2"
      [ -f "$firmware" ] || { printf 'UF2 file not found: %s\n' "$firmware" >&2; return 1; }
      case "$firmware" in *.uf2) ;; *) printf '%s\n' 'Expected a .uf2 firmware file' >&2; return 1 ;; esac
      mountpoint -q "$mountpoint_path" || { printf 'Not a mounted bootloader volume: %s\n' "$mountpoint_path" >&2; return 1; }
      sudo ${coreutils}/bin/cp "$firmware" "$mountpoint_path/" || return
      printf 'Copied %s to %s; the bootloader should disconnect when flashing completes.\n' "$(basename "$firmware")" "$mountpoint_path"
    }

    qmk-ferris-left-flash() {
      if [ "$#" -ne 1 ]; then printf '%s\n' 'Usage: qmk-ferris-left-flash <mounted-bootloader-volume>' >&2; return 2; fi
      qmk-ferris-left || return
      qmk-ferris-flash-uf2 "$PWD/ferris_sweep_manna-harbour_miryoku_rp2040_ce_left.uf2" "$1"
    }
    qmk-ferris-right-flash() {
      if [ "$#" -ne 1 ]; then printf '%s\n' 'Usage: qmk-ferris-right-flash <mounted-bootloader-volume>' >&2; return 2; fi
      qmk-ferris-right || return
      qmk-ferris-flash-uf2 "$PWD/ferris_sweep_manna-harbour_miryoku_rp2040_ce_right.uf2" "$1"
    }
  '';
}
