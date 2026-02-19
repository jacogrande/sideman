const featureCards = [
  {
    title: 'Track-level credits',
    description:
      'Resolve producers, writers, engineers, and session players from trusted sources in seconds.',
  },
  {
    title: 'Local-first monitoring',
    description:
      'Sideman reads what is currently playing without shipping your listening history off-device.',
  },
  {
    title: 'Smart source fallback',
    description:
      'Spotify, MusicBrainz, and Wikipedia enrichments are merged into a single clear view.',
  },
]

const releaseNotes = [
  'Private beta available for macOS users',
  'Instant song-to-credit lookup from your menubar',
  'Export-ready text for newsletters and social posts',
]

const requirements = ['macOS 13 Ventura or newer', 'Spotify desktop app', 'Internet connection for metadata lookups']

function App() {
  return (
    <div className="relative isolate min-h-screen overflow-hidden bg-slate-950 text-slate-100">
      <div className="pointer-events-none absolute inset-0 -z-10 overflow-hidden">
        <div className="absolute -left-36 top-[-8rem] h-96 w-96 rounded-full bg-cyan-400/25 blur-3xl" />
        <div className="absolute right-[-8rem] top-1/3 h-[28rem] w-[28rem] rounded-full bg-indigo-500/20 blur-3xl" />
        <div className="absolute bottom-[-12rem] left-1/3 h-[24rem] w-[24rem] rounded-full bg-emerald-400/20 blur-3xl" />
      </div>

      <header className="mx-auto flex w-full max-w-6xl items-center justify-between px-6 py-8">
        <a className="flex items-center gap-3 text-sm font-semibold uppercase tracking-[0.2em] text-white" href="#">
          <span className="inline-flex h-9 w-9 items-center justify-center rounded-xl bg-cyan-300 text-base font-bold tracking-normal text-slate-950">
            S
          </span>
          Sideman
        </a>
        <a
          className="rounded-full border border-cyan-200/50 px-4 py-2 text-sm font-medium text-cyan-100 transition hover:border-cyan-100 hover:bg-cyan-200/10"
          href="#download"
        >
          Download
        </a>
      </header>

      <main className="mx-auto w-full max-w-6xl px-6 pb-20">
        <section className="grid gap-14 pb-20 pt-8 lg:grid-cols-[1.2fr_0.8fr] lg:items-center">
          <div>
            <p className="inline-flex rounded-full border border-cyan-200/40 bg-cyan-300/10 px-4 py-1 text-xs font-semibold uppercase tracking-[0.2em] text-cyan-100">
              Private Beta
            </p>
            <h1 className="mt-6 text-balance text-4xl font-semibold leading-tight text-white md:text-6xl">
              Find the people behind every song you play.
            </h1>
            <p className="mt-6 max-w-2xl text-lg leading-relaxed text-slate-300">
              Sideman listens with you, identifies every track, and surfaces deep credits so your audience can
              discover the producers, writers, and musicians behind the music.
            </p>
            <div className="mt-8 flex flex-wrap gap-4">
              <a
                className="rounded-full bg-cyan-300 px-6 py-3 text-sm font-semibold text-slate-950 transition hover:bg-cyan-200"
                href="#download"
              >
                Download for macOS
              </a>
              <a
                className="rounded-full border border-white/20 px-6 py-3 text-sm font-semibold text-white transition hover:border-white/40 hover:bg-white/5"
                href="#features"
              >
                Explore Features
              </a>
            </div>
            <p className="mt-4 text-sm text-slate-400">No Spotify password sharing. Built for creators and curators.</p>
          </div>

          <div className="rounded-3xl border border-white/10 bg-white/5 p-6 shadow-2xl shadow-cyan-950/40 backdrop-blur">
            <p className="text-xs font-semibold uppercase tracking-[0.24em] text-cyan-100">Now Playing</p>
            <h2 className="mt-3 text-2xl font-semibold text-white">Nightcall</h2>
            <p className="text-sm text-slate-300">Kavinsky</p>
            <div className="mt-6 space-y-3">
              <article className="rounded-2xl border border-white/10 bg-slate-950/70 p-4">
                <p className="text-xs uppercase tracking-[0.18em] text-cyan-200">Producer</p>
                <p className="mt-1 text-lg text-white">Guy-Manuel de Homem-Christo</p>
              </article>
              <article className="rounded-2xl border border-white/10 bg-slate-950/70 p-4">
                <p className="text-xs uppercase tracking-[0.18em] text-cyan-200">Writer</p>
                <p className="mt-1 text-lg text-white">Kavinsky, Lovefoxxx</p>
              </article>
              <article className="rounded-2xl border border-white/10 bg-slate-950/70 p-4">
                <p className="text-xs uppercase tracking-[0.18em] text-cyan-200">Release Note</p>
                <p className="mt-1 text-sm text-slate-300">
                  Auto-generated context cards are ready to drop into your newsletter.
                </p>
              </article>
            </div>
          </div>
        </section>

        <section id="features" className="grid gap-6 md:grid-cols-3">
          {featureCards.map((item) => (
            <article key={item.title} className="rounded-3xl border border-white/10 bg-white/5 p-6 backdrop-blur">
              <h3 className="text-xl font-semibold text-white">{item.title}</h3>
              <p className="mt-3 leading-relaxed text-slate-300">{item.description}</p>
            </article>
          ))}
        </section>

        <section id="download" className="mt-20 grid gap-8 rounded-3xl border border-cyan-100/20 bg-cyan-300/10 p-8 lg:grid-cols-2">
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.22em] text-cyan-100">Download Sideman</p>
            <h2 className="mt-3 text-3xl font-semibold text-white">Get early access to the credits workflow.</h2>
            <p className="mt-4 leading-relaxed text-cyan-50/90">
              Sideman is currently distributed as a signed macOS app in private beta. Request access and we will send
              your download link.
            </p>
            <a
              className="mt-6 inline-flex rounded-full bg-white px-6 py-3 text-sm font-semibold text-slate-900 transition hover:bg-slate-100"
              href="mailto:hello@sideman.app?subject=Sideman%20Beta%20Access"
            >
              Request Beta Download
            </a>
          </div>
          <div className="rounded-2xl border border-white/20 bg-slate-950/40 p-6">
            <h3 className="text-sm font-semibold uppercase tracking-[0.2em] text-cyan-100">Release highlights</h3>
            <ul className="mt-4 space-y-2 text-slate-200">
              {releaseNotes.map((note) => (
                <li key={note} className="flex gap-2">
                  <span className="mt-2 h-1.5 w-1.5 shrink-0 rounded-full bg-cyan-200" />
                  <span>{note}</span>
                </li>
              ))}
            </ul>
            <h3 className="mt-6 text-sm font-semibold uppercase tracking-[0.2em] text-cyan-100">Requirements</h3>
            <ul className="mt-4 space-y-2 text-slate-200">
              {requirements.map((item) => (
                <li key={item} className="flex gap-2">
                  <span className="mt-2 h-1.5 w-1.5 shrink-0 rounded-full bg-emerald-200" />
                  <span>{item}</span>
                </li>
              ))}
            </ul>
          </div>
        </section>

        <footer className="mt-16 border-t border-white/10 py-8 text-sm text-slate-400">
          Sideman helps fans discover the humans behind the music.
        </footer>
      </main>
    </div>
  )
}

export default App
