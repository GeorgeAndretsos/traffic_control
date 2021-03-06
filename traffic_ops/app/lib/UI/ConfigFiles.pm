package UI::ConfigFiles;

#
# Copyright 2015 Comcast Cable Communications Management, LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#
#
use UI::Utils;

use Mojo::Base 'Mojolicious::Controller';
use Data::Dumper;
use Date::Manip;
use NetAddr::IP;
use UI::DeliveryService;
use JSON;
use API::DeliveryService::KeysUrlSig qw(URL_SIG_KEYS_BUCKET);

my $dispatch_table ||= {
	"logs_xml.config"         => sub { logs_xml_dot_config(@_) },
	"cacheurl.config"         => sub { cacheurl_dot_config(@_) },
	"records.config"          => sub { generic_config(@_) },
	"plugin.config"           => sub { generic_config(@_) },
	"astats.config"           => sub { generic_config(@_) },
	"volume.config"           => sub { volume_dot_config(@_) },
	"hosting.config"          => sub { hosting_dot_config(@_) },
	"storage.config"          => sub { storage_dot_config(@_) },
	"50-ats.rules"            => sub { ats_dot_rules(@_) },
	"cache.config"            => sub { cache_dot_config(@_) },
	"remap.config"            => sub { remap_dot_config(@_) },
	"parent.config"           => sub { parent_dot_config(@_) },
	"sysctl.conf"             => sub { generic_config(@_) },
	"ip_allow.config"         => sub { ip_allow_dot_config(@_) },
	"12M_facts"               => sub { facts(@_) },
	"regex_revalidate.config" => sub { regex_revalidate_dot_config(@_) },
	"drop_qstring.config"     => sub { drop_qstring_dot_config(@_) },
	"bg_fetch.config"         => sub { bg_fetch_dot_config(@_) },

	"url_sig_.config"      => sub { url_sig_config(@_) },
	"hdr_rw_.config"       => sub { header_rewrite_dot_config(@_) },
	"set_dscp_.config"     => sub { header_rewrite_dscp_dot_config(@_) },
	"to_ext_.config"       => sub { to_ext_dot_config(@_) },
	"regex_remap_.config"  => sub { regex_remap_dot_config(@_) },
	"cacheurl_.config"     => sub { cacheurl_dot_config(@_) },
	"all"                  => sub { gen_fancybox_data(@_) },
	"ssl_multicert.config" => sub { ssl_multicert_dot_config(@_) },

};

my $separator ||= {
	"records.config"  => " ",
	"plugin.config"   => " ",
	"sysctl.conf"     => " = ",
	"url_sig_.config" => " = ",
	"astats.config"   => "=",
};

sub genfiles {
	my $self = shift;
	my $mode = $self->param('mode');
	my $id   = $self->param('id');
	my $file = $self->param('filename');

	my $org_name = $file;

	$file =~ s/^url_sig_.*\.config$/url_sig_\.config/;
	$file =~ s/^hdr_rw_.*\.config$/hdr_rw_\.config/;
	$file =~ s/^set_dscp_.*\.config$/set_dscp_\.config/;
	$file =~ s/^regex_remap_.*\.config$/regex_remap_\.config/;
	$file =~ s/^cacheurl_.*\.config$/cacheurl_\.config/;
	$file =~ s/^to_ext_.*\.config$/to_ext_\.config/;

	my $text = undef;
	if ( $mode eq 'view' ) {

		if ( defined( $dispatch_table->{$file} ) ) {
			$text = $dispatch_table->{$file}->( $self, $id, $org_name );
		}
		else {
			$text = &take_and_bake( $self, $id, $org_name );
		}
	}

	if ( $file ne "all" ) {
		$self->res->headers->content_type("application/download");
		$self->res->headers->content_disposition("attachment; filename=\"$org_name\"");
		$self->render( text => $text, format => 'txt' );
	}
	else {

		# ignore $text, the good stuff is in the stash
		$self->stash( fbox_layout => 1 );
	}
}

sub gen_fancybox_data {
	my $self     = shift;
	my $id       = shift;
	my $filename = shift;

	my $file_text;
	my $server  = $self->server_data($id);
	my $ds_data = $self->ds_data($server);
	my $rs      = $self->db->resultset('ProfileParameter')->search(
		{ -and => [ profile => $server->profile->id, 'parameter.name' => 'location' ] },
		{ prefetch => [ { parameter => undef }, { profile => undef } ] }
	);
	while ( my $row = $rs->next ) {
		my $file = $row->parameter->config_file;

		# print "Genning $file\n";
		my $org_name = $file;
		$file =~ s/^url_sig_.*\.config$/url_sig_\.config/;
		$file =~ s/^hdr_rw_.*\.config$/hdr_rw_\.config/;
		$file =~ s/^set_dscp_.*\.config$/set_dscp_\.config/;
		$file =~ s/^regex_remap_.*\.config$/regex_remap_\.config/;
		$file =~ s/^cacheurl_.*\.config$/cacheurl_\.config/;
		$file =~ s/^to_ext_.*\.config$/to_ext_\.config/;

		my $text = "boo";
		if ( defined( $dispatch_table->{$file} ) ) {
			$text = $dispatch_table->{$file}->( $self, $id, $org_name, $ds_data );
		}
		else {
			$text = &take_and_bake( $self, $id, $org_name, $ds_data );
		}
		$file_text->{$org_name} = $text;
	}
	$self->stash( file_text => $file_text );
	$self->stash( host_name => $server->host_name );
}

sub server_data {
	my $self = shift;
	my $id   = shift;

	my $server;

	#	if ( defined( $self->app->session->{server_data} ) ) {
	#		$server = $self->app->session->{server_data};
	#		return $server;
	#	}
	if ( $id =~ /^\d+$/ ) {
		$server = $self->db->resultset('Server')->search( { id => $id } )->single;
	}
	else {
		$server = $self->db->resultset('Server')->search( { host_name => $id } )->single;
	}

	#	$self->app->session->{server_data} = $server;
	return $server;
}

sub header_comment {
	my $self      = shift;
	my $host_name = shift;

	my $text = "# DO NOT EDIT - Generated for " . $host_name . " by " . &name_version_string($self) . " on " . `date`;
	return $text;
}

