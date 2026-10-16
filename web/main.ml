open Js_of_ocaml
open Caml2d

module HtmlCanvas = struct
  type ctx = Dom_html.canvasRenderingContext2D Js.t

  let clear (ctx : ctx) =
    let canvas = ctx##.canvas in
    ctx##clearRect (Js.float 0.) (Js.float 0.)
      (Js.float (float_of_int canvas##.width))
      (Js.float (float_of_int canvas##.height))

  let circle (ctx : ctx) ~x ~y ~radius =
    ctx##beginPath;
    ctx##arc (Js.float x) (Js.float y) (Js.float radius) (Js.float 0.)
      (Js.float (2. *. Float.pi))
      Js._false;
    ctx##fill;
    ctx##stroke

  let line (ctx : ctx) ~x1 ~y1 ~x2 ~y2 =
    ctx##beginPath;
    ctx##moveTo (Js.float x1) (Js.float y1);
    ctx##lineTo (Js.float x2) (Js.float y2);
    ctx##stroke
end


let dt = 1. /. 120. (* fixed physics step; Verlet needs a constant dt *)
let max_dt = 0.05 (* seconds; caps the catch-up after a background tab *)
let radius = 20.
let one_second = (Js.float 1000.)

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
    let gravity =  Vec2.v 0. 980.0 (* pixels per second^2 *)
  end) in
  
  let module R = Renderer.Make (HtmlCanvas) (World) in
  
  let ps =
    World.init 20 (fun i ->
        (* prior position = position, so the ball starts at rest *)
        let offset = float_of_int i *. 50. in
        let p = Vec2.v (width /. 2. +. offset) radius  in
        Particle.create (Particle.Position p) (Particle.PriorPosition p)
          (Particle.Mass 1.)) in
    
    (* connect particles with springs *)
    World.connect ps 0 1 (Particle.Spring (100., 50.));
    World.connect ps 1 2 (Particle.Spring (100., 50.));
  
  let step () =
    World.add_force ps (Force (Vec2.v 1. 0.)); (* wind ? *)
    World.integrate ps dt;
  in
  ctx##.strokeStyle := Js.string "black";
  ctx##.font := Js.string "16px monospace";
 
  let frame_counter = Utils.FrameCounter.make 0 in
  let fps = ref 0  in
  ignore
    (Dom_html.window##setInterval
       (Js.wrap_callback (fun () -> fps := Utils.FrameCounter.reset frame_counter))
       one_second);
  
  let draw_fps () =
    ctx##.fillStyle := Js.string "black";
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
    ctx##.fillStyle := Js.string "white";
    R.render ctx ps ~radius;
    draw_fps ();
    request (loop !acc now)
  and request f =
    let callback = Js.wrap_callback (fun now -> f (Js.to_float now)) in
    ignore (Dom_html.window##requestAnimationFrame callback)
  in
  request (fun now -> loop 0. now now)
