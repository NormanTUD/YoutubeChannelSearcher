#!/usr/bin/perl

use strict;
use warnings;
use Term::ANSIColor;
use File::Path qw(make_path);
use Data::Dumper;
use autodie;
use Digest::MD5 qw/md5_hex/;
use Smart::Comments;
use JSON::Parse 'parse_json';
use File::Path;
use UI::Dialog;

my %options = (
	debug => 0,
	parameter => undef,
	path => undef,
	name => undef,
	lang => 'de',
	random => 0,
	comments => 1,
	rename => 0,
	repair => 0,
	commentlimit => 0,
	titleregex => '',
	update_existing => undef,
	only_download_comments_for_existing_videos => 0,
	parameter_is_playlist => 0,
	reparse_comments => 0
);

analyze_args(@ARGV);

sub message (@) {
	foreach (@_) {
		warn color("green").$_.color("reset")."\n";
	}
}

sub mywarn (@) {
	foreach (@_) {
		warn color("yellow").$_.color("reset")."\n";
	}
}

sub debug_level (@) {
	my $level = shift @_;
	return if !($options{debug} >= $level);
	foreach (@_) {
		warn color("white on_blue").$_.color("reset")."\n";
	}
}

sub debug (@) {
	return if !$options{debug};
	foreach (@_) {
		warn color("white on_blue").$_.color("reset")."\n";
	}
}

main();

