#
# Context Stats
#
# (c) 2024 AF
#
# GPLv3 license
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
#

package Plugins::ContextStats::Plugin;

use strict;
use warnings;
use utf8;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Log;
use Slim::Utils::Strings qw(string cstring);
use Slim::Utils::Prefs;
use Slim::Utils::Text;
use Slim::Utils::Unicode;
use Slim::Schema;
use POSIX;
use Time::HiRes qw(time);
use Path::Class;

my $log = Slim::Utils::Log->addLogCategory({
	'category' => 'plugin.contextstats',
	'defaultLevel' => 'INFO',
	'description' => 'PLUGIN_CONTEXTSTATS',
});

my $serverPrefs = preferences('server');
my $prefs = preferences('plugin.contextstats');

my ($listTypes, $apc_enabled, $MAIprefs);

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);

	initPrefs();

	if (main::WEBUI) {
		require Plugins::ContextStats::Settings;
		Plugins::ContextStats::Settings->new($class);
		Slim::Web::Pages->addPageFunction('contextstatsmenu\.html', \&_statsListsMenuWeb);
		if ($prefs->get('browsemenuitem')) {
			Slim::Web::Pages->addPageFunction('browse_all\.html', \&_statsListsMenuWebAll);
			Slim::Web::Pages->addPageLinks('browse', {'PLUGIN_CONTEXTSTATS' => 'plugins/ContextStats/html/browse_all.html'});
			Slim::Web::Pages->addPageLinks('icons', {'PLUGIN_CONTEXTSTATS' => 'plugins/ContextStats/html/images/contextstats_icon_svg.png'});
		}
	}

	registerContextMenuItems();

#	Slim::Control::Request::addDispatch  C  Q  T
	Slim::Control::Request::addDispatch(['contextstats', 'plcontrolcmd', '_cmd', '_listtype', '_ids'], [1, 0, 1, \&_multipleIdsPLcontrol]);
	Slim::Control::Request::addDispatch(['contextstats', 'jiveyearmenu', '_context', '_listtype', '_objectid', '_objectname'], [1, 0, 1, \&_jiveYearOrDecadeSel]);
	Slim::Control::Request::addDispatch(['contextstats', 'jivestatslistsmenu', '_context', '_listtype', '_objectid', '_objectname', '_usedecade'], [1, 0, 1, \&_jiveStatsListsMenu]);
	Slim::Control::Request::addDispatch(['contextstats', 'jiveitemsmenu', '_selectedlistid', '_context', '_listtype', '_objectid', '_objectname', '_usedecade'], [1, 0, 1, \&_jiveGetItems]);
	Slim::Control::Request::addDispatch(['contextstats', 'jiveactionsmenu', '_ids', '_listtype', '_multiple'], [0, 1, 1, \&_jiveActionsMenu]);
	Slim::Control::Request::addDispatch(['contextstats', 'jivebrowseall'], [1, 0, 1, \&_jiveBrowseAll]);
}

sub postinitPlugin {
	my $class = shift;
	$apc_enabled = Slim::Utils::PluginManager->isEnabled('Plugins::AlternativePlayCount::Plugin');
	main::DEBUGLOG && $log->is_debug && $log->debug('Plugin "Alternative Play Count" is enabled') if $apc_enabled;

	if (Slim::Utils::PluginManager->isEnabled('Plugins::MusicArtistInfo::Plugin')) {
		$MAIprefs = preferences('plugin.musicartistinfo');
	}
	registerJiveMenu($class) if $prefs->get('browsemenuitem');
}

