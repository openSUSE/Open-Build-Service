class SourceAttributeController < SourceController
  include ValidationHelper
  before_action :set_request_data, only: [:update, :set]
  before_action :find_attribute_container

  class RemoteProject < APIError
    setup 400, 'Attribute access to remote project is not yet supported'
  end

  class InvalidAttribute < APIError
  end

  class ChangeAttributeNoPermission < APIError
    setup 403
  end

  # GET
  # /source/:project/_attribute/:attribute
  # /source/:project/:package/_attribute/:attribute
  # /source/:project/:package/:binary/_attribute/:attribute
  #--------------------------------------------------------
  def show
    if params[:rev] || params[:meta] || params[:view] || @attribute_container.nil?
      # old or remote instance entry
      render xml: Backend::Api::Sources::Package.attributes(params[:project], params[:package], params)
      return
    end

    opts = { attrib_type: @at }.with_indifferent_access
    [:binary, :with_default, :with_project].each { |p| opts[p] = params[p] }
    render xml: @attribute_container.render_attribute_axml(opts)
  end

  # DELETE
  # /source/:project/_attribute/:attribute
  # /source/:project/:package/_attribute/:attribute
  # /source/:project/:package/:binary/_attribute/:attribute
  #--------------------------------------------------------
  def delete
    attrib = @attribute_container.find_attribute(@at.namespace, @at.name, @binary)

    # checks
    raise ActiveRecord::RecordNotFound, "Attribute #{params[:attribute]} does not exist" unless attrib
    unless User.possibly_nobody.can_create_attribute_in?(@attribute_container, @at)
      raise ChangeAttributeNoPermission, "User #{User.possibly_nobody.login} has no permission to change attribute"
    end

    # exec
    attrib.destroy
    render_ok
  end

  # POST
  # /source/:project/_attribute/:attribute
  # /source/:project/:package/_attribute/:attribute
  # /source/:project/:package/:binary/_attribute/:attribute
  #--------------------------------------------------------
  def update
    # This is necessary for checking the authorization and do not create the attribute
    # The attribute creation will happen in @attribute_container.store_attribute_xml
    any_change = false
    @request_data.elements('attribute') do |attr|
      attrib_type = AttribType.find_by_namespace_and_name!(attr.value('namespace'), attr.value('name'))
      attrib = Attrib.new(attrib_type: attrib_type)

      attr.elements('value') do |value|
        attrib.values.new(value: value)
      end

      attrib.container = @attribute_container

      unless attrib.valid?
        render_error(message: attrib.errors.full_messages.join('\n'), status: 400, errorcode: attrib.errors.filter_map(&:type).first&.to_s)
        return false
      end

      authorize attrib, :create?
    end

    # exec
    @request_data.elements('attribute') do |attr|
      any_change = true if @attribute_container.store_attribute_xml(attr, @binary)
    end
    # Single commit to backend
    @attribute_container.write_attributes if any_change
    render_ok
  end

  # PUT
  # /source/:project/_attribute
  # /source/:project/:package/_attribute
  #--------------------------------------------------------
  def set
    # This is necessary for checking the authorization and do not create the attribute
    # The attribute creation will happen in @attribute_container.store_attribute_xml
    @request_data.elements('attribute') do |attr|
      attrib_type = AttribType.find_by_namespace_and_name!(attr.value('namespace'), attr.value('name'))
      attrib = Attrib.new(attrib_type: attrib_type)

      attr.elements('value') do |value|
        attrib.values.new(value: value)
      end

      attrib.container = @attribute_container

      unless attrib.valid?
        render_error(message: attrib.errors.full_messages.join('\n'), status: 400, errorcode: attrib.errors.filter_map(&:type).first&.to_s)
        return false
      end

      authorize attrib, :create?
    end
    # exec
    @request_data.elements('attribute') do |attr|
      @attribute_container.store_attribute_xml(attr, @binary)
    end

    # cleanup not anymore used attributes
    attribs = if @attribute_container.is_a?(Project)
                Attrib.where(project: @attribute_container)
              else
                Attrib.where(package: @attribute_container)
              end
    attribs.each do |attrib|
      next if @request_data.elements('attribute').any? { |i| i['namespace'] == attrib.namespace && i['name'] == attrib.name }

      authorize attrib, :destroy?
      attrib.destroy!
    end

    # Single commit to backend
    @attribute_container.write_attributes
    render_ok
  end

  protected

  def attribute_type(name)
    return if name.blank?

    # if an attribute param is given, it needs to exist
    AttribType.find_by_name!(name)
  end

  def find_attribute_container
    # init and validation
    #--------------------
    @binary = params[:binary]
    # valid post commands
    if params[:package] && params[:package] != '_project'
      @attribute_container = Package.get_by_project_and_name(params[:project],
                                                             params[:package],
                                                             use_source: false)
    else
      # project
      raise RemoteProject if Project.is_remote_project?(params[:project])

      @attribute_container = Project.get_by_name(params[:project])
    end

    @at = attribute_type(params[:attribute])
  end
end