sub ds_data {
	my $self   = shift;
	my $server = shift;

	my $dsinfo;

	#	if ( defined( $self->app->session->{dsinfo} ) ) {
	#		$dsinfo = $self->app->session->{dsinfo};
	#		return $dsinfo;
	#	}
	$dsinfo->{host_name}   = $server->host_name;
	$dsinfo->{domain_name} = $server->domain_name;

	my $storage_data = $self->param_data( $server, "storage.config" );
	$dsinfo->{RAM_Volume}  = $storage_data->{RAM_Volume};
	$dsinfo->{Disk_Volume} = $storage_data->{Disk_Volume};

	my @server_ids = ();
	my $rs;
	if ( $server->type->name eq "MID" ) {

		# the mids will do all deliveryservices in this CDN
		my $domain =
			$self->db->resultset('ProfileParameter')
			->search( { -and => [ profile => $server->profile->id, 'parameter.name' => 'domain_name', 'parameter.config_file' => 'CRConfig.json' ] },
			{ prefetch => [ 'parameter', 'profile' ] } )->get_column('parameter.value')->single();

		$rs = $self->db->resultset('DeliveryServiceInfoForDomainList')->search( {}, { bind => [$domain] } );
	}
	else {
		$rs = $self->db->resultset('DeliveryServiceInfoForServerList')->search( {}, { bind => [ $server->id ] } );
	}

	my $j = 0;
	while ( my $row = $rs->next ) {
		my $org_server             = $row->org_server_fqdn;
		my $dscp                   = $row->dscp;
		my $re_type                = $row->re_type;
		my $ds_type                = $row->ds_type;
		my $signed                 = $row->signed;
		my $qstring_ignore         = $row->qstring_ignore;
		my $ds_xml_id              = $row->xml_id;
		my $ds_domain              = $row->domain_name;
		my $edge_header_rewrite    = $row->edge_header_rewrite;
		my $mid_header_rewrite     = $row->mid_header_rewrite;
		my $regex_remap            = $row->regex_remap;
		my $protocol               = $row->protocol;
		my $range_request_handling = $row->range_request_handling;
		my $origin_shield          = $row->origin_shield;
		my $cacheurl               = $row->cacheurl;
		my $remap_text             = $row->remap_text;
		my $multi_site_origin      = $row->multi_site_origin;

		if ( $re_type eq 'HOST_REGEXP' ) {
			my $host_re = $row->pattern;
			my $map_to  = $org_server . "/";
			if ( $host_re =~ /\.\*$/ ) {
				my $re = $host_re;
				$re =~ s/\\//g;
				$re =~ s/\.\*//g;
				my $hname = $ds_type =~ /^DNS/ ? "edge" : "ccr";
				my $map_from = "http://" . $hname . $re . $ds_domain . "/";
				if ( $protocol == 0 ) {
					$dsinfo->{dslist}->[$j]->{"remap_line"}->{$map_from} = $map_to;
				}
				elsif ( $protocol == 1 ) {
					$map_from = "https://" . $hname . $re . $ds_domain . "/";
					$dsinfo->{dslist}->[$j]->{"remap_line"}->{$map_from} = $map_to;
				}
				elsif ( $protocol == 2 ) {

					#add the first one with http
					$dsinfo->{dslist}->[$j]->{"remap_line"}->{$map_from} = $map_to;

					#add the second one for https
					my $map_from2 = "https://" . $hname . $re . $ds_domain . "/";
					$dsinfo->{dslist}->[$j]->{"remap_line2"}->{$map_from2} = $map_to;
				}
			}
			else {
				my $map_from = "http://" . $host_re . "/";
				if ( $protocol == 0 ) {
					$dsinfo->{dslist}->[$j]->{"remap_line"}->{$map_from} = $map_to;
				}
				elsif ( $protocol == 2 ) {

					#add with http
					$dsinfo->{dslist}->[$j]->{"remap_line"}->{$map_from} = $map_to;
				}
			}
		}
		$dsinfo->{dslist}->[$j]->{"dscp"}                   = $dscp;
		$dsinfo->{dslist}->[$j]->{"org"}                    = $org_server;
		$dsinfo->{dslist}->[$j]->{"type"}                   = $ds_type;
		$dsinfo->{dslist}->[$j]->{"domain"}                 = $ds_domain;
		$dsinfo->{dslist}->[$j]->{"signed"}                 = $signed;
		$dsinfo->{dslist}->[$j]->{"qstring_ignore"}         = $qstring_ignore;
		$dsinfo->{dslist}->[$j]->{"ds_xml_id"}              = $ds_xml_id;
		$dsinfo->{dslist}->[$j]->{"edge_header_rewrite"}    = $edge_header_rewrite;
		$dsinfo->{dslist}->[$j]->{"mid_header_rewrite"}     = $mid_header_rewrite;
		$dsinfo->{dslist}->[$j]->{"regex_remap"}            = $regex_remap;
		$dsinfo->{dslist}->[$j]->{"range_request_handling"} = $range_request_handling;
		$dsinfo->{dslist}->[$j]->{"origin_shield"}          = $origin_shield;
		$dsinfo->{dslist}->[$j]->{"cacheurl"}               = $cacheurl;
		$dsinfo->{dslist}->[$j]->{"remap_text"}             = $remap_text;
		$dsinfo->{dslist}->[$j]->{"multi_site_origin"}      = $multi_site_origin;

		if ( defined($edge_header_rewrite) ) {
			my $fname = "hdr_rw_" . $ds_xml_id . ".config";
			$dsinfo->{dslist}->[$j]->{"hdr_rw_file"} = $fname;
		}
		if ( defined($mid_header_rewrite) ) {
			my $fname = "hdr_rw_mid_" . $ds_xml_id . ".config";
			$dsinfo->{dslist}->[$j]->{"mid_hdr_rw_file"} = $fname;
		}
		if ( defined($cacheurl) ) {
			my $fname = "cacheurl_" . $ds_xml_id . ".config";
			$dsinfo->{dslist}->[$j]->{"cacheurl_file"} = $fname;
		}

		$j++;
	}

	#	$self->app->session->{dsinfo} = $dsinfo;
	return $dsinfo;
}

sub param_data {
	my $self     = shift;
	my $server   = shift;
	my $filename = shift;
	my $data;

	my $rs = $self->db->resultset('ProfileParameter')->search( { -and => [ profile => $server->profile->id, 'parameter.config_file' => $filename ] },
		{ prefetch => [ { parameter => undef }, { profile => undef } ] } );
	while ( my $row = $rs->next ) {
		if ( $row->parameter->name eq "location" ) {
			next;
		}
		my $value = $row->parameter->value;

		# some files have multiple lines with the same key... handle that with param id.
		my $key = $row->parameter->name;
		if ( defined( $data->{$key} ) ) {
			$key .= "__" . $row->parameter->id;
		}
		if ( $value =~ /^STRING __HOSTNAME__$/ ) {
			$value = "STRING " . $server->host_name . "." . $server->domain_name;
		}
		$data->{$key} = $value;
	}
	return $data;
}

