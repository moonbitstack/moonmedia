// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The samples below were produced by ffmpeg from a generated test pattern and
// a sine wave, then cut down to two frames so that they can live in the
// repository:
//
//   ffmpeg -f lavfi -i testsrc2=size=32x32:rate=8 -f lavfi -i sine=frequency=440:sample_rate=8000 \
//     -t 0.25 -c:v libx264 -preset ultrafast -g 2 -pix_fmt yuv420p -b:v 40k \
//     -c:a aac -b:a 8k -ac 1 -movflags +faststart small.mp4
//   ffmpeg ... -movflags frag_keyframe+empty_moov small_frag.mp4
//
// scripts/make-vectors.sh regenerates them.

///|
/// A two frame movie in one file, with its sample table up front.
let progressive : String =
  #|AAAAIGZ0eXBpc29tAAACAGlzb21pc28yYXZjMW1wNDEAAAV7bW9vdgAAAGxtdmhkAAAAAAAA
  #|AAAAAAAAAAAD6AAAAPoAAQAAAQAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAA
  #|AAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAwAAAlh0cmFrAAAAXHRr
  #|aGQAAAADAAAAAAAAAAAAAAABAAAAAAAAAPoAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAA
  #|AAAAAAABAAAAAAAAAAAAAAAAAABAAAAAACAAAAAgAAAAAAAkZWR0cwAAABxlbHN0AAAAAAAA
  #|AAEAAAD6AAAAAAABAAAAAAHQbWRpYQAAACBtZGhkAAAAAAAAAAAAAAAAAABAAAAAEABVxAAA
  #|AAAALWhkbHIAAAAAAAAAAHZpZGUAAAAAAAAAAAAAAABWaWRlb0hhbmRsZXIAAAABe21pbmYA
  #|AAAUdm1oZAAAAAEAAAAAAAAAAAAAACRkaW5mAAAAHGRyZWYAAAAAAAAAAQAAAAx1cmwgAAAA
  #|AQAAATtzdGJsAAAAt3N0c2QAAAAAAAAAAQAAAKdhdmMxAAAAAAAAAAEAAAAAAAAAAAAAAAAA
  #|AAAAACAAIABIAAAASAAAAAAAAAABFUxhdmM2Mi4yOC4xMDEgbGlieDI2NAAAAAAAAAAAAAAA
  #|GP//AAAALWF2Y0MBQtAL/+EAFmdC0AvaJbARAAADAAEAAAMAEA8SJqABAARozjyAAAAAEHBh
  #|c3AAAAABAAAAAQAAABRidHJ0AAAAAAAA7YAAAO2AAAAAGHN0dHMAAAAAAAAAAQAAAAIAAAgA
  #|AAAAFHN0c3MAAAAAAAAAAQAAAAEAAAAcc3RzYwAAAAAAAAABAAAAAQAAAAEAAAABAAAAHHN0
  #|c3oAAAAAAAAAAAAAAAIAAAdaAAAAEgAAABhzdGNvAAAAAAAAAAIAAAaaAAAOygAAAk10cmFr
  #|AAAAXHRraGQAAAADAAAAAAAAAAAAAAACAAAAAAAAAPoAAAAAAAAAAAAAAAEBAAAAAAEAAAAA
  #|AAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAkZWR0cwAAABxlbHN0
  #|AAAAAAAAAAEAAAD6AAAEAAABAAAAAAHFbWRpYQAAACBtZGhkAAAAAAAAAAAAAAAAAAAfQAAA
  #|C9BVxAAAAAAALWhkbHIAAAAAAAAAAHNvdW4AAAAAAAAAAAAAAABTb3VuZEhhbmRsZXIAAAAB
  #|cG1pbmYAAAAQc21oZAAAAAAAAAAAAAAAJGRpbmYAAAAcZHJlZgAAAAAAAAABAAAADHVybCAA
  #|AAABAAABNHN0YmwAAAB+c3RzZAAAAAAAAAABAAAAbm1wNGEAAAAAAAAAAQAAAAAAAAAAAAEA
  #|EAAAAAAfQAAAAAAANmVzZHMAAAAAA4CAgCUAAgAEgICAF0AVAAAAAAAwCAAAMAgFgICABRWI
  #|VuUABoCAgAECAAAAFGJ0cnQAAAAAAAAwCAAAMAgAAAAgc3R0cwAAAAAAAAACAAAAAgAABAAA
  #|AAABAAAD0AAAABxzdHNjAAAAAAAAAAEAAAABAAAAAQAAAAEAAAAgc3RzegAAAAAAAAAAAAAA
  #|AwAAAO8AAADWAAAAgAAAABxzdGNvAAAAAAAAAAMAAAWrAAAN9AAADtwAAAAac2dwZAEAAABy
  #|b2xsAAAAAgAAAAH//wAAABxzYmdwAAAAAHJvbGwAAAABAAAAAwAAAAEAAABidWR0YQAAAFpt
  #|ZXRhAAAAAAAAACFoZGxyAAAAAAAAAABtZGlyYXBwbAAAAAAAAAAAAAAAAC1pbHN0AAAAJal0
  #|b28AAAAdZGF0YQAAAAEAAAAATGF2ZjYyLjEyLjEwMQAAAAhmcmVlAAAJuW1kYXTeAgBMYXZj
  #|NjIuMjguMTAxAAI4pVLTRu6z9o+3xJV3LRIkSJEkg2radq2natp2rjO1cZ2raZ6dsU7YrDtW
  #|07VxnauM5VlOVbTlW02LE47E5VlIQIQIQIRJRkoyqMqlMlaU11yuru3MDdilAlAwMDAwMbNy
  #|yyyyyym5ZZZZZZTcssssssssssssssssssssssssssssssssssssssssssssssssssssssss
  #|ssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssss
  #|ssssssssssssssssssssvAAAAl8GBf//W9xF6b3m2Ui3lizYINkj7u94MjY0IC0gY29yZSAx
  #|NjUgcjMyMjMgMDQ4MGNiMCAtIEguMjY0L01QRUctNCBBVkMgY29kZWMgLSBDb3B5bGVmdCAy
  #|MDAzLTIwMjUgLSBodHRwOi8vd3d3LnZpZGVvbGFuLm9yZy94MjY0Lmh0bWwgLSBvcHRpb25z
  #|OiBjYWJhYz0wIHJlZj0xIGRlYmxvY2s9MDowOjAgYW5hbHlzZT0wOjAgbWU9ZGlhIHN1Ym1l
  #|PTAgcHN5PTEgcHN5X3JkPTEuMDA6MC4wMCBtaXhlZF9yZWY9MCBtZV9yYW5nZT0xNiBjaHJv
  #|bWFfbWU9MSB0cmVsbGlzPTAgOHg4ZGN0PTAgY3FtPTAgZGVhZHpvbmU9MjEsMTEgZmFzdF9w
  #|c2tpcD0xIGNocm9tYV9xcF9vZmZzZXQ9MCB0aHJlYWRzPTEgbG9va2FoZWFkX3RocmVhZHM9
  #|MSBzbGljZWRfdGhyZWFkcz0wIG5yPTAgZGVjaW1hdGU9MSBpbnRlcmxhY2VkPTAgYmx1cmF5
  #|X2NvbXBhdD0wIGNvbnN0cmFpbmVkX2ludHJhPTAgYmZyYW1lcz0wIHdlaWdodHA9MCBrZXlp
  #|bnQ9MiBrZXlpbnRfbWluPTEgc2NlbmVjdXQ9MCBpbnRyYV9yZWZyZXNoPTAgcmM9YWJyIG1i
  #|dHJlZT0wIGJpdHJhdGU9NDAgcmF0ZXRvbD0xLjAgcWNvbXA9MC42MCBxcG1pbj0wIHFwbWF4
  #|PTY5IHFwc3RlcD00IGlwX3JhdGlvPTEuNDAgYXE9MACAAAAE82WIhAXoMYACAACAqAAIAmAA
  #|CAIAIA1CYUw2At63tgC+AOYAAkygCAEBBjroLnh4bahAABAdAAEH4yIAAIDoAAg/MABwABAS
  #|AAEBQPZAJhyoPRizENMHd7f/hwABBpAAEWAyOAAIV4AAkYGdAABALAAEAgIUA+ECIzkrC3oI
  #|nsz/9oAAIAQABBaIOi3wrOVpd6G1Xf/hwABAlAAEJJigAYBACDZAC4F7cQGcKnq8OAAIEoAA
  #|hJMASMAAQWQYB8bQ21Kwu4MUe0lP1AAgCAEmiAFwLm4gs4VfV6gBgYDCbQLgtXGxXGb1ekAA
  #|EGsAoACgPCZEwN4IrPfvkgAAgpgYAEg4buOz0AwVr98CAAEUQAARWgABF+AAEKEIAAQHgABD
  #|tAAEG4AAQ2gAHAGo4JCZKLJU1SWCT+FgUOGARygKYA1Yky6cAAZHaBwAAIBYACBwujQ4Ttg5
  #|iwaU1E0IAAQHtQAmhQGohpAuUaj+AAvAGLvIA8uwEMDDTh7gBAUcQMBE9KWpIoCWkeT3wAAI
  #|BgAAgBizTQ4rlYgLESxBlhE4AYAAgjuPACvisIRyzTB02PYXwAcAAQOwCgANAEQ9KYCCZQsi
  #|SAEwSRBAO4FMAARiRwABCSAAEeEyAsBAYcAIOBCB1NZtq4AAEBUAAQGgU0AdBITyGbtZNUTw
  #|UyEgAAIY4IAAIIACRHkEAAEEwAARDzI4AAgEAACCGZIAAEMcAAQfAACpYASAAIAwAAgCD0wL
  #|jkzsBAvM/w8J7DQABABgAkUJwjCMTDKLAL/q9QAEAKAeeAGRh1eCeAnC76vYAACEeAHAAEBA
  #|A4MCEraiaBdPo0EM9AAAIFQAAgegAEADDUcB3GgXarAsAMAUA4+AMjBKeCcAnFj1eoAMBgGF
  #|wTEIhszwPQRPV6AAAQKwABA9AAIAGSocB3GgsVWwAAEGEBgANAsMGFAvs4cD6NDAeCAAEBgA
  #|ARwgADgABM8CAAEAYAAQVxAFdAmBgaJBhrnTENmdAxTW4GJJp7QAQHvLd/VwMnbgAAQOAABA
  #|EB4EDU6qUGQCzRUgWXPgAAQKwAIFB8pMZE5ABTopwapO4AGEPBoSf24onoQEHtbXeAAMcB4z
  #|wFWlqwkewFbIpghcAACAuABQofZN683INYkuLMwcAACBQAAIBIEgkQEmuheMlGZNpeAs4OAA
  #|IqgAAjlAACH4AAKAqZlgACDWAAIsjEHAAEGsAARZGCwABBqAAEWVgsAAQUwABEgYHAAEGoAA
  #|RZWBwABBTAAESBiDgACDWAAIsjEHAAEGsAARZGBwABBqAAEWVgcAAQUwABEgYHAAEGoAARZW
  #|BwABBTAAESBgQAAQQwABE4iAACEIAAI4sgAEAAQAgABAVuEEAAQVgJcDgAgACAEAAICtwOQA
  #|BBWAlwgAAQIAABBDAAEFC4QCAAINoBNwOAAIEAAAghgACChcDggACDaATcCzmAACDiAAJzoA
  #|AgMgACXSmCAACEcAAI6bHjgACEcAAI6bHywABBhAAEUpiDgACDCAAIpTA4AAhHAACOmxHAAE
  #|I4AAR02MHAAEGEAARSmIOAAIMIAAilMCAACAMAAI6kQAAQEgABFpkEAAQigABB+uEgABByAA
  #|EFO4HIAAhFAACD9cKAACDkAAIKdwgQABBHAAEFG4QAAQAAEEcAAQTrgcQABBHAAEFG4HAAIA
  #|ACCOAAIJ1yABAJzZOR1EuhlEvBVkvn2+f/4v/P9euONatJ/0/T/8P/P8eeOtXd1n/T8/+n/z
  #|9dcca1Zr/0/P/p/9/rjjjjUvFl0UgcBl0ck4mmZsMVzTTL2NjZHZs2RLHIfrwXYIHCUYTrOd
  #|FVRjGoNHRRHQboHUKDdBp1UUHEatiIs2EfLct2ydC6Nr7GyKLYUvyJHBWXMs52I885znUpUa
  #|lKnnnnnnVOqdU6p5551KnnVPOqeeedU6th55556CgupQic1hSJ3D8FOdUPNPzKnn5p/l8quY
  #|ifqOhSAOAAAADkGaIBalxHjrRrWhUACHAQ6dtL4TZH4Pw5/P/4f+f48661qR/H/7b/P486vi
  #|7uQfL5fLZsynO+00siKGGLm4xcw+QiL5D5RRRfKfjx4xfKb5fL5cdh4p+PFERToAyxRKqiCl
  #|BUF6lApJtLr7M4BrP2MhsLn5k4hp/MOH7Bp/MOH4aQPy4fhpAPyt+FfyADg=

