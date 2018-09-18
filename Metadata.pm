package Plugins::Phishin::Metadata;

use strict;

use Slim::Formats::RemoteMetadata;
use Slim::Utils::Cache;
use Slim::Utils::Log;
# use Slim::Utils::Prefs;

use Plugins::Phishin::Plugin;

use constant ARTIST       => 'Phish';
use constant CACHE_PREFIX => 'phishin_meta';
use constant CACHE_TTL    => 30 * 86400;

my $log = logger('plugin.phishin');
my $cache = Slim::Utils::Cache->new();

sub init {
	my $class = shift;

	Slim::Formats::RemoteMetadata->registerProvider(
		match => qr{https?://phish\.in/audio},
		func  => \&provider,
	);
}

sub provider {
	my ( $client, $url ) = @_;

	return __PACKAGE__->getMetadataFor($url);
}

sub getMetadataFor {
	my ( $class, $url ) = @_;

	my $meta = $cache->get(CACHE_PREFIX . $url) || {};

	$meta->{image} ||= Plugins::Phishin::Plugin->_pluginDataFor('icon');

	main::DEBUGLOG && $log->is_debug && $log->debug("Found metadata for $url: " . Data::Dump::dump($meta));
	return $meta;
}

sub setMetadata {
	my ( $class, $track, $show ) = @_;

	if (!$track->{mp3}) {
		$log->warn("Metadata is missing audio stream URL? " . $track);
		main::INFOLOG && $log->is_info && $log->info(Data::Dump::dump($track));
		return;
	}

	# consider the show details the album information
	my $album = $show->{date} || '';
	if (my $venue = $show->{venue}) {
		$album = ($album ? "$album - " : '') . $venue->{name};

		if ($track->{set_name}) {
			$album .= ' (' . $track->{set_name} . ')';
		}
	}

	my $meta = {
		title => $track->{title},
		artist => ARTIST,
		album => $album,
		cover => Plugins::Phishin::Plugin->_pluginDataFor('icon'),
		url   => $track->{mp3},
		tracknum => $track->{position},
		secs  => (delete $track->{duration}) / 1000,
	};

	$cache->set(CACHE_PREFIX . $meta->{url}, $meta);
	return $meta;
}

1;