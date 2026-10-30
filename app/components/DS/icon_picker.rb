# frozen_string_literal: true

# `DS::IconPicker` is a shared, searchable lucide-icon grid.
#
# `method` is a parameter because the backing columns can differ:
# for now `categories.lucide_icon` and `goals.icon`.
class DS::IconPicker < DesignSystemComponent
  CATEGORY_ICONS = {
    income: %w[banknote badge-dollar-sign circle-dollar-sign coins wallet],
    food_and_drink: %w[utensils cooking-pot pizza coffee apple beer wine martini cookie cake ice-cream-cone],
    groceries: %w[shopping-bag shopping-basket shopping-cart apple],
    shopping: %w[shopping-bag shopping-basket shopping-cart store barcode shirt],
    transportation: %w[car bus train bike truck fuel circle-parking],
    travel: %w[plane luggage hotel compass map-pin globe tent tree-palm],
    entertainment: %w[film drama music gamepad-2 ticket popcorn tv],
    healthcare: %w[stethoscope heart-pulse pill ambulance thermometer],
    personal_care: %w[scissors bath sparkles],
    home_improvement: %w[hammer drill wrench home house],
    mortgage_rent: %w[home house building key],
    utilities: %w[lightbulb zap plug power droplet waves],
    subscriptions: %w[wifi tv music smartphone],
    insurance: %w[shield shield-plus umbrella],
    sports_and_fitness: %w[dumbbell bike trophy award],
    gifts_and_donations: %w[gift hand-heart hand-helping heart-handshake],
    taxes: %w[landmark calculator receipt receipt-text percent],
    loan_payments: %w[credit-card wallet-cards banknote],
    services: %w[briefcase wrench],
    fees: %w[receipt receipt-text percent],
    savings_and_investments: %w[piggy-bank trending-up chart-line bar-chart-3 pie-chart coins]
  }.freeze

  attr_reader :form, :method, :icons, :placeholder

  def initialize(form:, method:, icons:, placeholder: nil)
    @form = form
    @method = method
    @icons = icons
    @placeholder = placeholder || I18n.t("ds.icon_picker.search_placeholder")
  end

  def icon_label(icon_name, locale: I18n.locale)
    I18n.t("ds.icon_picker.icons.#{icon_name}.label", locale: locale, default: icon_name.tr("-", " ").humanize)
  end

  def search_names(icon_name)
    [ icon_name, icon_label(icon_name), icon_label(icon_name, locale: :en) ].uniq
  end

  def search_keywords(icon_name)
    key = "ds.icon_picker.icons.#{icon_name}.keywords"
    keywords = Array(I18n.t(key, default: [])) + Array(I18n.t(key, locale: :en, default: []))

    CATEGORY_ICONS.each do |category, category_icons|
      next unless category_icons.include?(icon_name)

      keywords << I18n.t("models.category.defaults.#{category}")
      keywords << I18n.t("models.category.defaults.#{category}", locale: :en)
    end

    keywords.uniq
  end
end
