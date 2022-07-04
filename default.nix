let
  pkgs = import <nixpkgs> {};

in
pkgs.rustPlatform.buildRustPackage {
  pname = "myproject";
  version = "1.0.0";

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  nativeBuildInputs = with pkgs; [
    pkg-config
  ];

  buildInputs = with pkgs; [
    openssl
  ];
}
