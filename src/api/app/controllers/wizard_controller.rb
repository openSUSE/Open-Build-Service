require 'wizard'

class WizardController < ApplicationController

  # GET/POST /source/<project>/<package>/_wizard
  def package_wizard
    prj_name = params[:project]
    pkg_name = params[:package]
    pkg = Package.get_by_project_and_name(prj_name, pkg_name)

    if not @http_user.can_modify_package?(pkg)
      render_error :status => 403, :errorcode => "change_package_no_permission",
        :message => "no permission to change package"
      return
    end

    logger.debug("package_wizard, #{params.inspect}")

    @wizard_xml = "/source/#{prj_name}/#{pkg_name}/wizard.xml"
    begin
      @wizard = Wizard.new(backend_get(@wizard_xml))
    rescue ActiveXML::Transport::NotFoundError
      @wizard = Wizard.new("")
    end
    @wizard["name"] = pkg_name
    @wizard["email"] = @http_user.email
    
    loop do
      questions = @wizard.run
      logger.debug("questions: #{questions.inspect}")
      if ! questions || questions.empty?
        break
      end
      @wizard_form = WizardForm.new(
                        "Creating package #{pkg_name} in project #{prj_name}")
      questions.each do |question|
        name = question.keys[0]
        if params[name] && ! params[name].empty?
          @wizard[name] = params[name]
          next
        end
        attrs = question[name]
        @wizard_form.add_entry(name, attrs["type"], attrs["label"],
                               attrs["legend"], attrs["options"], @wizard[name])
      end
      if ! @wizard_form.entries.empty?
        return render_wizard
      end
    end

    # create package container
    package = Project.find_by_name!(params[:project]).new(name: params[:package])
    package.title = @wizard["summary"]
    package.description = @wizard["description"]
    package.store

    # create service file
    node = Builder::XmlMarkup.new(:indent=>2)
    xml = node.services() do |s|
       # download file
       m = @wizard["sourcefile"].split("://")
       protocol = m.first()
       host = m[1].split("/").first()
       path = m[1].split("/",2).last()
       s.service(:name => "download_url") do |d|
          d.param(protocol, :name => "protocol")
          d.param(host, :name => "host")
          d.param(path, :name => "path")
       end

       # run generator
       if @wizard["generator"] and @wizard["generator"] != "-"
          s.service(:name => "generator_#{@wizard['generator']}")
       end

       # run verification
    end

    logger.debug("package_wizard, #{xml.inspect}")
    logger.debug("package_wizard, #{xml}")
    Suse::Backend.put("/source/#{params[:project]}/#{params[:package]}/_service?rev=upload", xml)
    Suse::Backend.post("/source/#{params[:project]}/#{params[:package]}?cmd=commit&rev=upload&user=#{@http_user.login}", "")

    @wizard_form.last = true
    render_wizard
  end

  private
  def render_wizard
    if @wizard.dirty
      Suse::Backend.put(@wizard_xml, @wizard.serialize)
    end
    render :template => "wizard", :status => 200
  end
end

# vim:et:ts=2:sw=2
