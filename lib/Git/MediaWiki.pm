package Git::MediaWiki; # -*- mode: cperl; cperl-indent-level: 4; tab-width: 4; indent-tabs-mode: t; -*-

use strict;

use URI::URL;
use URI::Escape;
use MediaWiki::API;
use Git;
use HTTP::Date;
use Git::MediaWiki::Constants qw(:all);
use constant NAME => "mediawiki";

sub new {
	my $class = shift;
	my @arg = @_;
	my $self = bless({}, $class);

	$self->{remotename} = $arg[0];
	if ( $arg[0] eq "mediawiki::" . $arg[1] ) {
		$self->{remotename} = '_';
	}
	$self->{url} = $arg[1];
	$self->{dir} =
	  $ENV{GIT_DIR} . '/' . NAME . '/' . $self->{remotename};
	$self->{prefix} = 'refs/' . NAME . '/' . $self->{remotename};
	$self->{DEBUG} = 0;
	$| = 1;
	return $self;
}

sub setDebug {
	my $self = shift;

	$self->{DEBUG} = shift;
}

sub debug {
	my ($self, $line, $level) = @_;
	$level ||= 1;

	warn $line if $self->{DEBUG} && $level;
}

sub raiseError {
	my ($self, $error) = @_;

	die $error;
}

sub readLine {
	my $self = shift;

	$self->debug( "waiting for git...\n", 32 );
	my $line = <STDIN>;
	if ( $line ) {
		chomp( $line );
		$self->debug( "Got: <$line>\n" );
	}
	return $line || "";
}

sub handleGitCommunication {
	my $self = shift;

	while ( my $line = $self->readLine ) {
		if ( $line eq 'capabilities' ) {
			$self->handleCapabilities;
		} elsif ( $line eq 'list' ) {
			$self->handleList;
		} elsif ( substr( $line, 0, 6 ) eq 'import' ) {
			$self->handleImport( $line );
		} elsif ( $line eq 'export' ) {
			$self->handleExport;
		} elsif ( substr( $line, 0, 7 ) eq 'option ' ) {
			$self->handleOption( $line );
		} elsif ( $line eq '' ) {
			$self->handleExit;
		} else {
			$self->handleBadInput;
		}
	}
}

sub handleCapabilities {
	my $self = shift;

	$self->debug( "Capabilities:\n", 2 );
	$self->tellGit( "refspec refs/heads/*:" . $self->{prefix} . "/*\n" );
	$self->tellGit( "import\n" );
	$self->tellGit( "list\n" );
	$self->tellGit( "push\n" );
	$self->tellGit( "\n" );
}

sub handleList {
	my $self = shift;

	$self->debug( "List: (MW remotes only have one branch)\n", 2 );
	$self->tellGit( "? refs/heads/master\n" );
	$self->tellGit( "\@refs/heads/master HEAD\n" );
	$self->tellGit( "\n" );
}

# parse a sequence of
# <cmd> <arg1>
# <cmd> <arg2>
# \n
# (like batch sequence of import and sequence of push statements)
sub getMoreRefs {
	my ($self, $cmd) = @_;
	my @refs;

	while (1) {
		chomp(my $line = <STDIN>);

		$self->debug( "Got another line: $line\n", 2 );

		if ($line =~ /^$cmd (.*)$/) {
			push(@refs, $1);
		} elsif ($line eq "") {
			$self->debug(
				"Returning: [ ". join(", ", @refs) ." ]\n", 2
			  );
			return @refs;
		} else {
			die("Invalid command in this '$cmd' batch: $_\n");
		}
	}
}

sub tellGit {
	my $self = shift @_;

	$self->debug( "Telling git: @_\n", 16 );
	print @_;
}

sub literalData {
  my ($self, $content) = @_;
  $self->tellGit( 'data ', bytes::length($content), "\n", $content );
  return;
}

