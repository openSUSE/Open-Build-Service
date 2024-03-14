RSpec.describe WatchlistComponent, type: :component do
  let(:user) { create(:confirmed_user) }

  context 'when there is no watchable item in the current page' do
    let(:current_object) { create(:package) }
    let(:projects) { [] }
    let(:packages) { [] }
    let(:bs_requests) { [] }

    before do
      render_inline(described_class.new(user: user, current_object: current_object, projects: projects,
                                        packages: packages, bs_requests: bs_requests))
    end

    %w[package project request].each do |item_name|
      it { expect(rendered_content).to have_no_text("Watch this #{item_name}") }
      it { expect(rendered_content).to have_no_text("Remove this #{item_name} from Watchlist") }
      it { expect(rendered_content).to have_text("There are no #{item_name}s in the watchlist yet.") }
    end
  end

  context 'when loging in as a different user than the one who added stuff to watchlist' do
    let(:another_user) { create(:confirmed_user) }
    let(:package) { create(:package) }
    let(:projects) { [] }
    let(:packages) { [] }
    let(:bs_requests) { [] }

    before do
      create(:watched_item, :for_packages, watchable: package, user: another_user)
      render_inline(described_class.new(user: user, package: package, project: package.project,
                                        current_object: package, projects: projects, packages: packages, bs_requests: bs_requests))
    end

    it 'does not show anything' do
      expect(rendered_content).to have_text('Watch this package')
      expect(rendered_content).to have_text('There are no packages in the watchlist yet.')
    end
  end

  context 'when dealing with packages' do
    let(:projects) { [] }
    let(:packages) { [] }
    let(:bs_requests) { [] }

    context 'when passing a package object in the package parameter' do
      let(:package) { create(:package) }

      context 'and the package is not yet watched' do
        before do
          render_inline(described_class.new(user: user, package: package, project: package.project, current_object: package, projects: projects, packages: packages,
                                            bs_requests: bs_requests))
        end

        it { expect(rendered_content).to have_text('There are no packages in the watchlist yet.') }
        it { expect(rendered_content).to have_no_link(package.name) }
        it { expect(rendered_content).to have_text('Watch this package') }
      end

      context 'and the package is already watched' do
        let(:packages) { [package] }

        before do
          create(:watched_item, :for_packages, watchable: package, user: user)
          render_inline(described_class.new(user: user, package: package, project: package.project, current_object: package, projects: projects, packages: packages,
                                            bs_requests: bs_requests))
        end

        it { expect(rendered_content).to have_no_text('There are no packages in the watchlist yet.') }
        it { expect(rendered_content).to have_link(package.name) }
        it { expect(rendered_content).to have_text('Remove this package from Watchlist') }
      end
    end

    context 'when passing a string in the package parameter' do
      let(:multibuild_package) { "#{base_package}:flavor1" }

      context 'and the base package exists' do
        let(:base_package) { create(:package) }

        before do
          render_inline(described_class.new(user: user, package: multibuild_package, project: base_package.project, current_object: base_package, projects: projects, packages: packages,
                                            bs_requests: bs_requests))
        end

        it { expect(rendered_content).to have_text('There are no projects in the watchlist yet.') }
        it { expect(rendered_content).to have_no_link(base_package.name) }
        it { expect(rendered_content).to have_text('Watch this package') }
      end

      context "and the base package doesn't exist" do
        let(:base_package) { 'i_do_not_exist' }
        let(:project) { create(:project) }

        it {
          expect do
            described_class.new(user: user, package: multibuild_package, project: project, current_object: multibuild_package, projects: projects, packages: packages,
                                bs_requests: bs_requests)
          end.to raise_error(Package::Errors::UnknownObjectError)
        }
      end
    end
  end

  context 'when dealing with projects' do
    let(:project) { create(:project) }
    let(:projects) { [] }
    let(:packages) { [] }
    let(:bs_requests) { [] }

    context 'and the project is not yet watched' do
      before do
        render_inline(described_class.new(user: user, project: project, current_object: project, projects: projects,
                                          packages: packages, bs_requests: bs_requests))
      end

      it { expect(rendered_content).to have_text('There are no projects in the watchlist yet.') }
      it { expect(rendered_content).to have_no_link(project.name) }
      it { expect(rendered_content).to have_text('Watch this project') }
    end

    context 'and the project is already watched' do
      let(:projects) { [project] }

      before do
        create(:watched_item, :for_packages, watchable: project, user: user)
        render_inline(described_class.new(user: user, project: project, current_object: project, projects: projects,
                                          packages: packages, bs_requests: bs_requests))
      end

      it { expect(rendered_content).to have_no_text('There are no projects in the watchlist yet.') }
      it { expect(rendered_content).to have_link(project.name) }
      it { expect(rendered_content).to have_text('Remove this project from Watchlist') }
    end
  end

  context 'when dealing with new records' do
    let(:project) { Project.new }
    let(:projects) { [] }
    let(:packages) { [] }
    let(:bs_requests) { [] }

    before do
      render_inline(described_class.new(user: user, project: project, current_object: project, projects: projects,
                                        packages: packages, bs_requests: bs_requests))
    end

    it { expect(rendered_content).to have_text('There are no projects in the watchlist yet.') }
    it { expect(rendered_content).to have_no_text('Watch this project') }
  end

  context 'when dealing with requests' do
    let(:bs_request) { create(:bs_request_with_submit_action) }
    let(:projects) { [] }
    let(:packages) { [] }
    let(:bs_requests) { [] }

    context 'and the request is not yet watched' do
      before do
        render_inline(described_class.new(user: user, bs_request: bs_request, current_object: bs_request, projects: projects,
                                          packages: packages, bs_requests: bs_requests))
      end

      it { expect(rendered_content).to have_text('There are no requests in the watchlist yet.') }
      it { expect(rendered_content).to have_no_link("##{bs_request.number} Submit") }
      it { expect(rendered_content).to have_text('Watch this request') }
    end

    context 'and the request is already watched' do
      let(:bs_requests) { [bs_request] }

      before do
        create(:watched_item, :for_bs_requests, watchable: bs_request, user: user)
        render_inline(described_class.new(user: user, bs_request: bs_request, current_object: bs_request,
                                          projects: projects, packages: packages, bs_requests: bs_requests))
      end

      it { expect(rendered_content).to have_no_text('There are no requests in the watchlist yet.') }
      it { expect(rendered_content).to have_link("##{bs_request.number} Submit") }
      it { expect(rendered_content).to have_text('Remove this request from Watchlist') }
    end
  end
end
