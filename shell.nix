{ pkgs ? import <nixpkgs> { } }:
let
  odin-unwrapped = pkgs.llvmPackages_11.stdenv.mkDerivation (rec {
    name = "odin-unwrapped";
    src = ./.;
    dontConfigure = true;
    nativeBuildInputs = [ pkgs.git ];
  });
in
pkgs.mkShell {
  nativeBuildInputs = with pkgs; [     bintools
    llvm
    clang
    lld 
    gcc_multi
  ];
}