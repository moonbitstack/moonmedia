// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A fragment with two samples, written out, read back, and walked.
///
///     moon run src/examples/02-boxes
#coverage.skip
fn main raise {
  let samples : Array[@mp4.SampleData] = [
    {
      data: Bytes::from_array([b'\x00', b'\x00', b'\x00', b'\x01', b'\x67']),
      duration: 1024L,
      composition_offset: 0L,
      sync: true,
    },
    {
      data: Bytes::from_array([b'\x00', b'\x00', b'\x00', b'\x01', b'\x41']),
      duration: 1024L,
      composition_offset: 512L,
      sync: false,
    },
  ]
  let fragment = @mp4.MovieFragment::new(1, [
    { track_id: 1, base_decode_time: 0L, samples, },
  ])
  let data = fragment.encode()
  println("fragment: " + data.length().to_string() + " bytes")

  let file = @mp4.Mp4::parse(data[:])
  println("boxes at the top")
  for box in file.boxes {
    println("  " + box.type_ + " (" + box.byte_length().to_string() + " bytes)")
    for child in box.boxes() {
      println(
        "    " +
        child.type_ +
        " (" +
        child.byte_length().to_string() +
        " bytes)",
      )
    }
  }

  let read = file.fragments()[0]
  println(
    "fragment " +
    read.sequence.to_string() +
    ", media from " +
    read.start.to_string() +
    " to " +
    read.end.to_string(),
  )
  for run in read.runs {
    println(
      "  track " +
      run.track_id.to_string() +
      ", decode time " +
      run.base_decode_time.to_string(),
    )
    for sample in run.samples {
      println(
        "    " +
        sample.size.to_string() +
        " bytes at " +
        sample.offset.to_string() +
        ", " +
        sample.duration.to_string() +
        " ticks, key frame: " +
        sample.sync.to_string(),
      )
    }
  }

  // Reading and writing again gives the same bytes: a box this package has no
  // name for is kept as it was, and so is everything else.
  println("round trip: " + (file.encode() == data).to_string())

  // The bytes a sample points at are the bytes that went in.
  let first = read.runs[0].samples[0]
  println(
    "first sample: " +
    @utf8.decode_lossy(data[first.offset:first.offset + first.size]).to_string(),
  )
}
