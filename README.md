Context Stats
====

**Context Stats**[^1] lets you display lists of tracks, albums or artists *sorted by statistics* from the context menus of artists, albums, genres, years and playlists.<br><br>For more general library statistics (e.g. genres with the most or best rated tracks), have a look at the [**Visual Statistics**](https://github.com/AF-1/#-visual-statistics) plugin.<br><br>
If you use this plugin and like it, perhaps you could give it a :star: so that other users can discover it (in their News Feed). Thank you.
<br><br>
## Requirements

- LMS version >= 8.**4**
- LMS database = **SQLite**

<br>
<a href="https://github.com/AF-1/">⬅️ <b>Back to the list of all plugins</b></a>
<br><br><br>


## Screenshots[^2]

<img src="screenshots/cs.gif" width="100%">
<br><br><br>


## Installation

### Using the repository URL

- Add the repository URL below at the bottom of *LMS* > *Settings* > *Plugins* and click *Apply*:<br>
[https://raw.githubusercontent.com/AF-1/sobras/main/repos/lmsghonly/public.xml](https://raw.githubusercontent.com/AF-1/sobras/main/repos/lmsghonly/public.xml)

- Install the plugin from the added repository at the bottom of the page.
<br>

### Manual Install

Please read the instructions on how to [install a plugin manually](https://github.com/AF-1/sobras/wiki/Manual-installation-of-LMS-plugins).
<br><br><br>

## Reporting a new issue

If you want to report a new issue, please fill out this [**issue report template**](https://github.com/AF-1/lms-contextstats/issues/new?template=bug_report.md&title=%5BISSUE%5D+).<br><br>
If you use this plugin and like it, perhaps you could give it a :star: so that other users can discover it (in their News Feed). Thank you.
<br><br><br><br>

## FAQ

<details><summary>»<b>What do <i>AvR, TR, AvPC, TPC, AvSC, TSC and DPSV</i> stand for?</b>«</summary><br><p>
Av = average, i.e. the sum of all individual track values divided by the total number of all album/artist tracks.<br>
T = total, i.e the sum of all individual track values for an album/artist.<br><br>
- AvR = average rating<br><br>
- TR = total rating<br><br>
- AvPC = average play count<br><br>
- TPC = total play count<br><br>
- AvSC = average skip count<br><br>
- TSC = total skip count<br><br>
- DPSV = the average dynamic played/skipped value.
</p></details><br>

<details><summary>»<b>In lists for most/least total played or top total rated albums/artists, albums are sometimes listed more than once. Why?</b>«</summary><br><p>
This happens if the LMS database contains <i>more than one</i> contributor for the <i>same</i> contributor <i>role</i> (artist, album artist, track artist, band).<br>
Artists and albums lists in <i>Context Stats</i> will have items for each contributor (with identical (total) rating and play count values).</p></details><br>

<br><br>

[^1]:If you want localized strings in your language, please read <a href="https://github.com/AF-1/sobras/wiki/Adding-localization-to-LMS-plugins"><b>this</b></a>.
inspired by Erland's TrackStat.
[^2]: The screenshots might not correspond to the current UI in every detail.
