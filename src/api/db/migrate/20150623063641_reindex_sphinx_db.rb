
class ReindexSphinxDb < ActiveRecord::Migration
  def self.up
    rake = "rake"
    rake = "rake.ruby2.3" if File.exist?("/usr/bin/rake.ruby2.3")
    # we do not use ThinkingSphinx class, since searchd might not be able to startup
    system("cd #{Rails.root}; rm -rf tmp/binlog; exec #{rake} ts:index")
  end

  def self.down
  end
end
