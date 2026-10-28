// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// Two frames of a test pattern, as ffmpeg wrote them:
//
//   ffmpeg -f lavfi -i testsrc2=size=32x32:rate=4 -t 0.5 -c:v libx264 \
//     -preset ultrafast -g 2 -pix_fmt yuv420p -b:v 20k -movflags +faststart one.mp4
//
// A real caller reads a file or a socket; this one carries the file with it so
// that the example runs anywhere.

///|
/// The movie to package.
let movie : String =
  #|AAAAIGZ0eXBpc29tAAACAGlzb21pc28yYXZjMW1wNDEAAAMqbW9vdgAAAGxtdmhkAAAAAAAA
  #|AAAAAAAAAAAD6AAAAfQAAQAAAQAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAA
  #|AAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAAAlR0cmFrAAAAXHRr
  #|aGQAAAADAAAAAAAAAAAAAAABAAAAAAAAAfQAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAA
  #|AAAAAAABAAAAAAAAAAAAAAAAAABAAAAAACAAAAAgAAAAAAAkZWR0cwAAABxlbHN0AAAAAAAA
  #|AAEAAAH0AAAAAAABAAAAAAHMbWRpYQAAACBtZGhkAAAAAAAAAAAAAAAAAABAAAAAIABVxAAA
  #|AAAALWhkbHIAAAAAAAAAAHZpZGUAAAAAAAAAAAAAAABWaWRlb0hhbmRsZXIAAAABd21pbmYA
  #|AAAUdm1oZAAAAAEAAAAAAAAAAAAAACRkaW5mAAAAHGRyZWYAAAAAAAAAAQAAAAx1cmwgAAAA
  #|AQAAATdzdGJsAAAAt3N0c2QAAAAAAAAAAQAAAKdhdmMxAAAAAAAAAAEAAAAAAAAAAAAAAAAA
  #|AAAAACAAIABIAAAASAAAAAAAAAABFUxhdmM2Mi4yOC4xMDEgbGlieDI2NAAAAAAAAAAAAAAA
  #|GP//AAAALWF2Y0MBQsAK/+EAFmdCwAraJbARAAADAAEAAAMACA8SJqABAARozjyAAAAAEHBh
  #|c3AAAAABAAAAAQAAABRidHJ0AAAAAAAAg5AAAIOQAAAAGHN0dHMAAAAAAAAAAQAAAAIAABAA
  #|AAAAFHN0c3MAAAAAAAAAAQAAAAEAAAAcc3RzYwAAAAAAAAABAAAAAQAAAAIAAAABAAAAHHN0
  #|c3oAAAAAAAAAAAAAAAIAAAegAAAAmQAAABRzdGNvAAAAAAAAAAEAAANaAAAAYnVkdGEAAABa
  #|bWV0YQAAAAAAAAAhaGRscgAAAAAAAAAAbWRpcmFwcGwAAAAAAAAAAAAAAAAtaWxzdAAAACWp
  #|dG9vAAAAHWRhdGEAAAABAAAAAExhdmY2Mi4xMi4xMDEAAAAIZnJlZQAACEFtZGF0AAACXwYF
  #|//9b3EXpvebZSLeWLNgg2SPu73gyNjQgLSBjb3JlIDE2NSByMzIyMyAwNDgwY2IwIC0gSC4y
  #|NjQvTVBFRy00IEFWQyBjb2RlYyAtIENvcHlsZWZ0IDIwMDMtMjAyNSAtIGh0dHA6Ly93d3cu
  #|dmlkZW9sYW4ub3JnL3gyNjQuaHRtbCAtIG9wdGlvbnM6IGNhYmFjPTAgcmVmPTEgZGVibG9j
  #|az0wOjA6MCBhbmFseXNlPTA6MCBtZT1kaWEgc3VibWU9MCBwc3k9MSBwc3lfcmQ9MS4wMDow
  #|LjAwIG1peGVkX3JlZj0wIG1lX3JhbmdlPTE2IGNocm9tYV9tZT0xIHRyZWxsaXM9MCA4eDhk
  #|Y3Q9MCBjcW09MCBkZWFkem9uZT0yMSwxMSBmYXN0X3Bza2lwPTEgY2hyb21hX3FwX29mZnNl
  #|dD0wIHRocmVhZHM9MSBsb29rYWhlYWRfdGhyZWFkcz0xIHNsaWNlZF90aHJlYWRzPTAgbnI9
  #|MCBkZWNpbWF0ZT0xIGludGVybGFjZWQ9MCBibHVyYXlfY29tcGF0PTAgY29uc3RyYWluZWRf
  #|aW50cmE9MCBiZnJhbWVzPTAgd2VpZ2h0cD0wIGtleWludD0yIGtleWludF9taW49MSBzY2Vu
  #|ZWN1dD0wIGludHJhX3JlZnJlc2g9MCByYz1hYnIgbWJ0cmVlPTAgYml0cmF0ZT0yMCByYXRl
  #|dG9sPTEuMCBxY29tcD0wLjYwIHFwbWluPTAgcXBtYXg9NjkgcXBzdGVwPTQgaXBfcmF0aW89
  #|MS40MCBhcT0wAIAAAAU5ZYiEBmgxgAIAAIEYAAgLcAAIFAAMAJwVj6BAA9+S69A3gAXwABQT
  #|AEACAIGFy4Hxs7G2oQAAQLwABCyMiAACBeAAIWTAAcAAQIAABAsAt8ALgStBcFLkZ2APpdf/
  #|hwABCPAAEdYyOAAIdIAAlxGdAABAXAAEBwFNAHQSLBFOGsmqYSyI//aAACAYAAIBgWqAuFaQ
  #|3FTE7ogvt7/8OAAIHIAAhnMUAAYAYAKF1QShLJhkIoMnq8OAAIHIAAhnMASDAAEIUBAB8OIZ
  #|NXtZZARJeJgfqAAIAMAFiyoJQlEwykUGX1eoAGAYAw6SA+B+7EpvDV6vSAACEiAHAAEBAA4E
  #|ixqJoGEi375IAAIOoBgACwFhekY3cFxuv3wIAARpgABHIAAEggAARDwgABAyAAET8AAQrAAB
  #|FaAAcAG4cDQXNwqmUWpyOKgFgJnDABCtDWg/4u/SuADcvqXAAAgLgACAMBQXWqdKSYCWPDsU
  #|1jQQAAgdeoATY8ApEGkDJXtP4AC8ADD+hgBon8ZaCa1ge4AEAUEGhQ1G66hrHQ12BvHHgAAQ
  #|GgABAVCxZEXOZSEAYK2CHNBQ4ADAAEG0oaBrMjhBTPFeH1wJoXwAcAAQUwA4AAgJgAyBSewD
  #|yKYMo/gAIAQR5ABPAIIAAl/jgACGMAAJPZkBYAIAQEAAwUDsA4i6bauAABAlAAEDIDiAAJgZ
  #|Hk0jB3ObSNh9NCAAAiFgYAAQdABQ3yCAACDYAAIt5kcAAQFAABBnMkAACIWAAIWAAAgOSwAk
  #|AAQEgABAWBLIBUOxXfDNoIqYNjK+0AACAAADAMAAkKGoKQUjkKYUgEP1eoAAQAOACxwH5SQy
  #|0dwBQC36vYAACGCAA4AAgbAAkGhobuxzAJ42hqNJ6AAAQQAABBfAAEBwACRGHQEsNQW6rAsA
  #|BgA4AKHQflJgLR2AFAQvV6gAGAEAGCYjfR7IhaD8Cd6vQAACCCAAIL4AAgOAATEBaAlhqEKq
  #|2AAAhDgBAABAJAKBo+qWkigRhtDU+HggABAoAAEk4AAQHgABRgCAAEBAAAQgRwBHQCIAgCQg
  #|DjvUoK5EKgOlNuAYSRLqICQmyUbuX4MxY4AAEFAAAQGAGgNCt0mdGoOHSxCwlPgAAQPwABAC
  #|BgFT0TxOakEPtXg3TxwABgg0ZNjHHVYXgkMqNjd+AABADDgBIZQAw6kjSbcAMW5rAwcAACBO
  #|AAIAYMBEgJ7+SkBTImyaWjgAAQPAABAdAeBoyOOehKUmehRrJAWcHAAEboAASWgABFiAAFWF
  #|MywABCRAAEdxiDgACEiAAI7jBYAAhIAACO6wWAAIOoAAjCMDgACEgAAI7rA4AAg6gACMIxBw
  #|ABCRAAEdxiDgACEiAAI7jA4AAhIAACO6wOAAIOoAAjCMDgACEgAAI7rA4AAg6gACMIwIAAIM
  #|IAAjORAABC4AAElGQAATAAEBAAAQQbhBAAEHgBrgcAAmAAICAAAgg3A5AAEHgBrhAAAgbAAC
  #|DSAAIRFwgQABC5AAEBu4HAAEDYAAQaQABCIuBxAAELkAAQG7gWcwAAQmQABSrAAEEEAAT90w
  #|QAAQwAABJrY8cAAQwAABJrY+WAAIQ4AAjdMQcAAQhwABG6YHAAEMAAASa2I4AAhgAACTWxg4
  #|AAhDgACN0xBwABCHAAEbpgQAAQFgABJiiAACBIAAI7cggACF0AAIWlwiAAITQAAg73A5AAEL
  #|oAAQtLgeAAITQAAg73CABAAEEkAAQO7hAABYAAQawABCIuBwBAAEEkAAQO7gcAAsAAINYAAh
  #|EXIAAACVQZogGK8PwOAgECGQB4ACADA4dYBieCyfg21fgCKJBgqza1BcDFY0OMmDYbag/8aD
  #|PwgABDJAAEK0ABYHQgABAMABO4AByFYQaQAAIM7TfFSQAAgzgAP7QfCAAEBghgABAYAwEDIX
  #|SFRqfDApBgAOAAICQAAgKgBAFh6zYjEY1B9FDojGIPgDcChPRnc7x5tGuXethkg=

