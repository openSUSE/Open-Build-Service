Capybara.default_max_wait_time = 6
Capybara.save_and_open_page_path = Rails.root.join('tmp', 'capybara')

Capybara.register_driver :poltergeist do |app|
  Capybara::Poltergeist::Driver.new(app, debug: false, timeout: 30)
end

Capybara.register_driver :rack_test do |app|
  Capybara::RackTest::Driver.new(app, headers: {'HTTP_ACCEPT' => 'text/html'})
end

Capybara.javascript_driver = :poltergeist

# Automatically save the page a test fails
RSpec.configure do |config|
  config.after(:each, type: :feature) do
    example_filename = RSpec.current_example.full_description
    example_filename = example_filename.tr(' ', '_')
    example_filename = example_filename + '.html'
    example_filename = File.expand_path(example_filename, Capybara.save_and_open_page_path)
    if RSpec.current_example.exception.present?
      save_page(example_filename)
    else
      # remove the file if the test starts working again
      File.unlink(example_filename) if File.exist?(example_filename)
    end
  end
end
