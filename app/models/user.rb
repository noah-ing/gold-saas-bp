class User < ApplicationRecord
  devise :magic_link_authenticatable, :database_authenticatable, :registerable, :recoverable, :rememberable, :validatable

  # Active Storage association for avatar
  has_one_attached :avatar
  
  # Analytics associations
  has_many :visits, class_name: "Ahoy::Visit"
  has_many :events, through: :visits, class_name: "Ahoy::Event"
  
  # Constants for subscription statuses
  SUBSCRIPTION_STATUSES = %w[trialing active past_due canceled].freeze

  # Validations
  validates :subscription_status, inclusion: { in: SUBSCRIPTION_STATUSES }, allow_nil: true
  validates :name, length: { maximum: 100 }, allow_blank: true
  
  # Admin helper methods
  def admin?
    admin
  end

  # Subscription status helpers
  def trialing?
    subscription_status == 'trialing' && trial_ends_at.present? && trial_ends_at > Time.current
  end

  def active_subscription?
    subscription_status == 'active'
  end

  def past_due?
    subscription_status == 'past_due'
  end

  def canceled?
    subscription_status == 'canceled'
  end

  def subscribed?
    active_subscription? || trialing?
  end

  # Returns the user's current plan (could be nil if not subscribed)
  def current_plan
    Plan.find_by(stripe_price_id: stripe_subscription_id) if stripe_subscription_id.present?
  end

  # Card information helpers
  def card_info
    if card_brand.present? && card_last4.present?
      "#{card_brand.titleize} ending in #{card_last4}"
    else
      "No payment method"
    end
  end

  # Returns the formatted expiration date
  def card_expiration
    if card_exp_month.present? && card_exp_year.present?
      "#{card_exp_month}/#{card_exp_year}"
    else
      ""
    end
  end

  # Stripe customer helper
  def stripe_customer
    if stripe_customer_id.present?
      Stripe::Customer.retrieve(stripe_customer_id)
    else
      # Create a new customer if none exists
      customer = Stripe::Customer.create(
        email: email,
        name: name.presence || email.split('@').first # Use name if present, otherwise use email prefix
      )
      update(stripe_customer_id: customer.id)
      customer
    end
  end

  # Sets the card details from a Stripe payment method
  def update_card_details(payment_method)
    card = payment_method.card
    update(
      card_brand: card.brand,
      card_last4: card.last4,
      card_exp_month: card.exp_month,
      card_exp_year: card.exp_year
    )
  end

  # Helper for displaying user's name or email
  def display_name
    name.presence || email.split('@').first
  end

  # Notification preferences helpers
  def notification_enabled?(type)
    return false unless notification_preferences.is_a?(Hash)
    notification_preferences[type.to_s] || notification_preferences[type.to_sym]
  end

  def toggle_notification(type)
    prefs = notification_preferences || {}
    prefs[type.to_sym] = !notification_enabled?(type)
    update(notification_preferences: prefs)
  end
end
