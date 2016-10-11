#!perl
use 5.006;
use strict;
use warnings;
use Test::More;
use Test::Exception;
use Test::Warn;
use DBI;
use DBD::Mock;
use DBIx::TransactionManager::Distributed qw(register_dbh release_dbh dbh_is_registered txn);
use Scalar::Util qw(refaddr);
use Devel::Refcount qw(refcount);

subtest register_dbh => sub {
    my $dbh;
    lives_ok { $dbh = DBI->connect('DBI:Mock:', '', '') || die 'cannot create dbh' } "create dbh";
    is(register_dbh('category1', $dbh), $dbh, 'register successfully');
    is(refcount($dbh), 1, 'dbh refcount is not increased');
    my $result;
    warning_like(
        sub { $result = register_dbh('category1', $dbh) },
        qr/already registered this database handle at/,
        'register again to same category will failed'
    );
    ok(!$result, 'register failed');
    my $history = $dbh->{mock_all_history};
    is(scalar(@$history), 0, 'no statement executed');
    is(release_dbh('category1', $dbh), $dbh, 'release successfully');
    warning_is(sub { register_dbh('category1', $dbh) },
        undef, 'register 3rd time to same category will not failed because previous register already released');
    is(release_dbh('category1', $dbh), $dbh, 'clear regsiter for later tests');

    local $DBIx::TransactionManager::Distributed::IN_TRANSACTION = 1;
    is(register_dbh('category1', $dbh), $dbh, 'register successfully');
    $history = $dbh->{mock_all_history};
    is(scalar(@$history),        1,            'has 1 statement executed');
    is($history->[0]->statement, 'BEGIN WORK', 'begin_work statement when registered during IN_TRANSACTION');
    warning_is(sub { $result = register_dbh('category2', $dbh) }, undef, 'no warnings emit');    # that means begin-work is not called again
    is($result, $dbh, 'register twice successfully');
    $result = undef;
    is(refcount($dbh), 1, 'dbh refcount is not increased');
    $history = $dbh->{mock_all_history};
    is(scalar(@$history),        1,            'still has only 1 statement executed, that means begin-work only run once');
    is($history->[0]->statement, 'BEGIN WORK', 'begin_work statement when registered during IN_TRANSACTION');
    is(release_dbh('category1', $dbh), $dbh, 'release it from category1');
    ok(!dbh_is_registered('category1', $dbh), 'dbh should not be in category2 now');
    ok(dbh_is_registered('category2', $dbh), 'the dbh should still be in category2');
    warning_like(
        sub { release_dbh('category1', $dbh) },
        qr/releasing unregistered dbh (\S+) for category category1 \(but found it in these categories instead: category2/,
        'has warnings because dbh already released before'
    );
    ok(!dbh_is_registered('category2', $dbh), 'dbh should not be in category2 now');
};

subtest register_fork => sub {
    my $dbh1 = DBI->connect('DBI:Mock:', '', '');
    my $dbh2 = DBI->connect('DBI:Mock:', '', '');
    is(register_dbh('category1', $dbh1), $dbh1, 'register dbh1');
    is(register_dbh('category2', $dbh2), $dbh2, 'register dbh2');
    ok(dbh_is_registered('category1', $dbh1), 'the dbh1 is registered in category1');
    ok(dbh_is_registered('category2', $dbh2), 'the dbh2 is registered in category2');
    local $$ = 1;
    my $dbh3 = DBI->connect('DBI:Mock:', '', '');
    is(register_dbh('category3', $dbh3), $dbh3, 'register dbh3');
    ok(!dbh_is_registered('category1', $dbh1), 'the dbh1 is dropped because pid changed');
    ok(!dbh_is_registered('category2', $dbh2), 'the dbh2 is dropped because pid changed');
    ok(dbh_is_registered('category3', $dbh3), 'dbh3 is still there');
    ok(release_dbh('category3', $dbh3), 'clear dbh');
};

subtest txn => sub {
    # test warn
    my ($dbh1_1, $dbh1_2, $dbh2_1) = init_dbh_for_txn_test();
    my $code = sub {
        return qw(1_1 1_2 2_1);
    };
    $dbh1_1 = undef;
    warnings_like(
        sub {
            txn(sub { $code->() }, 'category1');
        },
        [qr/Had 1 database handles/, qr/unreleased dbh in/],
        "will emit warning if some dbhs are invalid now"
    );

    #test normal case
    clear_dbh_for_txn_test();
    ($dbh1_1, $dbh1_2, $dbh2_1) = init_dbh_for_txn_test();
    $code = sub {
        $dbh1_1->do('select 1_1');
        $dbh1_2->do('select 1_2');
        $dbh2_1->do('select 2_1');
        return wantarray ? qw(1_1 1_2 2_1) : "1";
    };
    my $result;
    warning_is(
        sub {
            $result = txn(sub { $code->() }, 'category1');
        },
        undef,
        'no warning for normal case'
    );
    is($result, '1', 'want scalar will get 1');
    my $history = $dbh1_1->{mock_all_history};
    is(scalar @$history, 3, "3 statement");
    is($history->[0]->statement, 'BEGIN WORK');
    is($history->[1]->statement, 'select 1_1');
    is($history->[2]->statement, 'COMMIT');
    $history = $dbh1_2->{mock_all_history};
    is(scalar @$history, 3, "3 statement");
    is($history->[0]->statement, 'BEGIN WORK');
    is($history->[1]->statement, 'select 1_2');
    is($history->[2]->statement, 'COMMIT');
    $history = $dbh2_1->{mock_all_history};
    is(scalar @$history,         1,            "dbh2_1 is not in category1, so only one statement");
    is($history->[0]->statement, 'select 2_1', 'dbh2_1 no begin_work and commit');

    for my $dbh ($dbh1_1, $dbh1_2, $dbh2_1) {
        $dbh->{mock_clear_history} = 1;
        $dbh->{AutoCommit}         = 1;    # DBD::Mock has an bug. the second dbh cannot reset autocommit after commit. so we reset it by hand
    }

    my @result = txn(sub { $code->() }, 'category1');
    is_deeply(\@result, [qw(1_1 1_2 2_1)], 'wantarray will get a list');

};

sub init_dbh_for_txn_test {
    my $dbh1_1 = DBI->connect('DBI:Mock:', '', '');
    my $dbh1_2 = DBI->connect('DBI:Mock:', '', '');
    my $dbh2_1 = DBI->connect('DBI:Mock:', '', '');
    ok(register_dbh('category1', $dbh1_1));
    ok(register_dbh('category1', $dbh1_2));
    ok(register_dbh('category2', $dbh2_1));
    return ($dbh1_1, $dbh1_2, $dbh2_1);
}

sub clear_dbh_for_txn_test {
    local $$ = 1;
    DBIx::TransactionManager::Distributed::_check_fork();
}

done_testing;

