# -*- coding: utf-8 -*-
require 'nyan_cat_formatter'

# Overwritting nyan-cat-formatter class to remove warning '::Fixnum is deprecated'
class RSpec3
  def start(notification)
    # TODO: Lazy fix for specs.
    if notification.kind_of?(Integer)
      super(OpenStruct.new(count: notification))
    else
      super(notification)
    end

    @current = @color_index = @passing_count = @failure_count = @pending_count = 0
    @example_results = []
    @failed_examples = []
    @pending_examples = []
  end

  def example_started(notification)
    if notification.respond_to?(:example)
      notification = notification.example
    end
    @example_name = notification.full_description
  end
end

class NyanUnicornFormatter < NyanCatFormatter
  RSpec::Core::Formatters.register self, :example_started, :example_passed, :example_pending, :example_failed, :start_dump, :start

  # Determine which Ascii Nyan Cat to display. If tests are complete,
  # Nyan Cat goes to sleep. If there are failing or pending examples,
  # Nyan Cat is concerned.
  #
  # @return [String] Nyan Cat
  def nyan_cat
    if failed_or_pending? && finished?
      ascii_cat('x')[@color_index % 2].join("\n")
    elsif failed_or_pending?
      ascii_cat('o')[@color_index % 2].join("\n")
    elsif finished?
      ascii_cat('-')[@color_index % 2].join("\n")
    else
      ascii_cat('·')[@color_index % 2].join("\n")
    end
  end

  def progress_lines
    last_length = 1
    [
      nyan_trail.split("\n").each_with_index.inject([]) do |result, (trail, index)|
        last_length = format("%s", "#{scoreboard[index]}/#{@example_count}:").length unless scoreboard[index].nil?
        value = scoreboard[index].nil? ? ' ' * (last_length / 2) : "#{scoreboard[index]}/#{@example_count}:"
        result << format("%s %s", value, trail)
      end
    ].flatten
  end

  # Ascii version of Nyan cat. Two cats in the array allow Nyan to animate running.
  #
  # @param o [String] Nyan's eye
  # @return [Array] Nyan cats
  def ascii_cat(o = '.')
    [
      [
        'OBS·         / ',
        "*·*       sS#{o}\\ ",
        '   .--,__sS/\,)',
        ' S(  /_ \  )   ',
        'Ss ||    ||    ',
        "   ''    ''    "
      ],
      [
        'OBS*         / ',
        "·*·       sS#{o}\\ ",
        '   .--,__sS/\,)',
        ' S(  /_ \  )   ',
        'Ss \\\\    \\\\    ',
        "    ''    ''   "
      ]
    ]
  end
end
