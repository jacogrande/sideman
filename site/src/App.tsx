import { useEffect, useRef, type CSSProperties } from "react";

/* ════════════════════════════════════════════════
   Utilities
   ════════════════════════════════════════════════ */

function useReveal() {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          el.classList.add("visible");
          observer.unobserve(el);
        }
      },
      { threshold: 0.05 }
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, []);
  return ref;
}

function Reveal({
  children,
  className = "",
}: {
  children: React.ReactNode;
  className?: string;
}) {
  const ref = useReveal();
  return (
    <div ref={ref} className={`reveal ${className}`}>
      {children}
    </div>
  );
}

/* ════════════════════════════════════════════════
   Art: Audio Waveform (Step 1)
   ════════════════════════════════════════════════ */

function AudioWaveform() {
  const bars = Array.from({ length: 40 }, (_, i) => {
    const seed = Math.sin(i * 9.1 + 3.7) * 0.5 + 0.5;
    const minH = 0.08 + seed * 0.15;
    const maxH = 0.4 + seed * 0.6;
    const dur = 1.6 + seed * 1.8;
    const delay = (i * 0.07) % 1.2;
    return { minH, maxH, dur, delay, opacity: 0.3 + seed * 0.7 };
  });

  return (
    <div className="flex items-center justify-center" aria-hidden="true">
      <svg viewBox="0 0 320 160" className="h-auto w-full max-w-xs md:max-w-sm">
        {bars.map((b, i) => (
          <rect
            key={i}
            className="waveform-bar"
            x={4 + i * 7.8}
            y={0}
            width={4}
            height={160}
            rx={2}
            fill="var(--gold)"
            opacity={b.opacity}
            style={{
              transformOrigin: "center bottom",
              animationDuration: `${b.dur}s`,
              animationDelay: `${b.delay}s`,
              "--min": b.minH,
              "--max": b.maxH,
            } as CSSProperties}
          />
        ))}
      </svg>
    </div>
  );
}

/* ════════════════════════════════════════════════
   Art: Name Cloud (Step 2)
   ════════════════════════════════════════════════ */

const NAME_CLOUD_DATA: {
  name: string;
  x: number;
  y: number;
  size: number;
  rotate: number;
  opacity: number;
  serif: boolean;
  color: string;
  layer: number;
}[] = [
  { name: "Nile Rodgers", x: 8, y: 10, size: 1.3, rotate: -8, opacity: 0.35, serif: true, color: "var(--gold)", layer: 1 },
  { name: "Carol Kaye", x: 55, y: 5, size: 1.0, rotate: 4, opacity: 0.2, serif: false, color: "var(--cream)", layer: 2 },
  { name: "Questlove", x: 25, y: 30, size: 1.6, rotate: -3, opacity: 0.3, serif: true, color: "var(--gold)", layer: 1 },
  { name: "Herbie Hancock", x: 60, y: 28, size: 0.85, rotate: 7, opacity: 0.18, serif: false, color: "var(--muted)", layer: 3 },
  { name: "Pino Palladino", x: 5, y: 52, size: 1.1, rotate: 5, opacity: 0.25, serif: true, color: "var(--cream)", layer: 2 },
  { name: "Steve Gadd", x: 48, y: 50, size: 0.9, rotate: -6, opacity: 0.22, serif: false, color: "var(--gold)", layer: 1 },
  { name: "Larry Graham", x: 72, y: 48, size: 1.2, rotate: 3, opacity: 0.28, serif: true, color: "var(--muted)", layer: 3 },
  { name: "Sheila E.", x: 15, y: 72, size: 1.4, rotate: -4, opacity: 0.32, serif: true, color: "var(--gold)", layer: 2 },
  { name: "James Jamerson", x: 50, y: 70, size: 0.8, rotate: 8, opacity: 0.15, serif: false, color: "var(--cream)", layer: 1 },
  { name: "Bob Clearmountain", x: 30, y: 88, size: 0.75, rotate: -2, opacity: 0.17, serif: false, color: "var(--muted)", layer: 3 },
  { name: "Tony Visconti", x: 68, y: 85, size: 1.0, rotate: 5, opacity: 0.23, serif: true, color: "var(--gold)", layer: 2 },
  { name: "Sylvia Massy", x: 8, y: 92, size: 0.9, rotate: -7, opacity: 0.2, serif: false, color: "var(--cream)", layer: 1 },
];

