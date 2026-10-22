open Js_of_ocaml
open Caml2d

let white = Js.string "white"
let black = Js.string "black"
(* area outline colours, used in turn as areas are added *)
let area_colours =
  Array.map Js.string [| "steelblue"; "darkorange"; "seagreen"; "crimson"; "purple"; "goldenrod" |]


let draw_fps ctx fps =
  ctx##.fillStyle := black;
  ctx##.textAlign := Js.string "left";
  ctx##.textBaseline := Js.string "alphabetic";
  ctx##fillText (Js.string (Printf.sprintf "%d fps" !fps)) (Js.float 10.) (Js.float 20.)

(* every circle in one path, so the canvas fills and strokes once a frame *)
let draw ctx circles =
  
  ctx##.fillStyle := white;
  ctx##.strokeStyle := black;
  ctx##beginPath;
  Rigid.Circles.iteri
    (fun _ ~x ~y ~radius ->
      (* move to the arc's start point, otherwise the path joins each
          circle to the previous one with a line *)
      ctx##moveTo (Js.float (x +. radius)) (Js.float y);
      ctx##arc (Js.float x) (Js.float y) (Js.float radius) (Js.float 0.)
        (Js.float (2. *. Float.pi))
        Js._false)
    circles;
    ctx##fill;
    ctx##stroke


let draw_areas ctx areas =
      List.iter
      (fun ((area : Area.t), colour) ->
        ctx##.strokeStyle := colour;
        match area.shape with
        | Box { top_left; bottom_right } ->
            ctx##strokeRect (Js.float top_left.x) (Js.float top_left.y)
              (Js.float (bottom_right.x -. top_left.x))
              (Js.float (bottom_right.y -. top_left.y))
        | Circular { center; radius } ->
            ctx##beginPath;
            ctx##arc (Js.float center.x) (Js.float center.y) (Js.float radius)
              (Js.float 0.) (Js.float (2. *. Float.pi)) Js._false;
            ctx##stroke
        | Everywhere -> ())
      areas
  

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
