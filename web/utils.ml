
module FrameCounter = struct
  type t = { mutable frames: int }

  let make initial_frames =
    { frames = initial_frames; }

  let incr fc = fc.frames <- fc.frames + 1

  let reset fc =
    let count = fc.frames in
    fc.frames <- 0;
    count
end