sub literalDataRaw {
  # Output possibly binary content.
  my ($self, $content) = @_;
  # Avoid confusion between size in bytes and in characters
  utf8::downgrade($content);
  binmode STDOUT, ':raw';
  $self->tellGit( 'data ', bytes::length($content), "\n", $content );
  binmode STDOUT, ':encoding(UTF-8)';
  return;
}

sub fixTitle {
	my ($self, $title) = @_;
	my $ext = $self->{pageExt};

	if ($title !~ m{\.(css|js)$}i) {
		$title = "$title$ext";
	}
	return $title;
}

sub importFileRevision {
	my ($self, $commit, $fullImport, $n, $mediafile) = @_;
	my %commit = %{$commit};
	my %mediafile;
	if ($mediafile) {
		%mediafile = %{$mediafile};
	}

	my $title = $self->fixTitle( $commit{title} );
	my $comment = $commit{comment};
	my $content = $commit{content};
	my $author = $commit{author};
	my $date = $commit{date};

	$self->tellGit( "commit refs/mediawiki/$self->{remotename}/master\n" );
	$self->tellGit( "mark :${n}\n" );
	$self->tellGit( "committer ${author} <${author}\@$self->{wikiName}> $date +0000\n" );
	$self->literalData($comment);

	# If it's not a clone, we need to know where to start from
	if (!$fullImport && $n == 1) {
		$self->tellGit( "from refs/mediawiki/$self->{remotename}/master^0\n" );
	}
	if ($content ne DELETED_CONTENT) {
		$self->tellGit( "M 644 inline $title\n" );
		$self->literalData($content);
		if (%mediafile) {
			$self->tellGit( "M 644 inline $mediafile{title}\n" );
			$self->literalDataRaw($mediafile{content});
		}
		$self->tellGit( "\n\n" );
	} else {
		$self->tellGit( "D $title\n" );
	}

	# mediawiki revision number in the git note
	if ($fullImport && $n == 1) {
		$self->tellGit( "reset refs/notes/$self->{remotename}/mediawiki\n" );
	}
	$self->tellGit( "commit refs/notes/$self->{remotename}/mediawiki\n" );
	$self->tellGit( "committer ${author} <${author}\@$self->{wikiName}> $date +0000\n" );
	$self->literalData('Note added by git-mediawiki during import');
	if (!$fullImport && $n == 1) {
		$self->tellGit( "from refs/notes/$self->{remotename}/mediawiki^0\n" );
	}
	$self->tellGit( "N inline :${n}\n" );
	$self->literalData( "mediawiki_revision: $commit{mw_revision}\n".
						  "mediawiki_timestamp: $date" );
	$self->tellGit( "\n\n" );
	return;
}

sub uniq {
	my $self = shift @_;
	my %seen;
	return grep { !$seen{$_}++ } @_;
}

sub getNotes {
	my ($self, $what) = @_;

	my $note = Git::command_oneline(
		"notes", "--ref=$self->{remotename}/mediawiki", "show",
		  "refs/mediawiki/$self->{remotename}/master"
		);
	$self->debug( "Notes returned: $note\n", 32 );
	if ($note eq '') {
		return $note;
	}
	my %noted;
	foreach (split(/\n/, $note)) {
		my ($key, $value) = split(/: /, $_, 2);
		if ($what eq $key) {
			return $value;
		}
		$noted{$key} = $value;
	}
	if ($what) {
		return;
	}
	return \%noted;
}


sub getLastLocalRevision {
	my ($self) = @_;
	# Get note regarding last mediawiki revision
	my $lastRevNumber = $self->getNotes( 'mediawiki_revision' );
	if ( !$lastRevNumber ) {
		warn "No previous mediawiki revision found.\n";
		$lastRevNumber = 0;
	} else {
		$self->debug( "Last local mediawiki revision found "
						. "is $lastRevNumber.\n" );
	}
	return $lastRevNumber;
}

