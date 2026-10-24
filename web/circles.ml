(* click to drop a circle where you clicked *)
open Js_of_ocaml
open Caml2d

let dt = 1. /. 120. (* fixed physics step; Verlet needs a constant dt *)
let max_dt = 0.05 (* seconds; caps the catch-up after a background tab *)
let max_circles = 500
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
    let area_colours = Canvas.area_colours in
    let colour =
      area_colours.(List.length !areas mod Array.length area_colours)
    in
    areas := (area, colour) :: !areas
  in

  (* world-wide gravity as an area; drop this if World.Make applies
     PARAMS.gravity itself, or gravity is applied twice *)
  add_area
    Area.
      {
        shape = Everywhere;
        params =
          { forces = Vec2.zero; drag_const = 0.; gravity = Vec2.v 0. 980. };
      };
  add_area
    Area.
      {
        shape =
          Box
            {
              top_left = Vec2.v 0. (height -. 300.);
              bottom_right = Vec2.v (width -. (width /. 3.)) height;
            };
        params =
          {
            forces = Vec2.zero;
            drag_const = 0.;
            gravity = Vec2.v 300. (-3000.);
          };
      };

  add_area
    Area.
      {
        shape =
          Box
            {
              top_left = Vec2.v (width -. (width /. 3.)) (height -. 300.);
              bottom_right = Vec2.v width height;
            };
        params =
          {
            forces = Vec2.zero;
            drag_const = 0.;
            gravity = Vec2.v (-300.) (-3000.);
          };
      };

  (* a click adds a circle at rest at the click point; clientX/Y match canvas
     coordinates because the canvas fills the window from its top-left *)
  canvas##.onclick :=
    Dom_html.handler (fun ev ->
        let p = Vec2.v (Js.to_float ev##.clientX) (Js.to_float ev##.clientY) in
        let radius = 10. +. Random.float 20. in
        let inv_mass = 1. /. radius in
        (match
           A.add_circle arena ~position:p ~prior_position:p ~inv_mass ~radius
         with
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

  let collisions = Collision.PairwiseContacts.create max_circles in

  let rec loop acc last now =
    let acc = ref (acc +. Float.min ((now -. last) /. 1000.) max_dt) in
    while !acc >= dt do
      A.step arena dt;
      acc := !acc -. dt
    done;
    Utils.FrameCounter.incr frame_counter;
    ctx##clearRect (Js.float 0.) (Js.float 0.) (Js.float width)
      (Js.float height);

    let circles = A.circles arena in
    Collision.PairwiseContacts.detect circles ~target:collisions;
    Canvas.draw_areas ctx !areas;
    Canvas.draw ctx (circles);
    Canvas.draw_collisions ctx circles collisions;
    Canvas.draw_fps ctx !fps;

    request (loop !acc now)
  and request f =
    let callback = Js.wrap_callback (fun now -> f (Js.to_float now)) in
    ignore (Dom_html.window##requestAnimationFrame callback)
  in
  request (fun now -> loop 0. now now)
