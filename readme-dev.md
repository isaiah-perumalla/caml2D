# caml2d — developer notes

## The OCaml environment

The toolchain (OCaml, dune, js_of_ocaml, ocamlformat) lives in a local opam
switch in `_opam/`, created by the setup step in `README.md`. Nothing is
installed system-wide, so in a new terminal `dune` is not found until you load
the switch:

```sh
eval $(opam env)
dune build
```

Do not `apt install ocaml-dune`: that installs a separate, older dune that does
not match the packages in `_opam/`.

To load it automatically, add this to `~/.bashrc`:

```sh
eval $(opam env --shell=bash)
```

opam selects the switch from the current directory, so this takes effect in
terminals opened inside the project.

## Checking versions

After `eval $(opam env)`:

```sh
ocaml -version            # compiler version
which ocaml               # should be .../caml2d/_opam/bin/ocaml
opam switch show          # which switch is active
opam list --installed     # every package and its version
```

If `which ocaml` prints nothing, the switch is not loaded in that terminal.

`dune-project` only requires `ocaml >= 5.3`; opam installed the newest
release available when the switch was created. As of 2026-10-14:

| Package | Version |
|---|---|
| ocaml | 5.4.1 |
| dune | 3.24.2 |
| js_of_ocaml | 6.4.1 |
