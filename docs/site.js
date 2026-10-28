// moonmedia — the site's own script. Three small jobs: run the playlist
// parser in the page, copy code blocks, and keep the guide's contents list
// pointing at the section you are reading.

const SEP = "\u001e";

const PRESETS = {
  "low-latency": `#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:4
#EXT-X-MEDIA-SEQUENCE:266
#EXT-X-SERVER-CONTROL:CAN-SKIP-UNTIL=12,PART-HOLD-BACK=1,CAN-BLOCK-RELOAD=YES
#EXT-X-PART-INF:PART-TARGET=0.33334
#EXT-X-MAP:URI="init.mp4"
#EXT-X-PART:DURATION=0.33334,URI="filePart267.0.mp4",INDEPENDENT=YES
#EXT-X-PART:DURATION=0.33334,URI="filePart267.1.mp4"
#EXTINF:4.00008,
fileSequence267.mp4
#EXT-X-PART:DURATION=0.33334,URI="filePart268.0.mp4",INDEPENDENT=YES
#EXT-X-PRELOAD-HINT:TYPE=PART,URI="filePart268.1.mp4"
#EXT-X-RENDITION-REPORT:URI="../1M/waitForMSN.php",LAST-MSN=267,LAST-PART=0`,

  vod: `#EXTM3U
#EXT-X-VERSION:7
#EXT-X-TARGETDURATION:6
#EXT-X-PLAYLIST-TYPE:VOD
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MAP:URI="init.mp4"
#EXTINF:6,
segment0.m4s
#EXTINF:6,
segment1.m4s
#EXTINF:6,
segment2.m4s
#EXTINF:4.004,
segment3.m4s
#EXT-X-ENDLIST`,

  master: `#EXTM3U
#EXT-X-VERSION:7
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="sound",NAME="English",LANGUAGE="en",DEFAULT=YES,URI="audio/en.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=2400000,AVERAGE-BANDWIDTH=2100000,RESOLUTION=1280x720,FRAME-RATE=30,CODECS="avc1.64001f,mp4a.40.2",AUDIO="sound"
720p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,FRAME-RATE=30,CODECS="avc1.4d401e,mp4a.40.2",AUDIO="sound"
360p.m3u8`,
};

function demo() {
  const root = document.getElementById("playlist-demo");
  if (!root) return;

  const input = document.getElementById("playlist-input");
  const verdict = document.getElementById("verdict");
  const cues = document.getElementById("cues");
  const print = document.getElementById("print");
  const stamp = document.getElementById("stamp");

  const say = (html) => {
    verdict.innerHTML = html;
  };

  const reject = (message) => {
    cues.replaceChildren();
    print.textContent = "";
    say("<b>rejected</b>");
    stamp.textContent = "No good · " + message;
    stamp.hidden = false;
  };

  const render = (text) => {
    if (!text.trim()) {
      reject("nothing to read");
      return;
    }
    if (!window.moonmedia) {
      say("<b>not built</b>");
      print.textContent =
        "The parser is compiled into demo.js by the site's workflow.\n" +
        "Build it locally with:\n\n" +
        "  moon build src/examples/browser --target js --release\n" +
        "  cp _build/js/release/build/examples/browser/browser.js docs/demo.js";
      cues.replaceChildren();
      stamp.hidden = true;
      return;
    }

    const out = window.moonmedia.report(text);
    const [summary, written, rows] = out.split(SEP);
    if (summary === "error") {
      reject(written);
      return;
    }
    stamp.hidden = true;

    const fields = {};
    for (const part of summary.split("|").slice(1)) {
      const [k, v] = part.split("=");
      fields[k] = v;
    }
    const master = summary.startsWith("master");

    const many = (n, one, two) => `${n} ${Number(n) === 1 ? one : two}`;

    if (master) {
      say(
        `<b>Master playlist</b><span>${many(fields.variants, "variant", "variants")}</span>` +
          `<span>${many(fields.iframes, "I-frame list", "I-frame lists")}</span>`
      );
    } else {
      const seconds = Number(fields.duration).toFixed(2);
      say(
        `<b>Media playlist · ${fields.type}</b>` +
          `<span>${many(fields.segments, "segment", "segments")}</span>` +
          `<span>${seconds} s</span><span>target ${fields.target} s</span>` +
          (fields.parts > 0 ? `<span>${many(fields.parts, "part", "parts")}</span>` : "")
      );
    }

    const labels = master
      ? ["#", "bandwidth", "size", "uri"]
      : ["cue", "duration", "parts", "uri"];
    const head = document.createElement("li");
    head.className = "head";
    for (const label of labels) {
      const cell = document.createElement("span");
      cell.textContent = label;
      head.append(cell);
    }
    cues.replaceChildren(head);

    for (const line of rows.split("\n")) {
      if (!line) continue;
      const cells = line.split("\t");
      const item = document.createElement("li");
      for (const value of cells) {
        const cell = document.createElement("span");
        cell.textContent = value;
        item.append(cell);
      }
      if (cells.length === 4) item.children[2].className = "parts";
      cues.append(item);
    }

    print.textContent = written;
  };

  let timer = 0;
  const later = () => {
    clearTimeout(timer);
    timer = setTimeout(() => render(input.value), 140);
  };

  input.addEventListener("input", later);

  for (const chip of root.querySelectorAll("[data-preset]")) {
    chip.addEventListener("click", () => {
      for (const other of root.querySelectorAll("[data-preset]")) {
        other.setAttribute("aria-pressed", String(other === chip));
      }
      input.value = PRESETS[chip.dataset.preset] || "";
      render(input.value);
    });
  }

  render(input.value);
}

