import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";

const source = await readFile(
  new URL("../../../app/javascript/utils/icon_search.js", import.meta.url),
  "utf8",
);
const searchUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`;
const { normalizeIconQuery, rankIcons } = await import(searchUrl);

const icons = [
  { names: ["credit-card", "Credit card"], keywords: ["payment debt"] },
  { names: ["shopping-cart"], keywords: ["groceries grocery supermarket"] },
  { names: ["car"], keywords: ["vehicle transport"] },
  { names: ["shopping-basket"], keywords: ["groceries grocery", "Épicerie"] },
  { names: ["piggy-bank"], keywords: ["saving savings", "Épargne et investissements"] },
  { names: ["paw-print"], keywords: ["pet pets animals"] },
];
const names = (query) => rankIcons(icons, query).map((icon) => icon.names[0]);

test("finds everyday concepts and curated singular/plural aliases", () => {
  assert.deepEqual(names("groceries"), ["shopping-cart", "shopping-basket"]);
  assert.deepEqual(names("grocery"), ["shopping-cart", "shopping-basket"]);
  assert.deepEqual(names("pets"), ["paw-print"]);
  assert.deepEqual(names("savings"), ["piggy-bank"]);
});

test("normalizes whitespace, separators, case and Latin accents", () => {
  assert.deepEqual(names("  CREDIT   CARD  "), ["credit-card"]);
  assert.deepEqual(names("credit_card"), ["credit-card"]);
  assert.deepEqual(names("credit-card"), ["credit-card"]);
  assert.deepEqual(names("epicerie"), ["shopping-basket"]);
  assert.deepEqual(names("epargne"), ["piggy-bank"]);
});

test("puts exact names ahead of incidental substrings and keyword matches", () => {
  assert.equal(names("car")[0], "car");
  const candidates = [
    { names: ["plane"], keywords: ["car"] },
    { names: ["credit-card"], keywords: [] },
    { names: ["car"], keywords: [] },
  ];
  assert.deepEqual(rankIcons(candidates, "car"), [candidates[2], candidates[1], candidates[0]]);
});

test("supports multiple words in any order without returning unrelated icons", () => {
  assert.deepEqual(names("card credit"), ["credit-card"]);
  assert.deepEqual(names("groceries animals"), []);
  assert.deepEqual(names("zzzz"), []);
  assert.deepEqual(names("\u0301"), []);
});

test("preserves original ordering on ties and restores all icons on clearing", () => {
  assert.deepEqual(names("shopping"), ["shopping-cart", "shopping-basket"]);
  assert.deepEqual(rankIcons(icons, " \t "), icons);
});

test("preserves non-Latin marks and supports scripts without word spaces", () => {
  assert.equal(normalizeIconQuery("ば"), "ば");
  assert.notEqual(normalizeIconQuery("ば"), normalizeIconQuery("は"));
  assert.equal(normalizeIconQuery("عَرَبِيّ"), "عَرَبِيّ");
  const localized = [{ names: ["plane", "飛行機"], keywords: ["旅行"] }];
  assert.deepEqual(rankIcons(localized, "飛行"), localized);
  assert.deepEqual(rankIcons(localized, "旅行"), localized);
});

// Exercise the actual controller without a browser or a second matching implementation.
const controllerSource = (
  await readFile(
    new URL("../../../app/javascript/controllers/icon_picker_controller.js", import.meta.url),
    "utf8",
  )
)
  .replace('import { Controller } from "@hotwired/stimulus";', "class Controller {}")
  .replace('"utils/icon_search"', JSON.stringify(searchUrl));
const { default: IconPickerController } = await import(
  `data:text/javascript;base64,${Buffer.from(controllerSource).toString("base64")}`
);

function picker() {
  let focused;
  let clicked;
  const details = { open: false };
  const order = [];
  const controller = new IconPickerController();
  controller.element = { closest: () => details };
  controller.inputTarget = { value: "", focus: () => { focused = "search"; } };
  controller.listTarget = { append: (element) => { order.push(element); }, scrollTop: 100 };
  controller.emptyMessageTarget = {
    classList: { toggle: (_name, hidden) => { controller.emptyHidden = hidden; } },
  };
  controller.itemTargets = icons.map((icon) => {
    const radio = {
      type: "radio",
      focus: () => { focused = icon.names[0]; },
      click: () => { clicked = icon.names[0]; },
    };
    return {
      dataset: { iconPickerNames: JSON.stringify(icon.names), iconPickerKeywords: JSON.stringify(icon.keywords) },
      querySelector: () => radio,
      click: () => radio.click(),
    };
  });
  controller.connect();
  return { controller, details, order, focused: () => focused, clicked: () => clicked };
}

function key(controller, key, target = controller.inputTarget, isComposing = false) {
  const event = { key, target, isComposing, prevented: false, preventDefault() { this.prevented = true; } };
  controller.handleKeydown(event);
  return event;
}

test("filters, reorders results, shows the empty state and resets on close", () => {
  const { controller, details, order } = picker();
  controller.inputTarget.value = "car";
  controller.filter();
  assert.equal(controller.results[0].names[0], "car");
  assert.equal(order.at(-controller.results.length), controller.results[0].element);
  assert.equal(controller.itemTargets[3].hidden, true);
  assert.equal(controller.listTarget.scrollTop, 0);
  controller.inputTarget.value = "zzzz";
  controller.filter();
  assert.equal(controller.emptyHidden, false);
  controller.resetOnClose({ target: {} });
  assert.equal(controller.inputTarget.value, "zzzz");
  controller.resetOnClose({ target: details });
  assert.equal(controller.inputTarget.value, "");
  assert.equal(controller.emptyHidden, true);
  assert.ok(controller.itemTargets.every((item) => !item.hidden));
  assert.deepEqual(order.slice(-icons.length), controller.itemTargets);
});

test("focuses search on opening and supports arrow and Enter selection", () => {
  const { controller, details, focused, clicked } = picker();
  details.open = true;
  controller.resetOnClose({ target: details });
  assert.equal(focused(), "search");
  controller.inputTarget.value = "car";
  controller.filter();
  assert.equal(key(controller, "ArrowDown").prevented, true);
  assert.equal(focused(), "car");
  assert.equal(key(controller, "Enter").prevented, true);
  assert.equal(clicked(), "car");
  const radio = controller.itemTargets[0].querySelector("input");
  assert.equal(key(controller, "Enter", radio).prevented, true);
  assert.equal(clicked(), "credit-card");
});

test("never submits on Enter with no results and leaves IME composition alone", () => {
  const { controller, clicked } = picker();
  controller.inputTarget.value = "zzzz";
  controller.filter();
  assert.equal(key(controller, "Enter").prevented, true);
  assert.equal(clicked(), undefined);
  assert.equal(key(controller, "Enter", controller.inputTarget, true).prevented, false);
});