# Get the last remote revision without taking in account which pages
# are tracked or not. This function makes a single request to the wiki
# thus avoid a loop onto all tracked pages. This is useful for the
# fetch-by-rev option.
sub getLastGlobalRemoteRev {
	my ($self) = @_;

	$self->debug( "Getting last global remote rev." );
	if ( !$self->{lastGlobalRemoteRev} ) {
		my $query = {
			action => 'query',
			list => 'recentchanges',
			prop => 'revisions',
			rclimit => '1',
			rcdir => 'older',
		};
		$self->connectMaybe();
		my $result = $self->{wiki}->api($query);
		$self->debug(
			"Last global remote rev: "
			  . $result->{query}->{recentchanges}[0]->{revid} . "\n", 1
		  );
		$self->{lastGlobalRemoteRev}
		  = $result->{query}->{recentchanges}[0]->{revid};
	}
	return $self->{lastGlobalRemoteRev};
}

sub importRef {
	my ($self, $ref) = @_;

	# This does not seem to be accurate any more:
	#     The remote helper will call "import HEAD" and
	#     "import refs/heads/master".
	#     Since HEAD is a symbolic ref to master (by convention,
	#     followed by the output of the command "list" that we gave),
	#     we don't need to do anything in this case.
	# We're getting "import refs/heads/master" twice and uniq handles
	# it.
	if ( $ref eq 'HEAD' ) {
		return;
	}

	$self->debug( "Searching revisions...\n" );
	my $lastLocal = $self->getLastLocalRevision();
	my $fetchFrom = $lastLocal + 1;
	my $lastRemoteRev = $self->getLastGlobalRemoteRev();

	if ( $lastRemoteRev == 0 ) {
		warn "warning: trying to clone an empty wiki!?!\n";
		return;
	}
	if ( $fetchFrom > $lastRemoteRev ) {
		warn "Up to date!\n";
		return;
	}

	if ($fetchFrom == 1) {
		$self->debug( "Fetching from beginning.\n" );
	} else {
		$self->debug( "Fetching from here.\n" );
	}

	my $n = 0;
	$self->{fetchStrategy}
	  ||= Git::config( "remote.$self->{remotename}.fetchStrategy" )
	  || Git::config( "mediawiki.fetchStrategy" ) || 'by_ref';
	if ( $self->{fetchStrategy} eq 'by_rev' ) {
		$self->debug(
			"Fetching & writing export data by revs...\n", 1
		  );
		$n = $self->importRefByRevs( $fetchFrom );
	} elsif ( $self->{fetchStrategy} eq 'by_page' ) {
		$self->debug(
			"Fetching & writing export data by pages...\n", 1
		  );
		$n = $self->importRefByPages( $fetchFrom );
	} else {
		die(<<EOB);
fatal: invalid fetch strategy "$self->{fetchStrategy}". Check your
configuration variables remote.$self->{remotename}.fetchStrategy and
mediawiki.fetchStrategy
EOB
	}

	if ( $fetchFrom == 1 && $n == 0 ) {
		warn "You appear to have cloned an empty MediaWiki.\n";
		# Something has to be done remote-helper side. If nothing is
		# done, an error is thrown saying that HEAD is referring to
		# unknown object 0000000000000000000 and the clone fails.
	}
	return;
}

sub getNamespaceId {
	my ($self, $name) = @_;
	$name =~ s/ /_/g;

	if (!exists $self->{allNamespaces}->{$name}) {
		warn "Namespace '${name}' not found in cache, " .
		  "refetching namespaces ...\n";
		# NS not found => get namespace id from MW and store it in
		# configuration file.
		$self->getNamespaces();
	}
	if (!exists($self->{allNamespaces}->{$name})) {
		warn "No such namespace '${name}' on this wiki.\n";
	}
	return exists( $self->{allNamespaces}->{$name}->{id} )
	  ? $self->{allNamespaces}->{$name}->{id} : "notANameSpace";
}

