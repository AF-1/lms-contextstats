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
	return ($prefs, qw(listlimit useapcvalues browsemenuitem displayxtraline jiveextralinelength min_album_tracks topratedminrating displayratingchar showyear recentlyplayedperiod recentlyaddedperiod contextmenuposition));
}

sub handler {
	my ($class, $client, $paramRef) = @_;
	return $class->SUPER::handler($client, $paramRef);
}

1;
