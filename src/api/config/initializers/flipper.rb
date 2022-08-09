FEATURE_TOGGLES = [
  { name: :trigger_workflow, description: 'Better SCM and CI integration with OBS workflows' },
  { name: :new_watchlist, description: 'New implementation of watchlist including projects, packages and requests' },
  { name: :request_show_redesign, description: 'Redesign of the request pages to improve the collaboration workflow' }
].freeze

Flipper.configure do
  # Register beta and rollout groups by default.
  # We need to add it when initializing because Flipper.register doesn't
  # store anything in database.

  Flipper.register(:staff) do |user|
    user.respond_to?(:is_staff?) && user.is_staff?
  end

  Flipper.register(:beta) do |user|
    # The user has to be in beta for this group to be active...
    user.respond_to?(:in_beta?) && user.in_beta? &&
      # ...and if the user didn't disable the feature, it will be active
      user.respond_to?(:disabled_beta_features) && !user.disabled_beta_features.exists?(name: feature_toggle_name)
  end

  Flipper.register(:rollout) do |user|
    user.respond_to?(:in_rollout?) && user.in_rollout?
  end

  FEATURE_TOGGLES.each do |feature_toggle|
    Flipper.feature(feature_toggle[:name]).disable unless Flipper.feature(feature_toggle[:name]).exist?
  end
end