function NameCloud() {
  return (
    <div className="relative h-64 w-full md:h-80" aria-hidden="true">
      {NAME_CLOUD_DATA.map((n, i) => (
        <span
          key={i}
          style={{
            position: "absolute",
            left: `${n.x}%`,
            top: `${n.y}%`,
            fontSize: `${n.size}rem`,
            transform: `rotate(${n.rotate}deg)`,
            opacity: n.opacity,
            color: n.color,
          }}
          className={n.serif ? "font-display italic" : "font-medium tracking-wide"}
        >
          {n.name}
        </span>
      ))}
    </div>
  );
}

/* ════════════════════════════════════════════════
   Art: Constellation Graph (Step 3)
   ════════════════════════════════════════════════ */

const CONSTELLATION_NODES: { cx: number; cy: number; r: number; gold?: boolean }[] = [
  //  0: focal point — offset left for asymmetry
  { cx: 130, cy: 128, r: 14, gold: true },
  //  1–5: inner orbit
  { cx: 90, cy: 78, r: 5 },
  { cx: 182, cy: 82, r: 6 },
  { cx: 195, cy: 152, r: 5 },
  { cx: 155, cy: 192, r: 6 },
  { cx: 78, cy: 175, r: 5 },
  //  6–11: outer orbit
  { cx: 38, cy: 35, r: 7 },
  { cx: 235, cy: 32, r: 8 },
  { cx: 268, cy: 148, r: 6 },
  { cx: 222, cy: 232, r: 7 },
  { cx: 55, cy: 235, r: 7 },
  { cx: 22, cy: 132, r: 5 },
  // 12–15: distant satellites
  { cx: 148, cy: 14, r: 3 },
  { cx: 288, cy: 72, r: 4 },
  { cx: 280, cy: 240, r: 3 },
  { cx: 85, cy: 258, r: 4 },
];

const CONSTELLATION_EDGES: [number, number][] = [
  // center to inner orbit
  [0, 1], [0, 2], [0, 3], [0, 4], [0, 5],
  // inner orbit to outer orbit
  [1, 6], [2, 7], [3, 8], [4, 9], [5, 10], [1, 11],
  // outer to distant satellites
  [6, 12], [7, 12], [7, 13], [8, 13], [9, 14], [10, 15],
  // cross-links for density
  [6, 11], [8, 9], [2, 3], [4, 5],
];

function ConstellationGraph() {
  const svgRef = useRef<SVGSVGElement>(null);

  useEffect(() => {
    const svg = svgRef.current;
    if (!svg) return;

    const circles = svg.querySelectorAll<SVGCircleElement>("[data-node]");
    const lines = svg.querySelectorAll<SVGLineElement>("[data-edge]");

    let raf: number;
    const animate = (t: number) => {
      const time = t / 1000;

      const positions = CONSTELLATION_NODES.map((node, i) => {
        const speed = 0.25 + i * 0.06;
        const rx = 6 + (i % 3) * 5;
        const ry = 5 + (i % 2) * 6;
        const phase = i * 1.4;
        return {
          x: node.cx + Math.sin(time * speed + phase) * rx,
          y: node.cy + Math.cos(time * speed * 0.7 + phase) * ry,
        };
      });

      circles.forEach((circle, i) => {
        const node = CONSTELLATION_NODES[i];
        const pulse = Math.sin(time * 1.2 + i * 0.9) * 0.5 + 0.5;
        const baseOpacity = node.gold ? 0.8 : 0.18;
        circle.setAttribute("cx", String(positions[i].x));
        circle.setAttribute("cy", String(positions[i].y));
        circle.setAttribute("r", String(node.r + pulse * 3));
        circle.setAttribute("opacity", String(baseOpacity + pulse * 0.15));
      });

      lines.forEach((line, i) => {
        const [a, b] = CONSTELLATION_EDGES[i];
        line.setAttribute("x1", String(positions[a].x));
        line.setAttribute("y1", String(positions[a].y));
        line.setAttribute("x2", String(positions[b].x));
        line.setAttribute("y2", String(positions[b].y));
      });

      raf = requestAnimationFrame(animate);
    };

    raf = requestAnimationFrame(animate);
    return () => cancelAnimationFrame(raf);
  }, []);

  return (
    <div className="flex items-center justify-center" aria-hidden="true">
      <svg ref={svgRef} viewBox="0 0 300 270" className="h-auto w-full max-w-xs md:max-w-sm">
        {/* Edges */}
        {CONSTELLATION_EDGES.map(([a, b], i) => (
          <line
            key={`e${i}`}
            data-edge
            x1={CONSTELLATION_NODES[a].cx}
            y1={CONSTELLATION_NODES[a].cy}
            x2={CONSTELLATION_NODES[b].cx}
            y2={CONSTELLATION_NODES[b].cy}
            stroke="var(--cream)"
            strokeWidth={1}
            strokeDasharray="8 5"
            opacity={0.25}
            className="constellation-edge"
            style={{ animationDuration: `${3 + i * 0.4}s` }}
          />
        ))}
        {/* Nodes */}
        {CONSTELLATION_NODES.map((n, i) => (
          <circle
            key={`n${i}`}
            data-node
            cx={n.cx}
            cy={n.cy}
            r={n.r}
            fill={n.gold ? "var(--gold)" : "var(--cream)"}
            opacity={n.gold ? 0.8 : 0.18}
          />
        ))}
      </svg>
    </div>
  );
}

