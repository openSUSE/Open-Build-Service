class FullTextSearch
  include ActiveModel::Serializers::JSON

  cattr_accessor :ranker, :field_weights, :per_page, :star,
      :linked_count_weight, :activity_index_weight, :links_to_other_weight,
      :is_devel_weight

  self.linked_count_weight = 100
  self.activity_index_weight = 500
  self.links_to_other_weight = -1000
  self.is_devel_weight = 1000
  self.field_weights = { name: 10, title: 2, description: 1 }
  self.ranker = :sph04
  self.per_page = 50
  self.star = false

  attr_accessor :text, :classes, :fields, :attrib_type_id, :issue_tracker_name, :issue_name
  attr_reader :result

  def initialize(attrib = {})
    if attrib
      attrib.each do |att, value|
        self.send(:"#{att}=", value)
      end
    end
    @result = nil
  end

  def search(options = {})
    if text.blank?
      search_str = nil
    elsif fields.nil? || fields.empty?
      search_str = Riddle::Query.escape(text)
    else
      search_str = "@(#{fields.map(&:to_s).join(",")}) #{Riddle::Query.escape(text)}"
    end

    issue_id = nil
    if issue_tracker_name && issue_name
      issue_id = Issue.joins(:issue_tracker).where("issue_trackers.name" => issue_tracker_name, name: issue_name).pluck(:id).first
    end

    args = {}
    args[:ranker] = FullTextSearch.ranker
    args[:star] = FullTextSearch.star
    args[:select] = "(@weight + "\
                    "#{FullTextSearch.linked_count_weight} * linked_count + "\
                    "#{FullTextSearch.links_to_other_weight} * links_to_other + "\
                    "#{FullTextSearch.is_devel_weight} * is_devel + "\
                    "#{FullTextSearch.activity_index_weight} * (activity_index * POW( 2.3276, (updated_at - #{Time.now.to_i}) / 10000000))) "\
                    "as adjusted_weight"
    args[:order] = "adjusted_weight DESC"
    args[:field_weights] = FullTextSearch.field_weights
    if issue_id || attrib_type_id
      args[:with] = {}
      args[:with][:issue_ids] = issue_id.to_i unless issue_id.nil?
      args[:with][:attrib_type_ids] = attrib_type_id.to_i unless attrib_type_id.nil?
    end
    if classes
      args[:classes] = classes.map {|i| i.to_s.classify.constantize }
    end

    args[:page] = options[:page]
    args[:per_page] = options[:per_page] || FullTextSearch.per_page

    puts args.inspect
    @result = ThinkingSphinx.search search_str, args
  end

  # Needed by ActiveModel::Serializers
  def attributes
    { 'text' => nil, 'classes' => nil, 'fields' => nil, 'attrib_type_id' => nil,
      'issue_tracker_name' => nil, 'issue_name' => nil,
      'result' => nil, 'total_entries' => nil }
  end

  private

  def read_attribute_for_serialization(attrib)
    if attrib.to_sym == :result
      # Format expected by webui search controller
      if @result.nil?
        nil
      else
        @result.map {|r| {:type => r.class.model_name.to_s.downcase,
                          :data  => r, :search_attributes => r.sphinx_attributes}}
      end
    elsif attrib.to_sym == :total_entries
      @result.nil? ? nil : @result.total_entries
    else
      super
    end
  end
end
