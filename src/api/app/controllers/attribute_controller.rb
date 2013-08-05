require "rexml/document"

class AttributeController < ApplicationController

  validate_action :index => {:method => :get, :response => :directory}
  validate_action :namespace_definition => {:method => :get, :response => :attribute_namespace_meta}
  validate_action :namespace_definition => {:method => :delete, :response => :status}
  validate_action :namespace_definition => {:method => :post, :request => :attribute_namespace_meta, :response => :status}
  validate_action :attribute_definition => {:method => :get, :response => :attrib_type}
  validate_action :attribute_definition => {:method => :delete, :response => :status}
  validate_action :attribute_definition => {:method => :put, :request => :attrib_type, :response => :status}

  def index
    valid_http_methods :get

    if params[:namespace]
      an = AttribNamespace.where(name: params[:namespace] ).first
      unless an
        render_error :status => 400, :errorcode => 'unknown_namespace',
          :message => "Attribute namespace does not exist: #{params[:namespace]}"
        return
      end
      list = an.attrib_types.pluck(:name)
    else
      list = AttribNamespace.pluck(:name)
    end

    builder = Builder::XmlMarkup.new( :indent => 2 )
    xml = builder.directory( :count => list.length ) do |dir|
      list.each do |a|
        dir.entry( :name => a )
      end
    end

    render :text => xml, :content_type => "text/xml"
  end

  # /attribute/:namespace/_meta
  def namespace_definition

    if params[:namespace].nil?
      render_error :status => 400, :errorcode => 'missing_parameter',
        :message => "parameter 'namespace' is missing"
      return
    end
    namespace = params[:namespace]

    if request.get?
      @an = AttribNamespace.where(name: namespace).select(:id, :name).first
      unless @an
        render_error :message => "Unknown attribute namespace '#{namespace}'",
          :status => 404, :errorcode => "unknown_attribute_namespace"
      end
      return
    end

    # namespace definitions must be managed by the admin
    return unless extract_user
    unless @http_user.is_admin?
      render_error :status => 403, :errorcode => 'permissions denied',
        :message => "Namespace changes are only permitted by the administrator"
      return
    end

    if request.post?
      logger.debug "--- updating attribute namespace definitions ---"

      xml_element = Xmlhash.parse( request.raw_post )

      unless xml_element['name'] == namespace
        render_error :status => 400, :errorcode => 'illegal_request',
          :message => "Illegal request: POST #{request.path}: path does not match content"
        return
      end

      db = AttribNamespace.where(name: namespace).first
      if db
          logger.debug "* updating existing attribute namespace"
          db.update_from_xml(xml_element)
      else
          logger.debug "* create new attribute namespace"
          AttribNamespace.create(:name => namespace).update_from_xml(xml_element)
      end

      logger.debug "--- finished updating attribute namespace definitions ---"
      render_ok
    elsif request.delete?
      AttribNamespace.where(name: namespace).destroy_all
      render_ok
    else
      render_error :status => 400, :errorcode => 'illegal_request',
        :message => "Illegal request: POST #{request.path}"
    end
  end

  # /attribute/:namespace/:name/_meta
  def attribute_definition
    if params[:namespace].nil?
      render_error :status => 400, :errorcode => 'missing_parameter',
        :message => "parameter 'namespace' is missing"
      return
    end
    if params[:name].nil?
      render_error :status => 400, :errorcode => 'missing_parameter',
        :message => "parameter 'name' is missing"
      return
    end
    namespace = params[:namespace]
    name = params[:name]
    ans = AttribNamespace.where(name: namespace).first
    unless ans
       render_error :status => 400, :errorcode => 'unknown_attribute_namespace',
         :message => "Specified attribute namespace does not exist: '#{namespace}'"
       return
    end

    if request.get?
      @at = ans.attrib_types.where(:name => name).first
      unless @at
        render_error :message => "Unknown attribute '#{namespace}':'#{name}'",
          :status => 404, :errorcode => "unknown_attribute"
      end
      return
    end

    # permission check via User model
    return unless extract_user
    unless @http_user.can_modify_attribute_definition?(ans)
      render_error :status => 403, :errorcode => 'permissions denied',
        :message => "Attribute type changes are not permitted"
      return
    end

    if request.post?
      logger.debug "--- updating attribute type definitions ---"

      xml = REXML::Document.new( request.raw_post )
      xml_element = xml.elements["/definition"] if xml
      unless xml and xml_element and xml_element.attributes['name'] == name and xml_element.attributes['namespace'] == namespace
        render_error :status => 400, :errorcode => 'illegal_request',
          :message => "Illegal request: POST #{request.path}: path does not match content"
        return
      end

      entry = ans.attrib_types.where("name = ?", name ).first
      if entry
          db = AttribType.find( entry.id ) # get a writable object
          logger.debug "* updating existing attribute definitions"
          db.update_from_xml(xml_element)
      else
          logger.debug "* create new attribute definition"
          AttribType.new(:name => name, :attrib_namespace => ans ).update_from_xml(xml_element)
      end

      logger.debug "--- finished updating attribute namespace definitions ---"
      #--- end update attribute namespace definitions ---#

      render_ok
    elsif request.delete?
      at = ans.attrib_types.where("name = ?", name ).first
      at.destroy if at
      render_ok
    else
      render_error :status => 400, :errorcode => 'illegal_request',
        :message => "Illegal request: POST #{request.path}"
    end
  end

end
