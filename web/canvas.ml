open Js_of_ocaml
open Caml2d

module HtmlCanvas (V : Vecarray.V2) = struct
  type ctx = Dom_html.canvasRenderingContext2D Js.t
  type points = V.t

  let white = Js.string "white"
  let black = Js.string "black"
  let center = Js.string "center"
  let middle = Js.string "middle"

  let clear (ctx : ctx) =
    let canvas = ctx##.canvas in
    ctx##clearRect (Js.float 0.) (Js.float 0.)
      (Js.float (float_of_int canvas##.width))
      (Js.float (float_of_int canvas##.height))

  (* index labels as JS strings, built once per index and reused every frame *)
  let labels = ref [||]

  let label i =
    if i >= Array.length !labels then
      labels :=
        Array.init
          (max (i + 1) (2 * Array.length !labels))
          (fun j ->
            if j < Array.length !labels then !labels.(j)
            else Js.string (string_of_int j));
    !labels.(i)

  (* all circles go in one path, so the canvas fills and strokes once per
     frame; the labels are drawn in a second pass with the text state set once *)
  let circles (ctx : ctx) ps ~radius =
    let r = Js.float radius
    and start = Js.float 0.
    and stop = Js.float (2. *. Float.pi) in
    ctx##.fillStyle := white;
    ctx##beginPath;
    V.iteri
      (fun _ x y ->
        (* move to the arc's start point, otherwise the path joins each
           circle to the previous one with a line *)
        ctx##moveTo (Js.float (x +. radius)) (Js.float y);
        ctx##arc (Js.float x) (Js.float y) r start stop Js._false)
      ps;
    ctx##fill;
    ctx##stroke;
    ctx##.fillStyle := black;
    ctx##.textAlign := center;
    ctx##.textBaseline := middle;
    V.iteri (fun i x y -> ctx##fillText (label i) (Js.float x) (Js.float y)) ps

  let line (ctx : ctx) ~x1 ~y1 ~x2 ~y2 =
    ctx##beginPath;
    ctx##moveTo (Js.float x1) (Js.float y1);
    ctx##lineTo (Js.float x2) (Js.float y2);
    ctx##stroke
end