///|
/// Cut a movie into segments a player can fetch, and write the playlists that
/// name them.
///
///     moon run src/examples/03-package
#coverage.skip
fn main raise {
  let bytes = @base64.decode(movie, ignore_whitespace=true)
  let file = @mp4.Mp4::parse(bytes[:])
  let tracks = file.tracks()
  println("tracks: " + tracks.length().to_string())
  for track in tracks {
    println(
      "  " +
      track.codec +
      " " +
      track.width.to_string() +
      "x" +
      track.height.to_string() +
      ", " +
      track.samples.length().to_string() +
      " samples",
    )
  }

  // One segment a second is what a player expects to be able to fetch whole.
  let packager = @moonmedia.Packager::new(file, target_duration=1.0)
  let init = packager.init_segment()
  println("initialisation: " + init.length().to_string() + " bytes")
  let segments = packager.segments()
  println("segments: " + segments.length().to_string())
  for i, segment in segments {
    println(
      "  segment" +
      i.to_string() +
      ".m4s " +
      segment.duration.to_string() +
      " s, " +
      segment.data.length().to_string() +
      " bytes, starts at " +
      segment.start.to_string() +
      " s",
    )
  }

  let playlist = packager.media_playlist()
  println("media playlist")
  println(playlist.encode())
  let master = packager.master_playlist()
  println("master playlist")
  println(master.encode())

  // The segments have to be fragments a player can fetch on their own: each
  // starts with its own movie fragment header.
  for segment in segments {
    let fragment = @mp4.Mp4::parse(segment.data[:])
    assert_eq(fragment.boxes[0].type_, "moof")
    assert_eq(fragment.boxes[1].type_, "mdat")
  }
  println("every segment is a fragment")
}
