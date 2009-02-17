#
# Copyright (C) 2004-2006 by Socialtext, Inc.
#
package Socialtext::Attachments;
use strict;
use warnings;

use base 'Socialtext::Base';

use Carp ();
use Class::Field qw( field );
use File::Copy ();
use File::Path ();
use Socialtext::ArchiveExtractor;
use Socialtext::ChangeEvent;
use Socialtext::Encode;
use Socialtext::File;
use Socialtext::Indexes;
use Socialtext::Page;
use Readonly;
use Socialtext::Validate qw( validate SCALAR_TYPE BOOLEAN_TYPE HANDLE_TYPE USER_TYPE );

sub class_id { 'attachments' }
field 'attachment_set';
field 'attachment_set_page_id';

sub all {
    my $self = shift;
    my %p = @_;
    my $page_id  = $p{page_id} || $self->hub->pages->current->id;
    my $no_index = $p{no_index};

    my $attachment_set = $self->attachment_set;

    return $attachment_set
      if defined $attachment_set and defined $self->attachment_set_page_id
        and $self->attachment_set_page_id eq $page_id;

    $self->attachment_set_page_id($page_id);
    $attachment_set = [];

    for my $entry ( @{ $self->_all_for_page($page_id, $no_index) } ) {
        my $attachment = $self->new_attachment(
            id      => $entry->{id},
            page_id => $page_id,
        )->load;
        next if $attachment->deleted;
        push @$attachment_set, $attachment;
    }

    $self->attachment_set($attachment_set);
}

sub index {
    my $self = shift;
    $self->{index}
        ||= Socialtext::Indexes->new_for_class( $self->hub, $self->class_id );
}

sub new_attachment {
    my $self = shift;
    $self->attachment_set(undef);
    $self->attachment_set_page_id(undef);
    Socialtext::Attachment->new(hub => $self->hub, @_);
}

sub from_file_handle {
    my $self = shift;
    my %args = @_;
    return delete $args{unpack}
      ? $self->unpack_archive(%args)
      : $self->create(%args);
}

{
    Readonly my $spec => {
        filename     => SCALAR_TYPE,
        fh           => HANDLE_TYPE,
        page_id      => SCALAR_TYPE( default => undef ),
        creator      => USER_TYPE,
        embed        => BOOLEAN_TYPE( default => 0 ),
        Content_type => SCALAR_TYPE( default => undef ),
        unpack   => BOOLEAN_TYPE( default => 0 ),
    };
    sub create {
        my $self = shift;
        my %args = validate( @_, $spec );

        $args{page_id} ||= $self->hub->pages->current->id;

        my $attachment = $self->new_attachment(%args);
        $attachment->save($args{fh});
        $attachment->store( user => $args{creator} );
        $attachment->inline( $args{page_id}, $args{creator} )
            if $args{embed};
        return $attachment;
    }
}

sub unpack_archive {
    my $self = shift;
    my %args = @_;

    my $tmpdir = File::Temp::tempdir( CLEANUP => 1 );

    $args{page_id} ||= $self->hub->pages->current->id;

    # Socialtext::ArchiveExtractor uses the extension to figure out how to unpack the
    # archive, so that must be preserved here.
    my $filename = File::Basename::basename( $args{filename} );
    my $tmparchive = "$tmpdir/$filename";

    open my $tmpfh, '>', $tmparchive
        or die "Couldn't open $tmparchive for writing: $!";
    File::Copy::copy($args{fh}, $tmpfh)
        or die "Cannot save $filename to $tmparchive: $!";
    close $tmpfh;

    my @files = Socialtext::ArchiveExtractor->extract( archive => $tmparchive );
    # If Socialtext::ArchiveExtractor couldn't extract anything we'll
    # attach the archive file itself.
    @files = $tmparchive unless @files;

    my @attachments;
    for my $file (@files) {
        open my $fh, '<', $file or die "Cannot read $file: $!";

        # REVIEW This looks weird: It seems like the list of attachments
        # is only the last one.
        @attachments = $self->create(
            filename => $file,
            fh       => $fh,
            embed    => $args{embed},
            creator  => $args{creator},
            page_id  => $args{page_id},
        );
    }

    return @attachments;
}

