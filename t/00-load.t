#!perl -T
use 5.006;
use strict;
use warnings;
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'DBIx::TransactionManager::Distributed' ) || print "Bail out!\n";
}

diag( "Testing DBIx::TransactionManager::Distributed $DBIx::TransactionManager::Distributed::VERSION, Perl $], $^X" );
