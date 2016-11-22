FactoryGirl.define do
  factory :package do
    project
    sequence(:name) { |n| "package_#{n}" }

    after(:create) do |package|
      # NOTE: Enable global write through when writing new VCR cassetes.
      # ensure the backend knows the project
      if CONFIG['global_write_through']
        Suse::Backend.put("/source/#{CGI.escape(package.project.name)}/#{CGI.escape(package.name)}/_meta", package.to_axml)
      end
    end

    factory :package_with_file do
      after(:create) do |package|
        # NOTE: Enable global write through when writing new VCR cassetes.
        # ensure the backend knows the project
        if CONFIG['global_write_through']
          Suse::Backend.put("/source/#{CGI.escape(package.project.name)}/#{CGI.escape(package.name)}/_config", Faker::Lorem.paragraph)
          Suse::Backend.put("/source/#{CGI.escape(package.project.name)}/#{CGI.escape(package.name)}/somefile.txt", Faker::Lorem.paragraph)
        end
      end
    end

    factory :package_with_service do
      after(:create) do |package|
        # NOTE: Enable global write through when writing new VCR cassetes.
        # ensure the backend knows the project
        if CONFIG['global_write_through']
          Suse::Backend.put("/source/#{URI.escape(package.project.name)}/#{URI.escape(package.name)}/_service", '<service/>')
        end
      end
    end

    factory :package_with_failed_comment_attribute do
      after(:create) do |package|
        create(:project_status_package_fail_comment_attrib, package: package)
      end
    end
  end
end