///|
/// The same two frames, written as an initialisation section and a fragment.
let fragmented : String =
  #|AAAAJGZ0eXBpc29tAAACAGlzb21pc282aXNvMmF2YzFtcDQxAAAE2W1vb3YAAABsbXZoZAAA
  #|AAAAAAAAAAAAAAAAA+gAAAAAAAEAAAEAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAQAA
  #|AAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIAAAH8dHJhawAA
  #|AFx0a2hkAAAAAwAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAAAAAAA
  #|AAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAQAAAAAAgAAAAIAAAAAABmG1kaWEAAAAgbWRoZAAA
  #|AAAAAAAAAAAAAAAAQAAAAAAAVcQAAAAAAC1oZGxyAAAAAAAAAAB2aWRlAAAAAAAAAAAAAAAA
  #|VmlkZW9IYW5kbGVyAAAAAUNtaW5mAAAAFHZtaGQAAAABAAAAAAAAAAAAAAAkZGluZgAAABxk
  #|cmVmAAAAAAAAAAEAAAAMdXJsIAAAAAEAAAEDc3RibAAAALdzdHNkAAAAAAAAAAEAAACnYXZj
  #|MQAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAgACAASAAAAEgAAAAAAAAAARVMYXZjNjIuMjgu
  #|MTAxIGxpYngyNjQAAAAAAAAAAAAAABj//wAAAC1hdmNDAULQC//hABZnQtAL2iWwEQAAAwAB
  #|AAADABAPEiagAQAEaM48gAAAABBwYXNwAAAAAQAAAAEAAAAUYnRydAAAAAAAAJxAAACcQAAA
  #|ABBzdHRzAAAAAAAAAAAAAAAQc3RzYwAAAAAAAAAAAAAAFHN0c3oAAAAAAAAAAAAAAAAAAAAQ
  #|c3RjbwAAAAAAAAAAAAABv3RyYWsAAABcdGtoZAAAAAMAAAAAAAAAAAAAAAIAAAAAAAAAAAAA
  #|AAAAAAAAAAAAAQEAAAAAAQAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAEAAAAAAAAAA
  #|AAAAAAAAAVttZGlhAAAAIG1kaGQAAAAAAAAAAAAAAAAAAB9AAAAAAFXEAAAAAAAtaGRscgAA
  #|AAAAAAAAc291bgAAAAAAAAAAAAAAAFNvdW5kSGFuZGxlcgAAAAEGbWluZgAAABBzbWhkAAAA
  #|AAAAAAAAAAAkZGluZgAAABxkcmVmAAAAAAAAAAEAAAAMdXJsIAAAAAEAAADKc3RibAAAAH5z
  #|dHNkAAAAAAAAAAEAAABubXA0YQAAAAAAAAABAAAAAAAAAAAAAQAQAAAAAB9AAAAAAAA2ZXNk
  #|cwAAAAADgICAJQACAASAgIAXQBUAAAAAAB9AAAAfQAWAgIAFFYhW5QAGgICAAQIAAAAUYnRy
  #|dAAAAAAAAB9AAAAfQAAAABBzdHRzAAAAAAAAAAAAAAAQc3RzYwAAAAAAAAAAAAAAFHN0c3oA
  #|AAAAAAAAAAAAAAAAAAAQc3RjbwAAAAAAAAAAAAAASG12ZXgAAAAgdHJleAAAAAAAAAABAAAA
  #|AQAAAAAAAAAAAAAAAAAAACB0cmV4AAAAAAAAAAIAAAABAAAAAAAAAAAAAAAAAAAAYnVkdGEA
  #|AABabWV0YQAAAAAAAAAhaGRscgAAAAAAAAAAbWRpcmFwcGwAAAAAAAAAAAAAAAAtaWxzdAAA
  #|ACWpdG9vAAAAHWRhdGEAAAABAAAAAExhdmY2Mi4xMi4xMDEAAADsbW9vZgAAABBtZmhkAAAA
  #|AAAAAAEAAABodHJhZgAAACR0ZmhkAAAAOQAAAAEAAAAAAAAE/QAAEDIAAAdaAQEAAAAAABR0
  #|ZmR0AQAAAAAAAAAAAAAAAAAAKHRydW4AAAMFAAAAAgAAAPQCAAAAAAAQMgAAB1oAAAgAAAAA
  #|EgAAAGx0cmFmAAAAJHRmaGQAAAA5AAAAAgAAAAAAAAT9AAAEAAAAAO8CAAAAAAAAFHRmZHQB
  #|AAAAAAAAAAAAAAAAAAAsdHJ1bgAAAwEAAAADAAAIYAAABAAAAADvAAAEAAAAANYAAAPQAAAA
  #|gAAACbltZGF0AAACXwYF//9b3EXpvebZSLeWLNgg2SPu73gyNjQgLSBjb3JlIDE2NSByMzIy
  #|MyAwNDgwY2IwIC0gSC4yNjQvTVBFRy00IEFWQyBjb2RlYyAtIENvcHlsZWZ0IDIwMDMtMjAy
  #|NSAtIGh0dHA6Ly93d3cudmlkZW9sYW4ub3JnL3gyNjQuaHRtbCAtIG9wdGlvbnM6IGNhYmFj
  #|PTAgcmVmPTEgZGVibG9jaz0wOjA6MCBhbmFseXNlPTA6MCBtZT1kaWEgc3VibWU9MCBwc3k9
  #|MSBwc3lfcmQ9MS4wMDowLjAwIG1peGVkX3JlZj0wIG1lX3JhbmdlPTE2IGNocm9tYV9tZT0x
  #|IHRyZWxsaXM9MCA4eDhkY3Q9MCBjcW09MCBkZWFkem9uZT0yMSwxMSBmYXN0X3Bza2lwPTEg
  #|Y2hyb21hX3FwX29mZnNldD0wIHRocmVhZHM9MSBsb29rYWhlYWRfdGhyZWFkcz0xIHNsaWNl
  #|ZF90aHJlYWRzPTAgbnI9MCBkZWNpbWF0ZT0xIGludGVybGFjZWQ9MCBibHVyYXlfY29tcGF0
  #|PTAgY29uc3RyYWluZWRfaW50cmE9MCBiZnJhbWVzPTAgd2VpZ2h0cD0wIGtleWludD0yIGtl
  #|eWludF9taW49MSBzY2VuZWN1dD0wIGludHJhX3JlZnJlc2g9MCByYz1hYnIgbWJ0cmVlPTAg
  #|Yml0cmF0ZT00MCByYXRldG9sPTEuMCBxY29tcD0wLjYwIHFwbWluPTAgcXBtYXg9NjkgcXBz
  #|dGVwPTQgaXBfcmF0aW89MS40MCBhcT0wAIAAAATzZYiEBegxgAIAAICoAAgCYAAIAgAgDUJh
  #|TDYC3re2AL4A5gACTKAIAQEGOugueHhtqEAAEB0AAQfjIgAAgOgACD8wAHAAEBIAAQFA9kAm
  #|HKg9GLMQ0wd3t/+HAAEGkAARYDI4AAhXgACRgZ0AAEAsAAQCAhQD4QIjOSsLegiezP/2gAAg
  #|BAAEFog6LfCs5Wl3obVd/+HAAECUAAQkmKABgEAINkALgXtxAZwqerw4AAgSgACEkwBIwABB
  #|ZBgHxtDbUrC7gxR7SU/UACAIASaIAXAubiCzhV9XqAGBgMJtAuC1cbFcZvV6QAAQawCgAKA8
  #|JkTA3gis9++SAACCmBgASDhu47PQDBWv3wIAARRAABFaAAEX4AAQoQgABAeAAEO0AAQbgABD
  #|aAAcAajgkJkoslTVJYJP4WBQ4YBHKApgDViTLpwABkdoHAAAgFgAIHC6NDhO2DmLBpTUTQgA
  #|BAe1ACaFAaiGkC5RqP4AC8AYu8gDy7AQwMNOHuAEBRxAwET0pakigJaR5PfAAAgGAACAGLNN
  #|DiuViAsRLEGWETgBgACCO48AK+KwhHLNMHTY9hfABwABA7AKAA0ARD0pgIJlCyJIATBJEEA7
  #|gUwABGJHAAEJIAAR4TICwEBhwAg4EIHU1m2rgAAQFQABAaBTQB0EhPIZu1k1RPBTISAAAhjg
  #|gAAggAJEeQQAAQTAABEPMjgACAQAAIIZkgAAQxwABB8AAKlgBIAAgDAACAIPTAuOTOwEC8z/
  #|DwnsNAAEAGACRQnCMIxMMosAv+r1AAQAoB54AZGHV4J4CcLvq9gAAIR4AcAAQEADgwIStqJo
  #|F0+jQQz0AAAgVAACB6AAQAMNRwHcaBdqsCwAwBQDj4AyMEp4JwCcWPV6gAwGAYXBMQiGzPA9
  #|BE9XoAABArAAED0AAgAZKhwHcaCxVbAAAQYQGAA0CwwYUC+zhwPo0MB4IAAQGAABHCAAOAAE
  #|zwIAAQBgABBXEAV0CYGBokGGudMQ2Z0DFNbgYkmntABAe8t39XAyduAABA4AAEAQHgQNTqpQ
  #|ZALNFSBZc+AABArAAgUHykxkTkAFOinBqk7gAYQ8GhJ/biiehAQe1td4AAxwHjPAVaWrCR7A
  #|VsimCFwAAIC4AFCh9k3rzcg1iS4szBwAAIFAAAgEgSCRASa6F4yUZk2l4Czg4AAiqAACOUAA
  #|IfgAAoCpmWAAINYAAiyMQcAAQawABFkYLAAEGoAARZWCwABBTAAESBgcAAQagABFlYHAAEFM
  #|AARIGIOAAINYAAiyMQcAAQawABFkYHAAEGoAARZWBwABBTAAESBgcAAQagABFlYHAAEFMAAR
  #|IGBAABBDAAETiIAAIQgAAjiyAAQABACAAEBW4QQABBWAlwOACAAIAQAAgK3A5AAEFYCXCAAB
  #|AgAAEEMAAQULhAIAAg2gE3A4AAgQAACCGAAIKFwOCAAINoBNwLOYAAIOIAAnOgACAyAAJdKY
  #|IAAIRwAAjpseOAAIRwAAjpsfLAAEGEAARSmIOAAIMIAAilMDgACEcAAI6bEcAAQjgABHTYwc
  #|AAQYQABFKYg4AAgwgACKUwIAAIAwAAjqRAABASAAEWmQQABCKAAEH64SAAEHIAAQU7gcgACE
  #|UAAIP1woAAIOQAAgp3CBAAEEcAAQUbhAABAAAQRwABBOuBxAAEEcAAQUbgcAAgAAII4AAgnX
  #|IAAAAA5BmiAWpcR460a1oVAAh94CAExhdmM2Mi4yOC4xMDEAAjilUtNG7rP2j7fElXctEiRI
  #|kSSDatp2radq2nauM7Vxnatpnp2xTtisO1bTtXGdq4zlWU5VtOVbTYsTjsTlWUhAhAhAhElG
  #|SjKoyqUyVpTXXK6u7cwN2KUCUDAwMDAxs3LLLLLLKblllllllNyyyyyyyyyyyyyyyyyyyyyy
  #|yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy
  #|yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy8AQCc2TkdRLoZRLwV
  #|ZL59vn/+L/z/XrjjWrSf9P0//D/z/HnjrV3dZ/0/P/p/8/XXHGtWa/9Pz/6f/f644441LxZd
  #|FIHAZdHJOJpmbDFc00y9jY2R2bNkSxyH68F2CBwlGE6znRVUYxqDR0UR0G6B1Cg3QadVFBxG
  #|rYiLNhHy3LdsnQuja+xsii2FL8iRwVlzLOdiPPOc51KVGpSp555551TqnVOqeeedSp51Tzqn
  #|nnnVOrYeeeeegoLqUInNYUidw/BTnVDzT8yp5+af5fKrmIn6joUgDgEOnbS+E2R+D8Ofz/+H
  #|/n+POutakfx/+2/z+POr4u7kHy+Xy2bMpzvtNLIihhi5uMXMPkIi+Q+UUUXyn48eMXym+Xy+
  #|XHYeKfjxREU6AMsUSqogpQVBepQKSbS6+zOAaz9jIbC5+ZOIafzDh+wafzDh+GkD8uH4aQD8
  #|rfhX8gA4AAAAbm1mcmEAAAArdGZyYQEAAAAAAAABAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAT9
  #|AQEBAAAAK3RmcmEBAAAAAAAAAgAAAAAAAAABAAAAAAAAAAAAAAAAAAAE/QEBAQAAABBtZnJv
  #|AAAAAAAAAG4=