sub main {
	debug "main()";

	my $d = new UI::Dialog( title => 'Name of the Search', backtitle => 'Name of the search',
		width => 65, height => 20, listheight => 5,
		order => [ 'whiptail', 'dialog' ] );

	if($options{only_download_comments_for_existing_videos}) {
		if($options{path}) {
			my @ids = map { s#.*/##; s#\.txt$##; $_ } <$options{path}/results/*.txt>;
			my $comments = "$options{path}/comments";
			warn "Got ".scalar(@ids)." IDs to try\n";
			foreach my $id (sort { rand() <=> rand() } @ids) { ### Working===[%]     done
				mywarn "\n"; # for smart comments
				my $first_comment_file = "$comments/".$id."_0.json";
				if(!-e $first_comment_file || !$options{reparse_comments}) {
					my $comments_file = "$comments/".$id.".json";
					unlink $comments_file if -e $comments_file;
					download_comments($comments_file, $id);
					get_timestamp_comments($comments, $id, $comments_file);
				}
			}
		} else {
			warn "--path must be specified for --only_download_comments_for_existing_videos\n";
		}
		exit 0;
	}

	if($options{update_existing}) {
		while (my $filename = <$options{update_existing}/*/index.php>) { # /
			$filename =~ s#/{2,}#/#g;
			my $foldername = ($filename =~ s#index\.php$##r);
			if(-d "$foldername/desc" && -d "$foldername/results") {
				$options{path} = $foldername;

				debug "found $foldername";

				my $old_index = read_file($filename);
				if($old_index =~ m#<title>(.*?)-Suche</title>#) {
					$options{name} = $1;
				}

				debug "Extracted name $options{name}";

				create_index_file();
			}
		}
		exit 0;
	}

	if(!defined $options{path}) {
		$options{path} = $d->inputbox(
			text => 'Enter the Path...',
			entry => $ENV{YoutubeChannelSearcherDir} ? $ENV{YoutubeChannelSearcherDir} : ''
		);
	}

	if(!defined $options{name} && !$options{rename} && -e "$options{path}/index.php") {
		my $index_file = "$options{path}/index.php";
		my $old_index = read_file($index_file);
		if($old_index =~ m#<title>(.*?)-Suche</title>#) {
			$options{name} = $1;
		}
	}

	if(!defined $options{name}) {
		$options{name} = $d->inputbox(
			text => 'Enter the Name...',
			entry => ''
		);
	}

	if(!defined $options{parameter}) {
		if(!$options{repair}) {
			$options{parameter} = $d->inputbox(
				text => 'Enter the URL...',
				entry => ''
			);
		}
	}


	if(!defined $options{lang}) {
		$options{lang} = $d->inputbox(
			text => 'Enter two letter language code (de, en, ...)...',
			entry => ''
		);
	}

	my @run_strings = ();
	for my $key (qw/lang parameter titleregex path name repair random debug/) {
		if($options{$key}) {
			push @run_strings, qq#--$key="$options{$key}"#;
		}
	}

	message "perl create.pl ".join(' ', @run_strings);;
	
	if($options{path}) {
		make_path($options{path});
		create_index_file();
	}

	if($options{parameter}) {
		download_data();
	} elsif ($options{reparse_comments}) {
		my @ids = map { s#.*/##; s#\.txt$##; $_ } <$options{path}/results/*.txt>;
		my $comments = "$options{path}/comments";
		foreach my $id (@ids) {
			my $comments_file = "$comments/".$id.".json";
			my $n = 0;
			while (-e "$comments/".$id."_".$n.".json") {
				unlink "$comments/".$id."_".$n.".json";
				$n++;
			}
			get_timestamp_comments($comments, $id, $comments_file);
		}
	} elsif ($options{repair}) {
		repair_data();
	} else {
		mywarn "No --parameter or --repair option given, not downloading any videos";
	}

	my $dl = "$options{path}/dl";
	if(-e $dl) {
		debug "Deleting $dl";
		rmtree($dl);
	}

	message "perl create.pl ".join(' ', @run_strings);;
}

sub get_defect_files {
	debug "get_defect_files()";
	my @defect = ();
	my $results = "$options{path}/results/";
	if(-d $results) {
		while (my $file = <$results/*.txt>) {
			my $contents = read_file($file);
			if ($contents =~ m#\d{2}:\d{2}:\d{2}\.\d{3}\s+-->\s+\d{2}:\d{2}:\d{2}\.\d{3}#) {
				my $id = $file;
				$id =~ s#\.txt##g;
				$id =~ s#.*/##g;
				push @defect, $id;
				unlink $file;
				debug "Content seems faulty";
			} else {
				debug "Content seems ok";
			}
		}
	} else {
		mywarn "$results not found";
	}
	return @defect;
}

sub get_timestamp_comments {
	my ($comments, $id, $comments_file) = @_; 
	debug "get_timestamp_comments($comments, $id, $comments_file)";
	my $comments_file_parsed  = "$comments/".$id."_0.json";
	if((!-e $comments_file_parsed || $options{reparse_comments}) && -e $comments_file) {
		my @possible_timestamps = ();
		my @lines = split(/[\n\r]/, read_file($comments_file));
		foreach my $line (@lines) {
			eval {
				my $data_struct = parse_json($line);
				if(exists $data_struct->{text}) {
					my $text = $data_struct->{text};

					if($text =~ m#(.*(\R\s*(?:\d{1,2}:)?\d{1,2}:\d{2}\b.*[a-z]{3,}.*){1,})#gim) {
						my $this_text = $text;
						my $votes = $data_struct->{votes};
						my $number_of_timestamps = 0;
						while ($this_text =~ m#\R\s*(\b(?:\d{1,2}:)?\d{1,2}:\d{2}\b)#gism) {
							$number_of_timestamps++;
						}
						if($number_of_timestamps >= 2) {
							push @possible_timestamps, { text => $this_text, votes => $votes, number_of_timestamps => $number_of_timestamps };
						}
					}
				}
			}; 

			if($@) {
				die $@;
			}
		}

		if(@possible_timestamps) {
			my @rated_timestamps = sort {
				$a->{number_of_timestamps} <=> $b->{number_of_timestamps} || 
				$a->{votes} <=> $b->{votes} ||
				length($b->{text}) <=> length($a->{text})
			} @possible_timestamps;
			for my $index (0 .. $#rated_timestamps) {
				$comments_file_parsed  = "$comments/".$id."_$index.json";
				mywarn "Printing comment to $comments_file_parsed\n";
				open my $fh, '>>', $comments_file_parsed;
				print $fh $possible_timestamps[$index]->{text};
				close $fh;
			}
		}
	}
}

sub download_comments {
	my ($comments_file, $id) = @_;
	debug "download_comments($comments_file, $id)";
	if(-e $comments_file) {
		mywarn "$comments_file already exists";
	} elsif ($options{comments}) {
		my $parameter = qq# --output "$comments_file" --youtubeid="$id" #;
		if ($options{commentlimit}) {
			$parameter .= qq# --limit $options{commentlimit} #;
		}
		my $command = qq#cd comments; python2.7 downloader.py $parameter; cd -#;
		debug $command;
		system($command);
	} else {
		debug "Not downloading comments because of --nocomments";
	}
}

sub download_duration {
	my ($duration_file, $id) = @_;
	debug "download_duration($duration_file, $id)";
	if(-e $duration_file) {
		mywarn "$duration_file already exists";
	} else {
		my $command = qq#youtube-dl --get-duration -- "$id"#;
		debug $command;
		my $title = qx($command);
		open my $fh, '>', $duration_file;
		print $fh $title;
		close $fh;
	}
}

sub download_description {
	my ($desc_file, $id) = @_;
	debug "download_description($desc_file, $id)";
	if(-e $desc_file) {
		mywarn "$desc_file already exists";
	} else {
		my $command = qq#youtube-dl --get-description -- "$id"#;
		debug $command;
		my $title = qx($command);
		open my $fh, '>', $desc_file;
		print $fh $title;
		close $fh;
	}
}

sub download_title {
	my ($title_file, $id) = @_;
	debug "download_title($title_file, $id)";
	if(-e $title_file) {
		mywarn "$title_file already exists";
	} else {
		my $command = qq#youtube-dl --get-title -- "$id"#;
		debug $command;
		my $title = qx($command);
		open my $fh, '>', $title_file;
		print $fh $title;
		close $fh;
	}
	return read_file($title_file);
}

sub download_text {
	my ($results_id, $dl, $id) = @_;
	debug "download_text($results_id, $dl, $id)";
	if (-f $results_id) {
		mywarn "$results_id already downloaded";
	} else {
		my $downloaded_filename = transcribe($dl, $id);
		if(-e $downloaded_filename) {
			my $contents = parse_vtt($downloaded_filename);
			open my $fh, '>', $results_id or die $!;
			print $fh $contents;
			close $fh;

			my $contents_edited = read_and_parse_file($results_id, $id);
			write_file($results_id, $contents_edited);
		} else {
			mywarn "$downloaded_filename did not get downloaded correctly";
		}
	}
}

sub repair_data {
	debug "repair_data()";

	my $results = "$options{path}/results";
	my $dl = "$options{path}/dl";

	make_path($results);
	make_path($dl);

	my @ids = get_defect_files();

	foreach my $id (@ids) { ### Working===[%]     done
		mywarn "\n"; # for smart comments
		debug "Getting data for id $id";
		my $unavailable = "$options{path}/unavailable";
		my $results_id = "$results/$id.txt";

		if(file_contains($unavailable, $id)) {
			mywarn "$id is listed in `$unavailable`, skipping it";
			next;
		}

		download_text($results_id, $dl, $id);	
	}

}

sub download_data {
	debug "download_data()";

	my $start = $options{parameter};

	my $results = "$options{path}/results";
	my $dl = "$options{path}/dl";
	my $durations = "$options{path}/durations";
	my $desc = "$options{path}/desc";
	my $titles = "$options{path}/titles";
	my $comments = "$options{path}/comments";

	make_path($results);
	make_path($dl);
	make_path($durations);
	make_path($desc);
	make_path($titles);
	make_path($comments);

	my @ids = ();

	if($start) {
		if($start =~ m#list# || $options{parameter_is_playlist}) {
			push @ids, dl_playlist($start);
		} else {
			push @ids, $start;
		}
	}

	while (my $filename = <$results/*.txt>) {
		if($filename =~ m#/([a-zA-Z0-9]+)\.txt#) {
			my $id = $1;
			push @ids, $id;
		}
	}

	@ids = uniq(@ids);
	if($options{random}) {
		@ids = sort { rand() <=> rand() } @ids;
	}

	foreach my $id (@ids) { ### Working===[%]     done
		mywarn "\n"; # for smart comments
		$id =~ s#^.*/watch\?v=(.*)(?:&|$)#$1#g;
		debug "Getting data for id $id";
		my $unavailable = "$options{path}/unavailable";
		my $results_id = "$results/$id.txt";
		my $duration_file = "$durations/".$id."_TITLE.txt";
		my $desc_file = "$desc/".$id."_TITLE.txt";
		my $title_file = "$titles/".$id."_TITLE.txt";
		my $comments_file = "$comments/".$id.".json";

		if(file_contains($unavailable, $id)) {
			mywarn "$id is listed in `$unavailable`, skipping it";
			next;
		}

		my $title = download_title($title_file, $id);

		if(!$options{titleregex} || $title =~ m#$options{titleregex}#i) {
			if(!$options{titleregex}) {
				debug "--titleregex not defined";
			} else {
				debug "$title =~ --titleregex=$options{titleregex}";
			}
			download_text($results_id, $dl, $id);	
			download_description($desc_file, $id);
			download_duration($duration_file, $id);
			download_comments($comments_file, $id);
			get_timestamp_comments($comments, $id, $comments_file);
		} else {
			mywarn "$title does not match $options{titleregex}";
		}
	}
}

sub clean_text {
	my $text = shift;
	debug_level 2, "clean_text(...)";
	my $cleaned = $text;

	$cleaned =~ s/\s+(?<![\r\n])/ /gs;

	my @new = ();
	my @splitted = split /[\r\n]/, $cleaned;
	foreach my $string (@splitted) {
		$string =~ s#^\s*##g;
		push @new, $string;
	}

	$cleaned = join("\n", @new);

	return $cleaned;
}

sub read_file {
	my $filename = shift;
	debug "read_file($filename)";
	if (!-e $filename) {
		return undef;
	} else {
		my $contents = '';
		open my $fh, '<', $filename or die $!;
		while (<$fh>) {
			$contents .= $_;
		}
		close $fh;
		return $contents;
	}
}

sub file_contains {
	my $filename = shift;
	my $string = shift;
	debug "file_contains($filename, $string)";
	if(!-e $filename) {
		return 0;
	}
	open(my $FILE, '<', $filename);
	my $ret = 0;
	if (grep{/$string/} <$FILE>){
		$ret = 1;
	} else {
		$ret = 0;
	}
	close $FILE;
	return $ret;
}

sub transcribe {
	my $dl = shift;
	my $id = shift;
	debug "transcribe($dl, $id)";

	my $dlid = $id;
	my $command = qq#youtube-dl --sub-lang=$options{lang} --write-auto-sub --skip-download -o "$dl/$dlid" -- "$dlid"#;
	mysystem($command);

	my $vtt_file = "$dl/$id.$options{lang}.vtt";

	if(!-e $vtt_file) {
		open my $fh, '>>', "$options{path}/unavailable" or die $!;
		print $fh "$id\n";
		close $fh;
	}
	return $vtt_file;
}

sub dl_playlist {
	my $start = shift;
	debug "dl_playlist($start)";
	my $hash = $options{path}.'/'.md5_hex($start);
	my @list = ();

	if(-e $hash) {
		@list = map { chomp $_; $_; } qx(cat $hash);
	} else {
		my $command = qq#youtube-dl -j --flat-playlist "$start" | jq -r '.id'#;
		debug $command;
		@list = qx($command);
		@list = map { chomp $_; $_ } @list;
		open my $fh, '>>', $hash;
		foreach (@list) {
			print $fh "$_\n";
		}
		close $fh;
	}

	if(@list) {
		mywarn "got ".Dumper(@list);
	} else {
		die "Could not download playlist data, probably you need to update youtube-dl";
	}

	return @list;
}

sub parse_vtt {
	my $filename = shift;
	debug "parse_vtt($filename)";

	my $contents = '';

	my $last_minute_marker = 0;
	my $last_hour_marker = 0;

	open my $fh, '<', $filename or die $!;
	while (my $line = <$fh>) {
		$line =~ s#\R##g;
		$line = remove_comments($line);
		if(
			$line !~ m#^WEBVTT$# &&
			$line !~ m#^Kind: captions$# &&
			$line !~ m#^Language: \w+$# &&
			$line !~ /^\s*$/ && 
			$line !~ m#^\d{2}:\d{2}:\d{2}\.\d{3}\s*-->\s*\d{2}:\d{2}:\d{2}\.\d{3}\s*(?:align:start position:0%)?$# &&
			$line ne get_last_line($contents)
		) {
			$contents .= "$line\n";
		} elsif (
			# 00:00:00.020 --> 00:00:07.080
			$line =~ m#^(\d{2}):(\d{2}):\d{2}\.\d{3}\s*-->\s*\d{2}:\d{2}:\d{2}\.\d{3}\s*(?:align:start position:0%)?$#
		) {
			my ($this_hour, $this_minute) = ($1, $2);

			if($last_hour_marker != $this_hour || $last_minute_marker != $this_minute) {
				$contents .= "[$this_hour:$this_minute]\n";
			}

			($last_hour_marker, $last_minute_marker) = ($this_hour, $this_minute);
		}
	}
	close $fh;

	$contents = wrap_lines($contents);
	return $contents;
}

sub wrap_lines {
	my $contents = shift;
	debug "wrap_lines(...)";

	my @splitted = split /(\[\d+:\d+\])/, $contents;

	my @removed = ();
	foreach (@splitted) {
		s#\R# #g;
		push @removed, $_;
	}

	my $joined = join "\n", map { s#^\s+##g; s#\s+$##g; $_ } @removed;
	$joined .= "\n";

	return $joined;
}

sub remove_comments {
	my $line = shift;
	debug "remove_comments(...)";
	$line =~ s#<\d\d:\d\d:\d\d\.\d{3}><c>##g;
	$line =~ s#</c>##g;
	return $line;
}

sub get_last_line {
	my $contents = shift;
	debug "get_last_line(...)";

	my @split = split /\R/, $contents;
	return "" unless @split;

	my $last_line = $split[$#split];
	if($last_line =~ m#^\[\d+:\d+\]$#) {
		$last_line = $split[$#split - 1];
	}

	return $last_line;
}
sub mysystem ($) {
	my $command = shift;
	debug "mysystem($command)";
	system($command);
	debug "RETURN-CODE: ".($? << 8)."\n";
}

sub _help {
	my $exit_code = shift;

	print <<EOL;
Example command:

perl create.pl --path=/var/www/domian --name="Domian-Suche" --parameter=https://www.youtube.com/watch\?v\=BRe8VCqepgQ\&list\=PLQ9CsdXRvhNcSiQB-OSbfkiBbwX2E8ICP

--help													This help
--nocomments												Disables comment downloader
--lang=de												Set language of the transcripts (default: de)
--debug													Enables debug output
--path=/path/												Path where the index.php and results should be stored
--name="Name"												Name of the search
--parameter=https://www.youtube.com/watch?v=07s3E2Gcvcs&list=PLQ9CsdXRvhNdqpNCs-Fsy4NSIQnWfsYiM		Youtube link (playlist or single video or channel) that should be downloaded
--titleregex="a.*b"											Only download videos in which's titles the regex matches
--rename												Prompt for a new search name even if one exists already
--repair												Repairs a repository
--random												Shuffles order of downloading randomly	
--update_existing=/path/										Finds currently existing searches in folder "/path/" and updates them
--reparse_comments											Reparse old comments
EOL

	exit $exit_code;
}

sub create_index_file {
	debug "create_index_file()";
	my $index = "$options{path}/index.php";
	if(-e $index) {
		mywarn "$index already exists! Unlinking it.";
		unlink $index;
	}


	my $contents = '';
	my $data_start = tell DATA;
	while (<DATA>) {
		$contents .= $_;
	}
	seek DATA, $data_start, 0;

	if($options{name}) {
		$contents =~ s#SUCHENAME#$options{name}#g;
	} else {
		mywarn "Es wurde kein Name angegeben. Ersetze ihn manuell (SUCHENAME in der $index)"
	}

	open my $fh, '>', $index or die $!;
	print $fh $contents;
	close $fh;
}

sub analyze_args {
	foreach (@_) {
		if(m#^--debug(?:=(\d+)?)?$#) {
			if(length($1)) {
				$options{debug} = $1;
			} else {
				$options{debug} = 1;
			}
		} elsif(m#^--repair(=\d+)?$#) {
			$options{repair} = 1;
		} elsif(m#^--update_existing=(.*)#) {
			if(-d $1) {
				$options{update_existing} = $1;
			} else {
				die "$1 is not a folder";
			}
		} elsif(m#^--parameter_is_playlist$#) {
			$options{parameter_is_playlist} = 1;
		} elsif(m#^--reparse_comments$#) {
			$options{reparse_comments} = 1;
		} elsif(m#^--only_download_comments_for_existing_videos$#) {
			$options{only_download_comments_for_existing_videos} = 1;
		} elsif(m#^--commentlimit=(\d+)?$#) {
			$options{commentlimit} = $1;
		} elsif(m#^--titleregex=(.*)$#) {
			$options{titleregex} = $1;
		} elsif(m#^--rename$#) {
			$options{rename} = 1;
		} elsif(m#^--path=(.*)$#) {
			$options{path} = $1;
		} elsif(m#^--nocomments$#) {
			$options{comments} = 0;
		} elsif(m#^--lang=(.*)$#) {
			$options{lang} = $1;
		} elsif(m#^--name=(.*)$#) {
			$options{name} = $1;
		} elsif(m#^--random$#) {
			$options{random} = 1;
		} elsif(m#^--help$#) {
			_help(0);
		} elsif(m#^--parameter=(.*)$#) {
			$options{parameter} = $1;
		} else {
			mywarn color("red")."Unknown parameter `$_`".color("reset")."\n";
			_help(1);
		}
	}
}

sub read_and_parse_file {
	my $file = shift;
	my $id = shift;
	debug "read_and_parse_file($file, $id)";

	my $contents = "[00:00 -> https://www.youtube.com/watch?v=$id&t=0] ";

	open my $fh, '<', $file or die $!;
	while (my $line = <$fh>) {
		if($line =~ m#^\[(\d+):(\d+)\]$#) {
			my ($hour, $minute) = ($1, $2);
			my $ytlink = create_ytlink($id, $hour, $minute);
			$line = "[$1:$2 -> $ytlink] ";
		#if($line =~ m#^(\[\d+:\d+ ->.*\])(.*)#) {
		#	$line = "\n$1 $2";
		}
		$contents .= $line;
	}
	close $fh;

	return $contents;
}

sub create_ytlink {
	my ($id, $hour, $minute) = @_;
	debug "create_ytlink($id, $hour, $minute)";

	my $time = ($hour * 3600) + ($minute * 60);
	my $ytlink = 'https://www.youtube.com/watch?v='.$id.'&t='.$time;
	return $ytlink;
}

sub write_file {
	my $file = shift;
	my $contents = shift;
	debug "write_file($file, ...)";

	open my $fh, '>', $file or die $!;
	print $fh $contents;
	close $fh or die $!;
}

sub uniq {
	debug "uniq(...)";
	my %seen;
	grep !$seen{$_}++, @_;
}

__DATA__
<!DOCTYPE html>
<html lang="de">
<?php
	$GLOBALS['script_starttime'] = time();
	$GLOBALS['pagenr'] = 0;
	if(array_key_exists("pagenr", $_GET)) {
		if(!preg_match('/^\d+$/', $_GET['pagenr'])) {
			$GLOBALS['pagenr'] = 0;
		} else {
			$GLOBALS['pagenr'] = $_GET['pagenr'];
		}
	} else {
		$GLOBALS['pagenr'] = 0;
	}

	$GLOBALS['results_per_page'] = 20;
	$GLOBALS['min_result'] = $GLOBALS['pagenr'] * $GLOBALS['results_per_page'];
	$GLOBALS['max_result'] = $GLOBALS['min_result'] + $GLOBALS['results_per_page'];


	$GLOBALS['show_next_page'] = 0;
?>
<head>
<title>SUCHENAME-Suche</title>
<style>
	table, th, td {
		border: 1px solid black;
	} 
	.find {
		background-color: orange;
	}

	.tr_0 {
		background-color: white;
	}

	.tr_1 {
		background-color: #ededed;
	}

	.tab {
		overflow: hidden;
		border: 1px solid #ccc;
		background-color: #f1f1f1;
	}

	.tab button {
		background-color: inherit;
		float: left;
		border: none;
		outline: none;
		cursor: pointer;
		padding: 14px 16px;
		transition: 0.3s;
		font-size: 17px;
	}

	.tab button:hover {
		background-color: #ddd;
	}

	.tab button.active {
		background-color: #ccc;
	}


	.commentstyle {
		font-size: 10px;
		padding: 6px 12px;
		border: 1px solid #ccc;
		border-top: none;
	}

	.tabcontent {
		font-size: 10px;
		display: none;
		padding: 6px 12px;
		border: 1px solid #ccc;
		border-top: none;
	}

	.button {
		background-color: #f0f0f0;
	}

	.checkboxclass {
		outline: 1px solid #1e5180;
	}

</style>
<script>
	function openCommentNoMarking(idname, ytid) {
		var i, tabcontent, tablinks;
		tabcontent = document.getElementsByClassName("tabcontent_" + ytid);
		for (i = 0; i < tabcontent.length; i++) {
			tabcontent[i].style.display = "none";
		}
		tablinks = document.getElementsByClassName("tablinks");
		for (i = 0; i < tablinks.length; i++) {
			tablinks[i].className = tablinks[i].className.replace(" active", "");
		}
		document.getElementById(idname).style.display = "block";
	}

	function openComment(evt, idname, ytid) {
		openCommentNoMarking(idname, ytid);
		evt.currentTarget.className += " active";
	}
</script>
</head>
<body>
<?php
	function count_number_of_results () {
		$fi = new FilesystemIterator(__DIR__.'/results/', FilesystemIterator::SKIP_DOTS);
		return iterator_count($fi);
	}
?>
<h1><a href="index.php">SUCHENAME-Suche</a></h1>

Searching through <?php print count_number_of_results(); ?> files

<form method="get">
<table>
	<tr>
		<td>Stichwort</td><td><input name="suche1" value="<?php print array_key_exists('suche1', $_GET) ? htmlentities($_GET['suche1']) : ''; ?>" /></td>
	</tr>
	<tr>
		<td>Hat Zeitkommentar?</td><td><input name="hastimecomment" value="1" <?php print array_key_exists('hastimecomment', $_GET) ? ' checked="CHECKED" ' : ''; ?> type="checkbox" class="checkboxclass" /></td>
	</tr>
	<tr>
		<td></td><td><input class="button" type="submit" value="Suchen" /></td>
	</tr>
</table>
</form>

<?php


$GLOBALS['php_start'] = time();
error_reporting(E_ALL);

set_error_handler(function ($severity, $message, $file, $line) {
	throw new \ErrorException($message, $severity, $severity, $file, $line);
});

ini_set('display_errors', 1);

function dier ($data, $enable_html = 0, $die = 1) {
	$debug_backtrace = debug_backtrace();
	$source_data = $debug_backtrace[0];

	$source = '';

	if(array_key_exists(1, $debug_backtrace) && array_key_exists('file', $debug_backtrace[1])) {
		@$source .= 'Aufgerufen von <b>'.$debug_backtrace[1]['file'].'</b>::<i>';
	}
	
	if(array_key_exists(1, $debug_backtrace) && array_key_exists('function', $debug_backtrace[1])) {
		@$source .= $debug_backtrace[1]['function'];
	}

	@$source .= '</i>, line '.htmlentities($source_data['line'])."<br />\n";

	print "<pre>\n";
	ob_start();
	print_r($data);
	$buffer = ob_get_clean();
	if($enable_html) {
		print $buffer;
	} else {
		print htmlentities($buffer);
	}
	print "</pre>\n";
	print "Backtrace:\n";
	print "<pre>\n";
	foreach ($debug_backtrace as $trace) {
		print htmlentities(sprintf("\n%s:%s %s", $trace['file'], $trace['line'], $trace['function']));
	}
	print "</pre>\n";
	exit();
}

function mark_time_in_timestamp_comment ($timestamp_comment, $time_in_s, $id) {
	$splitted_by_newlines = explode("\n", $timestamp_comment);

	$found = null;
	$i = 0;
	$earliest_time = 999999;
	foreach ($splitted_by_newlines as $line) {
		if(is_null($found)) {
			if(preg_match("/<a href=.*?v=.*t=(.*)'>/", $line, $all_matches)) {
				if($earliest_time > $all_matches[1]) {
					$earliest_time = $all_matches[1];
				}

				if ($all_matches[1] >= $time_in_s) {
					$found = $i;
				}
			}
			$i++;
		}
	}

	if(is_null($found)) {
		$found = count($splitted_by_newlines);
	}

	if($earliest_time > $time_in_s) {
		array_unshift($splitted_by_newlines, "<b><a href='https://www.youtube.com/watch?v=$id&t=$time_in_s'>".seconds2human($time_in_s)."</a> Keine Beschreibung</b><br>");
	} else {
		$found = $found - 1;
	}

	if(!is_null($found)) {
		$splitted_by_newlines[$found] = "<b>".$splitted_by_newlines[$found]."</b>";
	}

	$timestamp_comment_marked = join("\n", $splitted_by_newlines);
	return $timestamp_comment_marked;
}

function find_matches_in_comments ($stichwort, $id, $i) {
	$this_finds = array();
	if(file_exists("./comments/".$id."_0.json")) {
		$fn = fopen("./comments/".$id."_0.json", "r");

		while(!feof($fn))  {
			$result = fgets($fn);
			$result = strtolower($result);
			if(preg_match_all("/.*$stichwort.*/", $result, $matches, PREG_SET_ORDER)) {
				$this_finds[] = new searchResult($id, $matches, $result, $stichwort, $i);
			}
		}

		fclose($fn);
	}
	return $this_finds;
}

function find_matches_in_desc ($stichwort, $id, $i) {
	$this_finds = array();
	if(file_exists("./desc/".$id."_TITLE.txt")) {
		$fn = fopen("./desc/".$id."_TITLE.txt", "r");

		while(!feof($fn))  {
			$result = fgets($fn);
			$result = strtolower($result);
			if(preg_match_all("/.*$stichwort.*/", $result, $matches, PREG_SET_ORDER)) {
				$this_finds[] = new searchResult($id, $matches, $result, $stichwort, $i);
			}
		}

		fclose($fn);
	}
	return $this_finds;
}

function find_matches_in_titles ($stichwort, $id, $i) {
	$this_finds = array();
	if(file_exists("./titles/".$id."_TITLE.txt")) {
		$fn = fopen("./titles/".$id."_TITLE.txt", "r");

		while(!feof($fn))  {
			$result = fgets($fn);
			$result = strtolower($result);
			if(preg_match_all("/.*$stichwort.*/", $result, $matches, PREG_SET_ORDER)) {
				$this_finds[] = new searchResult($id, $matches, $result, $stichwort, $i);
			}
		}

		fclose($fn);
	}
	return $this_finds;
}

function link_url ($string) {
	$url = '~(?:(https?)://([^\s<]+)|(www\.[^\s<]+?\.[^\s<]+))(?<![\.,:])\d+~i';
	$string = preg_replace($url, '<a href="$0" target="_blank" title="$0">$0</a>', $string);
	return $string;
}

function mark_results ($stichwort, $string) {
	$string = preg_replace("/($stichwort)/", "<span class='find'>$0</span>", $string);
	return $string;
}

function timestamp_file_exists ($id) {
	if(file_exists("./comments/".$id."_0.json")) {
		return True;
	} else {
		return False;
	}
}

function find_matches_in_main_text ($stichwort, $id, $i) {
	if(show_entry($id)) {
		$this_finds = array();
		$fn = fopen("./results/$id.txt", "r");

		$str = '';
		$j = 0;
		$continue = 1;
		while($continue) {
			if($j <= $GLOBALS['max_result']) {
				$result = fgets($fn);
				if(preg_match_all("/.*$stichwort.*/i", $result, $matches, PREG_SET_ORDER)) {
					$lc_matches = array();
					foreach ($matches as $this_match) {
						if(preg_match('/^(\[.*\])(.*)/', $this_match[0], $internal_matches)) {
							$timestamp = $internal_matches[1];
							$text = strtolower($internal_matches[2]);
							$new_text = "$timestamp$text";
							$lc_matches[][] = $new_text;
						} else {
							$lc_matches[][] = $this_match[0];
						}
					}
					$this_finds[] = new searchResult($id, $lc_matches, $result, $stichwort, $i);
					$str = $str.$result;
					$j++;
				}
				$continue = !feof($fn);
			} else if($j > $GLOBALS['max_result']) {
				$GLOBALS['show_next_page'] = 1;
				$continue = 0;
				break;
			} else {
				$continue = !feof($fn);
			}

			if(!$continue) {
				break;
			}
		}

		fclose($fn);

		return $this_finds;
	} else {
		return array();
	}
}

function print_table ($finds, $is_title = 0) {
	$anzahl = count($finds);
	print "<table>\n";
	print "<tr>\n";
	print "<th>Nr.</th>\n";
	print "<th>Dauer</th>\n";
	print "<th>Desc<br/>Text</th>\n";
	print "<th>Titel</th>\n";
	print "<th>ID</th>\n";
	print "<th>Timestamp-Kommentare</th>\n";
	print "<th>Match</th>\n";
	print "</tr>\n";
	$j = 0;
	$max_i_per_page = $GLOBALS['results_per_page'];
	$show_max_result = ($GLOBALS['pagenr'] * $max_i_per_page) + $max_i_per_page;
	$show_min_result = $GLOBALS['pagenr'] * $max_i_per_page; 
	foreach ($finds as $this_find_key => $this_find) {
		if(property_exists($this_find, 'matches')) {
			if($show_min_result <= $j && $j <= $show_max_result) {
				if(show_entry($this_find->get_youtube_id(), $is_title)) {
					foreach ($this_find->get_matches() as $this_find_key2 => $this_find2) {
						$string = $this_find2[0];
						$string = link_url($string);
						$string = mark_results($this_find->stichwort, $string);
						print "<tr class='tr_".($j % 2)."'>\n";
						print "<td>$j</td>\n";
						print "<td>".$this_find->get_duration()."</td>\n";
						print "<td>".$this_find->get_desc().", ".$this_find->get_textfile_link()."</td>\n";
						print "<td>".$this_find->get_title()."</td>\n";
						print "<td><span style='font-size: 8;'><a href='http://youtube.com/watch?v=".$this_find->get_youtube_id()."'>".$this_find->get_youtube_id()."</a></span></td>\n";
						print "<td><span style='font-size: 11;'>".$this_find->get_timestamp_comments()."</span></td>\n";
						print "<td>$string</td></tr>\n";
					}
				}
			} else {
				$GLOBALS['show_next_page'] = 1;
			}
			$j++;
		}
	}

	if($j > $show_max_result) {
		$GLOBALS['show_next_page'] = 1;
	}

	if($GLOBALS['show_next_page']) {
		print '<tr style="background-color: yellow"><td colspan="7">';
		show_next_page();
		print '</tr></td>';
	}

	print "</table>\n";
}

function show_entry ($id, $is_title = False) {
	if($is_title) {
		return True;
	}
	if((array_key_exists('hastimecomment', $_GET) && timestamp_file_exists($id)) || !array_key_exists('hastimecomment', $_GET)) {
		return True;
	} else {
		return False;
	}
}

function get_all_files ($handle) {
	$files = array();
	while (false !== ($entry = readdir($handle))) {
		if(preg_match('/.*\.txt/', $entry)) {
			$files[] = $entry;
		}
	}
	closedir($handle);
	return $files;
}

function search_all_files ($files, $suchworte, $timeouttime, $timeout) {
	$finds = array();
	$comment_finds = array();
	$desc = array();
	$titles = array();


	foreach ($files as $key => $this_file) {
		if(count($finds) < ($GLOBALS['max_result'] + 10)) {
			$id = $this_file;
			$id = preg_replace('/\.txt$/', '', $id);

			$starttime = time();
			$i = 0;
			foreach ($suchworte as $key => $stichwort) {
				$stichwort = strtolower($stichwort);

				$these_finds = find_matches_in_main_text($stichwort, $id, $i);
				$finds = array_merge($finds, $these_finds);
				$i++;

				$thistime = time();
				if($thistime - $starttime > $timeouttime) {
					$timeout = 1;
					continue;
				}

				if ($timeout) {
					continue;
				}
			}
		}
	}


	foreach ($files as $key => $this_file) {
		if(count($comment_finds) < ($GLOBALS['max_result'] + 10)) {
			$id = $this_file;
			$id = preg_replace('/\.txt$/', '', $id);

			$starttime = time();
			$i = 0;
			foreach ($suchworte as $key => $stichwort) {
				$stichwort = strtolower($stichwort);

				$comment_finds = array_merge($comment_finds, find_matches_in_comments($stichwort, $id, $i));
				$i++;

				$thistime = time();
				if($thistime - $starttime > $timeouttime) {
					$timeout = 1;
					continue;
				}

				if ($timeout) {
					continue;
				}
			}
		}
	}

	foreach ($files as $key => $this_file) {
		if(count($titles) < ($GLOBALS['max_result'] + 10)) {
			$id = $this_file;
			$id = preg_replace('/\.txt$/', '', $id);

			$starttime = time();
			$i = 0;
			foreach ($suchworte as $key => $stichwort) {
				$stichwort = strtolower($stichwort);

				$titles = array_merge($titles, find_matches_in_titles($stichwort, $id, $i));
				$i++;

				$thistime = time();
				if($thistime - $starttime > $timeouttime) {
					$timeout = 1;
					continue;
				}

				if ($timeout) {
					continue;
				}
			}
		}
	}

	foreach ($files as $key => $this_file) {
		if(count($desc) < ($GLOBALS['max_result'] + 10)) {
			$id = $this_file;
			$id = preg_replace('/\.txt$/', '', $id);

			$starttime = time();
			$i = 0;
			foreach ($suchworte as $key => $stichwort) {
				$stichwort = strtolower($stichwort);

				$desc = array_merge($desc, find_matches_in_desc($stichwort, $id, $i));
				$i++;

				$thistime = time();
				if($thistime - $starttime > $timeouttime) {
					$timeout = 1;
					continue;
				}

				if ($timeout) {
					continue;
				}
			}
		}
	}

	foreach ($files as $key => $this_file) {
		if(count($desc) < ($GLOBALS['max_result'] + 10)) {
			$id = $this_file;
			$id = preg_replace('/\.txt$/', '', $id);

			$starttime = time();
			$i = 0;
			foreach ($suchworte as $key => $stichwort) {
				$stichwort = strtolower($stichwort);

				$desc = array_merge($desc, find_matches_in_desc($stichwort, $id, $i));
				$i++;

				$thistime = time();
				if($thistime - $starttime > $timeouttime) {
					$timeout = 1;
					continue;
				}

				if ($timeout) {
					continue;
				}
			}
		}
	}

	return array($finds, $comment_finds, $titles, $desc, $timeout);
}

function seconds2human($ss) {
	$s = $ss % 60;
	$m = sprintf("%02d", floor(($ss % 3600)/60));
	$h = sprintf("%02d", floor(($ss % 86400)/3600));

	if($h) {
		return "$h:$m:$s";
	} else {
		return "$m:$s";
	}
}

class searchResult {
	public $youtube_id;
	public $timestamp_human;
	public $timestamp;
	public $title = '<i>Kein Titel</i>';
	public $duration;
	public $desc;
	public $timestamp_comments = '<i>&mdash;</i>';
	public $matches;
	public $result;
	public $textfile;
	public $stichwort;
	public $counter_i;

	function __construct($id, $matches, $result, $stichwort, $i) {
		$this->set_youtube_id($id);
		$this->set_matches($matches);
		$this->set_result($result);
		$this->set_timestamp_from_result();
		$this->set_timestamp_comments();
		$this->set_stichwort($stichwort);
		$this->set_textfile();
		$this->set_i($i);
	}


	function replace_seconds_timestamp_with_youtube_link ($content) {
		$id = $this->get_youtube_id();
		$this_object = $this;
		$GLOBALS['marked_time'] = 0;
		$GLOBALS['timestamp'] = $this->get_timestamp();

		$new_data = preg_replace_callback(
			"/((?:\d{1,2}:)?\d{1,2}:\d{2})/", function ($match) use ($id) {
				$original = $match[0];

				$str_time = preg_replace("/^([\d]{1,2})\:([\d]{2})$/", "00:$1:$2", $original);
				sscanf($str_time, "%d:%d:%d", $hours, $minutes, $seconds);
				$time_seconds = $hours * 3600 + $minutes * 60 + $seconds;
				$time_without_seconds = $hours * 3600 + $minutes * 60;

				$mark = '';
				$markend = '';

				if(0 && $GLOBALS['timestamp'] && !$GLOBALS['marked_time']) {
					if($time_without_seconds >= $GLOBALS['timestamp']) {
						$mark = '<span style="color: red">';
						$markend = "</span>";
						$GLOBALS['marked_time'] = 1;
					}
				}

				return "<a href='https://www.youtube.com/watch?v=".$this->get_youtube_id()."&t=$time_seconds'>$mark$original$markend</a>";
			}, 
			$content
		);
		$GLOBALS['marked_time'] = 0;
		$GLOBALS['timestamp'] = Null;
		return $new_data;
	}

	function get_timestamp_comments_data () {
		$timestamps_array = array();
		$this_timestamp_file = "./comments/".$this->get_youtube_id()."_0.json";
		$n = 0;
		while (file_exists($this_timestamp_file)) {
			$content = nl2br(file_get_contents($this_timestamp_file));
			$timestamps_array[] = $this->replace_seconds_timestamp_with_youtube_link($content);
			$n++;
			$this_timestamp_file = "./comments/".$this->get_youtube_id()."_".$n.".json";
		}
		return $timestamps_array;
	}

	function get_timestamp_comments_string () {
		$timestamps_array = $this->get_timestamp_comments_data();

		$timestamps = '';
		$i = $this->get_i();
		if(count($timestamps_array) > 1) {
			$timestamps .= '<div class="tab">';
			for ($n = 0; $n < count($timestamps_array); $n++) {
				$timestamps .= '<button class="tablinks" onclick="openComment(event, \''.$this->get_youtube_id().'_'.$i.'_'.$n.'\', \''.$this->get_youtube_id().'_'.$i.'\')">'.($n + 1).'</button>';
			}
			$timestamps .= '</div>';
			for ($n = 0; $n < count($timestamps_array); $n++) {
				$style = '';
				if($n == 0) {
					$style = " style='display: block !important;' ";
				} else {
					$style = " style='display: none !important;' ";
				}
				$timestamps .= '<div '.$style.' id="'.$this->get_youtube_id().'_'.$i.'_'.$n.'" class="tabcontent tabcontent_'.$this->get_youtube_id().'_'.$i.'">';
				$timestamps .= mark_time_in_timestamp_comment($timestamps_array[$n], $this->get_timestamp(), $this->get_youtube_id());
				$timestamps .= '</div>';
			}
		} else if (count($timestamps_array) == 1) {
			$timestamps .= "<div class='commentstyle'>".mark_time_in_timestamp_comment($timestamps_array[0], $this->get_timestamp(), $this->get_youtube_id())."</div>";
		}
		return $timestamps;
	}

	function get_title_from_file () {
		$title = NULL;
		$title_file = "titles/".$this->get_youtube_id()."_TITLE.txt";
		if(file_exists($title_file)) {
			$title = file_get_contents($title_file);
		}
		return $title;
	}

	function get_desc_from_file () {
		$desc_file = "desc/".$this->get_youtube_id()."_TITLE.txt";
		$desc = '<i>Keine Beschreibung</i>';
		if(file_exists($desc_file)) {
			$desc = "<a href='./$desc_file'>Desc</a>";
		}
		return $desc;
	}

	function set_youtube_id ($value) { 
		$this->youtube_id = $value;
		$this->set_textfile();
		$this->set_title();
		$this->set_duration();
		$this->set_desc();
	}
	function get_youtube_id () { return $this->youtube_id; }

	function get_textfile_link() {
		$file = "<a href='./results/".$this->get_youtube_id().".txt'>Text</a>";
		return $file;
	}
	function set_textfile () { $file = "./results/".$this->get_youtube_id().".txt"; if(file_exists($file)) { $this->textfile = $file; } }
	function get_textfile () { return $this->textfile; }

	function set_timestamp_human ($value) { $this->timestamp_human = $value; }
	function get_timestamp_human () { return $this->timestamp_human; }

	function set_timestamp ($value) { $this->timestamp = $value; }
	function get_timestamp () { return $this->timestamp; }

	function set_timestamp_from_result () {
		$ts_human = Null;
		$ts = Null;

		$id = $this->get_youtube_id();
		$result = $this->get_result();

		if(preg_match('/^\[((?:\d+:)?\d+:\d+) -> https:\/\/www.youtube.com\/watch\?v='.$id.'&t=(\d+)\]/', $result, $matches)) {
			$this->set_timestamp_human($matches[1]);
			$this->set_timestamp($matches[2]);
		}
	}

	function set_text ($value) { $this->text = $value; }
	function get_text () { return $this->text; }

	function set_title () {
		$value = $this->get_title_from_file();
		$value = str_replace(array("\n", "\r"), '', $value);       
		$this->title = $value;
	}
	function get_title () { return $this->title; }

	function get_duration_from_file() {
		$duration_file = "durations/".$this->get_youtube_id()."_TITLE.txt";
		$duration = '<i>Unbekannte Länge</i>';
		if(file_exists($duration_file)) {
			$duration = file_get_contents($duration_file);
		}
		return $duration;
	}
	function set_duration () {
		$value = $this->get_duration_from_file();
		$value = str_replace(array("\n", "\r"), '', $value);       
		$this->duration = $value;
	}
	function get_duration () { return $this->duration; }

	function set_desc () { $this->desc = $this->get_desc_from_file(); }
	function get_desc () { return $this->desc; }

	function set_timestamp_comments () { $this->timestamp_comments = $this->get_timestamp_comments_string(); }
	function get_timestamp_comments () { return $this->timestamp_comments; }

	function set_matches ($value) { $this->matches = $value; }
	function get_matches () { return $this->matches; }

	function set_result ($value) { $this->result = $value; }
	function get_result () { return $this->result; }

	function set_stichwort ($value) { $this->stichwort = $value; }
	function get_stichwort () { return $this->stichwort; }

	function set_i ($value) { $this->counter_i = $value; }
	function get_i () { return $this->counter_i; }
}

$suchworte = array();

foreach ($_GET as $key => $value) {
	if(preg_match('/suche\d+/', $key)) {
		if(preg_match('/.+/', $value)) {
			$suchworte[] = $value;
		}
	}
}

function show_next_page () {
	if($GLOBALS['show_next_page'] && array_key_exists('suche1', $_GET)) {
		print "<a href='".basename(__FILE__)."?suche1=".urlencode($_GET['suche1'])."&pagenr=".($GLOBALS['pagenr'] + 1)."&hastimecomment=".urlencode(array_key_exists("hastimecomment", $_GET) ? $_GET['hastimecomment'] : 0)."'>Next page (".$GLOBALS['results_per_page']." more results, also next page for all the other categories)</a>";
	}
	$GLOBALS['show_next_page'] =  0;
}

if(count($suchworte)) {
	$timeout = 0;
	$timeouttime = 1;
	if ($handle = opendir('./results/')) {
		$files = get_all_files($handle);

		$finds_and_comments_and_title_and_desc_timeout = search_all_files($files, $suchworte, $timeouttime, $timeout);

		$finds = $finds_and_comments_and_title_and_desc_timeout[0];
		$comments = $finds_and_comments_and_title_and_desc_timeout[1];
		$title = $finds_and_comments_and_title_and_desc_timeout[2];
		$desc = $finds_and_comments_and_title_and_desc_timeout[3];
		$timeout = $finds_and_comments_and_title_and_desc_timeout[4];


		if(count($finds)) {
			print "<a href='#text'>Text</a><br>";
		}

		if(count($comments)) {
			print "<a href='#kommentare'>Timestamp-Kommentare</a><br>";
		}

		if(count($title)) {
			print "<a href='#titel'>Titel</a><br>";
		}

		if(count($desc)) {
			print "<a href='#desc'>Beschreibungen</a><br>";
		}

		if(count($finds)) {
			print "<h2 id='text'>Text</h2>";
			print_table($finds);
		}

		if(count($comments)) {
			print "<h2 id='kommentare'>Timestamp-Kommentare</h2>";
			print_table($comments);
		}

		if(count($title)) {
			print "<h2 id='titel'>Titel</h2>";
			print_table($title, 1);
		}

		if(count($desc)) {
			print "<h2 id='desc'>Beschreibungen</h2>";
			print_table($desc, 1);
		}

		if($timeout) {
			print "timeout ($timeouttime sekunden) erreicht.";
		}
	} else {
		print "dir ./results/ not found";
	}
}

print "Time needed to search: ".(time() - $GLOBALS['script_starttime'])."<br>\n";
?>
</body>
</html>
