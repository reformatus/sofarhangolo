# UX test notes for Sófár Hangoló

**Who uses it:** musicians and worship leaders, often on phones during rehearsal or a service,
sometimes on a tablet or a laptop connected to a projector. Text is Hungarian.

**Data:** the app downloads its song banks from the public, read-only bank APIs on first start
(the UX test's warm-up does this once). Songs, banks and their contents are real data: don't
judge them, only what the change does with them. Lists ("cues") are local to the browser; a
fresh test starts with none.

**Main pages** (routes under the site's address):

| Route | What | Check especially |
|---|---|---|
| `/home` | Home: news, links, quick access to banks | that it loads, news and buttons |
| `/bank` | Songs ("Dalok"): search and filters over all banks | search with and without accents (`ajandek` finds "Ajándék") |
| `/song/<uuid>` and `/song/<uuid>/lyrics`, `/svg`, `/pdf` | One song: lyrics with chords, sheet music (SVG), PDF | transposing, switching views, the add-to-list action |
| `/cues` | Lists ("Listáim"): the user's set lists; empty state when there are none | creating a list ("Új lista"), the empty state, editing and deleting |
| `/cue/<uuid>/edit` | Editing a list: slides, order, songs | adding a song, reordering |
| `/cue/<uuid>/present` (+ `/musician`) | Present mode for a list, full screen | moving between slides |

Navigation: on phones a bottom bar ("Főoldal", "Dalok", "Listák"), on tablets and desktops a side
rail. Always check a change that touches layout at a phone width (390 px) and a desktop width
(1280 px); breakpoints: tablet from 700 px, desktop from 1000 px.

**Deep links work only on app.sofarhangolo.hu.** On the test site every page load opens the home
screen (the app recognises routes in the address only on its own domain), so after opening the
site navigate inside the app: the "Listák" tab (a tab on phones, a rail button on desktops) for
lists, "Dalok" for songs, then open a song from the list. The address bar then shows the route.

Get a song's uuid from the song list (`/bank`, open a song, read the address bar), not from memory.