///|
fn bytes_of(text : String) -> Bytes {
  @base64.decode(text, ignore_whitespace=true) catch {
    _ => Bytes::new(0)
  }
}

///|
test "a plain file is written back byte for byte" {
  let data = bytes_of(progressive)
  let file = @mp4.Mp4::parse(data[:])
  assert_eq(file.boxes.map(fn(b) { b.type_ }), ["ftyp", "moov", "free", "mdat"])
  assert_eq(file.encode(), data)
  assert_eq(file.is_fragmented(), false)
}

///|
test "the sample table describes both tracks" {
  let file = @mp4.Mp4::parse(bytes_of(progressive)[:])
  let tracks = file.tracks()
  assert_eq(tracks.length(), 2)
  let video = tracks[0]
  assert_eq(video.kind, @mp4.TrackKind::Video)
  assert_eq(video.codec, "avc1.42d00b")
  assert_eq(video.width, 32)
  assert_eq(video.height, 32)
  assert_eq(video.samples.length(), 2)
  // Every frame is a key frame in a stream cut every second frame.
  assert_eq(video.samples[0].sync, true)
  assert_eq(video.samples[0].dts, 0L)
  assert_eq(video.samples[0].duration, 2048L)
  assert_eq(video.samples[1].dts, 2048L)
  let audio = tracks[1]
  assert_eq(audio.kind, @mp4.TrackKind::Audio)
  assert_eq(audio.codec, "mp4a.40.2")
  assert_eq(audio.sample_rate, 8000)
  assert_eq(audio.channels, 1)
  assert_eq(audio.samples.length(), 3)
  // Chunks of different tracks are interleaved, so samples of one track are not
  // adjacent; what has to hold is that they run forward and stay in the file.
  let mut previous = 0
  for sample in audio.samples {
    assert_true(sample.offset > previous)
    assert_true(sample.offset + sample.size <= file.data.length())
    previous = sample.offset
  }
}

