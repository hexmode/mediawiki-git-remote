package Git::MediaWiki::Constants;

use strict;

our (@EXPORT);
@EXPORT = qw(EMPTY);

# Mediawiki filenames can contain forward slashes. This variable
# decides by which pattern they should be replaced
use constant SLASH_REPLACEMENT => '%2F';

# Used to test for empty strings
use constant EMPTY => q{};

# HTTP codes
use constant HTTP_CODE_OK => 200;
use constant HTTP_CODE_PAGE_NOT_FOUND => 404;

# It's not always possible to delete pages (may require some
# privileges). Deleted pages are replaced with this content.
use constant DELETED_CONTENT => "[[Category:Deleted]]\n";

# It's not possible to create empty pages. New empty files in Git are
# sent with this content instead.
use constant EMPTY_CONTENT => "<!-- empty page -->\n";

# used to reflect file creation or deletion in diff.
use constant NULL_SHA1 => '0000000000000000000000000000000000000000';

# Used on Git's side to reflect empty edit messages on the wiki
use constant EMPTY_MESSAGE => '*Empty MediaWiki Message*';

# Number of pages taken into account at once in submodule get_page_list
use constant SLICE_SIZE => 50;

# Number of linked mediafile to get at once in get_linked_mediafiles
# The query is split in small batches because of the MW API limit of
# the number of links to be returned (500 links max).
use constant BATCH_SIZE => 10;

1

