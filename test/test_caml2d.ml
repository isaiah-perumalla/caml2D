open Caml2d

let () =
  let a = Vec2.v 3. 4. in
  assert (Vec2.length a = 5.);
  assert (Vec2.add a (Vec2.v 1. 1.) = Vec2.v 4. 5.);
  assert (Vec2.sub a a = Vec2.zero);
  assert (Vec2.scale 2. a = Vec2.v 6. 8.);
  assert (Vec2.dot a a = 25.)
