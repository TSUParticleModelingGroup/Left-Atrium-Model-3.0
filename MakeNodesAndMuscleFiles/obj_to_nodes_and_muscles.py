import os
import sys

"""
This script converts a Wavefront OBJ mesh file to simulation Nodes and Muscles files.
It extracts unique vertices and edges from the OBJ file and writes them in the format
expected by the simulation. Usage:
    python obj_to_nodes_and_muscles.py <input.obj> [output_nodes] [output_muscles] [--min-degree MIN_DEG]
    
    MIN_DEG: Remove vertices with degree <= MIN_DEG (default: 2, set to 0 to skip)
             Useful after MeshLab cleanup to remove remaining dead-ends.
"""

def parse_obj(obj_path):
    """
    Reads an OBJ file and extracts:
      - Vertices (v lines)
      - Edges (from faces, f lines)
    Returns:
      - List of (x, y, z) tuples for each vertex
      - List of (a, b) tuples for each unique edge
    """
    vertices = []
    edges = set()
    with open(obj_path, 'r') as f:
        for line in f:
            if line.startswith('v '):
                # Parse vertex coordinates
                parts = line.strip().split()
                x, y, z = map(float, parts[1:4])
                vertices.append((x, y, z))
            elif line.startswith('f '):
                # Parse face indices and convert to edges
                parts = line.strip().split()[1:]
                idxs = [int(p.split('/')[0]) - 1 for p in parts]
                for i in range(len(idxs)):
                    a, b = idxs[i], idxs[(i+1)%len(idxs)]
                    edge = tuple(sorted((a, b)))
                    edges.add(edge)
    return vertices, sorted(edges)

def remove_low_degree_vertices(vertices, edges, min_degree):
    """
    Removes vertices with degree <= min_degree (dead-ends, whiskers, isolated nodes).
    Returns:
      - List of vertices with degree > min_degree
      - List of edges with updated indices
      - Count of removed vertices
    """
    n = len(vertices)
    # Count connections (degree) for each vertex
    degree = [0] * n
    for a, b in edges:
        degree[a] += 1
        degree[b] += 1
    
    # Keep only vertices with degree > min_degree
    kept = [degree[i] > min_degree for i in range(n)]
    
    # Build mapping from old to new indices
    old_to_new = {}
    new_idx = 0
    for i in range(n):
        if kept[i]:
            old_to_new[i] = new_idx
            new_idx += 1
    
    # Rebuild vertices list
    new_vertices = [vertices[i] for i in range(n) if kept[i]]
    
    # Update edges, removing any that connect to removed vertices
    new_edges = set()
    for a, b in edges:
        if kept[a] and kept[b]:
            new_a = old_to_new[a]
            new_b = old_to_new[b]
            edge = tuple(sorted((new_a, new_b)))
            new_edges.add(edge)
    
    removed_count = n - len(new_vertices)
    return new_vertices, sorted(new_edges), removed_count

def remove_small_components(vertices, edges, min_size):
    """
    Remove connected components smaller than min_size, but always keep the largest component.
    Returns new_vertices, new_edges, removed_component_count, removed_vertex_count
    """
    n = len(vertices)
    if n == 0:
        return vertices, edges, 0, 0

    # Build adjacency
    adj = [[] for _ in range(n)]
    for a, b in edges:
        if 0 <= a < n and 0 <= b < n:
            adj[a].append(b)
            adj[b].append(a)

    visited = [False] * n
    components = []
    for i in range(n):
        if not visited[i]:
            stack = [i]
            visited[i] = True
            comp = []
            while stack:
                u = stack.pop()
                comp.append(u)
                for v in adj[u]:
                    if not visited[v]:
                        visited[v] = True
                        stack.append(v)
            components.append(comp)

    # Identify largest component index
    comp_sizes = [len(c) for c in components]
    largest_idx = max(range(len(components)), key=lambda i: comp_sizes[i])

    # Decide which components to keep
    keep = [False] * len(components)
    for idx, comp in enumerate(components):
        if idx == largest_idx or len(comp) >= min_size:
            keep[idx] = True

    # Build set of kept node indices
    kept_nodes = set()
    for idx, comp in enumerate(components):
        if keep[idx]:
            kept_nodes.update(comp)

    # If nothing kept (defensive), keep largest
    if not kept_nodes:
        kept_nodes.update(components[largest_idx])

    # Build mapping old->new
    old_to_new = {}
    new_idx = 0
    for i in range(n):
        if i in kept_nodes:
            old_to_new[i] = new_idx
            new_idx += 1

    new_vertices = [vertices[i] for i in range(n) if i in kept_nodes]

    new_edges = set()
    for a, b in edges:
        if a in kept_nodes and b in kept_nodes:
            new_edges.add(tuple(sorted((old_to_new[a], old_to_new[b]))))

    removed_comp_count = sum(1 for k in keep if not k)
    removed_vertex_count = n - len(new_vertices)
    return new_vertices, sorted(new_edges), removed_comp_count, removed_vertex_count

def write_nodes(vertices, out_path):
    """
    Writes the Nodes file with header and node data:
      <count>\n<pulse>\n<up>\n<front>\n
      <id> <type> <x> <y> <z>\n
    All nodes are assigned type 0 by default.
    """
    with open(out_path, 'w') as f:
        f.write(f"{len(vertices)}\n0\n0\n1\n")
        for idx, (x, y, z) in enumerate(vertices):
            f.write(f"{idx} 0 {x:.6f} {y:.6f} {z:.6f}\n")

def write_muscles(edges, out_path):
    """
    Writes the Muscles file with header and edge data:
      <count>\n
            <id> <type> <nodeA> <nodeB>\n
    """
    with open(out_path, 'w') as f:
        f.write(f"{len(edges)}\n")
        for idx, (a, b) in enumerate(edges):
                        f.write(f"{idx} 0 {a} {b}\n")

def main():
    # Simple usage: only input OBJ is required (cleanup done automatically)
    if len(sys.argv) != 2:
        print("Usage: python obj_to_nodes_and_muscles.py <input.obj>")
        sys.exit(1)

    obj_file = sys.argv[1]
    nodes_file = os.path.join(os.path.dirname(obj_file), "Nodes")
    muscles_file = os.path.join(os.path.dirname(obj_file), "Muscles")

    # Check OBJ file exists
    if not os.path.exists(obj_file):
        print(f"OBJ file '{obj_file}' not found.")
        sys.exit(1)

    # Parse OBJ
    vertices, edges = parse_obj(obj_file)
    original_vertex_count = len(vertices)
    original_edge_count = len(edges)

    # Remove small disconnected components (floating strings)
    # Heuristic: remove components smaller than min_component_size but always keep the largest component
    min_component_size = max(20, int(0.005 * original_vertex_count))
    vertices, edges, removed_comp_count, removed_vertex_count = remove_small_components(vertices, edges, min_component_size)
    if removed_comp_count > 0:
        print(f"Removed {removed_comp_count} small disconnected components, total {removed_vertex_count} vertices removed")

    print(f"  Before: {original_vertex_count} nodes, {original_edge_count} muscles")
    print(f"  After:  {len(vertices)} nodes, {len(edges)} muscles")

    write_nodes(vertices, nodes_file)
    write_muscles(edges, muscles_file)

    print(f"Wrote {len(vertices)} nodes to {nodes_file}")
    print(f"Wrote {len(edges)} muscles to {muscles_file}")

if __name__ == "__main__":
    main()
