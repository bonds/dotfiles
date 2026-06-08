"""Lightweight spell check and word-split for LLM output artifacts."""

import re

try:
    from spellchecker import SpellChecker

    _spell = SpellChecker()
    _HAS_SPELLCHECK = True
except ImportError:
    _HAS_SPELLCHECK = False

# Common short words that often get merged with the next word
_PREFIXES = {
    "is", "it", "in", "on", "at", "of", "to", "by", "as", "an",
    "the", "and", "for", "but", "not", "was", "are", "had", "has",
    "his", "her", "its", "our", "out", "all", "can", "may", "this",
    "that", "with", "from", "have", "been", "were", "some", "than",
    "what", "when", "then", "them", "they", "their", "which",
}


_CODE_RE = re.compile(r"[a-zA-Z_][a-zA-Z0-9_]*\b")


def _is_code(word: str) -> bool:
    """Skip words that look like code identifiers (camelCase, snake_case, dotted.paths)."""
    return bool(re.search(r"[._()\[\]{}<>]|^[a-z]+[A-Z]", word))


def fix(text: str) -> str:
    """Spell-check and word-split a single line of text."""
    if not _HAS_SPELLCHECK:
        return text
    words = text.split()
    result: list[str] = []
    for word in words:
        if _is_code(word):
            result.append(word)
        else:
            result.append(_fix_word(word))
    return " ".join(result)


def _fix_word(word: str) -> str:
    if _spell.known([word]):
        return word

    # Try splitting at a known prefix boundary
    for prefix in _PREFIXES:
        if word.startswith(prefix) and len(word) > len(prefix) + 1:
            rest = word[len(prefix):]
            if _spell.known([rest]):
                return f"{prefix} {rest}"

    # Try splitting at doubled-first-letter boundary (sspecific → s specific → specific)
    if len(word) >= 4 and word[0] == word[1]:
        rest = word[1:]
        if _spell.known([rest]):
            return rest  # "sspecific" → "specific"

    # Try the spell checker's best guess
    candidates = _spell.candidates(word)
    if candidates:
        return _spell.correction(word)

    return word
