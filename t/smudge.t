
use strict;
use warnings;
use Git::Mediawiki qw(smudge_filename);
use Test::More;

my %smudge = (
	'foo'			   => 'foo',
	'foo/bar'		   => 'foo/bar',
	'foo bar'		   => 'foo_bar',
	'foo_%_5bbar_%_5d' => 'foo[bar]',
	'foo_%_7bbar_%_7d' => 'foo{bar}',
	'foo_%_7cbar'	   => 'foo|bar',
);

for my $s (keys %smudge) {
	my $obs = smudge_filename($s);
	my $exp = $smudge{$s};
	is $obs, $exp, "smudge $s";
}

done_testing;