sub index_generate {
    my $self = shift;
    my $hash = {};
    for my $page_id ( $self->hub->pages->all_ids ) {
        for my $attachment (
            @{ $self->all( page_id => $page_id, no_index => 1 ) } ) {
            next unless $attachment->id;
            $hash->{$page_id}{ $attachment->id } = $attachment->serialize;
        }
    }
    return $hash;
}

sub index_delete {
    my $self = shift;
    my ($hash, $attachment) = @_;
    my $page_id = $attachment->page_id;
    my $entry = $hash->{$page_id};
    if (keys %$entry <= 1) {
        delete $hash->{$page_id};
        return;
    }
    delete $entry->{$attachment->id};
    $hash->{$page_id} = $entry;
    return;
}

sub index_add {
    my $self = shift;
    my ($hash, $attachment) = @_;
    my $page_id = $attachment->page_id;
    my $entry = $hash->{$page_id} || {};
    $entry->{$attachment->id} = $attachment->serialize;
    $hash->{$page_id} = $entry;
    return;
}

sub all_serialized {
    my $self = shift;
    my $page_id = shift;

    my @all_serialized;
    for my $attachment (@{$self->all(page_id => $page_id)}) {
        push @all_serialized, $attachment->serialize;
    }
    return \@all_serialized;
}

sub all_in_workspace {
    my $self = shift;
    my @attachments;
    my $hash = $self->index->read_only_hash;
    for my $page_id (keys %$hash) {
        next unless Socialtext::Page->new( hub => $self->hub, id => $page_id )->active;
        my $entry = $hash->{$page_id};
        $self->_add_attachment_from_index(\@attachments, $entry);
    }
    return \@attachments;
}

sub all_attachments_in_workspace {
    my $self = shift;
    return map {
        $self->new_attachment( id => $_->{id}, page_id => $_->{page_id}, )
            ->load
    } @{ $self->all_in_workspace() };
}

sub _all_for_page {
    my $self = shift;
    my $page_id  = shift;
    my $no_index = shift;
    my @attachments;

    if ($no_index) {
        my $directory = $self->plugin_directory . '/' . $page_id;

        Socialtext::File::ensure_directory($directory);

        for my $id ( Socialtext::File::all_directory_files($directory) ) {
            next unless $id =~ s/(.*)\.txt$/$1/;
            push @attachments, {id => $id};
        }
    }
    else {
        my $entry = $self->index->read($page_id);
        $self->_add_attachment_from_index( \@attachments, $entry );
    }
    return [ sort {$a->{id} cmp $b->{id}} @attachments ];
}

sub _add_attachment_from_index {
    my $self = shift;
    my $attachments_ref = shift;
    my $entry = shift;
    push @$attachments_ref, grep {
        -e $self->plugin_directory . '/' . $_->{page_id} . '/' . $_->{id};
    } values %$entry;
}

#------------------------------------------------------------------------------#
package Socialtext::Attachment;

use base 'Socialtext::Base';

use Class::Field qw( field );
use Email::Valid;
use MIME::Types;
use Socialtext::Encode;
use Socialtext::File::Stringify;

sub class_id { 'attachment' }
field 'id';
field 'page_id';
field 'filename';
field 'db_filename';
field 'loaded';
field 'Control' => '';
field 'From';
field 'Subject';
field 'DB_Filename';
field 'Date';
field 'Received';
field 'Content_MD5';
field 'Content_Length';
field 'Content_type';

sub new {
    my $self = shift;
    $self = $self->SUPER::new(@_);
    $self->id($self->new_id)
      unless $self->id;
    $self->page_id($self->hub->pages->current->id)
      unless $self->page_id;
    if (my $filename = $self->filename) {
        $filename = Socialtext::Encode::ensure_is_utf8(
            $self->filename
        );
        $filename =~ s#^.*/##;
        $filename =~ s#^.*\\##;
        # why would we do  ... => ~~.  ?
        $filename =~ s/(\.+)\./'~' x length($1) . '.'/ge;
        $self->filename($filename);
        $self->db_filename($self->uri_escape($filename));
    }
    return $self;
}

my $x = 0;
sub new_id {
    my $self = shift;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time);
    $year += 1900;
    my $id = sprintf('%4d%02d%02d%02d%02d%02d-%d-%d', 
        $year, $mon+1, $mday, $hour, $min, $sec, $x++, $$
    );
    return $id;
}

