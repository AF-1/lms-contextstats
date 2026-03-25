#
# Context Stats
# (c) 2024 AF
# Licensed under the GPLv3 - see LICENSE file
#

package Plugins::ContextStats::Settings;

use strict;
use warnings;
use utf8;

use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
use Slim::Utils::Log;

my $log = logger('plugin.contextstats');
my $prefs = preferences('plugin.contextstats');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_CONTEXTSTATS');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/ContextStats/settings/settings.html');
}

sub prefs {
	return ($prefs, qw(listlimit useapcvalues browsemenuitem displayxtraline jiveextralinelength min_album_tracks topratedminrating displayratingchar showyear recentlyplayedperiod recentlyaddedperiod ratingchangedperiod contextmenuposition));
}

1;
