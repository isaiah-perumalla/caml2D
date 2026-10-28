open Js_of_ocaml
open Caml2d

let white = Js.string "white"
let black = Js.string "black"
module Detect = Collision.PairwiseContacts
module Contacts = Collision.Contacts
module V2 = Vecarray.Float32Vec2

(* area outline colours, used in turn as areas are added *)
let area_colours =
  Array.map Js.string
    [|
      "steelblue"; "darkorange"; "seagreen"; "crimson"; "purple"; "goldenrod";
    |]

let circle_colours = Array.map Js.string
    [|
      "steelblue"; "darkorange"; "red";  "green"; "black";
    |]

let draw_fps ctx fps =
  ctx##.fillStyle := black;
  ctx##.textAlign := Js.string "left";
  ctx##.textBaseline := Js.string "alphabetic";
  ctx##fillText
    (Js.string (Printf.sprintf "%d fps" fps))
    (Js.float 10.) (Js.float 20.)

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

(* fill colours for colliding pairs; a pair's colour comes from its two
   indices, so it stays the same while the pair keeps touching instead of
   changing every frame *)
let collision_colours =
  Array.init 12 (fun k ->
      Js.string (Printf.sprintf "hsl(%d, 80%%, 60%%)" (k * 30)))

(* fills both circles of each colliding pair with that pair's colour; drawn
   after [draw], so the colours aren't painted over. A circle in several pairs
   ends up with the colour of the last one drawn *)
let draw_collisions ctx circles contacts =
  
  let positions = Positions.Linear.positions (Rigid.Circles.linear circles) in
  let fill_circle i =
    let x = V2.getx positions i and y = V2.gety positions i in
    let radius = Rigid.Circles.radius circles i in
    ctx##beginPath;
    ctx##arc (Js.float x) (Js.float y) (Js.float radius) (Js.float 0.)
      (Js.float (2. *. Float.pi))
      Js._false;
    ctx##fill;
    ctx##stroke
  in
  ctx##.strokeStyle := black;
  for k = 0 to Contacts.length contacts - 1 do
    let a = Contacts.a contacts ~i:k and b = Contacts.b contacts ~i:k in
    let colour =
      collision_colours.(((a * 31) + b) mod Array.length collision_colours)
    in
    ctx##.fillStyle := colour;
    fill_circle a;
    fill_circle b
  done

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
            (Js.float 0.)
            (Js.float (2. *. Float.pi))
            Js._false;
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