/* ════════════════════════════════════════════════
   Vinyl Record — pure SVG
   ════════════════════════════════════════════════ */

function VinylRecord({ className = "" }: { className?: string }) {
  const grooves = Array.from({ length: 55 }, (_, i) => ({
    r: 190 - i * 2.6,
    opacity: 0.1 + (i % 4) * 0.055,
  }));

  return (
    <svg
      className={`vinyl ${className}`}
      viewBox="0 0 400 400"
      fill="none"
      role="img"
      aria-label="Spinning vinyl record"
    >
      {/* Body */}
      <circle cx="200" cy="200" r="198" fill="#181715" />
      <circle
        cx="200"
        cy="200"
        r="196"
        fill="#141311"
        stroke="#2A2824"
        strokeWidth="0.5"
      />

      {/* Grooves */}
      {grooves.map(({ r, opacity }, i) => (
        <circle
          key={i}
          cx="200"
          cy="200"
          r={r}
          fill="none"
          stroke="var(--cream)"
          strokeWidth="0.4"
          opacity={opacity * 1.6}
        />
      ))}

      {/* Light reflection */}
      <ellipse
        cx="148"
        cy="128"
        rx="85"
        ry="65"
        fill="url(#vinyl-ref)"
        opacity="0.07"
      />

      {/* Label */}
      <circle cx="200" cy="200" r="52" fill="url(#vinyl-label)" />
      <text
        x="200"
        y="190"
        textAnchor="middle"
        fill="#0A0A08"
        fontSize="6.5"
        fontWeight="600"
        letterSpacing="0.18em"
        fontFamily="Outfit, sans-serif"
      >
        SIDEMAN
      </text>
      <text
        x="200"
        y="201"
        textAnchor="middle"
        fill="#0A0A08"
        fontSize="4.5"
        opacity="0.55"
        fontFamily="Outfit, sans-serif"
      >
        WHO PLAYED ON THAT?
      </text>
      <line
        x1="172"
        y1="207"
        x2="228"
        y2="207"
        stroke="#0A0A08"
        strokeWidth="0.4"
        opacity="0.2"
      />
      <text
        x="200"
        y="217"
        textAnchor="middle"
        fill="#0A0A08"
        fontSize="4"
        opacity="0.35"
        fontFamily="Outfit, sans-serif"
      >
        SIDE A
      </text>

      {/* Spindle */}
      <circle cx="200" cy="200" r="4" fill="#0A0A08" />

      <defs>
        <radialGradient id="vinyl-ref">
          <stop offset="0%" stopColor="var(--cream)" />
          <stop offset="100%" stopColor="transparent" />
        </radialGradient>
        <radialGradient id="vinyl-label" cx="0.38" cy="0.32" r="0.6">
          <stop offset="0%" stopColor="#E8BC82" />
          <stop offset="100%" stopColor="#B8895C" />
        </radialGradient>
      </defs>
    </svg>
  );
}

