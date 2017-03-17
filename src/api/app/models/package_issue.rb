class PackageIssue < ApplicationRecord
  belongs_to :package
  belongs_to :issue

  scope :open_issues_of_owner, -> (owner_id) { joins(:issue).where(issues: { state: 'OPEN', owner_id: owner_id})}
  scope :with_patchinfo, lambda {
    joins('LEFT JOIN package_kinds ON package_kinds.package_id = package_issues.package_id').where('package_kinds.kind = "patchinfo"')
  }

  def self.sync_relations(package, issues)
    retries = 10
    begin
      PackageIssue.transaction do
        allissues = []
        issues.map{|h| allissues += h.last}

        # drop not anymore existing relations
        PackageIssue.where("package_id = ? AND NOT issue_id IN (?)", package, allissues).lock(true).delete_all

        # create missing in an efficient way
        sql = ApplicationRecord.connection
        (allissues - package.issues.to_ary).each do |i|
          sql.execute("INSERT INTO `package_issues` (`package_id`, `issue_id`) VALUES (#{package.id},#{i.id})")
        end

        # set change value for all
        issues.each do |pair|
          PackageIssue.where(package: package, issue: pair.last).lock(true).update_all(change: pair.first)
        end
      end
    rescue ActiveRecord::StatementInvalid, Mysql2::Error
      retries -= 1
      retry if retries > 0
    end
  end
end

