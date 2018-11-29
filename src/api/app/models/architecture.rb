# This class provides all existing architectures known to OBS
class Architecture < ApplicationRecord
  #### Includes and extends
  #### Constants
  #### Self config
  #### Attributes

  #### Associations macros (Belongs to, Has one, Has many)
  has_many :repository_architectures, inverse_of: :architecture
  has_many :repositories, through: :repository_architectures
  has_many :flags

  #### Callbacks macros: before_save, after_save, etc.
  after_save :discard_cache
  after_destroy :discard_cache

  #### Scopes (first the default_scope macro if is used)
  scope :available, -> { where(available: 1) }

  #### Validations macros
  validates :name, uniqueness: true
  validates :name, presence: true

  #### Class methods using self. (public and then private)

  def discard_cache
    Rails.cache.delete('archcache')
  end

  def self.archcache
    Rails.cache.fetch('archcache') do
      Architecture.all.map { |arch| [arch.name, arch] }.to_h
    end
  end

  def self.from_cache!(archname)
    unless archcache.key?(archname)
      raise ActiveRecord::RecordNotFound, "unknown architecture: '#{archname}'"
    end
    archcache[archname]
  end

  def worker
    case name
    when 'i586' then 'x86_64'
    when 'ppc' then 'ppc64'
    when 's390' then 's390x'
    else name
    end
  end

  #### To define class methods as private use private_class_method
  #### private

  #### Instance methods (public and then protected/private)
  def to_s
    name
  end
  #### Alias of methods
end

# == Schema Information
#
# Table name: architectures
#
#  id        :integer          not null, primary key
#  name      :string(255)      not null, indexed
#  available :boolean          default(FALSE)
#
# Indexes
#
#  arch_name_index  (name) UNIQUE
#