sub parent_data {
	my $self   = shift;
	my $server = shift;

	my $pinfo;
	my @parent_cachegroup_ids;
	my $org_loc_type_id = &type_id( $self, "ORG_LOC" );
	if ( $server->type->name eq 'MID' ) {

		# multisite origins take all the org groups in to account
		@parent_cachegroup_ids = $self->db->resultset('Cachegroup')->search( { type => $org_loc_type_id } )->get_column('id')->all();
	}
	else {
		@parent_cachegroup_ids = $self->db->resultset('Cachegroup')->search( { id => $server->cachegroup->id } )->get_column('parent_cachegroup_id')->all();
	}

	my $online   = &admin_status_id( $self, "ONLINE" );
	my $reported = &admin_status_id( $self, "REPORTED" );

	# get the server's cdn domain
	my $param =
		$self->db->resultset('ProfileParameter')
		->search( { -and => [ profile => $server->profile->id, 'parameter.config_file' => 'CRConfig.json', 'parameter.name' => 'domain_name' ] },
		{ prefetch => [ { parameter => undef }, { profile => undef } ] } )->single();
	my $server_domain = $param->parameter->value;

	my $condition->{"status"} = { -in => [ $online, $reported ] };
	if (@parent_cachegroup_ids) {
		$condition->{"cachegroup"} = { -in => \@parent_cachegroup_ids };
	}

	my $rs_parent =
		$self->db->resultset('Server')->search( { %$condition },
		{ prefetch => [ 'cachegroup', 'status', 'type', 'profile' ] } );

	my %profile_cache    = ();
	my $deliveryservices = undef;
	while ( my $row = $rs_parent->next ) {

		next unless ( $row->type->name eq 'ORG' || $row->type->name eq 'EDGE' || $row->type->name eq 'MID' );
		if ( $row->type->name eq 'ORG' ) {
			my $rs_ds = $self->db->resultset('DeliveryserviceServer')->search( { server => $row->id }, { prefetch => ['deliveryservice'] } );
			while ( my $ds_row = $rs_ds->next ) {
				my $ds_domain = $ds_row->deliveryservice->org_server_fqdn;
				$ds_domain =~ s/https?:\/\/(.*)/$1/;
				push( @{ $deliveryservices->{$ds_domain} }, $row );
			}
		}
		else {
			push( @{ $deliveryservices->{"all_parents"} }, $row );
		}

		# get the profile info, and cache it in %profile_cache
		my $ds_domain      = undef;
		my $weight         = undef;
		my $port           = undef;
		my $use_ip_address = undef;
		my $pid            = $row->profile->id;
		if ( !defined( $profile_cache{$pid} ) ) {

			# assign $ds_domain, $weight and $port, and cache the results %profile_cache
			my $param =
				$self->db->resultset('ProfileParameter')
				->search( { -and => [ profile => $pid, 'parameter.config_file' => 'CRConfig.json', 'parameter.name' => 'domain_name' ] },
				{ prefetch => [ 'parameter', 'profile' ] } )->single();
			$ds_domain = $param->parameter->value;
			$profile_cache{$pid}->{domain_name} = $ds_domain;
			$param =
				$self->db->resultset('ProfileParameter')
				->search( { -and => [ profile => $pid, 'parameter.config_file' => 'parent.config', 'parameter.name' => 'weight' ] },
				{ prefetch => [ 'parameter', 'profile' ] } )->single();
			$weight = defined($param) ? $param->parameter->value : "0.999";
			$profile_cache{$pid}->{weight} = $weight;
			$param =
				$self->db->resultset('ProfileParameter')
				->search( { -and => [ profile => $pid, 'parameter.config_file' => 'parent.config', 'parameter.name' => 'port' ] },
				{ prefetch => [ 'parameter', 'profile' ] } )->single();
			$port = defined($param) ? $param->parameter->value : undef;
			$profile_cache{$pid}->{port} = $port;
			$param =
				$self->db->resultset('ProfileParameter')
				->search( { -and => [ profile => $pid, 'parameter.config_file' => 'parent.config', 'parameter.name' => 'use_ip_address' ] },
				{ prefetch => [ 'parameter', 'profile' ] } )->single();
			$use_ip_address = defined($param) ? $param->parameter->value : 0;
			$profile_cache{$pid}->{use_ip_address} = $use_ip_address;
		}
	}

	foreach my $prefix ( keys %{$deliveryservices} ) {
		my $i = 0;
		$rs_parent->reset;
		foreach my $row ( @{ $deliveryservices->{$prefix} } ) {
			my $pid            = $row->profile->id;
			my $ds_domain      = $profile_cache{$pid}->{domain_name};
			my $weight         = $profile_cache{$pid}->{weight};
			my $port           = $profile_cache{$pid}->{port};
			my $use_ip_address = $profile_cache{$pid}->{use_ip_address};
			if ( defined($ds_domain) && defined($server_domain) && $ds_domain eq $server_domain ) {
				$pinfo->{$prefix}->[$i]->{"host_name"}      = $row->host_name;
				$pinfo->{$prefix}->[$i]->{"port"}           = defined($port) ? $port : $row->tcp_port;
				$pinfo->{$prefix}->[$i]->{"domain_name"}    = $row->domain_name;
				$pinfo->{$prefix}->[$i]->{"weight"}         = $weight;
				$pinfo->{$prefix}->[$i]->{"use_ip_address"} = $use_ip_address;
				$pinfo->{$prefix}->[$i]->{"ip_address"}     = $row->ip_address;
				if ( $server->cachegroup->parent_cachegroup_id == $row->cachegroup->id ) {
					$pinfo->{$prefix}->[$i]->{"preferred"} = 1;
				}
				else {
					$pinfo->{$prefix}->[$i]->{"preferred"} = 0;
				}
				$i++;
			}
		}
	}
	return $pinfo;
}

