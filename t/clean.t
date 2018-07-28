
use strict;
use warnings;
use Git::MediaWiki qw(clean_filename);
use Test::More;

my %clean = (
	'foo'		=> 'foo',
	'foo/bar'	=> 'foo/bar',
	'foo%2Fbar' => 'foo/bar',
	'foo[bar]'	=> 'foo_%_5bbar_%_5d',
	'foo{bar}'	=> 'foo_%_7bbar_%_7d',
	'foo|bar'	=> 'foo_%_7cbar',
);

for my $s (keys %clean) {
	my $obs = clean_filename($s);
	my $exp = $clean{$s};
	is $obs, $exp, "clean $s";
}

done_testing;