sub smudgeFilename {
	my ($self, $filename, $useNS) = @_;
	my $useNs ||= "";

	if ($useNs) {
		$filename =~ s/^$useNs://;
	}
	$filename =~ s/ /_/g;

	# Decode forbidden characters encoded in clean_filename
	$filename =~ s/_%_([0-9a-fA-F][0-9a-fA-F])/sprintf('%c', hex($1))/ge;
	return $filename;
}

# Filter applied on MediaWiki data before adding them to Git
sub mediawikiSmudge {
	my ($self, $string) = @_;
	if ($string eq EMPTY_CONTENT) {
		$string = EMPTY;
	}
	# This \n is important. This is due to mediawiki's way to handle end of files.
	if ( substr( $string, -1 ) ne "\n" ) {
		$string .= "\n";
	}
	return $string;
}

# Import revisions given in second argument (array of integers).  Only
# pages appearing in the third argument (hash indexed by page titles)
# will be imported.
sub importRevIds {
	my ( $self, $fetchFrom, $revision, $pages ) = @_;
	my $n = 0;
	my $actual = 0;
	# Placeholer in case $rev->timestamp is undefined
	my $lastTimestamp = 0;

	foreach my $revId (@{$revision}) {
		# Count page even if we skip it, since we display
		# $n/$total and $total includes skipped pages.
		$n++;

		# fetch the content of the pages
		my $query = {
			action => 'query',
			prop => 'revisions',
			rvprop => 'content|timestamp|comment|user|ids',
			revids => $revId,
		};

		my $result = $self->{wiki}->api($query);
		if (!$result) {
			die "Failed to retrieve modified page for revision " .
			  $revId . "\n";
		}

		if (defined($result->{query}->{badrevids}->{$revId})) {
			# The revision id does not exist on the remote wiki.
			next;
		}

		if (!defined($result->{query}->{pages})) {
			die "Invalid revision $revId.\n";
		}

		my @results = values(%{$result->{query}->{pages}});
		my $resultPage = $results[0];
		my $rev = $results[0]->{revisions}->[0];
		my $pageTitle = $resultPage->{title};

		# FIXME
		# Differentiates classic pages and media files.
		my %mediafile;
		my ($namespace, $filename);
		# doh, doesn't work with main namespace
		if ($self->{useNamespace} && $pageTitle !~ /^$self->{useNamespace}:/) {
			$self->debug("Skipping $namespace because it doesn't match '" .
						   $self->{useNamespace} ."'\n", 1);
			return;
		} else {
			($namespace, $filename) =
			  $pageTitle =~ /^([^:]*):(.*)$/;
		}

		if (defined($namespace)) {
			my $id = $self->getNamespaceId($namespace);
			if (defined($id) and $id == $self->getNamespaceId('File')) {
				%mediafile = get_mediafile_for_page_revision(
					$filename, $rev->{timestamp}
				  );
			}
		}

		if (!exists($pages->{$pageTitle})) {
			warn "${n}/", scalar(@{$revision}),
			  ": Skipping revision #$rev->{revid} of $pageTitle\n";
			next;
		}

		$actual++;

		my %commit;
		$commit{author} = $rev->{user} || 'Anonymous';
		$commit{comment} = $rev->{comment} || EMPTY_MESSAGE;
		$commit{title} = $self->smudgeFilename($pageTitle, $self->{useNamespace});
		$commit{mw_revision} = $rev->{revid};
		$commit{content} = $self->mediawikiSmudge($rev->{'*'});
		if (!defined($rev->{timestamp})) {
			$lastTimestamp++;
		} else {
			$lastTimestamp = $rev->{timestamp};
		}
		$commit{date} = str2time($lastTimestamp);

		# If this is a revision of the media page for new version
		# of a file do one common commit for both file and media page.
		# Else do commit only for that page.
		warn "${n}/", scalar(@{$revision}),
		  ": Revision #$rev->{revid} of $commit{title}\n";
		$self->importFileRevision(
			\%commit, ($fetchFrom == 1), $actual, \%mediafile
		  );
	}

	return $actual;
}