/* ════════════════════════════════════════════════
   Equalizer — CSS-animated bars
   ════════════════════════════════════════════════ */

function Equalizer({
  bars = 7,
  className = "",
}: {
  bars?: number;
  className?: string;
}) {
  const durations = [0.82, 1.18, 0.94, 1.38, 0.74, 1.1, 0.9];
  const delays = [0, 0.24, 0.12, 0.4, 0.07, 0.3, 0.18];

  return (
    <div
      className={`flex items-end gap-[3px] ${className}`}
      aria-hidden="true"
    >
      {Array.from({ length: bars }, (_, i) => (
        <div
          key={i}
          className="eq-bar w-[3px] rounded-full bg-[var(--gold)]"
          style={{
            animationDuration: `${durations[i % durations.length]}s`,
            animationDelay: `${delays[i % delays.length]}s`,
          }}
        />
      ))}
    </div>
  );
}

/* ════════════════════════════════════════════════
   Credits Marquee — infinite horizontal scroll
   ════════════════════════════════════════════════ */

function CreditsMarquee() {
  const credits = [
    "Nile Rodgers — Guitar",
    "Carol Kaye — Bass",
    "Questlove — Drums",
    "Herbie Hancock — Keys",
    "Pino Palladino — Bass",
    "Steve Gadd — Drums",
    "Larry Graham — Bass",
    "Sheila E. — Percussion",
    "James Jamerson — Bass",
    "Bob Clearmountain — Mixing",
    "Tony Visconti — Producer",
    "Sylvia Massy — Engineer",
  ];

  const items = credits.map((c, i) => (
    <span
      key={i}
      className="mx-6 whitespace-nowrap font-display text-sm italic tracking-wide text-[var(--muted)] md:mx-10 md:text-base"
    >
      {c}
    </span>
  ));

  return (
    <div className="overflow-hidden border-y border-[var(--subtle)] py-5">
      <div className="marquee-track">
        <div className="flex">{items}</div>
        <div className="flex" aria-hidden="true">
          {items}
        </div>
      </div>
    </div>
  );
}

/* ════════════════════════════════════════════════
   Nav
   ════════════════════════════════════════════════ */

function Nav() {
  return (
    <header className="animate-fade-up absolute left-0 right-0 top-0 z-20 mx-auto flex w-full max-w-7xl items-center justify-between px-6 py-6 md:px-10">
      <a className="flex items-center gap-3" href="/">
        <img
          src="/sideman.svg"
          alt="Sideman"
          className="h-8 w-8 rounded-lg"
        />
        <span className="text-xs font-medium uppercase tracking-[0.25em] text-[var(--cream)]/60">
          Sideman
        </span>
      </a>
      <a
        className="glow-hover rounded-full border border-[var(--gold)]/30 px-5 py-2 text-xs font-medium uppercase tracking-[0.15em] text-[var(--gold)] transition-colors hover:border-[var(--gold)]/60 hover:text-[var(--cream)]"
        href="#download"
      >
        Download
      </a>
    </header>
  );
}

/* ════════════════════════════════════════════════
   Hero
   ════════════════════════════════════════════════ */

