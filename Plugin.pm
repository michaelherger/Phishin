package Plugins::Phishin::Plugin;

use strict;

use base qw(Slim::Plugin::OPMLBased);

use Slim::Utils::Strings qw(string cstring);
use Slim::Utils::Log;

use Plugins::Phishin::API;
use Plugins::Phishin::Metadata;

use vars qw($VERSION);

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.phishin',
	defaultLevel => 'WARN',
	description  => 'PLUGIN_PHISHIN',
} );

sub initPlugin {
	my $class = shift;

	$VERSION = $class->_pluginDataFor('version');

	Plugins::Phishin::Metadata->init();

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
		},{
			name => $client->string('PLUGIN_PHISHIN_VENUES'),
			type => 'link',
			url  => \&venues,
		},{
			name => $client->string('PLUGIN_PHISHIN_SONGS'),
			type => 'link',
			url  => \&songs,
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
				name => $_->{date} . ' - ' . $_->{venue_name} . ' - ' . $_->{location},
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

sub venues {
	my ($client, $cb, $params, $args) = @_;

	Plugins::Phishin::API->getVenues(sub {
		my ($venues) = @_;

		my $items = [];

		my $indexList = [];
		my $indexLetter;
		my $count = 0;

		foreach (@$venues) {
			next unless $_->{shows_count};

			my $textkey = uc(substr($_->{name} || '', 0, 1));

			if ( defined $indexLetter && $indexLetter ne ($textkey || '') ) {
				push @$indexList, [$indexLetter, $count];
				$count = 0;
			}

			$count++;
			$indexLetter = $textkey;

			push @$items, {
				name => $_->{name} . ' - ' . $_->{location},
				line1 => $_->{name},
				line2 => $_->{location},
				type => 'link',
				textkey => $textkey,
				url => \&venue,
				passthrough => [{
					venueId => $_->{id}
				}]
			}
		}

		push @$indexList, [$indexLetter, $count];

		$cb->({
			items     => $items,
			indexList => $indexList
		});
	});
}

sub venue {
	my ($client, $cb, $params, $args) = @_;

	Plugins::Phishin::API->getVenue($params->{venueId} || $args->{venueId}, sub {
		my ($venue) = @_;

		my $i = 0;
		my $items = [ reverse map {
			{
				name => $_,
				type => 'playlist',
				url => \&show,
				passthrough => [{
					showId => $venue->{show_ids}->[$i++]
				}]
			}
		} @{$venue->{show_dates} || []} ];

		$cb->({ items => $items });
	});
}

sub songs {
	my ($client, $cb, $params, $args) = @_;

	Plugins::Phishin::API->getSongs(sub {
		my ($songs) = @_;

		my $items = [];

		my $indexList = [];
		my $indexLetter;
		my $count = 0;

		foreach (@$songs) {
			next unless $_->{tracks_count};

			my $textkey = uc(substr($_->{title} || '', 0, 1));

			if ( defined $indexLetter && $indexLetter ne ($textkey || '') ) {
				push @$indexList, [$indexLetter, $count];
				$count = 0;
			}

			$count++;
			$indexLetter = $textkey;

			push @$items, {
				name => $_->{title} . ' (' . $_->{tracks_count} . ')',
				type => 'link',
				textkey => $textkey,
				url => \&song,
				passthrough => [{
					songId => $_->{id}
				}]
			}
		}

		push @$indexList, [$indexLetter, $count];

		$cb->({
			items     => $items,
			indexList => $indexList
		});
	});
}

sub song {
	my ($client, $cb, $params, $args) = @_;

	Plugins::Phishin::API->getSong($params->{songId} || $args->{songId}, sub {
		my ($song) = @_;

		my $i = 0;
		my $items = [ reverse map {
			{
				name => $_->{show_date},
				type => 'playlist',
				url => \&show,
				passthrough => [{
					showId => $_->{show_id}
				}]
			}
		} @{$song->{tracks} || []} ];

		$cb->({ items => $items });
	});
}

sub show {
	my ($client, $cb, $params, $args) = @_;

	Plugins::Phishin::API->getShow($params->{showId} || $args->{showId}, sub {
		my ($show) = @_;

		my $items = [ map {
			my $meta = Plugins::Phishin::Metadata->setMetadata($_, $show);

			{
				name => $meta->{title},
				type => 'audio',
				url  => $meta->{url},
			}
		} @{$show->{tracks}} ];

		$cb->({ items => $items });
	});
}

1;