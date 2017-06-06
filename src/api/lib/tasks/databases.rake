module Rake
  module TaskManager
    def redefine_task(task_class, *args, &block)
      task_name, deps = resolve_args(args)
      task_name = task_class.scope_name(@scope, task_name)
      deps = [deps] unless deps.respond_to?(:to_ary)
      deps = deps.collect(&:to_s)
      task = @tasks[task_name.to_s] = task_class.new(task_name, self)
      task.application = self
      # task.add_comment(@last_comment)
      @last_comment = nil
      task.enhance(deps, &block)
      task
    end
  end
  class Task
    class << self
      def redefine_task(args, &block)
        Rake.application.redefine_task(self, args, &block)
      end
    end
  end
end

def redefine_task(args, &block)
  Rake::Task.redefine_task(args, &block)
end

namespace :db do
  namespace :structure do
    desc "Dump the database structure to a SQL file"
    task dump: :environment do
      path = Rails.root.join('db', 'structure.sql')
      File.write(path, File.read(path).gsub(/ AUTO_INCREMENT=\d*/, ''))
    end
  end

  desc 'Create the database, load the structure, and initialize with the seed data'
  redefine_task setup: :environment do
    Rake::Task["db:structure:load"].invoke
    Rake::Task["db:seed"].invoke
  end
end
