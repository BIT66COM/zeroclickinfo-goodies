package DDG::GoodieRole::NumberStyle;

use strict;
use warnings;

use Moo;

has [qw(id decimal thousands exponential)] => (
    is => 'ro',
);

has number_regex => (
    is => 'lazy',
);

sub _build_number_regex {
    my $self = shift;
    my ($decimal, $thousands, $exponential) = ($self->decimal, $self->thousands, $self->exponential);

    return qr/[\d\Q$decimal\E\Q$thousands\E]+(?:\Q$exponential\E\d+)?/;
}

sub understands {
    my ($self, $number) = @_;
    my ($decimal, $thousands) = ($self->decimal, $self->thousands);

    # How do we know if a number is reasonable for this style?
    # This assumes the exponentials are not included to give better answers.
    return (
        # The number must contain only things we understand: numerals and separators for this style.
        $number =~ /^(\d|\Q$thousands\E|\Q$decimal\E)+$/
          && (
            # The number is not required to contain thousands separators
            $number !~ /\Q$thousands\E/
            || (
                # But if the number does contain thousands separators, they must delimit exactly 3 numerals.
                $number !~ /\Q$thousands\E\d{1,2}\b/
                && $number !~ /\Q$thousands\E\d{4,}/
                # And cannot follow a leading zero
                && $number !~ /^0\Q$thousands\E/
            ))
          && (
            # The number is not required to include decimal separators
            $number !~ /\Q$decimal\E/
            # But if one is included, it cannot be followed by another separator, whether decimal or thousands.
            || $number !~ /\Q$decimal\E(?:.*)?(?:\Q$decimal\E|\Q$thousands\E)/
          )) ? 1 : 0;
}

sub precision_of {
    my ($self, $number_text) = @_;
    my $decimal = $self->decimal;

    return ($number_text =~ /\Q$decimal\E(\d+)/) ? length($1) : 0;
}

sub for_computation {
    my ($self, $number_text) = @_;
    my ($decimal, $thousands, $exponential) = ($self->decimal, $self->thousands, $self->exponential);

    $number_text =~ s/\Q$thousands\E//g;    # Remove thousands seps, since they are just visual.
    $number_text =~ s/\Q$decimal\E/./g;     # Make sure decimal mark is something perl knows how to use.
    if ($number_text =~ s/^([\d$decimal$thousands]+)\Q$exponential\E([\d$decimal$thousands]+)$/$1e$2/ig) {
        # Convert to perl style exponentials and then make into human-style floats.
        $number_text = sprintf('%f', $number_text);
    }

    return $number_text;
}

sub for_display {
    my ($self, $number_text) = @_;
    my ($decimal, $thousands, $exponential) = ($self->decimal, $self->thousands, $self->exponential);

    if ($number_text =~ /(.*)\Q$exponential\E([+-]?\d+)/i) {
        $number_text = $self->for_display($1) . ' * 10^' . $self->for_display(int $2);
    } else {
        $number_text = reverse $number_text;
        $number_text =~ s/\./$decimal/g;    # Perl decimal mark to whatever we need.
        $number_text =~ s/(\d\d\d)(?=\d)(?!\d*\Q$decimal\E)/$1$thousands/g;
        $number_text = reverse $number_text;
    }

    return $number_text;
}

sub with_html {
    my ($self, $number_text) = @_;

    return $self->_add_html_exponents($self->for_display($number_text));
}

sub _add_html_exponents {

    my ($self, $string) = @_;

    return $string if ($string !~ /\^/ or $string =~ /^\^|\^$/);    # Give back the same thing if we won't deal with it properly.

    my @chars = split //, $string;
    my $number_re = $self->number_regex;
    my ($start_tag, $end_tag) = ('<sup>', '</sup>');
    my ($newly_up, $in_exp_number, $in_exp_parens, %power_parens);
    my ($parens_count, $number_up) = (0, 0);

    # because of associativity and power-to-power, we need to scan nearly the whole thing
    for my $index (1 .. $#chars - 1) {
        my $this_char = $chars[$index];
        if ($this_char =~ $number_re) {
            if ($newly_up) {
                $in_exp_number = 1;
                $newly_up      = 0;
            }
        } elsif ($this_char eq '(') {
            $parens_count += 1;
            $in_exp_number = 0;
            if ($newly_up) {
                $in_exp_parens += 1;
                $power_parens{$parens_count} = 1;
                $newly_up = 0;
            }
        } elsif ($this_char eq '^') {
            $chars[$index - 1] =~ s/$end_tag$//;    # Added too soon!
            $number_up += 1;
            $newly_up      = 1;
            $chars[$index] = $start_tag;            # Replace ^ with the tag.
        } elsif ($in_exp_number) {
            $in_exp_number = 0;
            $number_up -= 1;
            $chars[$index] = $end_tag . $chars[$index];
        } elsif ($number_up && !$in_exp_parens) {
            # Must have ended another term or more
            $chars[$index] = ($end_tag x ($number_up - 1)) . $chars[$index];
            $number_up = 0;
        } elsif ($this_char eq ')') {
            # We just closed a set of parens, see if it closes one of our things
            if ($in_exp_parens && $power_parens{$parens_count}) {
                $chars[$index] .= $end_tag;
                delete $power_parens{$parens_count};
                $in_exp_parens -= 1;
            }
            $parens_count -= 1;
        }
    }
    $chars[-1] .= $end_tag x $number_up if ($number_up);

    return join('', @chars);
}

1;
