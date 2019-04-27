package Plugins::Phishin::API;

use strict;

use Digest::MD5 qw(md5_hex);
use JSON::XS::VersionOneAndTwo;

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Cache;
use Slim::Utils::Log;

use constant API_URL => 'http://phish.in/api/v1/';
use constant CACHE_TTL => 3600;

my $log = logger('plugin.phishin');
my $cache = Slim::Utils::Cache->new();

sub getEras {
	my ($class, $cb) = @_;
	_call('/eras', $cb);
}

sub getYear {
	my ($class, $year, $cb) = @_;

	# ??? - sorting doesn't work?
	_call("/years/$year", sub {
		my ($shows) = @_;

		foreach (@$shows) {
			$cache->set('phishin_show_' . $_->{id}, $_, CACHE_TTL)
		}

		$cb->($shows);
	}, {
		sort_attr => 'date',
		sort_dir => 'desc'
	});
}

sub getVenues {
	my ($class, $cb) = @_;
	_call('/venues', sub {
		# unfortunately sorting seems broken - let's do it ourselves
		my $venues = [
			sort {
				$a->{slug} cmp $b->{slug}
			} @{shift || []}
		];

		$cb->($venues, @_);
	},{
		sort_attr => 'name'
	});
}

sub getVenue {
	my ($class, $id, $cb) = @_;
	_call("/venues/$id", $cb);
}

sub getSongs {
	my ($class, $cb) = @_;
	_call('/songs', sub {
		# unfortunately sorting seems broken - let's do it ourselves
		my $songs = [
			sort {
				$a->{slug} cmp $b->{slug}
			} @{shift || []}
		];

		$cb->($songs, @_);
	},{
		sort_attr => 'title'
	});
}

sub getSong {
	my ($class, $id, $cb) = @_;
	_call("/songs/$id", $cb);
}

sub getShow {
	my ($class, $id, $cb) = @_;

	if ( my $cached = $cache->get('phishin_show_' . $id) ) {
		main::INFOLOG && $log->is_info && $log->info("Returning cached data for show $id");
		main::DEBUGLOG && $log->is_debug && $log->debug(Data::Dump::dump($cached));
		$cb->($cached);
		return;
	}

	_call("/shows/$id", $cb);
}

sub search {
	my ($class, $query, $cb) = @_;
	_call("/search/$query", $cb);
}

sub _call {
	my ( $url, $cb, $params ) = @_;

	# $uri must not have a leading slash
	$url =~ s/^\///;
	$url = API_URL . $url . '.json';

	$params->{per_page} ||= 9999;

	if ( my @keys = sort keys %{$params}) {
		my @params;
		foreach my $key ( @keys ) {
			next if $key =~ /^_/;
			push @params, $key . '=' . $params->{$key};
			# push @params, $key . '=' . uri_escape_utf8( $params->{$key} );
		}

		$url .= '?' . join( '&', sort @params ) if scalar @params;
	}

	my $cached;
	my $cache_key;
	if (!$params->{_nocache}) {
		$cache_key = md5_hex($url);
	}

	main::INFOLOG && $log->is_info && $cache_key && $log->info("Trying to read from cache for $url");

	if ( $cache_key && ($cached = $cache->get($cache_key)) ) {
		main::INFOLOG && $log->is_info && $log->info("Returning cached data for $url");
		main::DEBUGLOG && $log->is_debug && $log->debug(Data::Dump::dump($cached));
		$cb->($cached);
		return;
	}
	elsif ( main::INFOLOG && $log->is_info ) {
		$log->info("API call: $url");
	}

	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			my $response = shift;
			my $params   = $response->params('params');

			my $result;

			if ( $response->headers->content_type =~ /json/i ) {
				$result = decode_json(
					$response->content,
				);
			}
			else {
				$log->error("phish.in didn't return JSON data? " . $response->content);
			}

			main::DEBUGLOG && $log->is_debug && $log->debug(Data::Dump::dump($result));

			if ($result && $result->{success} && $result->{data}) {
				$result = $result->{data};

				if ( $cache_key ) {
					if ( my $cache_control = $response->headers->header('Cache-Control') ) {
						my ($ttl) = $cache_control =~ /max-age=(\d+)/;

						$ttl ||= CACHE_TTL;		# XXX - we're going to always cache for a while, as we often do follow up calls while navigating

						if ($ttl) {
							main::INFOLOG && $log->is_info && $log->info("Caching result for $ttl using max-age (" . $response->url . ")");
							$cache->set($cache_key, $result, $ttl);
							main::INFOLOG && $log->is_info && $log->info("Data cached (" . $response->url . ")");
						}
					}
				}
			}

			$cb->($result, $response);
		},
		sub {
			my ($http, $error, $response) = @_;

			$log->error("Got error from phish.in': $error");

			main::INFOLOG && $log->is_info && $log->info(Data::Dump::dump($response));
			$cb->({
				error => 'Unexpected error: ' . $error,
			}, $response);
		},
	);

	$http->get($url, 'Authorization' => 'Bearer ' . Plugins::Phishin::Plugin->_pluginDataFor('id2'));
}

1;