class PublicKey
  include ActiveModel::Model

  attr_accessor :content, :algorithm, :ssl_certificate

  def self.find_by_project_name(project_name)
    response = Suse::Backend.get(backend_url(project_name)).body
    parsed_response = Xmlhash.parse(response)

    if parsed_response['pubkey'].present?
      public_key_params = {
        content: parsed_response['pubkey']['_content'],
        algorithm: parsed_response['pubkey']['algo']        
      }

      if parsed_response['sslcert'].present?
        public_key_params[:ssl_certificate] = parsed_response['sslcert']
      end

      new(public_key_params)
    end
  end

  private

  def self.backend_url(project_name)
    "/source/#{project_name}/_keyinfo?withsslcert=1"
  end
end