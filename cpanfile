requires 'Exporter';
requires 'Scalar::Util';
requires 'List::UtilsBy';

on configure => sub {
    requires 'ExtUtils::MakeMaker', '>= 6.48';
};

on build => sub {
    requires 'perl', '5.010000';
};

on test => sub {
    requires 'Test::More', '>= 0.98';
    requires 'DBI', '>= 1.632';
    requires 'DBD::Mock', '>= 1.45';
    requires 'Devel::Refcount', '>= 0.10';
    requires 'Test::Fatal', '>= 0.014';
    requires 'Test::Warnings', '>= 0.026';
    requires 'Test::Deep', '>= 0.113';
    requires 'Test::Refcount', '>= 0.08';
};

on develop => sub {
    requires 'Devel::Cover::Report::Codecov', '>= 0.14';
};
