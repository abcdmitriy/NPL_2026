
use strict;
use warnings;
use Text::CSV;

# 1. Чтение списка файлов из input.txt
open my $list_fh, '<:encoding(UTF-8)', 'input.txt'
    or die "Cannot open input.txt: $!\n";

my @files;

while (my $line = <$list_fh>) {
    chomp $line;
    $line =~ s/^\s+|\s+$//g;
    push @files, $line if length $line;
}

close $list_fh;

die "Error: file list in input.txt is empty\n" unless @files;

# Инициализация CSV-парсера
my $csv = Text::CSV->new({
    binary    => 1,
    auto_diag => 2,
    eol       => "\n"
}) or die "Cannot initialize Text::CSV\n";

my $expected_header;

# 2. Проверка существования файлов и совпадения заголовков
foreach my $file (@files) {
    die "Error: file '$file' does not exist or is not a file\n"
        unless -f $file;

    open my $fh, '<:encoding(UTF-8)', $file
        or die "Cannot open file '$file': $!\n";

    my $header = $csv->getline($fh);

    unless (defined $header) {
        close $fh;
        die "Error: file '$file' is empty or has no header\n";
    }

    if (!defined $expected_header) {
        $expected_header = [@$header];
    } else {
        my @diffs;

        my $max_cols = scalar(@$expected_header);
        $max_cols = scalar(@$header)
            if @$header > $max_cols;

        for (my $i = 0; $i < $max_cols; $i++) {
            my $has_expected = $i < @$expected_header;
            my $has_actual = $i < @$header;

            my $same = 0;

            if ($has_expected && $has_actual) {
                my $expected = $expected_header->[$i];
                my $actual = $header->[$i];

                $same = 1 if
                    (!defined $expected && !defined $actual) ||
                    (defined $expected && defined $actual &&
                     $expected eq $actual);
            }

            next if $same;

            my $expected_text = $has_expected
                ? "'" . (defined $expected_header->[$i]
                    ? $expected_header->[$i] : '') . "'"
                : "<missing>";

            my $actual_text = $has_actual
                ? "'" . (defined $header->[$i]
                    ? $header->[$i] : '') . "'"
                : "<missing>";

            push @diffs,
                "Column " . ($i + 1) .
                ": expected $expected_text, got $actual_text";
        }

        if (@diffs) {
            close $fh;

            die "ERROR: headers in '$file' do not match.\n" .
                "Differences:\n" . join("\n", @diffs) . "\n";
        }
    }

    close $fh;
}

# 3. Создание итогового файла
open my $out_fh, '>:encoding(UTF-8)', 'output.csv'
    or die "Cannot create output.csv: $!\n";

my @output_header = (@$expected_header, '_source');

$csv->print($out_fh, \@output_header)
    or die "Cannot write output header\n";

# 4. Последовательное объединение данных
my $total_rows = 0;

foreach my $file (@files) {
    open my $fh, '<:encoding(UTF-8)', $file
        or die "Cannot open file '$file': $!\n";

    # Пропуск заголовка
    my $header = $csv->getline($fh);

    my $record_number = 1;

    while (my $row = $csv->getline($fh)) {
        $record_number++;

        if (@$row != @$expected_header) {
            die "Error: different number of fields in '$file', " .
                "record $record_number\n";
        }

        # Добавление имени файла-источника
        push @$row, $file;

        $csv->print($out_fh, $row)
            or die "Cannot write record to output.csv\n";

        $total_rows++;
    }

    close $fh;
}

close $out_fh
    or die "Cannot close output.csv: $!\n";

print "Success: data from " . scalar(@files) .
      " files merged into output.csv\n";

print "Total records: $total_rows\n";