function Hero() {
  const words: { text: string; delay: number; gold?: boolean }[] = [
    { text: "Who", delay: 0.2 },
    { text: "played", delay: 0.38 },
    { text: "on that?", delay: 0.58, gold: true },
  ];

  return (
    <section className="relative flex min-h-screen items-center overflow-hidden">
      {/* Warm ambient glow */}
      <div className="pointer-events-none absolute left-1/3 top-1/4 h-[500px] w-[500px] rounded-full bg-[var(--gold)]/[0.03] blur-[120px]" />

      {/* Vinyl — desktop, slides in from right */}
      <div className="vinyl-slide pointer-events-none absolute right-[-15%] top-1/2 hidden md:block lg:right-[-8%]">
        <VinylRecord className="h-[500px] w-[500px] opacity-[0.55] lg:h-[620px] lg:w-[620px]" />
      </div>

      <div className="relative z-10 mx-auto w-full max-w-7xl px-6 pb-20 pt-32 md:px-10">
        {/* Headline — massive stacked words */}
        <h1 className="font-display text-[clamp(4.5rem,13vw,9.5rem)] font-black leading-[0.9] tracking-tight">
          {words.map(({ text, delay, gold }) => (
            <span key={text} className="word-reveal">
              <span
                className={gold ? "italic text-[var(--gold)]" : ""}
                style={{ animationDelay: `${delay}s` }}
              >
                {text}
              </span>
            </span>
          ))}
        </h1>

        {/* Equalizer — living music indicator */}
        <Equalizer className="animate-fade-up delay-3 mt-8" />

        {/* Subtitle */}
        <p className="animate-fade-up delay-3 mt-6 max-w-lg text-base leading-relaxed text-[var(--muted)] md:text-lg">
          A macOS menu bar app that reads your Spotify playback, surfaces
          session musicians, producers, writers, and engineers — then lets you
          tap any name to create a playlist of their work.
        </p>

        {/* CTAs */}
        <div className="animate-fade-up delay-4 mt-10 flex flex-wrap items-center gap-5">
          <a
            className="glow-hover rounded-full bg-[var(--gold)] px-7 py-3.5 text-sm font-semibold text-[var(--bg)]"
            href="#download"
          >
            Download for macOS
          </a>
          <a
            className="text-sm font-medium text-[var(--cream)]/50 transition-colors hover:text-[var(--gold)]"
            href="#how-it-works"
          >
            See how it works &darr;
          </a>
        </div>

        {/* Trust line — rewritten for humans, not engineers */}
        <p className="animate-fade-up delay-5 mt-8 text-sm text-[var(--muted)]/70">
          Reads playback locally. No listening data leaves your Mac. No
          passwords required.
        </p>

        {/* Vinyl — mobile, centered below */}
        <div className="mt-16 flex justify-center md:hidden">
          <VinylRecord className="h-[220px] w-[220px] opacity-50" />
        </div>
      </div>
    </section>
  );
}

/* ════════════════════════════════════════════════
   How It Works — editorial, not a grid
   ════════════════════════════════════════════════ */