///|
test "a fragmented file is written back byte for byte" {
  let data = bytes_of(fragmented)
  let file = @mp4.Mp4::parse(data[:])
  assert_eq(file.encode(), data)
  assert_eq(file.is_fragmented(), true)
  let fragments = file.fragments()
  assert_eq(fragments.length(), 1)
  assert_eq(fragments[0].sequence, 1)
  assert_eq(fragments[0].runs.length(), 2)
  assert_eq(fragments[0].runs[0].samples.length(), 2)
  // The fragment runs to the end of the file, media data included.
  assert_eq(fragments[0].end, data.length())
}

///|
test "a fragmented file still lists its samples" {
  let file = @mp4.Mp4::parse(bytes_of(fragmented)[:])
  let tracks = file.tracks()
  assert_eq(tracks.length(), 2)
  assert_eq(tracks[0].samples.length(), 2)
  assert_eq(tracks[0].samples[0].dts, 0L)
  assert_eq(tracks[1].samples.length(), 3)
  // The two files carry the same frames, and a frame is the same bytes either
  // way: the offsets differ, the data does not.
  let plain = @mp4.Mp4::parse(bytes_of(progressive)[:])
  let plain_video = plain.tracks()[0].samples
  let frag_video = tracks[0].samples
  for i = 0; i < frag_video.length(); i = i + 1 {
    let a = frag_video[i]
    let b = plain_video[i]
    assert_eq(
      file.data[a.offset:a.offset + a.size],
      plain.data[b.offset:b.offset + b.size],
    )
  }
}

