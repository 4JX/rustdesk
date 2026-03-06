{
  description = "Cross platform software to control the RGB/lighting of the 4 zone keyboard included in the 2020, 2021, 2022, 2023 and 2024 lineup of the Lenovo Legion laptops";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    crane.url = "github:ipetkov/crane";

    flake-parts.url = "github:hercules-ci/flake-parts";

    systems.url = "github:nix-systems/default-linux";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      flake-parts,
      systems,
      crane,
      rust-overlay,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import systems;

      perSystem =
        {
          system,
          pkgs,
          lib,
          ...
        }:
        let
          rustVersion = "1.94.0";

          rust = pkgs.rust-bin.stable.${rustVersion}.default.override {
            extensions = [
              "rust-src" # rust-analyzer
            ];
          };

          craneLib = (crane.mkLib pkgs).overrideToolchain rust;

          # Libraries needed both at compile and runtime
          sharedDeps = with pkgs; [
            ffmpeg_7
            fuse3
            gst_all_1.gst-plugins-base
            gst_all_1.gstreamer
            libXtst
            libaom
            libopus
            libpulseaudio
            libva
            libvdpau
            libvpx
            pipewire
            libxkbcommon
            libyuv
            pam
            xdotool
            atk
            bzip2
            cairo
            dbus
            gdk-pixbuf
            glib
            gst_all_1.gst-plugins-base
            gst_all_1.gstreamer
            gtk3
            libgit2
            libpulseaudio
            libsodium
            libXtst
            libvpx
            libyuv
            libopus
            libaom
            libxkbcommon
            pam
            pango
            zlib
            zstd
            openssl
          ];

          # Libraries needed at runtime
          runtimeDeps =
            with pkgs;
            [
              libXcursor
              libxcb
              freetype
              libXrandr
              libGL
              wayland
              libxkbcommon

              # Tray icon
              libayatana-appindicator
            ]
            ++ sharedDeps;

          buildEnvVars = {
            LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";
            OPENSSL_DIR = "${pkgs.openssl.dev}";
            OPENSSL_LIB_DIR = "${pkgs.openssl.out}/lib";
            OPENSSL_INCLUDE_DIR = "${pkgs.openssl.dev}/include";
            X86_64_UNKNOWN_LINUX_GNU_OPENSSL_DIR = "${pkgs.openssl.dev}";
            X86_64_UNKNOWN_LINUX_GNU_OPENSSL_LIB_DIR = "${pkgs.openssl.out}/lib";
            X86_64_UNKNOWN_LINUX_GNU_OPENSSL_INCLUDE_DIR = "${pkgs.openssl.dev}/include";
            CC = "clang";
            CXX = "clang++";
            HOST_CC = "clang";
            CC_x86_64_unknown_linux_gnu = "clang";
            SODIUM_USE_PKG_CONFIG = "1";
          };

          # Allow a few more files to be included in the build workspace
          workspaceSrc = ./.;
          workspaceSrcString = builtins.toString workspaceSrc;

          resFileFilter = path: _type: lib.hasPrefix "${workspaceSrcString}/app/res/" path;
          workspaceFilter = path: type: (resFileFilter path type) || (craneLib.filterCargoSources path type);

          src = lib.cleanSourceWith {
            src = workspaceSrc;
            filter = workspaceFilter;
          };

          # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/ru/rustdesk/package.nix
          buildInputs =
            with pkgs;
            [
              libvpx
              libyuv
              libaom
            ]
            ++ sharedDeps;

          nativeBuildInputs = with pkgs; [
            pkg-config
            cmake
            clang
          ];

          # Forgo using VCPKG hacks on local builds because pain
          cargoExtraArgs = ''--locked --features "scrap/linux-pkg-config"'';

          inherit (craneLib.crateNameFromCargoToml { cargoToml = ./Cargo.toml; }) pname version;

          commonArgs = {
            inherit
              pname
              version
              src
              buildInputs
              nativeBuildInputs
              cargoExtraArgs
              ;
          }
          // buildEnvVars;

          cargoArtifacts = craneLib.buildDepsOnly commonArgs;

          # The main application derivation
          legion-kb-rgb = craneLib.buildPackage (
            commonArgs
            // {
              meta.mainProgram = pname;
              inherit cargoArtifacts;

              doCheck = false;

              postFixup = ''
                patchelf --add-rpath "${lib.makeLibraryPath runtimeDeps}" "$out/bin/${pname}"
              '';
            }
          );
        in
        {
          _module.args.pkgs = import nixpkgs {
            inherit system;
            overlays = [ (import rust-overlay) ];
          };

          packages.default = legion-kb-rgb;

          apps.default.program = "${legion-kb-rgb}/bin/${pname}";

          devShells.default =
            let
              deps = buildInputs ++ nativeBuildInputs ++ runtimeDeps;
            in
            pkgs.mkShell {
              LD_LIBRARY_PATH = lib.makeLibraryPath deps;
              RUST_BACKTRACE = "1";
              inherit (buildEnvVars)
                LIBCLANG_PATH
                OPENSSL_DIR
                OPENSSL_LIB_DIR
                OPENSSL_INCLUDE_DIR
                X86_64_UNKNOWN_LINUX_GNU_OPENSSL_DIR
                X86_64_UNKNOWN_LINUX_GNU_OPENSSL_LIB_DIR
                X86_64_UNKNOWN_LINUX_GNU_OPENSSL_INCLUDE_DIR
                CC
                CXX
                HOST_CC
                CC_x86_64_unknown_linux_gnu
                SODIUM_USE_PKG_CONFIG
                ;

              buildInputs = [ rust ] ++ deps;
            };
        };
    };
}