function HowItWorks() {
  return (
    <section
      id="how-it-works"
      className="mx-auto max-w-7xl px-6 py-24 md:px-10 md:py-32"
    >
      <Reveal>
        <p className="text-xs font-medium uppercase tracking-[0.25em] text-[var(--gold)]">
          How it works
        </p>
      </Reveal>

      {/* ── Step 1: Play — text left, waveform right ── */}
      <Reveal className="mt-20 md:mt-28">
        <div className="grid items-center gap-10 md:grid-cols-2 md:gap-16">
          <div>
            <span className="step-num mb-3" aria-hidden="true">01</span>
            <h2 className="font-display text-3xl font-bold text-[var(--cream)] md:text-5xl">
              Play anything.
            </h2>
            <p className="mt-4 max-w-lg leading-relaxed text-[var(--muted)]">
              Open Spotify and hit play. Sideman lives in your menu bar, quietly
              detecting what&rsquo;s playing through a local system call — no
              extensions, no browser plugins, no permissions dialogs.
            </p>

            {/* Visual: now-playing indicator */}
            <div className="mt-8 inline-flex items-center gap-3 rounded-xl border border-[var(--subtle)] px-4 py-3 sm:gap-4 sm:px-6 sm:py-4">
              <div className="h-2.5 w-2.5 shrink-0 animate-[eq_1.5s_ease-in-out_infinite] rounded-full bg-[var(--emerald)]" />
              <div className="min-w-0">
                <p className="font-display text-base text-[var(--cream)] sm:text-lg">
                  Nightcall
                </p>
                <p className="text-sm text-[var(--muted)]">Kavinsky</p>
              </div>
              <Equalizer bars={5} className="ml-2 hidden sm:flex sm:ml-4" />
            </div>
          </div>

          <AudioWaveform />
        </div>
      </Reveal>

      <hr className="groove my-16 md:my-24" />

      {/* ── Step 2: Discover — name cloud left, text right ── */}
      <Reveal>
        <div className="grid items-center gap-10 md:grid-cols-2 md:gap-16">
          <div className="order-1 md:order-2">
            <span className="step-num mb-3" aria-hidden="true">02</span>
            <h2 className="font-display text-3xl font-bold text-[var(--cream)] md:text-5xl">
              See who&rsquo;s behind it.
            </h2>
            <p className="mt-4 max-w-lg leading-relaxed text-[var(--muted)]">
              Credits are resolved from MusicBrainz and Wikipedia in seconds.
              Session musicians, producers, songwriters, engineers — grouped by
              role, sourced from the most comprehensive music databases in the
              world.
            </p>

            {/* Visual: credits panel */}
            <div className="mt-8 max-w-md space-y-3">
              {[
                {
                  group: "Musicians",
                  items: [
                    "Guy-Manuel de Homem-Christo — Production",
                    "Lovefoxxx — Vocals",
                  ],
                },
                { group: "Writing", items: ["Vincent Belorgey", "Lovefoxxx"] },
                {
                  group: "Engineering",
                  items: ["SebastiAn — Mixing"],
                },
              ].map(({ group, items }) => (
                <div
                  key={group}
                  className="rounded-lg border border-[var(--subtle)] px-5 py-3"
                >
                  <p className="text-xs font-medium uppercase tracking-[0.2em] text-[var(--gold)]/60">
                    {group}
                  </p>
                  {items.map((item) => (
                    <p
                      key={item}
                      className="mt-1 text-sm text-[var(--cream)]/80"
                    >
                      {item}
                    </p>
                  ))}
                </div>
              ))}
            </div>
          </div>

          <div className="order-2 md:order-1">
            <NameCloud />
          </div>
        </div>
      </Reveal>

      <hr className="groove my-16 md:my-24" />

      {/* ── Step 3: Playlist — text left, constellation right ── */}
      <Reveal>
        <div className="grid items-center gap-10 md:grid-cols-2 md:gap-16">
          <div>
            <span className="step-num mb-3" aria-hidden="true">03</span>
            <h2 className="font-display text-3xl font-bold text-[var(--cream)] md:text-5xl">
              Tap a name.
              <br />
              <span className="text-[var(--gold)]">Get a playlist.</span>
            </h2>
            <p className="mt-4 max-w-lg leading-relaxed text-[var(--muted)]">
              See a musician you love? Tap their name. Sideman searches their
              entire discography across MusicBrainz, ranks tracks by listen count
              via ListenBrainz, matches them to Spotify, and creates a playlist —
              opened directly in your Spotify app.
            </p>

            {/* Visual: playlist being created */}
            <div className="mt-8 max-w-md">
              <div className="rounded-lg border border-[var(--gold)]/20 bg-[var(--gold)]/5 px-5 py-4">
                <p className="text-xs text-[var(--muted)]">
                  Creating playlist for
                </p>
                <p className="font-display mt-1 text-xl text-[var(--cream)]">
                  Pino Palladino
                </p>
              </div>

              <div className="mt-4 space-y-2 pl-2">
                {[
                  {
                    n: "01",
                    track: "Wherever I Lay My Hat",
                    artist: "Paul Young",
                  },
                  {
                    n: "02",
                    track: "Untitled (How Does It Feel)",
                    artist: "D'Angelo",
                  },
                  { n: "03", track: "Gravity", artist: "John Mayer" },
                  { n: "04", track: "On & On", artist: "Erykah Badu" },
                  { n: "05", track: "Lingus", artist: "Snarky Puppy" },
                ].map(({ n, track, artist }, i) => (
                  <div
                    key={n}
                    className="stagger flex items-baseline gap-4"
                    style={{ transitionDelay: `${0.15 + i * 0.1}s` }}
                  >
                    <span className="font-display text-xs text-[var(--cream)]/25">
                      {n}
                    </span>
                    <div>
                      <p className="text-sm text-[var(--cream)]">{track}</p>
                      <p className="text-xs text-[var(--muted)]">{artist}</p>
                    </div>
                  </div>
                ))}
                <p className="mt-3 pl-8 text-xs text-[var(--emerald)]">
                  + 17 more tracks &rarr; opens in Spotify
                </p>
              </div>
            </div>
          </div>

          <ConstellationGraph />
        </div>
      </Reveal>
    </section>
  );
}

