from typing import List, Dict, Any, Optional

class TrieNode:
    def __init__(self):
        self.children: Dict[str, TrieNode] = {}
        self.is_end_of_word: bool = False
        self.data: Optional[Dict[str, Any]] = None

class Trie:
    def __init__(self):
        self.root = TrieNode()

    def insert(self, word: str, data: Dict[str, Any]):
        """
        Inserts a word into the trie with associated data.
        """
        node = self.root
        for char in word.lower():
            if char not in node.children:
                node.children[char] = TrieNode()
            node = node.children[char]
        node.is_end_of_word = True
        node.data = data

    def search_prefix(self, prefix: str, limit: int = 5) -> List[Dict[str, Any]]:
        """
        Searches for all words matching the prefix and returns up to 'limit' data payloads.
        """
        node = self.root
        for char in prefix.lower():
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
