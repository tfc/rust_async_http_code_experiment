{
  description = "Heise Nix Example Project";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
    advisory-db.url = "github:rustsec/advisory-db";
    advisory-db.flake = false;
    crane.url = "github:ipetkov/crane";
    crane.inputs.nixpkgs.follows = "nixpkgs";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    systems = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    perSystem = { config, pkgs, system, ... }:
      let
        craneLib = inputs.crane.lib.${system};
        src = craneLib.cleanCargoSource (craneLib.path ./.);
        cargoArtifacts = craneLib.buildDepsOnly {
          inherit src;
          buildInputs = with pkgs; [ openssl pkg-config ];
        };

      in
      {
        devShells.default = pkgs.mkShell {
          inputsFrom = builtins.attrValues config.checks;
          inherit (config.checks.pre-commit-check) shellHook;
        };

        packages = {
          default = craneLib.buildPackage {
            inherit cargoArtifacts src;
          };

          docs = craneLib.cargoDoc {
            inherit cargoArtifacts src;
          };

          static =
            let
              staticPkgs = import inputs.nixpkgs {
                inherit system;
                overlays = [ (import inputs.rust-overlay) ];
              };

              archPrefix = builtins.elemAt (pkgs.lib.strings.split "-" system) 0;

              staticCraneLib =
                let
                  rustToolchain = staticPkgs.rust-bin.stable.latest.default.override {
                    targets = [ "${archPrefix}-unknown-linux-musl" ];
                  };
                in
                  (inputs.crane.mkLib staticPkgs).overrideToolchain rustToolchain;

            in
              staticCraneLib.buildPackage {
                inherit src;

                CARGO_BUILD_TARGET = "x86_64-unknown-linux-musl";
                CARGO_BUILD_RUSTFLAGS = "-C target-feature=+crt-static";

                nativeBuildInputs = [ pkgs.pkg-config ];
                buildInputs = [ pkgs.pkgsStatic.openssl ];
              };
        } // pkgs.lib.optionalAttrs (!pkgs.stdenv.isAarch64) {
          crossArm =
            let
              crossSystem = "aarch64-linux";

              crossPkgs = import inputs.nixpkgs {
                inherit crossSystem;
                localSystem = system;
                overlays = [ (import inputs.rust-overlay) ];
              };

              rustToolchain = crossPkgs.pkgsBuildHost.rust-bin.stable.latest.default.override {
                targets = [ "aarch64-unknown-linux-gnu" ];
              };

              craneLib = (inputs.crane.mkLib crossPkgs).overrideToolchain rustToolchain;

              crateExpression = { openssl , lib , pkg-config , stdenv }:
                craneLib.buildPackage {
                  inherit src;

                  nativeBuildInputs = [ pkg-config ];
                  buildInputs = [ openssl ];

                  CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER = "${stdenv.cc.targetPrefix}cc";
                  CARGO_BUILD_TARGET = "aarch64-unknown-linux-gnu";
                  HOST_CC = "${stdenv.cc.nativePrefix}cc";
                };
            in
              crossPkgs.callPackage crateExpression { };
        };

        checks = {
          inherit (config.packages)
            default
            docs
            ;

          hello-rust-audit = craneLib.cargoAudit {
            inherit (inputs) advisory-db;
            inherit src;
          };

          pre-commit-check = inputs.pre-commit-hooks.lib.${system}.run {
            src = ./.;
            hooks = {
              # Rust
              clippy.enable = true;
              rustfmt.enable = true;

              # Nix
              deadnix.enable = true;
              nixpkgs-fmt.enable = true;
              statix.enable = true;

              # Shell
              shellcheck.enable = true;
              shfmt.enable = true;
            };
            settings.rust.cargoManifestPath = "./rust/Cargo.toml";
          };
        };
      };
  };
}