///|
test "an initialisation section describes the codec and holds no frames" {
  let file = @mp4.Mp4::parse(bytes_of(progressive)[:])
  let init = file.init_section()
  let init_file = @mp4.Mp4::parse(init[:])
  assert_eq(init_file.boxes.map(fn(b) { b.type_ }), ["ftyp", "moov"])
  let moov = init_file.movie().unwrap()
  assert_eq(moov.child("mvex") != None, true)
  let trak = moov.children_of("trak")[0]
  let stbl = trak
    .child("mdia")
    .unwrap()
    .child("minf")
    .unwrap()
    .child("stbl")
    .unwrap()
  // The sample description stays, the tables that place samples go.
  assert_eq(stbl.boxes().map(fn(b) { b.type_ }), ["stsd"])
  // And what is left still names the codec.
  let tracks = init_file.tracks()
  assert_eq(tracks[0].codec, "avc1.42d00b")
  assert_eq(tracks[0].samples.length(), 0)
}

///|
test "a fragment built here reads back as the samples that went in" {
  let samples : Array[@mp4.SampleData] = [
    {
      data: Bytes::from_array([b'\x00', b'\x01', b'\x02']),
      duration: 100L,
      composition_offset: 0L,
      sync: true,
    },
    {
      data: Bytes::from_array([b'\x03', b'\x04']),
      duration: 100L,
      composition_offset: 20L,
      sync: false,
    },
  ]
  let fragment = @mp4.MovieFragment::new(7, [
    { track_id: 3, base_decode_time: 1000L, samples, },
  ])
  let data = fragment.encode()
  let file = @mp4.Mp4::parse(data[:])
  assert_eq(file.boxes.map(fn(b) { b.type_ }), ["moof", "mdat"])
  let fragments = file.fragments()
  assert_eq(fragments[0].sequence, 7)
  let run = fragments[0].runs[0]
  assert_eq(run.track_id, 3)
  assert_eq(run.base_decode_time, 1000L)
  assert_eq(run.samples.length(), 2)
  assert_eq(run.samples[0].dts, 1000L)
  assert_eq(run.samples[0].size, 3)
  assert_eq(run.samples[0].sync, true)
  assert_eq(run.samples[1].dts, 1100L)
  assert_eq(run.samples[1].duration, 100L)
  assert_eq(run.samples[1].composition_offset, 20L)
  assert_eq(run.samples[1].sync, false)
  // The data a run points at is the data it was given.
  let at = run.samples[0].offset
  assert_eq(data[at:at + 3], Bytes::from_array([b'\x00', b'\x01', b'\x02']))
}

