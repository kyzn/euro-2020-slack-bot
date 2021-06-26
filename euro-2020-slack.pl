use warnings;
use strict;

=head1 NAME

euro-2020-slack v0.03

=cut

package Euro2020Slack;
our $VERSION = '0.03';

use DDP;
use File::Slurper qw/read_text write_text/;
use Furl;
use Getopt::Long;
use JSON::XS;
use Test::Deep::NoTest;

=head1 DESCRIPTION

Downloads EURO 2020 live game status from football-data.org & posts to Slack.

You can install system dependencies on a ubuntu flavored OS like below.

    apt-get update
    apt install make cpanminus gcc libssl-dev zlib1g-dev

Once you have cpanm, run following to install perl dependencies.

    cpanm --installdeps .

=head1 SYNOPSIS


First, you will need a Football-Data.org token.

=over

=item Go to L<https://www.football-data.org/client/register> and register

=item You will get an email titled "Your free API-key for football-data.org"

=item Copy the token, keep it safe

=back

Then, you will need a Slack incoming webhook URL. Here's how to get it:

=over

=item Create an app at L<https://api.slack.com/apps?new_app=1>

=item Choose "From Scratch" if asked

=item Below "Add features and functionality", click "Incoming webhooks"

=item Turn on "Activate Incoming Webhooks"

=item Click "Add New Webhook to Workspace" down below

=item Choose the channel you want the bot to interact with

=item Copy webhook URL, take a note. Don't share this with other people.

=item Go to your app details page at L<https://api.slack.com>

=item Go to "Incoming webhooks" on left navigation, it will be there.

=back

Post to slack incoming webhook URL.

  perl euro-2020-slack.pl --token=.. --slack=https://hooks.slack.com/services/..

Increase politeness sleep for outgoing HTTP requests (defaults to 2 seconds)

  perl euro-2020-slack.pl --token=.. --slack=.. --sleep=10

Change delay (in minutes) to post to slack (put 0 for no delay. defaults to 3 mins)

  perl euro-2020-slack.pl --token=.. --slack=.. --delay=1

Specify multiple Slack URLs to post to multiple workspaces

  perl euro-2020-slack.pl --token=.. --slack=... --slack=...

Specify name and location of db.json file. This may be
helpful if you are running multiple instances of script.

  perl euro-2020-slack.pl --token=.. --slack=... --dbjson=some/file.json

Do a dry run: Don't post to slack, don't write to db.json

  perl euro-2020-slack.pl --token=... --dry

=head1 CONTRIBUTING

PRs are welcome, but you are encouraged to discuss it in issues first.
Please don't edit this README directly, it's auto generated with commands below.

    cpanm Pod::Markdown
    echo -e '![A sample run](sample.png)\n\n' > README.md && pod2markdown euro-2020-slack.pl >> README.md

=head1 LICENSE

MIT.

This script talks to L<football-data.org|https://www.football-data.org/>,
please check their terms for your use case.

=head1 ATTRIBUTION

This script is partly based on
L<j0k3r/worldcup-slack-bot|https://github.com/j0k3r/worldcup-slack-bot>
which was written in PHP.

Football data provided by the Football-Data.org API.

=cut

my @slack = ();
my $sleep = 2;
my $delay = 3;
my $token;
my $dbjson_filename = './db.json';
my $dry = 0;

GetOptions(
  'slack=s'  => \@slack,
  'token=s'  => \$token,
  'sleep=i'  => \$sleep,
  'delay=i'  => \$delay,
  'dbjson=s' => \$dbjson_filename,
  'dry'      => \$dry
) or die 'Encountered an error when parsing arguments';
die 'You have to specify your football-data.org API token via --token' unless $token;
die 'You have to specify at least one slack address via --slack' unless @slack or $dry;
die 'Delay has to be a non-negative integer' if $delay < 0;