/* ════════════════════════════════════════════════
   Co-Credits — the "× " feature
   ════════════════════════════════════════════════ */

function CoCredits() {
  return (
    <section className="mx-auto max-w-7xl px-6 pb-24 md:px-10 md:pb-32">
      <hr className="groove mb-24 md:mb-32" />

      <Reveal>
        <p className="text-xs font-medium uppercase tracking-[0.25em] text-[var(--gold)]">
          Co-Credits
        </p>
      </Reveal>

      <Reveal className="mt-12 md:mt-16">
        <div className="grid gap-10 md:grid-cols-2 md:gap-16">
          {/* Left — copy */}
          <div>
            <h2 className="font-display text-3xl font-bold text-[var(--cream)] md:text-5xl">
              Two names.
              <br />
              <span className="text-[var(--gold)]">Every collab.</span>
            </h2>
            <p className="mt-6 max-w-md leading-relaxed text-[var(--muted)]">
              Pick any two credited musicians and Sideman finds every recording
              they both appear on — across their entire discographies.
              Intersected via MusicBrainz, ranked by ListenBrainz popularity,
              delivered as a Spotify playlist.
            </p>
            <p className="mt-4 text-sm text-[var(--muted)]/70">
              Tap a name &rarr; choose &ldquo;Co-Credit&rdquo; &rarr; pick the
              second artist &rarr; playlist.
            </p>
          </div>

          {/* Right — visual demo */}
          <div>
            {/* Artist pair header */}
            <div className="flex flex-wrap items-center gap-2 sm:gap-3">
              <span className="rounded-full border border-[var(--gold)]/30 bg-[var(--gold)]/10 px-3 py-1.5 font-display text-xs text-[var(--cream)] sm:px-4 sm:text-sm">
                Pharrell Williams
              </span>
              <span
                className="font-display text-base italic text-[var(--gold)] sm:text-lg"
                aria-hidden="true"
              >
                &times;
              </span>
              <span className="rounded-full border border-[var(--gold)]/30 bg-[var(--gold)]/10 px-3 py-1.5 font-display text-xs text-[var(--cream)] sm:px-4 sm:text-sm">
                Snoop Dogg
              </span>
            </div>

            {/* Playlist result */}
            <div className="mt-6 rounded-lg border border-[var(--subtle)] px-5 py-4">
              <p className="text-xs text-[var(--muted)]">
                Pharrell Williams &times; Snoop Dogg — Credits
              </p>

              <div className="mt-4 space-y-2.5">
                {[
                  {
                    n: "01",
                    track: "Drop It Like It's Hot",
                    album: "R&G: Rhythm & Gangsta",
                  },
                  {
                    n: "02",
                    track: "Beautiful",
                    album: "The Neptunes Present… Clones",
                  },
                  {
                    n: "03",
                    track: "That Girl",
                    album: "Bush",
                  },
                  {
                    n: "04",
                    track: "Let's Get Blown",
                    album: "R&G: Rhythm & Gangsta",
                  },
                  {
                    n: "05",
                    track: "It Blows My Mind",
                    album: "Tha Last Meal",
                  },
                ].map(({ n, track, album }, i) => (
                  <div
                    key={n}
                    className="stagger flex items-baseline gap-4"
                    style={{ transitionDelay: `${0.2 + i * 0.1}s` }}
                  >
                    <span className="font-display text-xs text-[var(--cream)]/25">
                      {n}
                    </span>
                    <div>
                      <p className="text-sm text-[var(--cream)]">{track}</p>
                      <p className="text-xs text-[var(--muted)]">{album}</p>
                    </div>
                  </div>
                ))}
                <p className="mt-3 pl-8 text-xs text-[var(--emerald)]">
                  + 23 more shared credits &rarr; opens in Spotify
                </p>
              </div>
            </div>
          </div>
        </div>
      </Reveal>
    </section>
  );
}

/* ════════════════════════════════════════════════
   Privacy — bold typographic statement
   ════════════════════════════════════════════════ */

