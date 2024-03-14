module Webui
  module Projects
    class SigningKeysController < WebuiController
      before_action :set_project

      def show; end

      def download
        key = @project.signing_key(type: params[:kind])

        if key.present? && %w[gpg ssl].include?(params[:kind])
          if params[:kind] == 'gpg'
            send_data(key.content, disposition: 'attachment',
                                   filename: "#{@project.name.tr(':', '_')}_key.gpg")
          end
          if params[:kind] == 'ssl'
            send_data(key.content, disposition: 'attachment',
                                   filename: "#{@project.name.tr(':', '_')}_cert.pem")
          end
        else
          flash[:error] = "Key not found for project #{@project.name}"
          redirect_to project_signing_keys_path(@project)
        end
      end
    end
  end
end