# See all competitions at https://api.football-data.org/v2/competitions
my $competition_id = 2018; # EURO 2020
my $flag_of = {
  "Austria"         => ":flag-at:",
  "Belgium"         => ":flag-be:",
  "Croatia"         => ":flag-hr:",
  "Czech Republic"  => ":flag-cz:",
  "Denmark"         => ":flag-dk:",
  "England"         => ":flag-england:",
  "Finland"         => ":flag-fi:",
  "France"          => ":flag-fr:",
  "Germany"         => ":flag-de:",
  "Hungary"         => ":flag-hu:",
  "Italy"           => ":flag-it:",
  "Netherlands"     => ":flag-nl:",
  "North Macedonia" => ":flag-mk:",
  "Poland"          => ":flag-pl:",
  "Portugal"        => ":flag-pt:",
  "Russia"          => ":flag-ru:",
  "Scotland"        => ":flag-scotland:",
  "Slovakia"        => ":flag-sk:",
  "Spain"           => ":flag-es:",
  "Sweden"          => ":flag-se:",
  "Switzerland"     => ":flag-ch:",
  "Turkey"          => ":flag-tr:",
  "Ukraine"         => ":flag-ua:",
  "Wales"           => ":flag-wales:"
};

my $furl = Furl->new;

# "DB" is the local object read from db.json. It has structure:
# {
#   latest    => [ ... ], # matches array from API, from previous call
#   scheduled => {        # meaning "scheduled to be posted, don't schedule it again"
#     1234      => {         # match.id
#       kickoff         => 1,  # other events: start_of_et1, start_of_et2
#       end_of_first    => 1,  # end_of_90, end_of_et1, end_of_et2
#       start_of_second => 1,  # finished postponed canceled (match.status)
#       ...
#     },
#     2345 => {..}           # there can be multiple matches tracked
#   },
#   queue     => [        # May be out of order, esp. if delay parameter is tweaked
#     {
#       post_on_or_after => 1623650171, # epoch time (see `perldoc -f time`)
#       title            => "Flag Home - Away Flag",
#       subtitle         => "Kickoff"
#     },
#     { ... }             # There can be multiple tweets in queue
#   ]
# }
my $db = {};
if (-e $dbjson_filename){
  my $db_json = read_text($dbjson_filename);
  my $db_hash = eval { decode_json($db_json) };
  die 'Could not decode existing db.json' unless $db_hash;
  $db = $db_hash // +{};
}

# "LIVE" is the API call results that are just made.
# Not written to DB yet, but will be before exiting.
my $live = download_live_games();