sub load {
    my $self = shift;
    return $self if $self->loaded;

    my $path = $self->_content_file;

    for ( Socialtext::File::get_contents_utf8($path) ) {
        next unless /^(\w\S*):\s*(.*)$/;
        my $value = $2;
        ( my $key = $1 ) =~ s/-/_/g;
        next unless $self->can($key);
        $self->$key($value);
    }

    $self->filename( $self->Subject );
    $self->db_filename( $self->DB_Filename
            || $self->uri_escape( $self->Subject ) );

    $self->loaded(1);
    return $self;
}

sub _content_file {
    my $self = shift;

    return Socialtext::File::catfile(
        $self->hub->attachments->plugin_directory,
        $self->page_id,
        $self->id . '.txt',
    );
}

sub save {
    my $self = shift;
    my $tmp_file = shift;
    my $id = $self->id;
    my $db_filename = $self->db_filename;
    my $page_id = $self->page_id;

    my $attachdir = $self->hub->attachments->plugin_directory;
    my $file_path = "$attachdir/$page_id/$id";
    $self->assert_dirpath($file_path);
    my $dest = "$file_path/$db_filename";
    File::Copy::copy($tmp_file, $dest)
        or die "Couldn't copy from $tmp_file to $dest : $!";
    chmod(0755, $dest)
        or die "Couldn't set permissions on $dest : $!";
}

# XXX - this should be used elsewhere in this package
sub full_path {
    my $self = shift;
    return $self->{full_path} if defined $self->{full_path};

    my $attachdir = $self->hub->attachments->plugin_directory;
    my $page_id = $self->page_id;
    my $id = $self->id;
    my $db_filename = $self->db_filename;

    $self->{full_path} = "$attachdir/$page_id/$id/$db_filename";

    return $self->{full_path};
}

sub copy {
    my $self = shift;
    my $source = shift;
    my $target = shift;
    my $target_directory = shift;

    my $sourcefile = $source->db_filename;
    my $sourcedir = $source->hub->attachments->plugin_directory;
    my $source_page_id = $source->page_id;
    my $source_id = $source->id;
    my $sourcepath = "$sourcedir/$source_page_id/$source_id";
    $self->assert_dirpath($sourcepath);

    my $targetfile = $target->db_filename;

    my $target_page_id = $target->page_id; my $target_id = $target->id;
    my $targetpath = "$target_directory/$target_page_id/$target_id";

    $self->assert_dirpath($targetpath);

    File::Copy::copy("$sourcepath/$sourcefile", "$targetpath")
        or die "Can't copy $sourcepath/$sourcefile into $targetpath: $!";

    chmod(0755, $targetpath);
}

sub store {
    my $self = shift;
    my %p = @_;

    Carp::confess('no user given to Socialtext::Attachment->store')
        unless $p{user} && eval { $p{user}->can('email_address') };

    my $target_dir = $p{dir};
    my $id = $self->id;
    my $filename = $self->filename;
    my $db_filename = $self->db_filename;
    my $page_id = $self->page_id;

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time);
    $year += 1900;
    my $prt_date = sprintf("%4d-%02d-%02d %02d:%02d:%02d GMT",
                        $year, $mon+1, $mday, $hour, $min, $sec
                       );
    my $attachdir = $target_dir || $self->hub->attachments->plugin_directory;
    my $file_path = "$attachdir/$page_id/$id";
    $self->assert_dirpath($file_path);

    my $md5;
    open IN, '<', "$file_path/$db_filename"
      or die "Can't open $file_path/$db_filename for MD5 checksum: $!";
    binmode IN;
    $md5 = Digest::MD5->new->addfile(*IN)->b64digest;
    close IN;

    #need test for command line invocation
    my $remote_addr='';
    if  ($ENV{REMOTE_ADDR}) {
        $remote_addr = $ENV{REMOTE_ADDR};
    }

    my $from = $p{user}->email_address;

    my $filesize = -s "$file_path/$db_filename";
    open my $out, '>', "$file_path.txt"
        or die "Can't open output file: $!";
    binmode($out, ':utf8');
    print $out "Control: Deleted\n" if $self->deleted;
    print $out "Content-type: ", $self->Content_type, "\n"
        if $self->Content_type;
    print $out $self->utf8_decode(<<"QUOTEDTEXT");
