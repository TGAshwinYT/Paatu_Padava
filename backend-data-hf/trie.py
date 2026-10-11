import unicodedata
from typing import List, Dict, Any, Optional

class TrieNode:
    def __init__(self):
        self.children: Dict[str, TrieNode] = {}
        self.is_end_of_word: bool = False
        self.data: Optional[Dict[str, Any]] = None

class Trie:
    def __init__(self):
        self.root = TrieNode()

    @staticmethod
    def normalize_key(text: str) -> str:
        """
        Applies Unicode NFC normalization and lowercases text.
        Guarantees consistent prefix matching across mixed script,
        Tamil/Hindi combining characters, and transliterated search queries.
        """
        if not text:
            return ""
        return unicodedata.normalize("NFC", text).strip().lower()

    def insert(self, word: str, data: Optional[Dict[str, Any]] = None):
        """
        Inserts a word into the trie with associated data using Unicode NFC normalization.
        """
        if not word:
            return
        if data is None:
            data = {"name": word, "title": word, "type": "artist"}
        normalized = self.normalize_key(word)
        node = self.root
        for char in normalized:
            if char not in node.children:
                node.children[char] = TrieNode()
            node = node.children[char]
        node.is_end_of_word = True
        node.data = data

    def search_prefix(self, prefix: str, limit: int = 5) -> List[Dict[str, Any]]:
        """
        Searches for all words matching the prefix and returns up to 'limit' data payloads
        using Unicode NFC normalization.
        """
        if not prefix:
            return []
        normalized = self.normalize_key(prefix)
        node = self.root
        for char in normalized:
            if char not in node.children:
                return []
            node = node.children[char]
        
        results = []
        self._dfs(node, results, limit)
        return results

    def _dfs(self, node: TrieNode, results: List[Dict[str, Any]], limit: int):
        """
        Helper DFS to find all data payloads starting from a given node.
        """
        if len(results) >= limit:
            return

        if node.is_end_of_word and node.data is not None:
            results.append(node.data)

        # Sort children keys to have deterministic results
        for char in sorted(node.children.keys()):
            if len(results) >= limit:
                break
            self._dfs(node.children[char], results, limit)
