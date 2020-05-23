#!/usr/bin/perl

use strict;
use warnings;
use Term::ANSIColor;
use File::Path qw(make_path);
use Data::Dumper;
use autodie;
use Digest::MD5 qw/md5_hex/;
use Smart::Comments;

my %options = (
	debug => 0,
	parameter => undef,
	path => undef,
	name => undef,
	lang => 'de'
);

analyze_args(@ARGV);

sub mywarn (@) {
	foreach (@_) {
		warn color("yellow").$_.color("reset")."\n";
	}
}

sub debug (@) {
	return if !$options{debug};
	foreach (@_) {
		warn color("blue").$_.color("reset")."\n";
	}
}

main();

sub main {
	debug "main()";
	
	if($options{path}) {
		make_path($options{path});
		create_index_file();
	}

	if($options{parameter}) {
		download_data();
	} else {
		mywarn "No --parameter option given, not downloading any videos";
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
	make_path($results);
	make_path($dl);
	make_path($durations);
	make_path($desc);
	make_path($titles);

	my @ids = ();
	if($start =~ m#list#) {
		push @ids, dl_playlist($start);
	} else {
		push @ids, $start;
	}

	foreach my $id (sort { rand() <=> rand() } @ids) { ### Working===[%]     done
		warn "\n"; # for smart comments
		debug "Getting data for id $id";
		my $unavailable = "$options{path}/unavailable";
		my $results_id = "$results/$id.txt";
		my $duration_file = "$durations/".$id."_TITLE.txt";
		my $desc_file = "$desc/".$id."_TITLE.txt";
		my $title_file = "$titles/".$id."_TITLE.txt";

		if(file_contains($unavailable, $id)) {
			mywarn "$id is listed in `$unavailable`, skipping it";
			next;
		}

		if (-f $results_id) {
			mywarn "$id already downloaded";
		} else {
			my $downloaded_filename = transcribe($dl, $id);
			if(-e $downloaded_filename) {
				my $contents = parse_vtt($downloaded_filename);
				open my $fh, '>', $results_id or die $!;
				print $fh $contents;
				close $fh;

				#my $contents_edited = read_and_parse_file($downloaded_filename, $id);
				my $contents_edited = read_and_parse_file($results_id, $id);
				write_file($results_id, $contents_edited);
			} else {
				mywarn "$downloaded_filename did not get downloaded correctly";
			}
		}

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

	warn "got ".Dumper(@list);

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
			$line !~ m#^\d{2}:\d{2}:\d{2}\.\d{3}\s*-->\s*\d{2}:\d{2}:\d{2}\.\d{3}\s*align:start position:0%$# &&
			$line ne get_last_line($contents)
		) {
			$contents .= "$line\n";
		} elsif (
			$line =~ m#^(\d{2}):(\d{2}):\d{2}\.\d{3}\s*-->\s*\d{2}:\d{2}:\d{2}\.\d{3}\s*align:start position:0%$#
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
--lang=de												Set language of the transcripts (default: de)
--debug													Enables debug output
--path=/path/												Path where the index.php and results should be stored
--name="Name"												Name of the search
--parameter=https://www.youtube.com/watch?v=07s3E2Gcvcs&list=PLQ9CsdXRvhNdqpNCs-Fsy4NSIQnWfsYiM		Youtube link (playlist or single video or channel) that should be downloaded
EOL

	exit $exit_code;
}

sub create_index_file {
	debug "create_index_file()";
	my $index = "$options{path}/index.php";
	if(-e $index) {
		mywarn "$index already exists!"	
	} else {
		my $contents = '';
		while (<DATA>) {
			$contents .= $_;
		}

		if($options{name}) {
			$contents =~ s#SUCHENAME#$options{name}#g;
		} else {
			mywarn "Es wurde kein Name angegeben. Ersetze ihn manuell (SUCHENAME in der $index)"
		}

		open my $fh, '>', $index or die $!;
		print $fh $contents;
		close $fh;
	}
}

sub analyze_args {
	foreach (@_) {
		if(m#^--debug$#) {
			$options{debug} = 1;
		} elsif(m#^--path=(.*)$#) {
			$options{path} = $1;
		} elsif(m#^--lang=(.*)$#) {
			$options{lang} = $1;
		} elsif(m#^--name=(.*)$#) {
			$options{name} = $1;
		} elsif(m#^--help$#) {
			_help(0);
		} elsif(m#^--parameter=(.*)$#) {
			$options{parameter} = $1;
		} else {
			warn color("red")."Unknown parameter `$_`".color("reset")."\n";
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

__DATA__
<head>
	<title>SUCHENAME-Suche</title>
	<style type="text/css">
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
	</style>
</head>
<h1>SUCHENAME-Suche</h1>
Stichwort: <form method="get">
	<input name="suche1" value="<?php print array_key_exists('suche1', $_GET) ? htmlentities($_GET['suche1']) : ''; ?>" />
	<input type="submit" value="Suchen" />
</form>

<?php
	$suchworte = array();

	foreach ($_GET as $key => $value) {
		if(preg_match('/suche\d+/', $key)) {
			if(preg_match('/.+/', $value)) {
				$suchworte[] = $value;
			}
		}
	}

	if(count($suchworte)) {
		$timeout = 0;
		$timeouttime = 1;
		if ($handle = opendir('./results/')) {
			$files = array();
			while (false !== ($entry = readdir($handle))) {
				if(preg_match('/.*\.txt/', $entry)) {
					$files[] = $entry;
				}
			}
			closedir($handle);

			$finds = array();
			foreach ($files as $key => $thisfile) {
				$id = $thisfile;
				$id = preg_replace('/\.txt$/', '', $id);

				$starttime = time();
				foreach ($suchworte as $key => $this_stichwort) {
					$this_stichwort = strtolower($this_stichwort);

					$fn = fopen("./results/$thisfile", "r");

					while(!feof($fn))  {
						$result = fgets($fn);
						if(preg_match_all("/.*$this_stichwort.*/", $result, $matches, PREG_SET_ORDER)) {
							$finds[] = array("matches" => $matches, "id" => $id);
						}
					}

					fclose($fn);

					$thistime = time();
					if($thistime - $starttime > $timeouttime) {
						$timeout = 1;
						continue;
					}
				}
			}
			if(!count($finds)) {
				print("Keine Ergebnisse");
			} else {
				$url = '~(?:(https?)://([^\s<]+)|(www\.[^\s<]+?\.[^\s<]+))(?<![\.,:])\d+~i';
				$anzahl = count($finds);
				print "Anzahl Ergebnisse: $anzahl<br />\n";
				print "<table>\n";
				print "<tr>\n";
				print "<th>Nr.</th>\n";
				print "<th>Dauer</th>\n";
				print "<th>Desc<br/>Text</th>\n";
				print "<th>Titel</th>\n";
				print "<th>ID</th>\n";
				print "<th>Match</th>\n";
				print "</tr>\n";
				$i = 1;
				foreach ($finds as $this_find_key => $this_find) {
					$matches = $this_find['matches'];
					$id = $this_find['id'];
					$title_file = "titles/".$id."_TITLE.txt";
					$title = '<i>Kein Titel</i>';
					if(file_exists($title_file)) {
						$title = file_get_contents($title_file);
					}

					$duration_file = "durations/".$id."_TITLE.txt";
					$duration = '<i>Unbekannte Länge</i>';
					if(file_exists($duration_file)) {
						$duration = file_get_contents($duration_file);
					}

					$desc_file = "desc/".$id."_TITLE.txt";
					$desc = '<i>Keine Beschreibung</i>';
					if(file_exists($desc_file)) {
						$desc = "<a href='./$desc_file'>Desc</a>";
					}

					$textfile = "<a href='./results/$id.txt'>Text</a>";

					foreach ($matches as  $this_find_key2 => $this_find2) {
						$string = $this_find2[0];
						$string = preg_replace($url, '<a href="$0" target="_blank" title="$0">$0</a>', $string);
						$string = preg_replace("/($this_stichwort)/", "<span class='find'>$0</span>", $string);
						print "<tr class='tr_".($i % 2)."'>\n";
						print "<td>$i</td>\n";
						print "<td>$duration</td>\n";
						print "<td>$desc, $textfile</td>\n";
						print "<td>$title</td>\n";
						print "<td><span style='font-size: 8;'>$id</span></td>\n";
						#print "<td>$likes/$dislikes</td>\n";
						print "<td>$string</td></tr>\n";
					}
					$i++;
				}
				print "</table>\n";
				if($timeout) {
					print "Timeout ($timeouttime Sekunden) erreicht.";
				}
			}
		} else {
			print "Dir ./results/ not found";
		}
	}
?>
