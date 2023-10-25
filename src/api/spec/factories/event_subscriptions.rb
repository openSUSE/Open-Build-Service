FactoryBot.define do
  factory :event_subscription do
    enabled { true }

    factory :event_subscription_comment_for_project do
      eventtype { 'Event::CommentForProject' }
      receiver_role { 'commenter' }
      channel { :instant_email }
      user
      group { nil }
    end

    factory :event_subscription_comment_for_project_without_subscriber do
      eventtype { 'Event::CommentForProject' }
      receiver_role { 'commenter' }
      channel { :instant_email }
    end

    factory :event_subscription_comment_for_package do
      eventtype { 'Event::CommentForPackage' }
      receiver_role { 'commenter' }
      channel { :instant_email }
      user
      group { nil }
    end

    factory :event_subscription_comment_for_request do
      eventtype { 'Event::CommentForRequest' }
      receiver_role { 'commenter' }
      channel { :instant_email }
      user
      group { nil }
    end

    factory :event_subscription_comment_for_request_without_subscriber do
      eventtype { 'Event::CommentForRequest' }
      receiver_role { 'commenter' }
      channel { :instant_email }
    end

    factory :event_subscription_request_created do
      eventtype { 'Event::RequestCreate' }
      receiver_role { 'target_maintainer' }
      channel { :instant_email }
      user
      group { nil }
    end

    factory :event_subscription_request_statechange do
      eventtype { 'Event::RequestStatechange' }
      receiver_role { 'target_maintainer' }
      channel { :instant_email }
      user
      group { nil }
    end

    factory :event_subscription_review_wanted do
      eventtype { 'Event::ReviewWanted' }
      receiver_role { 'reviewer' }
      channel { :instant_email }
      user
      group { nil }
    end

    factory :event_subscription_relationship_create do
      eventtype { 'Event::RelationshipCreate' }
      receiver_role { 'any_role' }
      channel { :instant_email }
      user
      group { nil }
    end

    factory :event_subscription_relationship_delete do
      eventtype { 'Event::RelationshipDelete' }
      receiver_role { 'any_role' }
      channel { :instant_email }
      user
      group { nil }
    end

    factory :event_subscription_report_for_project do
      eventtype { 'Event::ReportForProject' }
      receiver_role { 'moderator' }
      channel { :instant_email }
      user
      group { nil }
    end

    factory :event_subscription_report_for_package do
      eventtype { 'Event::ReportForPackage' }
      receiver_role { 'moderator' }
      channel { :instant_email }
      user
      group { nil }
    end

    factory :event_subscription_report_for_comment do
      eventtype { 'Event::ReportForComment' }
      receiver_role { 'moderator' }
      channel { :instant_email }
      user
      group { nil }
    end

    factory :event_subscription_report_for_user do
      eventtype { 'Event::ReportForUser' }
      receiver_role { 'moderator' }
      channel { :instant_email }
      user
      group { nil }
    end
  end
end
