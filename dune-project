(lang dune 3.24)

(name caml2d)

(generate_opam_files true)

(package
 (name caml2d)
 (synopsis "2D physics simulation in the browser, written in OCaml")
 (depends
  (ocaml
   (>= 5.3))
  (js_of_ocaml
   (>= 6.0))
  (js_of_ocaml-compiler
   (>= 6.0))
  (js_of_ocaml-ppx
   (>= 6.0))
  (ocamlformat
   (and
    :with-dev-setup
    (= 0.29.0)))
  (ocaml-lsp-server :with-dev-setup)))
