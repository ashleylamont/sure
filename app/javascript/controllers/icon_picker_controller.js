import { Controller } from "@hotwired/stimulus";
import { rankIcons } from "utils/icon_search";

export default class extends Controller {
  static targets = ["input", "list", "item", "emptyMessage"];

  connect() {
    this.icons = this.itemTargets.map((element) => ({
      element,
      names: JSON.parse(element.dataset.iconPickerNames),
      keywords: JSON.parse(element.dataset.iconPickerKeywords),
    }));
    this.filter();
    if (this.element.closest("details")?.open) this.inputTarget.focus();
  }

  filter() {
    this.results = rankIcons(this.icons, this.inputTarget.value);
    const visible = new Set(this.results);
    for (const icon of this.icons) {
      icon.element.hidden = !visible.has(icon);
    }
    for (const icon of this.results) this.listTarget.append(icon.element);
    this.emptyMessageTarget.classList.toggle("hidden", this.results.length > 0);
    this.listTarget.scrollTop = 0;
  }

  resetOnClose(event) {
    if (event.target !== this.element.closest("details")) return;
    if (event.target.open) {
      this.inputTarget.focus();
    } else {
      this.inputTarget.value = "";
      this.filter();
    }
  }

  handleKeydown(event) {
    if (event.isComposing) return;
    if (event.target !== this.inputTarget) {
      if (event.key === "Enter" && event.target.type === "radio") {
        event.preventDefault();
        event.target.click();
      }
      return;
    }
    if (event.key === "Enter") {
      event.preventDefault();
      if (this.inputTarget.value.trim()) this.results[0]?.element.click();
    } else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      const result =
        event.key === "ArrowDown" ? this.results[0] : this.results.at(-1);
      result?.element.querySelector("input").focus();
    }
  }
}
