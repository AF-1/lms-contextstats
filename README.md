Context Stats
====

**Context Stats**[^1] lets you display lists of tracks, albums or artists *sorted by statistics* from the context menus of a selected artist, album, genre, year and playlist. Enabling *Display home menu item* in the plugin settings adds lists of tracks, albums or artists sorted by statistics for your **entire** music library.<br><br>For more general library statistics (e.g. genres with the most or best rated tracks), have a look at the [**Visual Statistics**](https://github.com/AF-1/#-visual-statistics) plugin.
<br><br>

## Requirements

- LMS version >= 8.**4**
- LMS database = SQLite

<br>
<a href="https://github.com/AF-1/">⬅️ <b>Back to the list of all plugins</b></a>
<br><br><br>


## Screenshots[^2]

<img src="screenshots/cs.gif" width="100%">
<br><br><br>


## Installation

**Context Stats** is available from the LMS plugin library: **LMS > Settings > Manage Plugins**.<br>

If you want to test a new patch that hasn't made it into a release version yet, you'll have to [install the plugin manually](https://github.com/AF-1/sobras/wiki/Manual-installation-of-LMS-plugins).
<br><br><br>

## Report a new issue

To report a new issue please file a GitHub [**issue report**](https://github.com/AF-1/lms-contextstats/issues/new/choose).<br><br>
If you use this plugin and like it, perhaps you could give it a :star: so that other users can discover it (in their News Feed). Thank you.
<br><br><br><br>

## FAQ

<details><summary>»<b>What do <i>AvR, TR, AvPC, TPC, AvSC, TSC and DPSV</i> stand for?</b>«</summary><br><p>
- AvR = average rating<br>
- TR = total rating<br>
- AvPC = average play count<br>
- TPC = total play count<br>
- AvSC = average skip count<br>
- TSC = total skip count<br>
- DPSV = average dynamic played/skipped value.
</p></details><br>

<details><summary>»<b>In the lists of most/least total played or top total rated albums/artists, albums are sometimes listed more than once. Why?</b>«</summary><br><p>
This happens if the LMS database contains <i>more than one</i> contributor for the <i>same</i> contributor <i>role</i> (artist, album artist, track artist, band).<br>
Artists and albums lists in <i>Context Stats</i> will have items for each contributor (with identical total rating, play count and skip count values).</p></details><br>

<br><br>

[^1]:If you want localized strings in your language, please read <a href="https://github.com/AF-1/sobras/wiki/Adding-localization-to-LMS-plugins"><b>this</b></a>.
inspired by Erland's TrackStat.
[^2]: The screenshots might not correspond to the current UI in every detail.
