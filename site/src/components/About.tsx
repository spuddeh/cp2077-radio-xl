const README = 'https://github.com/spuddeh/cp2077-radio-xl/blob/main/red4ext/plugins/RadioXL/stations/README.md'

export function About() {
  return (
    <main className="about">
      <section>
        <h2 className="section">What this is</h2>
        <p>
          The station builder makes a radio station mod for RadioXL. Fill in the station, add its audio, and Build .zip
          writes a mod ready to install with a mod manager: a <code>station.json</code> and the audio files, in the
          folder RadioXL reads stations from.
        </p>
        <p>
          The preview shows the station the way the game does: on the Radioport, where it sits on the dial, and on the
          four kinds of radio in the world. It is drawn from the game&apos;s own UI files, so the layout, colours and
          animations are the game&apos;s.
        </p>
        <p>
          Every field is checked against the rules RadioXL applies when it loads a station, so a station that builds
          here is one RadioXL will accept. The full format, including streams and idents, is in the{' '}
          <a href={README} target="_blank" rel="noopener noreferrer">
            station manifest reference
          </a>
          .
        </p>
      </section>

      <section>
        <h2 className="section">Editing a station</h2>
        <p>
          Drop a RadioXL station&apos;s zip or its installed folder on Edit a RadioXL station. The form fills from its{' '}
          <code>station.json</code>, each track is matched to its audio, and every other file in the mod, such as an
          icon archive, goes back into the zip unchanged. The station keeps its folder name, so the new zip installs
          over the old one.
        </p>
      </section>

      <section>
        <h2 className="section">Your files</h2>
        <p>
          Nothing is uploaded. Audio is read by this browser and written straight into the zip on your computer. The
          page makes no request to any other server.
        </p>
        <p>
          The station is not saved between visits. Closing or reloading the tab loses it, so the page asks first once
          anything has been entered.
        </p>
      </section>

      <section>
        <h2 className="section">Browsers</h2>
        <dl className="about-list">
          <dt>Chrome, Edge, Opera</dt>
          <dd>
            Build .zip asks where to save first, then writes the zip to that file as it goes. A station of any size works.
          </dd>
          <dt>Firefox, Safari</dt>
          <dd>
            These browsers cannot write to a file as it is built, so the whole zip is put together in memory and then
            downloaded. A large station needs as much free memory as its audio takes up, and the download starts only
            once the build ends.
          </dd>
          <dt>Copy station.json</dt>
          <dd>Needs clipboard permission. A browser that refuses it says so in a notification.</dd>
          <dt>Animation</dt>
          <dd>
            Starts off when your system asks apps to reduce motion (on Windows, Animation effects in the Accessibility
            settings). The switch above the preview overrides it, and the choice is remembered in this browser.
          </dd>
        </dl>
      </section>

      <section>
        <h2 className="section">Not built yet</h2>
        <p>
          Converting a RadioExt station or a RadioXL 0.1.0 station. A station with its own icon archive has to add that
          archive to the zip by hand.
        </p>
      </section>
    </main>
  )
}