function Privacy() {
  return (
    <Reveal>
      <section className="mx-auto max-w-7xl px-6 py-20 md:px-10 md:py-32">
        <div className="flex flex-col items-center text-center">
          <svg
            className="h-10 w-10 text-[var(--gold)]/40"
            fill="none"
            viewBox="0 0 24 24"
            strokeWidth={1}
            stroke="currentColor"
            aria-hidden="true"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              d="M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z"
            />
          </svg>
          <h2 className="font-display mt-6 text-2xl text-[var(--cream)] md:text-4xl">
            Your Mac. Your music.
            <br />
            <span className="text-[var(--muted)]">Nothing leaves.</span>
          </h2>
          <p className="mt-6 max-w-md leading-relaxed text-[var(--muted)]">
            Playback detection uses macOS AppleScript — a local system call.
            Spotify Web API is only used for playlist creation, with your
            explicit OAuth permission. No passwords. No tracking. No analytics.
          </p>
        </div>
      </section>
    </Reveal>
  );
}

/* ════════════════════════════════════════════════
   Download CTA
   ════════════════════════════════════════════════ */

function Download() {
  return (
    <Reveal>
      <section id="download" className="mx-auto max-w-7xl pb-20 md:px-10">
        <div className="relative overflow-hidden border-y border-[var(--gold)]/15 px-6 py-12 sm:py-16 md:rounded-2xl md:border md:px-16 md:py-20">
          {/* Warm stage-light glow */}
          <div className="pointer-events-none absolute -right-20 -top-20 h-64 w-64 rounded-full bg-[var(--gold)]/[0.06] blur-3xl" />

          <div className="relative max-w-xl">
            <p className="text-xs font-medium uppercase tracking-[0.25em] text-[var(--gold)]">
              Private Beta
            </p>
            <h2 className="font-display mt-4 text-3xl font-bold text-[var(--cream)] md:text-4xl">
              Try it.
            </h2>
            <p className="mt-6 leading-relaxed text-[var(--muted)]">
              Sideman is a signed macOS app in private beta. Request access and
              we&rsquo;ll send your download link.
            </p>

            <a
              className="glow-hover mt-8 inline-flex rounded-full bg-[var(--gold)] px-7 py-3.5 text-sm font-semibold text-[var(--bg)]"
              href="mailto:hello@sideman.app?subject=Sideman%20Beta%20Access"
            >
              Request Beta Access
            </a>

            <ul className="mt-10 flex flex-wrap gap-x-8 gap-y-3 text-sm text-[var(--muted)]">
              <li className="flex items-center gap-2">
                <span className="h-1.5 w-1.5 rounded-full bg-[var(--emerald)]" />
                macOS 13+
              </li>
              <li className="flex items-center gap-2">
                <span className="h-1.5 w-1.5 rounded-full bg-[var(--emerald)]" />
                Spotify desktop app
              </li>
              <li className="flex items-center gap-2">
                <span className="h-1.5 w-1.5 rounded-full bg-[var(--emerald)]" />
                Internet connection
              </li>
            </ul>
          </div>
        </div>
      </section>
    </Reveal>
  );
}

/* ════════════════════════════════════════════════
   Footer
   ════════════════════════════════════════════════ */

function Footer() {
  return (
    <footer className="mx-auto max-w-7xl border-t border-[var(--subtle)] px-6 py-10 md:px-10">
      <div className="flex flex-col items-start justify-between gap-4 sm:flex-row sm:items-center">
        <p className="font-display text-lg italic text-[var(--muted)]/50">
          For the people behind the music.
        </p>
        <p className="text-xs text-[var(--muted)]/30">
          &copy; {new Date().getFullYear()} Sideman
        </p>
      </div>
    </footer>
  );
}

/* ════════════════════════════════════════════════
   App
   ════════════════════════════════════════════════ */

function App() {
  return (
    <div className="texture relative min-h-screen bg-[var(--bg)]">
      <Nav />
      <main>
        <Hero />
        <CreditsMarquee />
        <HowItWorks />
        <CoCredits />
        <Privacy />
        <Download />
      </main>
      <Footer />
    </div>
  );
}

export default App;
