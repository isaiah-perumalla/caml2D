# caml2d

2D physics simulation in the browser, written in OCaml and compiled to
JavaScript with js_of_ocaml.

## Setup

```sh
opam switch create . --deps-only --with-test --with-dev-setup
eval $(opam env)
```

## Commands

```sh
dune build                    # build the site into _build/default/web
dune build --watch            # rebuild on change
dune build --profile release  # optimised, smaller JavaScript
dune test                     # run the native tests
dune fmt                      # format with ocamlformat
```

`caml2d.opam` is generated from `dune-project`. After changing dependencies
there, run `dune build @opam` and then `dune promote` to update it.

Open `_build/default/web/index.html` in a browser, or serve the directory:

```sh
python3 -m http.server -d _build/default/web 8000
```

## Layout

- `lib/` — pure OCaml simulation code, testable natively
- `web/` — browser entry point (canvas, animation loop) and static files
- `test/` — tests for `lib/`
