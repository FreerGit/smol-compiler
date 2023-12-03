# smol-compiler
A dead simple compiler targeting nasm, smol is pascal-like and features some simple IO operations. The language is really dead simple, it does not even have a notion of scopes. What interested me was the assembly generation though, not the feature set of the language. 

## Nix
I use nix, specifically nix-shell, simply run:

```console
nix-shell --max-jobs auto
```

A new shell will (after a long build time the first time, sorry) open with all necessary dependencies to build the compiler.

To run (within nix-shell):

TODO
```console
```

To install nix follow: [nix install docs](https://nixos.org/download)

If you would rather use odin directly without nix, then see Odin install docs: [Odin install docs](https://odin-lang.org/docs/install/)


