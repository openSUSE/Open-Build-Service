module Webui
  module Kiwi
    class ImagesController < WebuiController
      before_action -> { feature_active?(:kiwi_image_editor) }
      before_action :set_image, except: [:import_from_package]
      before_action :authorize_update, except: [:import_from_package]

      def import_from_package
        package = Package.find(params[:package_id])

        kiwi_file = package.kiwi_image_file

        unless kiwi_file
          redirect_back fallback_location: root_path, error: 'There is no KIWI file'
          return
        end

        package.kiwi_image.destroy if package.kiwi_image && package.kiwi_image_outdated?

        if package.kiwi_image.blank? || package.kiwi_image.destroyed?
          package.kiwi_image = ::Kiwi::Image.build_from_xml(package.source_file(kiwi_file), package.kiwi_file_md5)
          unless package.save
            errors = package.kiwi_image.parsed_errors("Kiwi File '#{kiwi_file}' has errors:",
                                                      [package.kiwi_image.package_groups.map(&:packages)].flatten.compact)
            redirect_to package_view_file_path(project: package.project, package: package, filename: kiwi_file), error: errors
            return
          end
        end

        redirect_to kiwi_image_path(package.kiwi_image)
      end

      def show
        @package_groups = @image.default_package_group
        respond_to do |format|
          format.html
          format.json { render json: { is_outdated: @image.outdated? } }
        end
      end

      def update
        ::Kiwi::Image.transaction do
          cleanup_non_project_repositories!

          @image.update_attributes!(image_params) unless params[:kiwi_image].empty?
          @image.write_to_backend
        end
        redirect_to action: :show
      rescue ActiveRecord::RecordInvalid, Timeout::Error
        @package_groups = @image.package_groups.select(&:kiwi_type_image?).first
        flash.now[:error] = @image.parsed_errors('Cannot update KIWI Image:', @package_groups.packages)
        render action: :show
      end

      def autocomplete_binaries
        binaries = ::Kiwi::Image.find_binaries_by_name(params[:term], @image.package.project.name,
                                                       params[:repositories], use_project_repositories: params[:use_project_repositories])
        render json: binaries.to_a.map { |result| {id: result.first, label: result.first, value: result.first} }
      end

      private

      def image_params
        repositories_attributes = [
          :id,
          :_destroy,
          :priority,
          :repo_type,
          :source_path,
          :alias,
          :username,
          :password,
          :prefer_license,
          :imageinclude,
          :replaceable,
          :order
        ]

        package_groups_attributes = [
          :id,
          :_destroy,
          packages_attributes: [:id, :name, :arch, :replaces, :bootdelete, :bootinclude, :_destroy]
        ]

        params.require(:kiwi_image).permit(
          :use_project_repositories,
          repositories_attributes: repositories_attributes,
          package_groups_attributes: package_groups_attributes
        )
      end

      def set_image
        @image = ::Kiwi::Image.includes(package_groups: :packages).find(params[:id])
      rescue ActiveRecord::RecordNotFound
        flash[:error] = "KIWI image '#{params[:id]}' does not exist"
        redirect_back(fallback_location: root_path)
      end

      def authorize_update
        authorize @image, :update?
      end

      def cleanup_non_project_repositories!
        return unless params[:kiwi_image][:use_project_repositories] == '1'

        @image.repositories.delete_all
        params[:kiwi_image].delete(:repositories_attributes)
      end
    end
  end
end
