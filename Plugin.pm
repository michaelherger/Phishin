package Plugins::Phishin::Plugin;

use strict;

use base qw(Slim::Plugin::OPMLBased);

use Slim::Utils::Strings qw(string cstring);
use Slim::Utils::Log;

use Plugins::Phishin::API;

use vars qw($VERSION);

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.phishin',
	defaultLevel => 'WARN',
	description  => 'PLUGIN_PHISHIN',
} );

sub initPlugin {
	my $class = shift;

	$VERSION = $class->_pluginDataFor('version');

	$class->SUPER::initPlugin(
		feed   => \&handleFeed,
		tag    => 'phishin',
		menu   => 'radios',
		is_app => 1,
		weight => 1,
	);
}

sub getDisplayName { 'PLUGIN_PHISHIN' }
sub playerMenu {}

sub handleFeed {
	my ($client, $cb, $args) = @_;

	if (!$client) {
		$cb->([{ name => string('NO_PLAYER_FOUND') }]);
		return;
	}

	$client = $client->master;

	my $items = [
		{
			name => $client->string('PLUGIN_PHISHIN_YEARS'),
			type => 'link',
			url  => \&eras,
		}
	];

	$cb->({
		items => $items,
	});
}

sub eras {
	my ($client, $cb, $params) = @_;

	Plugins::Phishin::API->getEras(sub {
		my ($eras) = @_;

		my $items = [];
		foreach my $era ( sort { $b <=> $a } keys %$eras ) {
			push @$items, {
				name => cstring($client, 'PLUGIN_PHISHIN_ERA', $era),
				type => 'outline',
				items => [ map {
					{
						name => $_,
						url => \&year,
						passthrough => [{
							year => $_
						}],
					}
				} reverse @{$eras->{$era}} ]
			}
		}

		$cb->({ items => $items });
	});
}

sub year {
	my ($client, $cb, $params, $args) = @_;

	Plugins::Phishin::API->getYear($params->{year} || $args->{year}, sub {
		my ($shows) = @_;

		my $items = [ map {
			{
				name => $_->{date} . ' - ' . $_->{venue_name},
				line1 => $_->{date} . ' - ' . $_->{venue_name},
				line2 => $_->{location},
				type => 'playlist',
				url => \&show,
				passthrough => [{
					showId => $_->{id}
				}]
			}
		} @$shows ];

		$cb->({ items => $items });
	});
}

sub show {
	my ($client, $cb, $params, $args) = @_;

	Plugins::Phishin::API->getShow($params->{showId} || $args->{showId}, sub {
		my ($show) = @_;

		# TODO - cache metadata

		my $items = [ map {
			{
				name => $_->{title},
				type => 'audio',
				url => $_->{mp3}
			}
		} @{$show->{tracks}} ];

		$cb->({ items => $items });
	});
}

sub _pluginDataFor {
	my $class = shift;
	my $key   = shift;

	my $pluginData = Slim::Utils::PluginManager->dataForPlugin($class);

	if ($pluginData && ref($pluginData) && $pluginData->{$key}) {
		return $pluginData->{$key};
	}

	return undef;
}

1;