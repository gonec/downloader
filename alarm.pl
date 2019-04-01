#!/usr/bin/perl -w
use Net::FTP;
use strict;
use Getopt::Std;
use URI;
use Config::IniFiles;
use Getopt::Std;
use Getopt::Long;
use threads;
use IO::Socket::INET;
our %settings;
our $last_error;
use File::Copy;
use File::Basename;
use Text::Iconv;
use DBI;
use strict;
sub ping_db {
	my $driver = "mysql";
	my $database = "mydb";
	my $dsn ="DBI:$driver:database=$database";
	my $user = "alarm";
	my $password = "alarmuser";
	my $dbh = DBI->connect($dsn, $user, $password) or return;
	my $up_str = "UPDATE services SET updated_at=NOW() WHERE id=2";
	my $sth = $dbh->prepare( $up_str );
	if ( $sth->execute() ) {
		$dbh->disconnect;
	}
}

#$|=1;
#open(my $FH,">", "c:/CODE/a.log");
#print $FH "WORKING\n";
#close $FH;
my %opts;
getopts('f:', \%opts);
my $ini_file;
if ( defined($opts{'f'}) ) {
	$ini_file = $opts{'f'};
}
else {
	die "can't read settings $ini_file\n";
}

sub start() {
	system("echo $$>alarm.pid");	
}


sub start_check(){
	print "MY PID $$\n";
	my $PID_FILE='/home/user/alarm.pid';
	if ( -f $PID_FILE) {
		if ( open(my $FH, '<', $PID_FILE) ) {
			my $pid = <$FH>;		
			chomp $pid;
			print "PID $pid\n";
			if (-e "/proc/$pid"){
				print "process already running\n";
				exit 0;
			}
			else {
				print "process not running\n";
				start();	
			}	
		}	
	}
	else{
		start();
	}
}


start_check();





my $ini = Config::IniFiles->new(-file=>$ini_file);
my $login = $ini->val('ftp', 'ftp_login');
my $pass  = $ini->val('ftp', 'ftp_password');
my $local_storage = $ini->val('ftp', 'ftp_dir');

my $exchange_dir = '/samba/allaccess/exchange/';
my $archive_dir  = '/samba/allaccess/storage/';

$settings{'ftp_user'} = $login;
$settings{'ftp_pass'} = $pass;
#$settings{'local_storage'} = $local_storage;
$settings{'local_storage'} = $exchange_dir;
$settings{'ftp_host'} ||= 'gonetsserv.ru';
#Подставляем логин
$settings{'ftp_user'} ||= '__FTP__LOGIN__';
#Подставляем пароль
$settings{'ftp_pass'} ||= '__FTP__PASSW__';
$settings{'ftp_prefix_files'} ||= 'inbox/';
#$settings{'local_storage'} ||= '/ftp/working_storage/';
sub archive_file{
	my $full_path = shift;
	my $file = basename($full_path);
	copy($full_path, $archive_dir.$file) or return 0;	
	#my $res = system("convmv -f cp1251 -t UTF-8 --notest /samba/allaccess/storage/$file");	
	return 1;
}


sub main(){
	
	$|=1;
	my $socket = new IO::Socket::INET(
		PeerHost => '127.0.0.1',
		PeerPort => '6666',
		Proto => 'tcp'
	);
	for (;;) {
	my $where_put = $settings{'local_storage'};
    	my $time_start = time;
	opendir (my $DIR, $settings{'local_storage'});
	my %h;
	my @local_files = readdir($DIR);
	foreach (@local_files) {
		$h{$_} = 1;
	}
	my $ftp;
	unless($ftp = Net::FTP->new($settings{'ftp_host'}, Debug=>1, Passive=>1)) {
		$last_error = "Cannot connect to".$settings{'ftp_host'};
		#print $FH $last_error;
		return 0; 
    	}
    	print "TIMEOUT: ".$ftp->timeout."\n";
    	if(!$ftp->login( $settings{'ftp_user'}, $settings{'ftp_pass'} )){
		#print "LOGIN FAILED $@\n";
		print "FTP_USER:\t".$settings{'ftp_user'}."\n";
		print "FTP_PASS:\t".$settings{'ftp_pass'}."\n";
		#$socket->send("FTP_FAILED");
		$last_error = "ftp login error ftp user:".$settings{'ftp_user'}."ftp pass:".$settings{'ftp_pass'} ;
		print $last_error;
		return 0;	
   	}
	else{
		#$socket->send("FTP_OK");
	}	
    	
    	$ftp->binary();
    	$ftp->cwd('inbox');
    	
    	my @server_files = $ftp->ls();
    	print "LIST SIZE".scalar(@server_files);
	
	my @download_list = ();
	foreach my $ftp_file (@server_files) {
		unless ( defined( $h{$ftp_file} ) ) {
			push @download_list, $ftp_file;
		}
	}    	 
	my $download_list_size = scalar @download_list;
	#$socket->send("DOWNLOAD:"."$download_list_size");
	#$socket->send("DOWNLOADED:0");
	my $downloaded_counter=0;
	foreach my $downloaded_file (@download_list) {
		my $converter = Text::Iconv->new('WINDOWS-1251', 'UTF-8');
		my $utf_downloaded_file = $converter->convert($downloaded_file);	
		my $downloaded_file_full = 	$where_put.$utf_downloaded_file;
		if ( !$ftp->get($downloaded_file, $downloaded_file_full) ) {
			my $last_error = "CAN NOT DOWNLOAD: $downloaded_file to $where_put  server message:".$ftp->message."\n";
			#print $last_error;
			return 0;	
		}	
		else {
			if( archive_file($downloaded_file_full)	){
				print "DELETING $downloaded_file\n";	
				$ftp->delete($downloaded_file);		
			}		
			
			$downloaded_counter++;
			#$socket->send("DOWNLOADED:".$downloaded_counter);
			$h{$downloaded_file} = 1;
			$last_error = "everythins is ok!\n";
		
	}
		
	}
	my $time_end = time;
	my $delta_time = $time_end - $time_start;
	print "DELTA TIME $delta_time";
	sleep(10);
	ping_db();	
	}
}
main();
