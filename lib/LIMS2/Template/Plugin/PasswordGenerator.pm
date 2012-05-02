package LIMS2::Template::Plugin::PasswordGenerator;

use strict;
use warnings FATAL => 'all';

use base qw( Template::Plugin Class::Data::Inheritable );

__PACKAGE__->mk_classdata( PW_CHARS => [ "A".."Z", "a".."z", "0".."9" ] );
__PACKAGE__->mk_classdata( PW_LEN => 12 );

sub generate_password {
    my ( $class, $pw_len ) = @_;

    $pw_len ||= $class->PW_LEN;    

    my $pw_chars = $class->PW_CHARS;
    
    join '', map { $pw_chars->[ int rand @{$pw_chars} ] } 1..$pw_len;
}

1;
