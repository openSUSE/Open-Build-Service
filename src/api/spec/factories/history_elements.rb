FactoryGirl.define do
  factory :history_element_review_assigned, class: 'HistoryElement::ReviewAssigned' do
    type { 'HistoryElement::ReviewAssigned' }
  end

  factory :history_element_review_accepted, class: 'HistoryElement::ReviewAccepted' do
    type { 'HistoryElement::ReviewAccepted' }
  end
end