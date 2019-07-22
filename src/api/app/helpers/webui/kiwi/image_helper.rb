# typed: false
module Webui::Kiwi::ImageHelper
  include Webui::ProjectHelper

  def kiwi_image_breadcrumb(kiwi_image, *args)
    @project = kiwi_image.package.try(:project)
    @package = kiwi_image.package
    return unless @project

    args.insert(0, link_to(@package, package_show_path(project: @project, package: @package)))
    project_bread_crumb(*args)
  end

  def icon_for_daemon(state)
    case state
    when 'dead'
      'fa-exclamation-circle text-danger'
    when 'booting'
      'fa-exclamation-triangle text-warning'
    else
      'fa-check-circle text-success'
    end
  end
end
