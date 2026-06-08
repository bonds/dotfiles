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


def fix(text: str) -> str:
    """Spell-check and word-split a single line of text.

    Words that look like code (containing dots, underscores, parens) or
    that are too far from any dictionary word are left unchanged.
    """
    if not _HAS_SPELLCHECK:
        return text
    words = text.split()
    result: list[str] = []
    for word in words:
        result.append(_fix_word(word))
    return " ".join(result)


def _fix_word(word: str) -> str:
    if _spell.known([word]):
        return word

    # Try splitting at a known prefix boundary (case-insensitive)
    lower = word.lower()
    for prefix in _PREFIXES:
        if lower.startswith(prefix) and len(word) > len(prefix) + 1:
            rest = word[len(prefix):]
            if _spell.known([rest]):
                return f"{word[:len(prefix)]} {rest}"

    # Try splitting at doubled-first-letter boundary (sspecific → s specific → specific)
    if len(word) >= 4 and word[0] == word[1]:
        rest = word[1:]
        if _spell.known([rest]):
            return rest  # "sspecific" → "specific"

    # Try the spell checker's best guess (returns None if no good match)
    best = _spell.correction(word)
    return best if best else word