sub ip_allow_data {
	my $self   = shift;
	my $server = shift;

	my $ipallow;
	$ipallow = ();

	my $i = 0;

	# localhost is trusted.
	$ipallow->[$i]->{src_ip} = '127.0.0.1';
	$ipallow->[$i]->{action} = 'ip_allow';
	$ipallow->[$i]->{method} = "ALL";
	$i++;
	$ipallow->[$i]->{src_ip} = '::1';
	$ipallow->[$i]->{action} = 'ip_allow';
	$ipallow->[$i]->{method} = "ALL";
	$i++;
	my $rs_parameter =
		$self->db->resultset('ProfileParameter')
		->search( { profile => $server->profile->id }, { prefetch => [ { parameter => undef }, { profile => undef } ] } );

	while ( my $row = $rs_parameter->next ) {
		if ( $row->parameter->name eq 'purge_allow_ip' && $row->parameter->config_file eq 'ip_allow.config' ) {
			$ipallow->[$i]->{src_ip} = $row->parameter->value;
			$ipallow->[$i]->{action} = "ip_allow";
			$ipallow->[$i]->{method} = "ALL";
			$i++;
		}
	}
	if ( $server->type->name eq 'MID' ) {
		my @edge_locs = $self->db->resultset('Cachegroup')->search( { parent_cachegroup_id => $server->cachegroup->id } )->get_column('id')->all();
		my %allow_locs;
		foreach my $loc (@edge_locs) {
			$allow_locs{$loc} = 1;
		}

		# get all the EDGE and RASCAL nets
		my @allowed_netaddrips;
		my @allowed_ipv6_netaddrips;
		my $etype = &type_id( $self, "EDGE" );
		my $rtype = &type_id( $self, "RASCAL" );
		my $rs_allowed = $self->db->resultset('Server')->search( { -or => [ type => $etype, type => $rtype ] } );
		while ( my $allow_row = $rs_allowed->next ) {
			if ( $allow_row->type->id == $rtype
				|| ( defined( $allow_locs{ $allow_row->cachegroup->id } ) && $allow_locs{ $allow_row->cachegroup->id } == 1 ) )
			{
				push( @allowed_netaddrips, NetAddr::IP->new( $allow_row->ip_address, $allow_row->ip_netmask ) );
				if ( defined $allow_row->ip6_address ) {
					push( @allowed_ipv6_netaddrips, NetAddr::IP->new( $allow_row->ip6_address ) );
				}
			}
		}

		# compact, coalesce and compact combined list again
		# if more than 5 servers are in a /24, list that /24 - TODO JvD: parameterize
		my @compacted_list = NetAddr::IP::Compact(@allowed_netaddrips);
		my $coalesced_list = NetAddr::IP::Coalesce( 24, 5, @allowed_netaddrips );
		my @combined_list  = NetAddr::IP::Compact( @allowed_netaddrips, @{$coalesced_list} );
		foreach my $net (@combined_list) {
			my $range = $net->range();
			$range =~ s/\s+//g;
			$ipallow->[$i]->{src_ip} = $range;
			$ipallow->[$i]->{action} = "ip_allow";
			$ipallow->[$i]->{method} = "ALL";
			$i++;
		}

		# now add IPv6. TODO JvD: paremeterize support enabled on/ofd and /48 and number 5
		my @compacted__ipv6_list = NetAddr::IP::Compact(@allowed_ipv6_netaddrips);
		my $coalesced_ipv6_list  = NetAddr::IP::Coalesce( 48, 5, @allowed_ipv6_netaddrips );
		my @combined_ipv6_list   = NetAddr::IP::Compact( @allowed_ipv6_netaddrips, @{$coalesced_ipv6_list} );
		foreach my $net (@combined_ipv6_list) {
			my $range = $net->range();
			$range =~ s/\s+//g;
			$ipallow->[$i]->{src_ip} = $range;
			$ipallow->[$i]->{action} = "ip_allow";
			$ipallow->[$i]->{method} = "ALL";
			$i++;
		}

		# allow RFC 1918 server space - TODO JvD: parameterize
		$ipallow->[$i]->{src_ip} = '172.16.0.0-172.31.255.255';
		$ipallow->[$i]->{action} = 'ip_allow';
		$ipallow->[$i]->{method} = "ALL";
		$i++;

		# end with a deny
		$ipallow->[$i]->{src_ip} = '0.0.0.0-255.255.255.255';
		$ipallow->[$i]->{action} = 'ip_deny';
		$ipallow->[$i]->{method} = "ALL";
		$i++;
		$ipallow->[$i]->{src_ip} = '::-ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff';
		$ipallow->[$i]->{action} = 'ip_deny';
		$ipallow->[$i]->{method} = "ALL";
		$i++;
	}
	else {

		# for edges deny "PUSH|PURGE|DELETE", allow everything else to everyone.
		$ipallow->[$i]->{src_ip} = '0.0.0.0-255.255.255.255';
		$ipallow->[$i]->{action} = 'ip_deny';
		$ipallow->[$i]->{method} = "PUSH|PURGE|DELETE";
		$i++;
		$ipallow->[$i]->{src_ip} = '::-ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff';
		$ipallow->[$i]->{action} = 'ip_deny';
		$ipallow->[$i]->{method} = "PUSH|PURGE|DELETE";
		$i++;
	}

	return $ipallow;
}

sub facts {
	my $self     = shift;
	my $id       = shift;
	my $filename = shift;

	my $server = $self->server_data($id);
	my $text   = $self->header_comment( $server->host_name );
	$text .= "profile:" . $server->profile->name . "\n";

	return $text;
}

sub logs_xml_dot_config {
	my $self     = shift;
	my $id       = shift;
	my $filename = shift;

	my $server = $self->server_data($id);
	my $data   = $self->param_data( $server, $filename );
	my $text   = "<!-- Generated for " . $server->host_name . " by " . &name_version_string($self) . " - Do not edit!! -->\n";

	my $log_format_name                 = $data->{"LogFormat.Name"}               || "";
	my $log_object_filename             = $data->{"LogObject.Filename"}           || "";
	my $log_object_format               = $data->{"LogObject.Format"}             || "";
	my $log_object_rolling_enabled      = $data->{"LogObject.RollingEnabled"}     || "";
	my $log_object_rolling_interval_sec = $data->{"LogObject.RollingIntervalSec"} || "";
	my $log_object_rolling_offset_hr    = $data->{"LogObject.RollingOffsetHr"}    || "";
	my $log_object_rolling_size_mb      = $data->{"LogObject.RollingSizeMb"}      || "";
	my $format                          = $data->{"LogFormat.Format"};
	$format =~ s/"/\\\"/g;
	$text .= "<LogFormat>\n";
	$text .= "  <Name = \"" . $log_format_name . "\"/>\n";
	$text .= "  <Format = \"" . $format . "\"/>\n";
	$text .= "</LogFormat>\n";
	$text .= "<LogObject>\n";
	$text .= "  <Format = \"" . $log_object_format . "\"/>\n";
	$text .= "  <Filename = \"" . $log_object_filename . "\"/>\n";
	$text .= "  <RollingEnabled = " . $log_object_rolling_enabled . "/>\n" unless defined();
	$text .= "  <RollingIntervalSec = " . $log_object_rolling_interval_sec . "/>\n";
	$text .= "  <RollingOffsetHr = " . $log_object_rolling_offset_hr . "/>\n";
	$text .= "  <RollingSizeMb = " . $log_object_rolling_size_mb . "/>\n";
	$text .= "</LogObject>\n";

	return $text;
}

sub cacheurl_dot_config {
	my $self     = shift;
	my $id       = shift;
	my $filename = shift;
	my $data     = shift;

	my $server = $self->server_data($id);
	my $text   = $self->header_comment( $server->host_name );
	if ( !defined($data) ) {
		$data = $self->ds_data($server);
	}

	if ( $filename eq "cacheurl_qstring.config" ) {    # This is the per remap drop qstring w cacheurl use case, the file is the same for all remaps
		$text .= "http://([^?]+)(?:\\?|\$)  http://\$1\n";
		$text .= "https://([^?]+)(?:\\?|\$)  https://\$1\n";
	}
	elsif ( $filename =~ /cacheurl_(.*).config/ )
	{    # Yes, it's possibe to have the same plugin invoked multiple times on the same remap line, this is from the remap entry
		my $ds_xml_id = $1;
		my $ds = $self->db->resultset('Deliveryservice')->search( { xml_id => $ds_xml_id }, { prefetch => [ 'type', 'profile' ] } )->single();
		if ($ds) {
			$text .= $ds->cacheurl . "\n";
		}
	}
	elsif ( $filename eq "cacheurl.config" ) {    # this is the global drop qstring w cacheurl use case
		foreach my $remap ( @{ $data->{dslist} } ) {
			if ( $remap->{qstring_ignore} == 1 ) {
				my $org = $remap->{org};
				$org =~ /(https?:\/\/)(.*)/;
				$text .= "$1(" . $2 . "/[^?]+)(?:\\?|\$)  $1\$1\n";
			}
		}

	}

	$text =~ s/\s*__RETURN__\s*/\n/g;
	return $text;
}