LIVE: foreach my $live_match (@$live){
  my $title = make_title($live_match);
  DB: foreach my $db_match (@{$db->{latest}}){

    if ($db_match->{id} == $live_match->{id}){
      # Game exists in both db and live. Check for diff.

      if ($live_match->{status} ne $db_match->{status}){
        # Status has changed. What's the new status?

        if ($live_match->{status} eq "PAUSED"){
          if (!$db->{scheduled}->{$live_match->{id}}->{end_of_first}){
            schedule_post($title, "End of first half");
            $db->{scheduled}->{$live_match->{id}}->{end_of_first} = 1;
            next LIVE;
          }
          elsif (
            $db->{scheduled}->{$live_match->{id}}->{start_of_et1} &&
            !$db->{scheduled}->{$live_match->{id}}->{start_of_et2} &&
            !$db->{scheduled}->{$live_match->{id}}->{end_of_et1}
          ){
            schedule_post($title, "End of first period of extra time");
            $db->{scheduled}->{$live_match->{id}}->{end_of_et1} = 1;
            next LIVE;
          }
          elsif (
            $db->{scheduled}->{$live_match->{id}}->{start_of_et2} &&
            !$db->{scheduled}->{$live_match->{id}}->{end_of_et2}
          ){
            schedule_post($title, "End of second period of extra time");
            $db->{scheduled}->{$live_match->{id}}->{end_of_et2} = 1;
            next LIVE;
          }
        }

        elsif ($live_match->{status} eq "IN_PLAY"){
          if ($live_match->{score}->{duration} eq 'REGULAR'){
            if (!$db->{scheduled}->{$live_match->{id}}->{start_of_second}){
              schedule_post($title, "Second half begins");
              $db->{scheduled}->{$live_match->{id}}->{start_of_second} = 1;
              next LIVE;
            }
          }
          elsif ($live_match->{score}->{duration} eq 'EXTRA_TIME'){
            if (!$db->{scheduled}->{$live_match->{id}}->{start_of_et1}){
              schedule_post($title, "First period of extra time begins");
              $db->{scheduled}->{$live_match->{id}}->{start_of_et1} = 1;
              next LIVE;
            }
            elsif (!$db->{scheduled}->{$live_match->{id}}->{start_of_et2}){
              schedule_post($title, "Second period of extra time begins");
              $db->{scheduled}->{$live_match->{id}}->{start_of_et2} = 1;
              next LIVE;
            }
          }
          elsif ($live_match->{score}->{duration} eq 'PENALTY_SHOOTOUT'){
            if (!$db->{scheduled}->{$live_match->{id}}->{start_of_pk}){
              schedule_post($title, "Penalty shootout begins");
              $db->{scheduled}->{$live_match->{id}}->{start_of_pk} = 1;
              next LIVE;
            }
          }
        }
      }
      elsif (!eq_deeply($live_match->{score}, $db_match->{score})){
        # Score has changed
        my $subtitle = make_subtitle($live_match, $db_match);
        schedule_post($title, $subtitle);
        next LIVE;
      }

      # No change, move on
      next LIVE;

    }
  }

  # Game exists in live but not in db: Just started
  if (!$db->{scheduled}->{$live_match->{id}}->{kickoff}){
    my $stage = $live_match->{stage};
    $stage =~ s/_/ /g;
    $stage = ucfirst lc $stage;
    my $group = $live_match->{group};
    my $matchday = $live_match->{matchday};
    my $title_no_score = make_title($live_match, 1);
    my $subtitle = "Kickoff - " . ($group && $matchday ? "$group Matchday $matchday" : "$stage");
    schedule_post($title_no_score, $subtitle);
    $db->{scheduled}->{$live_match->{id}}->{kickoff} = 1;
  }
}

DB: foreach my $db_match (@{$db->{latest}}){
  LIVE: foreach my $live_match (@$live){
    if ($db_match->{id} == $live_match->{id}){
      next DB;
    }
  }

  # Game exists in db, but not in live: Game finished (or postponed, canceled)
  my $finished_match = download_single_game($db_match->{id});
  my $status = lc $finished_match->{status};
  if (!$db->{scheduled}->{$finished_match->{id}}->{$status}){
    my $title = make_title($finished_match);
    my $subtitle = "Game $status";
    schedule_post($title, $subtitle);
    $db->{scheduled}->{$finished_match->{id}}->{$status} = 1;
  }
}

# Now that we processed new events, let's go through the post queue
foreach my $item (@{$db->{queue}}){
  if ($item->{post_on_or_after} <= time()){
    post_to_slack($item->{title}, $item->{subtitle});
    $item->{posted} = 1;
  }
}
@{$db->{queue}} = grep {!$_->{posted}} @{$db->{queue}};

# Save db.json before finishing up
$db->{latest} = $live;
if ($dry){
  print np $db; print "\n\n";
}
else {
  write_text($dbjson_filename, encode_json($db));
}

# Helper subroutine to make title
sub make_title {
  my $match = shift;
  my $hide_score = shift;

  my $home_name = $match->{homeTeam}->{name};
  my $away_name = $match->{awayTeam}->{name};

  my $home_flag = $flag_of->{$home_name};
  my $away_flag = $flag_of->{$away_name};

  my $home_score = $match->{score}->{fullTime}->{homeTeam};
  my $away_score = $match->{score}->{fullTime}->{awayTeam};

  my $home_pk = $match->{score}->{penalties}->{homeTeam};
  my $away_pk = $match->{score}->{penalties}->{awayTeam};
  my $score;

  if ($hide_score) {
    $score = "-";
  }
  else {
    if (defined $home_pk){
      $score = "$home_score ($home_pk) - ($away_pk) $away_score";
    }
    else {
      $score = "$home_score - $away_score";
    }
  }

  return "$home_flag $home_name $score $away_name $away_flag";
}

