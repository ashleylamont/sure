require "test_helper"

class DS::IconPickerTest < ViewComponent::TestCase
  test "renders one filterable label per icon, keyed by icon code" do
    render_icon_picker(icons: %w[pizza coffee dog])

    assert_selector "label.filterable-item", count: 3
    assert_selector "label.filterable-item[data-filter-name='pizza']"
    assert_selector "label.filterable-item[data-filter-name='coffee']"
    assert_selector "label.filterable-item[data-filter-name='dog']"
  end

  test "wires the icon search controller with a search input and empty message" do
    render_icon_picker(icons: %w[pizza])

    assert_selector "[data-controller='icon-picker']"
    assert_selector "input[type='search'][data-icon-picker-target='input']"
    assert_selector "[data-icon-picker-target='list']"
    assert_selector "[data-icon-picker-target='emptyMessage']", text: "No matching icons", visible: :all
  end

  test "prevents Enter in the search field from submitting the form" do
    render_icon_picker(icons: %w[pizza])

    action = page.find("input[type='search']")["data-action"]
    assert_includes action, "input->icon-picker#filter"
    assert_includes page.find("[data-controller='icon-picker']")["data-action"], "keydown->icon-picker#handleKeydown"
  end

  test "preserves the color-icon-picker contract on each radio" do
    render_icon_picker(icons: %w[pizza])

    radio = page.find("input[type='radio']", visible: :all)
    assert_equal "icon", radio["data-color-icon-picker-target"]
    assert_includes radio["data-action"], "change->color-icon-picker#handleIconChange"
    assert_includes radio["data-action"], "change->color-icon-picker#handleIconColorChange"

    assert_selector "label.filterable-item > input[type='radio'] + div > svg", visible: :all
  end

  test "binds radios to the method it was given" do
    render_icon_picker(icons: %w[pizza])
    assert_selector "input[name='category[lucide_icon]']", visible: :all

    render_inline DS::IconPicker.new(
      form: form_builder_for(Goal.new, "goal"),
      method: :icon,
      icons: %w[pizza]
    )
    assert_selector "input[name='goal[icon]']", visible: :all
  end

  test "exposes readable names and everyday search keywords" do
    render_icon_picker(icons: %w[shopping-basket credit-card paw-print])

    basket = page.find("label[data-filter-name='shopping-basket']")
    assert_equal "Shopping basket", basket["title"]
    assert_includes JSON.parse(basket["data-icon-picker-keywords"]).join(" "), "groceries"
    assert_selector "input[value='credit-card'][aria-label='Credit card']", visible: :all
    assert_includes page.find("label[data-filter-name='paw-print']")["data-icon-picker-keywords"], "pets"
  end

  test "searches translated categories alongside English names and keywords" do
    I18n.with_locale(:fr) do
      render_icon_picker(icons: %w[shopping-basket piggy-bank])

      basket = page.find("label[data-filter-name='shopping-basket']")
      assert_includes JSON.parse(basket["data-icon-picker-keywords"]), "Épicerie"
      assert_includes JSON.parse(basket["data-icon-picker-names"]), "shopping-basket"
      assert_includes JSON.parse(basket["data-icon-picker-names"]), "Shopping basket"
      assert_includes page.find("label[data-filter-name='piggy-bank']")["data-icon-picker-keywords"], "Épargne"
      assert_selector "input[value='shopping-basket'][aria-label='Shopping basket']", visible: :all
    end
  end

  test "all available icons have an English label and search metadata" do
    picker = DS::IconPicker.new(form: nil, method: :icon, icons: Category.icon_codes)

    Category.icon_codes.each do |code|
      assert I18n.exists?("ds.icon_picker.icons.#{code}.label", :en), "Missing label for #{code}"
      assert_not_empty picker.search_names(code)
      assert_not_empty picker.search_keywords(code)
    end
  end

  private
    def render_icon_picker(icons:)
      render_inline DS::IconPicker.new(
        form: form_builder_for(Category.new, "category"),
        method: :lucide_icon,
        icons: icons
      )
    end

    def form_builder_for(object, name)
      StyledFormBuilder.new(name, object, vc_test_controller.view_context, {})
    end
end
