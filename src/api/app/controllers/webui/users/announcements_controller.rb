class Webui::Users::AnnouncementsController < Webui::WebuiController
  before_action :require_login

  def create
    announcement = Announcement.find_by(id: params[:id])
    if announcement
      User.session!.announcements << announcement
      RabbitmqBus.send_to_bus('metrics', "user.acknowledged_announcement announcement_id=#{announcement.id}")
    else
      flash.now[:error] = "Couldn't find Announcement"
    end
    switch_to_webui2
  end
end
