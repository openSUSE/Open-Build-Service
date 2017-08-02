module Feature
  module Repository
    # ObsRepository for active and inactive features based on YamlRepository having default values for each key in OBS
    #
    class ObsRepository < YamlRepository
      # Returns list of active features
      #
      # @return [Array<Symbol>] list of active features
      #
      def active_features
        data = read_file(@yaml_file_name)
        data[@environment]['features'] = data[@environment]['features']
        get_active_features(data, @environment)
      end
    end
  end
end
