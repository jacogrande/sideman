import { useEffect, useRef } from "react";

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
      <circle cx="200" cy="200" r="198" fill="#111110" />
      <circle
        cx="200"
        cy="200"
        r="196"
        fill="#0F0F0D"
        stroke="#1a1918"
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
          strokeWidth="0.3"
          opacity={opacity}
        />
      ))}

      {/* Light reflection */}
      <ellipse
        cx="148"
        cy="128"
        rx="85"
        ry="65"
        fill="url(#vinyl-ref)"
        opacity="0.03"
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

      {/* Vinyl — desktop, positioned dramatically off-edge */}
      <div className="pointer-events-none absolute right-[-15%] top-1/2 hidden -translate-y-1/2 md:block lg:right-[-8%]">
        <VinylRecord className="h-[500px] w-[500px] opacity-[0.4] lg:h-[620px] lg:w-[620px]" />
      </div>

      <div className="relative z-10 mx-auto w-full max-w-7xl px-6 pb-20 pt-32 md:px-10">
        {/* Headline — massive stacked words */}
        <h1 className="font-display text-[clamp(3.5rem,11vw,9rem)] font-black leading-[0.92] tracking-tight">
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
          <VinylRecord className="h-[220px] w-[220px] opacity-35" />
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

      {/* ── Step 1: Play ── */}
      <Reveal className="mt-20 md:mt-28">
        <div className="grid items-start gap-8 md:grid-cols-[auto_1fr]">
          <span className="step-num" aria-hidden="true">
            01
          </span>
          <div className="md:pt-6">
            <h2 className="font-display text-3xl font-bold text-[var(--cream)] md:text-5xl">
              Play anything.
            </h2>
            <p className="mt-4 max-w-lg leading-relaxed text-[var(--muted)]">
              Open Spotify and hit play. Sideman lives in your menu bar, quietly
              detecting what&rsquo;s playing through a local system call — no
              extensions, no browser plugins, no permissions dialogs.
            </p>

            {/* Visual: now-playing indicator */}
            <div className="mt-8 inline-flex items-center gap-4 rounded-xl border border-[var(--subtle)] px-6 py-4">
              <div className="h-2.5 w-2.5 animate-[eq_1.5s_ease-in-out_infinite] rounded-full bg-[var(--emerald)]" />
              <div>
                <p className="font-display text-lg text-[var(--cream)]">
                  Nightcall
                </p>
                <p className="text-sm text-[var(--muted)]">Kavinsky</p>
              </div>
              <Equalizer bars={5} className="ml-4" />
            </div>
          </div>
        </div>
      </Reveal>

      <hr className="groove my-16 md:my-24" />

      {/* ── Step 2: Discover ── */}
      <Reveal>
        <div className="grid items-start gap-8 md:grid-cols-[auto_1fr]">
          <span className="step-num" aria-hidden="true">
            02
          </span>
          <div className="md:pt-6">
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
        </div>
      </Reveal>

      <hr className="groove my-16 md:my-24" />

      {/* ── Step 3: Playlist ── */}
      <Reveal>
        <div className="grid items-start gap-8 md:grid-cols-[auto_1fr]">
          <span className="step-num" aria-hidden="true">
            03
          </span>
          <div className="md:pt-6">
            <h2 className="font-display text-3xl font-bold text-[var(--cream)] md:text-5xl">
              Tap a name.
              <br />
              <span className="text-[var(--gold)]">Get a playlist.</span>
            </h2>
            <p className="mt-4 max-w-lg leading-relaxed text-[var(--muted)]">
              See a musician you love? Tap their name. Sideman searches their
              entire discography across MusicBrainz, ranks tracks by listen
              count via ListenBrainz, matches them to Spotify, and creates a
              playlist — opened directly in your Spotify app.
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
    <Reveal>
      <section className="mx-auto max-w-7xl px-6 pb-24 md:px-10 md:pb-32">
        <div className="relative overflow-hidden rounded-2xl border border-[var(--subtle)] p-8 md:p-14">
          {/* Dual warm glows — one per artist */}
          <div className="pointer-events-none absolute -left-16 -top-16 h-56 w-56 rounded-full bg-[var(--gold)]/[0.05] blur-[80px]" />
          <div className="pointer-events-none absolute -bottom-16 -right-16 h-56 w-56 rounded-full bg-[var(--gold)]/[0.04] blur-[80px]" />

          <div className="relative grid gap-12 md:grid-cols-[1fr_1fr]">
            {/* Left — copy */}
            <div>
              <p className="text-xs font-medium uppercase tracking-[0.25em] text-[var(--gold)]">
                Co-Credits
              </p>
              <h2 className="font-display mt-4 text-3xl font-bold text-[var(--cream)] md:text-5xl">
                Two names.
                <br />
                <span className="text-[var(--gold)]">Every collab.</span>
              </h2>
              <p className="mt-6 max-w-md leading-relaxed text-[var(--muted)]">
                Pick any two credited musicians and Sideman finds every
                recording they both appear on — across their entire
                discographies. Intersected via MusicBrainz, ranked by
                ListenBrainz popularity, delivered as a Spotify playlist.
              </p>
              <p className="mt-4 text-sm text-[var(--muted)]/70">
                Tap a name &rarr; choose &ldquo;Co-Credit&rdquo; &rarr; pick
                the second artist &rarr; playlist.
              </p>
            </div>

            {/* Right — visual demo */}
            <div>
              {/* Artist pair header */}
              <div className="flex items-center gap-3">
                <span className="rounded-full border border-[var(--gold)]/30 bg-[var(--gold)]/10 px-4 py-1.5 font-display text-sm text-[var(--cream)]">
                  Pharrell Williams
                </span>
                <span
                  className="font-display text-lg italic text-[var(--gold)]"
                  aria-hidden="true"
                >
                  &times;
                </span>
                <span className="rounded-full border border-[var(--gold)]/30 bg-[var(--gold)]/10 px-4 py-1.5 font-display text-sm text-[var(--cream)]">
                  Snoop Dogg
                </span>
              </div>

              {/* Playlist result */}
              <div className="mt-6 rounded-lg border border-[var(--subtle)] bg-[var(--bg)] px-5 py-4">
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
        </div>
      </section>
    </Reveal>
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
          <h2 className="font-display mt-6 text-3xl text-[var(--cream)] md:text-5xl">
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
      <section id="download" className="mx-auto max-w-7xl px-6 pb-20 md:px-10">
        <div className="relative overflow-hidden rounded-2xl border border-[var(--gold)]/15 p-10 md:p-16">
          {/* Warm stage-light glow */}
          <div className="pointer-events-none absolute -right-20 -top-20 h-64 w-64 rounded-full bg-[var(--gold)]/[0.06] blur-3xl" />

          <div className="relative max-w-xl">
            <p className="text-xs font-medium uppercase tracking-[0.25em] text-[var(--gold)]">
              Private Beta
            </p>
            <h2 className="font-display mt-4 text-3xl font-bold text-[var(--cream)] md:text-5xl">
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