function copyButtons() {
  for (const block of document.querySelectorAll(".code")) {
    const pre = block.querySelector("pre");
    if (!pre) continue;
    const button = document.createElement("button");
    button.className = "copy";
    button.type = "button";
    button.textContent = "copy";
    button.addEventListener("click", async () => {
      try {
        await navigator.clipboard.writeText(pre.textContent);
        button.textContent = "copied";
        setTimeout(() => (button.textContent = "copy"), 1400);
      } catch {
        button.textContent = "no";
      }
    });
    block.append(button);
  }
}

function guideContents() {
  const links = [...document.querySelectorAll(".toc a[href^='#']")];
  if (!links.length) return;
  const sections = links.map((link) => ({
    id: link.hash.slice(1),
    link,
    node: document.getElementById(link.hash.slice(1)),
  }));
  if (sections.some((section) => !section.node)) return;

  // The section being read is the last one whose heading is above the fold:
  // an observer with a negative margin skipped the first section at the top of
  // the page, which is exactly where a reader starts.
  const update = () => {
    const line = window.scrollY + 120;
    let current = sections[0].id;
    for (const section of sections) {
      const top = section.node.getBoundingClientRect().top + window.scrollY;
      if (top <= line) current = section.id;
    }
    for (const section of sections) {
      section.link.classList.toggle("active", section.id === current);
    }
  };

  window.addEventListener("scroll", update, { passive: true });
  window.addEventListener("resize", update);
  update();
}

function apiFilter() {
  const input = document.getElementById("filter");
  if (!input) return;
  const entries = [...document.querySelectorAll(".entry")];
  const groups = [...document.querySelectorAll(".pkg")];

  const apply = () => {
    const needle = input.value.trim().toLowerCase();
    for (const entry of entries) {
      const hit = !needle || entry.textContent.toLowerCase().includes(needle);
      entry.hidden = !hit;
    }
    for (const group of groups) {
      const any = [...group.querySelectorAll(".entry")].some((e) => !e.hidden);
      group.hidden = !any;
    }
  };

  input.addEventListener("input", apply);
  apply();
}

function tabs() {
  const root = document.querySelector("[data-tabs]");
  if (!root) return;
  const buttons = [...root.querySelectorAll(".tab")];
  const panels = [...root.querySelectorAll(".panel")];

  const select = (name) => {
    for (const button of buttons) {
      button.setAttribute("aria-selected", String(button.dataset.tab === name));
    }
    for (const panel of panels) {
      panel.hidden = panel.dataset.panel !== name;
    }
  };

  for (const button of buttons) {
    button.addEventListener("click", () => {
      select(button.dataset.tab);
      history.replaceState(null, "", "#" + button.dataset.tab);
    });
  }

  // The hash picks the view, so a link can point at the packet grid.
  const named = location.hash.slice(1);
  select(panels.some((panel) => panel.dataset.panel === named) ? named : buttons[0].dataset.tab);
}