sub importRefByRevs {
	my ( $self, $fetchFrom ) = @_;
	my $pages = $self->getPages();

	my $lastRemote = $self->getLastGlobalRemoteRev();
	my @revision = $fetchFrom..$lastRemote;
	return $self->importRevIds($fetchFrom, \@revision, $pages);
}

sub getGitRemoteList {
	my ( $self, $name ) = @_;
	my $blob = Git::config( "remote.$self->{remotename}.$name" );

	return split(
		/[\n]/, defined( $blob ) ? $blob : ''
	  );
}

sub getPageList {
	my ( $self, $pageList ) = @_;
	my $pages;
	while ( @{$pageList} ) {
		my $lastPage = SLICE_SIZE;
		if ($#{$pageList} < $lastPage ) {
			$lastPage = $#{$pageList};
		}
		my @slice = @{$pageList}[0..$lastPage];
		$pages = $self->getFirstPages( \@slice );
		$pageList = @{$pageList}[(SLICE_SIZE + 1)..$#{$pageList}];
	}
	return $pages;
}

sub getTrackedCategories {
	my ( $self ) = @_;
	my $pages;

	foreach my $category ( $self->{trackedCategories} ) {
		if (
			length( $category ) < 10
			  || substr( $category, 0,  9 ) != "Category:"
		) {
			# Mediawiki requires the Category
			# prefix, but let's not force the user
			# to specify it.
			$category = "Category:${category}";
		}
		my $pagesList = $self->{wiki}->list( {
			action => 'query', list => 'categorymembers',
			cmtitle => $category, cmlimit => 'max'
		  } ) || die $self->{wiki}->{error}->{code} . ': '
		  . $self->{wiki}->{error}->{details} . "\n";
		foreach my $page (@{$pagesList}) {
			$pages->{$page->{title}} = $page;
		}
	}
	return $pages;
}

sub fatal {
	my ($self, $action) = @_;

	warn "fatal: could not $action\n";
	warn "fatal: $self->{url} does not appear to be a mediawiki\n";
	if ( $self->{wiki}->{error} ) {
		warn "fatal: (error $self->{wiki}->{error}->{code} "
		  . "$self->{wiki}->{error}->{details})\n";
	}
	exit 1;
}

sub getPageChunk {
	my ($self, $ns, $from) = @_;

	if ($ns && $from) {
		# Since $ns might not match (e.g. "Project" != "Wikipedia")
		$from =~ s/^[^:]*:(.*)/$1/;
	}
	if (!defined $from) {
		$from = "";
	}
	$self->debug( "starting on $from\n", 4 ) if $from;
	my $ret = $self->{wiki}->list({
		action => 'query',
		apfrom => $from || "",
		list => 'allpages',
		apnamespace => $self->{allNamespaces}->{$ns}->{id},
		aplimit => 'max',
	});
	if (ref $ret eq "ARRAY") {
		return @{$ret}
	}
	return ();
}



sub getPagesInNamespace {
	my ($self, $ns) = @_;
	my ($current, $done, @pages);
	@pages = $self->getPageChunk($ns);

	return sub {
		# code to calculate $next_page or $done;
		if (scalar @pages == 0) {
			if (exists $current->{title}) {
				@pages =
				  $self->getPageChunk($ns, $current->{title});
			}
			if (scalar @pages > 0 && $pages[0]->{title} eq $current->{title}) {
				shift @pages;
			}
			if (scalar @pages == 0) {
				return;
			}
		}
		$current = shift @pages;
		$self->debug( "Got from the wiki: $current->{title}...\n", 8 );
		return $current;
	};
}

sub getAllPages {
	my ($self) = @_;
	my $pages = {};

	# No user-provided list, get the list of pages from the API.
	my $batch = BATCH_SIZE;
	my %seen;
	my @theseNS =
	  sort{ $self->{allNamespaces}->{$a}->{id} <=> $self->{allNamespaces}->{$b}->{id} }
	  grep{
		  defined $self->{allNamespaces}->{$_}->{id}
			&& !$seen{$self->{allNamespaces}->{$_}->{id}}++
		} keys %{$self->{allNamespaces}};

	foreach my $ns ( @theseNS ) {
		$self->debug( "Processing $ns\n" );
		my $pageIter = $self->getPagesInNamespace( $ns );
		if (!defined($pageIter)) {
			$self->fatal("get the list of wiki pages");
		}
		while (my $page = $pageIter->()) {
			$pages->{$page->{title}} = $page;
		}
	}
	return $pages;
}

sub addNSMap {
	my ($self, $name, $id) = @_;

	$name =~ s/ /_/g;
	$self->{allNamespaces}->{$name} = $id;
	Git::command_oneline( [
		"config", "--add", "remote.$self->{remotename}.namespaceCache", "$name:$id"
	  ] );
}

sub getNamespaces {
	my ($self) = @_;
	if ( scalar keys %{$self->{allNamespaces}} != 0) {
		return $self->{allNamespaces};
	}
	$self->{allNamespaces} = {};
	$self->connectMaybe();

	my $resp = $self->{wiki}->api({
		action => 'query',
		meta => 'siteinfo',
		siprop => 'namespaces'
	  });
	if (!defined $resp) {
		$self->fatal("get namespaces");
	}
	my %ns = %{$resp->{query}->{namespaces}};
	foreach my $ns (keys %ns) {
		if ($ns < 0 ) {
			delete $ns{$ns};
			next;
		}
		my $name = $ns{$ns}{'*'};
		my $canon = $ns{$ns}{'canonical'}
		  ? $ns{$ns}{'canonical'} : $name;
		$self->debug( "Got $name/$canon namespace.\n", 2 );
		$ns{$name} = $ns{$ns};
		$self->addNSMap( $name, $ns{$ns}{id} );
		if ($name ne $canon) {
			$ns{$canon} = $ns{$ns};
			$self->addNSMap( $canon, $ns{$ns}{id} );
		}
		delete $ns{$ns};
	}
	$self->{allNamespaces} = \%ns;
	return $self->{allNamespaces};
}


sub getAllNamespaces {
	my ($self) = @_;

	my $allNamespaces = {};
	map {
		my ($k, $v) = split(":", $_, 2);
		$allNamespaces->{$k} = $v;
	} $self->getGitRemoteList("namespaceCache");
	if (scalar keys %{$allNamespaces} == 0) {
		return $self->getNamespaces();
	}
	return $allNamespaces;
}

# Get the list of pages to be fetched according to configuration.
sub getPages {
	my ($self) = @_;
	my $userDefined;
	my $pages;

	$self->connectMaybe();
	if ( $self->{trackedPages} ) {
		$self->debug( "Listing tracked pages on remote wiki...\n" );
		$userDefined = 1;

		# The user provided a list of pages titles, but we
		# still need to query the API to get the page IDs.
		$pages = $self->getPageList( $self->{trackedPages} );
	}
	if ( $self->{trackedCategories} ) {
		$self->debug(
			"Listing tracked categories on remote wiki...\n", 1
		  );
		$userDefined = 1;
		$pages = $self->getTrackedCategories();
	}

	if ( $self->{useNamespace} ) {
		my $iter = $self->getPagesInNamespace( $self->{useNamespace} );
		$userDefined = 1;
		while (my $page = $iter->()) {
			$pages->{$page->{title}} = $page;
		}
	}
	if ( !$userDefined ) {
		$self->debug( "Listing all pages on remote wiki...\n" );
		$pages = $self->getAllPages();
	}
	if ( $self->{importMedia} ) {
		$self->debug(
			"Getting media files for selected pages...\n", 1
		  );
		if ($userDefined) {
			$self->getLinkedMediafiles( $pages );
		} else {
			$self->getAllMediafiles( $pages );
		}
	}

    my $found = scalar keys %{$pages};
    if ($found == 1) {
		$self->debug( "1 page found.\n" );
    }
    if ($found > 1) {
		$self->debug( "$found pages found.\n" );
    }
    if (!$found) {
		warn "No pages found.\n";
    }
	return $pages;
}

sub handleImport {
	my ($self, $line) = @_;
	my @import = split( / /, $line );
	shift @import;

	$self->debug( "Handling Import\n", 4 );
	# multiple import commands can follow each other.
	my @refs = $self->uniq( $self->getMoreRefs( 'import' ) );
	$self->debug( "Got refs: " . join( ", ", @refs ) . "\n", 2 );
	if ( !@refs ) {
		@refs = [ NULL_SHA1 ];
	}
	foreach my $ref (@refs) {
		$self->importRef( $ref );
	}
	$self->tellGit( "done\n" );
	return;

	if ( @import > 1 ) {
		$self->raiseError( "Too many imports requested: $line" );
	}
	$self->debug( "Import: $line\n", 2 );
}

sub handleExport {
	my $self = shift;

	$self->debug( "Export:\n", 2 );
}

sub handleOption {
	my $self = shift;
	my $line = shift;

	$self->debug( "Option: $line\n", 2 );
}

sub handleExit {
	my $self = shift;
	my $line = shift;

	$self->debug( "Exit: $line\n", 2 );
}

sub handleBadInput {
	my $self = shift;
	my $line = shift;

	$self->raiseError( "BadInput: <$line>\n", 2 );
}

sub connectMaybe {
	my ( $self ) = @_;

	# if connected, return
	if ( $self->{wiki} ) {
		return;
	}

	$self->{credential}->{url} = $self->{url};
	$self->{credential}->{username} = Git::config( "credential.$self->{url}.username" )
	  || Git::prompt( "Username for $self->{url}: " );
	$self->{credential}->{password} = Git::config( "credential.$self->{url}.password" )
	  || Git::prompt( "Password for $self->{url}: " );
	my $domain = Git::config( "credential.$self->{url}.domain" );
	$self->{credential}->{domain} = defined( $domain ) ? $domain
	  : Git::prompt( "Domain (if any) for $self->{url}: " );

	$self->{wikiName} = "FIXME-WITH-A-WIKI-NAME";

	$self->{wiki} = MediaWiki::API->new;
	$self->{wiki}->{config}->{api_url} = $self->{url} . "/api.php";
	Git::credential($self->{credential});
	if ( $self->{credential}->{username} ) {
		my $request = {
			lgname => $self->{credential}->{username},
			lgpassword => $self->{credential}->{password},
			lgdomain => $self->{wikiDomain}
		  };
		if ( $self->{wiki}->login($request) ) {
			Git::credential($self->{credential}, 'approve');
			$self->debug( qq(Logged in mediawiki user "$self->{credential}->{username}".\n) );
		} else {
			$self->debug( qq(Failed to log in mediawiki user "$self->{credential}->{username}" )
							. qq(on $self->{url}\n\nerror: ) . $self->{wiki}->{error}->{code} . ': '
							. $self->{wiki}->{error}->{details} . ")\n" );
			Git::credential($self->{credential}, 'reject');
			exit 1;
		}
	} else {
		warn "Using the mediawiki API for $self->{url} anonymously!\n\nSet git-credentials to avoid this message.\n";
	}

	$self->{pageExt} = Git::config( "remote.$self->{remotename}.pageExtension" ) || ".mediawiki";
	$self->{trackedPages} = $self->getGitRemoteList( "page" );
	$self->{trackedCategories} = $self->getGitRemoteList( "category" );
	$self->{allNamespaces} = $self->getAllNamespaces();
	$self->{useNamespace}
	  = Git::config( "remote.$self->{remotename}.onlyNS" );
	my $mediaFlag =
	  lc( Git::config( "remote.$self->{remotename}.media" ) || "" );
	$self->{importMedia} =
	  $mediaFlag eq 'import' || $mediaFlag eq 'both';
	$self->{exportMedia} =
	  $mediaFlag eq 'export' || $mediaFlag eq 'both';
}

1
