# moonmedia

Segmented streaming is three questions: what the bytes are wrapped in, what
tells a player which pieces exist, and how the stream got here in the first
place.

> **Status: planned.** The repository is set up; nothing is
> implemented yet.

| Package | What it reads and writes | Specification |
|:--|:--|:--|
| `m3u8` | The HLS playlist, master and media alike | [RFC 8216](https://www.rfc-editor.org/rfc/rfc8216) |
| `mpd` | The DASH manifest | ISO/IEC 23009-1 |
| `ts` | MPEG-TS: packets, PAT, PMT, PES | ISO/IEC 13818-1 |
| `mp4` | ISO base media format, whole files and fragments | ISO/IEC 14496-12 |
| `rtmp` | The handshake, chunk stream and messages publishers push with | Adobe RTMP 1.0 |

Delivery itself needs nothing new: HLS and DASH travel over ordinary HTTP, which
means [`moonhttp`](https://github.com/moonbitstack/moonhttp) for media types and
range requests, and a server to answer them.

## What is deliberately elsewhere

| Thing | Where it lives | Why |
|:--|:--|:--|
| Peer connections, RTP, ICE | [`moonrtc`](https://github.com/moonbitstack/moonrtc) | Sub-second conversation and segmented broadcast are different problems with different limits |
| Reading the MPD's XML | [`moonxml`](https://github.com/moonbitstack/moonxml) | A manifest is an XML document, and XML does not fit the JSON tree the rest of this family reads into |
| Serving the segments | a server built on `moonhttp` | Nothing here opens a socket |
| Audio and video codecs | nowhere — out of scope | This library packages media; it does not encode it |

## Install

```bash
moon add moonbitstack/moonmedia
```

## Licence

Apache-2.0. See [LICENSE](LICENSE).