sub initPrefs {
	$prefs->init({
		useapcvalues => 1,
		listlimit => 50,
		min_album_tracks => 1,
		contextmenuposition => 2,
		displayratingchar => 1,
		showyear => 1,
		displayxtraline => 1,
	});
	$prefs->setValidate({'validator' => 'intlimit', 'low' => 1, 'high' => 100}, 'min_album_tracks');
	$prefs->setValidate({'validator' => 'intlimit', 'low' => 5, 'high' => 500}, 'listlimit');

	$prefs->setChange(sub {
		my $pos = ($prefs->get('contextmenuposition') && $prefs->get('contextmenuposition') == 1) ? 'aaa' : 'zzz';
		my @contextmenus = ('contextstatsalbumtracks', 'contextstatsartisttracks', 'contextstatsartistalbums', 'contextstatsgenretracks', 'contextstatsgenrealbums', 'contextstatsgenreartists', 'contextstatsyeartracks', 'contextstatsyearalbums', 'contextstatsyearartists', 'contextstatsplaylisttracks', 'contextstatsplaylistalbums', 'contextstatsplaylistartists');
		foreach (@contextmenus) {
			Slim::Menu::SystemInfo->deregisterInfoProvider($pos.$_);
		}
		registerContextMenuItems();
	}, 'contextmenuposition');

	$listTypes = {
		#reqstats keys: 'added', 'playCount', 'lastPlayed', 'rating', 'skipCount', 'lastSkipped', 'dynPSval'
		'LastPlayed' => {
			id => 'LastPlayed',
			name => string('PLUGIN_CONTEXTSTATS_LASTPLAYED'),
			apc => 0,
			reqstats => {'lastPlayed' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 1
		},
		'LastSkipped' => {
			id => 'LastSkipped',
			name => string('PLUGIN_CONTEXTSTATS_LASTSKIPPED'),
			apc => 1,
			reqstats => {'lastSkipped' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 2
		},
		'FirstPlayed' => {
			id => 'FirstPlayed',
			name => string('PLUGIN_CONTEXTSTATS_FIRSTPLAYED'),
			apc => 0,
			reqstats => {'lastPlayed' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1},
			sortorder => 3
		},
		'LastAdded' => {
			id => 'LastAdded',
			name => string('PLUGIN_CONTEXTSTATS_LASTADDED'),
			apc => 0,
			reqstats => {'added' => 1},
			tracksvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1},
			sortorder => 4
		},
		'LeastPlayed' => {
			id => 'LeastPlayed',
			name => string('PLUGIN_CONTEXTSTATS_LEASTPLAYED'),
			apc => 0,
			reqstats => {'playCount' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1},
			sortorder => 5
		},
		'LeastPlayedLastAdded' => {
			id => 'LeastPlayedLastAdded',
			name => string('PLUGIN_CONTEXTSTATS_LEASTPLAYEDLASTADDED'),
			apc => 0,
			reqstats => {'playCount' => 1, 'added' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1},
			sortorder => 6
		},
		'LeastPlayedNotRecentlyAdded' => {
			id => 'LeastPlayedNotRecentlyAdded',
			name => string('PLUGIN_CONTEXTSTATS_LEASTPLAYEDNOTRECENTLYADDED'),
			apc => 0,
			reqstats => {'playCount' => 1, 'added' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1},
			sortorder => 7
		},
		'LeastSkipped' => {
			id => 'LeastSkipped',
			name => string('PLUGIN_CONTEXTSTATS_LEASTSKIPPED'),
			apc => 1,
			reqstats => {'skipCount' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 8
		},
		'MostPlayed' => {
			id => 'MostPlayed',
			name => string('PLUGIN_CONTEXTSTATS_MOSTPLAYED'),
			apc => 0,
			reqstats => {'playCount' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 9
		},
		'MostPlayedLastPlayed' => {
			id => 'MostPlayedLastPlayed',
			name => string('PLUGIN_CONTEXTSTATS_MOSTPLAYEDLASTPLAYED'),
			apc => 0,
			reqstats => {'playCount' => 1, 'lastPlayed' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 10
		},
		'MostPlayedNotRecentlyPlayed' => {
			id => 'MostPlayedNotRecentlyPlayed',
			name => string('PLUGIN_CONTEXTSTATS_MOSTPLAYEDNOTRECENTLYPLAYED'),
			apc => 0,
			reqstats => {'playCount' => 1, 'lastPlayed' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 11
		},
		'MostPlayedLastAdded' => {
			id => 'MostPlayedLastAdded',
			name => string('PLUGIN_CONTEXTSTATS_MOSTPLAYEDLASTADDED'),
			apc => 0,
			reqstats => {'playCount' => 1, 'added' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 12
		},
		'MostPlayedNotRecentlyAdded' => {
			id => 'MostPlayedNotRecentlyAdded',
			name => string('PLUGIN_CONTEXTSTATS_MOSTPLAYEDNOTRECENTLYADDED'),
			apc => 0,
			reqstats => {'playCount' => 1, 'added' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 13
		},
		'MostSkipped' => {
			id => 'MostSkipped',
			name => string('PLUGIN_CONTEXTSTATS_MOSTSKIPPED'),
			apc => 1,
			reqstats => {'skipCount' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 14
		},
		'PartlyPlayed' => {
			id => 'PartlyPlayed',
			name => string('PLUGIN_CONTEXTSTATS_PARTLYPLAYED'),
			apc => 0,
			reqstats => {'playCount' => 1},
			tracksvalidcontext => {},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1},
			sortorder => 15
		},
		'NeverPlayed' => {
			id => 'NeverPlayed',
			name => string('PLUGIN_CONTEXTSTATS_NEVERPLAYED'),
			apc => 0,
			reqstats => {'playCount' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1},
			sortorder => 16
		},
		'SpecificRating10' => {
			id => 'SpecificRating10',
			name => string('PLUGIN_CONTEXTSTATS_SPECIFICRATING_10'),
			apc => 0,
			reqstats => {'rating' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 17
		},
		'SpecificRating20' => {
			id => 'SpecificRating20',
			name => string('PLUGIN_CONTEXTSTATS_SPECIFICRATING_20'),
			apc => 0,
			reqstats => {'rating' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 18
		},
		'SpecificRating30' => {
			id => 'SpecificRating30',
			name => string('PLUGIN_CONTEXTSTATS_SPECIFICRATING_30'),
			apc => 0,
			reqstats => {'rating' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 19
		},
		'SpecificRating40' => {
			id => 'SpecificRating40',
			name => string('PLUGIN_CONTEXTSTATS_SPECIFICRATING_40'),
			apc => 0,
			reqstats => {'rating' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 20
		},
		'SpecificRating50' => {
			id => 'SpecificRating50',
			name => string('PLUGIN_CONTEXTSTATS_SPECIFICRATING_50'),
			apc => 0,
			reqstats => {'rating' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 21
		},
		'SpecificRating60' => {
			id => 'SpecificRating60',
			name => string('PLUGIN_CONTEXTSTATS_SPECIFICRATING_60'),
			apc => 0,
			reqstats => {'rating' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 22
		},
		'SpecificRating70' => {
			id => 'SpecificRating70',
			name => string('PLUGIN_CONTEXTSTATS_SPECIFICRATING_70'),
			apc => 0,
			reqstats => {'rating' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 23
		},
		'SpecificRating80' => {
			id => 'SpecificRating80',
			name => string('PLUGIN_CONTEXTSTATS_SPECIFICRATING_80'),
			apc => 0,
			reqstats => {'rating' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 24
		},
		'SpecificRating90' => {
			id => 'SpecificRating90',
			name => string('PLUGIN_CONTEXTSTATS_SPECIFICRATING_90'),
			apc => 0,
			reqstats => {'rating' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 25
		},
		'SpecificRating100' => {
			id => 'SpecificRating100',
			name => string('PLUGIN_CONTEXTSTATS_SPECIFICRATING_100'),
			apc => 0,
			reqstats => {'rating' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 26
		},
		'TopRated' => {
			id => 'TopRated',
			name => string('PLUGIN_CONTEXTSTATS_TOPRATED'),
			apc => 0,
			reqstats => {'rating' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 27
		},
		'TopDPSV' => {
			id => 'TopDPSV',
			name => string('PLUGIN_CONTEXTSTATS_TOPDPSV'),
			apc => 1,
			reqstats => {'dynPSval' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 28
		},
		'TopRatedLastPlayed' => {
			id => 'TopRatedLastPlayed',
			name => string('PLUGIN_CONTEXTSTATS_TOPRATEDLASTPLAYED'),
			apc => 0,
			reqstats => {'rating' => 1, 'lastPlayed' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 29
		},
		'TopRatedNotRecentlyPlayed' => {
			id => 'TopRatedNotRecentlyPlayed',
			name => string('PLUGIN_CONTEXTSTATS_TOPRATEDNOTRECENTLYPLAYED'),
			apc => 0,
			reqstats => {'rating' => 1, 'lastPlayed' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 30
		},
		'TopRatedLastAdded' => {
			id => 'TopRatedLastAdded',
			name => string('PLUGIN_CONTEXTSTATS_TOPRATEDLASTADDED'),
			apc => 0,
			reqstats => {'rating' => 1, 'added' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 31
		},
		'TopRatedNotRecentlyAdded' => {
			id => 'TopRatedNotRecentlyAdded',
			name => string('PLUGIN_CONTEXTSTATS_TOPRATEDNOTRECENTLYADDED'),
			apc => 0,
			reqstats => {'rating' => 1, 'added' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 32
		},
		'NotCompletelyRated' => {
			id => 'NotCompletelyRated',
			name => string('PLUGIN_CONTEXTSTATS_NOTCOMPLETELYRATED'),
			apc => 0,
			reqstats => {'rating' => 1},
			tracksvalidcontext => {},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 33
		},
		'NotCompletelyRatedLastPlayed' => {
			id => 'NotCompletelyRatedLastPlayed',
			name => string('PLUGIN_CONTEXTSTATS_NOTCOMPLETELYRATEDLASTPLAYED'),
			apc => 0,
			reqstats => {'rating' => 1, 'lastPlayed' => 1},
			tracksvalidcontext => {},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 34
		},
		'NotCompletelyRatedNotRecentlyPlayed' => {
			id => 'NotCompletelyRatedNotRecentlyPlayed',
			name => string('PLUGIN_CONTEXTSTATS_NOTCOMPLETELYRATEDNOTRECENTLYPLAYED'),
			apc => 0,
			reqstats => {'rating' => 1, 'lastPlayed' => 1},
			tracksvalidcontext => {},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 35
		},
		'NotCompletelyRatedLastAdded' => {
			id => 'NotCompletelyRatedLastAdded',
			name => string('PLUGIN_CONTEXTSTATS_NOTCOMPLETELYRATEDLASTADDED'),
			apc => 0,
			reqstats => {'rating' => 1, 'added' => 1},
			tracksvalidcontext => {},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 36
		},
		'NotCompletelyRatedNotRecentlyAdded' => {
			id => 'NotCompletelyRatedNotRecentlyAdded',
			name => string('PLUGIN_CONTEXTSTATS_NOTCOMPLETELYRATEDNOTRECENTLYADDED'),
			apc => 0,
			reqstats => {'rating' => 1, 'added' => 1},
			tracksvalidcontext => {},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 37
		},
		'NotRated' => {
			id => 'NotRated',
			name => string('PLUGIN_CONTEXTSTATS_NOTRATED'),
			apc => 0,
			reqstats => {'rating' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 38
		},
		'NotRatedLastPlayed' => {
			id => 'NotRatedLastPlayed',
			name => string('PLUGIN_CONTEXTSTATS_NOTRATEDLASTPLAYED'),
			apc => 0,
			reqstats => {'rating' => 1, 'lastPlayed' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 39
		},
		'NotRatedNotRecentlyPlayed' => {
			id => 'NotRatedNotRecentlyPlayed',
			name => string('PLUGIN_CONTEXTSTATS_NOTRATEDNOTRECENTLYPLAYED'),
			apc => 0,
			reqstats => {'rating' => 1, 'lastPlayed' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 40
		},
		'NotRatedLastAdded' => {
			id => 'NotRatedLastAdded',
			name => string('PLUGIN_CONTEXTSTATS_NOTRATEDLASTADDED'),
			apc => 0,
			reqstats => {'rating' => 1, 'added' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 41
		},
		'NotRatedNotRecentlyAdded' => {
			id => 'NotRatedNotRecentlyAdded',
			name => string('PLUGIN_CONTEXTSTATS_NOTRATEDNOTRECENTLYADDED'),
			apc => 0,
			reqstats => {'rating' => 1, 'added' => 1},
			tracksvalidcontext => {'artist' => 1, 'album' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			albumsvalidcontext => {'artist' => 1, 'genre' => 1, 'year' => 1, 'playlist' => 1},
			artistsvalidcontext => {'genre' => 1, 'year' => 1, 'playlist' => 1},
			sortorder => 42
		},
	};
}

sub registerContextMenuItems {
	my ($position, $genPos);
	if ($prefs->get('contextmenuposition') && $prefs->get('contextmenuposition') == 1) {
		$position = 'aaa'; $genPos = 'top';
	} else {
		$position = 'zzz'; $genPos = 'bottom';
	}

	Slim::Menu::AlbumInfo->registerInfoProvider($position.contextstatsalbumtracks => (
		after => $genPos,
		func => sub {
			return objectInfoHandler('album', 'tracks', @_);
		},
	));
	Slim::Menu::ArtistInfo->registerInfoProvider($position.contextstatsartisttracks => (
		after => $genPos,
		func => sub {
			return objectInfoHandler('artist', 'tracks', @_);
		},
	));
	Slim::Menu::ArtistInfo->registerInfoProvider($position.contextstatsartistalbums => (
		after => $position.'contextstatsartisttracks',
		func => sub {
			return objectInfoHandler('artist', 'albums', @_);
		},
	));
	Slim::Menu::GenreInfo->registerInfoProvider($position.contextstatsgenretracks => (
		after => $genPos,
		func => sub {
			return objectInfoHandler('genre', 'tracks', @_);
		},
	));
	Slim::Menu::GenreInfo->registerInfoProvider($position.contextstatsgenrealbums => (
		after => $position.'contextstatsgenretracks',
		func => sub {
			return objectInfoHandler('genre', 'albums', @_);
		},
	));
	Slim::Menu::GenreInfo->registerInfoProvider($position.contextstatsgenreartists => (
		after => $position.'contextstatsgenrealbums',
		func => sub {
			return objectInfoHandler('genre', 'artists', @_);
		},
	));
	Slim::Menu::YearInfo->registerInfoProvider($position.contextstatsyeartracks => (
		after => $genPos,
		func => sub {
			return objectInfoHandler('year', 'tracks', @_);
		},
	));
	Slim::Menu::YearInfo->registerInfoProvider($position.contextstatsyearalbums => (
		after => $position.'contextstatsyeartracks',
		func => sub {
			return objectInfoHandler('year', 'albums', @_);
		},
	));
	Slim::Menu::YearInfo->registerInfoProvider($position.contextstatsyearartists => (
		after => $position.'contextstatsyearalbums',
		func => sub {
			return objectInfoHandler('year', 'artists', @_);
		},
	));
	Slim::Menu::PlaylistInfo->registerInfoProvider($position.contextstatsplaylisttracks => (
		after => $genPos,
		func => sub {
			return objectInfoHandler('playlist', 'tracks', @_);
		},
	));
	Slim::Menu::PlaylistInfo->registerInfoProvider($position.contextstatsplaylistalbums => (
		after => $position.'contextstatsplaylisttracks',
		func => sub {
			return objectInfoHandler('playlist', 'albums', @_);
		},
	));
	Slim::Menu::PlaylistInfo->registerInfoProvider($position.contextstatsplaylistartists => (
		after => $position.'contextstatsplaylistalbums',
		func => sub {
			return objectInfoHandler('playlist', 'artists', @_);
		},
	));
}

sub objectInfoHandler {
	my ($context, $listType, $client, $url, $obj, $remoteMeta, $tags) = @_;
	$tags ||= {};
	main::DEBUGLOG && $log->is_debug && $log->debug('context = '.$context.' ## $listType = '.$listType.' ## url = '.Data::Dump::dump($url));

	if (Slim::Music::Import->stillScanning) {
		$log->warn('Warning: not available until library scan is completed');
		return;
	}

	my $objectID = ($context eq 'year' || $context eq 'decade') ? $obj : $obj->id;
	my $objectName;
	if ($context eq 'year' || $context eq 'decade') {
		$objectName = "".$obj;
	} else {
		$objectName = $obj->name;
	}

	my $menuItemTitle;
	$menuItemTitle = string('PLUGIN_CONTEXTSTATS_LISTITEMS_ARTISTS') if $listType eq 'artists';
	$menuItemTitle = string('PLUGIN_CONTEXTSTATS_LISTITEMS_ALBUMS') if $listType eq 'albums';
	$menuItemTitle = string('PLUGIN_CONTEXTSTATS_LISTITEMS_TRACKS') if $listType eq 'tracks';
	$menuItemTitle .= ' '.string('PLUGIN_CONTEXTSTATS_HEADER');
	if ($tags->{menuMode}) {
		return {
			type => 'redirect',
			name => $menuItemTitle,
			jive => {
				actions => {
					go => {
						player => 0,
						cmd => ['contextstats', ($context eq 'year' ? 'jiveyearmenu' : 'jivestatslistsmenu'), $context, $listType, $objectID, escape($objectName)],
					},
				}
			},
			favorites => 0,
		};
	} else {
		my $item = {
			type => 'text',
			name => $menuItemTitle,
			context => $context,
			listtype => $listType,
			objectname => escape($objectName),
			objectid => $objectID,
			web => {
				'type' => 'htmltemplate',
				'value' => 'plugins/ContextStats/listlink.html'
			},
		};
		return $item;
	}
}


sub _statsListsMenuWeb {
	my ($client, $params) = @_;
	main::DEBUGLOG && $log->is_debug && $log->debug("\ncontext = ".$params->{'context'}."\nlistType = ".$params->{'listtype'}."\nobjectid = ".Data::Dump::dump($params->{'objectid'})."\nobjectname = ".Data::Dump::dump($params->{'objectname'})."\nselectedlistid = ".Data::Dump::dump($params->{'selectedlistid'})."\nusedecade = ".Data::Dump::dump($params->{'usedecade'})."\naction = ".Data::Dump::dump($params->{'action'})."\nactionTrackIDs = ".Data::Dump::dump($params->{'actionTrackIDs'})."\n\n");

	## execute action if action and action track id(s) provided
	my $action = $params->{'action'};
	my $actionTrackIDs = $params->{'actiontrackids'};
	my $listType = $params->{'listtype'};

	if ($action && ($action eq 'load' || $action eq 'insert' || $action eq 'add') && $actionTrackIDs) {
		$log->info('action part');
		$client->execute(['contextstats', 'plcontrolcmd', $action, $listType, 'ids:'.$actionTrackIDs]);
	}

	$params->{'decade'} = (floor($params->{'objectid'}/10) * 10 + 0).'s' if ($params->{'context'} eq 'year');
	$params->{'apcenabled'} = $apc_enabled;
	$params->{'displayxtraline'} = $prefs->get('displayxtraline');
	my $host = $params->{host} || (Slim::Utils::Network::serverAddr() . ':' . preferences('server')->get('httpport'));
	$params->{'thishost'} = 'http://' . $host;

	if ($params->{'selectedlistid'} && $params->{'context'} && $params->{'listtype'} && ($params->{'objectid'} || $params->{'context'} eq 'all')) {
		my $matchingItems = getItemsForStats($client, 0, $params->{'context'}, $params->{'listtype'}, $params->{'objectid'}, $params->{'selectedlistid'}, $params->{'usedecade'});
		#$log->info('returned items = '.Data::Dump::dump($matchingItems));

		my @allItemIDs = ();
		foreach my $thisItem (@{$matchingItems}) {
			my $itemID = $thisItem->{'id'};
			push @allItemIDs, $itemID;
		}
		my $listalltrackids = join (',', @allItemIDs);

		my $itemCount = scalar @{$matchingItems};
		$params->{'itemcount'} = $itemCount;
		$params->{'allitemids'} = $listalltrackids;
		$params->{'statsitems'} = $itemCount > 0 ? $matchingItems : undef;
	}

	$params->{'listTypes'} = getListsForContext($params->{'listtype'}, $params->{'context'});
	return Slim::Web::HTTP::filltemplatefile('plugins/ContextStats/contextstatslists.html', $params);
}

sub _statsListsMenuWebAll {
	my ($client, $params) = @_;
	$params->{'lists'} = {
		1 => {'type' => 'tracks', 'name' => string('PLUGIN_CONTEXTSTATS_LISTITEMS_TRACKS')},
		2 => {'type' => 'albums', 'name' => string('PLUGIN_CONTEXTSTATS_LISTITEMS_ALBUMS')},
		3 => {'type' => 'artists', 'name' => string('PLUGIN_CONTEXTSTATS_LISTITEMS_ARTISTS')},
	};
	return Slim::Web::HTTP::filltemplatefile('plugins/ContextStats/browseall.html', $params);
}


sub _jiveYearOrDecadeSel {
	my $request = shift;
	main::DEBUGLOG && $log->is_debug && $log->debug('request params = '.Data::Dump::dump($request->getParamsCopy()));

	if ($request->isNotCommand([['contextstats'],['jiveyearmenu']])) {
		$request->setStatusBadDispatch();
		$log->warn('incorrect command');
		return;
	}

	my $client = $request->client();
	if (!defined $client) {
		$request->setStatusNeedsClient();
		return;
	}

	my $context = _getRequestParamVal($request, 'context');
	my $listType = _getRequestParamVal($request, 'listtype');
	my $objectID = _getRequestParamVal($request, 'objectid');
	my $objectName = _getRequestParamVal($request, 'objectname');
	my $decade = (floor($objectID/10) * 10 + 0).'s';

	if (defined($context) && defined($listType) && defined($objectID) && defined($objectName)) {
		$request->addResult('window', {menustyle => 'album'});
		my $actionsYear = {
			'go' => {
				'player' => 0,
				'cmd' => ['contextstats', 'jivestatslistsmenu', $context, $listType, $objectID, $objectName, 0],
			},
		};

		$request->addResultLoop('item_loop', 0, 'type', 'redirect');
		$request->addResultLoop('item_loop', 0, 'actions', $actionsYear);
		$request->addResultLoop('item_loop', 0, 'text', string('PLUGIN_CONTEXTSTATS_LISTITEMS_USEYEAR').' ('.$objectName.')');

		my $actionsDecade = {
			'go' => {
				'player' => 0,
				'cmd' => ['contextstats', 'jivestatslistsmenu', $context, $listType, $objectID, $objectName, 1],
			},
		};
		$request->addResultLoop('item_loop', 1, 'type', 'redirect');
		$request->addResultLoop('item_loop', 1, 'actions', $actionsDecade);
		$request->addResultLoop('item_loop', 1, 'text', string('PLUGIN_CONTEXTSTATS_LISTITEMS_USEDECADE').' ('.$decade.')');

		$request->addResult('offset', 0);
		$request->addResult('count', 2);

	} else {
		$request->setStatusBadParams();
	}
	$request->setStatusDone();
}

sub _jiveStatsListsMenu {
	my $request = shift;
	main::DEBUGLOG && $log->is_debug && $log->debug('request params = '.Data::Dump::dump($request->getParamsCopy()));

	if ($request->isNotCommand([['contextstats'],['jivestatslistsmenu']])) {
		$request->setStatusBadDispatch();
		$log->warn('incorrect command');
		return;
	}

	my $client = $request->client();
	if (!defined $client) {
		$request->setStatusNeedsClient();
		return;
	}

	my $context = _getRequestParamVal($request, 'context');
	my $listType = _getRequestParamVal($request, 'listtype');
	my $objectID = _getRequestParamVal($request, 'objectid', 1);
	my $objectName = _getRequestParamVal($request, 'objectname', 1);
	my $useDecade = _getRequestParamVal($request, 'usedecade', 1);
	if ($context && $listType && (($objectID && defined($objectName)) || $context eq 'all')) {
		my $validListTypes = getListsForContext($listType, $context);

		my %menuStyle = ();
		$menuStyle{'titleStyle'} = 'mymusic';
		$menuStyle{'menuStyle'} = 'album';
		$request->addResult('window',\%menuStyle);
		my $cnt = 0;

		foreach my $thisList (sort { $validListTypes->{$a}->{'sortorder'} <=> $validListTypes->{$b}->{'sortorder'}; } keys %{$validListTypes}) {
			my $actions = {
				'go' => {
					'player' => 0,
					'cmd' => ['contextstats', 'jiveitemsmenu', $validListTypes->{$thisList}{'id'}, $context, $listType, $objectID, $objectName, $useDecade],
				},
			};
			$request->addResultLoop('item_loop', $cnt, 'type', 'redirect');
			$request->addResultLoop('item_loop', $cnt, 'actions', $actions);
			$request->addResultLoop('item_loop', $cnt, 'text', $validListTypes->{$thisList}{'name'});
			$cnt++;
		}
		$request->addResult('offset', 0);
		$request->addResult('count', $cnt);
	} else {
		$request->setStatusBadParams();
	}
	$request->setStatusDone();
}

sub _jiveGetItems {
	my $request = shift;
	main::DEBUGLOG && $log->is_debug && $log->debug('request params = '.Data::Dump::dump($request->getParamsCopy()));

	if ($request->isNotCommand([['contextstats'],['jiveitemsmenu']])) {
		$request->setStatusBadDispatch();
		$log->warn('incorrect command');
		return;
	}

	my $client = $request->client();
	if (!defined $client) {
		$request->setStatusNeedsClient();
		return;
	}

	my $selectedListID = _getRequestParamVal($request, 'selectedlistid');
	my $context = _getRequestParamVal($request, 'context');
	my $listType = _getRequestParamVal($request, 'listtype');
	my $objectID = _getRequestParamVal($request, 'objectid', 1);
	my $objectName = _getRequestParamVal($request, 'objectname', 1);

	if (defined($selectedListID) && defined($context) && defined($listType) && (defined($objectID) || $context eq 'all')) {
		my $useDecade = _getRequestParamVal($request, 'usedecade', 1);
		my $matchingItems = getItemsForStats($client, 1, $context, $listType, $objectID, $selectedListID, $useDecade);
		#$log->info('returned items = '.Data::Dump::dump($matchingItems));

		my @allItemIDs = ();
		my $itemCount = scalar(@{$matchingItems});
		if ($itemCount > 0) {
			my $cnt = ($itemCount > 1) ? 1 : 0;

			foreach my $thisItem (@{$matchingItems}) {
				push @allItemIDs, $thisItem->{'id'};

				my $returntext = '';
				my $actions = {};
				my $sepChar = HTML::Entities::decode_entities('&#x2022;'); # "bullet" - HTML Entity (hex): &#x2022;

				if ($listType eq 'albums') {
					if ($thisItem->{'artworkid'}) {
						$request->addResultLoop('item_loop', $cnt, 'icon-id', $thisItem->{'artworkid'});
					} else {
						$request->addResultLoop('item_loop', $cnt, 'icon', 'plugins/ContextStats/html/images/coverplaceholder.png');
					}
					# id, albumtitle, year, artworkid, artistID, artistname, rating, playcount, skipcount, dpsv
					$returntext = $thisItem->{'albumtitle'};
					$returntext .= ' ('.$thisItem->{'year'}.')' if $prefs->get('showyear') && $thisItem->{'year'};
					$returntext .= "\n".trimStringLength($thisItem->{'artistname'}, 42).' '.$sepChar.' ';
					$returntext .= string('PLUGIN_CONTEXTSTATS_LISTITEMS_RATING_SHORT').': '.$thisItem->{'rating'}.' '.$sepChar.' '.string('PLUGIN_CONTEXTSTATS_LISTITEMS_PLAYCOUNT_SHORT').': '.$thisItem->{'playcount'};
					$returntext .= ' '.$sepChar.' '.string('PLUGIN_CONTEXTSTATS_LISTITEMS_SKIPCOUNT_SHORT').': '.$thisItem->{'skipcount'}.' '.$sepChar.' '.string('PLUGIN_CONTEXTSTATS_LISTITEMS_DPSV').': '.$thisItem->{'dpsv'} if $apc_enabled;
					$actions = {
						'go' => {
							'player' => 0,
							'cmd' => ['contextstats', 'jiveactionsmenu', $thisItem->{'id'}, $listType],
						},
					};
				}

				if ($listType eq 'artists') {
					# id, artistname, artistimage, rating, playcount, skipcount, dpsv
					my $artistImgUrl;
					if ($thisItem->{'artistimage'}) {
						$artistImgUrl = $thisItem->{'artistimage'}.'/image_50x50_o'; ## srcset="% webroot %][% item.artistimage %]/cover_100x100_o 2x"
					} else {
						$artistImgUrl = 'plugins/ContextStats/html/images/artist.png'
					}
					$request->addResultLoop('item_loop', $cnt, 'icon', $artistImgUrl);

					$returntext = $thisItem->{'artistname'};
					$returntext .= "\n".string('PLUGIN_CONTEXTSTATS_LISTITEMS_RATING_SHORT').': '.$thisItem->{'rating'}.' '.$sepChar.' '.string('PLUGIN_CONTEXTSTATS_LISTITEMS_PLAYCOUNT_SHORT').': '.$thisItem->{'playcount'};
					$returntext .= ' '.$sepChar.' '.string('PLUGIN_CONTEXTSTATS_LISTITEMS_SKIPCOUNT_SHORT').': '.$thisItem->{'skipcount'}.' '.$sepChar.' '.string('PLUGIN_CONTEXTSTATS_LISTITEMS_DPSV').': '.$thisItem->{'dpsv'} if $apc_enabled;

					$actions = {
						'go' => {
							'player' => 0,
							'cmd' => ['contextstats', 'jiveactionsmenu', $thisItem->{'id'}, $listType],
						},
					};
				}

				if ($listType eq 'tracks') {
					if ($thisItem->{'artworkid'}) {
						$request->addResultLoop('item_loop', $cnt, 'icon-id', $thisItem->{'artworkid'});
					} else {
						$request->addResultLoop('item_loop', $cnt, 'icon', 'plugins/ContextStats/html/images/coverplaceholder.png');
					}
					# id, tracktitle, year, albumID, albumtitle, artworkid, artistID, artistname, rating, playcount, skipcount, dpsv
					$returntext = $thisItem->{'tracktitle'}."\n".trimStringLength($thisItem->{'artistname'}, 42).' '.$sepChar.' ';
					$returntext .= string('PLUGIN_CONTEXTSTATS_LISTITEMS_RATING_SHORT').': '.$thisItem->{'rating'}.' '.$sepChar.' '.string('PLUGIN_CONTEXTSTATS_LISTITEMS_PLAYCOUNT_SHORT').': '.$thisItem->{'playcount'};
					$returntext .= ' '.$sepChar.' '.string('PLUGIN_CONTEXTSTATS_LISTITEMS_SKIPCOUNT_SHORT').': '.$thisItem->{'skipcount'}.' '.$sepChar.' '.string('PLUGIN_CONTEXTSTATS_LISTITEMS_DPSV').': '.$thisItem->{'dpsv'} if $apc_enabled;
					$actions = {
						'go' => {
							'player' => 0,
							'cmd' => ['contextstats', 'jiveactionsmenu', $thisItem->{'id'}, $listType],
						},
					};
				}

				$request->addResultLoop('item_loop', $cnt, 'type', 'redirect');
				$request->addResultLoop('item_loop', $cnt, 'actions', $actions);
				$request->addResultLoop('item_loop', $cnt, 'text', $returntext);
				$cnt++;
			}
			my %menuStyle = ();
			$menuStyle{'titleStyle'} = 'mymusic';
			$menuStyle{'menuStyle'} = 'album';
			$menuStyle{'windowStyle'} = 'icon_list';

			if ($itemCount > 1) {
				my $listallitemids = join (',', @allItemIDs);
				my $actions = {
					'go' => {
						'player' => 0,
						'cmd' => ['contextstats', 'jiveactionsmenu', 'ids:'.$listallitemids, $listType, 1],
					},
				};
				my $returnText = string('PLUGIN_CONTEXTSTATS_LISTITEMS_ALLTRACKS');
				$returnText = string('PLUGIN_CONTEXTSTATS_LISTITEMS_ALLALBUMS') if $listType eq 'albums';
				$returnText = string('PLUGIN_CONTEXTSTATS_LISTITEMS_ALLARTISTS') if $listType eq 'artists';

				$request->addResultLoop('item_loop', 0, 'type', 'redirect');
				$request->addResultLoop('item_loop', 0, 'actions', $actions);
				$request->addResultLoop('item_loop', 0, 'icon', 'plugins/ContextStats/html/images/allsongs.png');
				$request->addResultLoop('item_loop', 0, 'text', $returnText.' ('.$itemCount.')');
				$cnt++;
			}
			$request->addResult('window',\%menuStyle);
			$request->addResult('offset', 0);
			$request->addResult('count', $cnt);

		} else {
			$request->addResult('window', {
				'menustyle' => 'album',
				'titleStyle' => 'mymusic',
			});
			$request->addResultLoop('item_loop', 0, 'type', 'redirect');
			$request->addResultLoop('item_loop', 0, 'text', string('PLUGIN_CONTEXTSTATS_LISTITEMS_NOITEMSFOUND'));
			$request->addResultLoop('item_loop', 0, 'style', 'itemNoAction');
			$request->addResultLoop('item_loop', 0, 'action', 'none');
			$request->addResult('offset', 0);
			$request->addResult('count', 1);
		}

	} else {
		$request->setStatusBadParams();
	}
	$request->setStatusDone();
}

sub _jiveActionsMenu {
	my $request = shift;
	main::DEBUGLOG && $log->is_debug && $log->debug('request params = '.Data::Dump::dump($request->getParamsCopy()));

	if (!$request->isQuery([['contextstats'],['jiveactionsmenu']])) {
		$log->warn('incorrect command');
		$request->setStatusBadDispatch();
		return;
	}

	my $ids = _getRequestParamVal($request, 'ids');
	my $listType = _getRequestParamVal($request, 'listtype');
	my $multiple = _getRequestParamVal($request, 'multiple');

	$request->addResult('window', {
		menustyle => 'album',
	});

	my $actionsmenuitems = [
		{
			itemtext => string('PLUGIN_CONTEXTSTATS_JIVEACTIONMENU_PLAYNOW'),
			itemcmd => 'load'
		},
		{
			itemtext => string('PLUGIN_CONTEXTSTATS_JIVEACTIONMENU_PLAYNEXT'),
			itemcmd => 'insert'
		},
		{
			itemtext => string('PLUGIN_CONTEXTSTATS_JIVEACTIONMENU_APPEND'),
			itemcmd => 'add'
		}];

	my $cnt = 0;
	foreach my $menuitem (@{$actionsmenuitems}) {
		my $actions = {
				'player' => 0,
				'go' => {
					'cmd' => ['contextstats', 'plcontrolcmd', $menuitem->{'itemcmd'}, $listType, 'ids:'.$ids],
				},
				'player' => 0,
				'play' => {
					'cmd' => ['contextstats', 'plcontrolcmd', $menuitem->{'itemcmd'}, $listType, 'ids:'.$ids],
				}
		};

		$request->addResultLoop('item_loop', $cnt, 'nextWindow', 'parent');
		$request->addResultLoop('item_loop', $cnt, 'actions', $actions);
		$request->addResultLoop('item_loop', $cnt, 'text', $menuitem->{'itemtext'});
		$request->addResultLoop('item_loop', $cnt, 'style', 'itemplay');
		$cnt++;
	}
	$request->addResult('offset',0);
	$request->addResult('count',$cnt);
	$request->setStatusDone();
}

sub registerJiveMenu {
	my ($class, $client) = @_;

	my @menuItems = (
		{
			text => Slim::Utils::Strings::string('PLUGIN_CONTEXTSTATS'),
			weight => 81,
			id => 'contextstats',
			menuIcon => 'plugins/ContextStats/html/images/contextstats_icon_svg.png',
			window => {titleStyle => 'mymusic', 'icon-id' => $class->_pluginDataFor('icon')},
			actions => {
				go => {
					cmd => ['contextstats', 'jivebrowseall'],
				},
			},
		},
	);
	Slim::Control::Jive::registerPluginMenu(\@menuItems, 'myMusic') if $prefs->get('browsemenuitem');
}

sub _jiveBrowseAll {
	my $request = shift;
	main::DEBUGLOG && $log->is_debug && $log->debug('request params = '.Data::Dump::dump($request->getParamsCopy()));

	if ($request->isNotCommand([['contextstats'],['jivebrowseall']])) {
		$log->warn('incorrect command');
		$request->setStatusBadDispatch();
		return;
	}
	my $client = $request->client();
	if (!defined $client) {
		$request->setStatusNeedsClient();
		return;
	}

	$request->addResult('window', {menustyle => 'album'});

	my @Ltypes = (
		{'type' => 'tracks', 'name' => string('PLUGIN_CONTEXTSTATS_LISTITEMS_TRACKS')},
		{'type' => 'albums', 'name' => string('PLUGIN_CONTEXTSTATS_LISTITEMS_ALBUMS')},
		{'type' => 'artists', 'name' => string('PLUGIN_CONTEXTSTATS_LISTITEMS_ARTISTS')},
	);


	my $cnt = 0;
	foreach my $thisType (@Ltypes) {
		my $actions = {
			'go' => {
				'player' => 0,
				'cmd' => ['contextstats', 'jivestatslistsmenu', 'all', $thisType->{'type'}, 0, 0, 0],
			},
		};

		$request->addResultLoop('item_loop', $cnt, 'type', 'redirect');
		$request->addResultLoop('item_loop', $cnt, 'actions', $actions);
		$request->addResultLoop('item_loop', $cnt, 'text', $thisType->{'name'});
		$cnt++
	}

	$request->addResult('offset', 0);
	$request->addResult('count', $cnt);
	$request->setStatusDone();
}


sub getListsForContext {
	my ($thisListType, $thisContext) = @_;

	my $recentlyAddedPeriod = $prefs->get('recentlyaddedperiod');
	my $recentlyPlayedPeriod = $prefs->get('recentlyplayedperiod');
	my $validListTypes = {};

	foreach my $thisItem (keys %{$listTypes}) {
		if ($thisListType eq 'tracks') {
			if ($thisContext eq 'all') {
				next if scalar keys %{$listTypes->{$thisItem}{'tracksvalidcontext'}} == 0;
			} else {
				next if !$listTypes->{$thisItem}{'tracksvalidcontext'}{$thisContext};
			}
		}
		if ($thisListType eq 'albums') {
			if ($thisContext eq 'all') {
				next if scalar keys %{$listTypes->{$thisItem}{'albumsvalidcontext'}} == 0;
			} else {
				next if !$listTypes->{$thisItem}{'albumsvalidcontext'}{$thisContext};
			}
		}
		if ($thisListType eq 'artists') {
			if ($thisContext eq 'all') {
				next if scalar keys %{$listTypes->{$thisItem}{'artistsvalidcontext'}} == 0;
			} else {
				next if !$listTypes->{$thisItem}{'artistsvalidcontext'}{$thisContext};
			}
		}
		next if lc($listTypes->{$thisItem}{'id'}) =~ 'recentlyadded' && !$recentlyAddedPeriod;
		next if lc($listTypes->{$thisItem}{'id'}) =~ 'recentlyplayed' && !$recentlyPlayedPeriod;
		next if $listTypes->{$thisItem}{'apc'} && !$apc_enabled;

		$validListTypes->{$thisItem} = $listTypes->{$thisItem};
	}

	main::DEBUGLOG && $log->is_debug && $log->debug('validListTypes = '.Data::Dump::dump(\%{$validListTypes}));
	main::DEBUGLOG && $log->is_debug && $log->debug('count all listTypes: '.scalar (keys %{$listTypes}));
	main::DEBUGLOG && $log->is_debug && $log->debug('count validListTypes: '.scalar (keys %{$validListTypes}));

	return $validListTypes;
}

sub getItemsForStats {
	my ($client, $jive, $context, $listType, $objectid, $selectedlistid, $useDecade) = @_;

	#reqstats keys: 'added', 'playCount', 'lastPlayed', 'rating', 'skipCount', 'lastSkipped', 'dynPSval'
	my $table = ($apc_enabled && $prefs->get('useapcvalues')) ? 'alternativeplaycount' : 'tracks_persistent';
	my $activeClientLibrary = Slim::Music::VirtualLibraries->getLibraryIdForClient($client);
	my $topratedMinRating = $prefs->get('topratedminrating');
	my $recentlyPlayedPeriod = $prefs->get('recentlyplayedperiod');
	my $recentlyAddedPeriod = $prefs->get('recentlyaddedperiod');
	my $VAid = Slim::Schema->variousArtistsObject->id;

	#### build sql query ####
	# select
	my $sql = "SELECT";
	if ($listType eq 'albums' || $listType eq 'artists') {
		$sql .= " albums.id, albums.title, albums.year, albums.artwork, contributor_track.contributor, contributors.name" if $listType eq 'albums';
		$sql .= " contributor_track.contributor, contributors.name" if $listType eq 'artists';
		$sql .= ", avg(ifnull(tracks_persistent.rating,0)) as avgrating";
		$sql .= ", avg(ifnull($table.playCount,0)) as avgcount";
		$sql .= ", avg(ifnull(alternativeplaycount.skipCount,0)) as avgskipcount" if $apc_enabled;
		$sql .= ", avg(ifnull(alternativeplaycount.dynPSval,0)) as avgDPSV" if $apc_enabled;
	} elsif ($listType eq 'tracks') {
		$sql .= " tracks.id, tracks.title, tracks.year, albums.id, albums.title, albums.artwork, contributor_track.contributor, contributors.name";
		$sql .= ", ifnull(tracks_persistent.rating,0) as trackrating";
		$sql .= ", ifnull($table.playCount,0) as trackpc";
		$sql .= ", ifnull(alternativeplaycount.skipCount,0) as trackskipcount" if $apc_enabled;
		$sql .= ", ifnull(alternativeplaycount.dynPSval,0) as trackDPSV" if $apc_enabled;
	}
	$sql .= ", max($table.lastPlayed) as maxlastplayed";
	$sql .= ", max(ifnull(alternativeplaycount.lastSkipped,0)) as maxlastskipped" if $apc_enabled;
	$sql .= ", max(tracks_persistent.added) as maxadded";
	$sql .= " from tracks";

	# joins
	$sql .= " join library_track on library_track.track = tracks.id and library_track.library = \"$activeClientLibrary\"" if (defined($activeClientLibrary) && $activeClientLibrary ne '');
	$sql .= " join contributor_track on tracks.id = contributor_track.track and contributor_track.role in (1,4,5,6) join contributors on contributor_track.contributor = contributors.id";
	$sql .= " and contributor_track.contributor = $objectid" if $context eq 'artist';
	$sql .= " join albums on tracks.album = albums.id" unless $listType eq 'artists';

	$sql .= " left join tracks_persistent on tracks.urlmd5 = tracks_persistent.urlmd5";
	$sql .= " left join alternativeplaycount on tracks.urlmd5 = alternativeplaycount.urlmd5" if $apc_enabled;

	$sql .= " join genre_track on tracks.id = genre_track.track and genre_track.genre = $objectid" if $context eq 'genre';
	$sql .= " join playlist_track on tracks.url = playlist_track.track and playlist_track.playlist = $objectid" if $context eq 'playlist';

	# where clauses
	$sql .= " WHERE tracks.audio = 1";

	if ($listType eq 'tracks') {
		$sql .= " and tracks.album = $objectid" if $context eq 'album';
		if ($context eq 'year') {
			if ($useDecade) {
				my $decade = floor($objectid/10) * 10 + 0;
				$sql .= " and tracks.year >= $decade and tracks.year <= ($decade + 9)";
			} else {
				$sql .= " and tracks.year = $objectid";
			}
		}
		if ($selectedlistid =~ /LastPlayed/ || $selectedlistid =~ /FirstPlayed/) {
			if ($selectedlistid =~ /LastPlayed/ && $recentlyPlayedPeriod) {
				$sql .= " and ($table.lastPlayed >= (select max(ifnull($table.lastPlayed,0)) from $table) - $recentlyPlayedPeriod)";
			} else {
				$sql .= " and $table.lastPlayed is not null";
			}
		}
		if ($selectedlistid =~ /NotRecentlyPlayed/ && $recentlyPlayedPeriod) {
			$sql .= " and ($table.lastPlayed < (select max(ifnull($table.lastPlayed,0)) from $table) - $recentlyPlayedPeriod)";
		}
		$sql .= " and (tracks_persistent.added >= (select max(tracks_persistent.added) from tracks_persistent) - $recentlyAddedPeriod)" if ($selectedlistid =~ /LastAdded/ && $recentlyAddedPeriod);
		$sql .= " and (tracks_persistent.added < (select max(tracks_persistent.added) from tracks_persistent) - $recentlyAddedPeriod)" if ($selectedlistid =~ /NotRecentlyAdded/ && $recentlyAddedPeriod);
		$sql .= " and $table.playCount is not null" if ($selectedlistid =~ /MostPlayed/ || $selectedlistid =~ /LeastPlayed/);
		$sql .= " and ifnull($table.playCount,0) = 0" if ($selectedlistid =~ /NeverPlayed/);
		if ($selectedlistid =~ /SpecificRating\d+/) {
			my ($rating) = $selectedlistid =~ /SpecificRating(\d+)/;
			$sql .= " and ifnull(tracks_persistent.rating,0) >= ($rating - 5) and ifnull(tracks_persistent.rating,0) <= ($rating + 4)";
		}
		if ($selectedlistid =~ /TopRated/) {
			$sql .= " and ifnull(tracks_persistent.rating,0) >= $topratedMinRating";
		}
		if ($selectedlistid =~ /NotRated/) {
			$sql .= " and ifnull(tracks_persistent.rating,0) = 0";
		}
		if ($apc_enabled) {
			if ($selectedlistid =~ /MostSkipped/ || $selectedlistid =~ /LeastSkipped/) {
				$sql .= " and alternativeplaycount.skipCount is not null";
			}
			$sql .= " and alternativeplaycount.lastSkipped is not null" if $selectedlistid =~ /LastSkipped/;
			$sql .= " and alternativeplaycount.dynPSval is not null" if $selectedlistid =~ /TopDPSV/;
		}
	}

	# group
	$sql .= " GROUP by";
	if ($listType eq 'albums') {
		$sql .= " tracks.album";
	} elsif ($listType eq 'artists') {
		$sql .= " contributor_track.contributor";
	} else {
		$sql .= " tracks.id";
	}

	# having (artists/albums)
	if ($listType eq 'artists' || $listType eq 'albums') {
		$sql .= " HAVING count(tracks.id) >= ".(($context ne 'artist' && $listType eq 'albums' && $prefs->get('min_album_tracks') > 1) ? $prefs->get('min_album_tracks') : '1');
		$sql .= " and contributor_track.contributor != $VAid" if $listType eq 'artists';
		if ($context eq 'year') {
			if ($useDecade) {
				my $decade = floor($objectid/10) * 10 + 0;
				$sql .= " and tracks.year >= $decade and tracks.year <= ($decade + 9)";
			} else {
				$sql .= " and tracks.year = $objectid";
			}
		}
		if ($selectedlistid =~ /MostPlayed/ || $selectedlistid =~ /LeastPlayed/) {
			$sql .= " and avgcount > 0";
		}
		if ($selectedlistid =~ /SpecificRating\d+/) {
			my ($rating) = $selectedlistid =~ /SpecificRating(\d+)/;
			$sql .= " and avgrating >= ($rating - 5) and avgrating <= ($rating + 4)";
		}
		if ($selectedlistid =~ /NeverPlayed/) {
			$sql .= " and avgcount = 0";
		}
		if ($selectedlistid =~ /TopRated/) {
			$sql .= " and avgrating >= $topratedMinRating";
		}
		if ($selectedlistid =~ /NotRated/) {
			$sql .= " and avgrating = 0";
		}
		if ($selectedlistid =~ /PartlyPlayed/) {
			$sql .= " and min(ifnull($table.playCount,0)) = 0 and avgcount > 0";
		}
		if ($selectedlistid =~ /NotCompletelyRated/) {
			$sql .= " and min(ifnull(tracks_persistent.rating,0)) = 0 and avgrating > 0";
		}
		if ($selectedlistid =~ /LastPlayed/ || $selectedlistid =~ /FirstPlayed/) {
			if ($selectedlistid =~ /LastPlayed/ && $recentlyPlayedPeriod) {
				$sql .= " and ($table.lastPlayed >= (select max(ifnull($table.lastPlayed,0)) from $table) - $recentlyPlayedPeriod)";
			} else {
				$sql .= " and $table.lastPlayed is not null";
			}
		}
		if ($selectedlistid =~ /NotRecentlyPlayed/ && $recentlyPlayedPeriod) {
			$sql .= " and ($table.lastPlayed < (select max(ifnull($table.lastPlayed,0)) from $table) - $recentlyPlayedPeriod)";
		}
		if ($recentlyAddedPeriod) {
			$sql .= " and (tracks_persistent.added >= (select max(tracks_persistent.added) from tracks_persistent) - $recentlyAddedPeriod)" if $selectedlistid =~ /LastAdded/;
			$sql .= " and (tracks_persistent.added < (select max(tracks_persistent.added) from tracks_persistent) - $recentlyAddedPeriod)" if $selectedlistid =~ /NotRecentlyAdded/;
		}
	}

	# order
	$sql .= " ORDER by";
	$sql .= (($listType eq 'albums' || $listType eq 'artists') ? " avgrating" : " trackrating")." desc" if $listTypes->{$selectedlistid}{'reqstats'}{'rating'};
	$sql .= (($listType eq 'albums' || $listType eq 'artists') ? " avgDPSV" : " trackDPSV")." desc" if $listTypes->{$selectedlistid}{'reqstats'}{'dynPSval'};
	if ($listTypes->{$selectedlistid}{'reqstats'}{'playCount'}) {
		$sql .= ($listType eq 'albums' || $listType eq 'artists') ? " avgcount" : " trackpc";
		$sql .= " desc" if $selectedlistid =~ /MostPlayed/;
		$sql .= " asc" if $selectedlistid =~ /LeastPlayed/;
	}
	if ($listTypes->{$selectedlistid}{'reqstats'}{'skipCount'}) {
		$sql .= ($listType eq 'albums' || $listType eq 'artists') ? " avgskipcount" : " trackskipcount";
		$sql .= " desc" if $selectedlistid =~ /MostSkipped/;
		$sql .= " asc" if $selectedlistid =~ /LeastSkipped/;
	}
	$sql .= " maxlastskipped desc" if $listTypes->{$selectedlistid}{'reqstats'}{'lastSkipped'};
	if ($listTypes->{$selectedlistid}{'reqstats'}{'lastPlayed'}) {
		$sql .= "," if (scalar keys %{$listTypes->{$selectedlistid}{'reqstats'}} > 1);
		$sql .= " maxlastplayed";
		$sql .= " desc" if ($selectedlistid =~ /LastPlayed/ || $selectedlistid =~ /NotRecentlyPlayed/);
		$sql .= " asc" if $selectedlistid =~ /FirstPlayed/;
	}
	if ($listTypes->{$selectedlistid}{'reqstats'}{'added'}) {
		$sql .= "," if (scalar keys %{$listTypes->{$selectedlistid}{'reqstats'}} > 1);
		$sql .= " maxadded desc";
	}
	$sql .= ", random()";

	# limit
	my $listLimit = $prefs->get('listlimit') || 50;
	$sql .= " LIMIT $listLimit" unless $context eq 'album';

	main::DEBUGLOG && $log->is_debug && $log->debug("\nselectedlistid = ".$selectedlistid."\nSQL = ".$sql."\n");


	#### get items ####
	my @matchingItems = ();
	my $dbh = Slim::Schema->dbh;

	eval {
		my $sth = $dbh->prepare($sql);
		$sth->execute() or do {$sql = undef;};

		my ($trackID, $trackTitle, $trackYear, $albumID, $albumTitle, $albumYear, $albumArtwork, $artistID, $artistName);
		my ($avgRating, $avgPC, $avgSC, $avgDPSV, $trackRating, $trackPC, $trackSC, $trackDPSV);

		if ($listType eq 'albums') {
			$sth->bind_col(1,\$albumID);
			$sth->bind_col(2,\$albumTitle);
			$sth->bind_col(3,\$albumYear);
			$sth->bind_col(4,\$albumArtwork);
			$sth->bind_col(5,\$artistID);
			$sth->bind_col(6,\$artistName);
			$sth->bind_col(7,\$avgRating);
			$sth->bind_col(8,\$avgPC);
			$sth->bind_col(9,\$avgSC) if $apc_enabled;
			$sth->bind_col(10,\$avgDPSV) if $apc_enabled;
		} elsif ($listType eq 'artists') {
			$sth->bind_col(1,\$artistID);
			$sth->bind_col(2,\$artistName);
			$sth->bind_col(3,\$avgRating);
			$sth->bind_col(4,\$avgPC);
			$sth->bind_col(5,\$avgSC) if $apc_enabled;
			$sth->bind_col(6,\$avgDPSV) if $apc_enabled;
		} else {
			$sth->bind_col(1,\$trackID);
			$sth->bind_col(2,\$trackTitle);
			$sth->bind_col(3,\$trackYear);
			$sth->bind_col(4,\$albumID);
			$sth->bind_col(5,\$albumTitle);
			$sth->bind_col(6,\$albumArtwork);
			$sth->bind_col(7,\$artistID);
			$sth->bind_col(8,\$artistName);
			$sth->bind_col(9,\$trackRating);
			$sth->bind_col(10,\$trackPC);
			$sth->bind_col(11,\$trackSC) if $apc_enabled;
			$sth->bind_col(12,\$trackDPSV) if $apc_enabled;
		}

		while ($sth->fetch()) {
			if ($listType eq 'albums') {
				my $albumYear = $prefs->get('showyear') ? $albumYear : 0;
				push (@matchingItems, {
					id => $albumID,
					albumtitle => Slim::Utils::Unicode::utf8decode(trimStringLength($albumTitle, 80), 'utf8'),
					year => $albumYear,
					artworkid => $albumArtwork,
					artistID => $artistID,
					artistname => Slim::Utils::Unicode::utf8decode(trimStringLength($artistName, 80), 'utf8'),
					rating => round($avgRating),
					playcount => round($avgPC),
					skipcount => round($avgSC),
					dpsv => round($avgDPSV)
				});
			}
			if ($listType eq 'artists') {
				my $artistImage;
				if (defined($MAIprefs) && $MAIprefs->get('browseArtistPictures')) {
					$artistImage = 'imageproxy/mai/artist/' . ($artistID || 0);
				}
				push (@matchingItems, {
					id => $artistID,
					artistname => Slim::Utils::Unicode::utf8decode(trimStringLength($artistName, 80), 'utf8'),
					artistimage => $artistImage,
					rating => round($avgRating),
					playcount => round($avgPC),
					skipcount => round($avgSC),
					dpsv => round($avgDPSV)
				});
			}

			if ($listType eq 'tracks') {
				my $trackYear = $prefs->get('showyear') ? $trackYear : 0;
				my $ratingtext = ($trackRating > 4) ? getAppendedRatingText($trackRating, 'appended') : '';
				$trackTitle = trimStringLength(Slim::Utils::Unicode::utf8decode($trackTitle, 'utf8'), ($jive ? 60 : 70)).$ratingtext;
				main::DEBUGLOG && $log->is_debug && $log->debug(Slim::Utils::Unicode::encodingFromString($trackTitle).": ".$trackTitle);
				push (@matchingItems, {
					id => $trackID,
					tracktitle => $trackTitle,
					year => $trackYear,
					albumID => $albumID,
					albumtitle => Slim::Utils::Unicode::utf8decode(trimStringLength($albumTitle, 80), 'utf8'),
					artworkid => $albumArtwork,
					artistID => $artistID,
					artistname => Slim::Utils::Unicode::utf8decode(trimStringLength($artistName, 80), 'utf8'),
					rating => $trackRating,
					playcount => $trackPC,
					skipcount => $trackSC,
					dpsv => $trackDPSV
				});
			}

		}
		$sth->finish();
	};
	if ($@) {main::DEBUGLOG && $log->is_debug && $log->debug("error: $@");}

	main::INFOLOG && $log->is_info && $log->info('Fetched '.scalar (@matchingItems).(scalar (@matchingItems) == 1 ? ' item' : ' items')." for $selectedlistid and ID: $objectid");
	return \@matchingItems;
}

sub _multipleIdsPLcontrol {
	my $request = shift;
	main::DEBUGLOG && $log->is_debug && $log->debug('request params = '.Data::Dump::dump($request->getParamsCopy()));

	if ($request->isNotCommand([['contextstats'],['plcontrolcmd']])) {
		$request->setStatusBadDispatch();
		$log->warn('incorrect command');
		return;
	}

	my $client = $request->client();
	if (!defined $client) {
		$request->setStatusNeedsClient();
		return;
	}

	my $command = _getRequestParamVal($request, 'cmd');
	my $listType = _getRequestParamVal($request, 'listtype');
	my $ids = _getRequestParamVal($request, 'ids');

	my @allIDs = split(/,/, $ids);
	chop($listType);

	if ($command eq 'insert') {
		if ($listType eq 'tracks') {
			$client->execute(['playlistcontrol', 'cmd:'.$command, $listType.'_id:'.$ids]);
		} else {
			while (my $thisid = pop @allIDs) {
				$client->execute(['playlistcontrol', 'cmd:'.$command, $listType.'_id:'.$thisid]);
			}
		}
	}
	if ($command eq 'add') {
		foreach (@allIDs) {
			$client->execute(['playlistcontrol', 'cmd:'.$command, $listType.'_id:'.$_]);
		}
	}
	if ($command eq 'load') {
		$client->execute(['playlistcontrol', 'cmd:load', $listType.'_id:'.(shift @allIDs)]);
		foreach (@allIDs) {
			$client->execute(['playlistcontrol', 'cmd:add', $listType.'_id:'.$_]);
		}
	}

	$request->setStatusDone();
}

sub _getRequestParamVal {
	my ($request, $paramName, $optional) = @_;

	my $paramVal = $request->getParam('_'.$paramName);
	if (defined($paramVal) && $paramVal =~ /^$paramName:(.*)$/) {
		$paramVal = $1;
		return $paramVal;
	} elsif (defined($request->getParam('_'.$paramName))) {
		$paramVal = $request->getParam('_'.$paramName);
		return $paramVal;
	} else {
		$log->error("Missing parameter: $paramName. Provided $paramName = ".Data::Dump::dump($paramVal)) unless $optional;
		return;
	}
}

sub getAppendedRatingText {
	my $rating100ScaleValue = shift;
	my $nobreakspace = HTML::Entities::decode_entities('&#xa0;'); # "NO-BREAK SPACE" - HTML Entity (hex): &#xa0;
	my $displayratingchar = $prefs->get('displayratingchar'); # 0 = common text star *, 1 = "blackstar" - HTML Entity (hex): &#x2605
	my $ratingchar = $displayratingchar ? HTML::Entities::decode_entities('&#x2605;') : ' *';
	my $fractionchar = HTML::Entities::decode_entities('&#xbd;'); # "vulgar fraction one half" - HTML Entity (hex): &#xbd;
	my $text = '';

	if ($rating100ScaleValue > 0) {
		my $detecthalfstars = ($rating100ScaleValue/2)%2;
		my $ratingstars = $rating100ScaleValue/20;
		my $spacechar = ' ';

		if ($detecthalfstars == 1) {
			$ratingstars = floor($ratingstars);
			if ($displayratingchar) {
				$text = ($ratingchar x $ratingstars).$fractionchar;
			} else {
				$text = ($ratingchar x $ratingstars).' '.$fractionchar;
			}
		} else {
			$text = ($ratingchar x $ratingstars);
		}
	}

	if ($displayratingchar) {
		my $sepchar = HTML::Entities::decode_entities('&#x2022;'); # "bullet" - HTML Entity (hex): &#x2022;
		$text = $nobreakspace.$sepchar.$nobreakspace.$text;
	} else {
		$text = $nobreakspace.'('.$text.$nobreakspace.')';
	}

	return $text;
}

sub trimStringLength {
	my ($thisString, $maxlength) = @_;
	if (defined $thisString && (length($thisString) > $maxlength)) {
		$thisString = substr($thisString, 0, $maxlength).'...';
	}
	return $thisString;
}

sub round {
	my ($value, $decimals) = @_;
	return 0 if !$value;
	$decimals = 2 if !$decimals;
	my $factor = 10**$decimals;
	return int($value * $factor + 0.5) / $factor if $value >= 0;
	return int($value * $factor - 0.5) / $factor if $value < 0;
}

sub weight {
	return 81;
}

*escape = \&URI::Escape::uri_escape_utf8;
*unescape = \&URI::Escape::uri_unescape;

1;
