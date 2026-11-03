// The first blank line separates the direct meaning from the explanation.
// Do not guess sentence boundaries or delete model wording if the format is absent.
export function splitAnswer(text: string) {
  const normalized = text.replace(/\r\n?/g, '\n').trim();
  const boundary = /\n[\t ]*\n/.exec(normalized);
  return boundary
    ? { meaning: normalized.slice(0, boundary.index), explanation: normalized.slice(boundary.index + boundary[0].length).trim(), separated: true }
    : { meaning: normalized, explanation: '', separated: false };
}
export function renderAnswer(container: HTMLElement, text: string, complete = false) {
  const parts = splitAnswer(text);
  const meaning = document.createElement('p');
  meaning.className = complete && !parts.separated ? 'answer-body' : 'answer-meaning';
  meaning.textContent = parts.meaning;
  container.replaceChildren(meaning);
  if (parts.explanation) {
    const explanation = document.createElement('p');
    explanation.className = 'answer-explanation';
    explanation.textContent = parts.explanation;
    container.append(explanation);
  }
}
