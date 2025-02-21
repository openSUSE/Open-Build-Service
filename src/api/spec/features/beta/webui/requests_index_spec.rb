require 'browser_helper'

RSpec.describe 'Requests Index' do
  let(:submitter) { create(:confirmed_user, login: 'kugelblitz') }
  let(:receiver) { create(:confirmed_user, login: 'titan') }
  let(:another_submitter) { create(:confirmed_user, login: 'foo') }
  let(:target_project) { create(:project_with_package, package_name: 'goal', maintainer: receiver) }
  let(:source_project) { create(:project_with_package, package_name: 'ball', maintainer: submitter) }
  let(:other_source_project) { create(:project_with_package, package_name: 'package_2', maintainer: another_submitter) }
  let(:yet_another_project) { create(:project_with_package, package_name: 'goal', maintainer: receiver) }
  let(:reviewer) { create(:confirmed_user, login: 'reviewer_1') }

  let!(:incoming_request) do
    create(:bs_request_with_submit_action, description: 'Please take this',
                                           creator: submitter,
                                           source_package: source_project.packages.first,
                                           target_project: target_project)
  end

  let!(:other_incoming_request) do
    create(:bs_request_with_submit_action, description: 'This is very important',
                                           creator: another_submitter,
                                           source_package: other_source_project.packages.first,
                                           target_project: target_project)
  end

  let!(:yet_another_incoming_request) do
    create(:bs_request_with_submit_action, description: 'This is very important',
                                           creator: submitter,
                                           source_package: source_project.packages.first,
                                           target_project: yet_another_project)
  end

  let!(:yet_another_incoming_request2) do
    create(:bs_request_with_submit_action, description: 'This is very important again',
                                           creator: submitter,
                                           source_package: source_project.packages.first,
                                           target_project: yet_another_project)
  end

  let!(:outgoing_request) do
    create(:bs_request_with_submit_action, description: 'How about this?',
                                           creator: receiver,
                                           source_package: source_project.packages.first,
                                           target_project: other_source_project)
  end

  before do
    Flipper.enable(:request_index)
    login receiver
    visit my_requests_path
  end

  it 'lists all requests by default' do
    expect(page).to have_link(href: "/request/show/#{incoming_request.number}")
    expect(page).to have_link(href: "/request/show/#{other_incoming_request.number}")
    expect(page).to have_link(href: "/request/show/#{outgoing_request.number}")
  end

  it 'filters incoming requests' do
    find_by_id('requests-dropdown-trigger').click if mobile? # open the filter dropdown
    check('Incoming')

    expect(page).to have_link(href: "/request/show/#{incoming_request.number}")
    expect(page).to have_link(href: "/request/show/#{other_incoming_request.number}")
    expect(page).to have_no_link(href: "/request/show/#{outgoing_request.number}")
  end

  it 'filters outgoing requests' do
    find_by_id('requests-dropdown-trigger').click if mobile? # open the filter dropdown
    check('Outgoing')

    expect(page).to have_link(href: "/request/show/#{outgoing_request.number}")
    expect(page).to have_no_link(href: "/request/show/#{incoming_request.number}")
    expect(page).to have_no_link(href: "/request/show/#{other_incoming_request.number}")
  end

  describe 'filters request by state' do
    let!(:request_in_review) do
      create(:bs_request_with_submit_action,
             description: 'This is in review state',
             creator: receiver,
             source_package: source_project.packages.first,
             target_project: other_source_project,
             state: :review,
             review_by_user: receiver)
    end

    # rubocop:disable RSpec/ExampleLength
    it 'shows all requests with the selected state' do
      find_by_id('requests-dropdown-trigger').click if mobile? # open the filter dropdown
      within('#content-selector-filters') do
        check('review')
        sleep 2 # there is a timeout before firing the filtering
      end

      within('#requests') do
        expect(page).to have_link(href: "/request/show/#{request_in_review.number}")
        expect(page).to have_css('.list-group-item span.badge.text-bg-secondary', text: 'review')
        expect(page).to have_no_link(href: "/request/show/#{incoming_request.number}")
      end
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe 'filters request by action type' do
    let!(:request_with_maintenance_actions) do
      create(:bs_request_with_maintenance_release_actions,
             description: 'This is a maintenance request',
             creator: receiver,
             source_package: source_project.packages.first,
             target_project: other_source_project)
    end

    # rubocop:disable RSpec/ExampleLength
    it 'shows all requests with the selected action' do
      find_by_id('requests-dropdown-trigger').click if mobile? # open the filter dropdown
      within('#content-selector-filters') do
        check('Maintenance Release')
        page.execute_script('submitFilters()') # autosubmit form
      end

      within('#requests') do
        expect(page).to have_link(href: "/request/show/#{request_with_maintenance_actions.number}")
        expect(page).to have_css('.list-group-item .fas.fa-road-circle-check')
        expect(page).to have_no_link(href: "/request/show/#{incoming_request.number}")
      end
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe 'using the request creator filter' do
    before do
      if mobile?
        find_by_id('requests-dropdown-trigger').click # open the filter dropdown
        sleep 0.5 # wait for dropdown to open
      end

      within('#content-selector-filters') do
        fill_in('creators_search', with: receiver.login[0, 2])
        find('.ui-menu-item-wrapper', match: :first).click
        # Remove focus from autocomplete search to allow the autosubmit
        find(:xpath, '//*[@id="request-creator-dropdown"]/div/div/span/i').click
        page.execute_script('submitFilters()') # autosubmit form
      end

      if mobile?
        find_by_id('requests-dropdown-trigger').click # open the filter dropdown
        sleep 0.5 # wait for dropdown to open
      end

      within('#content-selector-filters') do
        fill_in('creators_search', with: another_submitter.login[0, 2])
        find('.ui-menu-item-wrapper', match: :first).click
        # Remove focus from autocomplete search to allow the autosubmit
        find(:xpath, '//*[@id="request-creator-dropdown"]/div/div/span/i').click
        page.execute_script('submitFilters()') # autosubmit form
      end
    end

    it 'filters the requests by multiple creators' do
      expect(page).to have_link(href: "/request/show/#{outgoing_request.number}")
      expect(page).to have_link(href: "/request/show/#{other_incoming_request.number}")
      expect(page).to have_no_link(href: "/request/show/#{incoming_request.number}")
    end

    # rubocop:disable RSpec/ExampleLength
    it 'allows to modify the filter selection' do
      if mobile?
        find_by_id('requests-dropdown-trigger').click # open the filter dropdown
        sleep 0.5 # wait for dropdown to open
      end

      within('#content-selector-filters') do
        uncheck("creators[#{receiver.login}]")
        page.execute_script('submitFilters()') # autosubmit form
      end

      expect(page).to have_no_link(href: "/request/show/#{outgoing_request.number}")
      expect(page).to have_link(href: "/request/show/#{other_incoming_request.number}")
      expect(page).to have_no_link(href: "/request/show/#{incoming_request.number}")
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe 'filters request by created_at' do
    let!(:request_in_review) do
      create(:bs_request_with_submit_action,
             description: 'This is in review state',
             creator: receiver,
             source_package: source_project.packages.first,
             target_project: other_source_project,
             state: :review,
             review_by_user: receiver)
    end

    # rubocop:disable RSpec/ExampleLength
    it 'shows only requests within the selected date range' do
      request_in_review.created_at = DateTime.now - 10.days # set request to be older
      request_in_review.save # update and store the new value
      find_by_id('requests-dropdown-trigger').click if mobile? # open the filter dropdown
      within('#content-selector-filters') do
        # filter from yesterday to tomorrow
        fill_in 'created_at_from', with: DateTime.now - 1.day
        fill_in 'created_at_to', with: DateTime.now + 1.day
        page.execute_script('submitFilters()') # autosubmit form
      end

      within('#requests') do
        expect(page).to have_no_link(href: "/request/show/#{request_in_review.number}")
        expect(page).to have_link(href: "/request/show/#{outgoing_request.number}")
      end
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe 'filters request by reviewer' do
    before do
      incoming_request.reviews.create(by_user: reviewer, state: 'new')

      if mobile?
        find_by_id('requests-dropdown-trigger').click # open the filter dropdown
        sleep 0.5 # wait for dropdown to open
      end

      within('#content-selector-filters') do
        fill_in('reviewer_search', with: reviewer.login)
        find('.ui-menu-item-wrapper', match: :first).click
        # Remove focus from autocomplete search to allow the autosubmit
        find(:xpath, '//*[@id="request-reviewer-dropdown"]/div/div/span/i').click
        page.execute_script('submitFilters()') # autosubmit form
      end
    end

    it 'shows requests with reviews by the selected reviewers' do
      expect(page).to have_link(href: "/request/show/#{incoming_request.number}")
      expect(page).to have_no_link(href: "/request/show/#{outgoing_request.number}")
    end
  end

  describe 'filters request by multiple project names' do
    before do
      if mobile?
        find_by_id('requests-dropdown-trigger').click # open the filter dropdown
        sleep 0.5 # wait for dropdown to open
      end

      within('#content-selector-filters') do
        fill_in('project_names_search', with: yet_another_project.name)
        find('.ui-menu-item-wrapper', match: :first).click
        fill_in('project_names_search', with: source_project.name)
        find('.ui-menu-item-wrapper', match: :first).click
        # Remove focus from autocomplete search to allow the autosubmit
        find(:xpath, '//*[@id="request-project-name-dropdown"]/div/div/span/i').click
        sleep 2
      end
    end

    it 'shows requests with source or target project by the selected project names' do
      expect(page).to have_link(href: "/request/show/#{yet_another_incoming_request.number}")
      expect(page).to have_link(href: "/request/show/#{yet_another_incoming_request2.number}")
      expect(page).to have_no_link(href: "/request/show/#{other_incoming_request.number}")
    end
  end
end
