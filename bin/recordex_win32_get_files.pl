use Win32::SerialPort;
use File::Copy::Recursive qw (rcopy);

my($src, $dst) = ("g:", "y:\\dvd");

my $serial = serial_init("COM3") || die "can't open serial port!";
serial_write($serial, "\0");
serial_write($serial, "!BNKSTA3");
sleep(1);
serial_write($serial, "\0");
serial_write($serial, "!BNKLF8E");
serial_write($serial, "!BNKLR9A");
serial_write($serial, "!BNKPG93");
serial_write($serial, "!BNKPH94");
serial_write($serial, "!BNKLF8E");
serial_write($serial, "!BNKLG8F");

my $count = 35;

for (;;)
{
    disk_open($serial, $src);
    disk_eject($serial);
    disk_get($serial);
    disk_close($src);
    mkdir("$dst\\dvd_$count");
    disk_copy($serial, $src, "$dst\\dvd_$count");
    sleep(10);
    $count++;
}

# METHODES

sub serial_init
{
    my $port_name = shift;

    print("try to open $port_name serial port...\n");

    my $serial = Win32::SerialPort->new($port_name) || return;

    $serial->baudrate(9600);
    $serial->databits(8);
    $serial->parity("none");
    $serial->stopbits(1);
    $serial->handshake("dtr");
    $serial->buffers(4096, 64);
    print("serial port opened\n");

    return $serial;
}

sub serial_write
{
    my($serial, $data) = @_;

    if (defined(my $count = $serial->write("$data\r\n")))
    {
	return if ($count == length($data)+2);

	warn "write incomplete!!\n";
	return;
    }

    warn "write failed!!\n";
}

sub disk_open
{
    my($serial, $src) = @_;
    serial_write($serial, "\0");
    print("open disk...\n");
    system("nircmd.exe cdrom open $src");
    sleep(1);
}

sub disk_eject
{
    my $serial = shift;
    print("eject disk...\n");
    serial_write($serial, "!BNKPG93");
    sleep(3);
    serial_write($serial, "!BNKPH94");
    sleep(3);
}

sub disk_get
{
    my $serial = shift;
    print("get new disk...\n");
    serial_write($serial, "!BNKDP90");
    sleep(5);
}

sub disk_close
{
    my $src = shift;
    print("close disk...\n");
    system("nircmd.exe cdrom close $src");
    sleep(3);
}

sub disk_copy
{
    my($serial, $src, $dst) = @_;

    my $dir_handle;

    print("copy disk...\n\n");

    unless (defined(opendir($dir_handle, $src)))
    {
	$serial->close || die "failed to close";
	print("serial port closed!\n");
	die "finished!";
    }

    closedir($dir_handle);

    rcopy($src, $dst);
    sleep(5);
}
