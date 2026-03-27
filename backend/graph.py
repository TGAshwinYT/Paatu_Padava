from collections import deque
from typing import List, Dict, Any, Set

class MusicGraph:
    """
    A Graph data structure using an Adjacency List to connect songs
    based on shared artists or albums, powering the recommendation engine.
    """
    def __init__(self):
        # Store song metadata payloads: {song_id: song_dict}
        self.nodes: Dict[str, Dict[str, Any]] = {}
        # Adjacency list for connections: {song_id: {neighbor_id1, neighbor_id2}}
        self.adjacency_list: Dict[str, Set[str]] = {}

    def add_song(self, song_dict: Dict[str, Any]):
        """
        Adds a song node to the graph if it doesn't already exist.
        """
        song_id = song_dict.get('id')
        if not song_id:
            return

        if song_id not in self.nodes:
            self.nodes[song_id] = song_dict
            self.adjacency_list[song_id] = set()

    def add_connection(self, song_id_1: str, song_id_2: str):
        """
        Creates an undirected connection between two songs.
        """
        if song_id_1 in self.adjacency_list and song_id_2 in self.adjacency_list:
            self.adjacency_list[song_id_1].add(song_id_2)
            self.adjacency_list[song_id_2].add(song_id_1)

    def get_recommendations(self, target_song_id: str, limit: int = 5) -> List[Dict[str, Any]]:
        """
        Uses Breadth-First Search (BFS) to find the nearest related songs.
        Traversal starts from the target song and explores neighbors layer by layer.
        """
        # Ensure the target song exists in our graph
        if target_song_id not in self.adjacency_list:
            return []

        recommendations = []
        visited = {target_song_id}
        # Initialize queue for BFS with the target song
        queue = deque([target_song_id])

        while queue and len(recommendations) < limit:
            current_id = queue.popleft()

            # Explore all neighbors of the current song
            for neighbor_id in self.adjacency_list.get(current_id, []):
                if neighbor_id not in visited:
                    visited.add(neighbor_id)
                    
                    # Add neighbor's metadata to our results (limit check again)
                    if neighbor_id in self.nodes:
                        recommendations.append(self.nodes[neighbor_id])
                        queue.append(neighbor_id)
                        
                        if len(recommendations) >= limit:
                            break
                            
        return recommendations

# Global Recommendation Graph Instance
recommendation_graph = MusicGraph()
