perl -e 'use Tie::File;
while (my $filename = <*.txt>) {
    my $id = ($filename =~ s#\.txt##r); 
    print "$filename -> $id\n"; 
    tie @array, "Tie::File", $filename or die "Cannot open $filename"; 
    if($array[0] !~ m#^\[#) {
        $array[0] = q#[00:00 -> https://www.youtube.com/watch?v=#.$id.q#&t=0] #.$array[0];
        print $array[0];
    }
}'
