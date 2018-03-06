module Cloud
  class UploadJob
    include ActiveModel::Validations
    include ActiveModel::Model
    extend Forwardable

    attr_accessor :user_upload_job, :backend_upload_job, :target_params, :filename, :arch, :target, :user, :vpc_subnet_id
    validate :validate_dependencies
    validates :user, presence: true
    validates :filename, presence: true, format: {
      with: /\A.+(.raw.xz|.vhdfixed.xz)\z/, message: "'%{value}' is not a valid cloud image (needs to be a raw.xz or vhdfixed.xz file)"
    }
    validates :arch, inclusion: { in: ['x86_64'], message: "'%{value}' is not a valid cloud architecture" }
    validates :target, inclusion: { in: ['ec2'] }
    validates :vpc_subnet_id, format: { with: /\Asubnet-[-\w]+\z/, message: 'not a valid format', allow_blank: true }

    def_delegator :backend_upload_job, :id

    def self.create(params)
      upload_job = new(params.slice(:filename, :arch, :user, :target, :vpc_subnet_id))
      return upload_job if upload_job.invalid?

      upload_job.target_params = upload_job.target_validator_class.build(params)
      return upload_job if upload_job.target_params.invalid?

      upload_job.backend_upload_job = Cloud::Backend::UploadJob.create(params.merge(target: upload_job.target))
      return upload_job if upload_job.backend_upload_job.invalid?

      upload_job.user_upload_job = upload_job.user.upload_jobs.create(job_id: upload_job.id)
      upload_job
    end

    def uploadable?
      valid?
      errors[:filename].blank? && errors[:arch].blank?
    end

    def target_validator_class
      @target_validator_class ||= "::Cloud::Params::#{target.capitalize}".constantize
    end

    private

    def validate_dependencies
      [target_params, backend_upload_job, user_upload_job].each do |dependency|
        next if dependency.blank? || dependency.valid?
        dependency.errors.full_messages.each do |msg|
          errors.add(:base, msg)
        end
      end
    end
  end
end
