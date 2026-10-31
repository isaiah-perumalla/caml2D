open Js_of_ocaml
open Caml2d

let dt = 1. /. 120. (* fixed physics step; Verlet needs a constant dt *)
let max_dt = 0.05 (* seconds; caps the catch-up after a background tab *)
let radius = 15.
let one_second = Js.float 1000.

let () =
  let canvas =
    match Dom_html.getElementById_coerce "canvas" Dom_html.CoerceTo.canvas with
    | Some canvas -> canvas
    | None -> failwith "missing <canvas id=\"canvas\">"
  in
  let ctx = canvas##getContext Dom_html._2d_ in
  let w = Dom_html.window##.innerWidth and h = Dom_html.window##.innerHeight in
  canvas##.width := w;
  canvas##.height := h;
  let width = float_of_int w and height = float_of_int h in
  (* the bounds are shrunk by the radius so the ball's edge, not its centre,
     touches the walls *)
  let module World = Particles.Make (struct
    let top_left = Vec2.v radius radius
    let bottom_right = Vec2.v (width -. radius) (height -. radius)
    let gravity = Vec2.v 0. 980.0 (* pixels per second^2 *)
  end) in
  let module HTML = Canvas.HtmlCanvas (Vecarray.Float32Vec2) in
  let module R = Renderer.Make (HTML) (World) in
  let rows = 7 and cols = 7 in
  let n = rows * cols in
  (* spread the grid across the box with equal spacing, using whichever of
     width or height is tighter so every particle starts on screen *)
  let spacing =
    Float.min
      ((width -. (10. *. radius)) /. float_of_int (cols + 1))
      ((height -. (10. *. radius)) /. float_of_int (rows + 1))
  in
  let ps =
    World.init n (fun i ->
        (* prior position = position, so the ball starts at rest *)
        let x = radius +. (spacing *. float_of_int ((i / rows) + 1)) in
        let y = radius +. (spacing *. float_of_int (i mod rows)) in
        let p = Vec2.v x y in
        Particle.create (Particle.Position p) (Particle.PriorPosition p)
          (Particle.Mass 1.))
  in

  (* rest length = spacing, so every spring starts relaxed *)
  (* vertical: i -> i+1 within a column *)
  for i = 0 to n - 2 do
    if (i + 1) mod rows <> 0 then
      World.connect ps i (i + 1) (Particle.Spring (1500., spacing))
  done;
  (* horizontal: i -> i+rows across columns *)
  for i = 0 to n - 1 - rows do
    World.connect ps i (i + rows) (Particle.Spring (150., spacing))
  done;

  let step () =
    World.add_force ps (Force (Vec2.v 1. 0.));
    (* wind ? *)
    World.integrate ps dt
  in
  ctx##.strokeStyle := Js.string "black";
  ctx##.font := Js.string "16px monospace";

  let frame_counter = Utils.FrameCounter.make 0 in
  let fps = ref 0 in
  ignore
    (Dom_html.window##setInterval
       (Js.wrap_callback (fun () ->
            fps := Utils.FrameCounter.reset frame_counter))
       one_second);

  let draw_fps () =
    ctx##.fillStyle := Js.string "black";
    ctx##.textAlign := Js.string "left";
    ctx##.textBaseline := Js.string "alphabetic";
    ctx##fillText
      (Js.string (Printf.sprintf "%d fps" !fps))
      (Js.float 10.) (Js.float 20.)
  in

 
  let rec loop acc last now =
    let acc = ref (acc +. Float.min ((now -. last) /. 1000.) max_dt) in
    while !acc >= dt do
      step ();
      acc := !acc -. dt
    done;
    Utils.FrameCounter.incr frame_counter;
    R.render ctx ps ~radius;
    draw_fps ();
    request (loop !acc now)
  and request f =
    let callback = Js.wrap_callback (fun now -> f (Js.to_float now)) in
    ignore (Dom_html.window##requestAnimationFrame callback)
  in
  request (fun now -> loop 0. now now)
