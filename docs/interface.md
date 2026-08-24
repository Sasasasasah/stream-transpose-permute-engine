# Stream Transpose and Permutation Interface Notes

Each slice accepts independent Transpose and Permute commands. The stream read
side is expressed as four tile-local groups of 16 six-bit selectors, matching
four independently active pipeline stages. A selector encodes one direction bit
and one five-bit stream index.

Successful Transpose capture consumes all 16 selected segments for its tile.
Permute emits a 4x16 producer-valid matrix, 16 destination selectors, and a
matching 4x16 matrix of 64-bit data segments.

The slice rejects unsupported command encodings without adding a retry or
backpressure state. Collision detection and physical stream-fabric adaptation
are outside this standalone implementation.
