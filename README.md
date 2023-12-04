# smol-compiler
A dead simple compiler targeting nasm, smol is pascal-like and features some simple IO operations. The language is really dead simple, it does not even have a notion of scopes. What interested me was the assembly generation though, not the feature set of the language. 

## Nix
To install nix, see: [Nix install docs](https://nixos.org/download)

I use nix, specifically nix-shell, simply run:

```console
nix-shell --max-jobs auto
```

A new shell will open with all necessary dependencies to build the compiler.

To run (within nix-shell):
```console
odin run ./src/smol.odin -file -- ./smol-programs/arith.smol
```

of course, you can pass any file with smol code, `arith.smol` is just an example.

If you would rather use Odin directly without nix, please see Odin install docs: [Odin install docs](https://odin-lang.org/docs/install/)


