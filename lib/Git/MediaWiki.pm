package Git::MediaWiki;

use strict;

use URI::URL;
use URI::Escape;

use constant NAME => "mediawiki";

sub new {
  my $class = shift;
  my @arg = @_;
  my $self = bless({}, $class);

  $self->{alias} = $arg[0];
  if ( $arg[0] eq "mediawiki::" . $arg[1] ) {
    $self->{alias} = '_';
  }
  $self->{url} = $arg[1];
  $self->{dir} = $ENV{GIT_DIR} . '/' . NAME . '/' . $self->{alias};
  $self->{prefix} = 'refs/' . NAME . '/' . $self->{alias};
  $| = 1;

  return $self;
}

sub setDebug {
  my $self = shift;

  $self->{DEBUG} = shift;
}

sub debug {
  my ($self, $line, $level) = @_;

  warn $line if $self->{DEBUG} && $level;
}

sub raiseError {
  my ($self, $error) = @_;

  die $error;
}

sub readLine {
  my $self = shift;

  my $line = <STDIN>;
  chomp( $line );
  $self->debug( "Got: <$line>\n", 1 );
  return $line;
}

sub tellGit {
  my $self = shift;
  my $line = shift;

  $self->debug( "Sending: <$line>\n", 1 );
  print "$line\n";
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
  $self->tellGit( "refspec refs/heads/*:" . $self->{prefix} . "/*" );
  $self->tellGit( "import" );
  $self->tellGit( "list" );
  $self->tellGit( "push" );
  $self->tellGit( "" );
}

sub handleList {
  my $self = shift;

  $self->debug( "List: (MW remotes only have one branch)\n", 2 );
  $self->tellGit( '? refs/heads/master' );
  $self->tellGit( '@refs/heads/master HEAD' );
  $self->tellGit( '' );
}

sub handleImport {
  my $self = shift;
  my $line = shift;
  my @import = split( / /, $line );
  shift @import;

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

1
