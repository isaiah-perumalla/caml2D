(* click to drop a circle where you clicked *)
open Js_of_ocaml
open Caml2d

let dt = 1. /. 120. (* fixed physics step; Verlet needs a constant dt *)
let max_dt = 0.05 (* seconds; caps the catch-up after a background tab *)
let max_circles = 500
let white = Js.string "white"
let black = Js.string "black"
let one_second = Js.float 1000.
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

  (* the walls are the window, known only at run time, so the functor is
     applied here, as Particles.Make is in main.ml *)
  let module A = World.Make (struct
    let top_left = Vec2.v 0. 0.
    let bottom_right = Vec2.v width height
    let gravity = Vec2.v 0. 980. (* pixels per second^2 *)
  end) in
  let arena = A.create ~max_circles in

  (* World doesn't expose its areas, so keep a list here for drawing; each
     area gets its colour when added, so adding more doesn't change the others *)
  let areas = ref [] in
  let add_area area =
    A.add_area arena area;
    let colour = area_colours.(List.length !areas mod Array.length area_colours) in
    areas := (area, colour) :: !areas
  in

  (* world-wide gravity as an area; drop this if World.Make applies
     PARAMS.gravity itself, or gravity is applied twice *)
  add_area
    Area.
      {
        shape = Everywhere;
        params = { forces = Vec2.zero; drag_const = 0.; gravity = Vec2.v 0. 980. };
      };
  add_area
    Area.
      {
        shape = Box { top_left = Vec2.v 0. (height -. 300.); 
                      bottom_right = Vec2.v (width -. (width /. 3.) ) height };
        params = { forces = Vec2.zero; drag_const = 0.; gravity = Vec2.v 300. (-3000.) };
      };

   add_area
    Area.
      {
        shape = Box { top_left = Vec2.v (width -. (width /. 3.) ) (height -. 300.); 
                      bottom_right = Vec2.v width  height };
        params = { forces = Vec2.zero; drag_const = 0.; gravity = Vec2.v (-300.) (-3000.) };
      };

  (* a click adds a circle at rest at the click point; clientX/Y match canvas
     coordinates because the canvas fills the window from its top-left *)
  canvas##.onclick :=
    Dom_html.handler (fun ev ->
        let p = Vec2.v (Js.to_float ev##.clientX) (Js.to_float ev##.clientY) in
        let radius = 10. +. Random.float 20. in
        (match A.add_circle arena ~position:p ~prior_position:p ~inv_mass:1. ~radius with
        | Some _ -> ()
        | None -> Console.console##log (Js.string "arena full"));
        Js._false);

  let frame_counter = Utils.FrameCounter.make 0 in
  let fps = ref 0 in
  ignore
    (Dom_html.window##setInterval
       (Js.wrap_callback (fun () ->
            fps := Utils.FrameCounter.reset frame_counter))
       one_second);

 
  let rec loop acc last now =
    let acc = ref (acc +. Float.min ((now -. last) /. 1000.) max_dt) in
    while !acc >= dt do
      A.step arena dt;
      acc := !acc -. dt
    done;
    Utils.FrameCounter.incr frame_counter;
    ctx##clearRect (Js.float 0.) (Js.float 0.) (Js.float width) (Js.float height);

    draw_areas ctx !areas;
    draw ctx (A.circles arena);
    draw_fps ctx fps;
    request (loop !acc now)
  and request f =
    let callback = Js.wrap_callback (fun now -> f (Js.to_float now)) in
    ignore (Dom_html.window##requestAnimationFrame callback)
  in
  request (fun now -> loop 0. now now)