# generic key $separator value pairs from the data hash
sub url_sig_config {
	my $self = shift;
	my $id   = shift;
	my $file = shift;

	my $sep    = defined( $separator->{$file} ) ? $separator->{$file} : " = ";
	my $server = $self->server_data($id);
	my $data   = $self->param_data( $server, $file );
	my $text   = $self->header_comment( $server->host_name );

	my $response_container = $self->riak_get( URL_SIG_KEYS_BUCKET, $file );
	my $response = $response_container->{response};
	if ( $response->is_success() ) {
		my $response_json = decode_json( $response->content );
		my $keys          = $response_json;
		foreach my $parameter ( sort keys %{$data} ) {
			if ( !defined($keys) || $parameter !~ /^key\d+/ ) {    # only use key parameters as a fallback (temp, remove me later)
				$text .= $parameter . $sep . $data->{$parameter} . "\n";
			}
		}

		# $self->app->log->debug( "keys #-> " . Dumper($keys) );
		foreach my $parameter ( sort keys %{$keys} ) {
			$text .= $parameter . $sep . $keys->{$parameter} . "\n";
		}
		return $text;
	}
	else {
		my $error = $response->content;
		return "Error: " . $error;
	}
}

# generic key $separator value pairs from the data hash
sub generic_config {
	my $self = shift;
	my $id   = shift;
	my $file = shift;

	my $sep = defined( $separator->{$file} ) ? $separator->{$file} : " = ";

	my $server = $self->server_data($id);
	my $data   = $self->param_data( $server, $file );
	my $text   = $self->header_comment( $server->host_name );
	foreach my $parameter ( sort keys %{$data} ) {
		my $p_name = $parameter;
		$p_name =~ s/__\d+$//;
		$text .= $p_name . $sep . $data->{$parameter} . "\n";
	}
	return $text;
}

sub volume_dot_config {
	my $self = shift;
	my $id   = shift;
	my $file = shift;

	my $server = $self->server_data($id);
	my $data   = $self->param_data( $server, "storage.config" );
	my $text   = $self->header_comment( $server->host_name );
	if ( defined( $data->{RAM_Drive_Prefix} ) ) {

		# TODO JvD: More vols??
		$text .= "# 12M NOTE: This is running with forced volumes - the size is irrelevant\n";
		$text .= "volume=" . $data->{RAM_Volume} . " scheme=http size=1%\n";
		$text .= "volume=" . $data->{Disk_Volume} . " scheme=http size=1%\n";
	}
	else {
		$text .= "volume=1 scheme=http size=100%\n";
	}
	return $text;
}

sub hosting_dot_config {
	my $self = shift;
	my $id   = shift;
	my $file = shift;
	my $data = shift;

	my $server = $self->server_data($id);
	my $text   = $self->header_comment( $server->host_name );
	if ( !defined($data) ) {
		$data = $self->ds_data($server);
	}

	if ( defined( $data->{RAM_Volume} ) ) {
		$text .= "# 12M NOTE: volume " . $data->{RAM_Volume} . " is the RAM volume\n";
		$text .= "# 12M NOTE: volume " . $data->{Disk_Volume} . " is the Disk volume\n";
		my %listed = ();
		foreach my $remap ( @{ $data->{dslist} } ) {
			if (   ( ( $remap->{type} =~ /_LIVE$/ || $remap->{type} =~ /_LIVE_NATNL$/ ) && $server->type->name eq 'EDGE' )
				|| ( $remap->{type} =~ /_LIVE_NATNL$/ && $server->type->name eq 'MID' ) )
			{
				if ( defined( $listed{ $remap->{org} } ) ) { next; }
				my $org_fqdn = $remap->{org};
				$org_fqdn =~ s/https?:\/\///;
				$text .= "hostname=" . $org_fqdn . " volume=" . $data->{RAM_Volume} . "\n";
				$listed{ $remap->{org} } = 1;
			}
		}
	}
	my $dvolno = 1;
	if ( defined( $data->{Disk_Volume} ) ) {
		$dvolno = $data->{Disk_Volume};
	}
	$text .= "hostname=*   volume=" . $dvolno . "\n";

	return $text;
}

sub storage_dot_config {
	my $self = shift;
	my $id   = shift;
	my $file = shift;

	my $server = $self->server_data($id);
	my $text   = $self->header_comment( $server->host_name );
	my $data   = $self->param_data( $server, $file );

	if ( defined( $data->{RAM_Drive_Prefix} ) ) {
		my $drive_prefix = $data->{RAM_Drive_Prefix};
		my @drive_postfix = split( /,/, $data->{RAM_Drive_Letters} );
		foreach my $l ( sort @drive_postfix ) {
			$text .= $drive_prefix . $l . " volume=" . $data->{RAM_Volume} . "\n";
		}
		$drive_prefix = $data->{Drive_Prefix};
		@drive_postfix = split( /,/, $data->{Drive_Letters} );
		foreach my $l ( sort @drive_postfix ) {
			$text .= $drive_prefix . $l . " volume=" . $data->{Disk_Volume} . "\n";
		}
	}
	else {

		# there is no volume patch, so no assignment in storaage.config
		my $drive_prefix = $data->{Drive_Prefix};
		my @drive_postfix = split( /,/, $data->{Drive_Letters} );
		foreach my $l ( sort @drive_postfix ) {
			$text .= $drive_prefix . $l . "\n";
		}
	}

	return $text;
}

sub ats_dot_rules {
	my $self = shift;
	my $id   = shift;
	my $file = shift;

	my $server = $self->server_data($id);
	my $text   = $self->header_comment( $server->host_name );
	my $data   = $self->param_data( $server, "storage.config" );    # ats.rules is based on the storage.config params

	my $drive_prefix = $data->{Drive_Prefix};
	my @drive_postfix = split( /,/, $data->{Drive_Letters} );
	foreach my $l ( sort @drive_postfix ) {
		$drive_prefix =~ s/\/dev\///;
		$text .= "KERNEL==\"" . $drive_prefix . $l . "\", OWNER=\"ats\"\n";
	}
	if ( defined( $data->{RAM_Drive_Prefix} ) ) {
		$drive_prefix = $data->{RAM_Drive_Prefix};
		@drive_postfix = split( /,/, $data->{RAM_Drive_Letters} );
		foreach my $l ( sort @drive_postfix ) {
			$drive_prefix =~ s/\/dev\///;
			$text .= "KERNEL==\"" . $drive_prefix . $l . "\", OWNER=\"ats\"\n";
		}
	}

	return $text;
}

sub cache_dot_config {
	my $self = shift;
	my $id   = shift;
	my $file = shift;
	my $data = shift;

	my $server = $self->server_data($id);
	my $text   = $self->header_comment( $server->host_name );
	if ( !defined($data) ) {
		$data = $self->ds_data($server);
	}

	foreach my $remap ( @{ $data->{dslist} } ) {
		if ( $remap->{type} eq "HTTP_NO_CACHE" ) {
			my $org_fqdn = $remap->{org};
			$org_fqdn =~ s/https?:\/\///;
			$text .= "dest_domain=" . $org_fqdn . " scheme=http action=never-cache\n";
		}
	}
	return $text;
}

