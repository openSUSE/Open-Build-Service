FactoryGirl.define do
  factory :package do
    sequence(:name) { |n| "#{Faker::Internet.domain_word}#{n}" }
    factory :package_with_file do
      after(:create) do |package|
        # Enable global_write_through when creating new or updating existing package factories
        # ensure the backend knows the project
        Suse::Backend.put("/source/#{CGI.escape(package.project.name)}/_meta", package.project.to_axml)
        Suse::Backend.put("/source/#{CGI.escape(package.project.name)}/#{CGI.escape(package.name)}/_meta", package.to_axml)
        Suse::Backend.put("/source/#{CGI.escape(package.project.name)}/#{CGI.escape(package.name)}/somefile.txt", Faker::Lorem.paragraph)
      end
    end
  end
end
