package Plugins::Phishin::API;

use strict;

use Digest::MD5 qw(md5_hex);
use JSON::XS::VersionOneAndTwo;
# use List::Util qw(min max);
# use POSIX qw(strftime);
# use Tie::Cache::LRU::Expires;
# use URI::Escape qw(uri_escape_utf8);

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Cache;
use Slim::Utils::Log;
# use Slim::Utils::Prefs;

use constant API_URL => 'http://phish.in/api/v1/';

my $log = logger('plugin.phishin');
my $cache = Slim::Utils::Cache->new();

sub getEras {
	my ($class, $cb) = @_;
	_call('/eras', $cb);
}

sub getYear {
	my ($class, $year, $cb) = @_;

	# ??? - sorting doesn't work?
	_call("/years/$year", $cb, {
		sort_attr => 'date',
		sort_dir => 'desc'
	});
}

sub getShow {
	my ($class, $id, $cb) = @_;
	_call("/shows/$id", $cb);
}

sub _call {
	my ( $url, $cb, $params ) = @_;

	# $uri must not have a leading slash
	$url =~ s/^\///;
	$url = API_URL . $url;

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

			$result = decode_json(
				$response->content,
			);

			main::DEBUGLOG && $log->is_debug && $log->debug(Data::Dump::dump($result));

			if ($result->{success} && $result->{data}) {
				$result = $result->{data};

				if ( $cache_key ) {
					if ( my $cache_control = $response->headers->header('Cache-Control') ) {
						my ($ttl) = $cache_control =~ /max-age=(\d+)/;

						$ttl ||= 60;		# XXX - we're going to always cache for a minute, as we often do follow up calls while navigating

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

	$http->get($url);
}

1;