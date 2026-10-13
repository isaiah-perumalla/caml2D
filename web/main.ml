open Js_of_ocaml
open Caml2d

let gravity = Vec2.v 0. 980. (* pixels per second^2 *)
let restitution = 0.8
let max_dt = 0.05 (* seconds; caps the step after a background tab *)
let radius = 20.

let () =
  let canvas =
    match Dom_html.getElementById_coerce "canvas" Dom_html.CoerceTo.canvas with
    | Some canvas -> canvas
    | None -> failwith "missing <canvas id=\"canvas\">"
  in
  let ctx = canvas##getContext Dom_html._2d_ in
  let width = Dom_html.window##.innerWidth in
  let height = Dom_html.window##.innerHeight in
  canvas##.width := width;
  canvas##.height := height;
  let width = float_of_int width and height = float_of_int height in
  let pos = ref (Vec2.v (width /. 2.) radius) in
  let vel = ref Vec2.zero in
  let step dt =
    vel := Vec2.add !vel (Vec2.scale dt gravity);
    pos := Vec2.add !pos (Vec2.scale dt !vel);
    if !pos.y > height -. radius then (
      pos := { !pos with y = height -. radius };
      vel := { !vel with y = -. !vel.y *. restitution })
  in
  let draw () =
    ctx##clearRect (Js.float 0.) (Js.float 0.) (Js.float width)
      (Js.float height);
    ctx##.fillStyle := Js.string "white";
    ctx##.strokeStyle := Js.string "black";
    ctx##beginPath;
    ctx##arc (Js.float !pos.x) (Js.float !pos.y) (Js.float radius) (Js.float 0.)
      (Js.float (2. *. Float.pi))
      Js._false;
    ctx##fill;
    ctx##stroke
  in
  let rec loop last now =
    step (Float.min ((now -. last) /. 1000.) max_dt);
    draw ();
    request (loop now)
  and request f =
    let callback = Js.wrap_callback (fun now -> f (Js.to_float now)) in
    ignore (Dom_html.window##requestAnimationFrame callback)
  in
  request (fun now -> loop now now)
