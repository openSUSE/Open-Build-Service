module RescueAuthorizationHandler
  extend ActiveSupport::Concern

  included do
    rescue_from Pundit::NotAuthorizedError do |exception|
      respond_to do |format|
        format.html do
          flash[:error] = authorization_message(exception)
          redirect_path = unauthorized_redirect_path(exception)
          if redirect_path
            redirect_to(redirect_path)
          else
            redirect_back(fallback_location: root_path)
          end
        end
        format.json { render json: { errorcode: authorization_errorcode(exception), summary: authorization_message(exception) }, status: 403 }
        format.js { render json: { errorcode: authorization_errorcode(exception), summary: authorization_message(exception) }, status: 403 }
        # Consider everything else an XML request...
        format.any do
          @errorcode = authorization_errorcode(exception)
          @summary = authorization_message(exception)
          render template: 'status', status: 403, formats: [:xml]
        end
      end
    end

    private

    def action_for_exception(exception)
      action = exception.query || 'show?'
      action = action.to_s.chop

      case action
      when 'index' then 'list'
      when 'show' then 'view'
      when 'new' then 'create'
      when 'destroy' then 'delete'
      else action
      end
    end

    def authorization_errorcode(exception)
      if exception.record.present?
        "#{action_for_exception(exception)}_#{ActiveSupport::Inflector.underscore(exception.record.class.to_s)}_not_authorized"
      else
        "#{action_for_exception(exception)}_not_authorized"
      end
    end

    def authorization_message(exception)
      case exception.reason
      when :anonymous_user
        'Please login to access the resource'
      when :request_state_change
        "Request #{exception.record.number} would not be acceptable by you"
      else
        "Sorry, you are not authorized to #{action_for_exception(exception)} this #{ActiveSupport::Inflector.underscore(exception.record.class.to_s).humanize(capitalize: false)}."
      end
    end

    def unauthorized_redirect_path(exception)
      case exception.reason
      when :anonymous_user
        mode = CONFIG['proxy_auth_mode'] || :off
        if mode == :off
          new_session_path
        else
          root_path
        end
      end
    end
  end
end
