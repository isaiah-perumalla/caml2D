open Caml2d

module A = World.Make (struct
  let top_left = Vec2.v 0. 0.
  let bottom_right = Vec2.v 100. 100.
  let gravity = Vec2.zero
end)

let add arena =
  let p = Vec2.v 10. 10. in
  A.add_circle arena ~position:p ~prior_position:p ~inv_mass:1. ~radius:5.

let () =
  (* add_circle fills the slots in turn, then reports a full arena with None
     instead of writing past the end of the buffers *)
  let arena = A.create ~max_circles:2 in
  assert (add arena = Some 0);
  assert (add arena = Some 1);
  assert (add arena = None);
  (* and keeps doing so *)
  assert (add arena = None)
