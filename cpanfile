requires 'Exporter';
requires 'Scalar::Util';
requires 'List::UtilsBy';

on configure => sub {
    requires 'ExtUtils::MakeMaker', '6.48';
};

on build => sub {
    requires 'perl', '5.010000';
};

on test => sub {
    requires 'Test::More', '0.94';
};

on develop => sub {
    requires 'Test::More', '0.88';
};