function anatomy() {
  const frames = document.querySelectorAll(".reel-frame[data-cut]");
  if (!frames.length) return;
  const cuts = [...document.querySelectorAll(".cut")];

  const show = (index) => {
    for (const cut of cuts) {
      cut.setAttribute("aria-pressed", String(cut.dataset.cut === String(index)));
    }
    for (const frame of frames) {
      const picked = frame.dataset.cut === String(index);
      frame.classList.toggle("picked", picked);
      frame.classList.toggle("muted", !picked);
    }
    const readout = document.getElementById("cut-readout");
    const cut = cuts.find((c) => c.dataset.cut === String(index));
    if (readout && cut) {
      for (const cell of readout.querySelectorAll("[data-field]")) {
        cell.textContent = cut.dataset[cell.dataset.field] || "—";
      }
    }
  };

  for (const cut of cuts) {
    cut.addEventListener("click", () => show(cut.dataset.cut));
  }
  show(0);
}


function boxTree() {
  const rows = [...document.querySelectorAll(".box-row")];
  const span = document.querySelector(".ruler .span");
  if (!rows.length || !span) return;
  const readout = document.getElementById("box-readout");
  const total = Math.max(...rows.map((row) => Number(row.dataset.start) + Number(row.dataset.size)));

  const show = (row) => {
    const start = Number(row.dataset.start);
    const size = Number(row.dataset.size);
    span.style.left = `${(start / total) * 100}%`;
    span.style.width = `${Math.max((size / total) * 100, 0.4)}%`;
    for (const other of rows) other.classList.toggle("active", other === row);
    if (readout) {
      const field = (name) => readout.querySelector(`[data-field="${name}"]`);
      field("type").textContent = row.dataset.type;
      field("offset").textContent = String(start);
      field("size").textContent = `${Number(row.dataset.size).toLocaleString("en-US")} bytes`;
      field("note").textContent = row.dataset.note;
    }
  };

  for (const row of rows) {
    row.addEventListener("mouseenter", () => show(row));
    row.addEventListener("focus", () => show(row));
    row.addEventListener("click", () => show(row));
  }
  show(rows[0]);
}

function packet() {
  const cells = [...document.querySelectorAll(".bytes span")];
  if (!cells.length) return;
  const readout = document.getElementById("byte-readout");
  const legend = [...document.querySelectorAll(".legend [data-field]")];
  const names = {
    sync: "sync byte",
    pid: "packet identifier",
    flags: "scrambling, adaptation, counter",
    af: "adaptation field",
    pcr: "programme clock",
    payload: "payload",
  };

  const show = (cell) => {
    for (const other of cells) other.classList.toggle("on", other === cell);
    if (!readout) return;
    const field = (name) => readout.querySelector(`[data-field="${name}"]`);
    field("offset").textContent = cell.dataset.byte;
    field("value").textContent = "0x" + cell.textContent;
    field("field").textContent = names[cell.dataset.field] || cell.dataset.field;
  };

  for (const cell of cells) {
    cell.addEventListener("mouseenter", () => show(cell));
    cell.addEventListener("click", () => show(cell));
  }

  // A legend item lights every byte of its field and dims the rest, which is
  // how a reader sees how much of the packet a clock takes.
  for (const item of legend) {
    item.addEventListener("mouseenter", () => {
      for (const cell of cells) {
        cell.classList.toggle("lit", cell.dataset.field === item.dataset.field);
        cell.classList.toggle("dim", cell.dataset.field !== item.dataset.field);
      }
    });
    item.addEventListener("mouseleave", () => {
      for (const cell of cells) cell.classList.remove("lit", "dim");
    });
  }

  show(cells[0]);
}

copyButtons();
demo();
guideContents();
apiFilter();
tabs();
anatomy();
boxTree();
packet();