///|
test "a box nobody named keeps its payload and its size form" {
  let odd = @mp4.Box::bytes(
    "odd!",
    Bytes::from_array([b'\x01', b'\x02', b'\x03']),
  )
  let big = { ..odd, type_: "big!", large: true, }
  let tree = [@mp4.Box::children("moov", [odd, big])]
  let data = @mp4.encode(tree)
  let back = @mp4.parse(data[:])
  assert_eq(back, tree)
  assert_eq(back[0].boxes()[1].large, true)
  // The 64-bit form starts with a size field of one, followed by the real size.
  let first = tree[0].boxes()[0].byte_length()
  assert_eq(
    data[8 + first:12 + first],
    Bytes::from_array([b'\x00', b'\x00', b'\x00', b'\x01']),
  )
}

///|
test "a segment index reads and writes the references it carries" {
  let index : @mp4.SegmentIndex = {
    reference_id: 1,
    timescale: 1000L,
    earliest_presentation_time: 0L,
    first_offset: 0L,
    references: [
      {
        reference_type: false,
        referenced_size: 12_345L,
        subsegment_duration: 4000L,
        starts_with_sap: true,
        sap_type: 1,
        sap_delta_time: 0L,
      },
      {
        reference_type: false,
        referenced_size: 6789L,
        subsegment_duration: 4000L,
        starts_with_sap: false,
        sap_type: 0,
        sap_delta_time: 0L,
      },
    ],
  }
  let box = @mp4.parse(index.encode()[:])[0]
  assert_eq(box.type_, "sidx")
  let back = @mp4.segment_index(box)
  assert_eq(back, index)
  // The box a player reads says how long the whole run of references lasts.
  assert_eq(back.references[0].subsegment_duration, 4000L)
  assert_eq(back.references[0].referenced_size, 12_345L)
  assert_eq(back.references[1].referenced_size, 6789L)
  assert_eq(back.references[0].starts_with_sap, true)
  assert_eq(back.references[1].starts_with_sap, false)
}

///|
test "panic: a box that ends past the file is refused" {
  // A movie header claiming more bytes than the file holds.
  let data = Bytes::from_array([
    b'\x00', b'\x00', b'\x00', b'\x40', b'm', b'o', b'o', b'v',
  ])
  @mp4.parse(data[:]) |> ignore
}

///|
test "panic: a box smaller than its own header is refused" {
  let data = Bytes::from_array([
    b'\x00', b'\x00', b'\x00', b'\x02', b'f', b't', b'y', b'p',
  ])
  @mp4.parse(data[:]) |> ignore
}

///|
test "panic: trailing bytes that are not a box are refused" {
  let data = Bytes::from_array([
    b'\x00', b'\x00', b'\x00', b'\x08', b'f', b'r', b'e', b'e', b'\x00',
  ])
  @mp4.parse(data[:]) |> ignore
}
