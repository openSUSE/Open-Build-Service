class NewSuseBugzillas < ActiveRecord::Migration
  def up
    t = IssueTracker.find_by_name('bnc')
    t ||= IssueTracker.find_by_name('boo')
    t.regex = '(?:bnc|BNC|bsc|BSC|boo|BOO)\s*[#:]\s*(\d+)'
    t.name = "bnc"
    t.description = "openSUSE Bugzilla"
    t.url = "https://bugzilla.opensuse.org/"
    t.label = "boo#@@@"
    t.show_url = "https://bugzilla.opensuse.org/show_bug.cgi?id=@@@"
    t.save!
    Delayed::Worker.delay_jobs = true
    IssueTracker.write_to_backend
  end

  def down
    t = IssueTracker.find_by_name('bnc')
    t ||= IssueTracker.find_by_name('boo')
    t.regex = '(?:bnc|BNC)\s*[#:]\s*(\d+)'
    t.name = "bnc"
    t.description = "Novell Bugzilla"
    t.url = "https://bugzilla.novell.com/"
    t.label = "bnc#@@@"
    t.show_url = "https://bugzilla.novell.com/show_bug.cgi?id=@@@"
    t.save!
    Delayed::Worker.delay_jobs = true
    IssueTracker.write_to_backend
  end
end