sub remap_dot_config {
	my $self = shift;
	my $id   = shift;
	my $file = shift;
	my $data = shift;

	my $server = $self->server_data($id);
	my $pdata  = $self->param_data( $server, 'package' );
	my $text   = $self->header_comment( $server->host_name );
	if ( !defined($data) ) {
		$data = $self->ds_data($server);
	}

	if ( $server->type->name eq 'MID' ) {
		my %mid_remap;
		foreach my $remap ( @{ $data->{dslist} } ) {

			if ( defined( $mid_remap{ $remap->{org} } ) ) {
				next;    # skip remap rules from extra HOST_REGEXP entries
			}

			if ( defined( $remap->{mid_header_rewrite} ) && $remap->{mid_header_rewrite} ne "" ) {
				$mid_remap{ $remap->{org} } .= " \@plugin=header_rewrite.so \@pparam=" . $remap->{mid_hdr_rw_file};
			}
			if ( $remap->{qstring_ignore} == 1 ) {
				$mid_remap{ $remap->{org} } .= " \@plugin=cacheurl.so \@pparam=cacheurl_qstring.config";
			}
			if ( defined( $remap->{cacheurl} ) && $remap->{cacheurl} ne "" ) {
				$mid_remap{ $remap->{org} } .= " \@plugin=cacheurl.so \@pparam=" . $remap->{cacheurl_file};
			}
			if ( $remap->{range_request_handling} == 2 ) {
				$mid_remap{ $remap->{org} } .= " \@plugin=cache_range_requests.so";
			}
		}
		foreach my $key ( keys %mid_remap ) {
			$text .= "map " . $key . " " . $key . $mid_remap{$key} . "\n";
		}
		return $text;
	}

	# mids don't get here.
	foreach my $remap ( @{ $data->{dslist} } ) {
		foreach my $map_from ( keys %{ $remap->{remap_line} } ) {
			my $map_to = $remap->{remap_line}->{$map_from};
			$text = $self->build_remap_line( $server, $pdata, $text, $data, $remap, $map_from, $map_to );
		}
		foreach my $map_from ( keys %{ $remap->{remap_line2} } ) {
			my $map_to = $remap->{remap_line2}->{$map_from};
			$text = $self->build_remap_line( $server, $pdata, $text, $data, $remap, $map_from, $map_to );
		}
	}
	return $text;
}

sub build_remap_line {
	my $self     = shift;
	my $server   = shift;
	my $pdata    = shift;
	my $text     = shift;
	my $data     = shift;
	my $remap    = shift;
	my $map_from = shift;
	my $map_to   = shift;

	if ( $remap->{type} eq 'ANY_MAP' ) {
		$text .= $remap->{remap_text} . "\n";
		return $text;
	}

	my $host_name = $data->{host_name};
	my $dscp      = $remap->{dscp};

	$map_from =~ s/ccr/$host_name/;

	if ( defined( $pdata->{'dscp_remap'} ) ) {
		$text .= "map	" . $map_from . "     " . $map_to . " \@plugin=dscp_remap.so \@pparam=" . $dscp;
	}
	else {
		$text .= "map	" . $map_from . "     " . $map_to . " \@plugin=header_rewrite.so \@pparam=dscp/set_dscp_" . $dscp . ".config";
	}
	if ( defined( $remap->{edge_header_rewrite} ) ) {
		$text .= " \@plugin=header_rewrite.so \@pparam=" . $remap->{hdr_rw_file};
	}
	if ( $remap->{signed} == 1 ) {
		$text .= " \@plugin=url_sig.so \@pparam=url_sig_" . $remap->{ds_xml_id} . ".config";
	}
	if ( $remap->{qstring_ignore} == 2 ) {
		my $dqs_file = "drop_qstring.config";
		$text .= " \@plugin=regex_remap.so \@pparam=" . $dqs_file;
	}
	elsif ( $remap->{qstring_ignore} == 1 ) {
		my $global_exists =
			$self->db->resultset('ProfileParameter')
			->search( { -and => [ profile => $server->profile->id, 'parameter.config_file' => 'cacheurl.config', 'parameter.name' => 'location' ] },
			{ prefetch => [ 'parameter', 'profile' ] } )->single();
		if ($global_exists) {
			$self->app->log->debug(
				"qstring_ignore == 1, but global cacheurl.config param exists, so skipping remap rename config_file=cacheurl.config parameter if you want to change"
			);
		}
		else {
			$text .= " \@plugin=cacheurl.so \@pparam=cacheurl_qstring.config";
		}
	}
	if ( defined( $remap->{cacheurl} ) && $remap->{cacheurl} ne "" ) {
		$text .= " \@plugin=cacheurl.so \@pparam=" . $remap->{cacheurl_file};
	}

	# Note: should use full path here?
	if ( defined( $remap->{regex_remap} ) && $remap->{regex_remap} ne "" ) {
		$text .= " \@plugin=regex_remap.so \@pparam=regex_remap_" . $remap->{ds_xml_id} . ".config";
	}
	if ( $remap->{range_request_handling} == 1 ) {
		$text .= " \@plugin=background_fetch.so \@pparam=bg_fetch.config";
	}
	elsif ( $remap->{range_request_handling} == 2 ) {
		$text .= " \@plugin=cache_range_requests.so ";
	}
	if ( defined( $remap->{remap_text} ) ) {
		$text .= " " . $remap->{remap_text};
	}
	$text .= "\n";
	return $text;
}