From: $from
Subject: $filename
DB_Filename: $db_filename
Date: $prt_date
Received: from $remote_addr
Content-MD5: $md5==
Content-Length: $filesize

QUOTEDTEXT
    close $out;

    # XXX: refactor into MetaDataObject with all metadata,
    # XXX: including Subject, Received, Control
    $self->filename($filename);
    $self->db_filename($db_filename);
    $self->Date($prt_date);
    $self->Content_Length($filesize);
    $self->Content_MD5("$md5==");
    $self->From($from);

    $self->hub->attachments->index->add($self) unless $self->deleted;
    Socialtext::ChangeEvent->Record($self);
}

sub page {
    my $self = shift;
    $self->hub->pages->new_page($self->page_id);
}

# XXX - a copy of Socialtext::Page->last_edited_by()
sub uploaded_by {
    my $self = shift;
    return unless $self->metadata->From;

    my $email_address = $self->metadata->From;
    # We have some very bogus data on our system, so this is a really
    # horrible hack to fix it.
    unless ( Email::Valid->address($email_address) ) {
        my ($name) = $email_address =~ /([\w-]+)/;
        $email_address = $name . '@example.com';
    }

    my $user = Socialtext::User->new( email_address => $email_address );

    # XXX - there are many usernames for pages that were never in
    # users.db or any htpasswd.db file. We need to have all users in
    # the DBMS, so we assume that if they don't exist, they should be
    # created. When we import pages into the DBMS, we'll need to
    # create any non-existent users at the same time, for referential
    # integrity.
    $user ||= Socialtext::User->create(
        username      => $email_address,
        email_address => $email_address,
    );

    return $user;
}

sub short_name {
    my $self = shift;
    my $name = $self->Subject;
    $name =~ s/ /_/g;
    return $name
      unless $name =~ /^(.{16}).{2,}(\..*)/;
    return "$1..$2";
}

sub content {
    my $self = shift;
    Socialtext::File::get_contents($self->full_path);
}

sub deleted {
    my $self = shift;
    return $self->{deleted} = shift if @_;
    return $self->{deleted} if defined $self->{deleted};
    $self->load;
    $self->{deleted} = $self->Control eq 'Deleted' ? 1 : 0;
}

sub delete {
    my $self = shift;
    my %p = @_;
    Carp::confess('no user given to Socialtext::Attachment->delete')
        unless $p{user};

    $self->load;
    $self->deleted(1);
    $self->store(%p);
    $self->hub->attachments->index->delete($self);
}

sub exists {
    return -f $_[0]->_content_file;
}

sub serialize {
    my $self = shift;
    return {
        filename => $self->filename,
        date     => $self->Date,
        length   => $self->Content_Length,
        md5      => $self->Content_MD5,
        from     => $self->From,
        page_id  => $self->page_id,
        id       => $self->id,
    };
}

sub inline {
    my $self = shift;
    my $page_id = shift;
    my $user = shift;

    my $page = $self->hub->pages->new_page($page_id);
    $page->metadata->update( user => $user );

    my $content = $page->content;
    $content = $self->image_or_file_wafl . $content;
    $page->content($content);
    $page->store( user => $user );
}

sub mime_type {
    my $self = shift;

    my $type = $self->Content_type;

    if ($type) {
        return $type;
    }
    my $type_object = MIME::Types->new->mimeTypeOf( $self->filename );
    return $type_object ? $type_object->type : 'application/binary';
}

sub should_popup {
    my $self = shift;
    my @easy_going_types = (
        qr|^text/|, # especially text/html
        qr|^image/|,
        qr|^video/|,
        # ...any others?   ...any exceptions?
    );
    return not grep { $self->mime_type =~ $_ } @easy_going_types;
}

#XXX use MIME::Types?
sub image_or_file_wafl {
    my $self = shift;
    my $filename = $self->utf8_decode($self->filename);
    $filename =~ /\.(gif|jpg|jpeg|png)$/i
      ? "{image: $filename}" . "\n\n"
      : "{file: $filename}" . "\n\n";
}

sub assert_dirpath {
    my $self = shift;
    my $path = shift;

    File::Path::mkpath($path)
        unless -d $path;
}

sub to_string {
    my $self = shift;
    return Socialtext::File::Stringify->to_string( $self->full_path,
        $self->mime_type );
}

1;
