// Fold Latin accents while preserving meaningful marks in scripts such as kana.
export function normalizeIconQuery(value) {
  return value
    .normalize("NFD")
    .replace(/(\p{Script=Latin})\p{Mark}+/gu, "$1")
    .normalize("NFC")
    .toLowerCase()
    .replace(/[-_\s]+/g, " ")
    .trim();
}

function fieldScore(field, query) {
  if (field === query) return 0;
  const words = field.split(" ");
  const terms = query.split(" ");
  if (terms.every((term) => words.includes(term))) return 1;
  if (terms.every((term) => words.some((word) => word.startsWith(term)))) {
    return 2;
  }
  if (terms.every((term) => field.includes(term))) return 3;
  return Number.POSITIVE_INFINITY;
}

// Stable sorting preserves the supplied icon order when relevance is equal.
export function rankIcons(icons, value) {
  const query = normalizeIconQuery(value);
  if (!query) return icons;

  return icons
    .map((icon) => ({
      icon,
      score: Math.min(
        ...icon.names.map((name) => fieldScore(normalizeIconQuery(name), query)),
        ...icon.keywords.map(
          (keyword) => fieldScore(normalizeIconQuery(keyword), query) + 4,
        ),
      ),
    }))
    .filter(({ score }) => Number.isFinite(score))
    .sort((a, b) => a.score - b.score)
    .map(({ icon }) => icon);
}
