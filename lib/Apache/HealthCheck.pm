package Apache::HealthCheck;

use 5.006001;
use Apache::Constants qw(:common);
use LWP::UserAgent;
use HTTP::Request;
use strict;
use warnings;

our @ISA = qw();

our $VERSION = '0.01';

sub handler {
    my ($r) = @_;

    my @check_urls = $r->dir_config->get('CheckURL');
    my $hn_success = $r->dir_config('HeaderNameSuccess');
    my $hn_fail = $r->dir_config('HeaderNameFail');
    my $hv_success = $r->dir_config('HeaderValueSuccess');
    my $hv_fail = $r->dir_config('HeaderValueFail');
    my $rc_success = $r->dir_config('ReturnCodeSuccess');
    my $rc_fail = $r->dir_config('ReturnCodeFail');
    my $html_success = $r->dir_config('HTMLSuccess');
    my $html_fail = $r->dir_config('HTMLFail');
    my $track_in_hdr = lc($r->dir_config('TrackResultsInHeader')) eq "on" ? 1 : 0;
    my $timeout = $r->dir_config('CheckTimeout') ? $r->dir_config('CheckTimeout') : 10;
    my $check_ua = $r->dir_config('CheckUserAgent') ? $r->dir_config('CheckUserAgent') : "Mozilla/5.0 (compatible; Apache::HealthCheck $VERSION;)";
    my $check_method = $r->dir_config('CheckMethod') ? $r->dir_config('CheckMethod') : "HEAD";

    my $ua = LWP::UserAgent->new(
        timeout     =>      $timeout,
        agent       =>      $check_ua,
    );

    my $tests = scalar(@check_urls);
    my $passed;

    my $i = 0;
    foreach my $url (@check_urls) {
        my ($result) = check_url($url, $ua, $check_method);
        ++$i;
        $passed += $result;
        if ($track_in_hdr) {
            if ($result) {
                $r->header_out("X-HealthCheck-$i-Success"       =>      $url);
            } else {
                $r->header_out("X-HealthCheck-$i-Fail"          =>      $url);
            }
        }
    }

    $r->content_type('text/html');

    if ($track_in_hdr) {
        $r->header_out("X-HealthCheck-Results"           =>      "$passed of $tests tests passed!");
    }

    if ($passed == $tests) {
        # all passed!
        $rc_success = $rc_success ? $rc_success : OK;
        $html_success = $html_success ? $html_success : "SUCCESS";
        send_result($r, $hn_success, $hv_success, $rc_success, $html_success);
    } else {
        # not all passed!
        $rc_fail = $rc_fail ? $rc_fail : SERVER_ERROR;
        $html_fail = $html_fail ? $html_fail : "FAIL";
        send_result($r, $hn_fail, $hv_fail, $rc_fail, $html_fail);
    }
    return OK;
}

sub send_result {
    my ($r, $hn, $hv, $rc, $html) = @_;

    if ($hn && $hv) {
        $r->header_out($hn      =>      $hv);
    }
    $r->status($rc);

    # print the header
    $r->send_http_header;

    if (-e $html) {
        open(HTML, '<', $html);
        {
            local $/;
            print <HTML>;
        }
        close(HTML);
    } else {
        print "$html";
    }
}

sub check_url {
    my ($in_url, $ua, $method) = @_;
    my ($url, $valid_rc_string) = split(/\s+/, $in_url);
    my (@valid_rc) = split(/\s*,\s*/, $valid_rc_string);
    my $req = HTTP::Request->new(uc($method), $url);
    my $resp = $ua->simple_request($req);

    if ($resp) {
        # check if it's a valid return code..
        return is_valid_rc($resp->code, @valid_rc);
    } else {
        # if nothing came back, return undef!
        return undef;
    }
}

sub is_valid_rc {
    my ($rc, @vrcs) = @_;
    foreach my $vrc (@vrcs) {
        if ($rc == $vrc) {
            return 1;
        }
    }
    return undef;
}

# Preloaded methods go here.

1;
__END__

=head1 NAME

Apache::HealthCheck - Checks a set of urls for conditions and puts up whatever page you want

=head1 SYNOPSIS

 <Location /health-check/>
    SetHander perl-script
    PerlModule Apache::HealthCheck
    PerlHandler Apache::HealthCheck
    PerlAddVar CheckURL "http://appserver1.example.com/ 404"
    PerlAddVar CheckURL "http://appserver1.example.com:8085/ 302"
    PerlAddVar CheckURL "http://component1.example.com:4424/ 403"
    PerlSetVar ReturnCodeSuccess 403
    PerlSetVar ReturnCodeFail 500
 </Location>

=head1 DESCRIPTION

Checks a list of urls for specific return codes and then returns a code / header / page of it's own.  This is useful for 
web server clusters where you might have a switch or a web server performing periodic health checks on an application.  This 
module allows you to harness the checks of all the urls (web services) a specific node might have in one easy to "check" URL.

If any of the URLs specified in the CheckURL directives fails to return the specified return code, the attempt is treated as 
failed, otherwise its treated as a success.

=head1 CONFIGURATION

Configuration must take place in the Apache config file using the PerlAddVar (or PerlSetVar) directives.

=over 2

=item 

B<CheckURL> - used to configure different URLs for checking.  The syntax is "http://yoursite.example.com <return code>" where 
<return code> is the numeric http code you expect back from the service.  NOTE: it's important that your URLs be URL encoded 
they must NOT contain spaces... URL encode your URLs here.  Any of these URLs failing to return the specified code results in 
an overall failure.

=item 

B<ReturnCodeSuccess> - the return code to return if all is clear (numeric valid http code 200, 302, 404, etc) (Default: 200)

=item 

B<ReturnCodeFail> - the return code to return if something failed (numeric valid http code 200, 302, 404, etc) (Default: 500)

=item

B<HeaderNameSuccess> - the name of a header to return if the check is a success (Optional)

=item

B<HeaderValueSuccess> - the corresponding value for the header returned if the check is a success (Optional)

=item

B<HeaderNameFail> - the name of a header to return if the check fails (Optional)

=item

B<HeaderValueFail> - the corresponding value for the header returned if the check fails (Optional)

=item

B<HTMLSuccess> - a path to an HTML file to send if the check is a success (Optional, default prints "SUCCESS")

=item

B<HTMLFail> - a path to an HTML file to send if the check fails (Optional, default prints "FAIL")

=item

B<TrackResultsInHeader> - Keep track of each individual check in the header using X-HealthCheck-#-Success or X-HealthCheck-#-Fail 
should be Set to On or Off (Default: Off)

=item

B<CheckTimeout> - The amount of time (in seconds) waited before the request is aborted (Default: 10)

=item

B<CheckUserAgent> - The user agent string to send while checking the different B<CheckURL>s.  Useful for cranky web apps 
that return certain content for certain browsers, as well as cleaning up logs for satistical analysis (by exempting this 
user agent from the recorded hits).

=item

B<CheckMethod> - The HTTP method to use on the CheckURL(s).  GET, POST, HEAD, etc.

=back

=head1 SEE ALSO

The Apache Documentation (http://httpd.apache.org/docs/1.3/), the mod_perl documentation (http://perl.apache.org/docs/1.0/)

=head1 AUTHOR

Michael Gregorowicz E<lt>mike@mg2.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2006 by Michael Gregorowicz

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.6.1 or,
at your option, any later version of Perl 5 you may have available.


=cut