# Helper subroutine to make subtitle
sub make_subtitle {
  my $live_match = shift;
  my $db_match = shift;

  my $home_name = $live_match->{homeTeam}->{name};
  my $away_name = $live_match->{awayTeam}->{name};

  my $home_live_score = $live_match->{score}->{fullTime}->{homeTeam};
  my $away_live_score = $live_match->{score}->{fullTime}->{awayTeam};
  my $home_db_score   = $db_match->{score}->{fullTime}->{homeTeam};
  my $away_db_score   = $db_match->{score}->{fullTime}->{awayTeam};

  my $home_live_pk = $live_match->{score}->{penalties}->{homeTeam};
  my $away_live_pk = $live_match->{score}->{penalties}->{awayTeam};
  my $home_db_pk   = $db_match->{score}->{penalties}->{homeTeam};
  my $away_db_pk   = $db_match->{score}->{penalties}->{awayTeam};

  if (defined $home_live_pk){
    # PKs ongoing
    if ($home_live_pk == $home_db_pk){
      if ($away_live_pk == $away_db_pk + 1){
        return ":soccer: $away_name scored!";
      }
      elsif ($away_live_pk == $away_db_pk - 1){
        return ":x: $away_name goal disallowed!!";
      }
    }
    elsif ($away_live_pk == $away_db_pk){
      if ($home_live_pk == $home_db_pk + 1){
        return ":soccer: $home_name scored!";
      }
      elsif ($home_live_pk == $home_db_pk - 1){
        return ":x: $home_name goal disallowed!!";
      }
    }
  }
  else {
    if ($home_live_score == $home_db_score){
      if ($away_live_score == $away_db_score + 1){
        return ":soccer: $away_name scored!";
      }
      elsif ($away_live_score == $away_db_score - 1){
        return ":x: $away_name goal disallowed!!";
      }
    }
    elsif ($away_live_score == $away_db_score){
      if ($home_live_score == $home_db_score + 1){
        return ":soccer: $home_name scored!";
      }
      elsif ($home_live_score == $home_db_score - 1){
        return ":x: $home_name goal disallowed!!";
      }
    }
  }

  return "";
}

# Helper subroutine to download live games
sub download_live_games {
  my $response = $furl->get(
    "http://api.football-data.org/v2/competitions/$competition_id/matches?status=LIVE",
    ["X-Auth-Token", $token]
  );
  die 'Error encountered when downloading live games' unless $response->is_success;
  sleep $sleep;

  my $content = $response->content;
  my $json    = eval { decode_json($content) };
  die 'Error encountered when parsing response' unless $json;

  # This is going to be an empty array if there's no live games
  return $json->{matches};
}

# Helper subroutine to download single game
sub download_single_game {
  my $match_id = shift;
  my $response = $furl->get(
    "http://api.football-data.org/v2/matches/$match_id",
    ["X-Auth-Token", $token]
  );
  die 'Error encountered when downloading live game' unless $response->is_success;
  sleep $sleep;

  my $content = $response->content;
  my $json    = eval { decode_json($content) };
  die 'Error encountered when parsing response' unless $json;

  return $json->{match};
}

sub schedule_post {
  my ($title, $subtitle) = @_;
  my $post = {
    post_on_or_after => time() + 60 * $delay - 1,
    title            => $title,
    subtitle         => $subtitle,
  };
  push @{$db->{queue}}, $post;
}

# Helper subroutine to post to slack
sub post_to_slack {
  my ($title, $subtitle) = @_;

  if ($dry){
    print '-'x30;
    print "\n$title\n$subtitle\n";
  } else {
    my $post_text = "*$title*" . ($subtitle ? "\n> $subtitle" : "");
    foreach my $url (@slack){
      $furl->post(
        $url,
        ["Content-type" => "application/json"],
        encode_json {"text" => $post_text},
      );
    }
  }
}
