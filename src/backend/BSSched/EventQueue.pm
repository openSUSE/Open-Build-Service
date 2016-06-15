# Copyright (c) 2015 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program (see the file COPYING); if not, write to the
# Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA
#

package BSSched::EventQueue;

use strict;
use warnings;

use Data::Dumper;

use BSUtil;
use BSSched::BuildRepo;
use BSSched::ProjPacks;
use BSSched::EventHandler;

=head1 NAME

 BSSched::EventQueue;

=head1 DESCRIPTION

 scheduler event queue handling

=head1 SYNOPSIS

  my $gctx = {
    rctx => BSSched::RPC->new();
  };

  my $ev_queue     = BSSched::EventQueue->new($gctx,@opts);

  my $total_events = $ev_queue->add_events(@new_events);

  my $gotevents    = $ev_queue->process_events();

=head1 METHODS

=cut

#
# EVENT QUEUE HANDLING
#

=head2 new - generate an event queue

  Parameters:

    $gctx - global context (must contain rctx)

    @opts - list of optional parameters

  Returns:

    BSSched::EventQueue object

  Example:

    my $ev_queue = BSSched::EventQueue->new($gctx,@opts);

=cut

sub new {
  my ($class, $gctx, @conf) = @_;
  my $ectx = {
    'gctx' => $gctx,
    'fetchprojpacks'          => {},
    'fetchprojpacks_nodelay'  => {},
    'deepcheck'               => {},
    'lowprioproject'          => {},
    'fullcache'               => undef,
    '_events'                 => [],
    @conf
  };
  return bless $ectx, $class;
}

=head2 process_events - process a list of events

  Parameters:

    none

  Returns:

    $gotevent - Boolean which indicates if events left to be executed

  Example:

    my $got_events = BSSched::EventQueue->process_events();


=cut

sub process_events {
  my ($ectx) = @_;

  my $gotevent = 0;
  my $gctx = $ectx->{'gctx'};

  $ectx->order() if @{$ectx->{_events}};

  while (@{$ectx->{_events}}) {
    my $ev = shift @{$ectx->{_events}};
    $ev->{'type'} ||= 'unknown';

    # have to be extra careful with uploadbuild/import events. if the package is in
    # (delayed)fetchprojpacks, delay event processing until we updated the projpack data.
    if ($ev->{'type'} eq 'uploadbuild' || $ev->{'type'} eq 'import') {
      if (BSSched::EventHandler::event_uploadbuildimport_delay($ectx, $ev)) {
	$gotevent = 1;    # still have an event to process
	next;
      }
    }

    # log event info
    if ($ev->{'type'} ne 'built') {
      my $estr = $ev->{'evfilename'} ? 'event' : 'remote event';
      for (qw{type project repository arch package}) {
	$estr .= " $ev->{$_}" if $ev->{$_};
      }
      print "$estr\n";
    }

    unlink($ev->{'evfilename'}) if $ev->{'evfilename'};
    delete $ev->{'evfilename'};

    if ($ev->{'type'} ne 'built' && $ectx->{'fullcache'}) {
      BSSched::BuildRepo::sync_fullcache($gctx, $ectx->{'fullcache'});
      $ectx->{'fullcache'} = undef;
    }
    if ($ev->{'type'} eq 'built' && !$ectx->{'fullcache'}) {
      # turn on fullcache if the next event is also of type built
      $ectx->{'fullcache'} = {} if $ectx->{_events}->[0] && $ectx->{_events}->[0]->{'type'} eq 'built';
    }
    $ectx->process_one($ev);
  }

  BSSched::BuildRepo::sync_fullcache($gctx, $ectx->{'fullcache'}) if $ectx->{'fullcache'} && $ectx->{'fullcache'}->{'prp'};
  $ectx->{'fullcache'} = undef;

  # postprocess
  if (%{$ectx->{'fetchprojpacks'}}) {
    BSSched::ProjPacks::do_fetchprojpacks($gctx,
					  $ectx->{'fetchprojpacks'}, $ectx->{'fetchprojpacks_nodelay'},
					  $ectx->{'deepcheck'}, $ectx->{'lowprioproject'});
  }

  $ectx->{'fetchprojpacks'} = {};
  $ectx->{'fetchprojpacks_nodelay'} = {};
  $ectx->{'deepcheck'} = {};
  $ectx->{'lowprioproject'} = {};

  return $gotevent;
}

=head2 process_one - process a single event

  Parameters:

    $ev - Event as an HashRef

  Returns:

    unknown

  Example:

    BSSched::EventQueue->process_one($ev);

  Description:

    mostly for internal use - should not be used directly

=cut

sub process_one {
  my ($ectx, $ev) = @_;
  my $type = $ev->{'type'} || 'unknown';
  if ($ectx->{'initialstartup'} && ($type eq 'exit' || $type eq 'exitcomplete')) {
    print "WARNING: there was an exit event, but we ignore it directly after starting the scheduler.\n";
    return;
  }
  my $evhandler = $BSSched::EventHandler::event_handlers{$type};
  if ($evhandler) {
    $evhandler->($ectx, $ev);
  } else {
    print "unknown event type '$type'\n";
  }
}

=head2 order - order events so that the important ones come first

  Parameters:

    none

  Returns:

    0

  Example:

    BSSched::EventQueue->order();

  Description:

    mostly for internal use - should not be used directly

=cut

sub order {
  my ($ectx) = @_;

  if (@{$ectx->{_events}} > 1) {
    # sort events a bit, exit events go first ;-)
    # uploadbuild/import events must go last
    my %evprio = ('exit' => -2, 'exitcomplete' => -2, 'restart' => -2, 'suspendproject' => -1, 'uploadbuild' => 1, 'import' => 1);
    @{$ectx->{_events}} = sort {
                    # the following lines might look a bit nasty, but this is needed to avoid
                    # "Uninitialized values" warings
                    ($evprio{$a->{'type'} || ''} || 0) <=> ($evprio{$b->{'type'} || ''} || 0) ||
                    ($a->{'type'} || '' )  cmp ($b->{'type'} || '') ||
                    ($a->{'project'} || '') cmp ($b->{'project'} || '') ||
                    ($a->{'job'} || '') cmp ($b->{'job'} || '')
                    } @{$ectx->{_events}} ;
  }
  return 0;
}

=head2 add_events - add a list of events to event queue

  Parameters:

    @new_events - list of events to be added

  Returns:

    Total count of new events

  Example:

    my $total_events = BSSched::EventQueue->add_events(@new_events);

=cut


sub add_events {
  my $self = shift;
  push @{$self->{_events}}, @_;
}

=head2 get_events - get list of actual events

  Parameters:

    none

  Returns:

    ArrayRef to event queue

  Example:

    my $events = BSSched::EventQueue->get_events();

=cut

sub get_events {
  return $_[0]->{_events};
}

=head2 events_in_queue - get counter of events in queue

  Parameters:

    none

  Returns:

    Number of elements in queue

  Example:

    my $count = BSSched::EventQueue->events_in_queue();

=cut

sub events_in_queue {
   return scalar(@{$_[0]->{_events}});
}

1;