sub parent_dot_config {
	my $self = shift;
	my $id   = shift;
	my $file = shift;
	my $data = shift;

	my $server      = $self->server_data($id);
	my $server_type = $server->type->name;
	my $text        = $self->header_comment( $server->host_name );
	if ( !defined($data) ) {
		$data = $self->ds_data($server);
	}

	# Origin Shield or Multi Site Origin
	$self->app->log->debug("id = $id and server_type = $server_type");
	if ( $server_type eq 'MID' ) {
		foreach my $ds ( @{ $data->{dslist} } ) {
			my $xml_id            = $ds->{ds_xml_id};
			my $os                = $ds->{origin_shield};
			my $multi_site_origin = defined( $ds->{multi_site_origin} ) ? $ds->{multi_site_origin} : 0;

			my $org_fqdn = $ds->{org};
			$org_fqdn =~ s/https?:\/\///;
			if ( defined($os) ) {
				my $algorithm = "";
				my $param =
					$self->db->resultset('ProfileParameter')
					->search( { -and => [ profile => $server->profile->id, 'parameter.config_file' => 'parent.config', 'parameter.name' => 'algorithm' ] },
					{ prefetch => [ 'parameter', 'profile' ] } )->single();
				my $pselect_alg = defined($param) ? $param->parameter->value : undef;
				if ( defined($pselect_alg) ) {
					$algorithm = "round_robin=$pselect_alg";
				}
				$text .= "dest_domain=$org_fqdn parent=$os $algorithm go_direct=true\n";
			}
			elsif ($multi_site_origin) {

				$text .= "dest_domain=$org_fqdn parent=\"";
				my $pinfo = $self->parent_data($server);

				#print Dumper($pinfo);
				foreach my $parent ( @{ $pinfo->{$org_fqdn} } ) {
					if ( $parent->{use_ip_address} == 1 ) {
						$text .= $parent->{ip_address} . ":" . $parent->{port} . "|" . $parent->{weight} . ";";
					}
					else {
						$text .= $parent->{"host_name"} . "." . $parent->{"domain_name"} . ":" . $parent->{"port"} . "|" . $parent->{"weight"} . ";";
					}
				}
				$text .= "\" round_robin=consistent_hash go_direct=false parent_is_proxy=false\n";
			}
		}

		#$text .= "dest_domain=. go_direct=true\n"; # this is implicit.
		$self->app->log->debug( "MID PARENT.CONFIG:\n" . $text . "\n" );
		return $text;
	}
	else {

		#"True" Parent
		my $pinfo = $self->parent_data($server);

		my %done = ();

		foreach my $remap ( @{ $data->{dslist} } ) {
			if ( $remap->{type} eq "HTTP_NO_CACHE" || $remap->{type} eq "HTTP_LIVE" || $remap->{type} eq "DNS_LIVE" ) {
				if ( !defined( $done{ $remap->{org} } ) ) {
					my $org_fqdn = $remap->{org};
					$org_fqdn =~ s/https?:\/\///;
					$text .= "dest_domain=" . $org_fqdn . " go_direct=true\n";
					$done{ $remap->{org} } = 1;
				}
			}
		}

		my $param =
			$self->db->resultset('ProfileParameter')
			->search( { -and => [ profile => $server->profile->id, 'parameter.config_file' => 'parent.config', 'parameter.name' => 'algorithm' ] },
			{ prefetch => [ 'parameter', 'profile' ] } )->single();
		my $pselect_alg = defined($param) ? $param->parameter->value : undef;
		if ( defined($pselect_alg) && $pselect_alg eq 'consistent_hash' ) {

			$text .= "dest_domain=. parent=\"";
			foreach my $parent ( @{ $pinfo->{"all_parents"} } ) {
				$text .= $parent->{"host_name"} . "." . $parent->{"domain_name"} . ":" . $parent->{"port"} . "|" . $parent->{"weight"} . ";";
			}
			$text .= "\" round_robin=consistent_hash go_direct=false";
		}
		else {    # default to old situation.
			$text .= "dest_domain=. parent=\"";
			foreach my $parent ( @{ $pinfo->{"all_parents"} } ) {
				$text .= $parent->{"host_name"} . "." . $parent->{"domain_name"} . ":" . $parent->{"port"} . ";";
			}
			$text .= "\" round_robin=urlhash go_direct=false";
		}

		$param =
			$self->db->resultset('ProfileParameter')
			->search( { -and => [ profile => $server->profile->id, 'parameter.config_file' => 'parent.config', 'parameter.name' => 'qstring' ] },
			{ prefetch => [ 'parameter', 'profile' ] } )->single();
		my $qstring = defined($param) ? $param->parameter->value : undef;
		if ( defined($qstring) ) {
			$text .= " qstring=" . $qstring;
		}

		$text .= "\n";

		# $self->app->log->debug($text);
		return $text;
	}
}

sub ip_allow_dot_config {
	my $self = shift;
	my $id   = shift;
	my $file = shift;

	my $server = $self->server_data($id);
	my $text   = $self->header_comment( $server->host_name );
	my $data   = $self->ip_allow_data( $server, $file );

	foreach my $access ( @{$data} ) {
		$text .= sprintf( "src_ip=%-70s action=%-10s method=%-20s\n", $access->{src_ip}, $access->{action}, $access->{method} );
	}

	return $text;
}

