class Kiwi::PackageGroup < ApplicationRecord
  has_many :packages, dependent: :destroy
  belongs_to :image

  # we need to add a prefix, to avoid generating class methods that already
  # exist in Active Record, such as "delete"
  enum kiwi_type: %i[bootstrap delete docker image iso lxc oem pxe split testsuite vmx], _prefix: :type

  scope :type_image, -> { where(kiwi_type: :image) }

  validates :kiwi_type, presence: true

  accepts_nested_attributes_for :packages, reject_if: :all_blank, allow_destroy: true

  def to_xml
    group_attributes = { type: kiwi_type }
    group_attributes[:profiles] = profiles if profiles.present?
    group_attributes[:patternType] = pattern_type if pattern_type.present?

    builder = Nokogiri::XML::Builder.new
    builder.packages(group_attributes) do |group|
      packages.each do |package|
        group.package(package.to_h)
      end
    end

    builder.to_xml save_with: Nokogiri::XML::Node::SaveOptions::NO_DECLARATION | Nokogiri::XML::Node::SaveOptions::FORMAT
  end

  def kiwi_type_image?
    kiwi_type == 'image'
  end
end

# == Schema Information
#
# Table name: kiwi_package_groups
#
#  id           :integer          not null, primary key
#  kiwi_type    :integer          not null
#  profiles     :string(255)
#  pattern_type :string(255)
#  image_id     :integer          indexed
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_kiwi_package_groups_on_image_id  (image_id)
#
# Foreign Keys
#
#  fk_rails_...  (image_id => kiwi_images.id)
#