sub regex_revalidate_dot_config {
	my $self = shift;
	my $id   = shift;
	my $file = shift;

	# note: Calling this from outside Configfiles, so $self->method doesn't work. TODO: Be smarter
	# my $server = $self->server_data($id);
	# my $text   = $self->header_comment( $server->host_name );
	my $server = &server_data( $self, $id );

	# Purges are CDN - wide.
	my $param =
		$self->db->resultset('ProfileParameter')
		->search( { -and => [ profile => $server->profile->id, 'parameter.config_file' => 'CRConfig.json', 'parameter.name' => 'domain_name' ] },
		{ prefetch => [ { parameter => undef }, { profile => undef } ] } )->single();
	my $server_domain = $param->parameter->value;

	my $text = "# DO NOT EDIT - Generated for " . $server_domain . " by " . &name_version_string($self) . " on " . `date`;

	my $max_days =
		$self->db->resultset('Parameter')->search( { name => "maxRevalDurationDays" }, { config_file => "regex_revalidate.config" } )->get_column('value')
		->single;
	my $interval = "> now() - interval '$max_days day'";    # postgres
	if ( $self->db->storage->isa("DBIx::Class::Storage::DBI::mysql") ) {
		$interval = "> now() - interval $max_days day";
	}

	my %regex_time;
	my $rs = $self->db->resultset('Job')->search( { start_time => \$interval } );
	##DN- even though we made these params, the front-end is still hard-coded to validate ttl between 48 - 672...
	my $max_hours =
		$self->db->resultset('Parameter')->search( { name => "ttl_max_hours" }, { config_file => "regex_revalidate.config" } )->get_column('value')->single;
	my $min_hours =
		$self->db->resultset('Parameter')->search( { name => "ttl_min_hours" }, { config_file => "regex_revalidate.config" } )->get_column('value')->single;
	while ( my $row = $rs->next ) {
		my $parameters = $row->parameters;
		my $ttl;
		if ( $row->keyword eq "PURGE" && ( defined($parameters) && $parameters =~ /TTL:(\d+)h/ ) ) {
			$ttl = $1;
			if ( $ttl > $min_hours || $ttl < $max_hours ) {
				$ttl = $min_hours;
			}
		}
		else {
			next;
		}

		my $date       = new Date::Manip::Date();
		my $start_time = $row->start_time;
		my $start_date = ParseDate($start_time);
		my $end_date   = DateCalc( $start_date, ParseDateDelta( $ttl . ':00:00' ) );
		my $err        = $date->parse($end_date);
		if ($err) {
			print "ERROR ON DATE CONVERSION:" . $err;
			next;
		}
		my $purge_end = $date->printf("%s");    # this is in secs since the unix epoch

		if ( $purge_end < time() ) {            # skip purges that have an end_time in the past
			next;
		}
		my $asset_url = $row->asset_url;

		my ( $scheme, $asset_hostname, $path, $query, $fragment ) = $row->asset_url =~ m|(?:([^:/?#]+):)?(?://([^/?#]*))?([^?#]*)(?:\?([^#]*))?(?:#(.*))?|;
		my $org_server = "$scheme://$asset_hostname";

		my $rs =
			$self->db->resultset('Deliveryservice')
			->search( { org_server_fqdn => $org_server }, { prefetch => [ { 'type' => undef }, { 'profile' => undef } ] } );

		while ( my $dsrow = $rs->next ) {
			my $ds_cdn_domain = $self->db->resultset('Parameter')->search(
				{ -and => [ 'me.name' => 'domain_name', 'deliveryservices.id' => $dsrow->id ] },
				{
					join     => { profile_parameters => { profile => { deliveryservices => undef } } },
					distinct => 1
				}
			)->get_column('value')->single();
			if ( $ds_cdn_domain eq $server_domain ) {

				# if there are multipe with same re, pick the longes lasting.
				if ( !defined( $regex_time{ $row->asset_url } )
					|| ( defined( $regex_time{ $row->asset_url } ) && $purge_end > $regex_time{ $row->asset_url } ) )
				{
					$regex_time{ $row->asset_url } = $purge_end;
				}
			}
		}
	}

	foreach my $re ( sort keys %regex_time ) {
		$text .= $re . " " . $regex_time{$re} . "\n";
	}

	return $text;
}

sub take_and_bake {
	my $self = shift;
	my $id   = shift;
	my $file = shift;

	my $server = $self->server_data($id);
	my $data   = $self->param_data( $server, $file );
	my $text   = $self->header_comment( $server->host_name );
	foreach my $parameter ( sort keys %{$data} ) {
		$text .= $data->{$parameter} . "\n";
	}
	return $text;
}

sub drop_qstring_dot_config {
	my $self = shift;
	my $id   = shift;
	my $file = shift;

	my $server = $self->server_data($id);
	my $text   = $self->header_comment( $server->host_name );

	$server = &server_data( $self, $id );
	my $drop_qstring =
		$self->db->resultset('ProfileParameter')
		->search( { -and => [ profile => $server->profile->id, 'parameter.name' => 'content', 'parameter.config_file' => 'drop_qstring.config' ] },
		{ prefetch => [ 'parameter', 'profile' ] } )->get_column('parameter.value')->single();
	if ($drop_qstring) {
		$text .= $drop_qstring . "\n";
	}
	else {
		$text .= "/([^?]+) \$s://\$t/\$1\n";
	}
	return $text;
}

sub header_rewrite_dot_config {
	my $self = shift;
	my $id   = shift;
	my $file = shift;

	my $server    = $self->server_data($id);
	my $text      = $self->header_comment( $server->host_name );
	my $ds_xml_id = undef;
	if ( $file =~ /^hdr_rw_mid_(.*)\.config$/ ) {
		$ds_xml_id = $1;
		my $ds = $self->db->resultset('Deliveryservice')->search( { xml_id => $ds_xml_id }, { prefetch => [ 'type', 'profile' ] } )->single();
		my $actions = $ds->mid_header_rewrite;
		$text .= $actions . "\n";
	}
	elsif ( $file =~ /^hdr_rw_(.*)\.config$/ ) {
		$ds_xml_id = $1;
		my $ds = $self->db->resultset('Deliveryservice')->search( { xml_id => $ds_xml_id }, { prefetch => [ 'type', 'profile' ] } )->single();
		my $actions = $ds->edge_header_rewrite;
		$text .= $actions . "\n";
	}

	$text =~ s/\s*__RETURN__\s*/\n/g;
	my $ipv4 = $server->ip_address;
	$text =~ s/__CACHE_IPV4__/$ipv4/g;
	return $text;
}

sub regex_remap_dot_config {
	my $self = shift;
	my $id   = shift;
	my $file = shift;

	my $server = $self->server_data($id);
	my $text   = $self->header_comment( $server->host_name );

	if ( $file =~ /^regex_remap_(.*)\.config$/ ) {
		my $ds_xml_id = $1;
		my $ds = $self->db->resultset('Deliveryservice')->search( { xml_id => $ds_xml_id }, { prefetch => [ 'type', 'profile' ] } )->single();
		$text .= $ds->regex_remap . "\n";
	}

	$text =~ s/\s*__RETURN__\s*/\n/g;
	return $text;
}

sub header_rewrite_dscp_dot_config {
	my $self = shift;
	my $id   = shift;
	my $file = shift;

	my $server = $self->server_data($id);
	my $text   = $self->header_comment( $server->host_name );
	my $dscp_decimal;
	if ( $file =~ /^set_dscp_(\d+)\.config$/ ) {
		$dscp_decimal = $1;
	}
	else {
		$text = "An error occured generating the DSCP header rewrite file.";
	}
	$text .= "cond %{REMAP_PSEUDO_HOOK}\n" . "set-conn-dscp " . $dscp_decimal . " [L]\n";

	return $text;
}

sub to_ext_dot_config {
	my $self = shift;
	my $id   = shift;
	my $file = shift;

	my $server = $self->server_data($id);
	my $text   = $self->header_comment( $server->host_name );

	# get the subroutine name for this file from the parameter
	my $subroutine =
		$self->db->resultset('ProfileParameter')
		->search( { -and => [ profile => $server->profile->id, 'parameter.config_file' => $file, 'parameter.name' => 'SubRoutine' ] },
		{ prefetch => [ 'parameter', 'profile' ] } )->get_column('parameter.value')->single();
	$self->app->log->error( "ToExtDotConfigFile == " . $subroutine );

	my $package;
	( $package = $subroutine ) =~ s/(.*)(::)(.*)/$1/;
	eval "use $package;";

	# And call it - the below calls the subroutine in the var $subroutine.
	$text .= &{ \&{$subroutine} }( $self, $id, $file );

	return $text;
}

sub ssl_multicert_dot_config {
	my $self = shift;
	my $id   = shift;
	my $file = shift;

	#id == hostname
	my $server = $self->server_data($id);
	my $text   = $self->header_comment( $server->host_name );

	# get a list of delivery services for the server
	my $protocol_search = '> 0';
	my @ds_list = $self->db->resultset('Deliveryservice')->search( { -and => [ 'server.id' => $server->id, 'me.protocol' => \$protocol_search ] },
		{ join => { deliveryservice_servers => { server => undef } }, } );
	foreach my $ds (@ds_list) {
		my $ds_id        = $ds->id;
		my $xml_id       = $ds->xml_id;
		my $rs_ds        = $self->db->resultset('Deliveryservice')->search( { 'me.id' => $ds_id } );
		my $data         = $rs_ds->single;
		my $domain_name  = UI::DeliveryService::get_cdn_domain( $self, $ds_id );
		my $ds_regexes   = UI::DeliveryService::get_regexp_set( $self, $ds_id );
		my @example_urls = UI::DeliveryService::get_example_urls( $self, $ds_id, $ds_regexes, $data, $domain_name, $data->protocol );

		#first one is the one we want
		my $hostname = $example_urls[0];
		$hostname =~ /(https?:\/\/)(.*)/;
		my $new_host = $2;
		my $key_name = "$new_host.key";
		$new_host =~ tr/./_/;
		my $cer_name = $new_host . "_cert.cer";

		$text .= "ssl_cert_name=$cer_name\t ssl_key_name=$key_name\n";
	}
	return $text;
}

# This is a temporary workaround until we have real partial object caching support in ATS, so hardcoding for now
sub bg_fetch_dot_config {
	my $self = shift;
	my $id   = shift;

	my $server = $self->server_data($id);
	my $text   = $self->header_comment( $server->host_name );
	$text .= "include User-Agent *\n";

	return $text;
}

1;
